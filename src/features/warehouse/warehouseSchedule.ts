import type { WarehouseScheduleRow, WarehouseTaskKind } from '../../types/domain'

/**
 * לו״ז המחסן (0196) — מה שאינו תלוי ב-React, ולכן נבדק לבדו.
 */

export const KIND_LABEL: Record<WarehouseTaskKind, string> = {
  prep: 'הכנה',
  return: 'החזרה',
}

/**
 * צבע הכותרת של כל סוג. קבוע ולא מהפלטה של האירועים: הפלטה צובעת את גוף
 * העמודה לפי האירוע, והכותרת צריכה לומר דבר אחר — הכנה או החזרה — במבט אחד.
 * לבן עליהם קריא בשני המצבים, ולכן אין להם גרסה כהה.
 */
export const KIND_COLOR: Record<WarehouseTaskKind, string> = {
  prep: '#1d3fd8',
  return: '#e8692e',
}

/** matches the --vl-ev-* ramp declared in index.css */
const PALETTE_SIZE = 12

/**
 * גוון לכל אירוע, קבוע לאורך הטווח: ההכנה ביום ראשון וההחזרה ביום שלישי
 * צבועות באותו צבע, כמו ההקמה והפירוק בלו״ז העבודה.
 */
export function eventTones(rows: WarehouseScheduleRow[]): Map<string, string> {
  const tones = new Map<string, string>()
  for (const r of rows) {
    if (tones.has(r.event_id)) continue
    const solid = `var(--vl-ev-${tones.size % PALETTE_SIZE})`
    tones.set(r.event_id, `color-mix(in srgb, ${solid} var(--vl-tone-tint-strong), transparent)`)
  }
  return tones
}

export interface WarehouseDay {
  date: string
  rows: WarehouseScheduleRow[]
}

/** השעה, ובלעדיה לסוף היום; הכנה לפני החזרה; ואז מספר התעודה. */
export function byWarehouseTime(a: WarehouseScheduleRow, b: WarehouseScheduleRow): number {
  const at = a.start_time ?? '99:99'
  const bt = b.start_time ?? '99:99'
  if (at !== bt) return at.localeCompare(bt)
  if (a.kind !== b.kind) return a.kind === 'prep' ? -1 : 1
  return (a.event_number ?? '').localeCompare(b.event_number ?? '', 'he', { numeric: true })
}

/** הימים שיש בהם משהו, לפי הסדר, וכל יום ממוין לפי השעה. */
export function groupByDay(rows: WarehouseScheduleRow[]): WarehouseDay[] {
  const map = new Map<string, WarehouseScheduleRow[]>()
  for (const r of rows) {
    const list = map.get(r.task_date)
    if (list) list.push(r)
    else map.set(r.task_date, [r])
  }
  return [...map.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([date, list]) => ({ date, rows: [...list].sort(byWarehouseTime) }))
}

export const rowKey = (r: Pick<WarehouseScheduleRow, 'event_id' | 'kind'>) => `${r.event_id}:${r.kind}`

/** מה שהשרת מקבל ב-`p_patch` — רק השדות שהמסך כותב. */
export type WarehousePatch = Partial<
  Pick<WarehouseScheduleRow, 'start_time' | 'duration_hours' | 'notes' | 'final_approved' | 'event_ready' | 'checked'>
> & {
  /** null = חזרה ליום הנגזר */
  task_date?: string | null
}

/**
 * העדכון האופטימי: אותה שורה עם השינוי, ותאריך שנוקה חוזר לנגזר — שאותו
 * רק השרת יודע, ולכן הוא נשאר עד שהשאילתה חוזרת.
 */
export function applyPatch(row: WarehouseScheduleRow, patch: WarehousePatch): WarehouseScheduleRow {
  const { task_date, ...rest } = patch
  const next = { ...row, ...rest }
  if ('task_date' in patch) {
    next.date_is_manual = task_date != null
    next.task_date = task_date ?? row.task_date
  }
  return next
}
