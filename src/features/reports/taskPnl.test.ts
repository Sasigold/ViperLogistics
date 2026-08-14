import { describe, expect, it } from 'vitest'
import { buildTaskPnlExport, taskPnlLabel } from './taskPnl'
import type { TaskPnlResult, TaskPnlRow } from './taskPnl'

const range = { from: '2026-01-01', to: '2026-01-31' }

const row = (over: Partial<TaskPnlRow>): TaskPnlRow => ({
  task_id: 't1',
  task_date: '2026-01-05',
  title: 'הקמה אולם',
  task_type_name: 'הקמה',
  task_type_code: 'setup',
  status_name: 'משובץ',
  status_color: '#8b5cf6',
  event_id: 'e1',
  event_number: 'A-1',
  end_client_name: null,
  customer_id: 'c1',
  customer_name: 'אקמי',
  customer_color: '#f00',
  contractor_name: null,
  revenue: 1000,
  price_is_manual: false,
  unpriced: false,
  contractor_cost: 0,
  payroll: 150,
  payroll_with_employer: 195,
  cost_total: 195,
  gross: 805,
  pct: 80.5,
  planned_workers: 2,
  planned_hours: 6,
  planned_worker_hours: 12,
  actual_workers: 1,
  actual_hours: 3,
  hours_delta: -9,
  shifts: 1,
  unrated_shifts: 0,
  no_attendance: false,
  ...over,
})

const result: TaskPnlResult = {
  rows: [
    row({}),
    row({ task_id: 't2', title: null, task_type_name: 'פירוק', revenue: 0, gross: -50, pct: null, customer_name: null }),
  ],
  summary: {
    tasks: 2,
    revenue: 1000,
    contractor: 0,
    payroll: 150,
    payroll_with_employer: 195,
    employer_pct: 30,
    cost_total: 245,
    gross: 755,
    pct: 75.5,
    planned_worker_hours: 12,
    actual_hours: 3,
  },
  meta: { estimated: true, unallocated: 350, truncated: true, scope_note: 'הערה', unrated_shifts: 1 },
}

describe('buildTaskPnlExport', () => {
  it('summary sheet then detail sheet, both from server numbers', () => {
    const plan = buildTaskPnlExport(range, result)
    expect(plan.sheets.map((s) => s.title)).toEqual(['רווחיות משימות — סיכום', 'רווחיות לפי משימה'])
    expect(plan.sheets[0].rows).toContainEqual(['רווח גולמי', 755])
    // the employer percentage is named in the label, not applied in the client
    expect(plan.sheets[0].rows).toContainEqual(['שכר כולל נטל מעביד (30%)', 195])
  })

  it('per-row gross is the server value, never recomputed from the parts', () => {
    const plan = buildTaskPnlExport(range, result)
    // 1000 - 195 = 805 happens to hold, but the row is asserted verbatim so a
    // client-side subtraction sneaking in would have to reproduce it exactly
    expect(plan.sheets[1].rows[0]).toEqual([
      'הקמה אולם', '2026-01-05', 'אקמי', 'הקמה', 1000, 0, 150, 195, 195, 805, 80.5, 12, 3, -9, 2, 1,
    ])
  })

  it('a null pct exports as empty, not as zero, and a missing customer as blank', () => {
    const plan = buildTaskPnlExport(range, result)
    const r = plan.sheets[1].rows[1]
    expect(r[2]).toBe('')
    expect(r[10]).toBe('')
  })

  it('an untitled task falls back to its type, not to an empty cell', () => {
    expect(taskPnlLabel(row({ title: null, task_type_name: 'פירוק' }))).toBe('פירוק')
    expect(taskPnlLabel(row({ title: null, task_type_name: null }))).toBe('משימה')
  })

  it('the caveats travel with both sheets', () => {
    const plan = buildTaskPnlExport(range, result)
    for (const sheet of plan.sheets) {
      const flat = sheet.rows.map((r) => String(r[0]))
      expect(flat).toContain('מוצגות השורות המובילות בלבד')
      expect(flat).toContain('הערה')
      expect(flat.some((x) => x.startsWith('משוער'))).toBe(true)
    }
  })

  it('denied → an empty plan, no sheets and no zeros', () => {
    expect(buildTaskPnlExport(range, { rows: null, meta: { denied: true } }).sheets).toEqual([])
  })
})
