import { describe, expect, it } from 'vitest'
import { differenceInCalendarDays } from 'date-fns'
import { RANGE_PRESETS, defaultRange, previousRange } from './dashboardRange'

const span = ({ from, to }: { from: string; to: string }) =>
  differenceInCalendarDays(new Date(to), new Date(from))

describe('previousRange', () => {
  it('a single day is preceded by the day before', () => {
    expect(previousRange({ from: '2026-03-10', to: '2026-03-10' })).toEqual({
      from: '2026-03-09',
      to: '2026-03-09',
    })
  })

  it('a month is preceded by a window of the same length', () => {
    const prev = previousRange({ from: '2026-03-01', to: '2026-03-31' })
    expect(prev.to).toBe('2026-02-28')
    expect(span(prev)).toBe(30)
  })

  it('never overlaps the range it is compared against', () => {
    const range = { from: '2026-03-01', to: '2026-03-31' }
    expect(new Date(previousRange(range).to) < new Date(range.from)).toBe(true)
  })

  it('crosses a year boundary without drifting', () => {
    expect(previousRange({ from: '2026-01-01', to: '2026-01-07' })).toEqual({
      from: '2025-12-25',
      to: '2025-12-31',
    })
  })

  /* An inverted range is reachable — the two date inputs are independent, and
     nothing stops someone typing the end before the start. It must not produce
     a negative span that would silently invert the delta's sign. */
  it('clamps an inverted range instead of producing a negative span', () => {
    const prev = previousRange({ from: '2026-03-31', to: '2026-03-01' })
    expect(span(prev)).toBe(0)
    expect(prev.to).toBe('2026-03-30')
  })
})

describe('presets', () => {
  it('every preset produces a forward range', () => {
    for (const p of RANGE_PRESETS) {
      const r = p.range()
      expect(span(r)).toBeGreaterThanOrEqual(0)
    }
  })

  it('“השבוע” is seven days', () => {
    expect(span(RANGE_PRESETS[0].range())).toBe(6)
  })

  it('“30 ימים” ends today', () => {
    const r = RANGE_PRESETS[2].range()
    expect(span(r)).toBe(29)
  })

  it('the default range is the current month', () => {
    const r = defaultRange()
    expect(r.from.slice(8)).toBe('01')
    expect(span(r)).toBeGreaterThanOrEqual(27)
  })
})
