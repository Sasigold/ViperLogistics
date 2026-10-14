/**
 * חשבוניות ספקים (0233) — הלוגיקה הטהורה של המסך: תוויות, חודשים, דגלים,
 * ושמות הקבצים בתיקייה שנשלחת לרואה החשבון. הסכומים והסיכומים מגיעים מהשרת
 * (`invoices_board`); כאן אין חישוב כסף — רק בדיקה שהסכומים שנקראו מתיישבים.
 */
import type { Invoice, InvoiceCategory, InvoiceDocType } from '../../types/domain'

export const INVOICE_BUCKET = 'invoices'

export const DOC_TYPE_LABELS: Record<InvoiceDocType, string> = {
  tax_invoice: 'חשבונית מס',
  tax_invoice_receipt: 'חשבונית מס/קבלה',
  receipt: 'קבלה',
  credit: 'חשבונית זיכוי',
  other: 'מסמך אחר',
}

export const CATEGORY_LABELS: Record<InvoiceCategory, string> = {
  subcontractors: 'כוח אדם וקבלני משנה',
  equipment: 'ציוד',
  vehicle: 'רכב',
  fuel: 'דלק',
  rent: 'שכירות',
  utilities: 'חשמל, מים וארנונה',
  communication: 'תקשורת',
  software: 'תוכנה ושירותי ענן',
  office: 'משרד',
  food: 'כיבוד ואוכל',
  professional: 'שירותים מקצועיים',
  marketing: 'פרסום ושיווק',
  insurance: 'ביטוח',
  travel: 'נסיעות',
  maintenance: 'תחזוקה וניקיון',
  other: 'אחר',
}

export const SOURCE_LABELS: Record<Invoice['source'], string> = {
  upload: 'הועלתה',
  camera: 'צולמה',
  gmail: 'Gmail',
}

const MONTHS = ['ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני', 'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר']

/** 'YYYY-MM-01' של החודש שבו `d` נמצא (לפי השעון המקומי). */
export function monthOf(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`
}

export function shiftMonth(period: string, by: number): string {
  const [y, m] = period.split('-').map(Number)
  const d = new Date(Date.UTC(y, m - 1 + by, 1))
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-01`
}

export function monthLabel(period: string): string {
  const [y, m] = period.split('-').map(Number)
  return `${MONTHS[m - 1]} ${y}`
}

/** 'YYYY-MM' — שם התיקייה */
export const monthKey = (period: string) => period.slice(0, 7)

export function fmtInvoiceDate(iso: string | null): string {
  if (!iso) return ''
  const [y, m, d] = iso.slice(0, 10).split('-')
  return `${d}/${m}/${y}`
}

export type InvoiceFlag = 'unread' | 'failed' | 'unreviewed' | 'mismatch' | 'duplicate' | 'no_total' | 'not_ours'

/**
 * מה ראוי לבדוק בחשבונית. `mismatch` — לפני מע"מ ועוד מע"מ אינו הסה"כ (בסטייה
 * של יותר משקל — עיגולים); `not_ours` — נקרא נמען, ואינו אף אחת מהחברות.
 */
export function invoiceFlags(i: Invoice, hasCompanies: boolean): InvoiceFlag[] {
  const out: InvoiceFlag[] = []
  if (i.read_status === 'failed' && !i.reviewed_at) out.push('failed')
  else if (i.read_status === 'pending' && !i.reviewed_at) out.push('unread')
  if (!i.reviewed_at && i.read_status === 'done') out.push('unreviewed')
  if (i.total_amount === null) out.push('no_total')
  if (
    i.total_amount !== null &&
    i.amount_before_vat !== null &&
    i.vat_amount !== null &&
    Math.abs(i.amount_before_vat + i.vat_amount - i.total_amount) > 1
  ) {
    out.push('mismatch')
  }
  if (i.duplicate) out.push('duplicate')
  if (hasCompanies && !i.company_id && i.recipient_name) out.push('not_ours')
  return out
}

export const FLAG_LABELS: Record<InvoiceFlag, string> = {
  unread: 'ממתינה לקריאה',
  failed: 'הקריאה נכשלה',
  unreviewed: 'לבדיקה',
  mismatch: 'הסכומים אינם מתיישבים',
  duplicate: 'אותו מספר חשבונית כבר קיים',
  no_total: 'חסר סכום',
  not_ours: 'הנמען אינו אחת החברות',
}

/** תו שאסור בשם קובץ בזיפ (או מבלבל ב-Windows) — מוחלף, ואורך מוגבל. */
export function safeName(s: string, max = 40): string {
  const t = [...s]
    .map((ch) => (ch.charCodeAt(0) < 32 ? ' ' : ch))
    .join('')
    .replace(/[\\/:*?"<>|]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max)
    .trim()
  return t || 'ללא'
}

/**
 * שמות הקבצים בתיקייה של החודש: "001_14-03-2026_פז_A-100.pdf", לפי סדר התאריך.
 * מספר רץ בתחילה — כך השמות ייחודיים, והשורה ב-Excel מצביעה עליהם.
 */
export function zipEntries(invoices: readonly Invoice[]): { invoice: Invoice; name: string }[] {
  const sorted = [...invoices].sort(
    (a, b) =>
      (a.issue_date ?? '9999').localeCompare(b.issue_date ?? '9999') || a.created_at.localeCompare(b.created_at),
  )
  return sorted.map((invoice, i) => {
    const parts = [
      String(i + 1).padStart(3, '0'),
      invoice.issue_date ? fmtInvoiceDate(invoice.issue_date).replace(/\//g, '-') : null,
      safeName(invoice.vendor_name ?? 'ספק', 30),
      invoice.invoice_number ? safeName(invoice.invoice_number, 20) : null,
    ].filter(Boolean)
    return { invoice, name: `${parts.join('_')}.pdf` }
  })
}

/** סכום לתצוגה בשורה: ₪ למטבע ישראלי, אחרת קוד המטבע. */
export function fmtAmount(n: number | null, currency: string): string {
  if (n === null || n === undefined) return '—'
  const s = Number(n).toLocaleString('he-IL', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  return currency === 'ILS' ? `₪${s}` : `${s} ${currency}`
}
