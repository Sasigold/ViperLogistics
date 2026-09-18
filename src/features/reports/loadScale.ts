/**
 * הלוגיקה של מפת העומסים, בלי React.
 *
 * השרת מחזיר **ספירות** — כמה עובדים, כמה משאיות, כמה ראשי צוות רצים באותו
 * רגע — ואת התקרה. ההמרה של השניים ל"כמה אחוז עמוס" ולשם הצוואר יושבת כאן
 * ולא בשרת, משתי סיבות: היא נחוצה גם על היום, גם על השעה וגם על התא במפה,
 * והיא ההכרעה הכי סבירה להשתנות. כאן היא גם נבדקת ב-vitest שרץ ב-node.
 *
 * המידה היא **המרבי מבין הממדים ולא ממוצע שלהם**. יום שבו כל העובדים פנויים
 * אבל אין ראש צוות שלישי הוא יום סגור, וממוצע היה מדלל אותו ל-40% ומראה
 * ירוק. לכן `bottleneck` נוסע לצד המספר: "87%" בלי "ממה" אינו מידע שאפשר
 * לפעול לפיו.
 */
import { addDays, getDay, startOfMonth } from 'date-fns'
import { toISODate } from '../../lib/dates'
import type { LoadCapacity, LoadDay, LoadDimension, LoadHour } from '../../types/domain'

/**
 * שלושת הממדים, ולצד כל אחד שדה התקרה שלו.
 *
 * הסדר הוא סדר ההכרעה בתיקו, ולכן הוא אינו שרירותי: כשעובדים ומשאיות
 * נוגעים באותו יחס, "עובדים" הוא מה שנאמר — הוא הממד שקשה יותר להשיג
 * בהתראה קצרה.
 */
export const LOAD_DIMENSIONS: {
  key: LoadDimension
  label: string
  /** הכותרת כשהיא נאמרת כצוואר בקבוק ולא כשם עמודה */
  bottleneckLabel: string
  capacityKey: keyof Pick<LoadCapacity, 'workers' | 'trucks' | 'team_leads'>
}[] = [
  { key: 'workers', label: 'עובדים', bottleneckLabel: 'כוח אדם', capacityKey: 'workers' },
  { key: 'leads', label: 'ראשי צוות', bottleneckLabel: 'ראשי צוות', capacityKey: 'team_leads' },
  { key: 'trucks', label: 'משאיות', bottleneckLabel: 'משאיות', capacityKey: 'trucks' },
]

export interface LoadCounts {
  workers: number
  trucks: number
  leads: number
}

export interface LoadScore {
  /** ‏0 ומעלה. יכול לעבור 100 — וזו כל התועלת שבו */
  pct: number
  /** הממד שקבע את המספר. null כשאין עומס כלל, או כשאין אף תקרה */
  bottleneck: LoadDimension | null
}

/**
 * אחוז אחד, ולצדו הממד שקבע אותו.
 *
 * תקרה שהיא אפס או חסרה **מדלגת על הממד** ואינה מחזירה אינסוף: מאגר שלא
 * הוגדרה לו תקרה אינו מאגר שנגמר, והצגת "∞%" הייתה הופכת את כל החודש לאדום
 * בגלל שדה ריק בהגדרות.
 */
export function loadScore(counts: LoadCounts, capacity: LoadCapacity | undefined): LoadScore {
  if (!capacity) return { pct: 0, bottleneck: null }
  let pct = 0
  let bottleneck: LoadDimension | null = null
  for (const d of LOAD_DIMENSIONS) {
    const cap = Number(capacity[d.capacityKey] ?? 0)
    if (!(cap > 0)) continue
    const ratio = (counts[d.key] / cap) * 100
    if (ratio > pct) {
      pct = ratio
      bottleneck = d.key
    }
  }
  return { pct: Math.round(pct), bottleneck: pct > 0 ? bottleneck : null }
}

/**
 * הפסגה של יום, בצורה ש-`loadScore` מקבל.
 *
 * ‏`peak_trucks` ו-`peak_leads` הם מעכשיו **הדרישה** ולא מה ששובץ (0181):
 * העומס הוא מה שצריך לסדר, ולא מה שכבר סודר. מה ששובץ נוסע לצדם ומוצג
 * כ"שובץ מתוך נדרש", אבל אינו נכנס לאחוז.
 */
export const dayCounts = (d: LoadDay): LoadCounts => ({
  workers: d.peak_workers,
  trucks: d.peak_trucks,
  leads: d.peak_leads,
})

/** ושל שעה. */
export const hourCounts = (h: LoadHour): LoadCounts => ({
  workers: h.workers,
  trucks: h.trucks,
  leads: h.leads,
})

/**
 * חמש מדרגות, ולא רצף.
 *
 * תא במפה נקרא במבט ולא בקריאה, ולכן הוא צריך מספר מצומצם של מצבים שאפשר
 * להבחין ביניהם בלי להשוות זה לזה. הגבול היחיד שהוא **סמנטי** ולא ויזואלי
 * הוא 100: מתחתיו זו עוד עבודה, מעליו זו עבודה שאין מי שיעשה.
 */
export const LOAD_BANDS = [
  { key: 'idle',   label: 'ריק',      max: 0 },
  { key: 'light',  label: 'נינוח',    max: 40 },
  { key: 'normal', label: 'תקין',     max: 70 },
  { key: 'busy',   label: 'עמוס',     max: 90 },
  { key: 'high',   label: 'כמעט מלא', max: 100 },
  { key: 'over',   label: 'מעל הקיבולת', max: Infinity },
] as const

export type LoadBand = (typeof LOAD_BANDS)[number]['key']

export function loadBand(pct: number): LoadBand {
  for (const b of LOAD_BANDS) if (pct <= b.max) return b.key
  return 'over'
}

/* ‏18% ל-92% על פני ארבע המדרגות. הרצפה אינה 0: תא של 5% חייב להיראות שונה
   מתא ריק, אחרת "יום עם משימה אחת" ו"יום בלי כלום" הם אותו תא. */
const BAND_STEP: Record<'light' | 'normal' | 'busy' | 'high', number> = {
  light: 18,
  normal: 42,
  busy: 66,
  high: 92,
}

/**
 * הצבע של תא.
 *
 * סקאלה **סדרתית בגוון אחד** — כחול המותג, מבהיר לכהה — כי המידה היא עוצמה
 * ולא זהות. החריג היחיד הוא `over`, שאינו "עוד קצת" אלא מצב אחר: הוא לובש
 * את צבע השגיאה של המערכת, ובמסך הוא נושא גם סימן ולא רק גוון — צבע לבדו
 * אינו מידע למי שאינו מבחין בו.
 *
 * הערכים הם `color-mix` על טוקנים ולא hex קשיח, ולכן הם נכונים גם ב-dark
 * mode בלי סקאלה שנייה.
 */
export function loadPaint(pct: number): { background: string; color: string; border: string } {
  const band = loadBand(pct)
  if (band === 'idle') {
    return {
      background: 'var(--color-subtle)',
      color: 'var(--color-ink-tertiary)',
      border: 'var(--color-line-subtle)',
    }
  }
  if (band === 'over') {
    return {
      background: 'color-mix(in srgb, var(--color-error) 88%, transparent)',
      color: '#ffffff',
      border: 'var(--color-error)',
    }
  }
  const step = BAND_STEP[band]
  return {
    background: `color-mix(in srgb, var(--color-primary) ${step}%, transparent)`,
    color: step >= 60 ? '#ffffff' : 'var(--color-ink)',
    border: `color-mix(in srgb, var(--color-primary) ${Math.min(step + 14, 100)}%, transparent)`,
  }
}

/**
 * החודש כרשת של שבועות.
 *
 * שבוע מתחיל בראשון, כמו בכל לוח אחר במערכת, והתאים שלפני הראשון בחודש
 * ואחרי האחרון בו הם `null` — ולא ימים של החודש השכן. מפה חודשית שגולשת
 * לחודש אחר היא מפה שאי אפשר לסכם, כי הכותרת שלה מבטיחה חודש.
 */
export function monthGrid(month: Date, days: LoadDay[]): (LoadDay | null)[][] {
  const byDay = new Map(days.map((d) => [d.day, d]))
  const first = startOfMonth(month)
  const lead = getDay(first)
  const cells: (LoadDay | null)[] = Array.from({ length: lead }, () => null)

  for (let d = first; d.getMonth() === first.getMonth(); d = addDays(d, 1)) {
    /* יום שאין לו שורה מהשרת הוא יום ריק ולא חור ברשת: השרת מחזיר שורה לכל
       יום בטווח, אבל הרשת נבנית מהחודש ולא מהטווח, ושני הקצוות שלהם
       יכולים לא להיפגש. */
    cells.push(byDay.get(toISODate(d)) ?? emptyDay(toISODate(d)))
  }
  while (cells.length % 7 !== 0) cells.push(null)

  const weeks: (LoadDay | null)[][] = []
  for (let i = 0; i < cells.length; i += 7) weeks.push(cells.slice(i, i + 7))
  return weeks
}

export function emptyDay(day: string): LoadDay {
  return {
    day,
    tasks: 0,
    timed: 0,
    untimed: 0,
    worker_need: 0,
    staffed: 0,
    gap: 0,
    lead_need: 0,
    lead_staffed: 0,
    truck_need: 0,
    truck_assigned: 0,
    worker_hours: 0,
    delegated: 0,
    customers: 0,
    sites: 0,
    peak_hour: null,
    peak_tasks: 0,
    peak_workers: 0,
    peak_trucks: 0,
    peak_trucks_assigned: 0,
    peak_leads: 0,
    peak_leads_staffed: 0,
    peak_sites: 0,
    peak_warehouses: 0,
    busy_hours: 0,
  }
}

export interface MonthSummary {
  /** ימים שיש בהם עבודה כלשהי — המכנה של כל השאר */
  activeDays: number
  /** ימים שהפסגה שלהם עברה את התקרה */
  overDays: number
  /** היום העמוס ביותר בחודש, ואחוזו. null כשאין עבודה בכלל */
  busiest: { day: LoadDay; score: LoadScore } | null
  /** ממוצע הפסגות של הימים הפעילים בלבד — ימי מנוחה אינם מדללים אותו */
  avgPeakPct: number
  /** סך התקנים שעוד לא אוישו בחודש */
  gap: number
  /** ‏"שובץ מתוך נדרש" על החודש כולו — שלושת הממדים, כל אחד כזוג (0181) */
  need: { workers: number; leads: number; trucks: number }
  staffed: { workers: number; leads: number; trucks: number }
  totalTasks: number
  /** מתוך `totalTasks`, אלה שיש להן שעה */
  timed: number
  /** משימות בלי שעה — מה שהמפה אינה יכולה למקם, אבל כן סופרת */
  untimed: number
  delegated: number
  /** הממד שהיה הצוואר ברוב הימים הפעילים */
  topBottleneck: LoadDimension | null
}

export function monthSummary(days: LoadDay[], capacity: LoadCapacity | undefined): MonthSummary {
  const counts: Record<string, number> = {}
  let activeDays = 0
  let overDays = 0
  let pctSum = 0
  let busiest: MonthSummary['busiest'] = null

  for (const d of days) {
    const score = loadScore(dayCounts(d), capacity)
    if (d.tasks === 0 && d.untimed === 0) continue
    activeDays++
    pctSum += score.pct
    if (score.pct > 100) overDays++
    if (score.bottleneck) counts[score.bottleneck] = (counts[score.bottleneck] ?? 0) + 1
    /* תיקו נשבר לטובת המוקדם: כששני ימים באותו אחוז, זה שקרוב יותר הוא זה
       שאפשר עוד לעשות בו משהו. */
    if (!busiest || score.pct > busiest.score.pct) busiest = { day: d, score }
  }

  const top = LOAD_DIMENSIONS.map((d) => d.key).reduce<LoadDimension | null>(
    (best, k) => ((counts[k] ?? 0) > (best ? (counts[best] ?? 0) : 0) ? k : best),
    null,
  )

  return {
    activeDays,
    overDays,
    busiest,
    avgPeakPct: activeDays ? Math.round(pctSum / activeDays) : 0,
    gap: days.reduce((s, d) => s + d.gap, 0),
    need: {
      workers: days.reduce((s, d) => s + d.worker_need, 0),
      leads: days.reduce((s, d) => s + d.lead_need, 0),
      trucks: days.reduce((s, d) => s + d.truck_need, 0),
    },
    staffed: {
      workers: days.reduce((s, d) => s + d.staffed, 0),
      leads: days.reduce((s, d) => s + d.lead_staffed, 0),
      trucks: days.reduce((s, d) => s + d.truck_assigned, 0),
    },
    totalTasks: days.reduce((s, d) => s + d.tasks, 0),
    timed: days.reduce((s, d) => s + d.timed, 0),
    untimed: days.reduce((s, d) => s + d.untimed, 0),
    delegated: days.reduce((s, d) => s + d.delegated, 0),
    topBottleneck: top,
  }
}

/**
 * הקטע של היממה ששווה לצייר.
 *
 * עשרים וארבע עמודות שמתוכן שש-עשרה ריקות הן גרף שהנתונים בו דחוסים לפינה.
 * החיתוך הוא לשעות שיש בהן משהו, ועוד שעה לכל צד כדי שהעמודה הראשונה לא
 * תיצמד לציר. יום ריק מקבל את חלון העבודה המקובל ולא חלון באורך אפס.
 */
export function hourExtent(hours: LoadHour[]): { from: number; to: number } {
  const busy = hours.filter((h) => h.tasks > 0).map((h) => h.hour)
  if (busy.length === 0) return { from: 6, to: 20 }
  return { from: Math.max(0, Math.min(...busy) - 1), to: Math.min(23, Math.max(...busy) + 1) }
}

/**
 * השעה העמוסה ביותר ביום, לפי אותה מידה של התא במפה.
 *
 * ‏`peak_hour` מהשרת עונה על אותה שאלה, אבל הוא נמדד מול התקרה **כפי שהייתה
 * בשעת הקריאה**; כאן הוא מחושב מאותן שעות שהמסך מצייר, ולכן המספר בכותרת
 * והעמודה הגבוהה בגרף אינם יכולים להיפרד.
 */
export function busiestHour(
  hours: LoadHour[],
  capacity: LoadCapacity | undefined,
): { hour: LoadHour; score: LoadScore } | null {
  let best: { hour: LoadHour; score: LoadScore } | null = null
  for (const h of hours) {
    if (h.tasks === 0) continue
    const score = loadScore(hourCounts(h), capacity)
    if (!best || score.pct > best.score.pct) best = { hour: h, score }
  }
  return best
}

/** ‏"09:00" מתוך 9 — השעה כפי שהיא נקראת על ציר ובכותרת. */
export const hourLabel = (h: number) => `${String(h).padStart(2, '0')}:00`

/**
 * אותה סקאלה, בצורה שאפשר לצבוע בה סימן ב-SVG.
 *
 * ‏`loadPaint` בונה `color-mix(...)`, וזה בסדר גמור ב-CSS אבל אינו הדרך שבה
 * שאר הגרפים במערכת צובעים `Cell` — שם הערך הוא צבע יחיד. ‏`color-mix` מול
 * ‏`transparent` הוא ממילא הרכבת אלפא, ולכן אותו מראה בדיוק מתקבל מצבע
 * הטוקן ועוד שקיפות — בלי לסמוך על פרשנות של `color-mix` בתוך תכונת SVG.
 */
export function loadMark(pct: number): { fill: string; opacity: number } {
  const band = loadBand(pct)
  if (band === 'idle') return { fill: 'var(--vl-border)', opacity: 1 }
  if (band === 'over') return { fill: 'var(--vl-error)', opacity: 0.88 }
  return { fill: 'var(--vl-primary)', opacity: BAND_STEP[band] / 100 }
}
