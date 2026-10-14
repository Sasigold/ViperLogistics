/**
 * משימות ניהול (0227, 0232) — הלוגיקה הטהורה של המסך: לאיזה נתיב משימה
 * שייכת, איך נקרא זמן עד היעד, ואיך נבנים המדדים והגרפים מהשרת.
 */
import type { Mission, MissionDay } from '../../types/domain'

/* ===== נתיבים ============================================================ */

export type Lane = 'overdue' | 'today' | 'week' | 'later' | 'done'

export const LANES: readonly { key: Lane; label: string }[] = [
  { key: 'overdue', label: 'באיחור' },
  { key: 'today', label: 'היום' },
  { key: 'week', label: 'השבוע' },
  { key: 'later', label: 'בהמשך' },
  { key: 'done', label: 'הושלמו' },
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

/* ===== זמן עד היעד ======================================================= */

const MIN = 60
const HOUR = 3600

/** "40 דק׳", "3 שע׳ 12 דק׳", "יום", "3 ימים" — לכרטיס, בדיוק של דקה */
export function fmtSpan(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds))
  const days = Math.floor(s / 86400)
  const hours = Math.floor((s % 86400) / HOUR)
  const minutes = Math.floor((s % HOUR) / MIN)
  if (days >= 2) return `${days} ימים`
  if (days === 1) return hours ? `יום ו-${hours} שע׳` : 'יום'
  if (hours >= 1) return minutes ? `${hours} שע׳ ${minutes} דק׳` : `${hours} שע׳`
  return `${Math.max(1, minutes)} דק׳`
}

export interface Countdown {
  text: string
  overdue: boolean
  /** פחות משעה ליעד */
  soon: boolean
}

export function countdown(dueIso: string, nowMs: number): Countdown {
  const diff = (Date.parse(dueIso) - nowMs) / 1000
  if (diff < 0) return { text: `באיחור של ${fmtSpan(-diff)}`, overdue: true, soon: false }
  return { text: `בעוד ${fmtSpan(diff)}`, overdue: false, soon: diff < HOUR }
}

/** כמה זמן מאחרת המשימה הוותיקה שבאיחור (שניות); null — אין באיחור */
export function oldestOverdueSeconds(missions: readonly Pick<Mission, 'status' | 'due_at'>[], nowMs: number): number | null {
  let oldest: number | null = null
  for (const m of missions) {
    if (m.status !== 'open') continue
    const due = Date.parse(m.due_at)
    if (due < nowMs && (oldest === null || due < oldest)) oldest = due
  }
  return oldest === null ? null : (nowMs - oldest) / 1000
}

/** אחוז העמידה ביעדים; null — אין משימות שהושלמו בטווח */
export function onTimePct(done: number, onTime: number): number | null {
  return done > 0 ? Math.round((100 * onTime) / done) : null
}

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

const pad = (n: number) => String(n).padStart(2, '0')

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
