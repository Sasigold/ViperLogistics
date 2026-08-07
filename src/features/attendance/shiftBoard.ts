/**
 * הלוגיקה של לוח המשמרות, בלי React.
 *
 * כל ההכרעות שאפשר לענות עליהן בלי DOM יושבות כאן: מה הטווח של "שבוע"
 * ו"3 ימים", איך משמרת נתלית על יום, ומה בדיוק עושה כל מסנן. המסך שמעליהן
 * רק מצייר — וזה מה שמאפשר לבדוק אותן ב-vitest שרץ ב-node.
 */
import { addDays, parseISO, startOfWeek } from 'date-fns'
import { toISODate } from '../../lib/dates'
import type { PlannedShift, ShiftRosterEntry, WorkSite } from '../../types/domain'

/**
 * שני טווחים, ואין אחרים. "שבוע" הוא שבוע קלנדרי (ראשון–שבת) ולא שבעה ימים
 * מהיום, כי לוח שיבוץ נקרא מול לוח השנה של מי שקורא אותו; "3 ימים" דווקא כן
 * מתחיל בעוגן, כי כל תפקידו הוא זום פנימה על מה שקרוב.
 */
export const BOARD_MODES = [
  { key: 'week', label: 'שבוע', days: 7 },
  { key: 'three', label: '3 ימים', days: 3 },
] as const

export type BoardMode = (typeof BOARD_MODES)[number]['key']

export const BOARD_LAYOUTS = [
  { key: 'roster', label: 'עובדים' },
  { key: 'timeline', label: 'ציר שעות' },
] as const

export type BoardLayout = (typeof BOARD_LAYOUTS)[number]['key']

export function boardRange(anchor: Date, mode: BoardMode): { from: string; to: string } {
  if (mode === 'week') {
    const from = startOfWeek(anchor, { weekStartsOn: 0 })
    return { from: toISODate(from), to: toISODate(addDays(from, 6)) }
  }
  return { from: toISODate(anchor), to: toISODate(addDays(anchor, 2)) }
}

/** כמה ימים לדלג כשלוחצים קדימה/אחורה — בדיוק רוחב התצוגה. */
export const boardStep = (mode: BoardMode) => (mode === 'week' ? 7 : 3)

/** הימים שבין from ל-to ועד בכלל, כאובייקטי Date לכותרות העמודות. */
export function boardDays(from: string, to: string): Date[] {
  const start = parseISO(from)
  const end = parseISO(to)
  const out: Date[] = []
  for (let d = start; d <= end; d = addDays(d, 1)) out.push(d)
  return out
}

export const cellKey = (profileId: string, date: string) => `${profileId}|${date}`

/**
 * אינדוקס המשמרות לתאים של הטבלה.
 *
 * המפתח הוא work_date ולא תאריך הסיום: משמרת שמתחילה ב-22:00 ונגמרת ב-02:00
 * שייכת ליום שבו התחילה, וזה גם מה ש-app.planned_shifts מחזיר.
 */
export function indexShifts(shifts: PlannedShift[]): Map<string, PlannedShift[]> {
  const out = new Map<string, PlannedShift[]>()
  for (const s of shifts) {
    const k = cellKey(s.profile_id, s.work_date)
    const hit = out.get(k)
    if (hit) hit.push(s)
    else out.set(k, [s])
  }
  for (const list of out.values()) list.sort((a, b) => a.seq - b.seq)
  return out
}

export interface BoardFilters {
  /** חיפוש חופשי על שם העובד */
  q: string
  employees: string[]
  customer: string
  site: '' | WorkSite
  /** '' = כולם, 'staff' = עובדי החברה בלבד, אחרת מזהה קבלן */
  contractor: string
}

export const emptyBoardFilters: BoardFilters = {
  q: '',
  employees: [],
  customer: '',
  site: '',
  contractor: '',
}

export const BOARD_FILTER_LABELS: Record<keyof BoardFilters, string> = {
  q: 'חיפוש',
  employees: 'עובדים',
  customer: 'לקוח',
  site: 'אתר עבודה',
  contractor: 'קבלן',
}

export const STAFF_ONLY = 'staff'

/**
 * שני סוגי מסננים, ולכן שתי תוצאות.
 *
 * מסנני *שורה* — עובד, חיפוש בשם, קבלן — מחליטים מי בכלל מופיע בלוח.
 * מסנני *משמרת* — לקוח, שטח/מחסן — מחליטים אילו צ׳יפים נשארים. עובד שכל
 * משמרותיו נפלו במסנן השני אינו נעלם: הוא יורד למדף "בלי משמרות", כי
 * "לאף אחד אין משמרת של הלקוח הזה" ו"אין כאן עובדים" הם שתי תשובות שונות.
 */
export function applyBoardFilters(
  roster: ShiftRosterEntry[],
  shifts: PlannedShift[],
  f: BoardFilters,
): { rows: ShiftRosterEntry[]; shifts: PlannedShift[]; empty: ShiftRosterEntry[] } {
  const q = f.q.trim().toLowerCase()
  const picked = new Set(f.employees)

  const candidates = roster.filter((r) => {
    if (picked.size && !picked.has(r.id)) return false
    if (q && !r.full_name.toLowerCase().includes(q)) return false
    if (f.contractor === STAFF_ONLY) return !r.contractor_id
    if (f.contractor && r.contractor_id !== f.contractor) return false
    return true
  })

  const visible = new Set(candidates.map((r) => r.id))
  const kept = shifts.filter((s) => {
    if (!visible.has(s.profile_id)) return false
    if (f.customer && s.customer_id !== f.customer) return false
    if (f.site && s.work_site !== f.site) return false
    return true
  })

  const withShifts = new Set(kept.map((s) => s.profile_id))
  return {
    rows: candidates.filter((r) => withShifts.has(r.id)),
    shifts: kept,
    empty: candidates.filter((r) => !withShifts.has(r.id)),
  }
}

/** שעות מתוכננות ומספר משמרות בטווח, לכל עובד. */
export function rangeTotals(shifts: PlannedShift[]): Map<string, { hours: number; count: number }> {
  const out = new Map<string, { hours: number; count: number }>()
  for (const s of shifts) {
    const hit = out.get(s.profile_id) ?? { hours: 0, count: 0 }
    hit.hours += s.planned_hours ?? 0
    hit.count += 1
    out.set(s.profile_id, hit)
  }
  return out
}

/** כמה מסננים פעילים — למונה שעל כפתור הסינון. */
export function activeBoardFilters(f: BoardFilters): (keyof BoardFilters)[] {
  return (Object.keys(f) as (keyof BoardFilters)[]).filter((k) =>
    k === 'employees' ? f.employees.length > 0 : !!f[k],
  )
}
