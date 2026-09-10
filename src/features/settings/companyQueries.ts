/**
 * פרטי החברה והלוגו שלה (0170).
 *
 * שניהם נדרשים לכותרת של מסמך הצעת המחיר, ועד היום לא היה להם מקום בכלל —
 * לא ח.פ, לא טלפון ולא קובץ לוגו. הפרטים יושבים ב-`app_settings` תחת
 * `company.details`, כי מספר טלפון שמשתנה אינו אמור לדרוש פריסה; הלוגו יושב
 * בדלי `company-assets`, כי הוא קובץ.
 *
 * הדלי פרטי כמו כל דלי אחר ברפו, אבל השער שלו שונה: קריאה פתוחה לכל מאומת
 * (לוגו אינו סוד, וכל מי שמפיק מסמך צריך אותו) וכתיבה למי שמנהל הגדרות.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import { useAppSetting } from '../attendance/attendanceQueries'
import { COMPANY_SETTINGS_KEY, EMPTY_COMPANY } from '../events/quote'
import type { CompanyDetails } from '../../types/domain'

export const COMPANY_BUCKET = 'company-assets'

/** ‏PNG/JPEG בלבד: pdf-lib מטמיע רק אותם, והדלי חוסם את השאר ממילא. */
export const LOGO_MIME = ['image/png', 'image/jpeg']

const SIGNED_URL_TTL_SECONDS = 15 * 60

/** פרטי החברה, עם נפילה לברירת מחדל כדי שמסך לא יתרסק על מסד ריק. */
export function useCompanyDetails() {
  const q = useAppSetting<CompanyDetails>(COMPANY_SETTINGS_KEY)
  return { ...q, company: { ...EMPTY_COMPANY, ...(q.data ?? {}) } as CompanyDetails }
}

/**
 * כתובת חתומה ללוגו, לתצוגה במסך ההגדרות.
 *
 * ה-staleTime קצר מהתוקף במכוון, כמו במפרט: כתובת שפגה במטמון היא תמונה
 * שבורה שאיש אינו מבין למה הופיעה.
 */
export function useCompanyLogoUrl(path: string | null | undefined) {
  return useQuery({
    queryKey: ['company_logo_url', path],
    enabled: !!path,
    staleTime: (SIGNED_URL_TTL_SECONDS - 300) * 1000,
    gcTime: SIGNED_URL_TTL_SECONDS * 1000,
    queryFn: async () => {
      if (!path) return null
      const { data, error } = await supabase.storage
        .from(COMPANY_BUCKET)
        .createSignedUrl(path, SIGNED_URL_TTL_SECONDS)
      if (error) throw error
      return data.signedUrl
    },
  })
}

/** הבייטים עצמם — מה ש-pdf-lib צריך כדי להטמיע את הלוגו במסמך. */
export async function fetchCompanyLogo(
  path: string | null,
): Promise<{ bytes: Uint8Array; kind: 'png' | 'jpg' } | null> {
  if (!path) return null
  const { data, error } = await supabase.storage.from(COMPANY_BUCKET).download(path)
  if (error || !data) return null
  const bytes = new Uint8Array(await data.arrayBuffer())
  return { bytes, kind: path.toLowerCase().endsWith('.png') ? 'png' : 'jpg' }
}

/**
 * שמירת פרטי החברה. שדה בודד או כולם — המיזוג נעשה כאן, כי `app_settings`
 * מחזיקה jsonb אחד ו-upsert עליו הוא החלפה.
 */
export function useSaveCompany() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (value: CompanyDetails) => {
      const { error } = await supabase
        .from('app_settings')
        .upsert({ key: COMPANY_SETTINGS_KEY, value })
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['app_settings', COMPANY_SETTINGS_KEY] }),
  })
}

/**
 * העלאת לוגו: קובץ לדלי, ואז הנתיב אל ההגדרות.
 *
 * אותו דפוס של המפרט (`specQueries.ts`) — העלאה, כתיבה, וניקוי הקובץ אם
 * הכתיבה נדחתה — ובנוסף הסרת הלוגו הקודם. קובץ יתום בדלי שאיש אינו מצביע
 * עליו הוא בדיוק מה שהופך "החלפת לוגו" לתיקייה שגדלה לנצח.
 */
export function useUploadCompanyLogo() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ file, company }: { file: File; company: CompanyDetails }) => {
      const ext = file.type === 'image/png' ? 'png' : 'jpg'
      const path = `logo/${crypto.randomUUID()}.${ext}`
      const { error: upErr } = await supabase.storage
        .from(COMPANY_BUCKET)
        .upload(path, file, { contentType: file.type, upsert: false })
      if (upErr) throw upErr

      const { error } = await supabase
        .from('app_settings')
        .upsert({ key: COMPANY_SETTINGS_KEY, value: { ...company, logo_path: path } })
      if (error) {
        await supabase.storage.from(COMPANY_BUCKET).remove([path])
        throw error
      }

      if (company.logo_path && company.logo_path !== path) {
        await supabase.storage.from(COMPANY_BUCKET).remove([company.logo_path])
      }
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['app_settings', COMPANY_SETTINGS_KEY] }),
  })
}
