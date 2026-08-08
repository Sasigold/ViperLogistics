import { useCallback, useMemo } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../../lib/supabase'
import { useAuth } from '../../../state/auth'
import { normalizeSpec } from './widgetSpec'
import type { WidgetSpec } from './widgetSpec'

/**
 * The widgets this reader built, plus the ones colleagues shared.
 *
 * Read through `dashboard_widget_catalog()` rather than straight off the
 * table, for one reason that matters: the RPC returns `perms` — the union of
 * every permission key the spec's source, measure, dimension and filter fields
 * require — computed on the server. The client drops that array into
 * `WidgetDef.perms` and the existing `widgetAllowed` works unchanged.
 *
 * So **the client never derives a permission requirement from a spec**. There
 * is no mirror of the catalogue here to go stale, which is exactly the failure
 * `PRICING_VARS` already demonstrates on the pricing screen.
 */

export interface CustomWidgetRow {
  id: string
  profile_id: string
  title: string
  subtitle: string | null
  spec: WidgetSpec
  icon: string | null
  shared: boolean
  is_mine: boolean
  /** every key the spec needs, from the server */
  perms: string[]
  /** false when the spec names a measure or field the catalogue no longer has */
  known: boolean
  /** false when this reader specifically may not run it */
  runnable: boolean
  created_at: string
  updated_at: string
}

export interface SaveWidgetInput {
  id?: string
  title: string
  subtitle?: string | null
  spec: WidgetSpec
  shared?: boolean
}

export function useCustomWidgets() {
  const me = useAuth((s) => s.me)
  const has = useAuth((s) => s.has)
  const qc = useQueryClient()
  const profileId = me?.profile.id
  const canBuild = has('dashboard.build_widget')

  const query = useQuery({
    queryKey: ['dashboard_widgets', profileId],
    enabled: !!profileId,
    queryFn: async (): Promise<CustomWidgetRow[]> => {
      const { data, error } = await supabase.rpc('dashboard_widget_catalog')
      if (error) throw error
      // the spec is jsonb written by whatever release last saved it; one bad
      // row must not take the dashboard down, so every one is normalised
      return ((data ?? []) as CustomWidgetRow[]).map((r) => ({ ...r, spec: normalizeSpec(r.spec) }))
    },
  })

  const invalidate = useCallback(() => {
    void qc.invalidateQueries({ queryKey: ['dashboard_widgets'] })
    void qc.invalidateQueries({ queryKey: ['dashboard', 'custom'] })
  }, [qc])

  const save = useMutation({
    mutationFn: async (input: SaveWidgetInput): Promise<string> => {
      if (!profileId) throw new Error('אין פרופיל פעיל')
      const row = {
        profile_id: profileId,
        title: input.title.trim(),
        subtitle: input.subtitle?.trim() || null,
        spec: input.spec,
        shared: input.shared ?? false,
      }
      const q = input.id
        ? supabase.from('dashboard_widgets').update(row).eq('id', input.id).select('id').single()
        : supabase.from('dashboard_widgets').insert(row).select('id').single()
      const { data, error } = await q
      if (error) throw error
      return (data as { id: string }).id
    },
    onSuccess: invalidate,
  })

  /* Deletion goes through an RPC, not an UPDATE. `dw_select` requires
     `deleted_at is null`, and Postgres re-checks the *updated* row against the
     SELECT policy — so `update … set deleted_at = now()` is rejected for
     everyone, always. 0045 carries the long version of this. */
  const remove = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('dashboard_widget_delete', { p_id: id })
      if (error) throw error
    },
    onSuccess: invalidate,
  })

  const setShared = useMutation({
    mutationFn: async ({ id, shared }: { id: string; shared: boolean }) => {
      const { error } = await supabase.from('dashboard_widgets').update({ shared }).eq('id', id)
      if (error) throw error
    },
    onSuccess: invalidate,
  })

  const rows = useMemo(() => query.data ?? [], [query.data])

  return {
    rows,
    /* The layout merge must not run against a half-loaded registry: between
       first paint and this query resolving, every custom id looks unknown, and
       a save landing in that window prunes them all out of `seen`. */
    isLoading: query.isLoading && !!profileId,
    error: query.error,
    canBuild,
    save: save.mutateAsync,
    remove: remove.mutateAsync,
    setShared: setShared.mutateAsync,
    saving: save.isPending || remove.isPending || setShared.isPending,
  }
}

export type CustomWidgets = ReturnType<typeof useCustomWidgets>
