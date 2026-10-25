/**
 * עוזר הוואטסאפ (0236) — הקריאות והפעולות של המסכים.
 *
 * הקישור שלי נקרא ישירות מ-`wa_links` (RLS: שלי, או מנהל מערכת); מספר הבוט
 * מ-`app_settings` (`whatsapp.bot`, אינו סוד). הקבוצות וההודעות — מנהלי מערכת
 * בלבד (RLS). כל כתיבה דרך RPC: `wa_link_code_create`, `wa_unlink`,
 * `wa_chat_unbind`.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import type { WaBot, WaChat, WaLink, WaLinkCode, WaMessage } from '../../types/domain'

const KEY = 'whatsapp'

export function useWhatsAppBot() {
  return useQuery({
    queryKey: [KEY, 'bot'],
    queryFn: async () => {
      const { data, error } = await supabase.from('app_settings').select('value').eq('key', 'whatsapp.bot').maybeSingle()
      if (error) throw error
      return ((data?.value ?? {}) as WaBot)
    },
  })
}

/** הקישור הפעיל שלי, או null. בזמן שקוד מוצג — נבדק שוב כל כמה שניות. */
export function useMyWhatsAppLink(polling: boolean) {
  const me = useAuth((s) => s.me?.profile.id)
  return useQuery({
    queryKey: [KEY, 'link', me],
    enabled: !!me,
    refetchInterval: polling ? 4000 : false,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('wa_links')
        .select('id, profile_id, wa_id, display_name, linked_at')
        .eq('profile_id', me!)
        .is('revoked_at', null)
        .maybeSingle()
      if (error) throw error
      return (data as WaLink | null) ?? null
    },
  })
}

export function useCreateLinkCode() {
  return useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.rpc('wa_link_code_create')
      if (error) throw error
      return data as WaLinkCode
    },
  })
}

export function useUnlinkWhatsApp() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (linkId: string) => {
      const { error } = await supabase.rpc('wa_unlink', { p_link_id: linkId })
      if (error) throw error
    },
    onSettled: () => qc.invalidateQueries({ queryKey: [KEY] }),
  })
}

const useIsAdmin = () => useAuth((s) => !!s.me?.profile.is_admin)

export function useWhatsAppLinks() {
  const admin = useIsAdmin()
  return useQuery({
    queryKey: [KEY, 'links'],
    enabled: admin,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('wa_links')
        .select('id, profile_id, wa_id, display_name, linked_at, profiles!wa_links_profile_id_fkey(full_name)')
        .is('revoked_at', null)
        .order('linked_at', { ascending: false })
      if (error) throw error
      return data as unknown as WaLink[]
    },
  })
}

export function useWhatsAppChats() {
  const admin = useIsAdmin()
  return useQuery({
    queryKey: [KEY, 'chats'],
    enabled: admin,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('wa_chats')
        .select('chat_id, is_group, name, active, bound_at, participants_ok, participants_checked_at, bound_by_profile:profiles!wa_chats_bound_by_fkey(full_name)')
        .eq('is_group', true)
        .order('bound_at', { ascending: false })
      if (error) throw error
      return data as unknown as WaChat[]
    },
  })
}

export function useWhatsAppMessages() {
  const admin = useIsAdmin()
  return useQuery({
    queryKey: [KEY, 'messages'],
    enabled: admin,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('wa_messages')
        .select('id, direction, chat_id, profile_id, body, status, error, created_at, profiles(full_name)')
        .order('created_at', { ascending: false })
        .limit(50)
      if (error) throw error
      return data as unknown as WaMessage[]
    },
  })
}

export function useUnbindChat() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (chatId: string) => {
      const { error } = await supabase.rpc('wa_chat_unbind', { p_chat_id: chatId })
      if (error) throw error
    },
    onSettled: () => qc.invalidateQueries({ queryKey: [KEY] }),
  })
}
