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

/**
 * שתי דרכים לקרוא את ציר השעות.
 *
 * "מקובץ" הוא ברירת המחדל: כשחמישה אנשים עובדים באותה משמרת, חמישה צ׳יפים
 * זהים זה לצד זה הם קיר שאי אפשר לקרוא ממנו כמה משמרות באמת רצות באותה
 * שעה. "לכל עובד" נשאר כי לפעמים רוצים לראות שורה לכל אדם — למשל כשבודקים
 * מי בדיוק חופף למי.
 */
export const TIMELINE_GROUPINGS = [
  { key: 'grouped', label: 'מקובץ' },
  { key: 'each', label: 'לכל עובד' },
] as const

export type TimelineGrouping = (typeof TIMELINE_GROUPINGS)[number]['key']

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

const ms = (iso: string) => parseISO(iso).getTime()

export interface ShiftGroupMember {
  shift: PlannedShift
  name: string
  /** יוצא מהמחסן, ולכן המשמרת שלו מתחילה מוקדם משל מי שמגיע ישר לשטח */
  fromWarehouse: boolean
}

/** משמרת אחת בציר השעות, עם כל מי שעובד בה. */
export interface ShiftGroup {
  key: string
  /** המשמרת שמייצגת את הקבוצה במגירת הפירוט — של החבר שמתחיל ראשון */
  lead: PlannedShift
  /** ממוינים לפי שעת ההתחלה, ואז לפי שם: יוצאי המחסן פותחים את הרשימה */
  members: ShiftGroupMember[]
  /** החלון שהקבוצה תופסת בציר: מההתחלה המוקדמת ועד הסיום המאוחר */
  start: string
  end: string
  /** תחילת העבודה בשטח — של מי שאינו יוצא מהמחסן. null כשכולם יוצאים ממנו */
  onsiteStart: string | null
  /**
   * סוף העבודה בשטח — הרגע שממנו והלאה נוסעים חזרה למחסן. null כשאיש
   * בקבוצה אינו חוזר לשם, ואז `end` הוא גם סוף העבודה.
   */
  onsiteEnd: string | null
  /** היציאה המוקדמת מהמחסן. null כשאיש בקבוצה אינו מתחיל שם */
  warehouseStart: string | null
  warehouseName: string | null
}

/**
 * מה הופך שתי משמרות לאותה משמרת: אותה קבוצת משימות בדיוק.
 *
 * ולא השעות — דווקא הן מה שמפריד בין מי שיוצא מהמחסן למי שמגיע ישר לשטח,
 * ושניהם עובדים באותה משמרת. app.planned_shifts גוזר את החלון מהמשימות
 * עצמן, ולכן זהות ב-task_ids גוררת גם אותו לקוח, אותה תווית ואותו סיום.
 * משמרת בלי משימות אינה אמורה להתקיים, ובכל זאת יש לה נפילה לאחור לשעות.
 */
const shiftGroupKey = (s: PlannedShift) =>
  s.task_ids?.length
    ? [...s.task_ids].sort().join(',')
    : `${s.shift_start}|${s.shift_end}|${s.label ?? ''}`

const soloKey = (s: PlannedShift) => `${s.profile_id}|${s.work_date}|${s.seq}`

/**
 * מתי נגמרת העבודה עצמה, כשחלק מהקבוצה עוד נוסע אחריה חזרה למחסן.
 *
 * ‏`shift_end` של מי שיצא מהמחסן כולל את הנסיעה חזרה, ו-`travel_hours` הוא
 * בדיוק אותה נסיעה — לו, ו-0 למי שהגיע ישירות לשטח וסיים בשטח (0079 §4).
 * חיסור אחד מחזיר את השעה שבה יורדים מהעבודה, וזו השעה שהפס התחתון בצ׳יפ
 * מתחיל בה.
 *
 * הגדול מבין החברים ולא הקטן: בקבוצה כולם חולקים את אותן משימות, ולכן זהו
 * אותו רגע לכולם — והמקסימום הוא מה ששומר על הפס בתוך החלון גם כשמשמרת
 * חריגה נכנסה לקבוצה בטעות.
 */
function onsiteEnd(members: ShiftGroupMember[]): string | null {
  let latest: number | null = null
  for (const m of members) {
    const travel = m.shift.travel_hours ?? 0
    if (travel <= 0) continue
    const at = ms(m.shift.shift_end) - travel * 3_600_000
    if (latest === null || at > latest) latest = at
  }
  return latest === null ? null : new Date(latest).toISOString()
}

/**
 * המשמרות של כולם, מקובצות לפי מי עובד באותה משמרת.
 *
 * במצב 'each' כל משמרת היא קבוצה של אחד — אותו מבנה נתונים בדיוק, כדי
 * שהמסך יצייר ויפתח מגירה בענף אחד ולא בשניים.
 */
export function groupShifts(
  shifts: PlannedShift[],
  nameById: Map<string, string>,
  grouping: TimelineGrouping = 'grouped',
): ShiftGroup[] {
  const buckets = new Map<string, ShiftGroupMember[]>()
  for (const s of shifts) {
    const key = grouping === 'each' ? soloKey(s) : shiftGroupKey(s)
    const member: ShiftGroupMember = {
      shift: s,
      name: nameById.get(s.profile_id) ?? '',
      fromWarehouse: s.work_site === 'warehouse',
    }
    const hit = buckets.get(key)
    if (hit) hit.push(member)
    else buckets.set(key, [member])
  }

  const groups: ShiftGroup[] = []
  for (const [key, members] of buckets) {
    members.sort(
      (a, b) =>
        ms(a.shift.shift_start) - ms(b.shift.shift_start) || a.name.localeCompare(b.name, 'he'),
    )
    // אחרי המיון הראשון בכל תת-רשימה הוא המוקדם שבה
    const wh = members.filter((m) => m.fromWarehouse)
    const field = members.filter((m) => !m.fromWarehouse)
    groups.push({
      key,
      lead: members[0].shift,
      members,
      start: members[0].shift.shift_start,
      end: members.reduce(
        (max, m) => (ms(m.shift.shift_end) > ms(max) ? m.shift.shift_end : max),
        members[0].shift.shift_end,
      ),
      onsiteStart: field[0]?.shift.shift_start ?? null,
      onsiteEnd: onsiteEnd(members),
      warehouseStart: wh[0]?.shift.shift_start ?? null,
      warehouseName: wh.find((m) => m.shift.warehouse_name)?.shift.warehouse_name ?? null,
    })
  }
  groups.sort((a, b) => ms(a.start) - ms(b.start) || a.key.localeCompare(b.key))
  return groups
}

/**
 * הפס המקווקו בראש הצ׳יפ נגמר בדיוק בשעה שבה מתחילה העבודה בשטח, ולכן
 * גובהו הוא חלקה של הנסיעה מהמחסן מתוך כל החלון.
 *
 * 0 כשאין בקבוצה גם יוצא-מחסן וגם מי שמגיע ישר לשטח: בלי שניהם אין מול מה
 * למדוד את הנסיעה, ומשמרת שכולה יוצאת מהמחסן מסומנת בתג ולא בפס. חסום
 * ב-60% כי מעבר לזה הפס בולע את שמות העובדים שמתחתיו.
 */
export const MAX_LEAD_PCT = 60

export function warehouseLeadPct(g: ShiftGroup): number {
  if (!g.onsiteStart || !g.warehouseStart) return 0
  const span = ms(g.end) - ms(g.start)
  const lead = ms(g.onsiteStart) - ms(g.start)
  if (span <= 0 || lead <= 0) return 0
  return Math.min(MAX_LEAD_PCT, (lead / span) * 100)
}

/**
 * והפס התחתון: הנסיעה חזרה למחסן, מסוף העבודה ועד סוף המשמרת.
 *
 * הוא אינו תלוי בהרכב הקבוצה, בשונה מהעליון: הנסיעה חזרה נמדדת מהמשמרת
 * עצמה (`travel_hours`) ולא מהפרש בין שני אנשים, ולכן גם משמרת שכולה יוצאת
 * מהמחסן — זו שאין לה פס עליון — מקבלת פס תחתון. זה בדיוק הפער שדווח: שעת
 * הסיום שבצ׳יפ כללה מאז ומתמיד את הנסיעה, ושום דבר בו לא אמר זאת.
 */
export function warehouseReturnPct(g: ShiftGroup): number {
  if (!g.onsiteEnd) return 0
  const span = ms(g.end) - ms(g.start)
  const tail = ms(g.end) - ms(g.onsiteEnd)
  if (span <= 0 || tail <= 0) return 0
  return Math.min(MAX_LEAD_PCT, (tail / span) * 100)
}

/**
 * שני הפסים יחד, אחרי שמוודאים שנשאר גוף לצ׳יפ.
 *
 * כל אחד מהם כבר חסום ב-MAX_LEAD_PCT בנפרד, אבל משמרת קצרה עם נסיעה ארוכה
 * לשני הכיוונים יכולה להגיע ל-120% ולמחוק את שמות העובדים שביניהם. כשהסכום
 * חורג, שניהם מצטמצמים באותו יחס — כך שהיחס *ביניהם* נשמר, וזה מה שהעין
 * קוראת מהצ׳יפ.
 */
export function warehouseBands(g: ShiftGroup): { lead: number; tail: number } {
  const lead = warehouseLeadPct(g)
  const tail = warehouseReturnPct(g)
  const total = lead + tail
  if (total <= MAX_LEAD_PCT) return { lead, tail }
  const k = MAX_LEAD_PCT / total
  return { lead: lead * k, tail: tail * k }
}

/** כמה מסננים פעילים — למונה שעל כפתור הסינון. */
export function activeBoardFilters(f: BoardFilters): (keyof BoardFilters)[] {
  return (Object.keys(f) as (keyof BoardFilters)[]).filter((k) =>
    k === 'employees' ? f.employees.length > 0 : !!f[k],
  )
}
