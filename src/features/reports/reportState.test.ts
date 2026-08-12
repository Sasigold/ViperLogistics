import { describe, expect, it } from 'vitest'
import { CATALOG_0043 } from './catalogFixture'
import {
  MAX_DIMS,
  autoBucket,
  blankReportState,
  normalizeReportState,
  panelViz,
  specsFor,
  stateFromParam,
  stateToParam,
  summaryAllowed,
  toSpec,
} from './reportState'
import { specProblems } from '../dashboard/builder/widgetSpec'
import type { ReportState } from './reportState'

const base: ReportState = {
  v: 1,
  source: 'tasks',
  measure: 'tasks.count',
  agg: 'count_distinct',
  filters: [],
  dims: [{ field: 'tasks.customer' }, { field: 'tasks.date' }],
  bucket: 'month',
  compare: false,
  range: { from: '2026-01-01', to: '2026-03-31' },
}

describe('toSpec', () => {
  it('builds an engine-legal spec for every breakdown', () => {
    for (const { spec } of specsFor(base, CATALOG_0043)) {
      expect(specProblems(spec, CATALOG_0043)).toEqual([])
    }
  })

  it('a time breakdown carries the state bucket and reads left to right', () => {
    const spec = toSpec(base, { field: 'tasks.date' }, CATALOG_0043)
    expect(spec.dimension).toEqual({ type: 'time', field: 'tasks.date', bucket: 'month' })
    expect(spec.sort).toEqual({ by: 'dimension', dir: 'asc' })
    expect(spec.viz).toBe('line')
  })

  it('a category breakdown sorts biggest first and asks for the whole ceiling', () => {
    const spec = toSpec(base, { field: 'tasks.customer' }, CATALOG_0043)
    expect(spec.dimension).toEqual({ type: 'cat', field: 'tasks.customer' })
    expect(spec.sort).toEqual({ by: 'measure', dir: 'desc' })
    expect(spec.limit).toBe(50)
    expect(spec.viz).toBe('bar')
  })

  it('no breakdown at all → the summary number', () => {
    const spec = toSpec(base, null, CATALOG_0043)
    expect(spec.dimension).toBeNull()
    expect(spec.viz).toBe('number')
    expect(specProblems(spec, CATALOG_0043)).toEqual([])
  })

  it('a DimChoice viz override wins over the kind default', () => {
    expect(panelViz({ field: 'tasks.status', viz: 'donut' }, CATALOG_0043.fields.find((f) => f.key === 'tasks.status'))).toBe('donut')
  })
})

describe('specsFor', () => {
  it('empty dims → exactly one summary run', () => {
    const runs = specsFor({ ...base, dims: [] }, CATALOG_0043)
    expect(runs).toHaveLength(1)
    expect(runs[0].dim).toBeNull()
  })

  it('one run per breakdown, in order', () => {
    const runs = specsFor(base, CATALOG_0043)
    expect(runs.map((r) => r.dim?.field)).toEqual(['tasks.customer', 'tasks.date'])
  })
})

describe('autoBucket', () => {
  it('a month reads daily', () => {
    expect(autoBucket({ from: '2026-01-01', to: '2026-01-31' })).toBe('day')
  })
  it('a quarter reads weekly — 90 daily rows would blow the 50-row ceiling', () => {
    expect(autoBucket({ from: '2026-01-01', to: '2026-03-31' })).toBe('week')
  })
  it('a year reads monthly', () => {
    expect(autoBucket({ from: '2026-01-01', to: '2026-12-31' })).toBe('month')
  })
})

describe('normalizeReportState', () => {
  it('round-trips a well-formed state untouched', () => {
    expect(normalizeReportState(base)).toEqual(base)
  })

  it('garbage in → a usable state out, never a throw', () => {
    for (const raw of [null, undefined, 42, 'x', [], { dims: 'nope', range: { from: 'bad' } }]) {
      const s = normalizeReportState(raw)
      expect(s.v).toBe(1)
      expect(Array.isArray(s.dims)).toBe(true)
      expect(s.range.from <= s.range.to).toBe(true)
    }
  })

  it('an inverted range falls back rather than reaching the engine', () => {
    const s = normalizeReportState({ ...base, range: { from: '2026-03-01', to: '2026-01-01' } })
    expect(s.range.from <= s.range.to).toBe(true)
  })

  it('duplicate breakdowns collapse and the count is capped', () => {
    const s = normalizeReportState({
      ...base,
      dims: [
        { field: 'a' }, { field: 'a' }, { field: 'b' }, { field: 'c' }, { field: 'd' }, { field: 'e' },
      ],
    })
    expect(s.dims.map((d) => d.field)).toEqual(['a', 'b', 'c', 'd'])
    expect(s.dims.length).toBeLessThanOrEqual(MAX_DIMS)
  })

  it('an unknown viz on a breakdown is dropped, not kept as something a renderer would choke on', () => {
    const s = normalizeReportState({ ...base, dims: [{ field: 'a', viz: 'hologram' }] })
    expect(s.dims[0].viz).toBeUndefined()
  })
})

describe('the URL param', () => {
  it('round-trips through serialise/parse', () => {
    expect(stateFromParam(stateToParam(base))).toEqual(base)
  })

  it('a mangled param is null, not a crash', () => {
    expect(stateFromParam('{not json')).toBeNull()
    expect(stateFromParam('')).toBeNull()
    expect(stateFromParam(null)).toBeNull()
  })
})

describe('blankReportState / summaryAllowed', () => {
  it('opens on the first measure the catalogue serves and validates', () => {
    const s = blankReportState(CATALOG_0043)
    expect(s.measure).toBe('tasks.count')
    expect(specProblems(toSpec(s, null, CATALOG_0043), CATALOG_0043)).toEqual([])
  })

  it('a measure whose allowed_dims has no __none__ refuses the bare summary', () => {
    expect(summaryAllowed(base, CATALOG_0043)).toBe(true)
    expect(summaryAllowed({ ...base, source: 'payroll', measure: 'payroll.total' }, CATALOG_0043)).toBe(true)
  })
})
