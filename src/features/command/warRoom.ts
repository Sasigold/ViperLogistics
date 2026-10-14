/**
 * חדר המלחמה (0227) — הלוגיקה הטהורה של המסך.
 *
 * המספרים עצמם (רמת האיום, החוב, הנקודות, הרצף) מגיעים מהשרת. מה שכאן הוא
 * איך מציגים אותם: לאיזה נתיב משימה שייכת, איך נקראת ספירה לאחור, איזו דרגה
 * שווה כמה XP, ומה אומר הדף בכל רמת איום.
 */
import type { Mission, MissionDay } from '../../types/domain'

/* ===== נתיבים ============================================================ */

export type Lane = 'overdue' | 'today' | 'week' | 'later' | 'done'

export const LANES: readonly { key: Lane; label: string }[] = [
  { key: 'overdue', label: 'באיחור' },
  { key: 'today', label: 'היום' },
  { key: 'week', label: 'השבוע' },
  { key: 'later', label: 'בהמשך' },
  { key: 'done', label: 'בוצע' },
]

const dayStart = (ms: number) => {
  const d = new Date(ms)
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
}
const DAY = 86_400_000

export function laneOf(m: Pick<Mission, 'status' | 'due_at'>, nowMs: number): Lane {
  if (m.status === 'done') return 'done'
  const due = Date.parse(m.due_at)
  if (due < nowMs) return 'overdue'
  const today = dayStart(nowMs)
  if (due < today + DAY) return 'today'
  if (due < today + 7 * DAY) return 'week'
  return 'later'
}

/** כל נתיב ממוין: באיחור — הוותיקה ראשונה; בוצע — האחרונה ראשונה; השאר — היעד הקרוב, ואז עדיפות. */
export function groupByLane(missions: readonly Mission[], nowMs: number): Record<Lane, Mission[]> {
  const out: Record<Lane, Mission[]> = { overdue: [], today: [], week: [], later: [], done: [] }
  for (const m of missions) out[laneOf(m, nowMs)].push(m)
  const byDue = (a: Mission, b: Mission) => Date.parse(a.due_at) - Date.parse(b.due_at) || a.priority - b.priority
  out.overdue.sort(byDue)
  out.today.sort(byDue)
  out.week.sort(byDue)
  out.later.sort(byDue)
  out.done.sort((a, b) => Date.parse(b.done_at ?? b.due_at) - Date.parse(a.done_at ?? a.due_at))
  return out
}

/* ===== ספירה לאחור ======================================================= */

export interface Span {
  days: number
  hours: number
  minutes: number
  seconds: number
}

export function splitSeconds(total: number): Span {
  const s = Math.max(0, Math.floor(total))
  return {
    days: Math.floor(s / 86400),
    hours: Math.floor((s % 86400) / 3600),
    minutes: Math.floor((s % 3600) / 60),
    seconds: s % 60,
  }
}

const pad = (n: number) => String(n).padStart(2, '0')

/** "2 ימים 4 שע׳", "3:12:05", "12 דק׳" — קצר, לכרטיס */
export function fmtSpan(seconds: number): string {
  const { days, hours, minutes, seconds: s } = splitSeconds(seconds)
  if (days >= 1) return `${days === 1 ? 'יום' : `${days} ימים`}${hours ? ` ${hours} שע׳` : ''}`
  if (hours >= 1) return `${hours}:${pad(minutes)}:${pad(s)}`
  return `${minutes}:${pad(s)}`
}

export interface Countdown {
  text: string
  overdue: boolean
  /** פחות משעה ליעד */
  urgent: boolean
}

export function countdown(dueIso: string, nowMs: number): Countdown {
  const diff = (Date.parse(dueIso) - nowMs) / 1000
  if (diff < 0) return { text: `באיחור ${fmtSpan(-diff)}`, overdue: true, urgent: false }
  return { text: `עוד ${fmtSpan(diff)}`, overdue: false, urgent: diff < 3600 }
}

/** שעון החוב: "3 ימים 04:12:55" */
export function fmtDebt(seconds: number): string {
  const { days, hours, minutes, seconds: s } = splitSeconds(seconds)
  const clock = `${pad(hours)}:${pad(minutes)}:${pad(s)}`
  if (days === 0) return clock
  return `${days === 1 ? 'יום' : `${days} ימים`} ${clock}`
}

/**
 * החוב עכשיו, משעון השרת: מה שהשרת ספר ברגע הקריאה, ועוד הזמן שעבר מאז
 * כפול מספר המשימות שבאיחור — כל אחת מוסיפה שנייה בכל שנייה.
 */
export function liveDebt(board: { debt_seconds: number; overdue: number }, elapsedMs: number): number {
  return board.debt_seconds + (board.overdue * Math.max(0, elapsedMs)) / 1000
}

/* ===== רמת האיום ========================================================= */

export type Defcon = 1 | 2 | 3 | 4 | 5

export interface DefconLook {
  name: string
  /** צבע הסרגל והכותרת */
  color: string
  /** משפטים שהדף אומר ברמה הזו */
  lines: readonly string[]
}

export const DEFCON: Record<Defcon, DefconLook> = {
  5: {
    name: 'שליטה מלאה',
    color: '#10b981',
    lines: ['השולחן נקי. ככה נראית שליטה.', 'אין איחורים. תמשיך ככה — זה בדיוק המצב.', 'אפס חוב. המכונה עובדת.'],
  },
  4: {
    name: 'ערנות',
    color: '#eab308',
    lines: ['יש משימות שהיעד שלהן היום. היום, לא מחר.', 'היום עוד לא נגמר — אבל הוא כן ייגמר.', 'סגור את של היום לפני שהן מאדימות.'],
  },
  3: {
    name: 'אזהרה',
    color: '#f97316',
    lines: ['משהו כבר מאחר. זה מתחיל ככה.', 'משימה אחת באיחור היא חריגה. שתיים הן הרגל.', 'השעון לא מחכה. גם המשימה לא.'],
  },
  2: {
    name: 'סכנה',
    color: '#ef4444',
    lines: ['המשימות מצטברות. כל שעה שעוברת נספרת.', 'החוב גדל בזמן שאתה קורא את זה.', 'זה כבר לא "אחר כך". זה עכשיו.'],
  },
  1: {
    name: 'קריסה',
    color: '#dc2626',
    lines: ['⛔ המשימות לא שוכחות. גם אתה לא.', '⛔ המצלמות לא יתקינו את עצמן.', '⛔ כל דקה כאן היא דקה שהעסק חשוף.'],
  },
}

/** משפט יציב לאורך הביקור — מתחלף רק כשהמצב משתנה */
export function defconLine(level: Defcon, seed: number): string {
  const lines = DEFCON[level].lines
  return lines[Math.abs(Math.floor(seed)) % lines.length]
}

/* ===== דרגות ============================================================= */

export const LEVELS: readonly { title: string; xp: number }[] = [
  { title: 'טירון', xp: 0 },
  { title: 'מבצעי', xp: 300 },
  { title: 'מפקד', xp: 1000 },
  { title: 'אלוף', xp: 2500 },
  { title: 'מכונה', xp: 5000 },
  { title: 'אגדה', xp: 10000 },
]

export interface LevelInfo {
  index: number
  title: string
  /** הדרגה הבאה, אם יש */
  next: { title: string; xp: number } | null
  /** 0..1 בדרך לדרגה הבאה */
  progress: number
}

export function levelOf(xp: number): LevelInfo {
  let index = 0
  for (let i = 0; i < LEVELS.length; i++) if (xp >= LEVELS[i].xp) index = i
  const cur = LEVELS[index]
  const next = LEVELS[index + 1] ?? null
  const progress = next ? Math.min(1, Math.max(0, (xp - cur.xp) / (next.xp - cur.xp))) : 1
  return { index, title: cur.title, next, progress }
}

/* ===== הישגים ============================================================ */

export const ACHIEVEMENTS: readonly { key: string; emoji: string; label: string; hint: string }[] = [
  { key: 'first_blood', emoji: '🩸', label: 'דם ראשון', hint: 'המשימה הראשונה שבוצעה' },
  { key: 'on_time_10', emoji: '🎯', label: 'צלף', hint: '10 משימות בזמן' },
  { key: 'early_bird_10', emoji: '🐦', label: 'ציפור מוקדמת', hint: '10 משימות יום ומעלה לפני היעד' },
  { key: 'five_in_a_day', emoji: '⚡', label: 'יום מטורף', hint: '5 משימות ביום אחד' },
  { key: 'inbox_zero', emoji: '🧘', label: 'Inbox Zero', hint: 'אף משימה פתוחה' },
  { key: 'no_snooze_20', emoji: '🚫', label: 'בלי נודניק', hint: '20 משימות ברצף בלי לדחות' },
  { key: 'streak_7', emoji: '🔥', label: 'שבוע נקי', hint: '7 ימים רצופים בלי איחור' },
  { key: 'streak_30', emoji: '🌋', label: 'חודש נקי', hint: '30 ימים רצופים בלי איחור' },
  { key: 'century', emoji: '💯', label: 'מאה', hint: '100 משימות שבוצעו' },
]

export const achievementOf = (key: string) => ACHIEVEMENTS.find((a) => a.key === key)

/* ===== עדיפות וחזרה ====================================================== */

export const PRIORITIES: readonly { value: 1 | 2 | 3 | 4; label: string; color: string }[] = [
  { value: 1, label: 'P1 · קריטי', color: '#dc2626' },
  { value: 2, label: 'P2 · גבוה', color: '#f97316' },
  { value: 3, label: 'P3 · רגיל', color: '#3563f0' },
  { value: 4, label: 'P4 · נמוך', color: '#667085' },
]

export const RECURRENCE_LABELS = {
  none: 'חד-פעמית',
  daily: 'כל יום',
  weekly: 'כל שבוע',
  monthly: 'כל חודש',
} as const

/** הנקודות שהמשימה שווה אם תיסגר עכשיו — בבואה של `app.mission_points`, לתצוגה בלבד. */
export function pointsIfDoneNow(m: Pick<Mission, 'priority' | 'due_at' | 'postpone_count'>, nowMs: number): number {
  const base = ({ 1: 100, 2: 60, 3: 40, 4: 25 } as const)[m.priority]
  const due = Date.parse(m.due_at)
  let pts: number
  if (nowMs <= due - DAY) pts = Math.round(base * 1.5)
  else if (nowMs <= due) pts = base
  else pts = Math.round(base * 0.5 * Math.max(0, 1 - (nowMs - due) / (72 * 3600_000)))
  return Math.max(0, pts - 10 * m.postpone_count)
}

/** Date → ערך של `datetime-local` בשעון המכשיר */
export const toLocalInput = (d: Date) =>
  `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`

/* ===== גרפים ============================================================= */

/** אחוז בזמן לפי שבוע (ראשון–שבת), מהסדרה היומית */
export function weeklyOnTime(daily: readonly MissionDay[]): { week: string; done: number; pct: number | null }[] {
  const weeks = new Map<string, { done: number; onTime: number }>()
  for (const d of daily) {
    const dt = new Date(`${d.day}T00:00:00`)
    const start = new Date(dt.getFullYear(), dt.getMonth(), dt.getDate() - dt.getDay())
    const key = `${start.getFullYear()}-${String(start.getMonth() + 1).padStart(2, '0')}-${String(start.getDate()).padStart(2, '0')}`
    const w = weeks.get(key) ?? { done: 0, onTime: 0 }
    w.done += d.done
    w.onTime += d.on_time
    weeks.set(key, w)
  }
  return [...weeks.entries()].map(([week, w]) => ({
    week,
    done: w.done,
    pct: w.done ? Math.round((100 * w.onTime) / w.done) : null,
  }))
}

/** עוצמת תא במפת החום: 0 (כלום) עד 4 */
export function heatLevel(done: number): 0 | 1 | 2 | 3 | 4 {
  if (done <= 0) return 0
  if (done === 1) return 1
  if (done <= 3) return 2
  if (done <= 5) return 3
  return 4
}
