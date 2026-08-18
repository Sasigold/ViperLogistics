/**
 * מפרט האירוע — הלוגיקה שאינה נוגעת ברשת ולא ב-DOM.
 *
 * כל מה שכאן נבדק ב-specs.test.ts. הכללים חייבים לשקף את מה שהמסד והדלי אוכפים
 * (0077): אותה רשימת MIME ואותו גבול גודל. הבדיקה כאן אינה אבטחה — היא נימוס,
 * כדי שהשגיאה תגיע לפני שהמשתמש חיכה להעלאה של 20MB שתידחה בשרת.
 */
import type { EventSpec } from '../../types/domain'

/** 25MB — אותו ערך שנרשם על ה-bucket ב-0077. */
export const SPEC_MAX_BYTES = 25 * 1024 * 1024

export const SPEC_MIME_TYPES = [
  'application/pdf',
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
] as const

/** ל-`accept` של ה-input: דפדפנים אינם עקביים ב-MIME של HEIC, ולכן גם סיומות. */
export const SPEC_ACCEPT = '.pdf,.jpg,.jpeg,.png,.webp,.heic,.heif,application/pdf,image/*'

/**
 * איך המפרט מוצג בפועל.
 *
 * 'download' אינו כישלון: HEIC הוא פורמט לגיטימי שאייפון מייצר, אף דפדפן שולחני
 * אינו מרנדר אותו, וכרטיס הורדה עדיף על ריבוע שבור.
 */
export type SpecViewerKind = 'pdf' | 'image' | 'link' | 'download'

export function specViewerKind(spec: Pick<EventSpec, 'source' | 'mime_type' | 'file_name'>): SpecViewerKind {
  if (spec.source === 'link') return 'link'
  const mime = (spec.mime_type ?? '').toLowerCase()
  if (mime === 'application/pdf') return 'pdf'
  if (mime === 'image/heic' || mime === 'image/heif') return 'download'
  if (mime.startsWith('image/')) return 'image'
  // MIME ריק קורה כשהמערכת של המשתמש אינה מזהה את הקובץ; הסיומת היא מה שנשאר
  const ext = (spec.file_name ?? '').split('.').pop()?.toLowerCase() ?? ''
  if (ext === 'pdf') return 'pdf'
  if (ext === 'heic' || ext === 'heif') return 'download'
  if (['jpg', 'jpeg', 'png', 'webp'].includes(ext)) return 'image'
  return 'download'
}

/** null = הקובץ תקין. אחרת — המשפט שיוצג למשתמש. */
export function validateSpecFile(file: { name: string; type: string; size: number }): string | null {
  if (file.size === 0) return 'הקובץ ריק'
  if (file.size > SPEC_MAX_BYTES) {
    return `הקובץ גדול מ-${Math.round(SPEC_MAX_BYTES / 1024 / 1024)}MB (${formatBytes(file.size)})`
  }
  const mime = file.type.toLowerCase()
  if (mime && (SPEC_MIME_TYPES as readonly string[]).includes(mime)) return null
  // דפדפן שלא זיהה סוג שולח מחרוזת ריקה. הסיומת מכריעה במקומו.
  const ext = file.name.split('.').pop()?.toLowerCase() ?? ''
  if (['pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'].includes(ext)) return null
  return 'אפשר להעלות PDF או תמונה בלבד'
}

/** קישור חיצוני. null = תקין. */
export function validateSpecUrl(raw: string): string | null {
  const value = raw.trim()
  if (!value) return 'צריך להזין כתובת'
  let parsed: URL
  try {
    parsed = new URL(value)
  } catch {
    return 'הכתובת אינה תקינה'
  }
  // אותו פרדיקט שה-CHECK במסד אוכף. javascript: ו-data: אינם קישור למסמך.
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return 'הכתובת צריכה להתחיל ב-https://'
  return null
}

/**
 * הנתיב בדלי. התיקייה הראשונה היא מזהה האירוע — זה החוזה שפוליסת ה-Storage
 * קוראת ממנו (0077), ולכן הוא נבנה כאן ולא נלקח מהמשתמש.
 *
 * שם הקובץ המקורי אינו נכנס לנתיב: הוא בעברית, עם רווחים, ולפעמים ארוך מ-255
 * בתים. הוא נשמר בעמודה `file_name` ומוצג משם.
 */
export function specStoragePath(eventId: string, fileName: string, uuid: string): string {
  const ext = fileName.includes('.') ? fileName.split('.').pop()!.toLowerCase().replace(/[^a-z0-9]/g, '') : ''
  return ext ? `${eventId}/${uuid}.${ext}` : `${eventId}/${uuid}`
}

/** הגרסה הפעילה: הגבוהה שאינה מוסרת. undefined כשאין מפרט כלל. */
export function currentSpec(specs: EventSpec[]): EventSpec | undefined {
  return sortedSpecs(specs)[0]
}

/** מהחדשה לישנה — הסדר שבו ההיסטוריה נקראת. */
export function sortedSpecs(specs: EventSpec[]): EventSpec[] {
  return [...specs].filter((s) => !s.deleted_at).sort((a, b) => b.version - a.version)
}

/**
 * מה נפתח כשלוחצים "השוואה": החדשה מול זו שלפניה.
 *
 * כשיש גרסה אחת בלבד אין מה להשוות, ושתי החלוניות מציגות אותה — עדיף על חלונית
 * ריקה שנראית כמו תקלה.
 */
export function pickCompareDefaults(specs: EventSpec[]): [EventSpec, EventSpec] | null {
  const live = sortedSpecs(specs)
  if (live.length === 0) return null
  return [live[0], live[1] ?? live[0]]
}

/** 'גרסה 3 · מפרט סופי.pdf' */
export function specLabel(spec: EventSpec): string {
  const name = spec.title?.trim() || (spec.source === 'file' ? spec.file_name : spec.url) || ''
  return name ? `גרסה ${spec.version} · ${name}` : `גרסה ${spec.version}`
}

export function formatBytes(bytes: number | null): string {
  if (bytes == null || bytes <= 0) return ''
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`
}
