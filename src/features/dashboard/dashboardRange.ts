import { addDays, differenceInCalendarDays, endOfMonth, startOfMonth, startOfWeek, subDays } from 'date-fns'
import { toISODate } from '../../lib/dates'

export interface DateRange {
  from: string
  to: string
}

/**
 * The same span, immediately before the selected one.
 *
 * This is what every "vs. previous period" delta on the dashboard compares
 * against, and it needs no new server surface — the same RPC is simply asked
 * about a different window. The two ranges never touch: a month ending on the
 * 31st is preceded by the window ending on the 30th of the month before.
 */
export function previousRange({ from, to }: DateRange): DateRange {
  const span = Math.max(0, differenceInCalendarDays(new Date(to), new Date(from)))
  const prevTo = subDays(new Date(from), 1)
  return { from: toISODate(subDays(prevTo, span)), to: toISODate(prevTo) }
}

/** the three shortcuts above the date fields */
export const RANGE_PRESETS: { label: string; range: () => DateRange }[] = [
  {
    label: 'השבוע',
    range: () => {
      const s = startOfWeek(new Date(), { weekStartsOn: 0 })
      return { from: toISODate(s), to: toISODate(addDays(s, 6)) }
    },
  },
  {
    label: 'החודש',
    range: () => ({ from: toISODate(startOfMonth(new Date())), to: toISODate(endOfMonth(new Date())) }),
  },
  {
    label: '30 ימים',
    range: () => ({ from: toISODate(subDays(new Date(), 29)), to: toISODate(new Date()) }),
  },
]

export function defaultRange(): DateRange {
  return { from: toISODate(startOfMonth(new Date())), to: toISODate(endOfMonth(new Date())) }
}
