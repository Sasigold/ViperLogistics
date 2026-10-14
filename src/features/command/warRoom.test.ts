import { describe, expect, it } from 'vitest'
import { parseQuickAdd } from './quickAdd'
import {
  countdown,
  defconLine,
  fmtDebt,
  fmtSpan,
  groupByLane,
  heatLevel,
  laneOf,
  levelOf,
  liveDebt,
  pointsIfDoneNow,
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
  points: 0,
  created_at: NOW.toISOString(),
  steps: [],
  ...over,
})

describe('נתיבים', () => {
  const t = NOW.getTime()
  it('באיחור / היום / השבוע / בהמשך / בוצע', () => {
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

describe('ספירה לאחור וחוב', () => {
  it('fmtSpan', () => {
    expect(fmtSpan(59)).toBe('0:59')
    expect(fmtSpan(3 * 3600 + 12 * 60 + 5)).toBe('3:12:05')
    expect(fmtSpan(86400 + 4 * 3600)).toBe('יום 4 שע׳')
    expect(fmtSpan(3 * 86400)).toBe('3 ימים')
  })

  it('countdown', () => {
    const t = NOW.getTime()
    expect(countdown(new Date(t + 1800_000).toISOString(), t)).toEqual({ text: 'עוד 30:00', overdue: false, urgent: true })
    expect(countdown(new Date(t - 2 * 86400_000).toISOString(), t).overdue).toBe(true)
  })

  it('fmtDebt ו-liveDebt', () => {
    expect(fmtDebt(3 * 86400 + 4 * 3600 + 12 * 60 + 55)).toBe('3 ימים 04:12:55')
    expect(fmtDebt(65)).toBe('00:01:05')
    expect(liveDebt({ debt_seconds: 100, overdue: 3 }, 10_000)).toBe(130)
  })
})

describe('דרגות, נקודות ורמת איום', () => {
  it('levelOf', () => {
    expect(levelOf(0)).toMatchObject({ index: 0, title: 'טירון', progress: 0 })
    expect(levelOf(650)).toMatchObject({ index: 1, title: 'מבצעי', progress: 0.5 })
    expect(levelOf(20000)).toMatchObject({ title: 'אגדה', next: null, progress: 1 })
  })

  it('pointsIfDoneNow — אותו כלל של app.mission_points', () => {
    const t = NOW.getTime()
    expect(pointsIfDoneNow({ priority: 1, due_at: new Date(t + 25 * 3600_000).toISOString(), postpone_count: 0 }, t)).toBe(150)
    expect(pointsIfDoneNow({ priority: 2, due_at: new Date(t + 3600_000).toISOString(), postpone_count: 2 }, t)).toBe(40)
    expect(pointsIfDoneNow({ priority: 1, due_at: new Date(t - 36 * 3600_000).toISOString(), postpone_count: 0 }, t)).toBe(25)
    expect(pointsIfDoneNow({ priority: 1, due_at: new Date(t - 96 * 3600_000).toISOString(), postpone_count: 3 }, t)).toBe(0)
  })

  it('defconLine יציב', () => {
    expect(defconLine(1, 4)).toBe(defconLine(1, 4))
    expect(typeof defconLine(5, 0)).toBe('string')
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
