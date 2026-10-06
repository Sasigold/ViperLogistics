/**
 * מה שהגיע מ-ViperFlow על האירוע — הקישור ורשימת הריהוט (0176‏–0177).
 *
 * שתי שאילתות ולא אחת, ובכוונה. הקישור זול, נטען עם דף האירוע ועם מגירת
 * המשימה, והוא מה שמכריע אם יש בכלל לשונית "ריהוט" ומה המונה שעליה. הרשימה
 * עצמה נטענת רק כשפותחים אותה: הזמנה גדולה היא מאות שורות, ואין סיבה שכל
 * פתיחה של משימה תמשוך אותן.
 *
 * הכתיבה אינה כאן ואין לה מקום להיות: לארבע הטבלאות של 0176 אין פוליסת
 * כתיבה כלל, והכותב היחיד הוא פונקציית הקצה בזהות service role. היוצא היחיד
 * הוא נעילת הסנכרון (0204), שעוברת ב-RPC ולא בטבלה.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { invokeFunction, supabase } from '../../lib/supabase'
import type { ViperflowEventLink, ViperflowOrderItem, ViperflowSpec } from '../../types/domain'

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

/**
 * המפרט כפי שהוא ברגע זה בהזמנה — עם תמונות, ובלי רכיבים (0187).
 *
 * זו הקריאה שהכפתור "מפרט" מפעיל, והיא אינה כותבת דבר: התמונות נקראות
 * מהקטלוג של ViperFlow בכל פתיחה ואינן נשמרות אצלנו. ‏`retry: false` כי
 * הנפילה הרכה כבר קיימת — המסך מציג את מה ששמור — וניסיון חוזר אוטומטי היה
 * רק מאריך את ההמתנה לפניה.
 *
 * ‏`staleTime` של דקה: מי שסוגר ופותח את המפרט פעמיים ברצף שואל את אותה
 * שאלה, ולא צריך שתי קריאות ל-API שיש לו מכסה.
 */
export function useViperflowSpec(eventId: string | null | undefined, enabled = true) {
  return useQuery({
    queryKey: ['viperflow_spec', eventId],
    enabled: !!eventId && enabled,
    retry: false,
    staleTime: 60_000,
    queryFn: async () => await invokeFunction<ViperflowSpec>('viperflow-spec', { event_id: eventId }),
  })
}

/**
 * עצירה וחידוש של הסנכרון לאירוע אחד (0204).
 *
 * ‏`locked` מפורש ולא "החלף": שתי לשוניות על אותו אירוע אינן הופכות זו את
 * ההכרעה של זו. בחידוש השרת גם מחיל את המשלוח האחרון שנדחה בזמן העצירה,
 * ולכן מה שמתבטל כאן הוא כל מה שהאירוע מציג — לא רק הקישור.
 */
export function useSetEventSyncLock(eventId: string | null | undefined) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (locked: boolean) => {
      const { data, error } = await supabase.rpc('viperflow_set_event_lock', {
        p_event_id: eventId!,
        p_locked: locked,
      })
      if (error) throw error
      return data as { locked: boolean; locked_at: string | null; caught_up?: boolean }
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['viperflow_event_link', eventId] })
      void qc.invalidateQueries({ queryKey: ['viperflow_spec', eventId] })
      void qc.invalidateQueries({ queryKey: ['viperflow_order_items', eventId] })
      void qc.invalidateQueries({ queryKey: ['events'] })
      void qc.invalidateQueries({ queryKey: ['workboard'] })
      void qc.invalidateQueries({ queryKey: ['event_activity'] })
      void qc.invalidateQueries({ queryKey: ['dashboard'] })
      void qc.invalidateQueries({ queryKey: ['viperflow_deliveries'] })
    },
  })
}
