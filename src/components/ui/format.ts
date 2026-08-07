/**
 * Display-only formatters. Data formatting that the app already had lives in
 * `src/lib/dates.ts`; these are presentation helpers the design system adds
 * (relative timestamps, compact counts) and are deliberately kept out of the
 * data layer.
 */

const RTF = new Intl.RelativeTimeFormat('he', { numeric: 'auto' })

const UNITS: [Intl.RelativeTimeFormatUnit, number][] = [
  ['year', 365 * 24 * 3600],
  ['month', 30 * 24 * 3600],
  ['week', 7 * 24 * 3600],
  ['day', 24 * 3600],
  ['hour', 3600],
  ['minute', 60],
]

/** "לפני 5 דקות" / "מחר" — falls back to '' for empty input. */
export function fmtRelative(value: string | Date | null | undefined): string {
  if (!value) return ''
  const date = typeof value === 'string' ? new Date(value) : value
  if (Number.isNaN(date.getTime())) return ''
  const diff = (date.getTime() - Date.now()) / 1000
  const abs = Math.abs(diff)
  if (abs < 45) return 'ממש עכשיו'
  for (const [unit, secs] of UNITS) {
    if (abs >= secs) return RTF.format(Math.round(diff / secs), unit)
  }
  return RTF.format(Math.round(diff / 60), 'minute')
}

/** Whole-day distance, ignoring clock time — for task dates. */
export function daysFromToday(isoDate: string): number {
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const [y, m, d] = isoDate.slice(0, 10).split('-').map(Number)
  const target = new Date(y, (m ?? 1) - 1, d ?? 1)
  return Math.round((target.getTime() - today.getTime()) / 86_400_000)
}

/** "היום" / "מחר" / "אתמול", otherwise null so the caller can use a date. */
export function relativeDayLabel(isoDate: string): string | null {
  const d = daysFromToday(isoDate)
  if (d === 0) return 'היום'
  if (d === 1) return 'מחר'
  if (d === -1) return 'אתמול'
  return null
}

const ILS = new Intl.NumberFormat('he-IL', {
  style: 'currency',
  currency: 'ILS',
  maximumFractionDigits: 2,
  minimumFractionDigits: 0,
})

/** 5616 -> "‏5,616 ₪". Empty string for null, so callers can render it raw. */
export function fmtMoney(value: number | string | null | undefined): string {
  if (value === null || value === undefined || value === '') return ''
  const n = typeof value === 'string' ? Number(value) : value
  return Number.isFinite(n) ? ILS.format(n) : ''
}

/** 9.5 -> "9.5 ש׳", 9 -> "9 ש׳". Trailing zeros are noise on an hours count. */
export function fmtHoursShort(value: number | string | null | undefined): string {
  if (value === null || value === undefined || value === '') return ''
  const n = typeof value === 'string' ? Number(value) : value
  if (!Number.isFinite(n)) return ''
  return `${Number(n.toFixed(2))} ש׳`
}

/** 12500 -> "12.5K"; keeps stat tiles from wrapping. */
export function compactNumber(n: number): string {
  return new Intl.NumberFormat('he-IL', { notation: 'compact', maximumFractionDigits: 1 }).format(n)
}

/** Percentage change vs a previous value; null when there is no baseline. */
export function pctDelta(current: number, previous: number): number | null {
  if (!Number.isFinite(current) || !Number.isFinite(previous) || previous === 0) return null
  return Math.round(((current - previous) / previous) * 100)
}
