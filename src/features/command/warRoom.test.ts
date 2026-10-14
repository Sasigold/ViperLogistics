import { describe, expect, it } from 'vitest'
import { parseQuickAdd } from './quickAdd'
import {
  countdown,
  fmtSpan,
  groupByLane,
  heatLevel,
  laneOf,
  oldestOverdueSeconds,
  onTimePct,
  weeklyOnTime,
} from './warRoom'
import type { Mission } from '../../types/domain'

// יום רביעי, 14.10.2026, 09:30 (שעון המכשיר)
const NOW = new Date(2026, 9, 14, 9, 30)
const ADMINS = [
  { id: 'a', full_name: 'שמחה גולד' },
  { id: 'b', full_name: 'דוד כהן' },
]

describe('parseQuickAdd', () => {
  it('הדוגמה של הבעלים', () => {
    const r = parseQuickAdd('התקנת מצלמות במחסן מחר 10:00 @שמחה !1', NOW, ADMINS)
    expect(r.title).toBe('התקנת מצלמות במחסן')
    expect(r.due).toEqual(new Date(2026, 9, 15, 10, 0))
    expect(r.priority).toBe(1)
    expect(r.ownerId).toBe('a')
    expect(r.chips).toEqual(['מחר', '10:00', '@שמחה גולד', 'P1'])
  })

  it('בלי יום ובלי שעה — היום ב-18:00, עדיפות 2', () => {
    const r = parseQuickAdd('לחדש ביטוח', NOW)
    expect(r.title).toBe('לחדש ביטוח')
    expect(r.due).toEqual(new Date(2026, 9, 14, 18, 0))
    expect(r.priority).toBe(2)
    expect(r.ownerId).toBeNull()
  })

  it('שעה שכבר עברה היום — מחר', () => {
    const r = parseQuickAdd('פגישה 08:00', NOW)
    expect(r.due).toEqual(new Date(2026, 9, 15, 8, 0))
    expect(r.chips).toContain('מחר')
  })

  it('יום בשבוע — הקרוב שאחרי היום; היום עצמו — בעוד שבוע', () => {
    expect(parseQuickAdd('x ביום ראשון', NOW).due).toEqual(new Date(2026, 9, 18, 18, 0))
    expect(parseQuickAdd('x ברביעי', NOW).due).toEqual(new Date(2026, 9, 21, 18, 0))
  })

  it('"שני" בתוך שם אינו יום', () => {
    expect(parseQuickAdd('שלב שני בפרויקט', NOW).title).toBe('שלב שני בפרויקט')
  })

  it('תאריך, בעוד, וחזרה', () => {
    expect(parseQuickAdd('x 3.11', NOW).due).toEqual(new Date(2026, 10, 3, 18, 0))
    expect(parseQuickAdd('x 1.1', NOW).due).toEqual(new Date(2027, 0, 1, 18, 0))
    expect(parseQuickAdd('x 31.2', NOW).title).toBe('x 31.2')
    expect(parseQuickAdd('x בעוד 3 ימים בשעה 9', NOW).due).toEqual(new Date(2026, 9, 17, 9, 0))
    const r = parseQuickAdd('בדיקת מטפים כל חודש', NOW)
    expect(r.recurrence).toBe('monthly')
    expect(r.title).toBe('בדיקת מטפים')
  })

  it('@ שאינו מנהל ידוע, או שמתאים לשניים — נשאר בשם', () => {
    expect(parseQuickAdd('x @יוסי', NOW, ADMINS).ownerId).toBeNull()
    expect(parseQuickAdd('x @כהן', NOW, ADMINS).ownerId).toBe('b')
  })
})

const m = (over: Partial<Mission>): Mission => ({
  id: '1',
  title: 't',
  description: null,
  owner_id: 'a',
  owner_name: 'א',
  created_by: null,
  due_at: NOW.toISOString(),
  priority: 2,
  recurrence: 'none',
  status: 'open',
  done_at: null,
  postpone_count: 0,
  created_at: NOW.toISOString(),
  steps: [],
  ...over,
})

describe('נתיבים', () => {
  const t = NOW.getTime()
  it('באיחור / היום / השבוע / בהמשך / הושלמו', () => {
    expect(laneOf(m({ due_at: new Date(t - 1000).toISOString() }), t)).toBe('overdue')
    expect(laneOf(m({ due_at: new Date(2026, 9, 14, 23, 0).toISOString() }), t)).toBe('today')
    expect(laneOf(m({ due_at: new Date(2026, 9, 16).toISOString() }), t)).toBe('week')
    expect(laneOf(m({ due_at: new Date(2026, 10, 16).toISOString() }), t)).toBe('later')
    expect(laneOf(m({ status: 'done', due_at: new Date(t - 1000).toISOString() }), t)).toBe('done')
  })

  it('ממוינים לפי יעד ואז עדיפות', () => {
    const g = groupByLane(
      [
        m({ id: 'x', due_at: new Date(2026, 9, 14, 20).toISOString(), priority: 3 }),
        m({ id: 'y', due_at: new Date(2026, 9, 14, 20).toISOString(), priority: 1 }),
        m({ id: 'z', due_at: new Date(2026, 9, 14, 12).toISOString(), priority: 4 }),
      ],
      t,
    )
    expect(g.today.map((x) => x.id)).toEqual(['z', 'y', 'x'])
  })
})

describe('זמן עד היעד ומדדים', () => {
  it('fmtSpan — בדיוק של דקה', () => {
    expect(fmtSpan(20)).toBe('1 דק׳')
    expect(fmtSpan(40 * 60)).toBe('40 דק׳')
    expect(fmtSpan(3 * 3600 + 12 * 60 + 5)).toBe('3 שע׳ 12 דק׳')
    expect(fmtSpan(2 * 3600)).toBe('2 שע׳')
    expect(fmtSpan(86400 + 4 * 3600)).toBe('יום ו-4 שע׳')
    expect(fmtSpan(3 * 86400 + 5)).toBe('3 ימים')
  })

  it('countdown', () => {
    const t = NOW.getTime()
    expect(countdown(new Date(t + 1800_000).toISOString(), t)).toEqual({ text: 'בעוד 30 דק׳', overdue: false, soon: true })
    expect(countdown(new Date(t - 2 * 86400_000).toISOString(), t)).toEqual({
      text: 'באיחור של 2 ימים',
      overdue: true,
      soon: false,
    })
  })

  it('oldestOverdueSeconds — רק פתוחות שעברו את היעד', () => {
    const t = NOW.getTime()
    expect(oldestOverdueSeconds([], t)).toBeNull()
    expect(
      oldestOverdueSeconds(
        [
          { status: 'open', due_at: new Date(t - 3600_000).toISOString() },
          { status: 'open', due_at: new Date(t - 7200_000).toISOString() },
          { status: 'done', due_at: new Date(t - 9 * 3600_000).toISOString() },
          { status: 'open', due_at: new Date(t + 3600_000).toISOString() },
        ],
        t,
      ),
    ).toBe(7200)
  })

  it('onTimePct', () => {
    expect(onTimePct(0, 0)).toBeNull()
    expect(onTimePct(12, 11)).toBe(92)
  })
})

describe('גרפים', () => {
  it('weeklyOnTime מקבץ ראשון–שבת', () => {
    const day = (d: string, done: number, on_time: number) => ({ day: d, done, on_time, open: 0, overdue: 0, debt_hours: 0 })
    expect(weeklyOnTime([day('2026-10-10', 2, 1), day('2026-10-11', 1, 1), day('2026-10-14', 3, 3)])).toEqual([
      { week: '2026-10-04', done: 2, pct: 50 },
      { week: '2026-10-11', done: 4, pct: 100 },
    ])
  })

  it('heatLevel', () => {
    expect([0, 1, 2, 4, 9].map(heatLevel)).toEqual([0, 1, 2, 3, 4])
  })
})
