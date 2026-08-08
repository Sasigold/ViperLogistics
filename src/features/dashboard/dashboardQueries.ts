import { useQuery } from '@tanstack/react-query'
import { addDays } from 'date-fns'
import { supabase } from '../../lib/supabase'
import { toISODate } from '../../lib/dates'
import type { DashboardStats, WorkBoardRow } from '../../types/domain'

/**
 * The dashboard's shared reads.
 *
 * Widgets call these directly rather than being handed data through a context:
 * eight KPI tiles asking for `useDashboardStats(from, to)` produce one request,
 * because react-query dedupes on the key. That keeps each widget a self-
 * contained thing you can move, hide or delete without touching a fan-out map
 * at the page level.
 *
 * The keys are the ones the page used before the widget rewrite, so anything
 * that invalidates `['dashboard']` still reaches all of it.
 */

export function useDashboardStats(from: string, to: string) {
  return useQuery({
    queryKey: ['dashboard', from, to],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('dashboard_stats', { p_from: from, p_to: to })
      if (error) throw error
      return data as DashboardStats
    },
  })
}

/** today, the next seven days, or whatever was touched last */
export type BoardSlice = 'today' | 'upcoming' | 'recent'

export function useBoardSlice(slice: BoardSlice, today: string) {
  return useQuery({
    queryKey: ['dashboard', slice, slice === 'recent' ? 'latest' : today],
    queryFn: async () => {
      let q = supabase.from('work_board_view').select('*')
      if (slice === 'today') {
        q = q.eq('task_date', today).order('onsite_start_time', { nullsFirst: false }).limit(60)
      } else if (slice === 'upcoming') {
        q = q
          .gt('task_date', today)
          .lte('task_date', toISODate(addDays(new Date(today), 7)))
          .order('task_date')
          .order('onsite_start_time', { nullsFirst: false })
          .limit(8)
      } else {
        q = q.order('updated_at', { ascending: false }).limit(8)
      }
      const { data, error } = await q
      if (error) throw error
      return data as WorkBoardRow[]
    },
  })
}
