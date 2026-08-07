import { describe, expect, it } from 'vitest'
import { buildAttendanceSheet, planHasMoney } from './exportAttendance'
import type { AttendanceReport, AttendanceReportRow } from '../../types/domain'

/**
 * הקובץ הזה יוצא מהמערכת ומגיע להנהלת חשבונות, ולכן שתי ההבטחות שבו נבדקות
 * כאן: שאין בו כסף למי שאינו רשאי לראות כסף, ושהסיכום הוא זה שהשרת חישב.
 */

function row(over: Partial<AttendanceReportRow> = {}): AttendanceReportRow {
  return {
    id: 'r1',
    profile_id: 'p1',
    full_name: 'עובד',
    contractor_id: null,
    work_date: '2026-03-09',
    seq: 1,
    shift_start: null,
    shift_end: null,
    planned_hours: 8,
    work_site: 'field',
    task_ids: [],
    clock_in_at: '2026-03-09T06:00:00.000Z',
    clock_out_at: '2026-03-09T14:00:00.000Z',
    actual_hours: 8,
    in_distance_m: null,
    out_distance_m: null,
    raw_clock_in_at: null,
    raw_clock_out_at: null,
    source: 'clock',
    status: 'approved',
    reviewed_at: null,
    flags: [],
    employee_note: null,
    manager_note: null,
    edited_at: null,
    pay: { version: 1, paid_hours: 8, worked_hours: 8, base_hours: 8, overtime_hours: 0, topup_hours: 0, is_rest_day: false },
    ...over,
  } as AttendanceReportRow
}

function report(over: Partial<AttendanceReport> = {}): AttendanceReport {
  return {
    rows: [row()],
    can_see_pay: false,
    totals: {
      entries: 1,
      pending: 0,
      pending_hours: 0,
      actual_hours: 8,
      paid_hours: 8,
      overtime_hours: 0,
      total: null,
    },
    ...over,
  } as AttendanceReport
}

describe('buildAttendanceSheet', () => {
  it('writes no money column for a reader without attendance.view_pay', () => {
    const plan = buildAttendanceSheet(report())
    expect(planHasMoney(plan)).toBe(false)
    expect(plan.columns.map((c) => c.key)).not.toContain('total')
    expect(plan.columns.map((c) => c.key)).not.toContain('hourly_rate')
  })

  // רכז משמרות רואה שעות בלי שכר. השעות חייבות להישאר.
  it('still writes hours for that reader', () => {
    const plan = buildAttendanceSheet(report())
    expect(plan.columns.map((c) => c.key)).toContain('paid_hours')
    expect(plan.rows[0]!.actual_hours).toBe(8)
  })

  it('writes money once the server says the reader may see it', () => {
    const plan = buildAttendanceSheet(
      report({
        can_see_pay: true,
        rows: [row({ pay: { ...row().pay, hourly_rate: 50, total: 400 } })],
        totals: { ...report().totals, total: 400 },
      }),
    )
    expect(planHasMoney(plan)).toBe(true)
    expect(plan.rows[0]!.total).toBe(400)
  })

  // אילו can_see_pay היה false אבל השרת בכל זאת החזיר סכום, אסור שהוא ידלוף
  it('omits money the server left on the row when it said the reader may not see it', () => {
    const plan = buildAttendanceSheet(
      report({ can_see_pay: false, rows: [row({ pay: { ...row().pay, hourly_rate: 50, total: 400 } })] }),
    )
    expect(planHasMoney(plan)).toBe(false)
    expect(JSON.stringify(plan)).not.toContain('400')
  })

  it('takes the totals from the server rather than summing the rows', () => {
    // שתי שורות של 8 שעות, אבל השרת אומר 8 — כי אחת ממתינה לאישור
    const plan = buildAttendanceSheet(
      report({
        rows: [row(), row({ id: 'r2', status: 'pending' })],
        totals: { entries: 2, pending: 1, pending_hours: 8, actual_hours: 8, paid_hours: 8, overtime_hours: 0, total: null },
      }),
    )
    expect(plan.footer[0]!.values.actual_hours).toBe(8)
  })

  it('says out loud that the total counts approved rows only', () => {
    const plan = buildAttendanceSheet(report())
    expect(String(plan.footer[0]!.values.full_name)).toContain('מאושר בלבד')
  })

  it('adds a pending line when something is waiting, and not when nothing is', () => {
    expect(buildAttendanceSheet(report()).footer).toHaveLength(1)
    const withPending = buildAttendanceSheet(
      report({ totals: { ...report().totals, pending: 2, pending_hours: 11 } }),
    )
    expect(withPending.footer).toHaveLength(2)
    expect(String(withPending.footer[1]!.values.full_name)).toContain('2')
  })

  it('produces one row per entry', () => {
    const plan = buildAttendanceSheet(report({ rows: [row(), row({ id: 'r2' })] }))
    expect(plan.rows).toHaveLength(2)
  })
})
