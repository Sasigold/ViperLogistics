import { useEffect, useState } from 'react'
import { useQueries } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import { specsFor } from './reportState'
import { specProblems } from '../dashboard/builder/widgetSpec'
import { previousRange } from '../dashboard/dashboardRange'
import type { Catalog, QuerySpec, RunResult } from '../dashboard/builder/widgetSpec'
import type { DimChoice, ReportState } from './reportState'
import type { DateRange } from '../dashboard/dashboardRange'

/**
 * The fan-out: one `reports_run` per breakdown, twice that when comparing.
 *
 * Two details carried over from the builder's preview:
 *
 *   • the queries key on a **debounced** copy of the state, so a filter being
 *     typed does not fire a volley per keystroke;
 *   • results dim while refetching rather than disappear — the panel decides,
 *     this hook only reports `isFetching`.
 *
 * A spec with client-visible problems is not sent at all: the server would
 * only 22023 it, and an error panel for a half-edited filter reads as broken.
 */

export interface PanelRun {
  dim: DimChoice | null
  spec: QuerySpec
  /** undefined = loading; the engine's rows/meta otherwise */
  current?: RunResult
  /** only when compare is on */
  previous?: RunResult
  error?: unknown
  isFetching: boolean
}

const run = (spec: QuerySpec, range: DateRange, ok: boolean) => ({
  queryKey: ['reports_run', spec, range.from, range.to] as const,
  enabled: ok,
  queryFn: async (): Promise<RunResult> => {
    const { data, error } = await supabase.rpc('reports_run', {
      p_spec: spec,
      p_from: range.from,
      p_to: range.to,
    })
    if (error) throw error
    return data as RunResult
  },
})

export function useReportRuns(state: ReportState, catalog: Catalog, ready: boolean) {
  const [debounced, setDebounced] = useState(state)
  useEffect(() => {
    const t = setTimeout(() => setDebounced(state), 350)
    return () => clearTimeout(t)
  }, [state])

  const specs = specsFor(debounced, catalog)
  const prev = previousRange(debounced.range)
  const sendable = specs.map(
    ({ spec }) =>
      ready && !!spec.measure && specProblems(spec, catalog).filter((p) => !p.unknown).length === 0,
  )

  const queries = useQueries({
    queries: specs.flatMap(({ spec }, i) => [
      run(spec, debounced.range, sendable[i]),
      ...(debounced.compare ? [run(spec, prev, sendable[i])] : []),
    ]),
  })

  const stride = debounced.compare ? 2 : 1
  const panels: PanelRun[] = specs.map(({ dim, spec }, i) => {
    const cur = queries[i * stride]
    const pre = debounced.compare ? queries[i * stride + 1] : undefined
    return {
      dim,
      spec,
      current: cur?.data,
      previous: pre?.data,
      error: cur?.error ?? undefined,
      isFetching: !!cur?.isFetching || !!pre?.isFetching,
    }
  })

  return { panels, debouncedState: debounced }
}
