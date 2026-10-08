/**
 * תשלומי אירועים (0205) — הקריאות והכתיבות.
 *
 * המפתחות מתחילים ב-`events`, ובכוונה: כל שינוי באירוע — מחיר משימה שהתעדכן,
 * הכנסה שנערכה בטופס, סנכרון מ-ViperFlow — כבר פוסל את `['events']`, ו"כמה
 * מגיע" נגזר בדיוק מהם. הסכום שבכרטיס לא יכול להישאר מאחורי המחיר שבדף.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { QueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import type { EventPaymentRow, EventPaymentSummary, PaymentMethod } from '../../types/domain'

export function invalidateEventPayments(qc: QueryClient) {
  void qc.invalidateQueries({ queryKey: ['events', 'payments'] })
  void qc.invalidateQueries({ queryKey: ['dashboard'] })
  void qc.invalidateQueries({ queryKey: ['receipts'] })
  // תשלום במזומן נכנס לארנק (0207)
  void qc.invalidateQueries({ queryKey: ['wallet'] })
}

/** הפירוט, התשלומים והיתרה של אירוע אחד. */
export function useEventPaymentSummary(eventId: string | null | undefined, enabled = true) {
  return useQuery({
    queryKey: ['events', 'payments', 'one', eventId],
    enabled: !!eventId && enabled,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('event_payment_summary', { p_event_id: eventId! })
      if (error) throw error
      return data as EventPaymentSummary
    },
  })
}

/** כל האירועים בטווח, עם מה שמגיע, מה ששולם והיתרה — מסך התשלומים. */
export function useEventPaymentsList(from: string, to: string, enabled = true) {
  return useQuery({
    queryKey: ['events', 'payments', 'list', from, to],
    enabled,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('event_payments_list', { p_from: from, p_to: to })
      if (error) throw error
      return (data ?? []) as EventPaymentRow[]
    },
  })
}

export function useAddEventPayment() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: {
      eventId: string
      amount: number
      method: PaymentMethod
      note: string | null
      receivedAt: string | null
    }) => {
      const { data, error } = await supabase.rpc('event_payment_add', {
        p_event_id: input.eventId,
        p_amount: input.amount,
        p_method: input.method,
        p_note: input.note,
        p_received_at: input.receivedAt,
      })
      if (error) throw error
      return data as string
    },
    onSuccess: () => invalidateEventPayments(qc),
  })
}

export function useRemoveEventPayment() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (receiptId: string) => {
      const { error } = await supabase.rpc('event_payment_remove', { p_receipt_id: receiptId })
      if (error) throw error
    },
    onSuccess: () => invalidateEventPayments(qc),
  })
}

/** חיוב ידני על אירוע (0207) — "עלות ייצור 1,000" נוסף ל"מגיע". */
export function useAddEventCharge() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { eventId: string; label: string; amount: number; note: string | null }) => {
      const { data, error } = await supabase.rpc('event_charge_add', {
        p_event_id: input.eventId,
        p_label: input.label,
        p_amount: input.amount,
        p_note: input.note,
      })
      if (error) throw error
      return data as string
    },
    onSuccess: () => invalidateEventPayments(qc),
  })
}

export function useRemoveEventCharge() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (chargeId: string) => {
      const { error } = await supabase.rpc('event_charge_remove', { p_charge_id: chargeId })
      if (error) throw error
    },
    onSuccess: () => invalidateEventPayments(qc),
  })
}

/**
 * עריכת סכומי ההכנסות של אירוע מכרטיס התשלומים (0212). אותו מסלול של טופס
 * האירוע: באירוע מ-ViperFlow שהסנכרון שלו רץ, השרת דוחה שינוי בסכום שמגיע
 * משם — העצירה היא שפותחת אותו.
 *
 * ‏`amounts`: קטגוריה → סכום כמחרוזת, וריק = מחיקת השורה.
 */
export function useSaveEventIncome() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { eventId: string; amounts: Record<string, string> }) => {
      const { error } = await supabase.rpc('event_income_save', {
        p_event_id: input.eventId,
        p_amounts: input.amounts,
      })
      if (error) throw error
    },
    onSuccess: () => {
      invalidateEventPayments(qc)
      void qc.invalidateQueries({ queryKey: ['event_income'] })
    },
  })
}

/**
 * העמלה הידנית על קטגוריה (0212, כיסאות). ‏null מוחק אותה. כל קביעה — גם
 * באותו סכום — מאשרת את הסכום הנוכחי כבסיס, וכך מורידה את "המפרט השתנה".
 */
export function useSetIncomeCommission() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { eventId: string; categoryId: string; amount: number | null }) => {
      const { error } = await supabase.rpc('event_income_set_commission', {
        p_event_id: input.eventId,
        p_category_id: input.categoryId,
        p_amount: input.amount,
      })
      if (error) throw error
    },
    onSuccess: () => {
      invalidateEventPayments(qc)
      void qc.invalidateQueries({ queryKey: ['event_income'] })
    },
  })
}
