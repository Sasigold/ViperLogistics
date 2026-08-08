import type { ComponentType, ReactNode } from 'react'
import type { UserKind } from '../../types/domain'

/* ===== sizes and groups ===================================================
   Four widths, not five. The two ends are the ones that matter: `sm` is the
   KPI tile that packs six to a row on a wide screen, `xl` is the full-width
   band. `md` and `lg` are what a chart or a table asks for in between.      */

export const SIZES = ['sm', 'md', 'lg', 'xl'] as const
export type WidgetSize = (typeof SIZES)[number]

export const GROUPS = ['finance', 'ops', 'customers', 'people', 'me'] as const
export type WidgetGroup = (typeof GROUPS)[number]

export const GROUP_LABELS: Record<WidgetGroup, string> = {
  finance: 'כספים',
  ops: 'תפעול',
  customers: 'לקוחות',
  people: 'כוח אדם',
  me: 'אישי',
}

/* ===== per-placement options ==============================================
   Declared as data so WidgetFrame can draw the options popover generically.
   A widget that invents its own settings UI is a widget whose settings look
   different from every other widget's.                                     */

export type OptionSpec =
  | { kind: 'number'; key: string; label: string; min: number; max: number; step?: number }
  | { kind: 'enum'; key: string; label: string; choices: { value: string; label: string }[] }
  | { kind: 'bool'; key: string; label: string }

export type WidgetOpts = Record<string, string | number | boolean | undefined>

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
}

export interface DashboardLayout {
  v: 1
  items: LayoutItem[]
  hidden: string[]
  seen: string[]
}

/* ===== the widget ========================================================= */

export interface WidgetProps {
  size: WidgetSize
  /** plotting height already resolved from size + h; 0 means "size to content" */
  height: number
  opts: WidgetOpts
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
   * A component, not a `render(ctx)` function like `boardFields.tsx` uses.
   * Board cells are hookless; widgets are almost entirely useQuery, and a
   * render function's hooks would belong to whatever component called it —
   * so swapping which widget sits in a slot would reorder that component's
   * hooks. An element gets its own scope and remounts cleanly.
   */
  Component: ComponentType<WidgetProps>
}
