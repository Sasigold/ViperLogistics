import { BUCKETS, GROUPS, PACKINGS, SIZES } from './dashboardTypes'
import type {
  Bucket,
  DashboardLayout,
  LayoutItem,
  Packing,
  ViewPrefs,
  WidgetMeta,
  WidgetOpts,
  WidgetSize,
} from './dashboardTypes'
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
  /**
   * KPI tile — two to a row on a phone, three on a tablet, four from `lg` and
   * six on a wide screen.
   *
   * The `lg` step is not cosmetic. Without it a tile spanned four columns from
   * 768px all the way to 1280px, which is exactly what a `md` chart spans — so
   * on a 1024–1279px screen a two-line number stood as wide as a chart, and the
   * KPI row read as a row of half-empty panels.
   */
  sm: 'col-span-6 md:col-span-4 lg:col-span-3 xl:col-span-2',
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

/* ===== packing ============================================================
   Two answers to the same question — what happens to the space a short card
   leaves under itself — and the reason both exist rather than one.

   `aligned` is what the grid has always done: every panel fills its row, so
   the borders line up and the difference between a chart and a two-line list
   becomes card interior instead of page gap. It is the right answer when the
   cards in a row have comparable amounts to say.

   `compact` is the answer when they do not. A month with one event draws a
   trend with one bar, a spend list with one row and six KPI tiles — and
   `aligned` turns each of those into a tall card that is mostly white. Here
   every card stands at its own height and `grid-auto-flow: dense` pulls the
   next card that fits into what is left over.

   Dense packing does move a card forward of its stored position, which is why
   this is a choice and not a fix: `aligned` is order-exact, `compact` is
   hole-free, and which of those matters more is the reader's to say. It sits
   on the view rather than in a preference, so a saved screen keeps it.        */

export const DEFAULT_PACKING: Packing = 'compact'

/** written literally — Tailwind v4 scans source text and would not see a template */
export const PACK_CLASS: Record<Packing, string> = {
  aligned: '',
  compact: '[grid-auto-flow:row_dense]',
}

export function packingOf(view: ViewPrefs | undefined): Packing {
  return view?.packing ?? DEFAULT_PACKING
}

/** plotting height per size; 0 means the body sizes to its content */
export const BODY_H: Record<WidgetSize, number> = { sm: 0, md: 250, lg: 250, xl: 300 }

const TALL_FACTOR = 1.5

export function bodyHeight(size: WidgetSize, h?: 'auto' | 'tall'): number {
  const base = BODY_H[size]
  return h === 'tall' ? Math.round(base * TALL_FACTOR) : base
}

/* A card's header and its body padding, measured off the rendered thing rather
   than guessed: a `CardHeader` with a title and a subtitle is 67px, `CardBody`
   adds 16px top and bottom, and the card's own borders another 2. Charts already
   honour `bodyHeight`, so a chart card stands exactly that much taller than its
   plot — which is what makes the sum the right ceiling for everything else: a
   list that would run to 520px is held to the height of the chart beside it and
   scrolls inside its own body. The few px of slack are deliberate; a ceiling
   that lands a hair under the real chrome puts a scrollbar on every chart. */
const PANEL_CHROME = 104

/**
 * How tall a widget is allowed to grow before its body scrolls.
 *
 * 0 means "no ceiling, size to content" — the KPI tiles, whose whole point is
 * that they are short. Anything with a declared body height gets one, because a
 * single content-driven card is otherwise free to set the height of every card
 * in its row, and that is where the dashboard's gaps came from.
 */
export function panelMaxHeight(size: WidgetSize, h?: 'auto' | 'tall'): number {
  const body = bodyHeight(size, h)
  return body === 0 ? 0 : body + PANEL_CHROME
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
const isPacking = (v: unknown): v is Packing => PACKINGS.includes(v as Packing)
const isBucket = (v: unknown): v is Bucket => BUCKETS.includes(v as Bucket)

/** how many rows a top-N section may be asked for; the server clamps the same way */
export const LIMIT_MIN = 3
export const LIMIT_MAX = 50

/**
 * The whole-screen preferences, from whatever was stored.
 *
 * Every field is optional and every unreadable one is dropped rather than
 * defaulted, so `view` round-trips as "what was actually chosen": an absent
 * `packing` is a layout that never expressed an opinion, which is not the same
 * as one that chose `aligned` and would keep it if the default ever moved.
 */
export function normalizeView(raw: unknown): ViewPrefs | undefined {
  if (!raw || typeof raw !== 'object') return undefined
  const o = raw as Record<string, unknown>
  const out: ViewPrefs = {}
  if (isPacking(o.packing)) out.packing = o.packing
  if (isBucket(o.bucket)) out.bucket = o.bucket
  if (typeof o.limit === 'number' && Number.isFinite(o.limit)) {
    out.limit = Math.round(Math.max(LIMIT_MIN, Math.min(LIMIT_MAX, o.limit)))
  }
  /* Zero is kept, not dropped. It is the difference between "the administrator
     published a five-minute refresh and I have not said otherwise" and "I turned
     it off", and the view inherits per key — so an absent `refresh` would hand
     the company's answer back every time somebody switched it off. */
  if (typeof o.refresh === 'number' && Number.isFinite(o.refresh) && o.refresh >= 0) {
    out.refresh = Math.round(Math.max(0, Math.min(120, o.refresh)))
  }
  const r = o.range
  if (r && typeof r === 'object') {
    const rr = r as Record<string, unknown>
    if (typeof rr.preset === 'string') out.range = { preset: rr.preset }
    else if (typeof rr.from === 'string' && typeof rr.to === 'string') out.range = { from: rr.from, to: rr.to }
  }
  return Object.keys(out).length > 0 ? out : undefined
}

/**
 * A view with one or more preferences changed.
 *
 * A key set back to `undefined` is deleted rather than stored as itself, and an
 * empty result is `undefined` rather than `{}` — the stored layout should carry
 * "what was actually chosen", so that a default which moves later moves for
 * everyone who never expressed an opinion about it.
 */
export function mergeView(view: ViewPrefs | undefined, patch: Partial<ViewPrefs>): ViewPrefs | undefined {
  const next: ViewPrefs = { ...(view ?? {}) }
  for (const [k, v] of Object.entries(patch)) {
    if (v === undefined) delete next[k as keyof ViewPrefs]
    else Object.assign(next, { [k]: v })
  }
  return Object.keys(next).length > 0 ? next : undefined
}

/** a stored options bag, with anything that is not a scalar dropped */
function normalizeOpts(raw: unknown): WidgetOpts | undefined {
  if (!raw || typeof raw !== 'object') return undefined
  const out: WidgetOpts = {}
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
    if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') out[k] = v
  }
  return Object.keys(out).length > 0 ? out : undefined
}

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
    const { id, size, h, opts, lock } = it as LayoutItem
    if (typeof id !== 'string' || taken.has(id)) continue
    taken.add(id)
    const cleanOpts = normalizeOpts(opts)
    items.push({
      id,
      size: isSize(size) ? size : 'md',
      ...(h === 'tall' ? { h } : {}),
      ...(cleanOpts ? { opts: cleanOpts } : {}),
      ...(lock === true ? { lock: true as const } : {}),
    })
  }
  const strings = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : [])
  const view = normalizeView(o.view)
  return { v: 1, items, hidden: strings(o.hidden), seen: strings(o.seen), ...(view ? { view } : {}) }
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

  return applyLocks(insertByGroup(kept, fresh, byId), fallback.items, byId)
}

/* ===== locks ==============================================================
   An administrator publishing a default can mark a placement `lock`. That is
   the one thing on this screen a user does not get the last word on, so it is
   worth being precise about what it does and does not do:

   * It is about **presence**, not shape. The widget is put back on every load
     and its remove button is gone; size, height and options stay the user's.
     "Everyone must see the overdue tasks" is a reasonable instruction, "and
     you must see them as a donut" is not.
   * It cannot show anybody anything they could not already see. Locked or not,
     `visibleItems` still filters by the reader's keys — a lock is a layout
     decision and never a permission one.
   * Only the *fallback* can carry one. A user's own saved layout stores the
     flag as it resolved, and `resolveLayout` re-derives it from the default on
     every load, so un-locking a widget in the published default releases it
     everywhere without anybody having to re-save.                            */

/** ids the published default insists on, in the order it lists them */
export function lockedIds(layout: DashboardLayout | null | undefined): string[] {
  return (layout?.items ?? []).filter((i) => i.lock).map((i) => i.id)
}

/**
 * Put every locked placement back, and take the flag off everything else.
 *
 * The stripping half is what makes the lock releasable: a user who saved while
 * a widget was locked stored `lock: true` in their own row, and without this
 * that copy would outlive the administrator's decision.
 */
export function applyLocks(
  items: readonly LayoutItem[],
  fallbackItems: readonly LayoutItem[],
  byId: Map<string, WidgetMeta>,
): LayoutItem[] {
  const locked = new Set(fallbackItems.filter((i) => i.lock).map((i) => i.id))
  const cleaned = items.map((i) => (locked.has(i.id) ? { ...i, lock: true as const } : stripLock(i)))
  const present = new Set(cleaned.map((i) => i.id))
  const missing = fallbackItems
    .filter((i) => i.lock && !present.has(i.id) && byId.has(i.id))
    .map((i) => ({ ...i, lock: true as const }))
  return missing.length > 0 ? insertByGroup(cleaned, missing, byId) : cleaned
}

function stripLock(i: LayoutItem): LayoutItem {
  if (!i.lock) return i
  const { lock: _drop, ...rest } = i
  return rest
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

/**
 * Write one placement's options.
 *
 * A key set back to its default is dropped rather than stored as itself: the
 * bag is what a *stored layout* carries, and a layout that remembers
 * `form: 'bar'` on a widget whose natural form is bar would keep drawing bars
 * after the widget's own answer moved on.
 */
export function setOpts(items: readonly LayoutItem[], id: string, opts: LayoutItem['opts']): LayoutItem[] {
  const clean = opts && Object.keys(opts).length > 0 ? opts : undefined
  return items.map((i) => {
    if (i.id !== id) return i
    if (!clean) {
      const { opts: _drop, ...rest } = i
      return rest
    }
    return { ...i, opts: clean }
  })
}

/** one key at a time — what the options popover writes on every interaction */
export function setOpt(
  items: readonly LayoutItem[],
  id: string,
  key: string,
  value: string | number | boolean | undefined,
): LayoutItem[] {
  const item = items.find((i) => i.id === id)
  if (!item) return [...items]
  const next = { ...(item.opts ?? {}) }
  if (value === undefined) delete next[key]
  else next[key] = value
  return setOpts(items, id, next)
}

/** an administrator's flag, written only onto a layout about to be published */
export function setLock(items: readonly LayoutItem[], id: string, on: boolean): LayoutItem[] {
  return items.map((i) => (i.id === id ? (on ? { ...i, lock: true as const } : stripLock(i)) : i))
}

/* ===== show / hide ======================================================== */

/**
 * These two take and return the **whole** layout state, unlike every other edit
 * in this file, and the asymmetry is deliberate.
 *
 * They are the only two that change `items` and `hidden` together, so they
 * cannot be written as `(items, id) => items` and be spread into the state by
 * the caller. Returning the two fields they know about — which is what they did
 * until 0151 — makes the caller responsible for carrying everything else
 * forward, and one caller that wrote `edit((s) => hideWidget(s.items, s.hidden,
 * id))` instead of `edit((s) => ({...s, ...hideWidget(...)}))` silently dropped
 * the whole screen's view preferences into the next save. Taking the state
 * makes that mistake unspellable.
 */
export interface LayoutState {
  items: LayoutItem[]
  hidden: string[]
  view?: ViewPrefs
}

export function hideWidget(state: LayoutState, id: string): LayoutState {
  /* A locked placement is the administrator's, and the two ways to remove a
     widget — the frame's ✕ and the catalogue's switch — both land here. Refusing
     in one place is what makes the lock true rather than merely un-clicked. */
  if (state.items.some((i) => i.id === id && i.lock)) return { ...state }
  return {
    ...state,
    items: state.items.filter((i) => i.id !== id),
    hidden: state.hidden.includes(id) ? [...state.hidden] : [...state.hidden, id],
  }
}

export function showWidget(state: LayoutState, meta: WidgetMeta, byId: Map<string, WidgetMeta>): LayoutState {
  const hidden = state.hidden.filter((h) => h !== meta.id)
  if (state.items.some((i) => i.id === meta.id)) return { ...state, items: [...state.items], hidden }
  return {
    ...state,
    items: insertByGroup([...state.items], [{ id: meta.id, size: meta.sizes[0] }], byId),
    hidden,
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
  view?: ViewPrefs,
): DashboardLayout {
  const ids = new Set<string>([...items.map((i) => i.id), ...hidden])
  const cleanView = normalizeView(view)
  return {
    v: 1,
    items: items.map((i) => ({ ...i })),
    hidden: hidden.filter((h) => known.has(h)),
    seen: [...ids].filter((id) => known.has(id)).sort(),
    ...(cleanView ? { view: cleanView } : {}),
  }
}
