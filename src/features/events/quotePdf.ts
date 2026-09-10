/**
 * ציור מסמך הצעת המחיר (0169).
 *
 * **למה pdf-lib ולא הדפסת הדפדפן.** שלושת מסכי הדוחות מייצאים PDF דרך
 * `window.print()`, ואפס תלויות הוא יתרון אמיתי — אבל דיאלוג ההדפסה אינו
 * מחזיר קובץ. המסמך הזה נשלח בוואטסאפ, כלומר הוא חייב להיות `File` בזיכרון,
 * ולכן הוא נבנה כאן.
 *
 * **ולמה לא html2canvas.** טיילווינד v4 פולט צבעי `oklch()` שהספרייה אינה
 * יודעת לפרש, והפלט שלה הוא תמונה: מטושטשת בהגדלה, כבדה פי עשרה, ובלי
 * טקסט שאפשר לחפש או להעתיק. מסמך מסחרי שיושב אצל לקוח קצה אינו צילום מסך.
 *
 * **המחיר של הבחירה הוא שני דברים שהדפדפן היה נותן בחינם:**
 *   1. **פונט.** אין ב-PDF פונט עברי מובנה, ולכן Heebo מוטמע מ-`public/fonts`
 *      (‏SIL OFL, שני משקלים, ‎44KB כל אחד).
 *   2. **סדר דו-כיווני.** ‏pdf-lib *כבר* מהפך עברית — fontkit עושה זאת בשמו —
 *      ובכך מהפך גם את הספרות שלצדה. כל שורה נחתכת ל**רצפים** ב-
 *      `lib/bidiText.ts` וכל רצף מצויר במיקומו.
 *
 * הקובץ כולו נטען עצלנית — `await import('./quotePdf')` — כמו exceljs.
 */
import { loadBidi, visualRuns } from '../../lib/bidiText'
import type { CompanyDetails } from '../../types/domain'
import type { QuoteLine, QuoteTotals } from './quote'
import { quoteFooterText } from './quote'

export interface QuoteLogo {
  bytes: Uint8Array
  /** ‏pdf-lib מטמיע PNG ו-JPEG בלבד; SVG אינו נתמך, ולכן גם הדלי חוסם אותו. */
  kind: 'png' | 'jpg'
}

export interface QuoteDocModel {
  documentNumber: string
  issuedAt: Date
  company: CompanyDetails
  logo: QuoteLogo | null
  customerName: string
  endClientName: string | null
  contactName: string | null
  contactPhone: string | null
  /** ‏YYYY-MM-DD */
  eventDate: string
  eventLocation: string | null
  lines: QuoteLine[]
  totals: QuoteTotals
  /** מודפס על שורת המע״מ. נמסר ואינו נגזר מהסכומים — הצעה על 0 ₪ עדיין
      צריכה לומר לפי איזה שיעור היא חושבה. */
  vatPct: number
  fixedNote: string
  notes: string | null
  paymentTerms: string | null
}

const PAGE_W = 595.28
const PAGE_H = 841.89
const M = 42
/** מתחת לזה מתחיל עמוד חדש: מקום לשורה, לקו ולכותרת התחתונה. */
const BOTTOM = 88

const INK = [0.08, 0.09, 0.11] as const
const MUTED = [0.42, 0.45, 0.5] as const
const LINE = [0.84, 0.86, 0.89] as const
const HEAD_BG = [0.96, 0.965, 0.975] as const
const ACCENT = [0.525, 0.231, 1] as const

/** עמודות הטבלה, כקצה **ימני** של כל אחת. המסמך עברי, ולכן ימין הוא ההתחלה. */
const COL_DESC_RIGHT = PAGE_W - M
const COL_WHEN_RIGHT = M + 208
const COL_AMOUNT_RIGHT = M + 92
const DESC_WIDTH = COL_DESC_RIGHT - COL_WHEN_RIGHT - 12

let fontsPromise: Promise<[ArrayBuffer, ArrayBuffer]> | null = null

/**
 * שני המשקלים, פעם אחת לכל חיי הלשונית.
 *
 * ‏`BASE_URL` ולא נתיב מוחלט: אפליקציה שתוגש מתת-נתיב עדיין תמצא אותם.
 */
function loadFonts(): Promise<[ArrayBuffer, ArrayBuffer]> {
  if (!fontsPromise) {
    const base = import.meta.env.BASE_URL || '/'
    fontsPromise = Promise.all([
      fetch(`${base}fonts/heebo-400.ttf`).then((r) => {
        if (!r.ok) throw new Error('font')
        return r.arrayBuffer()
      }),
      fetch(`${base}fonts/heebo-700.ttf`).then((r) => {
        if (!r.ok) throw new Error('font')
        return r.arrayBuffer()
      }),
    ]).catch((e) => {
      // מטמון שמחזיק כישלון היה נועל את המסך עד רענון.
      fontsPromise = null
      throw e
    })
  }
  return fontsPromise
}

/** ‏1,180.00 ₪ — מסמך מסחרי מציג אגורות גם כשהן אפס. */
function money(n: number): string {
  const abs = Math.abs(n).toLocaleString('he-IL', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
  return `${n < 0 ? '-' : ''}${abs} ₪`
}

/** ‏YYYY-MM-DD → DD/MM/YYYY, בלי `Date` ובלי אזור זמן שמזיז יום. */
function isoToHe(iso: string): string {
  const [y, m, d] = (iso || '').split('-')
  return y && m && d ? `${d}/${m}/${y}` : ''
}

/**
 * תאריך מקומי, ולא `toISOString().slice(0, 10)`.
 *
 * ישראל מקדימה את UTC, ולכן הפקה ב-00:30 מקומי היא אתמול ב-UTC — ותאריך
 * המסמך היה יוצא יום אחורה בדיוק בשעות שבהן איש אינו בודק.
 */
function localDate(d: Date): string {
  return `${two(d.getDate())}/${two(d.getMonth() + 1)}/${d.getFullYear()}`
}

function two(n: number): string {
  return n < 10 ? `0${n}` : String(n)
}

/**
 * גלישת שורות על המחרוזת ה**לוגית**.
 *
 * הסדר הוויזואלי נקבע פר-שורה ואחריה: לגלוש על מחרוזת שכבר הפכה היה חותך
 * מילים באמצע ומפזר את חלקיהן בין שתי שורות.
 */
function wrapLogical(
  text: string,
  maxWidth: number,
  size: number,
  widthOf: (s: string, size: number) => number,
): string[] {
  const words = String(text ?? '').split(/\s+/).filter(Boolean)
  if (!words.length) return []
  const out: string[] = []
  let line = words[0]
  for (const w of words.slice(1)) {
    const next = `${line} ${w}`
    if (widthOf(next, size) <= maxWidth) line = next
    else {
      out.push(line)
      line = w
    }
  }
  out.push(line)
  return out
}

/**
 * ‏`Uint8Array<ArrayBuffer>` ולא `Uint8Array` סתם: ‏pdf-lib מחזיר
 * `ArrayBufferLike`, ש-`Blob` ו-`File` אינם מקבלים (הם פוסלים
 * `SharedArrayBuffer`). ההעתקה בסוף היא מה שמצמצם את הטיפוס, והיא
 * הרבה יותר כנה מ-cast בכל אתר קריאה.
 */
export async function generateQuotePdf(doc: QuoteDocModel): Promise<Uint8Array<ArrayBuffer>> {
  const [{ PDFDocument, rgb }, fontkitMod, fonts] = await Promise.all([
    import('pdf-lib'),
    import('@pdf-lib/fontkit'),
    loadFonts(),
    loadBidi(),
  ])

  const pdf = await PDFDocument.create()
  pdf.registerFontkit(fontkitMod.default)
  const regular = await pdf.embedFont(fonts[0], { subset: true })
  const bold = await pdf.embedFont(fonts[1], { subset: true })

  pdf.setTitle(`מסמך הצעת מחיר ${doc.documentNumber}`)
  pdf.setProducer(doc.company.name || 'ViperLogistics')
  pdf.setCreationDate(doc.issuedAt)


  const widthOf = (s: string, size: number) =>
    visualRuns(s).reduce((w, r) => w + regular.widthOfTextAtSize(r.text, size), 0)

  const pages: import('pdf-lib').PDFPage[] = []
  const newPage = () => {
    const p = pdf.addPage([PAGE_W, PAGE_H])
    pages.push(p)
    return p
  }

  let page = newPage()
  let y = PAGE_H - M

  type TextOpts = { size?: number; bold?: boolean; color?: readonly number[] }

  /** רוחב השורה כפי שהיא באמת תצויר — סכום רוחבי הרצפים. */
  const measure = (text: string, size: number, isBold = false) => {
    const font = isBold ? bold : regular
    return visualRuns(text).reduce((w, r) => w + font.widthOfTextAtSize(r.text, size), 0)
  }

  /** ציור מיושר לשמאל: רצף אחרי רצף, כל אחד במיקום שהצטבר לפניו. */
  const left = (text: string, xLeft: number, yy: number, o: TextOpts = {}) => {
    const size = o.size ?? 10
    const font = o.bold ? bold : regular
    const c = o.color ?? INK
    let x = xLeft
    for (const run of visualRuns(text)) {
      page.drawText(run.text, { x, y: yy, size, font, color: rgb(c[0], c[1], c[2]) })
      x += font.widthOfTextAtSize(run.text, size)
    }
  }

  /** ציור מיושר לימין — ברירת המחדל של מסמך עברי. */
  const right = (text: string, xRight: number, yy: number, o: TextOpts = {}) => {
    left(text, xRight - measure(text, o.size ?? 10, o.bold), yy, o)
  }
  const rule = (yy: number, color: readonly number[] = LINE) =>
    page.drawLine({
      start: { x: M, y: yy },
      end: { x: PAGE_W - M, y: yy },
      thickness: 0.7,
      color: rgb(color[0], color[1], color[2]),
    })

  // ===== כותרת: הלוגו ופרטי החברה מימין, זהות המסמך משמאל =====
  // הקומה של הכותרת היא מה שהבלוק השמאלי דורש: שורתו האחרונה יושבת
  // ב-‎-45, ולכן הקו המפריד אינו יכול לעלות מעל ‎-58 גם כשמימין אין דבר.
  const HEADER_FLOOR = PAGE_H - M - 58
  if (doc.logo) {
    try {
      const img =
        doc.logo.kind === 'png'
          ? await pdf.embedPng(doc.logo.bytes)
          : await pdf.embedJpg(doc.logo.bytes)
      const box = 64
      const scale = Math.min(box / img.width, box / img.height)
      const w = img.width * scale
      const h = img.height * scale
      page.drawImage(img, { x: PAGE_W - M - w, y: y - h, width: w, height: h })
      // פרטי החברה יורדים מתחת ללוגו, ולא לצדו: שם חברה ארוך היה נדחס.
      y -= h + 10
    } catch {
      // לוגו פגום אינו עוצר מסמך. הכותרת נופלת חזרה לשם החברה בלבד.
    }
  }

  right(doc.company.name, PAGE_W - M, y - 14, { size: 15, bold: true })
  const companyLines = [
    doc.company.tax_id ? `ח.פ ${doc.company.tax_id}` : '',
    doc.company.phone ? `טלפון ${doc.company.phone}` : '',
    doc.company.email,
  ].filter(Boolean)
  let cy = y - 30
  for (const l of companyLines) {
    right(l, PAGE_W - M, cy, { size: 9, color: MUTED })
    cy -= 13
  }
  const headerBottom = Math.min(HEADER_FLOOR, cy)

  left('מסמך הצעת מחיר', M, PAGE_H - M - 14, { size: 15, bold: true, color: ACCENT })
  left(`מספר מסמך: ${doc.documentNumber}`, M, PAGE_H - M - 32, { size: 9, color: MUTED })
  left(`תאריך: ${localDate(doc.issuedAt)}`, M, PAGE_H - M - 45, { size: 9, color: MUTED })

  y = headerBottom
  rule(y)
  y -= 24

  // ===== לכבוד: לקוח הקצה, ולא הלקוח שבמערכת =====
  right('לכבוד', PAGE_W - M, y, { size: 9, color: MUTED })
  y -= 16
  right(doc.endClientName || '—', PAGE_W - M, y, { size: 13, bold: true })
  y -= 16
  if (doc.contactName || doc.contactPhone) {
    const via = ['באמצעות', doc.contactName, doc.contactPhone].filter(Boolean).join(' · ')
    right(via, PAGE_W - M, y, { size: 9.5, color: MUTED })
    y -= 16
  }

  y -= 6
  const meta = [
    ['תאריך אירוע', isoToHe(doc.eventDate)],
    ['מיקום אירוע', doc.eventLocation || '—'],
  ] as const
  for (const [label, value] of meta) {
    right(`${label}:`, PAGE_W - M, y, { size: 9.5, color: MUTED })
    right(value, PAGE_W - M - 74, y, { size: 9.5 })
    y -= 15
  }

  y -= 12

  // ===== טבלת השורות =====
  const tableHeader = () => {
    page.drawRectangle({
      x: M,
      y: y - 6,
      width: PAGE_W - 2 * M,
      height: 22,
      color: rgb(HEAD_BG[0], HEAD_BG[1], HEAD_BG[2]),
    })
    right('תיאור', COL_DESC_RIGHT - 8, y, { size: 9, bold: true, color: MUTED })
    right('תאריך ושעה', COL_WHEN_RIGHT, y, { size: 9, bold: true, color: MUTED })
    right('מחיר', COL_AMOUNT_RIGHT, y, { size: 9, bold: true, color: MUTED })
    y -= 26
  }
  tableHeader()

  for (const line of doc.lines) {
    const isAddon = line.kind === 'addon'
    const indent = isAddon ? 14 : 0
    const wrapped = wrapLogical(line.label, DESC_WIDTH - indent, 10, widthOf)
    const rowHeight = Math.max(wrapped.length, 1) * 13 + 7

    if (y - rowHeight < BOTTOM) {
      page = newPage()
      y = PAGE_H - M
      tableHeader()
    }

    // סימן התוספת מצויר ואינו תו: תבליט בתחילת מחרוזת עברית הוא תו ניטרלי,
    // ו-UAX#9 מציב אותו בקצה שאינו בהכרח הקצה שבו מתחילים לקרוא.
    if (isAddon) {
      page.drawCircle({
        x: COL_DESC_RIGHT - 11,
        y: y + 3.5,
        size: 1.6,
        color: rgb(MUTED[0], MUTED[1], MUTED[2]),
      })
    }

    let ly = y
    for (const w of wrapped.length ? wrapped : ['—']) {
      right(w, COL_DESC_RIGHT - 8 - indent, ly, {
        size: 10,
        color: isAddon ? MUTED : INK,
      })
      ly -= 13
    }
    if (line.whenText) right(line.whenText, COL_WHEN_RIGHT, y, { size: 9.5, color: MUTED })
    right(money(line.amount), COL_AMOUNT_RIGHT, y, { size: 10, bold: !isAddon })

    y = ly - 7
    rule(y + 4)
  }

  // ===== הסיכום =====
  const summaryHeight = 74
  if (y - summaryHeight < BOTTOM) {
    page = newPage()
    y = PAGE_H - M
  }
  y -= 10
  const sum = [
    ['סכום ביניים', money(doc.totals.subtotal), false],
    [`מע״מ ${doc.vatPct}%`, money(doc.totals.vatAmount), false],
    ['סה״כ לתשלום', money(doc.totals.total), true],
  ] as const
  for (const [label, value, strong] of sum) {
    if (strong) {
      rule(y + 14)
      y -= 4
    }
    right(label, COL_WHEN_RIGHT, y, { size: strong ? 11 : 10, bold: strong, color: strong ? INK : MUTED })
    right(value, COL_AMOUNT_RIGHT, y, { size: strong ? 11 : 10, bold: strong })
    y -= 17
  }

  // ===== הערות ותנאי תשלום =====
  const blocks: [string, string][] = [['הערות', [doc.fixedNote, doc.notes].filter(Boolean).join('\n')]]
  if (doc.paymentTerms) blocks.push(['תנאי תשלום', doc.paymentTerms])

  for (const [title, body] of blocks) {
    if (!body) continue
    y -= 16
    if (y < BOTTOM + 40) {
      page = newPage()
      y = PAGE_H - M
    }
    right(title, PAGE_W - M, y, { size: 9, bold: true, color: MUTED })
    y -= 15
    for (const paragraph of body.split('\n')) {
      for (const w of wrapLogical(paragraph, PAGE_W - 2 * M, 9.5, widthOf)) {
        if (y < BOTTOM) {
          page = newPage()
          y = PAGE_H - M
        }
        right(w, PAGE_W - M, y, { size: 9.5 })
        y -= 13
      }
    }
  }

  // ===== כותרת תחתונה, אחרי שידוע כמה עמודים יש =====
  const footer = quoteFooterText(doc.company.quote_footer || 'מסמך זה נוצר', doc.issuedAt)
  const current = page
  for (const [i, p] of pages.entries()) {
    page = p
    p.drawLine({
      start: { x: M, y: 56 },
      end: { x: PAGE_W - M, y: 56 },
      thickness: 0.7,
      color: rgb(LINE[0], LINE[1], LINE[2]),
    })
    right(footer, PAGE_W - M, 42, { size: 8, color: MUTED })
    if (pages.length > 1) left(`עמוד ${i + 1} מתוך ${pages.length}`, M, 42, { size: 8, color: MUTED })
  }
  page = current

  return new Uint8Array(await pdf.save())
}
