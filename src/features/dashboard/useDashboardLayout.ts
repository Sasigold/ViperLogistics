import { useCallback, useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { BUILT_IN_DEFAULT, WIDGETS, WIDGETS_BY_ID, WIDGET_IDS } from './registry'
import { normalizeLayout, resolveLayout, toStoredLayout, visibleItems } from './layout'
import type { DashboardLayout, LayoutItem } from './dashboardTypes'
import type { UserKind } from '../../types/domain'

export interface DashboardLayoutRow {
  id: string
  profile_id: string | null
  user_kind: UserKind | null
  name: string | null
  layout: unknown
  updated_at: string
}

const cacheKey = (profileId: string | undefined) => `vl-dashboard:${profileId ?? 'anon'}`

/**
 * The layout, from three places at once.
 *
 * localStorage is a *hydration cache*, not a second source of truth: the first
 * paint should not wait for a round trip, but the server is what decides. The
 * cached copy is overwritten the moment the query resolves — so a layout saved
 * on the phone shows up on the desktop, which is the whole reason this is not
 * simply another `vl-…-prefs` key like the work board uses.
 */
function readCache(profileId: string | undefined): DashboardLayout | null {
  try {
    const raw = localStorage.getItem(cacheKey(profileId))
    return raw ? normalizeLayout(JSON.parse(raw)) : null
  } catch {
    return null
  }
}

function writeCache(profileId: string | undefined, layout: DashboardLayout | null) {
  try {
    if (layout) localStorage.setItem(cacheKey(profileId), JSON.stringify(layout))
    else localStorage.removeItem(cacheKey(profileId))
  } catch {
    /* storage full or blocked — a view preference is not worth failing over */
  }
}

export function useDashboardLayout() {
  const me = useAuth((s) => s.me)
  const has = useAuth((s) => s.has)
  const qc = useQueryClient()
  const profileId = me?.profile.id
  const kind = me?.profile.user_kind

  /* Own rows plus every default row, in one read. RLS already narrows it: a
     non-admin sees their own rows and the defaults, and nothing else. */
  const { data: rows = [], isLoading } = useQuery({
    queryKey: ['dashboard_layouts', profileId],
    enabled: !!profileId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('dashboard_layouts')
        .select('id, profile_id, user_kind, name, layout, updated_at')
        .or(`profile_id.eq.${profileId},profile_id.is.null`)
      if (error) throw error
      return data as DashboardLayoutRow[]
    },
  })

  const mine = rows.find((r) => r.profile_id === profileId && r.name === null)
  const namedViews = useMemo(
    () => rows.filter((r) => r.profile_id === profileId && r.name !== null),
    [rows, profileId],
  )
  const orgForKind = rows.find((r) => r.profile_id === null && r.user_kind === kind)
  const orgGlobal = rows.find((r) => r.profile_id === null && r.user_kind === null)

  /** user → their kind's default → the company default → what ships in the app */
  const fallback = useMemo(
    () => normalizeLayout(orgForKind?.layout) ?? normalizeLayout(orgGlobal?.layout) ?? BUILT_IN_DEFAULT,
    [orgForKind, orgGlobal],
  )

  const saved = useMemo(() => {
    if (mine) return normalizeLayout(mine.layout)
    // nothing from the server yet — show the cached copy rather than a blank
    // grid, and let the query overwrite it when it lands
    return isLoading ? readCache(profileId) : null
  }, [mine, isLoading, profileId])

  const [draft, setDraft] = useState<{ items: LayoutItem[]; hidden: string[] } | null>(null)

  const resolved = useMemo(
    () => ({
      items: resolveLayout(WIDGETS, saved, fallback),
      hidden: saved?.hidden ?? fallback.hidden,
    }),
    [saved, fallback],
  )

  const current = draft ?? resolved
  const visible = useMemo(
    () => visibleItems(current.items, WIDGETS_BY_ID, has, kind),
    [current.items, has, kind],
  )

  useEffect(() => {
    if (mine) writeCache(profileId, normalizeLayout(mine.layout))
  }, [mine, profileId])

  /* ===== writes ========================================================== */

  const invalidate = () => void qc.invalidateQueries({ queryKey: ['dashboard_layouts'] })

  const save = useMutation({
    mutationFn: async (next: { items: LayoutItem[]; hidden: string[]; name?: string | null }) => {
      if (!profileId) throw new Error('אין פרופיל פעיל')
      const layout = toStoredLayout(next.items, next.hidden, WIDGET_IDS)
      const { error } = await supabase.from('dashboard_layouts').upsert(
        {
          profile_id: profileId,
          user_kind: null,
          name: next.name ?? null,
          layout,
          updated_by: profileId,
        },
        { onConflict: 'profile_id,user_kind,name' },
      )
      if (error) throw error
      if ((next.name ?? null) === null) writeCache(profileId, layout)
      return layout
    },
    onSuccess: invalidate,
  })

  /** back to the company default — the row is deleted, not overwritten */
  const reset = useMutation({
    mutationFn: async () => {
      if (!mine) return
      const { error } = await supabase.from('dashboard_layouts').delete().eq('id', mine.id)
      if (error) throw error
      writeCache(profileId, null)
    },
    onSuccess: invalidate,
  })

  const deleteView = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('dashboard_layouts').delete().eq('id', id)
      if (error) throw error
    },
    onSuccess: invalidate,
  })

  /** publish the current arrangement as what everyone (or one kind) starts with */
  const saveOrgDefault = useMutation({
    mutationFn: async (forKind: UserKind | null) => {
      const layout = toStoredLayout(current.items, current.hidden, WIDGET_IDS)
      const { error } = await supabase.from('dashboard_layouts').upsert(
        { profile_id: null, user_kind: forKind, name: null, layout, updated_by: profileId },
        { onConflict: 'profile_id,user_kind,name' },
      )
      if (error) throw error
    },
    onSuccess: invalidate,
  })

  const edit = useCallback(
    (fn: (state: { items: LayoutItem[]; hidden: string[] }) => { items: LayoutItem[]; hidden: string[] }) => {
      setDraft((d) => fn(d ?? resolved))
    },
    [resolved],
  )

  return {
    /** the merged list, including widgets the reader currently cannot see */
    items: current.items,
    hidden: current.hidden,
    /** what the grid draws */
    visible,
    byId: WIDGETS_BY_ID,
    isLoading,
    dirty: draft !== null,
    hasOwnLayout: !!mine,
    namedViews,
    edit,
    discard: () => setDraft(null),
    applyView: (row: DashboardLayoutRow) => {
      const l = normalizeLayout(row.layout)
      if (l) setDraft({ items: resolveLayout(WIDGETS, l, fallback), hidden: l.hidden })
    },
    save: async (name?: string | null) => {
      await save.mutateAsync({ ...current, name })
      if ((name ?? null) === null) setDraft(null)
    },
    reset: async () => {
      setDraft(null)
      await reset.mutateAsync()
    },
    deleteView: deleteView.mutateAsync,
    saveOrgDefault: saveOrgDefault.mutateAsync,
    saving: save.isPending || reset.isPending || saveOrgDefault.isPending,
  }
}
