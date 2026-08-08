import { useMemo } from 'react'
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import type { DateRange } from './dashboardRange'
import type { LayoutItem, WidgetDef, WidgetOpts } from './dashboardTypes'

export type SectionMap = Record<string, unknown>

async function fetchSections(keys: string[], range: DateRange, opts: WidgetOpts): Promise<SectionMap> {
  if (keys.length === 0) return {}
  const { data, error } = await supabase.rpc('dashboard_sections', {
    p_sections: keys,
    p_from: range.from,
    p_to: range.to,
    p_opts: opts,
  })
  if (error) throw error
  return (data ?? {}) as SectionMap
}

/**
 * One request for everything the visible widgets need, and nothing for what
 * they don't.
 *
 * The union has to be computed here rather than inside each widget: the server
 * is told which sections to compute, so the question "what is on screen" must
 * be answered before the first widget renders. Hiding a widget shrinks the
 * next request — which is the whole point of a dispatching RPC.
 *
 * Three queries rather than one, so that nudging a date does not refetch
 * everything:
 *   range  — sections whose widgets react to the date range
 *   static — sections that ignore it (pending approvals, the forecast)
 *   prev   — the same span before, for the widgets that show a delta
 */
export function useDashboardSections(
  items: LayoutItem[],
  byId: Map<string, WidgetDef>,
  range: DateRange,
  prev: DateRange,
) {
  const { rangeKeys, staticKeys, prevKeys, opts } = useMemo(() => {
    const inRange = new Set<string>()
    const inStatic = new Set<string>()
    const inPrev = new Set<string>()
    const merged: WidgetOpts = {}

    for (const item of items) {
      const def = byId.get(item.id)
      if (!def?.sections?.length) continue
      for (const s of def.sections) {
        ;(def.usesRange ? inRange : inStatic).add(s)
        if (def.usesRange && def.wantsDelta) inPrev.add(s)
      }
      // per-placement options are merged into one bag: `bucket` and `limit`
      // are read by the server for whichever section asks for them
      if (item.opts) Object.assign(merged, item.opts)
    }
    // sorted so the query key is stable no matter how the grid is arranged
    const sorted = (s: Set<string>) => [...s].sort()
    return { rangeKeys: sorted(inRange), staticKeys: sorted(inStatic), prevKeys: sorted(inPrev), opts: merged }
  }, [items, byId])

  const rangeQ = useQuery({
    queryKey: ['dashboard', 'sections', 'range', range.from, range.to, rangeKeys.join(','), opts],
    enabled: rangeKeys.length > 0,
    // nudging a date should not collapse the grid into skeletons
    placeholderData: keepPreviousData,
    queryFn: () => fetchSections(rangeKeys, range, opts),
  })

  const staticQ = useQuery({
    queryKey: ['dashboard', 'sections', 'static', staticKeys.join(','), opts],
    enabled: staticKeys.length > 0,
    staleTime: 5 * 60_000,
    queryFn: () => fetchSections(staticKeys, range, opts),
  })

  const prevQ = useQuery({
    queryKey: ['dashboard', 'sections', 'range', prev.from, prev.to, prevKeys.join(','), opts],
    enabled: prevKeys.length > 0,
    staleTime: 5 * 60_000,
    queryFn: () => fetchSections(prevKeys, prev, opts),
  })

  return useMemo(() => {
    const merged: SectionMap = { ...(staticQ.data ?? {}), ...(rangeQ.data ?? {}) }
    return {
      section: (key: string) => merged[key],
      prevSection: (key: string) => prevQ.data?.[key],
      /** true only while there is nothing at all to draw */
      isLoading: (rangeQ.isLoading && rangeKeys.length > 0) || (staticQ.isLoading && staticKeys.length > 0),
      error: rangeQ.error ?? staticQ.error,
      refetch: () => {
        void rangeQ.refetch()
        void staticQ.refetch()
      },
    }
  }, [rangeQ, staticQ, prevQ, rangeKeys.length, staticKeys.length])
}

export type DashboardSections = ReturnType<typeof useDashboardSections>
