import { describe, expect, it } from 'vitest'
import { buildAttendanceSheet, buildAttendanceWorkbook, planHasMoney, sheetName } from './exportAttendance'
import type { SheetBlock } from './exportAttendance'
import type { AttendanceReport, AttendanceReportRow, CibusReport, CibusTransaction } from '../../types/domain'

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
    bonus_note: null,
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
      corrections: 0,
      bonus: null,
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

  // הבונוס הוא כסף, ולכן הוא נופל תחת אותה הבטחה: השרת משמיט אותו מהשורה
  // למי שאינו רשאי לראות סכומים, והתוכנית לא מחזירה אותו דרך הדלת האחורית.
  it('omits the bonus for a reader without attendance.view_pay', () => {
    const plan = buildAttendanceSheet(
      report({ can_see_pay: false, rows: [row({ pay: { ...row().pay, bonus: 250, total: 650 } })] }),
    )
    expect(planHasMoney(plan)).toBe(false)
    expect(plan.columns.map((c) => c.key)).not.toContain('bonus')
    expect(JSON.stringify(plan)).not.toContain('250')
  })

  it('writes the bonus in its own column, and inside the total, once money is allowed', () => {
    const plan = buildAttendanceSheet(
      report({
        can_see_pay: true,
        rows: [row({ pay: { ...row().pay, hourly_rate: 50, bonus: 250, total: 650 } })],
        totals: { ...report().totals, bonus: 250, total: 650 },
      }),
    )
    expect(plan.columns.map((c) => c.key)).toContain('bonus')
    expect(plan.rows[0]!.bonus).toBe(250)
    // הבונוס כלול בסך ואינו נוסף עליו — 8 שעות × 50 ועוד 250
    expect(plan.rows[0]!.total).toBe(650)
    expect(plan.footer[0]!.values.bonus).toBe(250)
    expect(plan.footer[0]!.values.total).toBe(650)
  })

  it('takes the totals from the server rather than summing the rows', () => {
    // שתי שורות של 8 שעות, אבל השרת אומר 8 — כי אחת ממתינה לאישור
    const plan = buildAttendanceSheet(
      report({
        rows: [row(), row({ id: 'r2', status: 'pending' })],
        totals: { entries: 2, pending: 1, pending_hours: 8, actual_hours: 8, paid_hours: 8, overtime_hours: 0, corrections: 0, bonus: null, total: null },
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

// ===== 0210: סיבוס, וגיליון לכל עובד =========================================

const RANGE = { from: '2026-03-01', to: '2026-03-31' }

function txn(over: Partial<CibusTransaction> = {}): CibusTransaction {
  return {
    id: 'c1',
    txn_no: 1,
    occurred_at: '2026-03-09T10:00:00.000Z',
    link_key: 'u:1',
    employee_name: 'עובד',
    profile_id: 'p1',
    full_name: 'עובד',
    merchant: 'מסעדה',
    deal_type: 'ישיבה',
    amount: 29.9,
    entry_id: 'r1',
    ...over,
  }
}

function cibus(transactions: CibusTransaction[], over: Partial<CibusReport> = {}): CibusReport {
  return {
    transactions,
    employees: [
      {
        profile_id: 'p1',
        full_name: 'עובד',
        count: 2,
        amount: 59.9,
        matched_count: 1,
        matched_amount: 29.9,
        unmatched_count: 1,
        unmatched_amount: 30,
      },
    ],
    unlinked: [],
    totals: {
      count: 2,
      amount: 59.9,
      matched_count: 1,
      matched_amount: 29.9,
      unmatched_count: 1,
      unmatched_amount: 30,
      unlinked_count: 0,
      unlinked_amount: 0,
    },
    last_import_at: null,
    ...over,
  }
}

const twoTxns = () => [txn(), txn({ id: 'c2', txn_no: 2, entry_id: null, amount: 30, merchant: 'פיצה' })]

const tables = (blocks: SheetBlock[]) => blocks.filter((b): b is Extract<SheetBlock, { kind: 'table' }> => b.kind === 'table')

describe('buildAttendanceSheet with cibus', () => {
  it('adds no cibus column when nothing was imported', () => {
    expect(buildAttendanceSheet(report()).columns.map((c) => c.key)).not.toContain('cibus')
  })

  it('writes what was drawn, where, and how much next to the shift', () => {
    const plan = buildAttendanceSheet(report(), cibus(twoTxns()))
    expect(plan.columns.map((c) => c.key)).toEqual(expect.arrayContaining(['cibus', 'cibus_amount']))
    expect(String(plan.rows[0]!.cibus)).toContain('מסעדה')
    expect(plan.rows[0]!.cibus_amount).toBe(29.9)
    // המשיכה בלי נוכחות אינה מוצמדת לאף משמרת
    expect(String(plan.rows[0]!.cibus)).not.toContain('פיצה')
  })
})

describe('buildAttendanceWorkbook', () => {
  const two = () =>
    report({
      rows: [
        row(),
        row({ id: 'r2', work_date: '2026-03-10', clock_in_at: '2026-03-10T06:00:00.000Z' }),
        row({ id: 'r3', profile_id: 'p2', full_name: 'אבי', status: 'pending' }),
      ],
    })

  it('has a summary sheet, a sheet per employee, and the flat sheet', () => {
    const names = buildAttendanceWorkbook(two(), RANGE).map((s) => s.name)
    expect(names).toEqual(['סיכום', 'אבי', 'עובד', 'כל המשמרות'])
  })

  it('summarizes each employee from approved rows only', () => {
    const [summary] = buildAttendanceWorkbook(two(), RANGE)
    const rows = tables(summary!.blocks)[0]!.rows
    expect(rows.find((r) => r.name === 'עובד')).toMatchObject({ days: 2, shifts: 2, actual: 16, paid: 16 })
    // אבי ממתין לאישור: אין לו שעות מאושרות, אבל הוא בסיכום
    expect(rows.find((r) => r.name === 'אבי')).toMatchObject({ shifts: 0, actual: 0, pending: 1 })
  })

  it('takes the summary total line from the server', () => {
    const [summary] = buildAttendanceWorkbook(two(), RANGE)
    expect(tables(summary!.blocks)[0]!.footer[0]!.values.actual).toBe(8)
  })

  it('opens each employee sheet with the month summary, then the shifts', () => {
    const sheet = buildAttendanceWorkbook(two(), RANGE).find((s) => s.name === 'עובד')!
    const kinds = sheet.blocks.map((b) => b.kind)
    expect(kinds.indexOf('pairs')).toBeLessThan(kinds.indexOf('table'))
    const shifts = tables(sheet.blocks)[0]!
    expect(shifts.rows).toHaveLength(2)
    expect(shifts.columns.map((c) => c.key)).not.toContain('full_name')
  })

  it('writes no money anywhere for a reader without pay', () => {
    const wb = buildAttendanceWorkbook(
      report({ can_see_pay: false, rows: [row({ pay: { ...row().pay, hourly_rate: 50, bonus: 250, total: 650 } })] }),
      RANGE,
    )
    const text = JSON.stringify(wb)
    expect(text).not.toContain('650')
    expect(text).not.toContain('250')
    expect(text).not.toContain('סה״כ לתשלום')
    expect(text).not.toContain('"key":"total"')
    expect(text).not.toContain('"key":"bonus"')
  })

  it('writes each employee’s pay once the server allows it', () => {
    const wb = buildAttendanceWorkbook(
      report({
        can_see_pay: true,
        rows: [row({ pay: { ...row().pay, hourly_rate: 50, total: 400 } })],
        totals: { ...report().totals, total: 400 },
      }),
      RANGE,
    )
    const sheet = wb.find((s) => s.name === 'עובד')!
    const pairs = sheet.blocks.find((b) => b.kind === 'pairs') as Extract<SheetBlock, { kind: 'pairs' }>
    expect(pairs.pairs).toContainEqual(['סה״כ לתשלום', 400])
  })

  it('lists cibus without attendance on the employee sheet and in its own sheet', () => {
    const wb = buildAttendanceWorkbook(report(), RANGE, cibus(twoTxns()))
    expect(wb.map((s) => s.name)).toContain('סיבוס ללא נוכחות')
    const sheet = wb.find((s) => s.name === 'עובד')!
    const unmatched = tables(sheet.blocks)[1]!
    expect(unmatched.rows).toHaveLength(1)
    expect(unmatched.rows[0]!.merchant).toBe('פיצה')
    expect(unmatched.footer[0]!.values.amount).toBe(30)
  })

  it('gives a sheet to someone who drew cibus with no attendance at all', () => {
    const wb = buildAttendanceWorkbook(
      report({ rows: [] }),
      RANGE,
      cibus([txn({ entry_id: null, profile_id: 'p9', full_name: 'רק סיבוס' })], {
        employees: [
          {
            profile_id: 'p9',
            full_name: 'רק סיבוס',
            count: 1,
            amount: 29.9,
            matched_count: 0,
            matched_amount: 0,
            unmatched_count: 1,
            unmatched_amount: 29.9,
          },
        ],
      }),
    )
    expect(wb.map((s) => s.name)).toContain('רק סיבוס')
  })

  it('names an unidentified cibus user as such', () => {
    const wb = buildAttendanceWorkbook(
      report(),
      RANGE,
      cibus([...twoTxns(), txn({ id: 'c3', entry_id: null, profile_id: null, full_name: null, employee_name: 'זר' })]),
    )
    const sheet = wb.find((s) => s.name === 'סיבוס ללא נוכחות')!
    expect(tables(sheet.blocks)[0]!.rows.map((r) => r.name)).toContain('זר (לא זוהה)')
  })
})

describe('sheetName', () => {
  it('keeps names legal and unique', () => {
    const taken = new Set<string>()
    expect(sheetName('סיכום', taken)).toBe('סיכום')
    expect(sheetName('סיכום', taken)).toBe('סיכום (2)')
    expect(sheetName('a/b:c', taken)).toBe('a b c')
    expect(sheetName('א'.repeat(40), taken)).toHaveLength(31)
  })
})
