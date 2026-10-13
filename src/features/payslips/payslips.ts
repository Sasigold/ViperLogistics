/**
 * תלושי שכר (0218) — הלוגיקה הטהורה של המסכים.
 *
 * הסכומים ועלות המעביד מחושבים במסד (`payslip_amounts`, עמודות generated);
 * כאן רק תוויות, נתיבים, חלוקת עמודים לקריאה ובדיקות תצוגה על מספרים שהשרת
 * כבר החזיר.
 */
import type { MyPayslip, PayslipAmountKey, PayslipAmounts } from '../../types/domain'

export const PAYSLIP_BUCKET = 'payslips'

/** כמה עמודים בכל קריאה ל-`payslip-read` — זהה ל-MAX_PAGES_PER_CALL שם. */
export const READ_CHUNK = 6

const MONTHS = [
  'ינואר',
  'פברואר',
  'מרץ',
  'אפריל',
  'מאי',
  'יוני',
  'יולי',
  'אוגוסט',
  'ספטמבר',
  'אוקטובר',
  'נובמבר',
  'דצמבר',
]

/** '2026-09-01' → 'ספטמבר 2026'. אותה תווית של `app.payslip_period_label`. */
export function periodLabel(period: string): string {
  const [y, m] = period.split('-').map(Number)
  if (!y || !m || m < 1 || m > 12) return period
  return `${MONTHS[m - 1]} ${y}`
}

const pad = (n: number) => String(n).padStart(2, '0')

/** הראשון בחודש של התאריך, כ-'YYYY-MM-01' (שעון מקומי). */
export function monthOf(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-01`
}

/** '2026-01-01' + (−1) → '2025-12-01' */
export function shiftPeriod(period: string, delta: number): string {
  const [y, m] = period.split('-').map(Number)
  const idx = y * 12 + (m - 1) + delta
  return `${Math.floor(idx / 12)}-${pad((idx % 12) + 1)}-01`
}

/**
 * החודש שמוצע בהעלאה: החודש הקודם. רואה החשבון שולח את תלושי ספטמבר בתחילת
 * אוקטובר; תלוש שהקריאה מצאה בו חודש אחר מקבל את שלו בכל מקרה.
 */
export function defaultUploadPeriod(now: Date): string {
  return shiftPeriod(monthOf(now), -1)
}

/** החודשים לבחירה, החדש ראשון: מחודש הבא ועד `back` חודשים אחורה. */
export function periodOptions(now: Date, back = 24): string[] {
  const top = shiftPeriod(monthOf(now), 1)
  return Array.from({ length: back + 2 }, (_, i) => shiftPeriod(top, -i))
}

/** הנתיב של עמוד בדלי — החוזה של `app.may_touch_payslip_file`. */
export function pagePath(batchId: string, page: number): string {
  return `${batchId}/${page}.pdf`
}

export function slipPages(from: number, to: number): number[] {
  return Array.from({ length: Math.max(0, to - from + 1) }, (_, i) => from + i)
}

export function chunks<T>(items: readonly T[], size: number): T[][] {
  const out: T[][] = []
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size))
  return out
}

export function pageRangeLabel(from: number, to: number): string {
  return from === to ? `עמוד ${from}` : `עמודים ${from}–${to}`
}

/** "תלוש 09-2026 - משה כהן.pdf" — בלי תווים שמערכת קבצים דוחה. */
export function slipFileName(period: string, name?: string | null): string {
  const [y, m] = period.split('-')
  const who = (name ?? '')
    .replace(/[\\/:*?"<>|]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
  return `תלוש ${m}-${y}${who ? ` - ${who}` : ''}.pdf`
}

export interface CostFlag {
  tone: 'warning' | 'info'
  text: string
}

/**
 * מה שחסר או לא מתיישב בסכומים של תלוש — כדי שעלות מעביד חלקית לא תיראה
 * כמו עלות מלאה. ההשוואה היא בין שני מספרים שהשרת החזיר; שום סכום אינו
 * מחושב כאן.
 */
export function costFlags(a: PayslipAmounts | null | undefined): CostFlag[] {
  if (!a) return [{ tone: 'info', text: 'אין סכומים — התלוש לא נקרא ולא הוקלד' }]
  const flags: CostFlag[] = []
  if (a.gross_pay === null) flags.push({ tone: 'warning', text: 'חסר ברוטו — אין עלות מעביד' })
  if (a.gross_pay !== null && a.employer_national_insurance === null)
    flags.push({ tone: 'warning', text: 'ביטוח לאומי מעביד לא מופיע — העלות אינה כוללת אותו' })
  if (
    a.printed_employer_cost !== null &&
    a.employer_cost !== null &&
    Math.abs(Number(a.printed_employer_cost) - Number(a.employer_cost)) > 1
  )
    flags.push({ tone: 'warning', text: 'לא מתיישב עם עלות המעביד שמודפסת בתלוש' })
  return flags
}

export interface AmountField {
  key: PayslipAmountKey
  label: string
  hint?: string
}

/** הרכיבים בטופס, בשלוש קבוצות — כמו שהם מסודרים בתלוש. */
export const AMOUNT_GROUPS: { title: string; hint: string; fields: AmountField[] }[] = [
  {
    title: 'שכר',
    hint: 'מה ששולם לעובד החודש',
    fields: [
      { key: 'gross_pay', label: 'ברוטו (סה״כ תשלומים)' },
      { key: 'net_pay', label: 'נטו לתשלום' },
      {
        key: 'imputed_income',
        label: 'זקיפות שווי בתוך הברוטו',
        hint: 'שווי רכב, טלפון וכד׳ — נכללים בברוטו לצורכי מס אבל אינם כסף ששולם',
      },
    ],
  },
  {
    title: 'ניכויי העובד',
    hint: 'יורדים מהברוטו של העובד — אינם חלק מעלות המעביד',
    fields: [
      { key: 'income_tax', label: 'מס הכנסה' },
      { key: 'employee_national_insurance', label: 'ביטוח לאומי ומס בריאות — עובד' },
      { key: 'employee_pension', label: 'פנסיה / גמל — עובד' },
      { key: 'employee_study_fund', label: 'קרן השתלמות — עובד' },
    ],
  },
  {
    title: 'הפרשות המעביד',
    hint: 'משולמות מעל הברוטו — הן מה שהופך את הברוטו לעלות מעביד',
    fields: [
      { key: 'employer_pension', label: 'פנסיה / גמל — מעביד' },
      { key: 'employer_severance', label: 'פיצויים' },
      { key: 'employer_study_fund', label: 'קרן השתלמות — מעביד' },
      { key: 'employer_national_insurance', label: 'ביטוח לאומי — מעביד' },
      { key: 'employer_other', label: 'הפרשות מעביד אחרות', hint: 'אובדן כושר עבודה, מס שכר וכד׳' },
    ],
  },
  {
    title: 'בקרה',
    hint: 'לא נכנס לחישוב — רק להשוואה',
    fields: [{ key: 'printed_employer_cost', label: 'עלות מעביד כפי שמודפסת בתלוש' }],
  },
]

export const AMOUNT_KEYS: PayslipAmountKey[] = AMOUNT_GROUPS.flatMap((g) => g.fields.map((f) => f.key))

/** קלט טופס → מספר או null. "1,234.5" מתקבל; כל השאר — null. */
export function parseAmountInput(v: string): number | null {
  const t = v.replace(/[,\s₪]/g, '')
  if (t === '' || !/^-?\d+(\.\d+)?$/.test(t)) return null
  return Number(t)
}

export interface MonthGroup<T> {
  period: string
  slips: T[]
}

/** התלושים של העובד לפי חודש, החדש ראשון. שני תלושים באותו חודש (תלוש מתקן) — באותה קבוצה. */
export function groupByPeriod<T extends Pick<MyPayslip, 'period'>>(rows: readonly T[]): MonthGroup<T>[] {
  const map = new Map<string, T[]>()
  for (const r of rows) map.set(r.period, [...(map.get(r.period) ?? []), r])
  return [...map.entries()]
    .sort(([a], [b]) => (a < b ? 1 : a > b ? -1 : 0))
    .map(([period, slips]) => ({ period, slips }))
}
