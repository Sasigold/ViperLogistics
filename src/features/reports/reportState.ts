import { differenceInCalendarDays } from 'date-fns'
import { AGGS, BUCKETS, VIZ_KINDS, allowsNoDimension } from '../dashboard/builder/widgetSpec'
import { defaultRange } from '../dashboard/dashboardRange'
import type {
  Agg,
  Bucket,
  Catalog,
  CatalogField,
  CatalogMeasure,
  Filter,
  QuerySpec,
  VizKind,
} from '../dashboard/builder/widgetSpec'
import type { DateRange } from '../dashboard/dashboardRange'

/**
 * The state of the reports screen, and the pure functions that read it.
 *
 * Same discipline as `widgetSpec.ts`: no React, no Supabase, nothing that
 * touches the network — vitest holds the whole file against plain objects.
 *
 * The one idea this file adds over a widget spec: **one measure, many
 * breakdowns**. The engine runs a single measure × a single dimension per
 * call, so "extended breakdown" is a fan-out — each entry in `dims` becomes
 * its own `QuerySpec` via `toSpec`, and the screen runs them in parallel.
 * Nothing here records a permission: the server answers per panel, per
 * reader, exactly as it does for widgets.
 */

/** one breakdown panel: a groupable field, with an optional chart override */
export interface DimChoice {
  field: string
  /** unset = pick by field kind: time → line, category → bar */
  viz?: VizKind
}

export interface ReportState {
  v: 1
  source: string
  measure: string
  agg: Agg
  filters: Filter[]
  /** 0..MAX_DIMS breakdown panels; empty = one un-broken-down number */
  dims: DimChoice[]
  /** one bucket for every time breakdown on the screen */
  bucket: Bucket
  compare: boolean
  range: DateRange
}

export const MAX_DIMS = 4

/* ===== reading the catalogue ============================================== */

export const measureOf = (cat: Catalog, s: ReportState): CatalogMeasure | undefined =>
  cat.measures.find((m) => m.key === s.measure && m.source_key === s.source)

export const fieldOf = (cat: Catalog, key: string): CatalogField | undefined =>
  cat.fields.find((f) => f.key === key)

/* ===== state → engine specs =============================================== */

/**
 * One breakdown → one engine-legal spec. `dim = null` is the summary run —
 * the single number the stat row shows, legal only for measures that allow
 * `__none__`.
 */
export function toSpec(state: ReportState, dim: DimChoice | null, cat: Catalog): QuerySpec {
  const field = dim ? fieldOf(cat, dim.field) : undefined
  const isTime = field?.kind === 'time'
  const dimension = dim
    ? isTime
      ? ({ type: 'time', field: dim.field, bucket: state.bucket } as const)
      : ({ type: 'cat', field: dim.field } as const)
    : null
  return {
    v: 1,
    variant: 'query',
    source: state.source,
    measure: state.measure,
    agg: state.agg,
    dimension,
    filters: state.filters,
    // a time series reads left to right; anything else reads biggest first
    sort: isTime ? { by: 'dimension', dir: 'asc' } : { by: 'measure', dir: 'desc' },
    // the engine's ceiling, not the widget default of 12: a report wants the
    // whole distribution, and `meta.truncated` says so when it will not fit
    limit: 50,
    range_mode: 'page',
    viz: panelViz(dim, field),
    // entity colours wherever the dimension carries them (status, customer);
    // the renderer falls back to the brand palette when a row has no colour
    viz_opts: dim ? { palette: 'entity' } : {},
    goal: null,
  }
}

/** the chart a panel draws unless its DimChoice says otherwise */
export function panelViz(dim: DimChoice | null, field: CatalogField | undefined): VizKind {
  if (!dim) return 'number'
  if (dim.viz && VIZ_KINDS.includes(dim.viz)) return dim.viz
  return field?.kind === 'time' ? 'line' : 'bar'
}

/** the runs the screen needs: one per breakdown, or the bare summary */
export function specsFor(state: ReportState, cat: Catalog): { dim: DimChoice | null; spec: QuerySpec }[] {
  if (state.dims.length === 0) return [{ dim: null, spec: toSpec(state, null, cat) }]
  return state.dims.map((dim) => ({ dim, spec: toSpec(state, dim, cat) }))
}

/* ===== the 50-row defence ================================================
   A day bucket over a quarter is 90 rows against a 50-row engine ceiling —
   the chart would silently show the first 50. Auto-bucketing keeps a time
   series inside the ceiling; `meta.truncated` still guards the manual
   override.                                                                  */

export function autoBucket(range: DateRange): Bucket {
  const days = Math.max(0, differenceInCalendarDays(new Date(range.to), new Date(range.from)))
  if (days <= 31) return 'day'
  if (days <= 120) return 'week'
  return 'month'
}

/* ===== normalising ========================================================
   Anything at all → a state. Never throws. The input is a `saved_filters`
   row or a URL param written by an older (or newer) release; the
   `normalizeSpec` contract applies — unknown values are dropped to defaults
   rather than crashing the screen.                                           */

const has = <T extends string>(list: readonly T[], v: unknown): v is T =>
  typeof v === 'string' && (list as readonly string[]).includes(v)

const str = (v: unknown, fallback = ''): string => (typeof v === 'string' ? v : fallback)

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/

function normalizeRange(raw: unknown): DateRange {
  const o = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {}
  const from = str(o.from)
  const to = str(o.to)
  if (!ISO_DATE.test(from) || !ISO_DATE.test(to) || to < from) return defaultRange()
  return { from, to }
}

function normalizeDims(raw: unknown): DimChoice[] {
  if (!Array.isArray(raw)) return []
  const out: DimChoice[] = []
  for (const d of raw) {
    if (!d || typeof d !== 'object') continue
    const o = d as Record<string, unknown>
    const field = str(o.field)
    if (!field || out.some((x) => x.field === field)) continue
    out.push({ field, ...(has(VIZ_KINDS, o.viz) ? { viz: o.viz } : {}) })
    if (out.length >= MAX_DIMS) break
  }
  return out
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
      // kept verbatim like normalizeSpec: an unknown op renders read-only
      op: str(o.op) as Filter['op'],
      ...(o.value === undefined ? {} : { value: o.value as Filter['value'] }),
    })
    if (out.length >= 8) break
  }
  return out
}

export function normalizeReportState(raw: unknown): ReportState {
  const o = raw && typeof raw === 'object' && !Array.isArray(raw) ? (raw as Record<string, unknown>) : {}
  const range = normalizeRange(o.range)
  return {
    v: 1,
    source: str(o.source),
    measure: str(o.measure),
    agg: has(AGGS, o.agg) ? o.agg : 'sum',
    filters: normalizeFilters(o.filters),
    dims: normalizeDims(o.dims),
    bucket: has(BUCKETS, o.bucket) ? o.bucket : autoBucket(range),
    compare: o.compare === true,
    range,
  }
}

/* ===== the URL ============================================================
   The whole state rides in one param, so a report is a link. Safe to share
   by construction: the server re-evaluates permissions for whoever opens
   it — the URL carries *what to compute*, never who may see it.              */

export function stateToParam(state: ReportState): string {
  return JSON.stringify(state)
}

export function stateFromParam(raw: string | null | undefined): ReportState | null {
  if (!raw) return null
  try {
    return normalizeReportState(JSON.parse(raw))
  } catch {
    return null
  }
}

/* ===== defaults =========================================================== */

/** a fresh state over the first measure the catalogue serves */
export function blankReportState(cat: Catalog): ReportState {
  const source = cat.sources[0]
  const measure = cat.measures.find((m) => m.source_key === source?.key)
  const range = defaultRange()
  return {
    v: 1,
    source: source?.key ?? '',
    measure: measure?.key ?? '',
    agg: measure?.default_agg ?? 'sum',
    filters: [],
    dims: [],
    bucket: autoBucket(range),
    compare: false,
    range,
  }
}

/** may this state legally run with no breakdown at all? */
export function summaryAllowed(state: ReportState, cat: Catalog): boolean {
  return allowsNoDimension(measureOf(cat, state))
}
