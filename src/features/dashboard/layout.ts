import { GROUPS, SIZES } from './dashboardTypes'
import type { DashboardLayout, LayoutItem, WidgetMeta, WidgetSize } from './dashboardTypes'
import type { UserKind } from '../../types/domain'

/* ===== the grid ===========================================================
   Twelve columns. A size token maps to a *literal* class string, never to a
   template — Tailwind v4 scans source text, so `col-span-${n}` would compile
   to nothing and every widget would silently fall back to one column.

   `col-span-N` is `grid-column: span N`, a logical property: the container
   inherits dir="rtl" from <html> and the grid flows right-to-left on its own.
   That is the reason the grid is a grid and not absolute positioning — a
   library that measures in physical pixels would need its indices inverted.  */

export const SPAN: Record<WidgetSize, string> = {
  /** KPI tile — the `grid-cols-2 md:grid-cols-3 xl:grid-cols-6` row, per tile */
  sm: 'col-span-6 md:col-span-4 xl:col-span-2',
  /** a third — what a chart or a task list asks for */
  md: 'col-span-12 lg:col-span-4',
  /** two thirds — the day timeline */
  lg: 'col-span-12 lg:col-span-8',
  xl: 'col-span-12',
}

/**
 * The four widths are today's dashboard vocabulary, not a new one: it already
 * lays KPIs out six to a row and everything else in thirds. Keeping the same
 * fractions is what lets the built-in default reproduce the current screen
 * exactly, so turning the page into widgets changes nothing visible.
 */
export const SIZE_LABELS: Record<WidgetSize, string> = {
  sm: 'קטן',
  md: 'שליש',
  lg: 'שני שליש',
  xl: 'רוחב מלא',
}

/** plotting height per size; 0 means the body sizes to its content */
export const BODY_H: Record<WidgetSize, number> = { sm: 0, md: 250, lg: 250, xl: 300 }

const TALL_FACTOR = 1.5

export function bodyHeight(size: WidgetSize, h?: 'auto' | 'tall'): number {
  const base = BODY_H[size]
  return h === 'tall' ? Math.round(base * TALL_FACTOR) : base
}

/* ===== permissions ========================================================
   The catalogue is filtered by the same answer the server gives. A widget the
   reader holds no key for is not offered, not drawn, and — importantly — not
   deleted from the saved layout: see `visibleItems`.                        */

export function widgetAllowed(
  meta: WidgetMeta,
  has: (key: string) => boolean,
  kind: UserKind | undefined,
): boolean {
  if (meta.kinds && kind && !meta.kinds.includes(kind)) return false
  if (meta.perms?.some((p) => !has(p))) return false
  if (meta.anyPerms?.length && !meta.anyPerms.some((p) => has(p))) return false
  return true
}

/** a stored size the widget no longer offers falls back to its first */
export function clampSize(meta: WidgetMeta, size: WidgetSize | undefined): WidgetSize {
  if (size && meta.sizes.includes(size)) return size
  return meta.sizes[0] ?? 'md'
}

/* ===== reading a stored layout ============================================ */

const isSize = (v: unknown): v is WidgetSize => SIZES.includes(v as WidgetSize)

/**
 * Anything at all → a layout, or null when there is nothing usable in it.
 *
 * The input is jsonb from a table and JSON from localStorage; a layout that
 * throws on parse would take the whole dashboard down with it, which is a poor
 * trade for a view preference.
 */
export function normalizeLayout(raw: unknown): DashboardLayout | null {
  if (!raw || typeof raw !== 'object') return null
  const o = raw as Partial<DashboardLayout>
  if (!Array.isArray(o.items)) return null
  const items: LayoutItem[] = []
  const taken = new Set<string>()
  for (const it of o.items) {
    if (!it || typeof it !== 'object') continue
    const { id, size, h, opts } = it as LayoutItem
    if (typeof id !== 'string' || taken.has(id)) continue
    taken.add(id)
    items.push({
      id,
      size: isSize(size) ? size : 'md',
      ...(h === 'tall' ? { h } : {}),
      ...(opts && typeof opts === 'object' ? { opts } : {}),
    })
  }
  const strings = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : [])
  return { v: 1, items, hidden: strings(o.hidden), seen: strings(o.seen) }
}

export const EMPTY_LAYOUT: DashboardLayout = { v: 1, items: [], hidden: [], seen: [] }

/* ===== the merge ==========================================================
   Called on every load, against a layout that may have been written by an
   older release. Four rules, each closing a real failure:

   1. An id with no definition is dropped. A widget retired in a later release
      must not break a layout saved before it was.
   2. A widget released later appears exactly once, ever — governed by `seen`,
      not by presence in `items`. Keyed off `items` alone, a widget the user
      deliberately removed would come back on every single load.
   3. Only `defaultOn` widgets arrive on their own. Without that, each release
      would shove its new cards into everybody's dashboard.
   4. Permissions are *not* applied here. That happens at render, in
      `visibleItems`, so a key revoked this morning and restored this afternoon
      leaves the widget exactly where it was rather than destroying its slot.  */

export function resolveLayout(
  metas: readonly WidgetMeta[],
  saved: DashboardLayout | null,
  fallback: DashboardLayout,
): LayoutItem[] {
  const base = saved && saved.items.length > 0 ? saved : fallback
  const byId = new Map(metas.map((m) => [m.id, m]))
  const seen = new Set(base.seen.length > 0 ? base.seen : [...base.items.map((i) => i.id), ...base.hidden])
  const hidden = new Set(base.hidden)

  const kept: LayoutItem[] = []
  for (const item of base.items) {
    const meta = byId.get(item.id)
    if (!meta) continue // rule 1
    kept.push({ ...item, size: clampSize(meta, item.size) })
  }

  const fresh = metas
    .filter((m) => m.defaultOn && !seen.has(m.id) && !hidden.has(m.id) && !kept.some((k) => k.id === m.id))
    .map((m) => ({ id: m.id, size: m.sizes[0] }))

  return insertByGroup(kept, fresh, byId)
}

/** a widget that arrives late lands at the tail of its own group, not the page */
export function insertByGroup(
  items: LayoutItem[],
  fresh: LayoutItem[],
  byId: Map<string, WidgetMeta>,
): LayoutItem[] {
  const out = [...items]
  for (const f of fresh) {
    const group = byId.get(f.id)?.group
    let at = out.length
    for (let i = out.length - 1; i >= 0; i--) {
      if (byId.get(out[i].id)?.group === group) {
        at = i + 1
        break
      }
    }
    // no sibling on the page yet — sit next to the groups that come before it
    if (at === out.length && group) {
      const order = GROUPS.indexOf(group)
      const later = out.findIndex((it) => {
        const g = byId.get(it.id)?.group
        return g !== undefined && GROUPS.indexOf(g) > order
      })
      if (later >= 0) at = later
    }
    out.splice(at, 0, f)
  }
  return out
}

/** what actually gets drawn: the merged list minus what the reader may not see */
export function visibleItems(
  items: readonly LayoutItem[],
  byId: Map<string, WidgetMeta>,
  has: (key: string) => boolean,
  kind: UserKind | undefined,
): LayoutItem[] {
  return items.filter((it) => {
    const meta = byId.get(it.id)
    return !!meta && widgetAllowed(meta, has, kind)
  })
}

/* ===== edits ==============================================================
   Everything works in *id* space, never index space. The rendered list is a
   permission-filtered subset of the stored one, so an index from the grid does
   not address the same element as an index into storage — and translating
   between them on every edit is a bug waiting for the first revoked key.     */

/** drop `activeId` where `overId` currently sits — the shape a drag reports */
export function moveByIds(items: readonly LayoutItem[], activeId: string, overId: string): LayoutItem[] {
  if (activeId === overId) return [...items]
  const from = items.findIndex((i) => i.id === activeId)
  const to = items.findIndex((i) => i.id === overId)
  if (from < 0 || to < 0) return [...items]
  const out = [...items]
  const [moved] = out.splice(from, 1)
  out.splice(to, 0, moved)
  return out
}

/**
 * Step one place among the widgets the user can actually see.
 *
 * `offset` is ±1 for the arrows, ±Infinity for "to the top" / "to the end".
 * Stepping through the *visible* neighbours is what makes an arrow move a
 * widget one slot on screen rather than jumping it over something invisible.
 */
export function moveByOffset(
  items: readonly LayoutItem[],
  id: string,
  offset: number,
  visibleIds: readonly string[],
): LayoutItem[] {
  const vi = visibleIds.indexOf(id)
  if (vi < 0) return [...items]
  const target = Math.max(0, Math.min(visibleIds.length - 1, vi + offset))
  if (target === vi) return [...items]
  return moveByIds(items, id, visibleIds[target])
}

export function setSize(items: readonly LayoutItem[], id: string, size: WidgetSize): LayoutItem[] {
  return items.map((i) => (i.id === id ? { ...i, size } : i))
}

export function setHeight(items: readonly LayoutItem[], id: string, h: 'auto' | 'tall'): LayoutItem[] {
  return items.map((i) => (i.id === id ? (h === 'tall' ? { ...i, h } : omitHeight(i)) : i))
}

function omitHeight(i: LayoutItem): LayoutItem {
  const { h: _drop, ...rest } = i
  return rest
}

export function setOpts(items: readonly LayoutItem[], id: string, opts: LayoutItem['opts']): LayoutItem[] {
  return items.map((i) => (i.id === id ? { ...i, opts } : i))
}

/* ===== show / hide ======================================================== */

export function hideWidget(items: readonly LayoutItem[], hidden: readonly string[], id: string) {
  return {
    items: items.filter((i) => i.id !== id),
    hidden: hidden.includes(id) ? [...hidden] : [...hidden, id],
  }
}

export function showWidget(
  items: readonly LayoutItem[],
  hidden: readonly string[],
  meta: WidgetMeta,
  byId: Map<string, WidgetMeta>,
) {
  if (items.some((i) => i.id === meta.id)) return { items: [...items], hidden: hidden.filter((h) => h !== meta.id) }
  return {
    items: insertByGroup([...items], [{ id: meta.id, size: meta.sizes[0] }], byId),
    hidden: hidden.filter((h) => h !== meta.id),
  }
}

/* ===== writing a layout back ==============================================
   `seen` is rebuilt from what exists rather than accumulated, so an id that
   left the registry leaves the memory too and the list cannot grow without
   bound. The accepted cost: a widget removed and re-added later counts as new
   again, which is the right answer anyway.                                   */

export function toStoredLayout(
  items: readonly LayoutItem[],
  hidden: readonly string[],
  known: ReadonlySet<string>,
): DashboardLayout {
  const ids = new Set<string>([...items.map((i) => i.id), ...hidden])
  return {
    v: 1,
    items: items.map((i) => ({ ...i })),
    hidden: hidden.filter((h) => known.has(h)),
    seen: [...ids].filter((id) => known.has(id)).sort(),
  }
}
