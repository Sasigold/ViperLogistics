import { format, parseISO } from 'date-fns'
import { he } from 'date-fns/locale'
import type { AttendanceReportRow, AttendanceStatus, StaffRole, WorkSite } from '../../types/domain'

export const WORK_SITE_LABELS: Record<WorkSite, string> = {
  field: 'שטח',
  warehouse: 'מחסן',
}

/**
 * התפקיד בשיבוץ למשימה. יושב כאן ולא במסך העובדים כי שני מסכים קוראים אותו
 * — ניהול העובדים ופירוק המשמרת — ושתי רשימות זהות הן שתי רשימות שיסטו.
 */
export const ASSIGNMENT_ROLE_LABELS: Record<StaffRole, string> = {
  worker: 'עובד',
  driver: 'נהג',
  team_lead: 'ראש צוות',
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

/** פער של פחות מדקה בין המתוכנן לבפועל הוא עיגול, לא חוסר. */
export const SHORTFALL_TOLERANCE_H = 1 / 60

/**
 * כמה שעות חסרות במשמרת מול השיבוץ שלה.
 *
 * משמרת בלי שיבוץ — החתמה ספונטנית — אינה "חסרה": אין מולה מה להשוות, וכל
 * מספר שהיה מוחזר כאן היה המצאה. אותה הכרעה משמשת גם את שורת המשמרת וגם את
 * אריח "שעות חסרות", כדי שהאריח יהיה בדיוק סכום השורות שמתחתיו.
 */
export function shiftShortfall(
  plannedHours: number | null | undefined,
  actualHours: number | null | undefined,
): number {
  const planned = plannedHours ?? 0
  if (planned <= 0) return 0
  const gap = planned - (actualHours ?? 0)
  return gap >= SHORTFALL_TOLERANCE_H ? gap : 0
}

/**
 * מה המשמרת אומרת במבט אחד — לא מצב האישור בלבד. משמרת מאושרת יכולה עדיין
 * להיות "שעות נוספות" או "חסר", וזה מה שמי שקורא את הדוח מחפש בה.
 */
export type ShiftTone = 'present' | 'overtime' | 'short' | 'pending' | 'rejected' | 'open'

/**
 * הטון של משמרת אחת. סדר ההכרעה הוא מה שמעכב תשלום לפני מה שרק מתאר את
 * המשמרת: רשומה שממתינה לאישור אינה "נוכח" גם אם השעות בה מושלמות, ומשמרת
 * שעדיין פתוחה אינה "חסר" רק משום שהעובד לא סיים אותה עדיין.
 */
export function shiftTone(
  r: Pick<AttendanceReportRow, 'status' | 'clock_out_at' | 'planned_hours' | 'actual_hours' | 'pay'>,
): ShiftTone {
  if (r.status === 'pending') return 'pending'
  if (r.status === 'rejected') return 'rejected'
  if (!r.clock_out_at) return 'open'
  if ((r.pay?.overtime_hours ?? 0) > 0) return 'overtime'
  return shiftShortfall(r.planned_hours, r.actual_hours) > 0 ? 'short' : 'present'
}

/** דגלים שמצדיקים תשומת לב של מנהל, להבדיל מאלה שהם רק מידע. */
export const ATTENTION_FLAGS = new Set(['no_site_coords', 'no_shift', 'auto_closed', 'low_accuracy'])

export const needsAttention = (flags: string[] | null | undefined) =>
  (flags ?? []).some((f) => ATTENTION_FLAGS.has(f))

/** '07:00'. שעה בודדת, כשהטווח כבר מוצג במקום אחר בשורה. */
export const fmtTime = (iso: string) => format(parseISO(iso), 'HH:mm')

const hhmm = fmtTime

/** '07:00–14:00'. משמרת שחוצה חצות מקבלת את התאריך בצד הסיום. */
export function fmtShiftRange(start?: string | null, end?: string | null): string {
  if (!start) return ''
  if (!end) return `${hhmm(start)}–`
  const sameDay = format(parseISO(start), 'yyyy-MM-dd') === format(parseISO(end), 'yyyy-MM-dd')
  return sameDay ? `${hhmm(start)}–${hhmm(end)}` : `${hhmm(start)}–${format(parseISO(end), 'HH:mm (dd/MM)')}`
}

/**
 * השעה שבה יורדים מהעבודה, כשסוף המשמרת כולל נסיעה חזרה למחסן.
 *
 * ‏`shift_end` נושא את הנסיעה בתוכו (0079 §4) ו-`travel_hours` הוא בדיוק
 * היא, ולכן החיסור הזה הוא היחיד שמפריד בין "סיימנו" ל"הגענו". מוחזר ''
 * כשאין נסיעה — אז שתי השעות הן אותה שעה, ואין מה להפריד.
 */
export function fmtWorkEnd(end: string, travelHours: number | null | undefined): string {
  const travel = travelHours ?? 0
  if (travel <= 0) return ''
  return format(new Date(parseISO(end).getTime() - travel * 3_600_000), 'HH:mm')
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

/**
 * עמודת ה-"שעות × תעריף" בפירוט השכר, או null לשורה שאינה מכפלה.
 *
 * הבונוס למשמרת הוא סכום קבוע ומגיע מהשרת עם hours ו-rate שהם null. אילו
 * הוצג לו "0:00 × 0" הוא היה נראה כמו שורה שהחישוב שלה נכשל. שני המסכים
 * שמציירים את ה-lines קוראים לכאן, כדי שלא תהיה ביניהם החלטה כפולה.
 */
export function fmtPayLineRate(hours: number | null, rate: number | null): string | null {
  if (hours == null || rate == null) return null
  return `${fmtDuration(hours)} × ${rate}`
}

/** מטרים לתצוגה קצרה: 240 מ׳ / 3.2 ק״מ */
export function fmtDistance(m: number | null | undefined): string {
  if (m == null) return ''
  return m < 1000 ? `${Math.round(m)} מ׳` : `${(m / 1000).toFixed(1)} ק״מ`
}
