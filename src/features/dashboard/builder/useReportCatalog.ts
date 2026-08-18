import { useQuery } from '@tanstack/react-query'
import { supabase } from '../../../lib/supabase'
import { useAuth } from '../../../state/auth'
import { EMPTY_CATALOG } from './widgetSpec'
import type { Catalog, CatalogField, CatalogMeasure, CatalogSource } from './widgetSpec'

/**
 * What the builder is allowed to ask for, straight from the server.
 *
 * There is deliberately no hardcoded copy of any of this in the client. The
 * pricing screen keeps its own `PRICING_VARS` mirror of a server-side list and
 * that mirror has already drifted; serving the catalogue instead means the
 * picker and the guard read the same rows and cannot disagree.
 *
 * Reading the three tables directly rather than through an RPC is fine here:
 * `report_sources` / `report_measures` / `report_fields` carry a plain
 * `select` policy for `authenticated` (0043), and knowing that a field exists
 * grants nothing — every one of them is separately gated at run time inside
 * `app.report_run`. What the client must never do is *derive* a permission
 * requirement from a spec; that answer comes from the server too, on each
 * widget row.
 *
 * Half an hour of staleness is right for a table only a migration can write.
 */

const SOURCE_COLS = 'key, label_he, row_noun_he, scope_note_he, sort_order'
const MEASURE_COLS =
  'key, source_key, label_he, hint_he, allowed_aggs, default_agg, unit, is_estimate, fanout_safe, allowed_dims, sort_order'
const FIELD_COLS =
  'key, source_key, label_he, kind, col_type, fans_out, nullable, is_estimate, can_group, can_filter, allowed_ops, sort_order'

/**
 * `enabled` exists for callers that only *might* need the catalogue. The
 * dashboard was fetching it on every load for every user — three table reads on
 * the most-visited screen in the product, for a builder a driver or a client
 * can never open.
 */
export function useReportCatalog(enabled = true) {
  const me = useAuth((s) => s.me)
  const query = useQuery({
    queryKey: ['report_catalog'],
    enabled: enabled && !!me,
    staleTime: 30 * 60 * 1000,
    gcTime: 60 * 60 * 1000,
    queryFn: async (): Promise<Catalog> => {
      const [sources, measures, fields] = await Promise.all([
        supabase.from('report_sources').select(SOURCE_COLS).order('sort_order'),
        supabase.from('report_measures').select(MEASURE_COLS).order('sort_order'),
        supabase.from('report_fields').select(FIELD_COLS).order('sort_order'),
      ])
      if (sources.error) throw sources.error
      if (measures.error) throw measures.error
      if (fields.error) throw fields.error
      return {
        sources: (sources.data ?? []) as CatalogSource[],
        measures: (measures.data ?? []) as CatalogMeasure[],
        fields: (fields.data ?? []) as CatalogField[],
      }
    },
  })

  return {
    catalog: query.data ?? EMPTY_CATALOG,
    isLoading: query.isLoading,
    error: query.error,
  }
}
