/**
 * תלושי שכר (0218) — הלוגיקה הטהורה של המסכים.
 *
 * הסכומים ועלות המעביד מחושבים במסד (`payslip_amounts`, עמודות generated);
 * כאן רק תוויות, נתיבים, חלוקת עמודים לקריאה ובדיקות תצוגה על מספרים שהשרת
 * כבר החזיר.
 */
import type { MyPayslip, PayslipAmountKey, PayslipAmounts, PayslipNiBracket } from '../../types/domain'

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
  if (a.gross_pay !== null && a.taxable_income === null)
    flags.push({ tone: 'warning', text: 'חסר "חייב מ.ה." — ביטוח לאומי מעסיק לא חושב' })
  if (a.taxable_income !== null && a.employer_national_insurance === null)
    flags.push({ tone: 'warning', text: 'אין מדרגות ביטוח לאומי לחודש התלוש (בהגדרות)' })
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

/** הרכיבים בטופס, בקבוצות — כמו שהם מסודרים בתלוש (0219). */
export const AMOUNT_GROUPS: { title: string; hint: string; fields: AmountField[] }[] = [
  {
    title: 'נתונים כלליים',
    hint: 'מה ששולם לעובד החודש',
    fields: [
      { key: 'gross_pay', label: 'ברוטו (סה״כ תשלומים)' },
      { key: 'net_pay', label: 'נטו לתשלום' },
    ],
  },
  {
    title: 'ניכויים מהעובד',
    hint: 'בתלוש בצד ימין למטה. יורדים מהברוטו של העובד — אינם חלק מעלות המעביד',
    fields: [
      { key: 'employee_national_insurance', label: 'ביטוח לאומי' },
      { key: 'employee_health_tax', label: 'דמי בריאות' },
      { key: 'employee_pension', label: 'פנסיה / גמל — עובד', hint: 'לפי שם הקרן בתלוש, למשל מיטב דש' },
      { key: 'income_tax', label: 'מס הכנסה' },
      { key: 'employee_study_fund', label: 'קרן השתלמות — עובד' },
    ],
  },
  {
    title: 'תשלומי המעסיק',
    hint: 'בתלוש בצד שמאל למעלה. משולמים מעל הברוטו — הם מה שהופך את הברוטו לעלות מעביד',
    fields: [
      { key: 'employer_severance', label: 'פיצויים חודשי' },
      { key: 'employer_pension', label: 'קופ״ג מעסיק — חודשי' },
      {
        key: 'taxable_income',
        label: 'חייב מ.ה.',
        hint: 'ביטוח לאומי מעסיק מחושב ממנו לפי המדרגות בהגדרות',
      },
      { key: 'employer_study_fund', label: 'קרן השתלמות — מעסיק' },
      { key: 'employer_other', label: 'תשלומי מעסיק אחרים', hint: 'אובדן כושר עבודה וכד׳' },
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

/** מדרגה בטופס ההגדרות: מחרוזות כפי שהוקלדו. */
export interface BracketDraft {
  up_to: string
  rate: string
}

/**
 * בדיקת טופס המדרגות לפני שליחה — אותם כללים של `payslip_ni_brackets_save`
 * (השרת בודק שוב). מחזירה את המדרגות או הודעת שגיאה.
 */
export function parseBrackets(rows: readonly BracketDraft[]): { brackets: PayslipNiBracket[] } | { error: string } {
  const out: PayslipNiBracket[] = []
  let prev = 0
  for (let i = 0; i < rows.length; i++) {
    const n = i + 1
    const rate = parseAmountInput(rows[i].rate)
    if (rate === null || rate < 0 || rate > 100) return { error: `מדרגה ${n}: האחוז חייב להיות בין 0 ל-100` }
    if (rows[i].up_to.trim() === '') {
      if (i < rows.length - 1) return { error: 'רק המדרגה האחרונה יכולה להיות בלי תקרה' }
      out.push({ up_to: null, rate })
      continue
    }
    const up = parseAmountInput(rows[i].up_to)
    if (up === null || up <= prev) return { error: `מדרגה ${n}: הסכום חייב להיות גדול מהמדרגה שלפניה` }
    prev = up
    out.push({ up_to: up, rate })
  }
  if (out.length > 12) return { error: 'עד 12 מדרגות' }
  return { brackets: out }
}

/** תיאור מדרגה בעברית: "מ-7,000 עד 15,000 ₪ — 5%". */
export function bracketLabel(brackets: readonly PayslipNiBracket[], i: number): string {
  const from = i === 0 ? 0 : (brackets[i - 1].up_to ?? 0)
  const fmt = (v: number) => v.toLocaleString('he-IL', { maximumFractionDigits: 2 })
  const b = brackets[i]
  const range = b.up_to === null ? `מעל ${fmt(from)} ₪` : `מ-${fmt(from)} עד ${fmt(b.up_to)} ₪`
  return `${range} — ${fmt(b.rate)}%`
}

/** 'YYYY-MM-01' → ערך של `<input type="month">`. */
export const toMonthInput = (period: string | null) => (period ? period.slice(0, 7) : '')

/** `<input type="month">` → 'YYYY-MM-01', או null כשריק. */
export const fromMonthInput = (v: string) => (/^\d{4}-\d{2}$/.test(v) ? `${v}-01` : null)

/** "ינואר 2026 – יוני 2026", או "מינואר 2026, בלי תפוגה". */
export function termLabel(from: string, to: string | null): string {
  return to ? `${periodLabel(from)} – ${periodLabel(to)}` : `מ${periodLabel(from)}, בלי תפוגה`
}
