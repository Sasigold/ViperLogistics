import { describe, expect, it } from 'vitest'
import {
  applyBoardFilters,
  boardDays,
  boardRange,
  boardStep,
  cellKey,
  emptyBoardFilters,
  groupShifts,
  indexShifts,
  rangeTotals,
  activeBoardFilters,
  warehouseLeadPct,
  MAX_LEAD_PCT,
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

describe('groupShifts', () => {
  const names = new Map([
    ['p1', 'דני כהן'],
    ['p2', 'יוסי לוי'],
    ['p3', 'מאיה בר'],
  ])

  /** אותה משמרת בדיוק לשלושה אנשים: אותן משימות, אותן שעות. */
  const sameShift = ['p1', 'p2', 'p3'].map((profile_id) =>
    shift({ profile_id, work_date: '2026-08-12', task_ids: ['t1', 't2'] }),
  )

  it('שלושה עובדים על אותה משמרת הם צ׳יפ אחד עם שלושה שמות', () => {
    const groups = groupShifts(sameShift, names)
    expect(groups).toHaveLength(1)
    expect(groups[0].members.map((m) => m.name)).toEqual(['דני כהן', 'יוסי לוי', 'מאיה בר'])
  })

  it('וסדר המשימות במערך אינו מפצל אותם לשתי קבוצות', () => {
    const groups = groupShifts(
      [
        shift({ profile_id: 'p1', work_date: '2026-08-12', task_ids: ['t1', 't2'] }),
        shift({ profile_id: 'p2', work_date: '2026-08-12', task_ids: ['t2', 't1'] }),
      ],
      names,
    )
    expect(groups).toHaveLength(1)
  })

  it('משמרת עם קבוצת משימות אחרת נשארת בנפרד', () => {
    const groups = groupShifts(
      [
        shift({ profile_id: 'p1', work_date: '2026-08-12', task_ids: ['t1', 't2'] }),
        shift({ profile_id: 'p2', work_date: '2026-08-12', task_ids: ['t1'] }),
      ],
      names,
    )
    expect(groups).toHaveLength(2)
  })

  it("מצב 'לכל עובד' מחזיר קבוצה של אחד לכל משמרת", () => {
    const groups = groupShifts(sameShift, names, 'each')
    expect(groups).toHaveLength(3)
    expect(groups.every((g) => g.members.length === 1)).toBe(true)
  })

  it('מי שיוצא מהמחסן פותח את הרשימה, והחלון נמתח אחורה עד היציאה', () => {
    const groups = groupShifts(
      [
        shift({ profile_id: 'p2', work_date: '2026-08-12', task_ids: ['t1'] }),
        shift({
          profile_id: 'p1',
          work_date: '2026-08-12',
          task_ids: ['t1'],
          work_site: 'warehouse',
          warehouse_name: 'מחסן רמלה',
          shift_start: '2026-08-12T05:30:00+03:00',
        }),
      ],
      names,
    )
    const g = groups[0]
    expect(g.members.map((m) => m.name)).toEqual(['דני כהן', 'יוסי לוי'])
    expect(g.lead.profile_id).toBe('p1')
    expect(g.start).toBe('2026-08-12T05:30:00+03:00')
    expect(g.end).toBe('2026-08-12T15:00:00+03:00')
    expect(g.warehouseStart).toBe('2026-08-12T05:30:00+03:00')
    expect(g.warehouseName).toBe('מחסן רמלה')
    // מי שמגיע ישר לשטח הוא זה שמגדיר מתי העבודה עצמה מתחילה
    expect(g.onsiteStart).toBe('2026-08-12T07:00:00+03:00')
  })

  it('וכשכולם יוצאים מהמחסן אין התחלה בשטח להשוות מולה', () => {
    const groups = groupShifts(
      ['p1', 'p2'].map((profile_id) =>
        shift({
          profile_id,
          work_date: '2026-08-12',
          task_ids: ['t1'],
          work_site: 'warehouse',
          shift_start: '2026-08-12T05:30:00+03:00',
        }),
      ),
      names,
    )
    expect(groups[0].onsiteStart).toBeNull()
    expect(groups[0].warehouseStart).toBe('2026-08-12T05:30:00+03:00')
    expect(warehouseLeadPct(groups[0])).toBe(0)
  })

  it('הסיום הוא המאוחר מבין החברים, גם כשהוא לא של הראשון', () => {
    const groups = groupShifts(
      [
        shift({ profile_id: 'p1', work_date: '2026-08-12', task_ids: ['t1'] }),
        shift({
          profile_id: 'p2',
          work_date: '2026-08-12',
          task_ids: ['t1'],
          shift_end: '2026-08-12T16:30:00+03:00',
        }),
      ],
      names,
    )
    expect(groups[0].end).toBe('2026-08-12T16:30:00+03:00')
  })

  it('הקבוצות חוזרות ממוינות לפי שעת ההתחלה', () => {
    const groups = groupShifts(
      [
        shift({
          profile_id: 'p1',
          work_date: '2026-08-12',
          task_ids: ['t2'],
          shift_start: '2026-08-12T12:00:00+03:00',
        }),
        shift({ profile_id: 'p2', work_date: '2026-08-12', task_ids: ['t1'] }),
      ],
      names,
    )
    expect(groups.map((g) => g.members[0].name)).toEqual(['יוסי לוי', 'דני כהן'])
  })

  it('משמרת בלי משימות נופלת לאחור לשעות ואינה מתמזגת עם משמרת אחרת', () => {
    const groups = groupShifts(
      [
        shift({ profile_id: 'p1', work_date: '2026-08-12', task_ids: [] }),
        shift({
          profile_id: 'p2',
          work_date: '2026-08-12',
          task_ids: [],
          shift_start: '2026-08-12T09:00:00+03:00',
        }),
      ],
      names,
    )
    expect(groups).toHaveLength(2)
  })
})

describe('warehouseLeadPct', () => {
  const names = new Map([
    ['p1', 'דני כהן'],
    ['p2', 'יוסי לוי'],
  ])

  const mixed = (warehouseStart: string) =>
    groupShifts(
      [
        shift({ profile_id: 'p2', work_date: '2026-08-12', task_ids: ['t1'] }),
        shift({
          profile_id: 'p1',
          work_date: '2026-08-12',
          task_ids: ['t1'],
          work_site: 'warehouse',
          shift_start: warehouseStart,
        }),
      ],
      names,
    )[0]

  it('שעה של נסיעה מתוך חלון של תשע היא כאחד עשר אחוז', () => {
    // 06:00 → 15:00 = 9 שעות, מתוכן שעה עד תחילת העבודה ב-07:00
    expect(warehouseLeadPct(mixed('2026-08-12T06:00:00+03:00'))).toBeCloseTo(100 / 9, 5)
  })

  it('ונסיעה ארוכה בטירוף נחסמת, כדי שהפס לא יבלע את השמות', () => {
    // 13 שעות "נסיעה" מתוך חלון של 21 — 62%, שנחתכות ל-60
    expect(warehouseLeadPct(mixed('2026-08-11T18:00:00+03:00'))).toBe(MAX_LEAD_PCT)
  })

  it('בלי יוצא מחסן אין פס בכלל', () => {
    const g = groupShifts([shift({ profile_id: 'p1', work_date: '2026-08-12' })], names)[0]
    expect(warehouseLeadPct(g)).toBe(0)
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
