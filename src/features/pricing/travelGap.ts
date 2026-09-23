/**
 * מחיר בלי זמן נסיעה (0197).
 *
 * זמן הנסיעה נגזר מאזור התמחור שהפין של האירוע נופל בתוכו. אירוע בלי פין,
 * עם פין מחוץ לכל אזור, או עם מיקום שהוזן ביד — המחיר שלו מחושב עם אפס
 * שעות נסיעה ונראה סופי. הסימון האדום הוא מה שמונע ממנו לצאת ללקוח כך.
 */
import { useQuery } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'

export type TravelGapReason = 'manual' | 'no_pin' | 'no_zone'

export const TRAVEL_GAP_TEXT = 'המחיר ללא חישוב זמן הנסיעה למיקום'

const REASON_TEXT: Record<TravelGapReason, string> = {
  manual: 'המיקום הוזן ידנית',
  no_pin: 'למיקום אין נקודה על המפה',
  no_zone: 'המיקום מחוץ לאזורי התמחור',
}

export function travelGapReasonText(reason: TravelGapReason): string {
  return REASON_TEXT[reason]
}

/** מפה ממזהה אירוע לסיבה. אירוע שאינו בה — המחיר שלו כולל נסיעה. */
export function useEventTravelGaps(eventIds: string[], enabled = true) {
  return useQuery({
    queryKey: ['events', 'travel_gaps', eventIds],
    enabled: enabled && eventIds.length > 0,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('event_travel_gaps', { p_event_ids: eventIds })
      if (error) throw error
      const rows = (data ?? []) as { event_id: string; reason: TravelGapReason }[]
      return new Map(rows.map((r) => [r.event_id, r.reason]))
    },
  })
}

/**
 * האם המחיר של משימה זו חסר את זמן הנסיעה: האירוע סומן, המחיר מחושב (לא
 * ידני), ואין על המשימה דריסת `travel_hours` שכבר נושאת את הנסיעה.
 */
export function lacksTravel(
  gap: TravelGapReason | undefined,
  t: { customer_price: number | null; price_is_manual?: boolean | null; travel_hours: number | null },
): boolean {
  return !!gap && t.customer_price != null && !t.price_is_manual && t.travel_hours == null
}
