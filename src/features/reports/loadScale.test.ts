import { describe, expect, it } from 'vitest'
import {
  busiestHour,
  emptyDay,
  hourExtent,
  loadBand,
  loadMark,
  loadPaint,
  loadScore,
  monthGrid,
  monthSummary,
} from './loadScale'
import type { LoadCapacity, LoadDay, LoadHour } from '../../types/domain'

const cap: LoadCapacity = {
  workers: 10,
  trucks: 4,
  team_leads: 2,
  source: { workers: 'configured', trucks: 'configured', team_leads: 'configured' },
}

const day = (day: string, over: Partial<LoadDay> = {}): LoadDay => ({ ...emptyDay(day), ...over })

const hour = (h: number, over: Partial<LoadHour> = {}): LoadHour => ({
  hour: h,
  tasks: 0,
  workers: 0,
  staffed: 0,
  gap: 0,
  trucks: 0,
  trucks_assigned: 0,
  leads: 0,
  leads_staffed: 0,
  customers: 0,
  sites: 0,
  warehouses: 0,
  delegated: 0,
  ...over,
})

describe('loadScore', () => {
  it('takes the worst dimension, not the average of them', () => {
    // עובדים 5/10 ומשאיות 1/4 פנויים לגמרי; ראשי הצוות מלאים — והיום סגור.
    const s = loadScore({ workers: 5, trucks: 1, leads: 2 }, cap)
    expect(s.pct).toBe(100)
    expect(s.bottleneck).toBe('leads')
  })

  it('names the dimension that decided, so the number can be acted on', () => {
    expect(loadScore({ workers: 9, trucks: 1, leads: 1 }, cap).bottleneck).toBe('workers')
    expect(loadScore({ workers: 1, trucks: 4, leads: 1 }, cap).bottleneck).toBe('trucks')
  })

  it('goes past 100 rather than clamping — that is the whole point of it', () => {
    expect(loadScore({ workers: 15, trucks: 0, leads: 0 }, cap).pct).toBe(150)
  })

  it('a capacity of zero skips its dimension instead of reading as infinite', () => {
    const noTrucks: LoadCapacity = { ...cap, trucks: 0 }
    const s = loadScore({ workers: 2, trucks: 3, leads: 0 }, noTrucks)
    expect(s.pct).toBe(20)
    expect(s.bottleneck).toBe('workers')
  })

  it('no capacity at all is zero, not a division', () => {
    expect(loadScore({ workers: 9, trucks: 9, leads: 9 }, undefined)).toEqual({
      pct: 0,
      bottleneck: null,
    })
  })

  it('an empty hour names no bottleneck', () => {
    expect(loadScore({ workers: 0, trucks: 0, leads: 0 }, cap)).toEqual({ pct: 0, bottleneck: null })
  })
})

describe('loadBand', () => {
  it('zero is its own band — an empty day is not a quiet one', () => {
    expect(loadBand(0)).toBe('idle')
    expect(loadBand(1)).toBe('light')
  })

  it('100 is still within capacity; only past it is over', () => {
    expect(loadBand(100)).toBe('high')
    expect(loadBand(101)).toBe('over')
  })
})

describe('loadPaint', () => {
  it('an empty cell and a barely-busy one do not look alike', () => {
    expect(loadPaint(0).background).not.toEqual(loadPaint(5).background)
  })

  it('over capacity leaves the sequential ramp for the error token', () => {
    expect(loadPaint(120).background).toContain('--color-error')
    expect(loadPaint(90).background).toContain('--color-primary')
  })
})

describe('loadMark', () => {
  it('is a single colour plus alpha — a chart Cell fill, not a color-mix', () => {
    const m = loadMark(50)
    expect(m.fill).toBe('var(--vl-primary)')
    expect(m.opacity).toBeGreaterThan(0)
    expect(m.opacity).toBeLessThanOrEqual(1)
  })

  it('rises with the load, so the tallest bar is also the darkest', () => {
    expect(loadMark(80).opacity).toBeGreaterThan(loadMark(30).opacity)
  })

  it('leaves the ramp past capacity, like the cells do', () => {
    expect(loadMark(130).fill).toBe('var(--vl-error)')
    expect(loadMark(0).fill).toBe('var(--vl-border)')
  })
})

describe('monthGrid', () => {
  it('pads to whole weeks starting on Sunday, without borrowing the neighbour month', () => {
    // ‏2026-02-01 הוא יום ראשון, ולפברואר 2026 יש 28 יום — בדיוק ארבעה שבועות.
    const weeks = monthGrid(new Date(2026, 1, 1), [])
    expect(weeks).toHaveLength(4)
    expect(weeks.every((w) => w.length === 7)).toBe(true)
    expect(weeks[0][0]?.day).toBe('2026-02-01')
    expect(weeks[3][6]?.day).toBe('2026-02-28')
  })

  it('leads with blanks when the month does not start on Sunday', () => {
    // ‏2026-01-01 הוא יום חמישי: ארבעה תאים ריקים לפניו.
    const weeks = monthGrid(new Date(2026, 0, 15), [])
    expect(weeks[0].slice(0, 4)).toEqual([null, null, null, null])
    expect(weeks[0][4]?.day).toBe('2026-01-01')
  })

  it('carries the server row where there is one, and an empty day where there is not', () => {
    const weeks = monthGrid(new Date(2026, 1, 1), [day('2026-02-03', { tasks: 4, peak_workers: 6 })])
    expect(weeks[0][2]?.tasks).toBe(4)
    expect(weeks[0][1]?.tasks).toBe(0)
  })
})

describe('monthSummary', () => {
  const days = [
    day('2026-02-01'), // ריק — אינו מדלל את הממוצע
    day('2026-02-02', { tasks: 2, peak_workers: 5, peak_leads: 1, gap: 3, delegated: 1 }), // 50%
    day('2026-02-03', { tasks: 3, peak_workers: 6, peak_leads: 3, gap: 1 }), // 150%, leads
    day('2026-02-04', { tasks: 1, peak_workers: 9, peak_leads: 1, gap: 0 }), // 90%, workers
    day('2026-02-05', { tasks: 0, untimed: 2 }), // עבודה בלי שעה — יום פעיל
  ]

  it('averages the active days only, so a quiet weekend does not hide a full week', () => {
    const s = monthSummary(days, cap)
    expect(s.activeDays).toBe(4)
    expect(s.avgPeakPct).toBe(Math.round((50 + 150 + 90 + 0) / 4))
  })

  it('counts the days that went past capacity', () => {
    expect(monthSummary(days, cap).overDays).toBe(1)
  })

  it('points at the worst day, with the reason', () => {
    const s = monthSummary(days, cap)
    expect(s.busiest?.day.day).toBe('2026-02-03')
    expect(s.busiest?.score.bottleneck).toBe('leads')
  })

  it('sums what still needs staffing across the whole month', () => {
    expect(monthSummary(days, cap).gap).toBe(4)
  })

  it('counts untimed tasks separately rather than dropping them', () => {
    expect(monthSummary(days, cap).untimed).toBe(2)
  })

  /* ‏0181: העומס נמדד מול הדרישה, אבל "שובץ מתוך נדרש" הוא מה שאומר מה עוד
     נשאר לעשות — ולכן שני המספרים נסכמים על החודש, לכל ממד בנפרד. */
  it('sums each dimension as a pair: what is needed, and what was staffed', () => {
    const s = monthSummary(
      [
        day('2026-03-01', {
          tasks: 2,
          worker_need: 7,
          staffed: 3,
          lead_need: 2,
          lead_staffed: 1,
          truck_need: 4,
          truck_assigned: 1,
        }),
        day('2026-03-02', {
          tasks: 1,
          worker_need: 3,
          staffed: 3,
          lead_need: 1,
          lead_staffed: 0,
          truck_need: 2,
          truck_assigned: 2,
        }),
      ],
      cap,
    )
    expect(s.need).toEqual({ workers: 10, leads: 3, trucks: 6 })
    expect(s.staffed).toEqual({ workers: 6, leads: 1, trucks: 3 })
  })

  it('a month with no work at all reports zero, not NaN', () => {
    const s = monthSummary([day('2026-02-01'), day('2026-02-02')], cap)
    expect(s.avgPeakPct).toBe(0)
    expect(s.busiest).toBeNull()
    expect(s.topBottleneck).toBeNull()
  })
})

describe('hourExtent', () => {
  it('trims the empty edges of the day and keeps one hour of air', () => {
    expect(hourExtent([hour(7), hour(8, { tasks: 1 }), hour(15, { tasks: 2 }), hour(20)])).toEqual({
      from: 7,
      to: 16,
    })
  })

  it('does not run past midnight at either end', () => {
    expect(hourExtent([hour(0, { tasks: 1 }), hour(23, { tasks: 1 })])).toEqual({ from: 0, to: 23 })
  })

  it('an empty day gets the usual working window, not a zero-width one', () => {
    expect(hourExtent([hour(9), hour(10)])).toEqual({ from: 6, to: 20 })
  })
})

describe('busiestHour', () => {
  it('is measured the same way the cells are', () => {
    const hours = [
      hour(8, { tasks: 1, workers: 3, trucks: 1, leads: 1 }), // 50% — leads
      hour(10, { tasks: 2, workers: 5, trucks: 2, leads: 2 }), // 100% — leads
      hour(15, { tasks: 1, workers: 5, trucks: 1, leads: 0 }), // 50% — workers
    ]
    const best = busiestHour(hours, cap)
    expect(best?.hour.hour).toBe(10)
    expect(best?.score).toEqual({ pct: 100, bottleneck: 'leads' })
  })

  it('a day with no timed work has no busiest hour', () => {
    expect(busiestHour([hour(8), hour(9)], cap)).toBeNull()
  })
})
