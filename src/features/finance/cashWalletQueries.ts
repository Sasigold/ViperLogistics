/**
 * ארנק המזומנים (0207) — הקריאות והכתיבות.
 *
 * תשלום במזומן שנרשם או נמחק בכרטיס האירוע פוסל גם את `['wallet']`
 * (`invalidateEventPayments`), כדי שהיתרה לא תישאר מאחור.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import type { CashWallet } from '../../types/domain'

export function useCashWallet(from: string, to: string, enabled = true) {
  return useQuery({
    queryKey: ['wallet', from, to],
    enabled,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('cash_wallet', { p_from: from, p_to: to })
      if (error) throw error
      return data as CashWallet
    },
  })
}

export function useAddWalletEntry() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: {
      kind: 'expense' | 'income'
      amount: number
      label: string
      note: string | null
      date: string | null
    }) => {
      const { data, error } = await supabase.rpc('cash_wallet_entry_add', {
        p_kind: input.kind,
        p_amount: input.amount,
        p_label: input.label,
        p_note: input.note,
        p_entry_date: input.date,
      })
      if (error) throw error
      return data as string
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['wallet'] }),
  })
}

export function useRemoveWalletEntry() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('cash_wallet_entry_remove', { p_entry_id: id })
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['wallet'] }),
  })
}
