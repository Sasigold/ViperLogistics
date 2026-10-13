// החצי הטהור של קריאת תלושי השכר (0218) — בלי שום import של Deno, כדי
// ש-vitest יכסה אותו (אותו שיקול של `_shared/viperflow.ts`).
//
// כאן: ההנחיה ל-Claude, הסכמה שהתשובה חייבת לעמוד בה, והנרמול של התשובה
// לצורה ש-`payslip_store_reading` שומרת ו-`payslip_apply_reading` מקבצת.
// המסד אינו סומך על הצורה: גם הוא מסנן כל סכום (`app.payslip_num`) וכל
// חודש (`app.payslip_period`). הנרמול כאן הוא כדי שמה שנשמר יהיה נקי.

/** ברירת המחדל. `PAYSLIP_MODEL` בסודות הפונקציה מחליף אותה. */
export const PAYSLIP_MODEL = 'claude-opus-5-5'

/**
 * הרכיבים, בסדר שבו המסך מציג אותם. שמות זהים לעמודות `payslip_amounts`.
 * ביטוח לאומי מעסיק אינו כאן: הוא מחושב במסד מ-`taxable_income` לפי המדרגות
 * שבהגדרות (0219), וזקיפות שווי אינן חלק מהעלות.
 */
export const AMOUNT_KEYS = [
  'gross_pay',
  'net_pay',
  'income_tax',
  'employee_national_insurance',
  'employee_health_tax',
  'employee_pension',
  'employee_study_fund',
  'employer_severance',
  'employer_pension',
  'taxable_income',
  'employer_study_fund',
  'employer_other',
  'printed_employer_cost',
] as const

export type AmountKey = (typeof AMOUNT_KEYS)[number]

/**
 * רכיבים שהם סכום אחד מודפס. כל השאר מצטברים: שתי קרנות פנסיה, או שתי שורות
 * פיצויים, יכולות לחזור כשתי שורות של אותו רכיב — ושתיהן נספרות.
 */
const SINGLE_VALUE: ReadonlySet<string> = new Set<AmountKey>([
  'gross_pay',
  'net_pay',
  'taxable_income',
  'printed_employer_cost',
])

export interface PayslipReading {
  kind: 'payslip' | 'other'
  employee_name: string | null
  employee_no: string | null
  /** 'YYYY-MM-01' */
  period: string | null
  page_index: number | null
  page_total: number | null
  amounts: Partial<Record<AmountKey, number>>
  notes: string | null
}

export const PAYSLIP_SYSTEM = `You read one page of an Israeli payslip PDF (תלוש שכר) and return its data as JSON.
The PDF a company receives from its accountant contains many payslips, one employee after another; you see a single page of it.

Identify the page:
- kind: "payslip" when the page is (part of) one employee's payslip. "other" for anything else — a cover letter, a summary of all employees (ריכוז / דוח מרכז), a Form 102/106 page, a blank page.
- employee_name: the employee's name exactly as printed.
- employee_number: the payroll employee number (מספר עובד / מס' עובד). NEVER return the national ID number (תעודת זהות / ת.ז.) in any field.
- period_month, period_year: the month the payslip is for (e.g. "תלוש שכר לחודש 09/2026" → 9, 2026).
- page_index, page_total: page numbering printed on the page ("דף 2 מתוך 2", "עמוד 1 מתוך 2"), if any.

amounts: a list of {component, amount} — one entry for each component below that is printed on this page, and nothing for a component that is not printed. Current month only, never the cumulative year-to-date columns (מצטבר / מתחילת השנה). Plain numbers in shekels, no thousands separators. Never estimate or compute a value from rates; report only what is printed (sums of several printed lines of the same component are fine). Where to look is typical of the payslips this company receives; if the layout differs, find the same labels elsewhere on the page.

General figures:
- gross_pay: total payments for the month (סה"כ תשלומים / שכר ברוטו). If both "סה"כ תשלומים" and "ברוטו למס הכנסה" appear, use סה"כ תשלומים.
- net_pay: the final amount paid to the employee (נטו לתשלום).

Employee deductions (usually in the deductions block at the bottom right):
- income_tax: מס הכנסה.
- employee_national_insurance: the employee's ביטוח לאומי only — not the health tax.
- employee_health_tax: the employee's דמי בריאות / מס בריאות.
- employee_pension: the employee's deductions to pension / provident fund / managers' insurance — usually shown under the fund's name (e.g. מיטב דש, תגמולי עובד, קופ"ג עובד), summed over all funds.
- employee_study_fund: the employee's קרן השתלמות deduction.

Employer payments (usually in the block at the top left):
- employer_severance: the employer's monthly severance contribution ("פיצויים חודשי" / פיצויים מעסיק).
- employer_pension: the employer's monthly provident / pension contribution ("קופ"ג מעסיק-חודשי" / תגמולי מעביד), summed over all funds, excluding severance.
- taxable_income: the amount liable for income tax this month ("חייב מ.ה." / "חייב במס הכנסה" / ברוטו למס הכנסה), usually in the left column. This is the base the company uses to compute the employer's national insurance — do not report the employer's national insurance itself.
- employer_study_fund: the employer's קרן השתלמות contribution.
- employer_other: any other employer contribution printed on the payslip that is not one of the above (e.g. אובדן כושר עבודה מעביד when shown separately). Not the employer's national insurance.
- printed_employer_cost: the total employer cost if the payslip prints one (עלות מעביד / עלות שכר כוללת).

notes: one short sentence about anything unclear on the page, otherwise null.`

// ‏structured outputs מגביל ל-16 שדות עם union (כל nullable הוא union). הסכומים
// הם 13 רכיבים, ולכן הם רשימה של מה שמודפס — בלי אף שדה nullable — ולא אובייקט
// שכל רכיב בו "מספר או null". השדות שנשארו nullable: שבעה.
const int = { anyOf: [{ type: 'integer' }, { type: 'null' }] }
const str = { anyOf: [{ type: 'string' }, { type: 'null' }] }

export const PAYSLIP_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: [
    'kind',
    'employee_name',
    'employee_number',
    'period_month',
    'period_year',
    'page_index',
    'page_total',
    'amounts',
    'notes',
  ],
  properties: {
    kind: { type: 'string', enum: ['payslip', 'other'] },
    employee_name: str,
    employee_number: str,
    period_month: int,
    period_year: int,
    page_index: int,
    page_total: int,
    amounts: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['component', 'amount'],
        properties: {
          component: { type: 'string', enum: [...AMOUNT_KEYS] },
          amount: { type: 'number' },
        },
      },
    },
    notes: str,
  },
} as const

const clean = (v: unknown, max: number): string | null => {
  if (typeof v !== 'string') return null
  const s = v.replace(/\s+/g, ' ').trim()
  return s ? s.slice(0, max) : null
}

const intIn = (v: unknown, lo: number, hi: number): number | null => {
  const n = typeof v === 'string' ? Number(v) : v
  return typeof n === 'number' && Number.isInteger(n) && n >= lo && n <= hi ? n : null
}

/** סכום: מספר סופי בטווח של `numeric(12,2)`, מעוגל לאגורות. מחרוזת "1,234.50" מתקבלת. */
export function amount(v: unknown): number | null {
  const n = typeof v === 'string' ? Number(v.replace(/[,\s₪]/g, '')) : v
  if (typeof n !== 'number' || !Number.isFinite(n) || Math.abs(n) >= 1e9) return null
  return Math.round(n * 100) / 100
}

/** "מספר עובד": ספרות ואותיות בלבד. רצף של 9 ספרות בדיוק נזרק — זו תעודת זהות, לא מספר עובד. */
export function employeeNo(v: unknown): string | null {
  const s = typeof v === 'number' ? String(v) : typeof v === 'string' ? v : ''
  const t = s.replace(/[^0-9A-Za-z]/g, '').slice(0, 40)
  if (!t || /^\d{9}$/.test(t)) return null
  return t
}

export function normalizeReading(raw: unknown): PayslipReading {
  const r = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>
  const kind = r.kind === 'other' ? 'other' : 'payslip'
  const month = intIn(r.period_month, 1, 12)
  const year = intIn(r.period_year, 2000, 2099)
  const amounts: Partial<Record<AmountKey, number>> = {}
  // הסכמה מחזירה רשימה [{component, amount}]; אובייקט {רכיב: סכום} מתקבל גם הוא.
  // רכיב שחוזר ברשימה מצטבר, חוץ מסכום יחיד (ברוטו, נטו, עלות מודפסת) — שם האחרון קובע.
  const known = new Set<string>(AMOUNT_KEYS)
  if (kind === 'payslip' && Array.isArray(r.amounts)) {
    for (const e of r.amounts as unknown[]) {
      const item = (e && typeof e === 'object' ? e : {}) as Record<string, unknown>
      const k = item.component
      const v = amount(item.amount)
      if (typeof k !== 'string' || !known.has(k) || v === null) continue
      const key = k as AmountKey
      amounts[key] =
        SINGLE_VALUE.has(key) || amounts[key] === undefined ? v : Math.round((amounts[key]! + v) * 100) / 100
    }
  } else if (kind === 'payslip' && r.amounts && typeof r.amounts === 'object') {
    const obj = r.amounts as Record<string, unknown>
    for (const k of AMOUNT_KEYS) {
      const v = amount(obj[k])
      if (v !== null) amounts[k] = v
    }
  }
  const pageTotal = intIn(r.page_total, 1, 99)
  let pageIndex = intIn(r.page_index, 1, 99)
  if (pageIndex !== null && pageTotal !== null && pageIndex > pageTotal) pageIndex = null
  return {
    kind,
    employee_name: kind === 'payslip' ? clean(r.employee_name, 120) : null,
    employee_no: kind === 'payslip' ? employeeNo(r.employee_number) : null,
    period: month !== null && year !== null ? `${year}-${String(month).padStart(2, '0')}-01` : null,
    page_index: pageIndex,
    page_total: pageTotal,
    amounts,
    notes: clean(r.notes, 300),
  }
}

/** base64 בלי שורות חדשות, בלי Buffer ובלי Deno — במנות, כדי לא לפוצץ את המחסנית. */
export function bytesToBase64(bytes: Uint8Array): string {
  let bin = ''
  const CHUNK = 0x8000
  for (let i = 0; i < bytes.length; i += CHUNK) {
    bin += String.fromCharCode(...bytes.subarray(i, i + CHUNK))
  }
  return btoa(bin)
}

/** `fn` על כל איבר, לכל היותר `limit` במקביל; התוצאות בסדר הקלט. */
export async function mapLimit<T, R>(items: readonly T[], limit: number, fn: (item: T) => Promise<R>): Promise<R[]> {
  const out = new Array<R>(items.length)
  let next = 0
  const worker = async () => {
    while (next < items.length) {
      const i = next++
      out[i] = await fn(items[i])
    }
  }
  await Promise.all(Array.from({ length: Math.max(1, Math.min(limit, items.length)) }, worker))
  return out
}
