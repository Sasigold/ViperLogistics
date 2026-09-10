/**
 * ייצוא סיכום המשימות של הקבלן ל-Excel (0172).
 *
 * הקובץ הזה הוא מה שהקבלן שולח להנהלת חשבונות, ולכן הוא נבנה על אותם שני
 * כללים של `exportAttendance`:
 *
 * 1. **הסכומים הם מה שהשרת החזיר.** ‏`contractor_tasks` נושא את המחיר,
 *    את מה ששולם ואת פירוט הקנסות; חישוב שני בדפדפן היה נפרד מהראשון ברגע
 *    שמישהו יערוך תעריף.
 * 2. **עמודות כסף נכתבות רק כשהן חזרו.** קבלן בלי `portal.view_financials`
 *    מקבל את רשימת המשימות שלו בלי אף עמודת סכום — ולא עמודה מלאה מקפים,
 *    שנקראת כמו טעות.
 *
 * בניית הגיליון מופרדת מהכתיבה שלו כדי שהכלל השני יהיה ניתן לבדיקה בלי
 * ‏ExcelJS ובלי DOM.
 */
import type { PortalTaskRow } from '../../types/domain'
import { paidAmountOf, penaltyOf, summarize, taskLabel } from './portalTasks'

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

const MONEY_KEYS = ['price', 'penalty', 'paid_amount'] as const

/** ‏true כשהשרת החזיר מחיר על שורה כלשהי — ואז יש עמודות כסף. */
export function hasMoney(rows: PortalTaskRow[]): boolean {
  return rows.some((r) => r.price != null)
}

export function buildPortalTasksSheet(rows: PortalTaskRow[]): SheetPlan {
  const withMoney = hasMoney(rows)

  const columns: SheetColumn[] = [
    { header: 'תאריך', key: 'task_date', width: 12 },
    { header: 'תאריך אירוע', key: 'event_date', width: 12 },
    { header: 'מספר אירוע', key: 'event_number', width: 14 },
    { header: 'משימה', key: 'task', width: 24 },
    { header: 'לקוח', key: 'customer', width: 20 },
    { header: 'לקוח סופי', key: 'end_client', width: 20 },
    { header: 'מיקום', key: 'location', width: 30 },
    { header: 'עובדים', key: 'worker_count', width: 9 },
    { header: 'סטטוס', key: 'status', width: 14 },
    ...(withMoney
      ? [
          { header: 'מחיר', key: 'price', width: 12 },
          // עמודה משלו ולא בלועה במחיר: קנס הוא ההפרש בין מה שהקבלן ציפה לו
          // לבין מה שנרשם, וזו השאלה הראשונה שהוא ישאל על השורה.
          { header: 'מזה קנסות', key: 'penalty', width: 12 },
          { header: 'שולם', key: 'paid_amount', width: 12 },
          { header: 'תאריך תשלום', key: 'paid_at', width: 14 },
        ]
      : []),
  ]

  const sheetRows = rows.map((r) => {
    const row: Record<string, string | number> = {
      task_date: r.task_date,
      event_date: r.event_date ?? '',
      event_number: r.event_number ?? '',
      task: taskLabel(r),
      customer: r.customer_name ?? '',
      end_client: r.end_client_name ?? '',
      location: r.location_text ?? '',
      worker_count: r.worker_count || '',
      status: r.status_name,
    }
    if (withMoney) {
      row.price = r.price ?? ''
      // אפס נכתב ריק ולא כ-0: עמודה מלאה באפסים קוראת כמו נתון, וקנס הוא
      // החריג ולא הכלל.
      row.penalty = penaltyOf(r) || ''
      row.paid_amount = paidAmountOf(r) ?? ''
      row.paid_at = r.paid_at ? r.paid_at.slice(0, 10) : ''
    }
    return row
  })

  const t = summarize(rows)
  const footer: SheetPlan['footer'] = [
    {
      values: withMoney
        ? {
            task_date: 'סה״כ',
            task: `${t.tasks} משימות`,
            price: t.expected,
            penalty: t.penalties || '',
            paid_amount: t.paid,
          }
        : { task_date: 'סה״כ', task: `${t.tasks} משימות` },
      style: 'bold',
    },
  ]
  if (withMoney) {
    footer.push({
      values: { task_date: 'יתרה לתשלום', price: t.unpaid },
      style: 'italic',
    })
  }
  if (t.unpriced > 0) {
    footer.push({
      values: { task_date: `ללא מחיר: ${t.unpriced} משימות` },
      style: 'italic',
    })
  }

  return { columns, rows: sheetRows, footer }
}

/** ‏true אם התוכנית מכילה עמודת כסף כלשהי — קיים בשביל הבדיקה. */
export function planHasMoney(plan: SheetPlan): boolean {
  const keys = new Set(plan.columns.map((c) => c.key))
  if (MONEY_KEYS.some((k) => keys.has(k))) return true
  return [...plan.rows, ...plan.footer.map((f) => f.values)].some((r) =>
    MONEY_KEYS.some((k) => k in r),
  )
}

export async function exportPortalTasks(rows: PortalTaskRow[], range: { from: string; to: string }) {
  const ExcelJS = (await import('exceljs')).default
  const plan = buildPortalTasksSheet(rows)

  const wb = new ExcelJS.Workbook()
  wb.creator = 'ViperLogistics'
  const ws = wb.addWorksheet('משימות', { views: [{ rightToLeft: true, state: 'frozen', ySplit: 1 }] })
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
  a.download = `contractor-tasks-${range.from || 'start'}_${range.to || 'end'}.xlsx`
  a.click()
  URL.revokeObjectURL(url)
}
