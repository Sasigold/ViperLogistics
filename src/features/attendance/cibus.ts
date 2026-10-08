/**
 * סיבוס מול השעון (0210) — החלק הטהור.
 *
 * הדפדפן רק קורא את קובץ ה-Excel של סיבוס ומתרגם אותו לשורות. מי צומד למי,
 * איזו משיכה נפלה בתוך משמרת (או עד שעה לפניה/אחריה) וכמה נמשך בלי נוכחות —
 * כל זה מוכרע בשרת (`cibus_import`, `cibus_report`), והמסך והייצוא רק מציגים.
 *
 * השעה נשלחת כפי שהיא כתובה בקובץ, שעון ישראל בלי אזור זמן: השרת ממקם אותה,
 * כדי שמחשב שאזור הזמן שלו אחר לא יזיז משיכה ממשמרת למשמרת.
 */
import type { CibusImportRow, CibusReport, CibusTransaction } from '../../types/domain'

/** הכותרות בדוח המפורט של סיבוס. ההתאמה היא לפי שם ולא לפי מיקום העמודה. */
const HEADERS = {
  datetime: ['תאריך ושעה'],
  date: ['תאריך'],
  time: ['שעה'],
  txn_no: ["מס' עסקה", 'מס עסקה', 'מספר עסקה'],
  user_no: ["מס' משתמש", 'מס משתמש', 'מספר משתמש'],
  first_name: ['שם פרטי'],
  last_name: ['שם משפחה'],
  employee_name: ['שם העובד/ת', 'שם העובד', 'שם עובד'],
  merchant: ['שם בית העסק', 'בית עסק'],
  deal_type: ['סוג עסקה'],
  amount: ['הסכום שחוייב', 'הסכום שחויב', 'סכום'],
  company_part: ['חלק חברה'],
  employee_part: ['חלק עובד'],
} as const

type HeaderKey = keyof typeof HEADERS

const norm = (s: string) => s.replace(/["'`״׳]/g, "'").replace(/\s+/g, ' ').trim()

const pad2 = (n: number) => String(n).padStart(2, '0')

/** '31/08/2026 00:25' · '2026-08-31 00:25' · תאריך ושעה בשני תאים → '2026-08-31T00:25' */
export function cibusLocalDateTime(datetime: string, date = '', time = ''): string | null {
  const parse = (s: string) => {
    const dmy = s.match(/^(\d{1,2})[./-](\d{1,2})[./-](\d{4})(?:[ T]+(\d{1,2}):(\d{2}))?/)
    if (dmy) return { y: +dmy[3], m: +dmy[2], d: +dmy[1], hh: dmy[4], mm: dmy[5] }
    const iso = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T]+(\d{1,2}):(\d{2}))?/)
    if (iso) return { y: +iso[1], m: +iso[2], d: +iso[3], hh: iso[4], mm: iso[5] }
    return null
  }
  let p = parse(datetime.trim())
  if (!p || p.hh == null) {
    const d = parse(date.trim()) ?? p
    const t = time.trim().match(/^(\d{1,2}):(\d{2})/)
    if (!d) return null
    p = t ? { ...d, hh: t[1], mm: t[2] } : d
  }
  if (p.hh == null || p.mm == null) return null
  if (p.m < 1 || p.m > 12 || p.d < 1 || p.d > 31 || +p.hh > 23 || +p.mm > 59) return null
  return `${p.y}-${pad2(p.m)}-${pad2(p.d)}T${pad2(+p.hh)}:${p.mm}`
}

const toNumber = (s: string): number | null => {
  const cleaned = s.replace(/[₪,\s]/g, '')
  if (!cleaned) return null
  const n = Number(cleaned)
  return Number.isFinite(n) ? n : null
}

export interface CibusParseResult {
  rows: CibusImportRow[]
  /** שורות שנראו כמו משיכה ולא נקראו — עם הסיבה, למסך */
  errors: string[]
}

/**
 * מטריצת מחרוזות (גיליון אחרי `normalizeCell`) → משיכות.
 *
 * שורת הכותרות מאותרת לפי התוכן ולא לפי המיקום: לפניה בדוח של סיבוס יש
 * כותרת, הערת "מידע רגיש" ושורות ריקות, ואחרי המשיכות שורת סה"כ והערה
 * משפטית. כל שורה בלי מספר עסקה פשוט אינה משיכה.
 */
export function parseCibusMatrix(matrix: string[][]): CibusParseResult {
  const headerIdx = matrix.findIndex((r) => {
    const cells = r.map(norm)
    return HEADERS.txn_no.some((h) => cells.includes(norm(h))) && cells.some((c) => c === norm('סוג עסקה') || HEADERS.amount.some((h) => c === norm(h)))
  })
  if (headerIdx < 0) {
    return { rows: [], errors: ['לא נמצאה שורת הכותרות של סיבוס ("מס\' עסקה", "הסכום שחוייב"). האם זה הדוח המפורט?'] }
  }

  const header = matrix[headerIdx]!.map(norm)
  const col = {} as Record<HeaderKey, number>
  for (const key of Object.keys(HEADERS) as HeaderKey[]) {
    col[key] = header.findIndex((h) => HEADERS[key].some((name) => norm(name) === h))
  }
  const at = (r: string[], key: HeaderKey) => (col[key] >= 0 ? (r[col[key]] ?? '').trim() : '')

  const rows: CibusImportRow[] = []
  const errors: string[] = []
  const seen = new Set<number>()

  for (let i = headerIdx + 1; i < matrix.length; i++) {
    const r = matrix[i]!
    const txnRaw = at(r, 'txn_no')
    if (!/^\d+$/.test(txnRaw)) continue
    const txn_no = Number(txnRaw)
    if (seen.has(txn_no)) continue
    seen.add(txn_no)

    const first = at(r, 'first_name')
    const last = at(r, 'last_name')
    const employee_name = at(r, 'employee_name') || `${first} ${last}`.trim()
    const occurred_local = cibusLocalDateTime(at(r, 'datetime'), at(r, 'date'), at(r, 'time'))
    const amount = toNumber(at(r, 'amount'))
    if (!occurred_local) {
      errors.push(`עסקה ${txn_no}: תאריך ושעה לא נקראו`)
      continue
    }
    if (amount == null) {
      errors.push(`עסקה ${txn_no}: אין סכום`)
      continue
    }
    if (!employee_name) {
      errors.push(`עסקה ${txn_no}: אין שם עובד`)
      continue
    }
    const userNo = at(r, 'user_no')
    rows.push({
      txn_no,
      occurred_local,
      user_no: /^\d+$/.test(userNo) ? Number(userNo) : null,
      first_name: first || null,
      last_name: last || null,
      employee_name,
      merchant: at(r, 'merchant') || null,
      deal_type: at(r, 'deal_type') || null,
      amount,
      company_part: toNumber(at(r, 'company_part')),
      employee_part: toNumber(at(r, 'employee_part')),
    })
  }

  if (rows.length === 0 && errors.length === 0) errors.push('לא נמצאו משיכות בקובץ')
  return { rows, errors }
}

/** סיכום של מה שנקרא, למסך התצוגה המקדימה — לפני שנשלח דבר לשרת. */
export function summarizeParsed(rows: CibusImportRow[]) {
  const employees = new Set(rows.map((r) => r.user_no ?? r.employee_name))
  const days = rows.map((r) => r.occurred_local.slice(0, 10)).sort()
  return {
    count: rows.length,
    employees: employees.size,
    amount: Math.round(rows.reduce((a, r) => a + r.amount, 0) * 100) / 100,
    from: days[0] ?? null,
    to: days[days.length - 1] ?? null,
  }
}

/** המשיכות שנפלו בכל דיווח נוכחות, לפי מזהה הדיווח. */
export function cibusByEntry(report: CibusReport | null | undefined): Map<string, CibusTransaction[]> {
  const map = new Map<string, CibusTransaction[]>()
  for (const t of report?.transactions ?? []) {
    if (!t.entry_id) continue
    const list = map.get(t.entry_id)
    if (list) list.push(t)
    else map.set(t.entry_id, [t])
  }
  return map
}

/** המשיכות בלי נוכחות של עובד אחד (או של עובד סיבוס שטרם צומד, לפי link_key) */
export function unmatchedFor(report: CibusReport | null | undefined, profileId: string): CibusTransaction[] {
  return (report?.transactions ?? []).filter((t) => !t.entry_id && t.profile_id === profileId)
}

/** ₪29.90 — סיבוס נמשך באגורות, ולכן שתי ספרות ולא עיגול לשקל כמו fmtMoney */
export function fmtCibusAmount(n: number | null | undefined): string {
  if (n == null) return ''
  return new Intl.NumberFormat('he-IL', {
    style: 'currency',
    currency: 'ILS',
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  }).format(n)
}

/** '00:25' בשעון ישראל, בלי קשר לאזור הזמן של המחשב */
export function cibusTime(iso: string): string {
  return new Date(iso).toLocaleTimeString('he-IL', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    timeZone: 'Asia/Jerusalem',
  })
}

/** '31/08/2026' בשעון ישראל */
export function cibusDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-GB', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    timeZone: 'Asia/Jerusalem',
  })
}

/**
 * ‏'₪29.90' בלי סימני הכיווניות ש-Intl מוסיף: בתא של אקסל הם נשארים כתווים
 * בלתי נראים בטקסט, ומפריעים לחיפוש ולהעתקה.
 */
export function plainCibusAmount(n: number): string {
  return `₪${Number.isInteger(n) ? n : n.toFixed(2)}`
}

/** "משיכה אחת" / "3 משיכות" */
export function cibusCount(n: number): string {
  return n === 1 ? 'משיכה אחת' : `${n} משיכות`
}

/** "₪29.90 · YOM YOM דלק אפק (00:25)" — שורה אחת לתא באקסל או לטולטיפ במסך */
export function cibusLine(t: CibusTransaction): string {
  return `${plainCibusAmount(t.amount)} · ${t.merchant ?? 'סיבוס'} (${cibusTime(t.occurred_at)})`
}
