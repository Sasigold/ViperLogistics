import { exportNotices, sheetName } from '../dashboard/exportDashboard'
import type { ExportPlan, ExportSheet } from '../dashboard/exportDashboard'
import type { DateRange } from '../dashboard/dashboardRange'

/**
 * רווחיות פר-משימה — הטיפוסים של תשובת `task_pnl` (0070) ובניית הייצוא שלה.
 * טהור, כמו כל בוני הייצוא: **כל מספר בקובץ הוא מספר שרת.** החיסור, האחוז,
 * נטל המעביד ופער השעות כולם חושבו ב-RPC, והקובץ רק מסדר אותם.
 *
 * שתי עמודות שקל לפרש לא נכון, ולכן הן נושאות את הבסיס בכותרת: ההכנסה היא
 * המחיר **שהוזמן** (מחושב מהתכנון), והעלות נמדדת מהשעות **שהוחתמו בפועל**.
 */

export interface TaskPnlRow {
  task_id: string
  task_date: string
  title: string | null
  task_type_name: string | null
  task_type_code: string | null
  status_name: string | null
  status_color: string | null
  event_id: string | null
  event_number: string | null
  end_client_name: string | null
  customer_id: string | null
  /** null כשאין `customers.view` — השדה נשמט, הדוח לא נחסם */
  customer_name: string | null
  customer_color: string | null
  contractor_name: string | null
  revenue: number
  price_is_manual: boolean
  unpriced: boolean
  contractor_cost: number
  payroll: number
  payroll_with_employer: number
  cost_total: number
  gross: number
  /** null כשאין הכנסה — אחוז מאפס הוא שקר */
  pct: number | null
  planned_workers: number | null
  planned_hours: number | null
  planned_worker_hours: number
  actual_workers: number
  actual_hours: number
  hours_delta: number
  shifts: number
  unrated_shifts: number
  no_attendance: boolean
}

export interface TaskPnlSummary {
  tasks: number
  revenue: number
  contractor: number
  payroll: number
  payroll_with_employer: number
  employer_pct: number
  cost_total: number
  gross: number
  pct: number | null
  planned_worker_hours: number
  actual_hours: number
}

export interface TaskPnlMeta {
  revenue_basis?: string
  cost_basis?: string
  estimated?: boolean
  excludes_overhead?: boolean
  employer_pct?: number | null
  allocated?: number | null
  unallocated?: number | null
  unrated_shifts?: number | null
  tasks_no_attendance?: number | null
  unpriced_tasks?: number | null
  truncated?: boolean
  scope_note?: string | null
  denied?: boolean
}

export interface TaskPnlResult {
  /** null = "לא בשבילך" — מוסכמת המנוע */
  rows: TaskPnlRow[] | null
  summary?: TaskPnlSummary
  meta: TaskPnlMeta
}

export const TASK_PNL_COLUMNS = [
  'משימה',
  'תאריך',
  'לקוח',
  'סוג',
  'הכנסה (לפי התכנון)',
  'עלות קבלן',
  'שכר משויך (משוער)',
  'שכר כולל נטל מעביד',
  'עלות כוללת',
  'רווח גולמי',
  '% רווח',
  'שעות-עובד מתוכננות',
  'שעות שהוחתמו',
  'פער שעות',
  'עובדים מתוכננים',
  'עובדים בפועל',
] as const

/** התווית שהמסך והקובץ מסכימים עליה לשורה אחת */
export function taskPnlLabel(r: TaskPnlRow): string {
  return r.title || r.task_type_name || 'משימה'
}

export function buildTaskPnlExport(range: DateRange, result: TaskPnlResult): ExportPlan {
  if (result.rows === null || result.meta.denied) return { range, sheets: [] }

  const taken = new Set<string>()
  const sheets: ExportSheet[] = []
  const notices = exportNotices(result.meta as Record<string, unknown>)

  const s = result.summary
  if (s) {
    const rows: (string | number)[][] = [
      ['משימות', s.tasks],
      ['הכנסה (לפי התכנון)', s.revenue],
      ['עלות קבלנים', s.contractor],
      ['שכר משויך', s.payroll],
      [`שכר כולל נטל מעביד (${s.employer_pct}%)`, s.payroll_with_employer],
      ['עלות כוללת', s.cost_total],
      ['רווח גולמי', s.gross],
      ['% רווח', s.pct ?? ''],
      ['שעות-עובד מתוכננות', s.planned_worker_hours],
      ['שעות שהוחתמו', s.actual_hours],
    ]
    for (const note of notices) rows.push([note, ''])
    sheets.push({
      name: sheetName('סיכום', taken),
      title: 'רווחיות משימות — סיכום',
      columns: ['שדה', 'ערך'],
      rows,
    })
  }

  const rows: (string | number)[][] = result.rows.map((r) => [
    taskPnlLabel(r),
    r.task_date,
    r.customer_name ?? '',
    r.task_type_name ?? '',
    r.revenue,
    r.contractor_cost,
    r.payroll,
    r.payroll_with_employer,
    r.cost_total,
    r.gross,
    r.pct ?? '',
    r.planned_worker_hours,
    r.actual_hours,
    r.hours_delta,
    r.planned_workers ?? '',
    r.actual_workers,
  ])
  for (const note of notices) rows.push([note])
  sheets.push({
    name: sheetName('רווחיות משימות', taken),
    title: 'רווחיות לפי משימה',
    columns: [...TASK_PNL_COLUMNS],
    rows,
  })

  return { range, sheets }
}
