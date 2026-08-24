/**
 * תוספות מחיר — קריאה, הוספה והסרה (0113).
 *
 * שתי זוויות על אותן שורות, ולכן שני מפתחות: ‏`task_price_addons` היא מה
 * שכרטיס המשימה עורך, ו-`event_price_addons` היא מה שכרטיס התמחור באירוע
 * מציג — אותן שורות, עם שם המשימה שהן יושבות עליה. שתיהן עוברות באותה
 * פוליסה, ולכן משתמש לקוח מקבל את התוספות של האירוע שלו ותו לא.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import type { EventPriceAddon, TaskPriceAddon } from '../../types/domain'

/**
 * ‏`Number` ולא חיבור ישיר: ‏PostgREST מחזירה `numeric` כמספר, אך שינוי אחד
 * בשכבת ההעברה היה הופך את הסכום לשרשור מחרוזות בשקט.
 */
export function sumAddons(rows: { amount: number }[]): number {
  return rows.reduce((total, r) => total + Number(r.amount), 0)
}

export function useTaskPriceAddons(taskId: string | null, enabled = true) {
  return useQuery({
    queryKey: ['task_price_addons', taskId],
    enabled: enabled && !!taskId,
    queryFn: async () => {
      // RLS כבר מסתירה שורות שהוסרו ממי שאינו אדמין. הסינון כאן הוא כדי
      // ששני סוגי הקוראים יראו את אותו כרטיס.
      const { data, error } = await supabase
        .from('task_price_addons')
        .select('*')
        .eq('task_id', taskId)
        .is('deleted_at', null)
        .order('created_at')
      if (error) throw error
      return data as TaskPriceAddon[]
    },
  })
}

export function useEventPriceAddons(eventId: string | null, enabled = true) {
  return useQuery({
    queryKey: ['event_price_addons', eventId],
    enabled: enabled && !!eventId,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('event_price_addons', { p_event_id: eventId })
      if (error) throw error
      return (data ?? []) as EventPriceAddon[]
    },
  })
}

export function useAddPriceAddon(taskId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (next: { amount: number; note: string }) => {
      const { error } = await supabase
        .from('task_price_addons')
        .insert({ task_id: taskId, amount: next.amount, note: next.note.trim() })
      if (error) throw error
    },
    onSuccess: () => invalidate(qc, taskId),
  })
}

/**
 * ההסרה עוברת ב-RPC ולא ב-UPDATE ישיר, מאותה סיבה שב-`useRemoveSpec`:
 * פוסטגרס מחילה את פוליסת ה-select גם על השורה החדשה ב-UPDATE, ולכן שורה
 * אינה יכולה להעלים את עצמה מעיני מי שמחק אותה.
 */
export function useRemovePriceAddon(taskId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (addonId: string) => {
      const { error } = await supabase.rpc('remove_task_price_addon', { p_addon_id: addonId })
      if (error) throw error
    },
    onSuccess: () => invalidate(qc, taskId),
  })
}

function invalidate(qc: ReturnType<typeof useQueryClient>, taskId: string) {
  void qc.invalidateQueries({ queryKey: ['task_price_addons', taskId] })
  /* כרטיס התמחור באירוע מסכם את התוספות, והוא פתוח על מסך אחר — אין כאן
     את מזהה האירוע, ולכן כל השורשים שהתוספת נוגעת בהם מתיישנים יחד. */
  void qc.invalidateQueries({ queryKey: ['event_price_addons'] })
  void qc.invalidateQueries({ queryKey: ['event_activity'] })
}
