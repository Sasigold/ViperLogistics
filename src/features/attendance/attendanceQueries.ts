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
  AttendanceStatus,
  ClockConfig,
  ClockStatus,
  OvertimeConfig,
  PlannedShift,
  ShiftBreakdown,
  ShiftRosterEntry,
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
    // עובד שטח בלי קליטה: ברירת המחדל ('online') משהה את ה-fetch כשהדפדפן
    // מדווח offline, וה-cache של ה-service worker לא היה נשאל בכלל.
    // offlineFirst נותן לבקשה לצאת — וה-SW עונה מהעותק השמור.
    networkMode: 'offlineFirst',
    queryFn: async () => {
      // GET ולא POST: הפונקציה stable, ורק בקשת GET נתפסת במטמון ה-SW
      const { data, error } = await supabase.rpc('attendance_my_status', undefined, { get: true })
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
    // ראו useMyClockStatus: offlineFirst + GET כדי שהלוח יעלה גם בלי קליטה
    networkMode: 'offlineFirst',
    queryFn: async () => {
      const { data, error } = await supabase.rpc('my_shifts', { p_from: from, p_to: to }, { get: true })
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

/**
 * הרוסטר של לוח המשמרות: מי בכלל אמור להופיע בו, בטווח מסוים.
 *
 * RPC ולא שאילתה על profiles, כי profiles_select נותן לעובד צוות לקרוא רק
 * שורות user_kind='staff' — ועובד קבלן שקיבל התחברות אינו שם. לוח שנבנה
 * מקריאה ישירה היה מציג "את כולם" בלי חצי מהם.
 *
 * הטווח משפיע: עובד שהושבת נכלל רק אם יש לו שיבוץ בתוכו.
 */
export function useShiftRoster(from: string, to: string, enabled = true) {
  return useQuery({
    queryKey: ['attendance', 'roster', from, to],
    enabled: enabled && !!from && !!to,
    staleTime: 5 * 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('shift_roster', { p_from: from, p_to: to })
      if (error) throw error
      return (data ?? []) as ShiftRosterEntry[]
    },
  })
}

/**
 * המשמרות של כל הצוות בטווח. p_profile_ids הוא חיתוך עם מה שמותר לקורא
 * לראות ולעולם לא הרחבה שלו — השרת מצמצם בשקט, ולכן אין כאן טיפול בשגיאה
 * של "ביקשת עובד שאסור לך".
 */
export function useTeamShifts(from: string, to: string, profileIds?: string[] | null) {
  const has = useAuth((s) => s.has)
  return useQuery({
    queryKey: ['attendance', 'team_shifts', from, to, profileIds ?? null],
    enabled: has(PERM.ATTENDANCE_VIEW_ALL) && !!from && !!to,
    // דפדוף בין שבועות משאיר את הלוח הקודם על המסך במקום לרוקן אותו
    placeholderData: (prev) => prev,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('team_shifts', {
        p_from: from,
        p_to: to,
        p_profile_ids: profileIds?.length ? profileIds : null,
      })
      if (error) throw error
      return (data ?? []) as PlannedShift[]
    },
  })
}

/**
 * מאיזה משימות מורכבת המשמרת. המזהים מגיעים מהשורה שנלחצה ולא מחושבים
 * מחדש: seq של משמרת תלוי בטווח שגזר אותו, ולכן גזירה חוזרת עלולה לתאר
 * בשקט משמרת אחרת. השרת מוודא שכל מזהה באמת משובץ לאדם הזה.
 */
export function useShiftTasks(profileId: string | null, taskIds: string[] | null) {
  const key = taskIds?.length ? [...taskIds].sort().join(',') : null
  return useQuery({
    queryKey: ['attendance', 'shift_tasks', profileId, key],
    enabled: !!profileId && !!key,
    staleTime: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('shift_task_breakdown', {
        p_profile_id: profileId,
        p_task_ids: taskIds,
      })
      if (error) throw error
      return data as ShiftBreakdown
    },
  })
}

export interface ReportFilters {
  from: string
  to: string
  profileIds?: string[] | null
  contractorId?: string | null
  onlyFlagged?: boolean
  /** null = כל הסטטוסים. הסינון נעשה בשרת כדי שהסיכומים יתאימו לשורות. */
  status?: AttendanceStatus[] | null
}

/**
 * הסגל של הקבלן שלי, כדי לבנות ממנו מסנן "עובד" בדוח שבפורטל. profiles_select
 * חוסם קריאה ישירה לטבלה עבור contractor_user (מותר לו רק השורה של עצמו),
 * ולכן זה RPC ולא שאילתה ישירה — עם אותו מפתח שהדוח עצמו בודק.
 */
export function useContractorStaff() {
  const has = useAuth((s) => s.has)
  return useQuery({
    queryKey: ['attendance', 'contractor_staff'],
    enabled: has(PERM.PORTAL_ATTENDANCE),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('contractor_staff_list')
      if (error) throw error
      return (data ?? []) as { id: string; full_name: string }[]
    },
  })
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
        p_status: f.status?.length ? f.status : null,
      })
      if (error) throw error
      return data as AttendanceReport
    },
  })
}

/**
 * דיווח משמרת ידני של העובד עצמו. נכתב בסטטוס 'ממתין לאישור' ואינו נספר
 * בשעות עד שמנהל יאשר — כל הבדיקות (חפיפה, חלון אחורה, משמרת עתידית)
 * יושבות ב-RPC, ולכן הטופס כאן מוודא רק שיש מה לשלוח.
 */
export function useSubmitAttendanceEntry() {
  const invalidate = useAttendanceInvalidate()
  return useMutation({
    mutationFn: async (v: {
      clockIn: string
      clockOut: string
      note?: string | null
      /** חובה בשרת: לדיווח ידני אין GPS, והמלל הוא מה שהמנהל מאשר לפיו (0084) */
      inPlace: string
      outPlace: string
    }) => {
      const { data, error } = await supabase.rpc('attendance_submit_entry', {
        p_clock_in: new Date(v.clockIn).toISOString(),
        p_clock_out: new Date(v.clockOut).toISOString(),
        p_note: v.note || null,
        p_in_place: v.inPlace,
        p_out_place: v.outPlace,
      })
      if (error) throw error
      return data as { entry_id: string; hours: number }
    },
    onSuccess: invalidate,
  })
}

/** אישור או דחייה של דיווח. דחייה מחייבת נימוק — השרת דוחה בלעדיו. */
export function useReviewAttendanceEntry() {
  const invalidate = useAttendanceInvalidate()
  return useMutation({
    mutationFn: async (v: { id: string; approve: boolean; note?: string | null }) => {
      const { error } = await supabase.rpc('attendance_review_entry', {
        p_id: v.id,
        p_approve: v.approve,
        p_note: v.note || null,
      })
      if (error) throw error
    },
    onSuccess: invalidate,
  })
}

/**
 * בונוס למשמרת. RPC משלו ולא פרמטר על attendance_save_entry, כי הוא נשמר
 * במפתח אחר: מי שמתקן שעות (attendance.edit_entry) אינו בהכרח מי שרשאי
 * לקבוע סכום כסף (attendance.manage_bonus). אפס מוחק את הבונוס.
 */
export function useSetShiftBonus() {
  const invalidate = useAttendanceInvalidate()
  return useMutation({
    mutationFn: async (v: { id: string; bonus: number; note?: string | null }) => {
      const { error } = await supabase.rpc('attendance_set_bonus', {
        p_id: v.id,
        p_bonus: v.bonus,
        p_note: v.note || null,
      })
      if (error) throw error
    },
    onSuccess: invalidate,
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
