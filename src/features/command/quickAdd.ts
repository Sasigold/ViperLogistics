/**
 * שורת ההוספה המהירה של חדר המלחמה (0227) — מפענח טהור.
 *
 *   "התקנת מצלמות במחסן מחר 10:00 @שמחה !1"
 *
 * מזהה: יום (היום / מחר / מחרתיים / ביום ראשון / בשלישי / בעוד 3 ימים / בעוד
 * שבוע / 14.11 / 14/11/2026), שעה (10:00, בשעה 9), מנהל (@שם — לפי תחילת
 * השם), עדיפות (!1 עד !4) וחזרה (כל יום / כל שבוע / כל חודש). מה שנשאר הוא
 * שם המשימה. בלי יום — היום; בלי שעה — 18:00; יעד שכבר עבר זז ליום הבא.
 *
 * השעות הן שעון המכשיר — המשרד בישראל, וכך גם השרת מציג אותן.
 */
import type { MissionRecurrence } from '../../types/domain'

export interface QuickAddResult {
  title: string
  due: Date
  priority: 1 | 2 | 3 | 4
  ownerId: string | null
  recurrence: MissionRecurrence
  /** מה זוהה, לתצוגה מקדימה: "מחר", "10:00", "@שמחה"… */
  chips: string[]
}

const DAYS = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת']
export const DEFAULT_HOUR = 18

const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate())
const addDays = (d: Date, n: number) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n)

/** תחילית השם של מנהל, בלי תלות ברישיות ובמקף/גרש */
const norm = (s: string) => s.toLowerCase().replace(/[׳'"״-]/g, '').trim()

export function parseQuickAdd(
  input: string,
  now: Date,
  admins: readonly { id: string; full_name: string }[] = [],
): QuickAddResult {
  const words = input.trim().split(/\s+/).filter(Boolean)
  const used = new Set<number>()
  const chips: string[] = []
  let day: Date | null = null
  let hour: number | null = null
  let minute = 0
  let priority: 1 | 2 | 3 | 4 = 2
  let ownerId: string | null = null
  let recurrence: MissionRecurrence = 'none'

  const take = (...idx: number[]) => idx.forEach((i) => used.add(i))

  for (let i = 0; i < words.length; i++) {
    if (used.has(i)) continue
    const w = words[i]
    const next = words[i + 1]

    // עדיפות
    const prio = /^!([1-4])$/.exec(w)
    if (prio) {
      priority = Number(prio[1]) as 1 | 2 | 3 | 4
      chips.push(`P${priority}`)
      take(i)
      continue
    }

    // מנהל
    if (w.startsWith('@') && w.length > 1) {
      const q = norm(w.slice(1))
      const hit = admins.filter((a) => norm(a.full_name).startsWith(q) || norm(a.full_name).split(/\s+/).some((p) => p.startsWith(q)))
      if (hit.length === 1) {
        ownerId = hit[0].id
        chips.push(`@${hit[0].full_name}`)
        take(i)
      }
      continue
    }

    // חזרה
    if (w === 'כל' && next) {
      const rec = ({ יום: 'daily', שבוע: 'weekly', חודש: 'monthly' } as const)[next as 'יום']
      if (rec) {
        recurrence = rec
        chips.push(`כל ${next}`)
        take(i, i + 1)
        continue
      }
    }

    // שעה: 10:00 / ב-10:00 / ב10:30 / בשעה 9
    const clock = /^(?:ב-?)?([01]?\d|2[0-3]):([0-5]\d)$/.exec(w)
    if (clock) {
      hour = Number(clock[1])
      minute = Number(clock[2])
      chips.push(`${clock[1].padStart(2, '0')}:${clock[2]}`)
      take(i)
      continue
    }
    if ((w === 'בשעה' || w === 'שעה') && next && /^([01]?\d|2[0-3])$/.test(next)) {
      hour = Number(next)
      minute = 0
      chips.push(`${next.padStart(2, '0')}:00`)
      take(i, i + 1)
      continue
    }

    // ימים יחסיים
    const rel = ({ היום: 0, מחר: 1, מחרתיים: 2 } as Record<string, number>)[w]
    if (rel !== undefined) {
      day = addDays(now, rel)
      chips.push(w)
      take(i)
      continue
    }
    if (w === 'בעוד' && next) {
      if (next === 'שבוע') {
        day = addDays(now, 7)
        chips.push('בעוד שבוע')
        take(i, i + 1)
        continue
      }
      if (next === 'יומיים') {
        day = addDays(now, 2)
        chips.push('בעוד יומיים')
        take(i, i + 1)
        continue
      }
      const n = Number(next)
      if (Number.isInteger(n) && n > 0 && n < 400 && (words[i + 2] === 'ימים' || words[i + 2] === 'יום')) {
        day = addDays(now, n)
        chips.push(`בעוד ${n} ימים`)
        take(i, i + 1, i + 2)
        continue
      }
    }

    // ימי השבוע: "יום שלישי" / "ביום שלישי" / "בשלישי" — הקרוב שאחרי היום
    if ((w === 'יום' || w === 'ביום') && next && DAYS.includes(next)) {
      day = nextWeekday(now, DAYS.indexOf(next))
      chips.push(`יום ${next}`)
      take(i, i + 1)
      continue
    }
    if (w.startsWith('ב') && DAYS.includes(w.slice(1))) {
      day = nextWeekday(now, DAYS.indexOf(w.slice(1)))
      chips.push(`יום ${w.slice(1)}`)
      take(i)
      continue
    }

    // תאריך: 14.11 / 14/11 / 14.11.26 / 14/11/2026 (גם ב-14.11)
    const date = /^(?:ב-?)?(\d{1,2})[./](\d{1,2})(?:[./](\d{2}|\d{4}))?$/.exec(w)
    if (date) {
      const d = Number(date[1])
      const m = Number(date[2]) - 1
      let y = date[3] ? Number(date[3]) : now.getFullYear()
      if (y < 100) y += 2000
      const cand = new Date(y, m, d)
      if (cand.getMonth() === m && cand.getDate() === d) {
        // בלי שנה ותאריך שעבר — השנה הבאה
        day = !date[3] && cand < startOfDay(now) ? new Date(y + 1, m, d) : cand
        chips.push(`${d}.${m + 1}`)
        take(i)
        continue
      }
    }
  }

  const base = day ?? startOfDay(now)
  let due = new Date(base.getFullYear(), base.getMonth(), base.getDate(), hour ?? DEFAULT_HOUR, minute)
  // יעד שכבר עבר, כשלא נאמר יום — מחר באותה שעה
  if (!day && due <= now) {
    due = addDays(due, 1)
    due.setHours(hour ?? DEFAULT_HOUR, minute)
    chips.push('מחר')
  }

  const title = words
    .filter((_, i) => !used.has(i))
    .join(' ')
    .trim()

  return { title, due, priority, ownerId, recurrence, chips }
}

/** הקרוב שאחרי היום (היום עצמו — בעוד שבוע) */
function nextWeekday(now: Date, dow: number): Date {
  const diff = (dow - now.getDay() + 7) % 7 || 7
  return addDays(now, diff)
}
