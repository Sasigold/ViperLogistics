import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { addDays } from 'date-fns'
import { supabase } from '../../lib/supabase'
import { toISODate } from '../../lib/dates'
import type { DashboardStats, EventPaymentsDashboard, WorkBoardRow } from '../../types/domain'

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

/**
 * תשלומי אירועים בטווח (0205) — מה מגיע, מה שולם ומה עוד לא, ושנים-עשר
 * החודשים שמסתיימים בסוף הטווח. אותה שאלה משרתת את כרטיסי הדשבורד ואת פס
 * הסיכום של מסך התשלומים, כדי ששני המסכים לעולם לא יסתרו זה את זה.
 *
 * ‏`customerId` (‏0208) מצמצם ללקוח אחד — הפילטר של מסך התשלומים. הוא נשלח
 * רק כשנבחר לקוח, כך שהדשבורד שואל בדיוק את מה ששאל קודם. ‏`keepPreviousData`
 * כמו בסקשנים של הדשבורד: בהחלפת לקוח או טווח המספרים הקודמים נשארים עד
 * שהחדשים מגיעים, והפילטר עצמו (שבא מאותה תשובה) אינו נעלם לרגע.
 *
 * ‏null — למי שאינו רשאי; הכרטיס נעלם.
 */
export function useEventPaymentsDashboard(from: string, to: string, enabled = true, customerId?: string | null) {
  return useQuery({
    queryKey: ['dashboard', 'event_payments', from, to, customerId ?? null],
    enabled,
    placeholderData: keepPreviousData,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('event_payments_dashboard', {
        p_from: from,
        p_to: to,
        ...(customerId ? { p_customer_id: customerId } : {}),
      })
      if (error) throw error
      return (data ?? null) as EventPaymentsDashboard | null
    },
  })
}
