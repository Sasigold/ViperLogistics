import { format, parseISO } from 'date-fns'
import { he } from 'date-fns/locale'
import type { AttendanceStatus, WorkSite } from '../../types/domain'

export const WORK_SITE_LABELS: Record<WorkSite, string> = {
  field: 'שטח',
  warehouse: 'מחסן',
}

/**
 * דגלים שהשעון תולה על רשומה. הרשימה כאן היא תצוגה בלבד — הקודים עצמם
 * נכתבים במסד כ-text[] פתוח, ולכן קוד שיתווסף בעתיד יופיע כמו שהוא ולא
 * ייעלם מהמסך.
 */
export const FLAG_LABELS: Record<string, string> = {
  no_site_coords: 'לא אומת מיקום',
  no_shift: 'ללא משמרת משובצת',
  low_accuracy: 'דיוק מיקום נמוך',
  auto_closed: 'נסגרה אוטומטית',
  manual: 'הוזן ידנית',
  self_reported: 'דיווח עצמי',
  edited: 'תוקן',
}

export const flagLabel = (f: string) => FLAG_LABELS[f] ?? f

/**
 * מתוך כל הדגלים שהשעון עשוי לתלות על רשומה, רק שניים שווים תג משלהם: תוקן
 * (מנהל נגע בשעות) ו-ללא משמרת משובצת (חסר שיבוץ לצייד את הדוח מולו). השאר
 * — אימות מיקום, דיוק, סגירה אוטומטית, דיווח עצמי — הם פרטי אבחון של השעון
 * שלא עוזרים למי שקורא את הדוח, ו-'manual' עצמו מיותר כי מקור הרשומה כבר
 * מסומן בתג נפרד ("ידני").
 */
const NOTABLE_FLAGS = new Set(['edited', 'no_shift'])

export const visibleFlags = (flags: string[] | null | undefined) =>
  (flags ?? []).filter((f) => NOTABLE_FLAGS.has(f))

/**
 * מצב האישור. 'approved' אינו מקבל תווית: רשומה מאושרת היא המצב הרגיל,
 * ותג על כל שורה בדוח היה רעש שמסתיר את שתי השורות שבאמת דורשות מבט.
 */
export const STATUS_LABELS: Record<AttendanceStatus, string> = {
  pending: 'ממתין לאישור',
  approved: 'מאושר',
  rejected: 'נדחה',
}

export const STATUS_TONES: Record<AttendanceStatus, 'warning' | 'success' | 'error'> = {
  pending: 'warning',
  approved: 'success',
  rejected: 'error',
}

/** דגלים שמצדיקים תשומת לב של מנהל, להבדיל מאלה שהם רק מידע. */
export const ATTENTION_FLAGS = new Set(['no_site_coords', 'no_shift', 'auto_closed', 'low_accuracy'])

export const needsAttention = (flags: string[] | null | undefined) =>
  (flags ?? []).some((f) => ATTENTION_FLAGS.has(f))

const hhmm = (iso: string) => format(parseISO(iso), 'HH:mm')

/** '07:00–14:00'. משמרת שחוצה חצות מקבלת את התאריך בצד הסיום. */
export function fmtShiftRange(start?: string | null, end?: string | null): string {
  if (!start) return ''
  if (!end) return `${hhmm(start)}–`
  const sameDay = format(parseISO(start), 'yyyy-MM-dd') === format(parseISO(end), 'yyyy-MM-dd')
  return sameDay ? `${hhmm(start)}–${hhmm(end)}` : `${hhmm(start)}–${format(parseISO(end), 'HH:mm (dd/MM)')}`
}

/** 'יום ג׳, 12 באוגוסט' */
export function fmtDayLabel(d: string): string {
  return format(parseISO(d), 'EEEE, d בMMMM', { locale: he })
}

/** שעות עשרוניות ל-'8:30 ש׳' */
export function fmtDuration(hours: number | null | undefined): string {
  if (hours == null) return '—'
  const mins = Math.round(hours * 60)
  return `${Math.floor(mins / 60)}:${String(mins % 60).padStart(2, '0')}`
}

/** מטרים לתצוגה קצרה: 240 מ׳ / 3.2 ק״מ */
export function fmtDistance(m: number | null | undefined): string {
  if (m == null) return ''
  return m < 1000 ? `${Math.round(m)} מ׳` : `${(m / 1000).toFixed(1)} ק״מ`
}
