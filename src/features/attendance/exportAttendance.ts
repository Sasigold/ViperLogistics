/**
 * ייצוא דוח הנוכחות ל-Excel.
 *
 * ExcelJS נטען עצלנית מהמסך, בדיוק כמו ב-ExcelDialog: הוא כבד, והייצוא הוא
 * הסיבה היחידה שהוא נחוץ במסך הזה.
 *
 * שני כללים שאסור לשבור כאן:
 *
 * 1. הסכומים מגיעים מ-attendance_report ולא מחושבים מחדש בדפדפן. המנוע יודע
 *    מה נספר ומה לא — שורה שממתינה לאישור אינה נכנסת לסיכום, והתקרה השבועית
 *    תלויה בסדר. חישוב שני כאן היה נפרד מהראשון ברגע שמישהו יערוך מדרגה
 *    בהגדרות, והקובץ הזה הוא מה שמגיע להנהלת חשבונות.
 * 2. עמודות הכסף נכתבות רק כשהשרת החזיר אותן. attendance_report משמיט
 *    hourly_rate/total/lines מהשורה למי שאינו רשאי לראות סכומים, ולכן אין
 *    כאן הכרעת הרשאה שנייה שיכולה לחלוק על הראשונה.
 *
 * בניית הגיליון מופרדת מהכתיבה שלו כדי שהכלל השני יהיה ניתן לבדיקה בלי
 * ExcelJS ובלי DOM.
 *
 * מבנה הקובץ: "סיכום" (שורה לכל עובד), גיליון לכל עובד — סיכום החודש שלו
 * למעלה, המשמרות מתחת, והמשיכות בלי נוכחות בסוף — "כל המשמרות" (הגיליון
 * השטוח, לסינון), ו"סיבוס ללא נוכחות" כשיובא סיבוס (0210).
 *
 * הסיכום של כל עובד הוא סכום השורות המאושרות שלו, בדיוק כמו שורת העובד
 * במסך ובדיוק כמו ה-totals של השרת: אין כאן חישוב שכר — רק קיבוץ של מה
 * שהשרת כבר חישב לכל שורה. סיכומי הסיבוס מגיעים מוכנים מ-cibus_report.
 */
import type { AttendanceReport, AttendanceReportRow, CibusReport, CibusTransaction } from '../../types/domain'
import { STATUS_LABELS, WORK_SITE_LABELS, flagLabel, fmtCoords, shiftEndLocation } from './shiftFormat'
import { cibusByEntry, cibusCount, cibusDate, cibusLine, cibusTime, plainCibusAmount } from './cibus'

const hhmm = (iso: string | null): string =>
  iso ? new Date(iso).toLocaleTimeString('he-IL', { hour: '2-digit', minute: '2-digit', hour12: false }) : ''

const SOURCE_LABELS: Record<AttendanceReportRow['source'], string> = {
  clock: 'שעון',
  manual: 'ידני',
}

export interface SheetColumn {
  header: string
  key: string
  width: number
}

export interface SheetPlan {
  columns: SheetColumn[]
  rows: Record<string, string | number>[]
  /** שורות הסיכום, אחרי שורה ריקה */
  footer: { values: Record<string, string | number>; style: 'bold' | 'italic' }[]
}

const MONEY_KEYS = ['hourly_rate', 'bonus', 'total'] as const

/** עמודות הסיבוס בגיליון משמרות: מה נמשך ואיפה, ועמודה מספרית לסכום */
const CIBUS_COLUMNS: SheetColumn[] = [
  { header: 'סיבוס', key: 'cibus', width: 34 },
  { header: 'סיבוס ₪', key: 'cibus_amount', width: 10 },
]

const round2 = (n: number) => Math.round(n * 100) / 100

function cibusCells(list: CibusTransaction[] | undefined): Record<string, string | number> {
  if (!list?.length) return { cibus: '', cibus_amount: '' }
  return {
    cibus: list.map(cibusLine).join('; '),
    cibus_amount: round2(list.reduce((a, t) => a + t.amount, 0)),
  }
}

export function buildAttendanceSheet(report: AttendanceReport, cibus?: CibusReport | null): SheetPlan {
  const withPay = report.can_see_pay
  const byEntry = cibus ? cibusByEntry(cibus) : null

  const columns: SheetColumn[] = [
    { header: 'עובד', key: 'full_name', width: 22 },
    { header: 'תאריך', key: 'work_date', width: 12 },
    { header: 'משמרת', key: 'seq', width: 8 },
    { header: 'כניסה', key: 'clock_in', width: 10 },
    { header: 'יציאה', key: 'clock_out', width: 10 },
    { header: 'שעות בפועל', key: 'actual_hours', width: 12 },
    { header: 'שעות מתוכננות', key: 'planned_hours', width: 14 },
    { header: 'שעות לתשלום', key: 'paid_hours', width: 13 },
    { header: 'שעות נוספות', key: 'overtime_hours', width: 12 },
    ...(withPay
      ? [
          { header: 'תעריף', key: 'hourly_rate', width: 10 },
          // עמודה משלו ולא רק בלוע ב"לתשלום": הנהלת חשבונות צריכה לדעת כמה
          // מהסכום אינו שעות.
          { header: 'בונוס', key: 'bonus', width: 10 },
          { header: 'לתשלום', key: 'total', width: 12 },
        ]
      : []),
    ...(byEntry ? CIBUS_COLUMNS : []),
    { header: 'יציאה מ', key: 'work_site', width: 10 },
    // ‏0166: הקצה השני. משמרת יכולה לצאת מהמחסן ולהסתיים בשטח, ולהפך —
    // ועד כאן הגיליון ידע לספר רק את חציה הראשון.
    { header: 'סיום ב', key: 'end_place', width: 16 },
    { header: 'נקודת כניסה', key: 'in_point', width: 20 },
    { header: 'נקודת יציאה', key: 'out_point', width: 20 },
    { header: 'מקור', key: 'source', width: 8 },
    { header: 'סטטוס', key: 'status', width: 14 },
    { header: 'הערות מערכת', key: 'flags', width: 24 },
    { header: 'הערת עובד', key: 'employee_note', width: 26 },
    { header: 'הערת מנהל', key: 'manager_note', width: 26 },
  ]

  const rows = report.rows.map((r) => {
    const row: Record<string, string | number> = {
      full_name: r.full_name,
      work_date: r.work_date,
      seq: r.seq,
      clock_in: hhmm(r.clock_in_at),
      clock_out: hhmm(r.clock_out_at),
      actual_hours: r.actual_hours ?? '',
      planned_hours: r.planned_hours ?? '',
      paid_hours: r.pay?.paid_hours ?? '',
      overtime_hours: r.pay?.overtime_hours ?? '',
      work_site: r.work_site ? WORK_SITE_LABELS[r.work_site] : '',
      end_place: shiftEndLocation(r) ?? '',
      // הנקודה כטקסט ולא כשתי עמודות: היא נקראת ונדבקת למפה כמו שהיא
      in_point: fmtCoords(r.in_lat, r.in_lng) ?? '',
      out_point: fmtCoords(r.out_lat, r.out_lng) ?? '',
      source: SOURCE_LABELS[r.source] ?? r.source,
      status: STATUS_LABELS[r.status] ?? r.status,
      flags: (r.flags ?? []).map(flagLabel).join(', '),
      employee_note: r.employee_note ?? '',
      manager_note: r.manager_note ?? '',
    }
    if (byEntry) Object.assign(row, cibusCells(byEntry.get(r.id)))
    if (withPay) {
      row.hourly_rate = r.pay?.hourly_rate ?? ''
      // אפס נכתב ריק ולא כ-0: עמודה מלאה באפסים קוראת כמו נתון, ובונוס הוא
      // החריג ולא הכלל.
      row.bonus = r.pay?.bonus || ''
      row.total = r.pay?.total ?? ''
    }
    return row
  })

  // הסיכום סופר מאושרות בלבד, ולכן הוא בכוונה אינו שווה לסכום עמודת השעות
  // שמעליו כשיש שורות שממתינות לאישור. הכותרת אומרת את זה במפורש.
  const t = report.totals
  const totals: Record<string, string | number> = {
    full_name: 'סה״כ (מאושר בלבד)',
    actual_hours: t.actual_hours,
    paid_hours: t.paid_hours,
    overtime_hours: t.overtime_hours,
  }
  if (withPay) {
    totals.bonus = t.bonus ?? ''
    totals.total = t.total ?? ''
  }
  if (cibus) totals.cibus_amount = cibus.totals.matched_amount

  const footer: SheetPlan['footer'] = [{ values: totals, style: 'bold' }]
  if (t.pending > 0) {
    footer.push({
      values: { full_name: `ממתין לאישור: ${t.pending} רשומות`, actual_hours: t.pending_hours },
      style: 'italic',
    })
  }

  return { columns, rows, footer }
}

/** true אם התוכנית מכילה עמודת כסף כלשהי — קיים בשביל הבדיקה. */
export function planHasMoney(plan: SheetPlan): boolean {
  const keys = new Set(plan.columns.map((c) => c.key))
  if (MONEY_KEYS.some((k) => keys.has(k))) return true
  return [...plan.rows, ...plan.footer.map((f) => f.values)].some((r) =>
    MONEY_KEYS.some((k) => k in r),
  )
}

// ===== חוברת העבודה =========================================================

export type SheetBlock =
  | { kind: 'title'; text: string; style: 'title' | 'subtitle' | 'heading' | 'note' }
  | { kind: 'pairs'; pairs: [string, string | number][] }
  | ({ kind: 'table' } & SheetPlan)
  | { kind: 'blank' }

export interface WorkbookSheet {
  name: string
  blocks: SheetBlock[]
}

/** שם גיליון חוקי באקסל: עד 31 תווים, בלי []:*?/\ — וייחודי בחוברת */
export function sheetName(raw: string, taken: Set<string>): string {
  const base = (raw.replace(/[[\]:*?/\\]/g, ' ').replace(/\s+/g, ' ').trim() || 'גיליון').slice(0, 31)
  let name = base
  for (let i = 2; taken.has(name.toLowerCase()); i++) {
    const suffix = ` (${i})`
    name = base.slice(0, 31 - suffix.length) + suffix
  }
  taken.add(name.toLowerCase())
  return name
}

/** '9:30' — שעות כפי שקוראים אותן בדוח, לצד המספר העשרוני בטבלה */
function hm(hours: number): string {
  const mins = Math.round(hours * 60)
  return `${Math.floor(mins / 60)}:${String(mins % 60).padStart(2, '0')}`
}

interface EmployeeSummary {
  profileId: string
  name: string
  rows: AttendanceReportRow[]
  days: number
  shifts: number
  pending: number
  actual: number
  paid: number
  overtime: number
  bonus: number
  total: number | null
  cibusMatchedCount: number
  cibusMatchedAmount: number
  cibusUnmatched: CibusTransaction[]
  cibusUnmatchedAmount: number
}

/**
 * סיכום לכל עובד: השורות המאושרות שלו בלבד, כמו במסך. העובדים הם כל מי
 * שיש לו נוכחות בחודש, ובנוסף מי שמשך סיבוס בלי שום נוכחות — דווקא הוא
 * צריך את הגיליון שלו.
 */
export function summarizeEmployees(report: AttendanceReport, cibus?: CibusReport | null): EmployeeSummary[] {
  const withPay = report.can_see_pay
  const byId = new Map<string, EmployeeSummary>()
  const get = (id: string, name: string) => {
    let e = byId.get(id)
    if (!e) {
      e = {
        profileId: id,
        name,
        rows: [],
        days: 0,
        shifts: 0,
        pending: 0,
        actual: 0,
        paid: 0,
        overtime: 0,
        bonus: 0,
        total: null,
        cibusMatchedCount: 0,
        cibusMatchedAmount: 0,
        cibusUnmatched: [],
        cibusUnmatchedAmount: 0,
      }
      byId.set(id, e)
    }
    return e
  }

  for (const r of report.rows) {
    const e = get(r.profile_id, r.full_name)
    e.rows.push(r)
    if (r.status === 'pending') e.pending += 1
    if (r.status !== 'approved') continue
    e.shifts += 1
    e.actual += r.actual_hours ?? 0
    e.paid += r.pay?.paid_hours ?? 0
    e.overtime += r.pay?.overtime_hours ?? 0
    if (withPay) {
      e.bonus += r.pay?.bonus ?? 0
      if (r.pay?.total != null) e.total = (e.total ?? 0) + r.pay.total
    }
  }
  for (const e of byId.values()) {
    e.days = new Set(e.rows.filter((r) => r.status === 'approved' && (r.actual_hours ?? 0) > 0).map((r) => r.work_date)).size
    e.actual = round2(e.actual)
    e.paid = round2(e.paid)
    e.overtime = round2(e.overtime)
    e.bonus = round2(e.bonus)
    if (e.total != null) e.total = round2(e.total)
    // מהישן לחדש: גיליון של חודש נקרא מההתחלה
    e.rows.sort((a, b) => a.clock_in_at.localeCompare(b.clock_in_at))
  }

  for (const c of cibus?.employees ?? []) {
    const e = get(c.profile_id, c.full_name)
    e.cibusMatchedCount = c.matched_count
    e.cibusMatchedAmount = c.matched_amount
    e.cibusUnmatchedAmount = c.unmatched_amount
    e.cibusUnmatched = (cibus?.transactions ?? []).filter((t) => !t.entry_id && t.profile_id === c.profile_id)
  }

  return [...byId.values()].sort((a, b) => a.name.localeCompare(b.name, 'he'))
}

const UNMATCHED_COLUMNS: SheetColumn[] = [
  { header: 'תאריך', key: 'date', width: 12 },
  { header: 'שעה', key: 'time', width: 8 },
  { header: 'בית עסק', key: 'merchant', width: 34 },
  { header: 'סוג עסקה', key: 'deal_type', width: 10 },
  { header: 'סכום', key: 'amount', width: 10 },
]

const unmatchedRow = (t: CibusTransaction): Record<string, string | number> => ({
  date: cibusDate(t.occurred_at),
  time: cibusTime(t.occurred_at),
  merchant: t.merchant ?? '',
  deal_type: t.deal_type ?? '',
  amount: t.amount,
})

/** הגיליון של עובד אחד: סיכום החודש, המשמרות, והמשיכות בלי נוכחות. */
function employeeSheet(
  e: EmployeeSummary,
  report: AttendanceReport,
  cibus: CibusReport | null | undefined,
  range: { from: string; to: string },
  name: string,
): WorkbookSheet {
  const withPay = report.can_see_pay
  const shifts = buildAttendanceSheet({ ...report, rows: e.rows }, cibus)
  // השם כבר בכותרת הגיליון; השורות עצמן לא צריכות לחזור עליו
  const columns = shifts.columns.filter((c) => c.key !== 'full_name')

  const pairs: [string, string | number][] = [
    ['ימי עבודה', e.days],
    ['משמרות מאושרות', e.shifts],
    ['שעות בפועל', `${hm(e.actual)} (${e.actual})`],
    ['שעות לתשלום', `${hm(e.paid)} (${e.paid})`],
  ]
  if (e.overtime > 0) pairs.push(['שעות נוספות', `${hm(e.overtime)} (${e.overtime})`])
  if (withPay) {
    if (e.bonus > 0) pairs.push(['בונוסים (כלול בסך)', e.bonus])
    pairs.push(['סה״כ לתשלום', e.total ?? 0])
  }
  if (e.pending > 0) pairs.push(['ממתין לאישור (לא נספר)', `${e.pending} משמרות`])
  if (cibus) {
    const line = (n: number, amount: number) => (n ? `${cibusCount(n)} · ${plainCibusAmount(amount)}` : 'אין')
    pairs.push(['סיבוס בזמן משמרת', line(e.cibusMatchedCount, e.cibusMatchedAmount)])
    pairs.push(['סיבוס ללא נוכחות', line(e.cibusUnmatched.length, e.cibusUnmatchedAmount)])
  }

  const blocks: SheetBlock[] = [
    { kind: 'title', text: e.name, style: 'title' },
    { kind: 'title', text: `דוח נוכחות ${range.from} – ${range.to}`, style: 'subtitle' },
    { kind: 'blank' },
    { kind: 'title', text: 'סיכום החודש (מאושר בלבד)', style: 'heading' },
    { kind: 'pairs', pairs },
    { kind: 'blank' },
    { kind: 'title', text: 'משמרות', style: 'heading' },
  ]
  if (e.rows.length) {
    blocks.push({
      kind: 'table',
      columns,
      rows: shifts.rows.map((r) => {
        const { full_name: _omit, ...rest } = r
        void _omit
        return rest
      }),
      footer: [],
    })
  } else {
    blocks.push({ kind: 'title', text: 'אין דיווחי נוכחות בחודש הזה', style: 'note' })
  }

  if (e.cibusUnmatched.length) {
    blocks.push(
      { kind: 'blank' },
      { kind: 'title', text: 'משיכות סיבוס ללא דיווח נוכחות', style: 'heading' },
      {
        kind: 'table',
        columns: UNMATCHED_COLUMNS,
        rows: e.cibusUnmatched.map(unmatchedRow),
        footer: [{ values: { date: 'סה״כ', amount: e.cibusUnmatchedAmount }, style: 'bold' }],
      },
    )
  }
  return { name, blocks }
}

export function buildAttendanceWorkbook(
  report: AttendanceReport,
  range: { from: string; to: string },
  cibus?: CibusReport | null,
): WorkbookSheet[] {
  const withPay = report.can_see_pay
  const employees = summarizeEmployees(report, cibus)
  const taken = new Set<string>()
  const summaryName = sheetName('סיכום', taken)
  const perEmployee = employees.map((e) => employeeSheet(e, report, cibus, range, sheetName(e.name, taken)))

  const summaryColumns: SheetColumn[] = [
    { header: 'עובד', key: 'name', width: 22 },
    { header: 'ימי עבודה', key: 'days', width: 10 },
    { header: 'משמרות', key: 'shifts', width: 9 },
    { header: 'שעות בפועל', key: 'actual', width: 11 },
    { header: 'שעות לתשלום', key: 'paid', width: 12 },
    { header: 'שעות נוספות', key: 'overtime', width: 11 },
    ...(withPay
      ? [
          { header: 'בונוס', key: 'bonus', width: 10 },
          { header: 'לתשלום', key: 'total', width: 12 },
        ]
      : []),
    { header: 'ממתין לאישור', key: 'pending', width: 12 },
    ...(cibus
      ? [
          { header: 'סיבוס במשמרות ₪', key: 'cibus_matched', width: 15 },
          { header: 'סיבוס ללא נוכחות', key: 'cibus_unmatched_count', width: 15 },
          { header: 'סיבוס ללא נוכחות ₪', key: 'cibus_unmatched', width: 17 },
        ]
      : []),
  ]
  const summaryRows = employees.map((e) => {
    const row: Record<string, string | number> = {
      name: e.name,
      days: e.days,
      shifts: e.shifts,
      actual: e.actual,
      paid: e.paid,
      overtime: e.overtime || '',
      pending: e.pending || '',
    }
    if (withPay) {
      row.bonus = e.bonus || ''
      row.total = e.total ?? ''
    }
    if (cibus) {
      row.cibus_matched = e.cibusMatchedAmount || ''
      row.cibus_unmatched_count = e.cibusUnmatched.length || ''
      row.cibus_unmatched = e.cibusUnmatchedAmount || ''
    }
    return row
  })
  // שורת הסה״כ היא של השרת — report.totals ו-cibus.totals — ולא סכום העמודה
  const t = report.totals
  const totalRow: Record<string, string | number> = {
    name: 'סה״כ (מאושר בלבד)',
    actual: t.actual_hours,
    paid: t.paid_hours,
    overtime: t.overtime_hours,
    pending: t.pending || '',
  }
  if (withPay) {
    totalRow.bonus = t.bonus ?? ''
    totalRow.total = t.total ?? ''
  }
  if (cibus) {
    totalRow.cibus_matched = cibus.totals.matched_amount
    totalRow.cibus_unmatched_count = cibus.totals.unmatched_count
    totalRow.cibus_unmatched = cibus.totals.unmatched_amount
  }

  const summaryBlocks: SheetBlock[] = [
    { kind: 'title', text: 'דוח נוכחות — סיכום לפי עובד', style: 'title' },
    { kind: 'title', text: `${range.from} – ${range.to}`, style: 'subtitle' },
    { kind: 'blank' },
    { kind: 'table', columns: summaryColumns, rows: summaryRows, footer: [{ values: totalRow, style: 'bold' }] },
  ]
  if (cibus) {
    summaryBlocks.push({
      kind: 'title',
      text: 'סיבוס "במשמרות" = משיכה בין הכניסה ליציאה, או עד שעה לפני או אחרי. משמרת שנדחתה אינה נוכחות.',
      style: 'note',
    })
  }

  const sheets: WorkbookSheet[] = [{ name: summaryName, blocks: summaryBlocks }, ...perEmployee]

  const flat = buildAttendanceSheet(report, cibus)
  sheets.push({ name: sheetName('כל המשמרות', taken), blocks: [{ kind: 'table', ...flat }] })

  if (cibus && cibus.totals.unmatched_count > 0) {
    const all = cibus.transactions.filter((x) => !x.entry_id)
    sheets.push({
      name: sheetName('סיבוס ללא נוכחות', taken),
      blocks: [
        { kind: 'title', text: 'משיכות סיבוס ללא דיווח נוכחות', style: 'title' },
        { kind: 'title', text: `${range.from} – ${range.to}`, style: 'subtitle' },
        { kind: 'blank' },
        {
          kind: 'table',
          columns: [{ header: 'עובד', key: 'name', width: 22 }, ...UNMATCHED_COLUMNS],
          rows: all.map((x) => ({
            name: x.full_name ?? `${x.employee_name} (לא זוהה)`,
            ...unmatchedRow(x),
          })),
          footer: [{ values: { name: 'סה״כ', amount: cibus.totals.unmatched_amount }, style: 'bold' }],
        },
      ],
    })
  }
  return sheets
}

/** כתיבת החוברת. מופרד מההורדה כדי שאפשר יהיה לכתוב אותה גם בלי DOM. */
export async function writeAttendanceWorkbook(sheets: WorkbookSheet[]) {
  const ExcelJS = (await import('exceljs')).default

  const wb = new ExcelJS.Workbook()
  wb.creator = 'ViperLogistics'
  const HEAD_FILL = { type: 'pattern' as const, pattern: 'solid' as const, fgColor: { argb: 'FFE8EEF9' } }
  const thin = { style: 'thin' as const, color: { argb: 'FFD0D5DD' } }

  for (const sheet of sheets) {
    const ws = wb.addWorksheet(sheet.name, { views: [{ rightToLeft: true }] })
    const widths: number[] = []
    const widen = (i: number, w: number) => (widths[i] = Math.max(widths[i] ?? 10, w))

    for (const b of sheet.blocks) {
      if (b.kind === 'blank') {
        ws.addRow([])
      } else if (b.kind === 'title') {
        const row = ws.addRow([b.text])
        row.font =
          b.style === 'title'
            ? { bold: true, size: 15 }
            : b.style === 'heading'
              ? { bold: true, size: 12, color: { argb: 'FF1D4ED8' } }
              : b.style === 'subtitle'
                ? { color: { argb: 'FF667085' } }
                : { italic: true, color: { argb: 'FF667085' } }
      } else if (b.kind === 'pairs') {
        for (const [label, value] of b.pairs) {
          const row = ws.addRow([label, value])
          row.getCell(1).font = { bold: true }
          row.getCell(1).fill = HEAD_FILL
          row.getCell(1).border = { top: thin, bottom: thin, left: thin, right: thin }
          row.getCell(2).border = { top: thin, bottom: thin, left: thin, right: thin }
          row.getCell(2).alignment = { horizontal: 'right' }
          widen(0, 22)
          widen(1, 22)
        }
      } else {
        const head = ws.addRow(b.columns.map((c) => c.header))
        head.font = { bold: true }
        head.eachCell((cell) => {
          cell.fill = HEAD_FILL
          cell.border = { bottom: thin }
        })
        b.columns.forEach((c, i) => widen(i, c.width))
        for (const r of b.rows) ws.addRow(b.columns.map((c) => r[c.key] ?? ''))
        for (const f of b.footer) {
          const row = ws.addRow(b.columns.map((c) => f.values[c.key] ?? ''))
          row.font = f.style === 'bold' ? { bold: true } : { italic: true }
          row.eachCell((cell) => (cell.border = { top: thin }))
        }
      }
    }
    widths.forEach((w, i) => (ws.getColumn(i + 1).width = w))
  }
  return wb.xlsx.writeBuffer()
}

export async function exportAttendanceReport(
  report: AttendanceReport,
  range: { from: string; to: string },
  cibus?: CibusReport | null,
) {
  const buf = await writeAttendanceWorkbook(buildAttendanceWorkbook(report, range, cibus))
  const blob = new Blob([buf], {
    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `attendance-${range.from}_${range.to}.xlsx`
  a.click()
  URL.revokeObjectURL(url)
}
