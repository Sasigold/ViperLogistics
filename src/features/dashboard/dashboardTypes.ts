import type { ComponentType, ReactNode } from 'react'
import type { UserKind } from '../../types/domain'

/* ===== sizes and groups ===================================================
   Four widths, not five. The two ends are the ones that matter: `sm` is the
   KPI tile that packs six to a row on a wide screen, `xl` is the full-width
   band. `md` and `lg` are what a chart or a table asks for in between.      */

export const SIZES = ['sm', 'md', 'lg', 'xl'] as const
export type WidgetSize = (typeof SIZES)[number]

/* `custom` sits last on purpose: `insertByGroup` places a newly-shown widget
   after the groups that come before it, so a widget somebody built lands at
   the end of the page rather than in the middle of the finance row. */
export const GROUPS = ['finance', 'ops', 'customers', 'people', 'me', 'custom'] as const
export type WidgetGroup = (typeof GROUPS)[number]

export const GROUP_LABELS: Record<WidgetGroup, string> = {
  finance: 'כספים',
  ops: 'תפעול',
  customers: 'לקוחות',
  people: 'כוח אדם',
  me: 'אישי',
  custom: 'ווידג׳טים שנבנו',
}

/* ===== display forms ======================================================
   The same numbers, drawn a different way. Which form a widget is in is a
   *placement* property and not a property of the widget: two people looking at
   the same "revenue by customer" can reasonably want a bar chart and a table,
   and neither of them is wrong.

   The vocabulary is deliberately the builder's (`widgetSpec.ts`) minus the two
   forms that need a spec to mean anything — `gauge` wants a target and
   `number` wants a single row. A hand-written widget declares the subset it
   can honestly draw in `WidgetDef.forms`; declaring `donut` for a time series
   would offer a slice per week, which is a picture of nothing.               */

export const FORMS = ['bar', 'row', 'line', 'area', 'donut', 'table', 'list'] as const
export type WidgetForm = (typeof FORMS)[number]

export const FORM_LABELS: Record<WidgetForm, string> = {
  bar: 'עמודות',
  row: 'עמודות אופקיות',
  line: 'קו',
  area: 'שטח',
  donut: 'טבעת',
  table: 'טבלה',
  list: 'רשימה',
}

/* ===== per-placement options ==============================================
   Declared as data so WidgetFrame can draw the options popover generically.
   A widget that invents its own settings UI is a widget whose settings look
   different from every other widget's.

   Everything here is **client-side**. The one bag of options the server reads
   (`p_opts` — `bucket` and `limit`) is page-level and lives on the view, for a
   reason worth stating: `dashboard_sections` takes one `p_opts` for the whole
   fan-out, so two widgets asking for two different buckets would silently
   agree on whichever one the merge happened to write last. A control that
   quietly changes the card next to it is worse than no control.             */

/**
 * `unsetLabel` and `defaultOn` both answer the same question, and it is the
 * question a generic settings control gets wrong by default: what does *not
 * storing a key* mean?
 *
 * A stored bag should carry choices and not defaults — a widget whose natural
 * answer moves in a later release should follow it — so "the default" is
 * written as an absent key. That only works if the control can say which state
 * is the default. Without `defaultOn`, a switch could only ever store `true`
 * (off wrote "no opinion", which read back as on); without `unsetLabel`, the
 * minimum of a number range and "no limit at all" were the same value, so the
 * minimum was unreachable and the menu misreported the card.
 */
export type OptionSpec =
  | {
      kind: 'number'
      key: string
      label: string
      min: number
      max: number
      step?: number
      hint?: string
      /** what "no value stored" means, e.g. "all rows"; stepping below `min` returns to it */
      unsetLabel?: string
    }
  | { kind: 'enum'; key: string; label: string; choices: { value: string; label: string }[]; hint?: string }
  | { kind: 'bool'; key: string; label: string; hint?: string; defaultOn?: boolean }

export type WidgetOpts = Record<string, string | number | boolean | undefined>

/* ===== the view =========================================================== 
   Everything that is true of the whole screen rather than of one card. It
   travels inside the layout json — a saved view is "my dashboard, as I like
   it", and a packing mode the save forgets is a saved view that comes back
   looking like somebody else's.                                             */

/** how the grid closes the space a short card leaves under itself */
export const PACKINGS = ['aligned', 'compact'] as const
export type Packing = (typeof PACKINGS)[number]

export const PACKING_LABELS: Record<Packing, string> = {
  aligned: 'מיושר',
  compact: 'צפוף',
}

export const BUCKETS = ['day', 'week', 'month'] as const
export type Bucket = (typeof BUCKETS)[number]

export const BUCKET_LABELS: Record<Bucket, string> = {
  day: 'יום',
  week: 'שבוע',
  month: 'חודש',
}

export interface ViewPrefs {
  /**
   * `aligned` is the grid as it has always been: every card fills its row, so
   * the borders line up and a short card is padded from the inside.
   * `compact` lets each card stand at its own height and packs the holes that
   * leaves — which is the answer when half the page has one row of data.
   */
  packing?: Packing
  /** the time bucket every trend on the page is drawn in — one server option */
  bucket?: Bucket
  /** how many rows a top-N section returns; the server clamps it to 1..50 */
  limit?: number
  /** the range the view opens on. A preset re-evaluates on every load. */
  range?: { preset: string } | { from: string; to: string }
  /** minutes between automatic refreshes; absent or 0 means never */
  refresh?: number
}

/* ===== the stored layout ==================================================
   `items` is what you see, in order. `hidden` is what you removed on purpose.
   `seen` is the pair's memory: every id this layout has ever been offered.

   Without `seen` there is no way to tell "a widget released after you last
   saved" from "a widget you deleted" — the first must appear, the second must
   stay gone, and both look identical as "an id that isn't in items".        */

export interface LayoutItem {
  id: string
  size: WidgetSize
  /** taller body, for widgets that declared `resizableHeight` */
  h?: 'auto' | 'tall'
  opts?: WidgetOpts
  /**
   * Set by an administrator on a published default, never by a user on their
   * own layout: the widget is put back on every load and cannot be removed.
   *
   * It is a property of the *placement* rather than of the widget, because
   * "everyone must see the overdue tasks" is a decision about this company and
   * this month — not something `registry.tsx` could ever know.
   */
  lock?: true
}

export interface DashboardLayout {
  v: 1
  items: LayoutItem[]
  hidden: string[]
  seen: string[]
  /** whole-screen preferences; absent means the built-in defaults */
  view?: ViewPrefs
}

/* ===== the widget ========================================================= */

export interface WidgetProps {
  size: WidgetSize
  /** plotting height already resolved from size + h; 0 means "size to content" */
  height: number
  opts: WidgetOpts
}

/**
 * Which form this placement is drawn in.
 *
 * `forms[0]` is the widget's natural one, so a widget that never had its form
 * touched renders exactly as it did before it was offered a choice — and a
 * form saved by a client that offered more than this one still does draws the
 * natural one rather than nothing.
 */
export function widgetForm(def: Pick<WidgetDef, 'forms'>, opts: WidgetOpts | undefined): WidgetForm | undefined {
  const forms = def.forms
  if (!forms?.length) return undefined
  const want = opts?.form
  return typeof want === 'string' && forms.includes(want as WidgetForm) ? (want as WidgetForm) : forms[0]
}

/**
 * The half of a widget that the layout maths needs.
 *
 * Split out from `WidgetDef` so `layout.ts` stays free of React and can be
 * unit-tested against plain objects.
 */
export interface WidgetMeta {
  /** stable forever. Renaming one silently relocates every saved layout. */
  id: string
  group: WidgetGroup
  sizes: readonly WidgetSize[]
  /** appears on its own for users who already have a saved layout */
  defaultOn?: boolean
  /** every key is required */
  perms?: string[]
  /** any one key is enough — for a widget two different roles can justify */
  anyPerms?: string[]
  /** account kinds this widget makes sense for; absent means all */
  kinds?: UserKind[]
}

export interface WidgetDef extends WidgetMeta {
  title: string
  subtitle?: string
  /** one line in the catalogue, explaining what the widget answers */
  description: string
  icon?: ReactNode
  resizableHeight?: boolean
  /** reacts to the page's date range */
  usesRange?: boolean
  /** wants the previous period too, for a delta */
  wantsDelta?: boolean
  /** server sections to request; drives what dashboard_sections is asked for */
  sections?: string[]
  options?: OptionSpec[]
  /**
   * The display forms this widget can draw its own data in, natural one first.
   * Absent means "one form only" — a KPI tile is a number and nothing else.
   */
  forms?: readonly WidgetForm[]
  /**
   * A component, not a `render(ctx)` function like `boardFields.tsx` uses.
   * Board cells are hookless; widgets are almost entirely useQuery, and a
   * render function's hooks would belong to whatever component called it —
   * so swapping which widget sits in a slot would reorder that component's
   * hooks. An element gets its own scope and remounts cleanly.
   */
  Component: ComponentType<WidgetProps>
}
