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
  NotificationScope,
  NotificationScopeKind,
  NotificationScopeMode,
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

/**
 * ארבעת המצבים, לפי מה שקורה בפועל.
 *
 * מ-0086 אין למשתמש דעה: ההעדפה האישית ירדה מסולם ההכרעה, ולכן `opt_in`
 * ו-`off` נגמרים באותו מקום, וכך גם `opt_out` ו-`forced`. שני הזוגות נשארים
 * כי הם ברירות המחדל שבקטלוג (`notification_types`) ומה שכבר שמור בטבלת
 * המדיניות — התוויות הן שהיו משקרות, לא הערכים.
 */
export const MODES: { key: NotificationMode; label: string; hint: string }[] = [
  { key: 'off', label: 'לא נשלח', hint: 'ההתראה כבויה לקהל הזה' },
  { key: 'opt_in', label: 'לא נשלח (כבוי כברירת מחדל)', hint: 'ברירת מחדל כבויה בקטלוג' },
  { key: 'opt_out', label: 'נשלח (דלוק כברירת מחדל)', hint: 'ברירת מחדל דלוקה בקטלוג' },
  { key: 'forced', label: 'נשלח תמיד', hint: 'ההתראה נשלחת לקהל הזה' },
]

export const SCOPE_KINDS: { key: NotificationScopeKind; label: string }[] = [
  { key: 'customer', label: 'לקוחות' },
  { key: 'contractor', label: 'קבלנים' },
  { key: 'worker', label: 'עובדים' },
]

/**
 * אילו סוגי-ישות רלוונטיים לתחולה של כל סוג — מראה מדויקת של מה שהפולטים
 * ב-0110 בודקים בפועל דרך app.notification_in_scope. סוג שאינו כאן אינו
 * נבדק מול תחולה (הפולט שלו לא השתנה), ולכן אין להציג לו בורר.
 */
const SCOPE_MAP: Record<string, NotificationScopeKind[]> = {
  event_created: ['customer'],
  event_approved: ['customer'],
  event_updated: ['customer'],
  event_cancelled: ['customer'],
  spec_uploaded: ['customer'],
  /* ‏0136: המעבר בין זרועות הביצוע נבדק מול תחולת הלקוח, כמו שאר האירוע. */
  task_performed_by_changed: ['customer'],
  task_published: ['worker', 'contractor'],
  task_unpublished: ['worker', 'contractor'],
  task_assigned: ['worker', 'contractor'],
  assignment_removed: ['worker', 'contractor'],
  task_time_changed: ['worker', 'contractor'],
  contractor_worker_count_changed: ['contractor'],
  contractor_worker_assigned: ['contractor'],
  attendance_clock_in: ['worker', 'contractor'],
  attendance_clock_out: ['worker', 'contractor'],
}

export function scopeKindsForType(t: NotificationType): NotificationScopeKind[] {
  return SCOPE_MAP[t.key] ?? []
}

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

/*
 * ‏`useSetPreference` הוסרה ב-0086 ולא נשארה כאן כקוד מת: ההעדפה האישית
 * ירדה מסולם ההכרעה, ו-`set_notification_preference` זורק 42501 לכל קורא.
 * מי שקובע הוא המנהל — `useSavePolicy` לקהל ו-`useSaveOverride` לאדם.
 */

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

/**
 * התחולה (0110): טבלאות דלילות באותה פילוסופיה של notification_policies —
 * שורה קיימת רק כשמנהל צמצם. אין שורת מצב = הסוג חל על כולם, וההתראה
 * שהנושא שלה מחוץ לתחולה אינה נוצרת כלל (בשונה מהשתקה, שמתעדת ומסננת).
 */
export function useNotificationScopeModes() {
  const has = useAuth((s) => s.has)
  return useQuery({
    queryKey: ['notification_scope_modes'],
    enabled: has(PERM.NOTIFICATIONS_MANAGE),
    queryFn: async () => {
      const { data, error } = await supabase.from('notification_scope_modes').select('*')
      if (error) throw error
      return data as NotificationScopeMode[]
    },
  })
}

export function useNotificationScopes() {
  const has = useAuth((s) => s.has)
  return useQuery({
    queryKey: ['notification_scopes'],
    enabled: has(PERM.NOTIFICATIONS_MANAGE),
    queryFn: async () => {
      const { data, error } = await supabase.from('notification_scopes').select('*')
      if (error) throw error
      return data as NotificationScope[]
    },
  })
}

/** בחירת 'all' מוחקת את שורת המצב ואת הרשימה — הטבלה נשארת "מה שצומצם". */
export function useSaveScopeMode() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (v: {
      type: string
      entityKind: NotificationScopeKind
      mode: 'all' | 'selected'
    }) => {
      if (v.mode === 'all') {
        const del = await supabase
          .from('notification_scope_modes')
          .delete()
          .eq('type', v.type)
          .eq('entity_kind', v.entityKind)
        if (del.error) throw del.error
        const delScopes = await supabase
          .from('notification_scopes')
          .delete()
          .eq('type', v.type)
          .eq('entity_kind', v.entityKind)
        if (delScopes.error) throw delScopes.error
        return
      }
      const { error } = await supabase
        .from('notification_scope_modes')
        .upsert(
          { type: v.type, entity_kind: v.entityKind, mode: v.mode, updated_at: new Date().toISOString() },
          { onConflict: 'type,entity_kind' },
        )
      if (error) throw error
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['notification_scope_modes'] })
      void qc.invalidateQueries({ queryKey: ['notification_scopes'] })
    },
  })
}

/** הוספה/הסרה של ישות בודדת ברשימת התחולה של (סוג, סוג-ישות). */
export function useToggleScopeEntity() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (v: {
      type: string
      entityKind: NotificationScopeKind
      entityId: string
      included: boolean
    }) => {
      if (v.included) {
        const { error } = await supabase
          .from('notification_scopes')
          .upsert(
            { type: v.type, entity_kind: v.entityKind, entity_id: v.entityId },
            { onConflict: 'type,entity_kind,entity_id' },
          )
        if (error) throw error
        return
      }
      const { error } = await supabase
        .from('notification_scopes')
        .delete()
        .eq('type', v.type)
        .eq('entity_kind', v.entityKind)
        .eq('entity_id', v.entityId)
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['notification_scopes'] }),
  })
}

/** הישויות שהבורר מציג: לקוחות, קבלנים, ועובדי סגל פעילים. */
export function useScopeEntities(kind: NotificationScopeKind, enabled: boolean) {
  const has = useAuth((s) => s.has)
  return useQuery({
    queryKey: ['notification_scope_entities', kind],
    enabled: enabled && has(PERM.NOTIFICATIONS_MANAGE),
    queryFn: async (): Promise<{ id: string; name: string }[]> => {
      if (kind === 'customer') {
        const { data, error } = await supabase
          .from('customers')
          .select('id, name')
          .is('deleted_at', null)
          .eq('is_active', true)
          .order('name')
        if (error) throw error
        return data as { id: string; name: string }[]
      }
      if (kind === 'contractor') {
        const { data, error } = await supabase
          .from('contractors')
          .select('id, name')
          .is('deleted_at', null)
          .eq('is_active', true)
          .order('name')
        if (error) throw error
        return data as { id: string; name: string }[]
      }
      const { data, error } = await supabase
        .from('profiles')
        .select('id, full_name')
        .eq('user_kind', 'staff')
        .eq('is_active', true)
        .is('deleted_at', null)
        .order('full_name')
      if (error) throw error
      return (data as { id: string; full_name: string }[]).map((p) => ({
        id: p.id,
        name: p.full_name,
      }))
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
