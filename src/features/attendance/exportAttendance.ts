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
 */
import type { AttendanceReport, AttendanceReportRow } from '../../types/domain'
import { STATUS_LABELS, WORK_SITE_LABELS, flagLabel } from './shiftFormat'

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

export function buildAttendanceSheet(report: AttendanceReport): SheetPlan {
  const withPay = report.can_see_pay

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
    { header: 'יציאה מ', key: 'work_site', width: 10 },
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
      source: SOURCE_LABELS[r.source] ?? r.source,
      status: STATUS_LABELS[r.status] ?? r.status,
      flags: (r.flags ?? []).map(flagLabel).join(', '),
      employee_note: r.employee_note ?? '',
      manager_note: r.manager_note ?? '',
    }
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

export async function exportAttendanceReport(
  report: AttendanceReport,
  range: { from: string; to: string },
) {
  const ExcelJS = (await import('exceljs')).default
  const plan = buildAttendanceSheet(report)

  const wb = new ExcelJS.Workbook()
  wb.creator = 'ViperLogistics'
  const ws = wb.addWorksheet('נוכחות', { views: [{ rightToLeft: true, state: 'frozen', ySplit: 1 }] })
  ws.columns = plan.columns
  ws.getRow(1).font = { bold: true }

  for (const r of plan.rows) ws.addRow(r)
  ws.addRow({})
  for (const f of plan.footer) {
    const row = ws.addRow(f.values)
    row.font = f.style === 'bold' ? { bold: true } : { italic: true }
  }

  const buf = await wb.xlsx.writeBuffer()
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
