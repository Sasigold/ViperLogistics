import { useMemo } from 'react'
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import { isCustomId, toUuid } from './builder/customRegistry'
import type { RunResult } from './builder/widgetSpec'
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
  const { rangeKeys, staticKeys, prevKeys, opts, customIds } = useMemo(() => {
    const inRange = new Set<string>()
    const inStatic = new Set<string>()
    const inPrev = new Set<string>()
    const custom: string[] = []
    const merged: WidgetOpts = {}

    for (const item of items) {
      // a user-built widget is answered by dashboard_widgets_run, not by a
      // section — it has no fixed key the server could know in advance
      if (isCustomId(item.id)) {
        const uuid = toUuid(item.id)
        if (uuid) custom.push(uuid)
        continue
      }
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
    return {
      rangeKeys: sorted(inRange),
      staticKeys: sorted(inStatic),
      prevKeys: sorted(inPrev),
      opts: merged,
      customIds: custom.sort(),
    }
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

  /* One round trip for every user-built widget on the grid, the same bargain
     `dashboard_sections` makes: twelve custom widgets are not twelve requests.
     A widget whose spec pins its own window still goes through here — the
     server reads `range_mode` off the spec, so the page range is only a
     default. */
  const customQ = useQuery({
    queryKey: ['dashboard', 'custom', range.from, range.to, customIds.join(',')],
    enabled: customIds.length > 0,
    placeholderData: keepPreviousData,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('dashboard_widgets_run', {
        p_ids: customIds,
        p_from: range.from,
        p_to: range.to,
      })
      if (error) throw error
      return (data ?? {}) as Record<string, RunResult | null>
    },
  })

  /* Depend on the payloads and flags, never on the query objects themselves:
     react-query hands back a fresh object on every render, so a memo keyed on
     those would never hold — and this value goes into the page context, which
     would then re-render every widget on the grid on every keystroke in the
     date field. */
  const rangeData = rangeQ.data
  const staticData = staticQ.data
  const prevData = prevQ.data
  const customData = customQ.data
  const isLoading = (rangeQ.isLoading && rangeKeys.length > 0) || (staticQ.isLoading && staticKeys.length > 0)
  const error = rangeQ.error ?? staticQ.error
  const refetchRange = rangeQ.refetch
  const refetchStatic = staticQ.refetch
  const refetchCustom = customQ.refetch

  return useMemo(() => {
    const merged: SectionMap = { ...(staticData ?? {}), ...(rangeData ?? {}) }
    return {
      section: (key: string) => merged[key],
      prevSection: (key: string) => prevData?.[key],
      /* Same three-way distinction the sections use: `undefined` is "not
         loaded", `null` is the server declining. The widget draws a skeleton
         for the first and removes itself for the second. */
      customResult: (uuid: string) => customData?.[uuid],
      /** true only while there is nothing at all to draw */
      isLoading,
      error,
      refetch: () => {
        void refetchRange()
        void refetchStatic()
        void refetchCustom()
      },
    }
  }, [rangeData, staticData, prevData, customData, isLoading, error, refetchRange, refetchStatic, refetchCustom])
}

export type DashboardSections = ReturnType<typeof useDashboardSections>
