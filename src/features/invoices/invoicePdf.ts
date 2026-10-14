/**
 * כל חשבונית נשמרת כ-PDF אחד (0233 §2). קובץ PDF עולה כמו שהוא (אחרי בדיקה
 * שהוא נפתח ואינו מוגן בסיסמה); צילום או תמונה מוקטנים ל-2400 פיקסלים בצד
 * הארוך, נדחסים ל-JPEG ונעטפים בעמוד PDF בגודל התמונה. הקטנה דרך canvas גם
 * מיישרת תמונה שצולמה לרוחב (EXIF), ופותחת HEIC בדפדפן שיודע לקרוא אותו.
 */
import { PDFDocument } from 'pdf-lib'

const MAX_SIDE = 2400
export const MAX_FILE_BYTES = 15 * 1024 * 1024

export class InvoiceFileError extends Error {}

export const isPdf = (f: File) => f.type === 'application/pdf' || /\.pdf$/i.test(f.name)
export const isImage = (f: File) => f.type.startsWith('image/') || /\.(jpe?g|png|heic|heif|webp)$/i.test(f.name)

async function checkPdf(bytes: Uint8Array) {
  let doc: PDFDocument
  try {
    doc = await PDFDocument.load(bytes, { ignoreEncryption: true })
  } catch {
    throw new InvoiceFileError('הקובץ אינו PDF תקין')
  }
  if (doc.isEncrypted) throw new InvoiceFileError('הקובץ מוגן בסיסמה — יש לשמור אותו בלי סיסמה')
  if (doc.getPageCount() === 0) throw new InvoiceFileError('בקובץ אין עמודים')
}

async function imageToJpeg(file: File): Promise<{ bytes: Uint8Array; width: number; height: number }> {
  let bitmap: ImageBitmap
  try {
    bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' })
  } catch {
    throw new InvoiceFileError('הדפדפן לא הצליח לפתוח את התמונה')
  }
  const scale = Math.min(1, MAX_SIDE / Math.max(bitmap.width, bitmap.height))
  const width = Math.round(bitmap.width * scale)
  const height = Math.round(bitmap.height * scale)
  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new InvoiceFileError('הדפדפן לא הצליח לעבד את התמונה')
  ctx.fillStyle = '#fff'
  ctx.fillRect(0, 0, width, height)
  ctx.drawImage(bitmap, 0, 0, width, height)
  bitmap.close()
  const blob = await new Promise<Blob | null>((res) => canvas.toBlob(res, 'image/jpeg', 0.85))
  if (!blob) throw new InvoiceFileError('הדפדפן לא הצליח לעבד את התמונה')
  return { bytes: new Uint8Array(await blob.arrayBuffer()), width, height }
}

/** תמונות (כמה צילומים של אותה חשבונית) כ-PDF אחד, עמוד לכל תמונה. */
export async function imagesToPdf(files: readonly File[]): Promise<Uint8Array> {
  const doc = await PDFDocument.create()
  for (const f of files) {
    const { bytes, width, height } = await imageToJpeg(f)
    const img = await doc.embedJpg(bytes)
    // עמוד בגודל A4 בקירוב בצד הארוך; התמונה עצמה נשמרת ברזולוציה המלאה
    const s = 842 / Math.max(width, height)
    const page = doc.addPage([width * s, height * s])
    page.drawImage(img, { x: 0, y: 0, width: width * s, height: height * s })
  }
  return doc.save()
}

/** הקובץ שיעלה, כ-PDF. */
export async function toInvoicePdf(file: File): Promise<Uint8Array> {
  if (isPdf(file)) {
    if (file.size > MAX_FILE_BYTES) throw new InvoiceFileError('הקובץ גדול מ-15MB')
    const bytes = new Uint8Array(await file.arrayBuffer())
    await checkPdf(bytes)
    return bytes
  }
  if (isImage(file)) {
    const pdf = await imagesToPdf([file])
    if (pdf.length > MAX_FILE_BYTES) throw new InvoiceFileError('התמונה גדולה מדי')
    return pdf
  }
  throw new InvoiceFileError('רק PDF או תמונה')
}

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', bytes as BufferSource)
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

/** שם הקובץ שיישמר: אותו שם, עם ‎.pdf. */
export const pdfName = (name: string) => (/\.pdf$/i.test(name) ? name : `${name.replace(/\.[^.]+$/, '')}.pdf`)
