import { describe, expect, it } from 'vitest'
import {
  EMPTY_CATALOG,
  MAX_FILTERS,
  MAX_LIMIT,
  VIZ_KINDS,
  VIZ_SIZES,
  allowsNoDimension,
  blankQuerySpec,
  dimensionsFor,
  disclosureRule,
  effectiveViz,
  isNote,
  isQuery,
  normalizeSpec,
  specProblems,
  specTitle,
  vizAllows,
} from './widgetSpec'
import type { Catalog, CatalogField, CatalogMeasure, QuerySpec } from './widgetSpec'

/* ===== a catalogue small enough to reason about ===========================
   Mirrors the shapes 0043 seeds: a money measure that cannot survive row
   fan-out, a count measure that can, and an engine measure with an explicit
   allowed_dims list.                                                         */

const measure = (over: Partial<CatalogMeasure> & { key: string }): CatalogMeasure => ({
  source_key: 'tasks',
  label_he: 'מדד',
  hint_he: null,
  allowed_aggs: ['sum'],
  default_agg: 'sum',
  unit: 'count',
  is_estimate: false,
  fanout_safe: true,
  allowed_dims: null,
  sort_order: 10,
  ...over,
})

const field = (over: Partial<CatalogField> & { key: string }): CatalogField => ({
  source_key: 'tasks',
  label_he: 'שדה',
  kind: 'cat',
  col_type: 'uuid',
  fans_out: false,
  nullable: false,
  is_estimate: false,
  can_group: true,
  can_filter: true,
  allowed_ops: ['eq', 'in'],
  sort_order: 10,
  ...over,
})

const CAT: Catalog = {
  sources: [
    { key: 'tasks', label_he: 'משימות', row_noun_he: 'משימות', scope_note_he: null, sort_order: 10 },
    { key: 'payroll', label_he: 'שכר', row_noun_he: 'משמרות', scope_note_he: null, sort_order: 40 },
  ],
  measures: [
    measure({ key: 'tasks.count', label_he: 'מספר משימות', allowed_aggs: ['count_distinct'], default_agg: 'count_distinct' }),
    measure({ key: 'revenue', label_he: 'הכנסות', unit: 'money', allowed_aggs: ['sum', 'avg'], fanout_safe: false }),
    measure({
      key: 'payroll.total',
      source_key: 'payroll',
      label_he: 'עלות שכר',
      unit: 'money',
      allowed_dims: ['__none__', 'payroll.date'],
    }),
  ],
  fields: [
    field({ key: 'tasks.date', label_he: 'תאריך משימה', kind: 'time', col_type: 'date', allowed_ops: ['gte', 'between'] }),
    field({ key: 'tasks.customer', label_he: 'לקוח' }),
    field({ key: 'tasks.truck', label_he: 'משאית', fans_out: true, can_filter: false, allowed_ops: [] }),
    field({ key: 'payroll.date', source_key: 'payroll', label_he: 'לפי זמן', kind: 'time', col_type: 'date', can_filter: false, allowed_ops: [] }),
    field({ key: 'payroll.worker', source_key: 'payroll', label_he: 'לפי עובד', can_filter: false, allowed_ops: [] }),
  ],
}

const baseSpec = (over: Partial<QuerySpec> = {}): QuerySpec => ({
  ...blankQuerySpec(CAT),
  source: 'tasks',
  measure: 'revenue',
  agg: 'sum',
  ...over,
})

/* ===== normalising ======================================================== */

describe('normalizeSpec', () => {
  /* The stored value is jsonb written by whatever release last saved it. One
     unparseable widget must not take the dashboard with it. */
  it.each([
    ['null', null],
    ['undefined', undefined],
    ['a string', 'hello'],
    ['an array', []],
    ['an empty object', {}],
    ['a number', 42],
  ])('never throws on %s', (_label, input) => {
    expect(() => normalizeSpec(input)).not.toThrow()
  })

  it('falls back to an empty note for anything unusable', () => {
    const s = normalizeSpec(null)
    expect(isNote(s)).toBe(true)
  })

  it('survives every field being the wrong type', () => {
    const s = normalizeSpec({
      variant: 'query',
      source: 5,
      measure: {},
      agg: 'nonsense',
      dimension: 'not-an-object',
      filters: 'not-an-array',
      sort: 7,
      limit: 'twelve',
      viz: 99,
      viz_opts: [],
      goal: 'none',
    })
    expect(isQuery(s)).toBe(true)
    if (!isQuery(s)) return
    expect(s.source).toBe('')
    expect(s.agg).toBe('sum')
    expect(s.dimension).toBeNull()
    expect(s.filters).toEqual([])
    expect(s.limit).toBe(12)
    expect(s.goal).toBeNull()
  })

  it('clamps the limit into range', () => {
    const hi = normalizeSpec({ variant: 'query', limit: 100000 }) as QuerySpec
    const lo = normalizeSpec({ variant: 'query', limit: -1 }) as QuerySpec
    expect(hi.limit).toBe(MAX_LIMIT)
    expect(lo.limit).toBe(1)
  })

  it('caps the filter list', () => {
    const many = Array.from({ length: 40 }, (_, i) => ({ id: `f${i}`, field: 'tasks.customer', op: 'eq', value: 'x' }))
    const s = normalizeSpec({ variant: 'query', filters: many }) as QuerySpec
    expect(s.filters).toHaveLength(MAX_FILTERS)
  })

  /* The CondEditor rule. A newer client may write an op this build has never
     heard of; rewriting it would silently change what the widget counts. */
  it('preserves an unrecognised filter op instead of dropping it', () => {
    const s = normalizeSpec({
      variant: 'query',
      filters: [{ id: 'a', field: 'tasks.customer', op: 'matches_regex', value: '^x' }],
    }) as QuerySpec
    expect(s.filters).toHaveLength(1)
    expect(s.filters[0].op).toBe('matches_regex')
    expect(s.filters[0].value).toBe('^x')
  })

  it('preserves an unrecognised viz, and only falls back at render', () => {
    const s = normalizeSpec({ variant: 'query', viz: 'sankey', dimension: { type: 'cat', field: 'tasks.customer' } }) as QuerySpec
    expect(s.viz).toBe('sankey')
    expect(effectiveViz(s)).toBe('table')
  })

  it('round-trips an unknown shape byte for byte', () => {
    const stored = {
      v: 1,
      variant: 'query',
      source: 'tasks',
      measure: 'revenue',
      agg: 'sum',
      dimension: { type: 'cat', field: 'tasks.customer' },
      filters: [{ id: 'a', field: 'tasks.customer', op: 'starts_with', value: 'א' }],
      sort: { by: 'measure', dir: 'desc' },
      limit: 12,
      range_mode: 'page',
      viz: 'treemap',
      viz_opts: {},
      goal: null,
    }
    const once = normalizeSpec(stored)
    const twice = normalizeSpec(JSON.parse(JSON.stringify(once)))
    expect(twice).toEqual(once)
  })

  it('reads a note and clamps its length', () => {
    const s = normalizeSpec({ variant: 'note', body: 'x'.repeat(5000), tone: 'warn' })
    expect(isNote(s)).toBe(true)
    if (!isNote(s)) return
    expect(s.body.length).toBe(2000)
    expect(s.tone).toBe('warn')
  })

  /* A time series reads left to right; a top-N reads biggest first. Getting
     this wrong turns every trend chart into a ranking. */
  it('defaults sort by the shape of the dimension', () => {
    const t = normalizeSpec({ variant: 'query', dimension: { type: 'time', field: 'tasks.date' } }) as QuerySpec
    const c = normalizeSpec({ variant: 'query', dimension: { type: 'cat', field: 'tasks.customer' } }) as QuerySpec
    expect(t.sort).toEqual({ by: 'dimension', dir: 'asc' })
    expect(c.sort).toEqual({ by: 'measure', dir: 'desc' })
  })

  it('drops range_days unless the mode is relative', () => {
    const page = normalizeSpec({ variant: 'query', range_mode: 'page', range_days: 30 }) as QuerySpec
    const rel = normalizeSpec({ variant: 'query', range_mode: 'relative', range_days: 90 }) as QuerySpec
    expect(page.range_days).toBeUndefined()
    expect(rel.range_days).toBe(90)
  })
})

/* ===== the legality matrix ================================================ */

describe('dimensionsFor', () => {
  const revenue = CAT.measures.find((m) => m.key === 'revenue')!
  const count = CAT.measures.find((m) => m.key === 'tasks.count')!
  const payroll = CAT.measures.find((m) => m.key === 'payroll.total')!

  /* The trap this closes: `unnest(truck_ids)` multiplies a task into one row
     per truck, so a task-level SUM double counts while a COUNT DISTINCT does
     not. The picker must not offer the first combination at all. */
  it('hides a fanning dimension from a measure that cannot survive it', () => {
    expect(dimensionsFor(CAT, revenue).map((f) => f.key)).not.toContain('tasks.truck')
    expect(dimensionsFor(CAT, count).map((f) => f.key)).toContain('tasks.truck')
  })

  it('honours an explicit allowed_dims whitelist', () => {
    expect(dimensionsFor(CAT, payroll).map((f) => f.key)).toEqual(['payroll.date'])
  })

  it('never crosses sources', () => {
    expect(dimensionsFor(CAT, revenue).every((f) => f.source_key === 'tasks')).toBe(true)
  })

  it('is empty for an unknown measure', () => {
    expect(dimensionsFor(CAT, undefined)).toEqual([])
  })

  it('reads __none__ as permission to show a bare number', () => {
    expect(allowsNoDimension(payroll)).toBe(true)
    expect(allowsNoDimension(measure({ key: 'x', allowed_dims: ['payroll.date'] }))).toBe(false)
    expect(allowsNoDimension(revenue)).toBe(true)
  })
})

/* ===== visualisation fit ================================================== */

describe('vizAllows', () => {
  const timeDim = { type: 'time', field: 'tasks.date', bucket: 'week' } as const
  const catDim = { type: 'cat', field: 'tasks.customer' } as const

  it.each(VIZ_KINDS)('has a verdict for %s in all three shapes', (viz) => {
    for (const dim of [null, catDim, timeDim]) {
      expect(typeof vizAllows(viz, dim)).toBe('boolean')
    }
  })

  it('reserves the bare-number visuals for a spec with no breakdown', () => {
    expect(vizAllows('number', null)).toBe(true)
    expect(vizAllows('number', catDim)).toBe(false)
    expect(vizAllows('gauge', catDim)).toBe(false)
  })

  it('requires a breakdown for every chart', () => {
    expect(vizAllows('bar', null)).toBe(false)
    expect(vizAllows('donut', null)).toBe(false)
    expect(vizAllows('table', null)).toBe(false)
  })

  it('keeps line and area on a time axis', () => {
    expect(vizAllows('line', timeDim)).toBe(true)
    expect(vizAllows('line', catDim)).toBe(false)
    expect(vizAllows('area', catDim)).toBe(false)
  })

  it('falls back to a shape that always renders', () => {
    expect(effectiveViz(baseSpec({ viz: 'bar', dimension: null }))).toBe('number')
    expect(effectiveViz(baseSpec({ viz: 'number', dimension: catDim }))).toBe('table')
  })

  it('declares at least one size for every viz', () => {
    for (const viz of VIZ_KINDS) {
      expect(VIZ_SIZES[viz].length).toBeGreaterThan(0)
    }
  })
})

/* ===== validation ========================================================= */

describe('specProblems', () => {
  it('is silent on a spec that fits the catalogue', () => {
    expect(specProblems(baseSpec({ viz: 'number' }), CAT)).toEqual([])
  })

  it('flags an unknown source as unknown, not wrong', () => {
    const p = specProblems(baseSpec({ source: 'invoices' }), CAT)
    expect(p).toHaveLength(1)
    expect(p[0]).toMatchObject({ at: 'source', unknown: true })
  })

  it('flags an aggregate the measure does not allow', () => {
    const p = specProblems(baseSpec({ agg: 'min', viz: 'number' }), CAT)
    expect(p.some((x) => x.at === 'agg')).toBe(true)
  })

  /* Known field, illegal pairing — the message has to be different from
     "not in the catalogue", because the fix is different. */
  it('separates an illegal pairing from an unknown field', () => {
    const illegal = specProblems(
      baseSpec({ dimension: { type: 'cat', field: 'tasks.truck' }, viz: 'bar' }),
      CAT,
    ).find((x) => x.at === 'dimension')
    const missing = specProblems(
      baseSpec({ dimension: { type: 'cat', field: 'tasks.moon' }, viz: 'bar' }),
      CAT,
    ).find((x) => x.at === 'dimension')
    expect(illegal?.unknown).toBeFalsy()
    expect(missing?.unknown).toBe(true)
  })

  it('requires a breakdown when the measure demands one', () => {
    const narrow: Catalog = {
      ...CAT,
      measures: [...CAT.measures, measure({ key: 'only_split', allowed_dims: ['tasks.customer'] })],
    }
    const p = specProblems(baseSpec({ measure: 'only_split', dimension: null, viz: 'number' }), narrow)
    expect(p.some((x) => x.at === 'dimension')).toBe(true)
  })

  it('rejects a filter value of the wrong shape', () => {
    const spec = baseSpec({
      viz: 'number',
      filters: [
        { id: 'a', field: 'tasks.customer', op: 'in', value: 'not-a-list' },
        { id: 'b', field: 'tasks.date', op: 'between', value: ['2026-01-01'] },
      ],
    })
    const p = specProblems(spec, CAT)
    expect(p.filter((x) => x.filterId).length).toBe(2)
  })

  it('accepts a valueless operator with no value', () => {
    const cat: Catalog = {
      ...CAT,
      fields: CAT.fields.map((f) =>
        f.key === 'tasks.customer' ? { ...f, allowed_ops: ['eq', 'in', 'is_null'] } : f,
      ),
    }
    const spec = baseSpec({ viz: 'number', filters: [{ id: 'a', field: 'tasks.customer', op: 'is_null' }] })
    expect(specProblems(spec, cat).filter((x) => x.filterId)).toEqual([])
  })

  it('flags an unrecognised op on a filter row without dropping it', () => {
    const spec = baseSpec({
      viz: 'number',
      filters: [{ id: 'a', field: 'tasks.customer', op: 'matches' as never, value: 'x' }],
    })
    const p = specProblems(spec, CAT)
    expect(p.find((x) => x.filterId === 'a')?.unknown).toBe(true)
    expect(spec.filters).toHaveLength(1)
  })

  it('reports an empty note', () => {
    expect(specProblems({ v: 1, variant: 'note', body: '   ' }, CAT)).toHaveLength(1)
    expect(specProblems({ v: 1, variant: 'note', body: 'שלום' }, CAT)).toEqual([])
  })

  it('says nothing useful, but does not throw, against an empty catalogue', () => {
    expect(() => specProblems(baseSpec(), EMPTY_CATALOG)).not.toThrow()
  })
})

/* ===== the auto title ===================================================== */

describe('specTitle', () => {
  it('names the measure on its own', () => {
    expect(specTitle(baseSpec(), CAT)).toBe('הכנסות')
  })

  it('adds the breakdown', () => {
    expect(specTitle(baseSpec({ dimension: { type: 'cat', field: 'tasks.customer' } }), CAT)).toBe(
      'הכנסות לפי לקוח',
    )
  })

  it('adds the bucket for a time breakdown', () => {
    expect(
      specTitle(baseSpec({ dimension: { type: 'time', field: 'tasks.date', bucket: 'week' } }), CAT),
    ).toBe('הכנסות לפי תאריך משימה, שבועי')
  })

  it('names a non-default aggregate', () => {
    expect(specTitle(baseSpec({ agg: 'avg' }), CAT)).toBe('ממוצע הכנסות')
  })

  it('names a note', () => {
    expect(specTitle({ v: 1, variant: 'note', body: 'x' }, CAT)).toBe('פתק')
  })

  it('does not throw on a measure the catalogue lost', () => {
    expect(specTitle(baseSpec({ measure: 'gone' }), CAT)).toBe('ווידג׳ט')
  })
})

/* ===== the estimate disclosure ============================================ */

describe('disclosureRule', () => {
  it('says nothing about an exact number', () => {
    expect(disclosureRule({ estimated: false, allocated: 10, unallocated: 90 })).toBe('ok')
  })

  it('allows percentages while the unallocated share is small', () => {
    expect(disclosureRule({ estimated: true, allocated: 950, unallocated: 50 })).toBe('ok')
  })

  it('hides percentages once too much is unattributed', () => {
    expect(disclosureRule({ estimated: true, allocated: 700, unallocated: 300 })).toBe('hide_percent')
  })

  /* Nothing allocated and nothing unallocated is not "0% unattributed" — it is
     "the allocation produced nothing", which is a different sentence. */
  it('warns rather than dividing by zero', () => {
    expect(disclosureRule({ estimated: true, allocated: 0, unallocated: 0 })).toBe('warn')
    expect(disclosureRule({ estimated: true })).toBe('warn')
  })
})
