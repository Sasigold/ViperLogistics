import { describe, expect, it } from 'vitest'
import { FORMS } from './dashboardTypes'
import {
  CATEGORY_FORMS,
  RANK_FORMS,
  SERIES_OPTIONS,
  TREND_FORMS,
  TREND_OPTIONS,
  applySeriesOpts,
  pickForm,
  plotHeight,
} from './seriesOpts'
import type { SeriesRow } from './seriesOpts'

const row = (label: string, value: number): SeriesRow => ({ key: label, label, value })

const CATEGORIES: SeriesRow[] = [row('אלף', 3), row('בית', 9), row('גימל', 1), row('דלת', 7)]

/* A trend arrives oldest-first, which is what makes "keep the last N" the
   right slice and "sort by value" the wrong operation. */
const BUCKETS: SeriesRow[] = [row('2026-01-01', 5), row('2026-02-01', 2), row('2026-03-01', 8)]

describe('the form vocabularies', () => {
  it('only names forms the type system knows', () => {
    for (const list of [CATEGORY_FORMS, RANK_FORMS, TREND_FORMS]) {
      for (const f of list) expect(FORMS).toContain(f)
    }
  })

  /* A slice per week is a picture of nothing, and a line joining "furniture" to
     "logistics" asserts a progression between two things that have no order.
     Both of those are decisions, so both get a test. */
  it('never offers a donut for a time series', () => {
    expect(TREND_FORMS).not.toContain('donut')
  })

  it('never offers a line or an area for a category', () => {
    for (const list of [CATEGORY_FORMS, RANK_FORMS]) {
      expect(list).not.toContain('line')
      expect(list).not.toContain('area')
    }
  })

  /* Every vocabulary can fall back to the two forms that draw any row shape —
     which is what lets a reader rescue a card whose chart says nothing. */
  it('always offers the table and the list', () => {
    for (const list of [CATEGORY_FORMS, RANK_FORMS, TREND_FORMS]) {
      expect(list).toContain('table')
      expect(list).toContain('list')
    }
  })

  it('gives a time series no sort control — it is already in its own order', () => {
    expect(TREND_OPTIONS.map((o) => o.key)).not.toContain('sort')
    expect(SERIES_OPTIONS.map((o) => o.key)).toContain('sort')
  })
})

describe('pickForm', () => {
  it('falls back to the natural form when nothing was chosen', () => {
    expect(pickForm(CATEGORY_FORMS, {})).toBe(CATEGORY_FORMS[0])
  })

  it('honours a stored choice the widget offers', () => {
    expect(pickForm(CATEGORY_FORMS, { form: 'table' })).toBe('table')
  })

  /* A layout saved by a client that offered more forms than this one, or a
     widget whose vocabulary narrowed in a later release. Drawing nothing is the
     one answer that is definitely wrong. */
  it('falls back rather than break on a form this widget cannot draw', () => {
    expect(pickForm(TREND_FORMS, { form: 'donut' })).toBe(TREND_FORMS[0])
    expect(pickForm(CATEGORY_FORMS, { form: 'nonsense' })).toBe(CATEGORY_FORMS[0])
  })
})

describe('applySeriesOpts', () => {
  it('leaves the rows alone when nothing is set', () => {
    expect(applySeriesOpts(CATEGORIES, {})).toEqual(CATEGORIES)
  })

  it('sorts by value in both directions', () => {
    expect(applySeriesOpts(CATEGORIES, { sort: 'desc' }).map((r) => r.value)).toEqual([9, 7, 3, 1])
    expect(applySeriesOpts(CATEGORIES, { sort: 'asc' }).map((r) => r.value)).toEqual([1, 3, 7, 9])
  })

  it('does not mutate what it was given', () => {
    const before = CATEGORIES.map((r) => r.value)
    applySeriesOpts(CATEGORIES, { sort: 'desc' })
    expect(CATEGORIES.map((r) => r.value)).toEqual(before)
  })

  /* "Top 3" has to mean the three biggest, not the first three the server
     happened to return — which is only true if the sort runs first. */
  it('slices after sorting, so top-N means the N biggest', () => {
    expect(applySeriesOpts(CATEGORIES, { sort: 'desc', top: 2 }).map((r) => r.label)).toEqual(['בית', 'דלת'])
  })

  it('slices from the front when there is no sort', () => {
    expect(applySeriesOpts(CATEGORIES, { top: 2 }).map((r) => r.label)).toEqual(['אלף', 'בית'])
  })

  /* The tail of a trend is the part anybody is looking at, so a limited time
     series keeps the most recent buckets rather than the oldest. */
  it('keeps the last buckets of a time series, and never reorders one', () => {
    expect(applySeriesOpts(BUCKETS, { top: 2 }, true).map((r) => r.label)).toEqual(['2026-02-01', '2026-03-01'])
    expect(applySeriesOpts(BUCKETS, { sort: 'desc' }, true).map((r) => r.value)).toEqual([5, 2, 8])
  })

  it('ignores a top larger than the data', () => {
    expect(applySeriesOpts(CATEGORIES, { top: 99 })).toHaveLength(4)
  })
})

describe('plotHeight', () => {
  /* The hole the reader complained about: eighteen pixels of bar and two
     hundred of air, because the frame hands down one height per widget size. */
  it('shrinks a horizontal ranking to the rows it actually has', () => {
    expect(plotHeight('row', 2, 250)).toBeLessThan(250)
    expect(plotHeight('row', 20, 250)).toBe(250)
  })

  it('never shrinks below a readable floor', () => {
    expect(plotHeight('row', 1, 250)).toBe(120)
  })

  /* A bar chart squeezed to 90px is unreadable, and a wide short one is fine —
     so only the form whose height *is* its row count is measured in rows. */
  it('leaves every other form at the height it was given', () => {
    for (const f of ['bar', 'line', 'area', 'donut'] as const) {
      expect(plotHeight(f, 1, 250)).toBe(250)
    }
  })
})
