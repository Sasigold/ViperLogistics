import type { WorkBoardRow } from '../../types/domain'

/* ── colour-coded groups ───────────────────────────────────────────────────
   Every task that belongs to the same event is painted with the same hue, so
   an event that spans a setup on Sunday and a teardown on Tuesday reads as one
   thing at a glance. A task with no event is neutral — it belongs to nobody.

   Hue alone is never the whole signal: each group also carries a running
   number, so the board stays readable for anyone who can't separate the
   colours, and so two groups that happen to land on the same palette slot can
   still be told apart.                                                      */

export type ColorBy = 'event' | 'customer' | 'none'

export const COLOR_BY_OPTIONS: { key: ColorBy; label: string }[] = [
  { key: 'event', label: 'אירוע' },
  { key: 'customer', label: 'לקוח' },
  { key: 'none', label: 'ללא' },
]

/** matches the --vl-ev-* ramp declared in index.css */
const PALETTE_SIZE = 12

export interface GroupTone {
  /** 1-based running number of the group within the loaded range */
  index: number
  /** the hue itself — a palette variable, or the customer's own colour */
  solid: string
  /** wash for a task column's body */
  tint: string
  /** wash for headers and the group band */
  tintStrong: string
  /** the group's outer edge */
  border: string
}

function makeTone(index: number, color?: string | null): GroupTone {
  const solid = color || `var(--vl-ev-${(index - 1) % PALETTE_SIZE})`
  return {
    index,
    solid,
    /* the strength of each wash lives in CSS (`--vl-tone-*` in index.css), so
       the board darkens or lightens from one place and dark mode can hold its
       own numbers without a second code path here */
    tint: `color-mix(in srgb, ${solid} var(--vl-tone-tint), transparent)`,
    tintStrong: `color-mix(in srgb, ${solid} var(--vl-tone-tint-strong), transparent)`,
    border: `color-mix(in srgb, ${solid} var(--vl-tone-border), transparent)`,
  }
}

/** the identity a row is grouped by, or null when the row stands alone */
export function groupKeyOf(row: WorkBoardRow, colorBy: ColorBy): string | null {
  if (colorBy === 'event') return row.event_id ? `e:${row.event_id}` : null
  if (colorBy === 'customer') return row.customer_id ? `c:${row.customer_id}` : null
  return null
}

/** the key a row is clustered by — solo rows cluster with themselves only */
export function clusterKeyOf(row: WorkBoardRow, colorBy: ColorBy): string {
  return groupKeyOf(row, colorBy) ?? `solo:${row.id}`
}

export function groupLabelOf(row: WorkBoardRow, colorBy: ColorBy): string {
  if (colorBy === 'customer') return row.customer_name ?? 'ללא לקוח'
  if (row.event_number) return `#${row.event_number}`
  return row.end_client_name ?? row.title ?? 'אירוע'
}

/**
 * Assigns a tone per group across the whole loaded range — colours must not
 * change from day to day, so the map is built once from rows in date order and
 * every day's layout reads from it.
 */
export function buildTones(rows: WorkBoardRow[], colorBy: ColorBy): Map<string, GroupTone> {
  const tones = new Map<string, GroupTone>()
  if (colorBy === 'none') return tones
  for (const row of rows) {
    const key = groupKeyOf(row, colorBy)
    if (!key || tones.has(key)) continue
    tones.set(key, makeTone(tones.size + 1, colorBy === 'customer' ? row.customer_color : null))
  }
  return tones
}

export interface Cluster {
  /** unique within the day — one event can appear as more than one run when
   *  another event's task falls between two of its own */
  key: string
  /** the identity every run of the same group shares, for colour and hover */
  groupKey: string
  label: string
  tone: GroupTone | null
  rows: WorkBoardRow[]
}

/**
 * Lays one day's tasks out in the order the reader asked for — by start time on
 * site unless they chose otherwise — and then gathers *consecutive* rows of the
 * same event into a run.
 *
 * The order comes first on purpose: a schedule is read down the clock, and
 * grouping the whole event together used to move a 18:00 teardown up beside its
 * own 06:00 setup, ahead of everything that actually happens in between. The
 * hue still ties the event together wherever its tasks land.
 */
export function clusterDay(
  rows: WorkBoardRow[],
  colorBy: ColorBy,
  tones: Map<string, GroupTone>,
  cmp: (a: WorkBoardRow, b: WorkBoardRow) => number,
): Cluster[] {
  const runs: Cluster[] = []
  for (const row of [...rows].sort(cmp)) {
    const groupKey = clusterKeyOf(row, colorBy)
    const last = runs[runs.length - 1]
    if (last && last.groupKey === groupKey) {
      last.rows.push(row)
      continue
    }
    runs.push({
      key: `${groupKey}#${runs.length}`,
      groupKey,
      label: groupLabelOf(row, colorBy),
      tone: tones.get(groupKey) ?? null,
      rows: [row],
    })
  }
  return runs
}
