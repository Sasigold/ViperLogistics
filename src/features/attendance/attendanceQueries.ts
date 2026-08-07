/**
 * הוקים של מודול הנוכחות.
 *
 * כמעט הכול עובר דרך RPCs ולא דרך הטבלאות: השעון כותב רק דרך
 * attendance_clock_in/out (זה מה שהופך את חסימת המיקום לאכיפה ולא להצעה),
 * והדוח מגיע מ-attendance_report כי הוא צריך לקרוא תעריפים שהקורא עצמו
 * אינו רשאי לקרוא.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import type {
  AttendanceReport,
  ClockConfig,
  ClockStatus,
  OvertimeConfig,
  PlannedShift,
  Warehouse,
  WorkerPaySettings,
} from '../../types/domain'

/** מפתח כלשהו מ-app_settings. הטבלה קריאה לכל מאומת. */
export function useAppSetting<T>(key: string) {
  return useQuery({
    queryKey: ['app_settings', key],
    queryFn: async () => {
      const { data, error } = await supabase.from('app_settings').select('value').eq('key', key).maybeSingle()
      if (error) throw error
      return ((data as { value: T } | null)?.value ?? null) as T | null
    },
  })
}

export function useOvertimeConfig() {
  return useAppSetting<OvertimeConfig>('attendance.overtime')
}

/** קריאה פתוחה לכל מאומת: הדפדפן צריך את זה כדי לדעת מול מה הוא נמדד. */
export function useWarehouses(activeOnly = false) {
  return useQuery({
    queryKey: ['warehouses', activeOnly],
    queryFn: async () => {
      let q = supabase.from('warehouses').select('*').is('deleted_at', null)
      if (activeOnly) q = q.eq('is_active', true)
      const { data, error } = await q.order('sort_order').order('name')
      if (error) throw error
      return data as Warehouse[]
    },
  })
}

export function useClockConfig() {
  return useAppSetting<ClockConfig>('attendance.clock')
}

export function useSaveAppSetting(key: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (value: unknown) => {
      const { error } = await supabase.from('app_settings').upsert({ key, value })
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['app_settings', key] }),
  })
}

export function useMyClockStatus() {
  const has = useAuth((s) => s.has)
  return useQuery({
    queryKey: ['attendance', 'status'],
    enabled: has(PERM.ATTENDANCE_VIEW_OWN),
    // המשמרת "הנוכחית" זזה עם השעון, ולכן הנתון מתיישן מעצמו
    refetchInterval: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('attendance_my_status')
      if (error) throw error
      return data as ClockStatus
    },
  })
}

export function useMyShifts(from: string, to: string) {
  const has = useAuth((s) => s.has)
  return useQuery({
    queryKey: ['attendance', 'shifts', from, to],
    enabled: has(PERM.ATTENDANCE_VIEW_SCHEDULE) && !!from && !!to,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('my_shifts', { p_from: from, p_to: to })
      if (error) throw error
      return (data ?? []) as PlannedShift[]
    },
  })
}

export function useEmployeeShifts(profileId: string | null, from: string, to: string) {
  return useQuery({
    queryKey: ['attendance', 'shifts', 'employee', profileId, from, to],
    enabled: !!profileId && !!from && !!to,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('employee_shifts', {
        p_profile_id: profileId,
        p_from: from,
        p_to: to,
      })
      if (error) throw error
      return (data ?? []) as PlannedShift[]
    },
  })
}

export interface ReportFilters {
  from: string
  to: string
  profileIds?: string[] | null
  contractorId?: string | null
  onlyFlagged?: boolean
}

export function useAttendanceReport(f: ReportFilters, enabled = true) {
  return useQuery({
    queryKey: ['attendance', 'report', f],
    enabled: enabled && !!f.from && !!f.to,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('attendance_report', {
        p_from: f.from,
        p_to: f.to,
        p_profile_ids: f.profileIds?.length ? f.profileIds : null,
        p_contractor_id: f.contractorId ?? null,
        p_only_flagged: f.onlyFlagged ?? false,
      })
      if (error) throw error
      return data as AttendanceReport
    },
  })
}

/**
 * הגדרות השכר והשעון של עובד. חוזרת null גם כשהשורה קיימת אבל ה-RLS חוסם
 * אותה — הכרטיס במסך הוא שמגודר, לא השאילתה.
 */
export function useWorkerPaySettings(profileId?: string | null) {
  return useQuery({
    queryKey: ['worker_pay_settings', profileId],
    enabled: !!profileId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('worker_pay_settings')
        .select('*')
        .eq('profile_id', profileId)
        .maybeSingle()
      if (error) throw error
      return (data as WorkerPaySettings) ?? null
    },
  })
}

export function useSaveWorkerPaySettings(profileId?: string | null) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (patch: Partial<WorkerPaySettings>) => {
      if (!profileId) throw new Error('חסר מזהה עובד')
      const { error } = await supabase
        .from('worker_pay_settings')
        .upsert({ profile_id: profileId, ...patch }, { onConflict: 'profile_id' })
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['worker_pay_settings', profileId] }),
  })
}

/** כל מה שמשנה נוכחות מרענן גם את הסטטוס וגם את הדוח. */
export function useAttendanceInvalidate() {
  const qc = useQueryClient()
  return () => void qc.invalidateQueries({ queryKey: ['attendance'] })
}
