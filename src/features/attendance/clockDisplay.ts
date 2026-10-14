/**
 * ערכי תצוגה של מסך השעון — שעון, טבעת, תוויות יום.
 *
 * אין כאן חישוב עסקי: השעות הנספרות, השכר והשער של הכניסה נקבעים בשרת.
 * מה שנגזר כאן הוא רק *איך לצייר* את מה שכבר הגיע — כמה מהטבעת למלא,
 * וכמה זמן נשאר עד שעה שהשרת כבר מסר.
 */
import { addDays, format, isSameDay } from 'date-fns'
import { he } from 'date-fns/locale'

const MIN = 60_000

/** דקות → "H:MM" (שלילי נחשב 0) */
export function fmtHM(minutes: number): string {
  const m = Math.max(0, Math.floor(minutes))
  return `${Math.floor(m / 60)}:${String(m % 60).padStart(2, '0')}`
}

/** דקות שלמות מ-a עד b (ISO או ms); שלילי כש-b לפני a */
export function minutesBetween(a: string | number, b: string | number): number {
  const ta = typeof a === 'number' ? a : new Date(a).getTime()
  const tb = typeof b === 'number' ? b : new Date(b).getTime()
  return (tb - ta) / MIN
}

/**
 * כמה מהטבעת לצבוע: `base` בצבע ההדגשה (שעות בתוך המשמרת המתוכננת) ו-`over`
 * בענבר (הזמן שאחרי הסוף המתוכנן). שניהם שבר מאורך המשמרת המתוכנן, והסכום
 * לא עובר סיבוב אחד.
 */
export function ringArcs(workedMin: number, plannedMin: number, overMin = 0) {
  if (!(plannedMin > 0)) return { base: 0, over: 0 }
  const over = Math.min(Math.max(0, overMin), Math.max(0, workedMin))
  const base = Math.min(1, Math.max(0, workedMin - over) / plannedMin)
  return { base, over: Math.min(1 - base, over / plannedMin) }
}

/**
 * מצב השעות הנוספות מול הסוף המתוכנן: כמה נשאר עד שהן מתחילות, או כמה
 * כבר עברו מאז.
 */
export function overtimeState(nowMs: number, plannedEnd: string | null | undefined) {
  if (!plannedEnd) return null
  const diff = minutesBetween(nowMs, plannedEnd)
  return diff > 0
    ? { kind: 'until' as const, minutes: diff }
    : { kind: 'over' as const, minutes: -diff }
}

/** "היום" / "מחר" / שם היום */
export function dayLabel(iso: string, now: Date = new Date()): string {
  const d = new Date(iso)
  if (isSameDay(d, now)) return 'היום'
  if (isSameDay(d, addDays(now, 1))) return 'מחר'
  return format(d, 'EEEE', { locale: he })
}

/** שורת התאריך בכותרת — "יום רביעי 14.10" */
export function headerDate(now: Date = new Date()): string {
  return format(now, 'EEEE d.M', { locale: he })
}

/** "HH:MM" מקומי, או '—' */
export function clockTime(iso: string | null | undefined): string {
  if (!iso) return '—'
  const d = new Date(iso)
  return isNaN(d.getTime()) ? '—' : format(d, 'HH:mm')
}

/** "12.10" לשורות הממתינות */
export function shortDate(isoDate: string): string {
  const d = new Date(isoDate.length === 10 ? `${isoDate}T12:00:00` : isoDate)
  return isNaN(d.getTime()) ? isoDate : format(d, 'd.M')
}
