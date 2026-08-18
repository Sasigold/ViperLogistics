/**
 * המפרט של האירוע — קריאה, העלאה והסרה.
 *
 * הדלי `event-specs` פרטי (0077), ולכן אין URL קבוע לקובץ: כל תצוגה עוברת
 * ב-createSignedUrl. זה גם השימוש הראשון ב-Supabase Storage במערכת.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import type { EventSpec } from '../../types/domain'
import { specStoragePath } from './specs'

export const SPEC_BUCKET = 'event-specs'

/** תוקף הכתובת החתומה. ארוך מספיק לקרוא מפרט, קצר מספיק שלא ישוטט. */
const SIGNED_URL_TTL_SECONDS = 15 * 60

export function useEventSpecs(eventId: string, enabled = true) {
  return useQuery({
    queryKey: ['event_specs', eventId],
    enabled,
    queryFn: async () => {
      // RLS כבר מסתירה גרסאות שהוסרו ממי שאינו אדמין. הסינון כאן הוא כדי
      // שהמסך יראה אותו דבר לשני סוגי הקוראים.
      const { data, error } = await supabase
        .from('event_specs')
        .select('*')
        .eq('event_id', eventId)
        .is('deleted_at', null)
        .order('version', { ascending: false })
      if (error) throw error
      return data as EventSpec[]
    },
  })
}

/**
 * כתובת לתצוגה. לקישור חיצוני היא הכתובת עצמה; לקובץ היא חתומה ופגה.
 *
 * ה-staleTime קצר מהתוקף במכוון — כתובת שפגה במטמון היא תמונה שבורה שאיש
 * אינו מבין למה הופיעה.
 */
export function useSpecSignedUrl(spec: EventSpec | null | undefined) {
  return useQuery({
    queryKey: ['event_spec_url', spec?.id],
    enabled: !!spec,
    staleTime: (SIGNED_URL_TTL_SECONDS - 300) * 1000,
    gcTime: SIGNED_URL_TTL_SECONDS * 1000,
    queryFn: async () => {
      if (!spec) return null
      if (spec.source === 'link') return spec.url
      if (!spec.storage_path) return null
      const { data, error } = await supabase.storage
        .from(SPEC_BUCKET)
        .createSignedUrl(spec.storage_path, SIGNED_URL_TTL_SECONDS)
      if (error) throw error
      return data.signedUrl
    },
  })
}

/** הורדה מיידית — כתובת חתומה חד-פעמית שהדפדפן שומר בשם המקורי של הקובץ. */
export async function specDownloadUrl(spec: EventSpec): Promise<string | null> {
  if (spec.source === 'link') return spec.url
  if (!spec.storage_path) return null
  const { data, error } = await supabase.storage
    .from(SPEC_BUCKET)
    .createSignedUrl(spec.storage_path, SIGNED_URL_TTL_SECONDS, {
      download: spec.file_name ?? true,
    })
  if (error) throw error
  return data.signedUrl
}

export interface NewSpec {
  file?: File
  url?: string
  title?: string
}

/**
 * העלאה בשני צעדים, ובניקוי אחריהם.
 *
 * הקובץ עולה לפני שיש לו שורה, ולכן דחייה של ה-INSERT (הרשאה, אירוע שנמחק)
 * הייתה משאירה אובייקט יתום בדלי. ה-remove בענף הכישלון הוא מה שמונע את זה;
 * פוליסת ה-delete על storage.objects קיימת בשבילו בדיוק.
 *
 * מספר הגרסה אינו נשלח מכאן — הטריגר במסד קובע אותו תחת נעילה, ושתי העלאות
 * במקביל לאותו אירוע אינן יכולות לקבל אותו מספר.
 */
export function useUploadSpec(eventId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (next: NewSpec) => {
      const title = next.title?.trim() || null

      if (!next.file) {
        const { error } = await supabase.from('event_specs').insert({
          event_id: eventId,
          source: 'link',
          url: next.url!.trim(),
          title,
        })
        if (error) throw error
        return
      }

      const file = next.file
      const path = specStoragePath(eventId, file.name, crypto.randomUUID())
      const { error: upErr } = await supabase.storage.from(SPEC_BUCKET).upload(path, file, {
        contentType: file.type || undefined,
        upsert: false,
      })
      if (upErr) throw upErr

      const { error } = await supabase.from('event_specs').insert({
        event_id: eventId,
        source: 'file',
        storage_path: path,
        file_name: file.name,
        mime_type: file.type || null,
        size_bytes: file.size,
        title,
      })
      if (error) {
        await supabase.storage.from(SPEC_BUCKET).remove([path])
        throw error
      }
    },
    onSuccess: () => invalidate(qc, eventId),
  })
}

/**
 * הסרה עוברת ב-RPC ולא ב-UPDATE ישיר.
 *
 * פוסטגרס מחילה את פוליסת ה-select גם על השורה החדשה ב-UPDATE, ולכן שורה אינה
 * יכולה להעלים את עצמה מעיני מי שמחק אותה — אותה סיבה בדיוק ש-soft_delete של
 * אירוע הוא RPC. הקובץ עצמו נשאר בדלי: ההיסטוריה אינה נמחקת, היא רק יורדת מהמסך.
 */
export function useRemoveSpec(eventId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (specId: string) => {
      const { error } = await supabase.rpc('remove_event_spec', { p_spec_id: specId })
      if (error) throw error
    },
    onSuccess: () => invalidate(qc, eventId),
  })
}

function invalidate(qc: ReturnType<typeof useQueryClient>, eventId: string) {
  void qc.invalidateQueries({ queryKey: ['event_specs', eventId] })
  // הטריגר במסד רשם שורה ביומן, והיומן פתוח על אותו מסך
  void qc.invalidateQueries({ queryKey: ['event_activity', eventId] })
}
