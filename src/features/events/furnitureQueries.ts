/**
 * מה שהגיע מ-ViperFlow על האירוע — הקישור ורשימת הריהוט (0176‏–0177).
 *
 * שתי שאילתות ולא אחת, ובכוונה. הקישור זול, נטען עם דף האירוע ועם מגירת
 * המשימה, והוא מה שמכריע אם יש בכלל לשונית "ריהוט" ומה המונה שעליה. הרשימה
 * עצמה נטענת רק כשפותחים אותה: הזמנה גדולה היא מאות שורות, ואין סיבה שכל
 * פתיחה של משימה תמשוך אותן.
 *
 * הכתיבה אינה כאן ואין לה מקום להיות: לארבע הטבלאות של 0176 אין פוליסת
 * כתיבה כלל, והכותב היחיד הוא פונקציית הקצה בזהות service role.
 */
import { useQuery } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import type { ViperflowEventLink, ViperflowOrderItem } from '../../types/domain'

/**
 * הקישור להזמנה, אם יש. `maybeSingle` ולא `single`: לרוב האירועים במערכת
 * אין קישור, וזה מצב תקין ולא שגיאה.
 */
export function useViperflowLink(eventId: string | null | undefined, enabled = true) {
  return useQuery({
    queryKey: ['viperflow_event_link', eventId],
    enabled: !!eventId && enabled,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('viperflow_event_link')
        .select('*')
        .eq('event_id', eventId!)
        .maybeSingle()
      if (error) throw error
      return (data as ViperflowEventLink | null) ?? null
    },
  })
}

/**
 * שורות ההזמנה, בסדר שבו ViperFlow שלח אותן.
 *
 * ‏`select('*')` מחזיר את כל העמודות שיש — ואין ביניהן מחיר (0176 §2).
 */
export function useViperflowOrderItems(eventId: string | null | undefined, enabled = true) {
  return useQuery({
    queryKey: ['viperflow_order_items', eventId],
    enabled: !!eventId && enabled,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('viperflow_order_items')
        .select('*')
        .eq('event_id', eventId!)
        .order('position')
      if (error) throw error
      return (data ?? []) as ViperflowOrderItem[]
    },
  })
}
