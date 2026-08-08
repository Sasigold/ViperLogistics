import type { WidgetSize } from '../dashboardTypes'

/**
 * The shape of a user-built widget, and the pure functions that read it.
 *
 * No React, no Supabase, no imports from anything that touches the network —
 * the same discipline `layout.ts` and `pricingSchema.ts` keep, so vitest can
 * hold the whole file against plain objects.
 *
 * The spec says *what to compute*, never *who may see it*. Not one field here
 * records a permission, an author, or a resolved scope: the server decides all
 * three, per reader, on every run. That is the entire reason a shared widget is
 * safe — it is re-evaluated against whoever is looking at it.
 */

/* ===== the vocabulary ===================================================== */

export const VIZ_KINDS = [
  'number',
  'bar',
  'row',
  'line',
  'area',
  'donut',
  'table',
  'gauge',
  'note',
] as const
export type VizKind = (typeof VIZ_KINDS)[number]

export const BUCKETS = ['day', 'week', 'month', 'quarter'] as const
export type Bucket = (typeof BUCKETS)[number]

export const AGGS = ['sum', 'count', 'count_distinct', 'avg', 'min', 'max'] as const
export type Agg = (typeof AGGS)[number]

/**
 * Operators, and the number of jsonb slots each one reads.
 *
 * Every filter occupies exactly one slot in the params array regardless of op —
 * `between` puts a two-element array in its slot, and the valueless ops put
 * null there. Keeping arity at one means the server's slot index is simply the
 * filter's ordinal, and there is no bookkeeping to get wrong.
 */
export const FILTER_OPS = [
  'eq',
  'ne',
  'in',
  'not_in',
  'gt',
  'gte',
  'lt',
  'lte',
  'between',
  'is_null',
  'is_not_null',
  'is_true',
  'is_false',
] as const
export type FilterOp = (typeof FILTER_OPS)[number]

export const OP_LABELS: Record<FilterOp, string> = {
  eq: 'שווה ל',
  ne: 'שונה מ',
  in: 'אחד מ',
  not_in: 'לא אחד מ',
  gt: 'גדול מ',
  gte: 'גדול או שווה ל',
  lt: 'קטן מ',
  lte: 'קטן או שווה ל',
  between: 'בין',
  is_null: 'ריק',
  is_not_null: 'אינו ריק',
  is_true: 'כן',
  is_false: 'לא',
}

/** ops that take no value at all — the editor draws no input for these */
export const VALUELESS_OPS: readonly FilterOp[] = ['is_null', 'is_not_null', 'is_true', 'is_false']
/** ops whose value is a list */
export const LIST_OPS: readonly FilterOp[] = ['in', 'not_in']

export const BUCKET_LABELS: Record<Bucket, string> = {
  day: 'יומי',
  week: 'שבועי',
  month: 'חודשי',
  quarter: 'רבעוני',
}

export const AGG_LABELS: Record<Agg, string> = {
  sum: 'סכום',
  count: 'ספירה',
  count_distinct: 'ספירה ייחודית',
  avg: 'ממוצע',
  min: 'מינימום',
  max: 'מקסימום',
}

/* ===== the spec =========================================================== */

export type FilterValue = string | number | boolean | (string | number)[] | null

export interface Filter {
  /** local only, for React keys and reordering; the server ignores it */
  id: string
  field: string
  op: FilterOp
  value?: FilterValue
}

export interface TimeDimension {
  type: 'time'
  field: string
  bucket: Bucket
}
export interface CatDimension {
  type: 'cat'
  field: string
}
export type Dimension = TimeDimension | CatDimension

export interface VizOpts {
  show_legend?: boolean
  show_values?: boolean
  stacked?: boolean
  decimals?: 0 | 1 | 2
  /** 'entity' paints each bar with the customer's or status's own colour */
  palette?: 'brand' | 'entity'
  compare_prev?: boolean
}

export interface QuerySpec {
  v: 1
  variant: 'query'
  source: string
  measure: string
  agg: Agg
  dimension?: Dimension | null
  /** flat and ANDed, capped at MAX_FILTERS — see the note below */
  filters: Filter[]
  sort: { by: 'measure' | 'dimension'; dir: 'asc' | 'desc' }
  limit: number
  /** 'page' follows the dashboard's date picker; 'relative' pins a window */
  range_mode: 'page' | 'relative'
  range_days?: number
  viz: VizKind
  viz_opts: VizOpts
  goal?: { target: number; direction: 'up' | 'down' } | null
}

export interface NoteSpec {
  v: 1
  variant: 'note'
  body: string
  tone?: 'default' | 'info' | 'warn'
}

export type WidgetSpec = QuerySpec | NoteSpec

export const MAX_FILTERS = 8
export const MAX_LIMIT = 50
export const MAX_NOTE = 2000

/**
 * Filters are a flat ANDed list, not a tree — the deliberate anti-copy of
 * `app.price_cond` (0017).
 *
 * Two of that function's properties are wrong here. It recurses with no depth
 * bound, and it *fails open*: an operator it does not recognise returns true.
 * For a pricing condition that is a defensible default; for a filter it means
 * showing more rows than the author asked for, which is the one direction a
 * data filter must never fail in. So: a bounded list, and an unknown operator
 * is rejected by the server rather than ignored.
 *
 * Eight leaves covers every dashboard filter worth having. If OR is ever
 * needed it arrives as a value-level `in`, not as a node type.
 */

/* ===== the run result ===================================================== */

export interface RunRow {
  key: string | null
  label: string
  color: string | null
  value: number | null
  n: number
}

export interface RunMeta {
  measure?: string
  agg?: Agg
  unit?: 'count' | 'money' | 'hours' | 'volume' | 'percent'
  dimension?: string | null
  bucket?: Bucket | null
  total?: number | null
  row_count?: number
  truncated?: boolean
  /** trap: a not-null-default-0 price column cannot distinguish never-set from zero */
  presence?: { present: number; missing: number; zero: number } | null
  fans_out?: boolean
  estimated?: boolean
  allocated?: number | null
  unallocated?: number | null
  unrated_shifts?: number | null
  scope_note?: string | null
  /** the reader may not see this at all */
  denied?: boolean
  /** …because their data scope is narrowed and the measure is company-wide */
  scoped?: boolean
  /** a key the server no longer knows: version skew, not a permission problem */
  unsupported?: string
}

export interface RunResult {
  rows: RunRow[] | null
  meta: RunMeta
}

/* ===== normalising ========================================================
   Anything at all → a spec. Never throws.

   The input is jsonb written by an older release of this file, and a spec that
   threw on parse would take down a whole dashboard for one bad widget. Same
   contract as `normalizeLayout`.

   The `CondEditor` rule (PricingTab.tsx) applies throughout: a value this
   version does not recognise is **kept and flagged**, never rewritten. The
   editor renders those rows read-only, and they round-trip byte-identical. A
   builder that quietly repaired specs would destroy widgets built by a newer
   client the moment an older one opened them.                                */

const has = <T extends string>(list: readonly T[], v: unknown): v is T =>
  typeof v === 'string' && (list as readonly string[]).includes(v)

const str = (v: unknown, fallback = ''): string => (typeof v === 'string' ? v : fallback)

const num = (v: unknown, fallback: number): number =>
  typeof v === 'number' && Number.isFinite(v) ? v : fallback

export function normalizeSpec(raw: unknown): WidgetSpec {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return emptyNote()
  const o = raw as Record<string, unknown>

  if (o.variant === 'note') {
    return {
      v: 1,
      variant: 'note',
      body: str(o.body).slice(0, MAX_NOTE),
      tone: has(['default', 'info', 'warn'] as const, o.tone) ? o.tone : 'default',
    }
  }

  const dim = normalizeDimension(o.dimension)
  return {
    v: 1,
    variant: 'query',
    source: str(o.source),
    measure: str(o.measure),
    agg: has(AGGS, o.agg) ? o.agg : 'sum',
    dimension: dim,
    filters: normalizeFilters(o.filters),
    sort: normalizeSort(o.sort, dim),
    limit: Math.max(1, Math.min(Math.round(num(o.limit, 12)), MAX_LIMIT)),
    range_mode: o.range_mode === 'relative' ? 'relative' : 'page',
    ...(o.range_mode === 'relative'
      ? { range_days: Math.max(1, Math.min(Math.round(num(o.range_days, 30)), 400)) }
      : {}),
    // an unrecognised viz is PRESERVED here and only falls back at render time
    viz: typeof o.viz === 'string' ? (o.viz as VizKind) : 'number',
    viz_opts: normalizeVizOpts(o.viz_opts),
    goal: normalizeGoal(o.goal),
  }
}

function emptyNote(): NoteSpec {
  return { v: 1, variant: 'note', body: '', tone: 'default' }
}

function normalizeDimension(raw: unknown): Dimension | null {
  if (!raw || typeof raw !== 'object') return null
  const d = raw as Record<string, unknown>
  const field = str(d.field)
  if (!field) return null
  // `type` is a client convenience; the server reads report_fields.kind and
  // decides for itself whether to date_trunc. A spec that mislabels a text
  // column as a time dimension changes nothing about the SQL emitted.
  if (d.type === 'time') {
    return { type: 'time', field, bucket: has(BUCKETS, d.bucket) ? d.bucket : 'week' }
  }
  return { type: 'cat', field }
}

function normalizeFilters(raw: unknown): Filter[] {
  if (!Array.isArray(raw)) return []
  const out: Filter[] = []
  for (const [i, f] of raw.entries()) {
    if (!f || typeof f !== 'object') continue
    const o = f as Record<string, unknown>
    const field = str(o.field)
    if (!field) continue
    out.push({
      id: str(o.id) || `f${i}`,
      field,
      // an op this version does not know is kept verbatim; `specProblems`
      // flags it and the editor draws that row read-only
      op: str(o.op) as FilterOp,
      ...(o.value === undefined ? {} : { value: o.value as FilterValue }),
    })
    if (out.length >= MAX_FILTERS) break
  }
  return out
}

function normalizeSort(raw: unknown, dim: Dimension | null): QuerySpec['sort'] {
  const o = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {}
  const by = o.by === 'dimension' ? 'dimension' : o.by === 'measure' ? 'measure' : null
  const dir = o.dir === 'asc' ? 'asc' : o.dir === 'desc' ? 'desc' : null
  // a time series reads left to right; anything else reads biggest first
  if (dim?.type === 'time') return { by: by ?? 'dimension', dir: dir ?? 'asc' }
  return { by: by ?? 'measure', dir: dir ?? 'desc' }
}

function normalizeVizOpts(raw: unknown): VizOpts {
  if (!raw || typeof raw !== 'object') return {}
  const o = raw as Record<string, unknown>
  const out: VizOpts = {}
  if (typeof o.show_legend === 'boolean') out.show_legend = o.show_legend
  if (typeof o.show_values === 'boolean') out.show_values = o.show_values
  if (typeof o.stacked === 'boolean') out.stacked = o.stacked
  if (o.decimals === 0 || o.decimals === 1 || o.decimals === 2) out.decimals = o.decimals
  if (o.palette === 'brand' || o.palette === 'entity') out.palette = o.palette
  if (typeof o.compare_prev === 'boolean') out.compare_prev = o.compare_prev
  return out
}

function normalizeGoal(raw: unknown): QuerySpec['goal'] {
  if (!raw || typeof raw !== 'object') return null
  const o = raw as Record<string, unknown>
  if (typeof o.target !== 'number' || !Number.isFinite(o.target)) return null
  return { target: o.target, direction: o.direction === 'down' ? 'down' : 'up' }
}

export const isQuery = (s: WidgetSpec): s is QuerySpec => s.variant === 'query'
export const isNote = (s: WidgetSpec): s is NoteSpec => s.variant === 'note'

/* ===== the catalogue, as the client sees it ===============================
   Mirrors the three report_* tables. There is no hardcoded copy of any of it:
   the whole point of serving the catalogue is that a client-side mirror is a
   thing that drifts.                                                         */

export interface CatalogSource {
  key: string
  label_he: string
  row_noun_he: string
  scope_note_he: string | null
  sort_order: number
}

export interface CatalogMeasure {
  key: string
  source_key: string
  label_he: string
  hint_he: string | null
  allowed_aggs: Agg[]
  default_agg: Agg
  unit: RunMeta['unit']
  is_estimate: boolean
  fanout_safe: boolean
  allowed_dims: string[] | null
  sort_order: number
}

export interface CatalogField {
  key: string
  source_key: string
  label_he: string
  kind: 'cat' | 'time' | 'num' | 'bool'
  col_type: 'uuid' | 'text' | 'numeric' | 'int' | 'date' | 'bool'
  fans_out: boolean
  nullable: boolean
  is_estimate: boolean
  can_group: boolean
  can_filter: boolean
  allowed_ops: FilterOp[]
  sort_order: number
}

export interface Catalog {
  sources: CatalogSource[]
  measures: CatalogMeasure[]
  fields: CatalogField[]
}

export const EMPTY_CATALOG: Catalog = { sources: [], measures: [], fields: [] }

const byKey = <T extends { key: string }>(list: T[]) => new Map(list.map((x) => [x.key, x]))

/** dimensions this measure may legally be broken down by, already permission-filtered */
export function dimensionsFor(cat: Catalog, measure: CatalogMeasure | undefined): CatalogField[] {
  if (!measure) return []
  return cat.fields.filter((f) => {
    if (f.source_key !== measure.source_key || !f.can_group) return false
    // the same array the server validates against, fetched from the server —
    // so the picker and the guard cannot disagree
    if (measure.allowed_dims && !measure.allowed_dims.includes(f.key)) return false
    // a dimension that multiplies rows is illegal for a measure that sums at
    // the un-multiplied level; offering it would produce a confident wrong number
    if (f.fans_out && !measure.fanout_safe) return false
    return true
  })
}

/** may this measure be shown with no breakdown at all? */
export function allowsNoDimension(measure: CatalogMeasure | undefined): boolean {
  if (!measure) return false
  return !measure.allowed_dims || measure.allowed_dims.includes('__none__')
}

export function filterableFields(cat: Catalog, sourceKey: string): CatalogField[] {
  return cat.fields.filter((f) => f.source_key === sourceKey && f.can_filter && f.allowed_ops.length > 0)
}

/* ===== validation =========================================================
   Advisory only. The server re-checks every one of these and is the actual
   boundary; this exists so the editor can say what is wrong before the user
   presses save.                                                              */

export interface SpecProblem {
  /** which control to point at */
  at: 'source' | 'measure' | 'agg' | 'dimension' | 'viz' | 'limit' | 'note'
  /** a filter's local id, when `at` is a filter row */
  filterId?: string
  message: string
  /** true when the value is unrecognised rather than wrong — preserve, don't fix */
  unknown?: boolean
}

export function specProblems(spec: WidgetSpec, cat: Catalog): SpecProblem[] {
  const out: SpecProblem[] = []
  if (isNote(spec)) {
    if (spec.body.trim().length === 0) out.push({ at: 'note', message: 'הפתק ריק' })
    return out
  }

  const source = cat.sources.find((s) => s.key === spec.source)
  if (!source) {
    out.push({ at: 'source', message: 'מקור הנתונים אינו בקטלוג', unknown: true })
    return out
  }
  const measure = cat.measures.find((m) => m.key === spec.measure && m.source_key === spec.source)
  if (!measure) {
    out.push({ at: 'measure', message: 'המדד אינו בקטלוג', unknown: true })
    return out
  }
  if (!measure.allowed_aggs.includes(spec.agg)) {
    out.push({ at: 'agg', message: 'סוג החישוב אינו נתמך למדד הזה' })
  }

  if (spec.dimension) {
    const legal = dimensionsFor(cat, measure)
    if (!legal.some((f) => f.key === spec.dimension?.field)) {
      const known = cat.fields.some((f) => f.key === spec.dimension?.field)
      out.push({
        at: 'dimension',
        message: known ? 'הפילוח הזה אינו חוקי למדד הזה' : 'הפילוח אינו בקטלוג',
        unknown: !known,
      })
    }
  } else if (!allowsNoDimension(measure)) {
    out.push({ at: 'dimension', message: 'המדד הזה מחייב פילוח' })
  }

  const fields = byKey(cat.fields)
  for (const f of spec.filters) {
    const def = fields.get(f.field)
    if (!def || def.source_key !== spec.source || !def.can_filter) {
      out.push({ at: 'dimension', filterId: f.id, message: 'שדה הסינון אינו בקטלוג', unknown: true })
      continue
    }
    if (!def.allowed_ops.includes(f.op)) {
      out.push({ at: 'dimension', filterId: f.id, message: 'תנאי הסינון אינו נתמך לשדה הזה', unknown: true })
      continue
    }
    const problem = filterValueProblem(f)
    if (problem) out.push({ at: 'dimension', filterId: f.id, message: problem })
  }
  if (spec.filters.length > MAX_FILTERS) {
    out.push({ at: 'dimension', message: `עד ${MAX_FILTERS} תנאי סינון` })
  }

  if (!VIZ_KINDS.includes(spec.viz)) {
    out.push({ at: 'viz', message: 'סוג תצוגה שאינו מוכר לגרסה הזו', unknown: true })
  } else if (!vizAllows(spec.viz, spec.dimension ?? null)) {
    out.push({ at: 'viz', message: 'סוג התצוגה אינו מתאים לפילוח שנבחר' })
  }
  return out
}

function filterValueProblem(f: Filter): string | null {
  if (VALUELESS_OPS.includes(f.op)) return null
  if (LIST_OPS.includes(f.op)) {
    return Array.isArray(f.value) && f.value.length > 0 ? null : 'בחר ערך אחד לפחות'
  }
  if (f.op === 'between') {
    return Array.isArray(f.value) && f.value.length === 2 ? null : 'הזן טווח, שני ערכים'
  }
  if (f.value === undefined || f.value === null || f.value === '') return 'חסר ערך'
  return Array.isArray(f.value) ? 'ערך יחיד, לא רשימה' : null
}

/* ===== visualisation fit ==================================================
   One table, so the picker and the validator cannot disagree about which
   chart a spec can wear.                                                     */

export const VIZ_NEEDS: Record<VizKind, 'none' | 'optional' | 'required'> = {
  number: 'none',
  gauge: 'none',
  note: 'none',
  bar: 'required',
  row: 'required',
  donut: 'required',
  table: 'required',
  line: 'required',
  area: 'required',
}

/** charts that only make sense along an axis of time */
const TIME_ONLY: readonly VizKind[] = ['line', 'area']

export function vizAllows(viz: VizKind, dim: Dimension | null): boolean {
  const needs = VIZ_NEEDS[viz]
  if (!needs) return false
  if (needs === 'none') return dim === null
  if (needs === 'required' && dim === null) return false
  if (TIME_ONLY.includes(viz) && dim?.type !== 'time') return false
  return true
}

/** what to draw when the stored viz is one this release does not know */
export function effectiveViz(spec: QuerySpec): VizKind {
  if (VIZ_KINDS.includes(spec.viz) && vizAllows(spec.viz, spec.dimension ?? null)) return spec.viz
  return spec.dimension ? 'table' : 'number'
}

/* ===== the auto title ===================================================== */

/**
 * "הכנסות לפי לקוח, שבועי" — filled into the title field as the user builds,
 * and abandoned the moment they type their own.
 */
export function specTitle(spec: WidgetSpec, cat: Catalog): string {
  if (isNote(spec)) return 'פתק'
  const measure = cat.measures.find((m) => m.key === spec.measure)
  if (!measure) return 'ווידג׳ט'
  let title = measure.label_he
  if (spec.agg !== measure.default_agg && AGG_LABELS[spec.agg]) {
    title = `${AGG_LABELS[spec.agg]} ${title}`
  }
  if (spec.dimension) {
    const field = cat.fields.find((f) => f.key === spec.dimension?.field)
    if (field) title += ` לפי ${field.label_he}`
    if (spec.dimension.type === 'time') title += `, ${BUCKET_LABELS[spec.dimension.bucket]}`
  }
  return title
}

/* ===== the estimate disclosure ============================================
   0041 left this as a comment on `margin.by_customer`: "the card refuses to
   show percentages when the unallocated share is too large". Here it is as a
   function, so a test can hold it.

   Payroll is allocated to customers through `attendance_entries.task_ids`,
   weighted by `tasks.hours_count`. A shift with no task ids — warehouse work,
   manual reports — cannot be allocated at all and lands in `unallocated`
   rather than being spread silently across customers. Past a threshold, the
   per-customer percentages stop meaning anything and the widget says so.     */

export const UNALLOCATED_LIMIT = 0.15

export function disclosureRule(meta: RunMeta): 'ok' | 'hide_percent' | 'warn' {
  if (!meta.estimated) return 'ok'
  const denom = (meta.allocated ?? 0) + (meta.unallocated ?? 0)
  if (denom === 0) return 'warn'
  return (meta.unallocated ?? 0) / denom > UNALLOCATED_LIMIT ? 'hide_percent' : 'ok'
}

/* ===== defaults =========================================================== */

export function blankQuerySpec(cat: Catalog): QuerySpec {
  const source = cat.sources[0]
  const measure = cat.measures.find((m) => m.source_key === source?.key)
  return {
    v: 1,
    variant: 'query',
    source: source?.key ?? '',
    measure: measure?.key ?? '',
    agg: measure?.default_agg ?? 'sum',
    dimension: null,
    filters: [],
    sort: { by: 'measure', dir: 'desc' },
    limit: 12,
    range_mode: 'page',
    viz: 'number',
    viz_opts: {},
    goal: null,
  }
}

export function blankNoteSpec(): NoteSpec {
  return emptyNote()
}

/** the sizes a viz can wear; the first is what a fresh widget gets */
export const VIZ_SIZES: Record<VizKind, readonly WidgetSize[]> = {
  number: ['sm', 'md'],
  gauge: ['sm', 'md'],
  note: ['sm', 'md', 'lg', 'xl'],
  donut: ['sm', 'md'],
  bar: ['md', 'lg', 'xl'],
  row: ['md', 'lg', 'xl'],
  line: ['md', 'lg', 'xl'],
  area: ['md', 'lg', 'xl'],
  table: ['md', 'lg', 'xl'],
}
