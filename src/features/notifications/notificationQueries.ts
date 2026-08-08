/**
 * השאילתות של מסכי ההתראות.
 *
 * שימו לב למה ש*אין* כאן: מימוש של סדר ההכרעה. הוא יושב ב-SQL
 * (‏app.notification_enabled ב-0046), ומגיע ללקוח מוכן דרך
 * my_notification_settings. מירור שלו ב-TypeScript היה הדבר שמתיישן ברגע
 * שמישהו יוסיף דרגה לסולם.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import type {
  NotificationAudience,
  NotificationChannel,
  NotificationMode,
  NotificationPolicy,
  NotificationPolicyOverride,
  NotificationSetting,
  NotificationType,
  PushSubscriptionRow,
} from '../../types/domain'

export const CHANNELS: { key: NotificationChannel; label: string }[] = [
  { key: 'inapp', label: 'פעמון' },
  { key: 'email', label: 'מייל' },
  { key: 'push', label: 'התראה למכשיר' },
]

export const AUDIENCES: { key: NotificationAudience; label: string }[] = [
  { key: 'admin', label: 'מנהלים' },
  { key: 'staff', label: 'עובדים' },
  { key: 'contractor_user', label: 'קבלנים' },
  { key: 'customer_user', label: 'לקוחות' },
]

export const MODES: { key: NotificationMode; label: string; hint: string }[] = [
  { key: 'off', label: 'כבוי', hint: 'לא נשלח, והמשתמש אינו יכול להדליק' },
  { key: 'opt_in', label: 'כבוי כברירת מחדל', hint: 'המשתמש יכול להדליק לעצמו' },
  { key: 'opt_out', label: 'דלוק כברירת מחדל', hint: 'המשתמש יכול לכבות לעצמו' },
  { key: 'forced', label: 'חובה', hint: 'תמיד נשלח, והמשתמש אינו יכול לכבות' },
]

export interface PushConfig {
  enabled: boolean
  vapid_public_key: string
  muted_types: string[]
}

export interface EmailConfig {
  enabled: boolean
  from: string
  muted_types: string[]
}

/** ההגדרות שלי, אחרי כל שכבות ההכרעה בשרת. */
export function useMyNotificationSettings() {
  const me = useAuth((s) => s.me)
  return useQuery({
    queryKey: ['notification_settings', 'me', me?.profile.id],
    enabled: !!me,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('my_notification_settings')
      if (error) throw error
      return (data ?? []) as NotificationSetting[]
    },
  })
}

export function useSetPreference() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (v: { type: string; channel: NotificationChannel; enabled: boolean }) => {
      const { error } = await supabase.rpc('set_notification_preference', {
        p_type: v.type,
        p_channel: v.channel,
        p_enabled: v.enabled,
      })
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['notification_settings'] }),
  })
}

export function useNotificationTypes() {
  return useQuery({
    queryKey: ['notification_types'],
    staleTime: 5 * 60_000,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('notification_types')
        .select('*')
        .eq('is_active', true)
        .order('sort_order')
      if (error) throw error
      return data as NotificationType[]
    },
  })
}

export function useNotificationPolicies() {
  const has = useAuth((s) => s.has)
  return useQuery({
    queryKey: ['notification_policies'],
    enabled: has(PERM.NOTIFICATIONS_MANAGE),
    queryFn: async () => {
      const { data, error } = await supabase.from('notification_policies').select('*')
      if (error) throw error
      return data as NotificationPolicy[]
    },
  })
}

/**
 * שמירת תא במטריצה.
 *
 * בחירה שמחזירה את התא לברירת המחדל של הקטלוג *מוחקת* את השורה במקום לכתוב
 * אותה. כך `select * from notification_policies` נשאר "מה שהמנהל באמת שינה",
 * ולא רשימה שצריך להשוות מול ברירות המחדל כדי להבין ממנה משהו.
 */
export function useSavePolicy() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (v: {
      audience: NotificationAudience
      type: string
      channel: NotificationChannel
      mode: NotificationMode
      isDefault: boolean
    }) => {
      if (v.isDefault) {
        const { error } = await supabase
          .from('notification_policies')
          .delete()
          .eq('audience', v.audience)
          .eq('type', v.type)
          .eq('channel', v.channel)
        if (error) throw error
        return
      }
      const { error } = await supabase.from('notification_policies').upsert(
        {
          audience: v.audience,
          type: v.type,
          channel: v.channel,
          mode: v.mode,
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'audience,type,channel' },
      )
      if (error) throw error
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['notification_policies'] })
      void qc.invalidateQueries({ queryKey: ['notification_settings'] })
    },
  })
}

export function useUserNotificationSettings(profileId: string | null) {
  const has = useAuth((s) => s.has)
  return useQuery({
    queryKey: ['notification_settings', 'user', profileId],
    enabled: !!profileId && has(PERM.NOTIFICATIONS_MANAGE),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('notification_user_settings', {
        p_profile: profileId,
      })
      if (error) throw error
      return (data ?? []) as NotificationSetting[]
    },
  })
}

export function useNotificationOverrides(profileId: string | null) {
  const has = useAuth((s) => s.has)
  return useQuery({
    queryKey: ['notification_overrides', profileId],
    enabled: !!profileId && has(PERM.NOTIFICATIONS_MANAGE),
    queryFn: async () => {
      const { data, error } = await supabase
        .from('notification_policy_overrides')
        .select('*')
        .eq('profile_id', profileId)
      if (error) throw error
      return data as NotificationPolicyOverride[]
    },
  })
}

/** כל מי שיש לו חריג, כדי שהיוצאים מן הכלל לא יצטברו בלי שאיש רואה אותם. */
export function useOverriddenProfiles() {
  const has = useAuth((s) => s.has)
  return useQuery({
    queryKey: ['notification_overrides', 'all'],
    enabled: has(PERM.NOTIFICATIONS_MANAGE),
    queryFn: async () => {
      const { data, error } = await supabase
        .from('notification_policy_overrides')
        .select('profile_id, profiles(full_name)')
      if (error) throw error
      const seen = new Map<string, string>()
      for (const row of (data ?? []) as unknown as {
        profile_id: string
        profiles: { full_name: string } | null
      }[]) {
        if (!seen.has(row.profile_id)) seen.set(row.profile_id, row.profiles?.full_name ?? '—')
      }
      return [...seen].map(([id, name]) => ({ id, name }))
    },
  })
}

export function useSaveOverride() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (v: {
      profileId: string
      type: string
      channel: NotificationChannel
      mode: NotificationMode | null
    }) => {
      if (v.mode === null) {
        const { error } = await supabase
          .from('notification_policy_overrides')
          .delete()
          .eq('profile_id', v.profileId)
          .eq('type', v.type)
          .eq('channel', v.channel)
        if (error) throw error
        return
      }
      const { error } = await supabase.from('notification_policy_overrides').upsert(
        {
          profile_id: v.profileId,
          type: v.type,
          channel: v.channel,
          mode: v.mode,
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'profile_id,type,channel' },
      )
      if (error) throw error
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['notification_overrides'] })
      void qc.invalidateQueries({ queryKey: ['notification_settings'] })
    },
  })
}

export function usePushStats() {
  const has = useAuth((s) => s.has)
  return useQuery({
    queryKey: ['notification_push_stats'],
    enabled: has(PERM.NOTIFICATIONS_MANAGE),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('notification_push_stats')
      if (error) throw error
      return (data ?? {}) as Record<string, { devices: number; people: number }>
    },
  })
}

/** מכשירי הדחיפה שלי. RLS מצמצם ממילא, והסינון כאן הוא לקורא ולא לשרת. */
export function useMyDevices() {
  const me = useAuth((s) => s.me)
  return useQuery({
    queryKey: ['push_subscriptions', me?.profile.id],
    enabled: !!me,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('push_subscriptions')
        .select('id, profile_id, endpoint, user_agent, created_at, last_seen_at, failure_count, last_error')
        .order('last_seen_at', { ascending: false })
      if (error) throw error
      return data as PushSubscriptionRow[]
    },
  })
}

export function usePushConfig() {
  return useQuery({
    queryKey: ['app_settings', 'notifications.push'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('app_settings')
        .select('value')
        .eq('key', 'notifications.push')
        .maybeSingle()
      if (error) throw error
      const v = (data?.value ?? {}) as Partial<PushConfig>
      return {
        enabled: !!v.enabled,
        vapid_public_key: v.vapid_public_key ?? '',
        muted_types: v.muted_types ?? [],
      } satisfies PushConfig
    },
  })
}

export function useEmailConfig() {
  return useQuery({
    queryKey: ['app_settings', 'notifications.email'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('app_settings')
        .select('value')
        .eq('key', 'notifications.email')
        .maybeSingle()
      if (error) throw error
      const v = (data?.value ?? {}) as Partial<EmailConfig>
      return {
        enabled: !!v.enabled,
        from: v.from ?? '',
        muted_types: v.muted_types ?? [],
      } satisfies EmailConfig
    },
  })
}
