import { useQuery } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import { toISODate } from '../../lib/dates'

/**
 * Count of tasks whose date has passed while their status is still open.
 * Read-only head-count over the existing `work_board_view`; RLS scopes it to
 * whatever the signed-in user may already see.
 *
 * Surfaced as a sidebar badge so an overdue task is visible from any screen
 * instead of only after opening the board.
 */
export function useOverdueCount(enabled = true) {
  return useQuery({
    queryKey: ['workboard', 'overdue-count'],
    enabled,
    staleTime: 60_000,
    queryFn: async () => {
      const { count, error } = await supabase
        .from('work_board_view')
        .select('id', { count: 'exact', head: true })
        .lt('task_date', toISODate(new Date()))
        .eq('status_is_terminal', false)
      if (error) throw error
      return count ?? 0
    },
  })
}
