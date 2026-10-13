/**
 * פיצול ואיחוד של קבצי התלושים בדפדפן (0218 §1), ב-pdf-lib — אותה ספרייה של
 * הצעת המחיר. הקובץ של רואה החשבון מתפצל לעמוד לכל קובץ לפני ההעלאה, ותלוש
 * של כמה עמודים מתאחד בחזרה רק כשמישהו פותח אותו.
 */
import { PDFDocument } from 'pdf-lib'

export class PdfReadError extends Error {}

async function load(bytes: ArrayBuffer | Uint8Array): Promise<PDFDocument> {
  let doc: PDFDocument
  try {
    doc = await PDFDocument.load(bytes, { ignoreEncryption: true })
  } catch {
    throw new PdfReadError('הקובץ אינו PDF תקין')
  }
  // ‏ignoreEncryption טוען, אבל העמודים שיוצאים מקובץ מוצפן הם ריקים
  if (doc.isEncrypted) throw new PdfReadError('הקובץ מוגן בסיסמה — יש לבקש מרואה החשבון קובץ בלי סיסמה')
  return doc
}

/** כל עמוד כקובץ PDF משלו, לפי הסדר. */
export async function splitPages(bytes: ArrayBuffer | Uint8Array): Promise<Uint8Array[]> {
  const src = await load(bytes)
  const count = src.getPageCount()
  if (count === 0) throw new PdfReadError('בקובץ אין עמודים')
  const out: Uint8Array[] = []
  for (let i = 0; i < count; i++) {
    const doc = await PDFDocument.create()
    const [page] = await doc.copyPages(src, [i])
    doc.addPage(page)
    out.push(await doc.save())
  }
  return out
}

/** כמה קבצים לקובץ אחד, עמודיהם לפי הסדר. קובץ אחד חוזר כמו שהוא. */
export async function mergePdfs(parts: readonly Uint8Array[]): Promise<Uint8Array> {
  if (parts.length === 1) return parts[0]
  const doc = await PDFDocument.create()
  for (const part of parts) {
    const src = await load(part)
    const pages = await doc.copyPages(src, src.getPageIndices())
    for (const p of pages) doc.addPage(p)
  }
  return doc.save()
}
