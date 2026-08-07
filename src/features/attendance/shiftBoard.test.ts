import { describe, expect, it } from 'vitest'
import {
  applyBoardFilters,
  boardDays,
  boardRange,
  boardStep,
  cellKey,
  emptyBoardFilters,
  indexShifts,
  rangeTotals,
  activeBoardFilters,
  STAFF_ONLY,
} from './shiftBoard'
import type { PlannedShift, ShiftRosterEntry, WorkSite } from '../../types/domain'

/** 2026-08-12 הוא יום רביעי; השבוע שלו הוא 09/08 (ראשון) עד 15/08 (שבת). */
const WED = new Date(2026, 7, 12)

function shift(over: Partial<PlannedShift> & { profile_id: string; work_date: string }): PlannedShift {
  return {
    seq: 1,
    shift_start: `${over.work_date}T07:00:00+03:00`,
    shift_end: `${over.work_date}T15:00:00+03:00`,
    planned_hours: 8,
    work_site: 'field' as WorkSite,
    task_ids: ['t1'],
    first_task_id: 't1',
    last_task_id: 't1',
    start_lat: null,
    start_lng: null,
    end_lat: null,
    end_lng: null,
    travel_hours: 0,
    label: 'הקמה',
    customer_id: 'c1',
    customer_color: '#3563f0',
    warehouse_id: null,
    warehouse_name: null,
    ...over,
  }
}

function person(over: Partial<ShiftRosterEntry> & { id: string; full_name: string }): ShiftRosterEntry {
  return {
    contractor_id: null,
    contractor_name: null,
    is_contractor: false,
    is_active: true,
    ...over,
  }
}

describe('boardRange', () => {
  it('שבוע נצמד לראשון–שבת ולא לשבעה ימים מהעוגן', () => {
    expect(boardRange(WED, 'week')).toEqual({ from: '2026-08-09', to: '2026-08-15' })
  })

  it('וגם כשהעוגן הוא כבר יום ראשון', () => {
    expect(boardRange(new Date(2026, 7, 9), 'week')).toEqual({ from: '2026-08-09', to: '2026-08-15' })
  })

  it('3 ימים מתחיל דווקא בעוגן עצמו', () => {
    expect(boardRange(WED, 'three')).toEqual({ from: '2026-08-12', to: '2026-08-14' })
  })

  it('והצעד קדימה הוא ברוחב התצוגה', () => {
    expect(boardStep('week')).toBe(7)
    expect(boardStep('three')).toBe(3)
  })
})

describe('boardDays', () => {
  it('מחזיר 7 ימים לשבוע ו-3 לשלושה', () => {
    expect(boardDays('2026-08-09', '2026-08-15')).toHaveLength(7)
    expect(boardDays('2026-08-12', '2026-08-14')).toHaveLength(3)
  })

  it('כולל את שני הקצוות', () => {
    const days = boardDays('2026-08-12', '2026-08-14')
    expect(days[0].getDate()).toBe(12)
    expect(days[2].getDate()).toBe(14)
  })
})

describe('indexShifts', () => {
  it('תולה משמרת על work_date שלה', () => {
    const idx = indexShifts([shift({ profile_id: 'p1', work_date: '2026-08-12' })])
    expect(idx.get(cellKey('p1', '2026-08-12'))).toHaveLength(1)
  })

  it('משמרת חוצת חצות נשארת ביום שבו התחילה', () => {
    const idx = indexShifts([
      shift({
        profile_id: 'p1',
        work_date: '2026-08-12',
        shift_start: '2026-08-12T22:00:00+03:00',
        shift_end: '2026-08-13T02:00:00+03:00',
      }),
    ])
    expect(idx.get(cellKey('p1', '2026-08-12'))).toHaveLength(1)
    expect(idx.get(cellKey('p1', '2026-08-13'))).toBeUndefined()
  })

  it('שתי משמרות באותו יום חוזרות ממוינות לפי seq', () => {
    const idx = indexShifts([
      shift({ profile_id: 'p1', work_date: '2026-08-12', seq: 2, label: 'שנייה' }),
      shift({ profile_id: 'p1', work_date: '2026-08-12', seq: 1, label: 'ראשונה' }),
    ])
    expect(idx.get(cellKey('p1', '2026-08-12'))?.map((s) => s.label)).toEqual(['ראשונה', 'שנייה'])
  })

  it('ומשמרות של אנשים שונים אינן מתערבבות', () => {
    const idx = indexShifts([
      shift({ profile_id: 'p1', work_date: '2026-08-12' }),
      shift({ profile_id: 'p2', work_date: '2026-08-12' }),
    ])
    expect(idx.get(cellKey('p1', '2026-08-12'))).toHaveLength(1)
    expect(idx.get(cellKey('p2', '2026-08-12'))).toHaveLength(1)
  })
})

describe('applyBoardFilters', () => {
  const roster = [
    person({ id: 'p1', full_name: 'דני כהן' }),
    person({ id: 'p2', full_name: 'יוסי לוי' }),
    person({ id: 'p3', full_name: 'מאיה בר', contractor_id: 'k1', contractor_name: 'קבלן א', is_contractor: true }),
  ]
  const shifts = [
    shift({ profile_id: 'p1', work_date: '2026-08-12', customer_id: 'c1' }),
    shift({ profile_id: 'p2', work_date: '2026-08-12', customer_id: 'c2', work_site: 'warehouse' }),
  ]

  it('בלי מסננים: מי שיש לו משמרת בשורות, והשאר במדף', () => {
    const r = applyBoardFilters(roster, shifts, emptyBoardFilters)
    expect(r.rows.map((x) => x.id)).toEqual(['p1', 'p2'])
    expect(r.empty.map((x) => x.id)).toEqual(['p3'])
  })

  it('חיפוש בשם מצמצם שורות', () => {
    const r = applyBoardFilters(roster, shifts, { ...emptyBoardFilters, q: 'יוסי' })
    expect(r.rows.map((x) => x.id)).toEqual(['p2'])
    expect(r.empty).toHaveLength(0)
  })

  it('בחירת עובדים מפורשת גוברת על השאר', () => {
    const r = applyBoardFilters(roster, shifts, { ...emptyBoardFilters, employees: ['p1'] })
    expect(r.rows.map((x) => x.id)).toEqual(['p1'])
    expect(r.shifts).toHaveLength(1)
  })

  it("קבלן='עובדי החברה' משאיר רק את מי שאין לו קבלן", () => {
    const r = applyBoardFilters(roster, shifts, { ...emptyBoardFilters, contractor: STAFF_ONLY })
    expect([...r.rows, ...r.empty].map((x) => x.id)).toEqual(['p1', 'p2'])
  })

  it('וקבלן מסוים משאיר רק אותו', () => {
    const r = applyBoardFilters(roster, shifts, { ...emptyBoardFilters, contractor: 'k1' })
    expect([...r.rows, ...r.empty].map((x) => x.id)).toEqual(['p3'])
  })

  it('מסנן לקוח מוריד עובד למדף ולא מוחק אותו מהלוח', () => {
    const r = applyBoardFilters(roster, shifts, { ...emptyBoardFilters, customer: 'c1' })
    expect(r.rows.map((x) => x.id)).toEqual(['p1'])
    // p2 עדיין עובד קיים — רק אין לו משמרת של הלקוח הזה
    expect(r.empty.map((x) => x.id)).toEqual(['p2', 'p3'])
    expect(r.shifts).toHaveLength(1)
  })

  it('מסנן אתר עבודה מתנהג אותו דבר', () => {
    const r = applyBoardFilters(roster, shifts, { ...emptyBoardFilters, site: 'warehouse' })
    expect(r.rows.map((x) => x.id)).toEqual(['p2'])
    expect(r.empty.map((x) => x.id)).toEqual(['p1', 'p3'])
  })

  it('משמרת של עובד שסונן החוצה אינה נשארת בתוצאה', () => {
    const r = applyBoardFilters(roster, shifts, { ...emptyBoardFilters, q: 'דני' })
    expect(r.shifts.every((s) => s.profile_id === 'p1')).toBe(true)
  })
})

describe('rangeTotals', () => {
  it('סוכם שעות ומשמרות לכל עובד', () => {
    const t = rangeTotals([
      shift({ profile_id: 'p1', work_date: '2026-08-12', planned_hours: 8 }),
      shift({ profile_id: 'p1', work_date: '2026-08-13', planned_hours: 4.5 }),
      shift({ profile_id: 'p2', work_date: '2026-08-12', planned_hours: 6 }),
    ])
    expect(t.get('p1')).toEqual({ hours: 12.5, count: 2 })
    expect(t.get('p2')).toEqual({ hours: 6, count: 1 })
  })

  it('ומשמרת בלי שעות אינה מפילה את הסכום', () => {
    const t = rangeTotals([
      shift({ profile_id: 'p1', work_date: '2026-08-12', planned_hours: null }),
      shift({ profile_id: 'p1', work_date: '2026-08-13', planned_hours: 3 }),
    ])
    expect(t.get('p1')).toEqual({ hours: 3, count: 2 })
  })
})

describe('activeBoardFilters', () => {
  it('סופר רשימת עובדים ריקה כלא-פעילה', () => {
    expect(activeBoardFilters(emptyBoardFilters)).toEqual([])
  })

  it('וסופר כל מסנן שיש בו ערך', () => {
    const active = activeBoardFilters({
      ...emptyBoardFilters,
      q: 'דני',
      employees: ['p1'],
      site: 'warehouse',
    })
    expect(active.sort()).toEqual(['employees', 'q', 'site'])
  })
})
