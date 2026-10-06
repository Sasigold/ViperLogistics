/**
 * תשלומי אירועים (0205) — הלוגיקה הטהורה של המסכים.
 *
 * הכסף עצמו — כמה מגיע, כמה שולם, מה היתרה — נספר בשרת (`event_payment_summary`,
 * `event_payments_list`). מה שכאן הוא רק איך קוראים את המספרים: מה מצב
 * האירוע, איך כותבים שורת עמלה, ואיך הופכים את מה שהוקלד לסכום.
 */
import { endOfMonth, endOfYear, format, startOfMonth, startOfYear, subMonths } from 'date-fns'
import type { EventPaymentLine, PaymentMethod } from '../../types/domain'

export const METHOD_LABELS: Record<PaymentMethod, string> = {
  cash: 'מזומן',
  other: 'אחר',
}

/**
 * מצב התשלום של אירוע.
 *
 *   * `paid` — שולם במלואו.
 *   * `partial` — שולם חלק, ונשארה יתרה.
 *   * `unpaid` — מגיע סכום, ולא שולם דבר.
 *   * `credit` — שולם יותר ממה שמגיע: מחיר שירד אחרי התשלום, או אירוע שבוטל.
 *   * `none` — אין מה לגבות ולא שולם דבר (אירוע שעוד לא תומחר).
 */
export type PaymentState = 'paid' | 'partial' | 'unpaid' | 'credit' | 'none'

/** אגורות ולא שברים של אגורה: 0.1 + 0.2 אינו 0.3, ויתרה של 1e-13 אינה חוב. */
function cents(v: number): number {
  return Math.round(v * 100)
}

export function paymentState(due: number, paid: number): PaymentState {
  const d = cents(due)
  const p = cents(paid)
  if (d <= 0 && p <= 0) return 'none'
  if (p > d) return 'credit'
  if (p === d) return 'paid'
  return p > 0 ? 'partial' : 'unpaid'
}

export const STATE_LABELS: Record<PaymentState, string> = {
  paid: 'שולם',
  partial: 'שולם חלקית',
  unpaid: 'לא שולם',
  credit: 'יתרת זכות',
  none: 'אין סכום',
}

export const STATE_TONES: Record<PaymentState, 'success' | 'warning' | 'error' | 'info' | 'neutral'> = {
  paid: 'success',
  partial: 'warning',
  unpaid: 'error',
  credit: 'info',
  none: 'neutral',
}

/** הסינון של מסך התשלומים. "פתוח" = כל מה שנשארה עליו יתרה. */
export type PaymentFilter = 'all' | 'open' | 'unpaid' | 'partial' | 'paid'

export function matchesFilter(due: number, paid: number, filter: PaymentFilter): boolean {
  const state = paymentState(due, paid)
  switch (filter) {
    case 'all':
      return true
    case 'open':
      return state === 'unpaid' || state === 'partial'
    default:
      return state === filter
  }
}

/**
 * שורה בפירוט: שורת הכנסה שוייפר מקבל ממנה פחות ממאה אחוז היא עמלה, וכך
 * הבעלים קורא לה ("עמלות מהריהוט הישן"). הובלות, שהן 100%, נשארות בשמן.
 */
export function lineLabel(line: Pick<EventPaymentLine, 'label' | 'pct'>): string {
  return line.pct != null && line.pct < 100 ? `עמלה — ${line.label}` : line.label
}

/**
 * מה שהוקלד בשדה הסכום, כמספר — או null כשאין סכום תקין.
 *
 * מקבל "20,000" ו-"20000.5" ו-"₪ 1,250": מי שמקליד סכום כסף מקליד אותו
 * כפי שהוא רואה אותו. דוחה אפס, שלילי, ויותר משתי ספרות אחרי הנקודה — אותם
 * כללים שהשרת אוכף, כדי שהכפתור לא יציע שמירה שתיכשל.
 */
export function parseAmount(raw: string): number | null {
  const clean = raw.replace(/[\s,₪]/g, '')
  if (!/^\d+(\.\d{1,2})?$/.test(clean)) return null
  const n = Number(clean)
  return Number.isFinite(n) && n > 0 ? n : null
}

/** אזהרה (לא חסימה — השרת רושם) כשהתשלום גבוה מהיתרה. */
export function overpayWarning(amount: number | null, balance: number): string | null {
  if (amount == null) return null
  if (cents(balance) <= 0) return 'לאירוע הזה אין יתרה לתשלום — התשלום יירשם כיתרת זכות'
  if (cents(amount) > cents(balance)) return 'הסכום גבוה מהיתרה — ההפרש יירשם כיתרת זכות'
  return null
}

/**
 * הטווחים המהירים של מסך התשלומים. הטווח הוא תאריך **האירוע**: "מהאירועים
 * של החודש, מה שולם" — לא "מה נכנס החודש", שזו שאלה של מסך התקבולים.
 */
export type RangePreset = 'month' | 'prev_month' | 'quarter' | 'year'

export const PRESET_LABELS: Record<RangePreset, string> = {
  month: 'החודש',
  prev_month: 'חודש קודם',
  quarter: '3 חודשים',
  year: 'השנה',
}

export function presetRange(preset: RangePreset, today: Date): { from: string; to: string } {
  const iso = (d: Date) => format(d, 'yyyy-MM-dd')
  switch (preset) {
    case 'month':
      return { from: iso(startOfMonth(today)), to: iso(endOfMonth(today)) }
    case 'prev_month': {
      const prev = subMonths(today, 1)
      return { from: iso(startOfMonth(prev)), to: iso(endOfMonth(prev)) }
    }
    case 'quarter':
      return { from: iso(startOfMonth(subMonths(today, 2))), to: iso(endOfMonth(today)) }
    case 'year':
      return { from: iso(startOfYear(today)), to: iso(endOfYear(today)) }
  }
}

/** אותה תקרה שהשרת אוכף (0205) — שנה ועוד קצת, כמו הדשבורד. */
export const MAX_RANGE_DAYS = 400

export function rangeError(from: string, to: string): string | null {
  if (!from || !to) return 'יש לבחור טווח תאריכים'
  const days = (new Date(to).getTime() - new Date(from).getTime()) / 86_400_000
  if (days < 0) return 'תאריך הסיום לפני תאריך ההתחלה'
  if (days > MAX_RANGE_DAYS) return 'הטווח ארוך משנה — יש לקצר אותו'
  return null
}
