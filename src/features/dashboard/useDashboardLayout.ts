import { useCallback, useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { BUILT_IN_DEFAULT, WIDGETS } from './registry'
import { customWidgetDefs } from './builder/customRegistry'
import { useCustomWidgets } from './builder/useCustomWidgets'
import { lockedIds, mergeView, normalizeLayout, resolveLayout, toStoredLayout, visibleItems } from './layout'
import type { DashboardLayout, LayoutItem, ViewPrefs, WidgetDef } from './dashboardTypes'
import type { UserKind } from '../../types/domain'

/** the three things an edit can touch, held together so one `setDraft` moves all of them */
interface DraftState {
  items: LayoutItem[]
  hidden: string[]
  view?: ViewPrefs
}

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

  /* ===== the registry, hand-written plus built ============================
     Every layout operation below takes this merged list rather than `WIDGETS`.
     Miss one of them and a custom widget renders on the grid but is invisible
     to the section planner, or is offered by the drawer with no component. */
  const custom = useCustomWidgets()
  const widgets: WidgetDef[] = useMemo(
    () => [...WIDGETS, ...customWidgetDefs(custom.rows)],
    [custom.rows],
  )
  const byId = useMemo(() => new Map(widgets.map((w) => [w.id, w])), [widgets])
  const known = useMemo(() => new Set(widgets.map((w) => w.id)), [widgets])

  /* Own rows plus every default row, in one read. RLS already narrows it: a
     non-admin sees their own rows and the defaults, and nothing else. */
  const { data: rows = [], isLoading: layoutsLoading } = useQuery({
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

  /* Both queries, not just the layout one. Between first paint and
     `dashboard_widgets` resolving, the merged registry holds no custom ids at
     all — and `toStoredLayout` prunes `seen` against exactly that set. A save
     landing in that window forgets every custom widget the user has. */
  const isLoading = layoutsLoading || custom.isLoading

  const saved = useMemo(() => {
    if (mine) return normalizeLayout(mine.layout)
    // nothing from the server yet — show the cached copy rather than a blank
    // grid, and let the query overwrite it when it lands
    return layoutsLoading ? readCache(profileId) : null
  }, [mine, layoutsLoading, profileId])

  const [draft, setDraft] = useState<DraftState | null>(null)

  const resolved = useMemo(() => {
    const items = resolveLayout(widgets, saved, fallback)
    /* A widget the administrator locked is back on the page whatever the user
       once said about it, so leaving its id in `hidden` would only make the
       catalogue draw a switch that does nothing when it is turned off. */
    const locked = new Set(lockedIds(fallback))
    const hidden = (saved?.hidden ?? fallback.hidden).filter((h) => !locked.has(h))
    /* The view is the user's when they have one and the published default's
       otherwise — the same ladder the items climb, for the same reason: an
       administrator who publishes a packing has published it to everyone who
       never expressed an opinion, and to nobody who did. */
    return { items, hidden, view: saved?.view ?? fallback.view }
  }, [widgets, saved, fallback])

  const current = draft ?? resolved
  const visible = useMemo(
    () => visibleItems(current.items, byId, has, kind),
    [current.items, byId, has, kind],
  )

  useEffect(() => {
    if (mine) writeCache(profileId, normalizeLayout(mine.layout))
  }, [mine, profileId])

  /* ===== writes ========================================================== */

  const invalidate = () => void qc.invalidateQueries({ queryKey: ['dashboard_layouts'] })

  const save = useMutation({
    mutationFn: async (next: DraftState & { name?: string | null }) => {
      if (!profileId) throw new Error('אין פרופיל פעיל')
      // `known` is what prunes `seen`; saving before the custom widgets have
      // landed would prune every one of them out of it
      if (custom.isLoading) throw new Error('הווידג׳טים עדיין נטענים')
      const layout = toStoredLayout(next.items, next.hidden, known, next.view)
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

  /* Renaming and overwriting go by row id rather than through the upsert's
     conflict target: `(profile_id, user_kind, name)` means a rename is a *new*
     key, so an upsert would leave the old row behind under the old name. */
  const renameView = useMutation({
    mutationFn: async ({ id, name }: { id: string; name: string }) => {
      const { error } = await supabase
        .from('dashboard_layouts')
        .update({ name, updated_by: profileId })
        .eq('id', id)
      if (error) throw error
    },
    onSuccess: invalidate,
  })

  /** overwrite a saved view with what is on screen — the half "save as" never had */
  const updateView = useMutation({
    mutationFn: async (id: string) => {
      if (custom.isLoading) throw new Error('הווידג׳טים עדיין נטענים')
      const layout = toStoredLayout(current.items, current.hidden, known, current.view)
      const { error } = await supabase
        .from('dashboard_layouts')
        .update({ layout, updated_by: profileId })
        .eq('id', id)
      if (error) throw error
    },
    onSuccess: invalidate,
  })

  /** an administrator taking a published default back down */
  const deleteOrgDefault = useMutation({
    mutationFn: async (forKind: UserKind | null) => {
      const row = rows.find((r) => r.profile_id === null && r.user_kind === forKind && r.name === null)
      if (!row) return
      const { error } = await supabase.from('dashboard_layouts').delete().eq('id', row.id)
      if (error) throw error
    },
    onSuccess: invalidate,
  })

  /** publish the current arrangement as what everyone (or one kind) starts with */
  const saveOrgDefault = useMutation({
    mutationFn: async (forKind: UserKind | null) => {
      if (custom.isLoading) throw new Error('הווידג׳טים עדיין נטענים')
      const layout = toStoredLayout(current.items, current.hidden, known, current.view)
      const { error } = await supabase.from('dashboard_layouts').upsert(
        { profile_id: null, user_kind: forKind, name: null, layout, updated_by: profileId },
        { onConflict: 'profile_id,user_kind,name' },
      )
      if (error) throw error
    },
    onSuccess: invalidate,
  })

  const edit = useCallback(
    (fn: (state: DraftState) => DraftState) => {
      setDraft((d) => fn(d ?? resolved))
    },
    [resolved],
  )

  /**
   * Apply an edit and write it in the same breath.
   *
   * Edit mode has a save bar and a draft that waits for it; the controls that
   * live *outside* edit mode — a card's display form, the view menu — have
   * neither, and a setting that forgets itself on reload is a setting nobody
   * uses twice. The transform runs against the current state here rather than
   * through `setDraft`, because the value to persist has to be in hand before
   * the mutation is called and a state updater has not run yet.
   */
  const commit = useCallback(
    async (fn: (state: DraftState) => DraftState) => {
      const next = fn(draft ?? resolved)
      setDraft(next)
      await save.mutateAsync({ ...next, name: null })
      setDraft(null)
    },
    [draft, resolved, save],
  )

  return {
    /** the merged list, including widgets the reader currently cannot see */
    items: current.items,
    hidden: current.hidden,
    /** what the grid draws */
    visible,
    widgets,
    byId,
    isLoading,
    customWidgets: custom,
    dirty: draft !== null,
    hasOwnLayout: !!mine,
    namedViews,
    /** the published defaults, so an administrator can see what exists and undo it */
    orgDefaults: useMemo(() => rows.filter((r) => r.profile_id === null && r.name === null), [rows]),
    /** whole-screen preferences: packing, bucket, top-N, opening range */
    view: current.view,
    setView: (patch: Partial<ViewPrefs>) => edit((st) => ({ ...st, view: mergeView(st.view, patch) })),
    edit,
    commit,
    discard: () => setDraft(null),
    /**
     * Switch to a saved view.
     *
     * `persist` is the difference between the two places this is called from,
     * and it matters: inside edit mode a view is a starting point that the save
     * bar will confirm, but outside it there *is* no save bar — so applying a
     * view left a dirty draft the reader had no way to keep, and the whole
     * thing evaporated on the next load.
     */
    applyView: (row: DashboardLayoutRow, persist?: boolean) => {
      const l = normalizeLayout(row.layout)
      if (!l) return
      const next = { items: resolveLayout(widgets, l, fallback), hidden: l.hidden, view: l.view }
      if (persist) return commit(() => next)
      setDraft(next)
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
    renameView: (id: string, name: string) => renameView.mutateAsync({ id, name }),
    updateView: updateView.mutateAsync,
    saveOrgDefault: saveOrgDefault.mutateAsync,
    deleteOrgDefault: deleteOrgDefault.mutateAsync,
    saving:
      save.isPending ||
      reset.isPending ||
      saveOrgDefault.isPending ||
      updateView.isPending ||
      renameView.isPending ||
      deleteOrgDefault.isPending,
  }
}
