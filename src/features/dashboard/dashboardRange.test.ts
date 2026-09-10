import { describe, expect, it } from 'vitest'
import { differenceInCalendarDays } from 'date-fns'
import { RANGE_PRESETS, defaultRange, isWholeMonth, previousRange, stepMonth } from './dashboardRange'

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

describe('stepMonth', () => {
  it('a whole month steps to the whole month before it', () => {
    expect(stepMonth({ from: '2026-03-01', to: '2026-03-31' }, -1)).toEqual({
      from: '2026-02-01',
      to: '2026-02-28',
    })
  })

  it('a whole month steps to the whole month after it', () => {
    expect(stepMonth({ from: '2026-01-01', to: '2026-01-31' }, 1)).toEqual({
      from: '2026-02-01',
      to: '2026-02-28',
    })
  })

  it('crosses a year boundary in both directions', () => {
    expect(stepMonth({ from: '2026-01-01', to: '2026-01-31' }, -1).from).toBe('2025-12-01')
    expect(stepMonth({ from: '2026-12-01', to: '2026-12-31' }, 1).from).toBe('2027-01-01')
  })

  it('lands on February 29 in a leap year rather than on the 28th', () => {
    expect(stepMonth({ from: '2028-03-01', to: '2028-03-31' }, -1).to).toBe('2028-02-29')
  })

  /* A custom window is anchored on its start: "the month before" has to name a
     month, and the month a range began in is the only one it names. */
  it('snaps a custom window to the whole month its start falls in', () => {
    expect(stepMonth({ from: '2026-03-17', to: '2026-04-04' }, -1)).toEqual({
      from: '2026-02-01',
      to: '2026-02-28',
    })
    expect(stepMonth({ from: '2026-03-17', to: '2026-04-04' }, 0)).toEqual({
      from: '2026-03-01',
      to: '2026-03-31',
    })
  })

  it('always produces a whole month', () => {
    for (const delta of [-13, -1, 0, 1, 7]) {
      expect(isWholeMonth(stepMonth({ from: '2026-05-14', to: '2026-06-02' }, delta))).toBe(true)
    }
  })
})

describe('isWholeMonth', () => {
  it('recognises a calendar month', () => {
    expect(isWholeMonth({ from: '2026-02-01', to: '2026-02-28' })).toBe(true)
  })

  it('rejects a window that stops short of the month end', () => {
    expect(isWholeMonth({ from: '2026-02-01', to: '2026-02-27' })).toBe(false)
  })

  it('rejects a thirty-day window that spans two months', () => {
    expect(isWholeMonth({ from: '2026-02-05', to: '2026-03-06' })).toBe(false)
  })

  it('the default range is a whole month', () => {
    expect(isWholeMonth(defaultRange())).toBe(true)
  })
})
