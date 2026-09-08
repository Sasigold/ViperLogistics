import type { OptionSpec, WidgetForm, WidgetOpts } from './dashboardTypes'
import { widgetForm } from './dashboardTypes'

/**
 * The arithmetic behind a series card, with no React in it.
 *
 * Split out from `parts/SeriesCard.tsx` for the reason `layout.ts` is split
 * out of the grid: which rows a card shows, in what order, drawn how tall, is
 * the part that decides how much of the screen ends up empty — and that
 * deserves to be pinned down by a test rather than eyeballed in a browser.
 */

export interface SeriesRow {
  /** stable identity — also what `onSelect` gets handed */
  key: string
  label: string
  value: number
  /** the entity's own colour, when it has one */
  color?: string
  /** a second line in the list and table forms */
  hint?: string
}

/* ===== the options every series widget offers =============================
   Declared once and spread into the widget's `options`, so "show top 5" means
   the same thing and sits in the same place on every card that has it.      */

export const TOP_OPTION: OptionSpec = {
  kind: 'number',
  key: 'top',
  label: 'כמה שורות',
  min: 3,
  max: 20,
  /* Unset is "everything the server sent", not three. Saying so is what makes
     three reachable — stepping below the minimum returns here. */
  unsetLabel: 'הכול',
  hint: 'מתוך מה שכבר נטען — בלי פנייה נוספת לשרת',
}

export const SORT_OPTION: OptionSpec = {
  kind: 'enum',
  key: 'sort',
  label: 'סדר',
  choices: [
    { value: 'natural', label: 'כפי שהתקבל' },
    { value: 'desc', label: 'מהגדול לקטן' },
    { value: 'asc', label: 'מהקטן לגדול' },
  ],
}

export const VALUES_OPTION: OptionSpec = {
  kind: 'bool',
  key: 'values',
  label: 'הצגת המספרים',
  hint: 'בטבלה וברשימה',
  /* On is the default, so *off* is the opinion worth storing — `SeriesCard`
     reads `opts.values !== false`, and without this the switch could only ever
     write the value that changes nothing. */
  defaultOn: true,
}

/** what a categorical series offers; a time series drops the sort, which would scramble it */
export const SERIES_OPTIONS: OptionSpec[] = [TOP_OPTION, SORT_OPTION, VALUES_OPTION]
export const TREND_OPTIONS: OptionSpec[] = [TOP_OPTION, VALUES_OPTION]

/* ===== the three vocabularies =============================================
   Declared here rather than spelled out per widget so that the registry entry
   and the component cannot drift: the entry offers exactly the forms the
   component knows how to draw, and `forms[0]` is what the widget looked like
   before anybody was offered a choice.

   `donut` is absent from `TREND_FORMS` on purpose — a slice per week is a
   picture of nothing. `line` and `area` are absent from the categorical ones
   for the mirror reason: joining "furniture" to "logistics" with a line
   asserts a progression between two categories that have no order.          */

/** counted categories — customers, statuses, task types */
export const CATEGORY_FORMS = ['bar', 'row', 'donut', 'table', 'list'] as const

/** a ranking whose labels are names, so the horizontal bar comes first */
export const RANK_FORMS = ['row', 'bar', 'donut', 'table', 'list'] as const

/** a value over time */
export const TREND_FORMS = ['bar', 'line', 'area', 'table', 'list'] as const

/* ===== reading the options ================================================ */

/** the form this placement asked for, or the widget's natural one */
export function pickForm(forms: readonly WidgetForm[], opts: WidgetOpts): WidgetForm {
  return widgetForm({ forms }, opts) ?? forms[0]
}

/**
 * Sort and slice, in that order.
 *
 * Slicing after sorting is what makes "top 5" mean the five biggest rather
 * than the first five the server happened to return; slicing a time series —
 * which never sorts — keeps the most recent buckets, because the tail of a
 * trend is the part anybody is looking at.
 */
export function applySeriesOpts(rows: SeriesRow[], opts: WidgetOpts, timeAxis?: boolean): SeriesRow[] {
  const sort = opts.sort
  let out = rows
  if (!timeAxis && (sort === 'desc' || sort === 'asc')) {
    out = [...rows].sort((a, b) => (sort === 'desc' ? b.value - a.value : a.value - b.value))
  }
  const top = typeof opts.top === 'number' ? opts.top : undefined
  if (top && out.length > top) out = timeAxis ? out.slice(out.length - top) : out.slice(0, top)
  return out
}

/**
 * How tall the plot actually needs to be.
 *
 * The frame hands down one number per size, and for a full chart that is the
 * right one. For a horizontal ranking of two rows it is not: eighteen pixels of
 * bar and two hundred of air is the picture the reader was complaining about.
 * So a `row` chart is measured in rows, and every other form keeps the height
 * it was given — a bar chart with two bars is short and wide, which is fine,
 * while a bar chart squeezed to 90px is unreadable.
 *
 * Arithmetic that decides how much of the screen ends up empty, so it lives
 * here with the rest of it and has a test.
 */
export function plotHeight(form: WidgetForm, count: number, given: number): number {
  if (form !== 'row') return given
  const needed = count * 30 + 40
  return Math.max(120, Math.min(given, needed))
}
