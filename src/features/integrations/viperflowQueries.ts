/**
 * החיבור ל-ViperFlow — מה שהמסך של המשרד קורא וכותב (0176 §6).
 *
 * הקריאה של המצב עוברת ב-RPC ולא בשאילתה על הטבלה, מאותו נימוק שכתוב על
 * `useFleetExpirySummary`: המונים (כמה נכנסו ביממה, כמה פתוחים) הם ספירה על
 * טבלת המשלוחים, וספירה בלקוח תסתור את עצמה ברגע שדף שני יטען אחרת. רשימת
 * המשלוחים עצמה כן נקראת ישירות — היא טבלה עם פוליסת select, והיא מדפדפת.
 *
 * הסודות אינם כאן ואינם יכולים להיות: מפתח החתימה ומפתח ה-API יושבים
 * בסודות של פונקציות הקצה בלבד, ולכן אין להם hook ואין להם שדה בטופס.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { QueryClient } from '@tanstack/react-query'
import { invokeFunction, supabase } from '../../lib/supabase'
import type { ViperflowConnectionStatus, ViperflowDelivery } from '../../types/domain'

export function invalidateViperflow(qc: QueryClient) {
  void qc.invalidateQueries({ queryKey: ['viperflow'] })
  void qc.invalidateQueries({ queryKey: ['viperflow_deliveries'] })
}

export function useViperflowStatus() {
  return useQuery({
    queryKey: ['viperflow', 'status'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('viperflow_connection_status')
      if (error) throw error
      return (data ?? []) as ViperflowConnectionStatus[]
    },
  })
}

/**
 * המשלוחים האחרונים. ‏`failedOnly` הוא מה שהופך את המסך מיומן לרשימת עבודה:
 * שורה אדומה היא מעטפה שהגיעה ולא הוחלה, והיא ממתינה ללחיצה.
 */
export function useViperflowDeliveries(failedOnly: boolean, limit = 50) {
  return useQuery({
    queryKey: ['viperflow_deliveries', failedOnly, limit],
    queryFn: async () => {
      let query = supabase
        .from('viperflow_deliveries')
        .select(
          'id, connection_id, event_id, delivery_id, event_type, attempt, origin, entity_id, occurred_at, received_at, processed_at, status, reason, event_row_id',
        )
        .order('received_at', { ascending: false })
        .limit(limit)
      if (failedOnly) query = query.eq('status', 'failed')

      const { data, error } = await query
      if (error) throw error
      return (data ?? []) as ViperflowDelivery[]
    },
  })
}

export function useSetViperflowConnection() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: {
      customerId: string
      label: string
      isActive: boolean
      notes?: string | null
      connectionId?: string | null
    }) => {
      const { data, error } = await supabase.rpc('viperflow_set_connection', {
        p_customer_id: input.customerId,
        p_label: input.label,
        p_is_active: input.isActive,
        p_notes: input.notes ?? null,
        p_connection_id: input.connectionId ?? null,
      })
      if (error) throw error
      return data as string
    },
    onSuccess: () => invalidateViperflow(qc),
  })
}

/**
 * הרצה מחדש של משלוח שנכשל. המעטפה שמורה אצלנו (0176 §3), ולכן זה אינו
 * מבקש דבר מ-ViperFlow — גם לא אחרי שהוא כבר מחק אותה מהיומן שלו.
 */
export function useReplayDelivery() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (deliveryId: string) => {
      const { data, error } = await supabase.rpc('viperflow_replay', { p_delivery: deliveryId })
      if (error) throw error
      return data as { status?: string; reason?: string }
    },
    onSuccess: () => invalidateViperflow(qc),
  })
}

export interface SyncSummary {
  connection: string
  since: string | null
  scanned: number
  applied: number
  duplicate: number
  failed: number
  has_more: boolean
  errors: string[]
}

/** משיכה יזומה מה-API. ראו `supabase/functions/viperflow-sync`. */
export function useViperflowSync() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (connectionId?: string) =>
      await invokeFunction<SyncSummary>('viperflow-sync', {
        connection_id: connectionId ?? null,
      }),
    onSuccess: () => invalidateViperflow(qc),
  })
}
