import { describe, expect, it } from 'vitest'
import { SIZES } from './dashboardTypes'
import type { DashboardLayout, LayoutItem, WidgetMeta } from './dashboardTypes'
import {
  BODY_H,
  SPAN,
  bodyHeight,
  clampSize,
  hideWidget,
  moveByIds,
  moveByOffset,
  normalizeLayout,
  panelMaxHeight,
  resolveLayout,
  setSize,
  showWidget,
  toStoredLayout,
  visibleItems,
  widgetAllowed,
} from './layout'

/* A miniature registry: two ops widgets, one finance widget behind a key, and
   one that ships later in the suite to stand in for "a future release". */
const META: WidgetMeta[] = [
  { id: 'ops.a', group: 'ops', sizes: ['sm', 'md'], defaultOn: true },
  { id: 'ops.b', group: 'ops', sizes: ['md', 'lg'], defaultOn: true },
  { id: 'finance.money', group: 'finance', sizes: ['sm'], defaultOn: true, perms: ['pricing.revenue'] },
  { id: 'me.optin', group: 'me', sizes: ['md'] }, // defaultOn is absent on purpose
]
const byId = new Map(META.map((m) => [m.id, m]))
const known = new Set(META.map((m) => m.id))
const allowAll = () => true

const layout = (items: LayoutItem[], hidden: string[] = [], seen: string[] = []): DashboardLayout => ({
  v: 1,
  items,
  hidden,
  seen,
})

/** a layout that has already been offered everything — isolates one rule at a time */
const caughtUp = (items: LayoutItem[], hidden: string[] = []) =>
  layout(items, hidden, META.map((m) => m.id))

/* The built-in default lists every `defaultOn` widget. That is an invariant,
   not a coincidence: a defaultOn widget missing from it would be re-added by
   the merge on every load for users who have nothing saved. */
const FALLBACK = layout(
  [
    { id: 'ops.a', size: 'sm' },
    { id: 'ops.b', size: 'md' },
    { id: 'finance.money', size: 'sm' },
  ],
  [],
  ['ops.a', 'ops.b', 'finance.money'],
)

describe('grid tokens', () => {
  /* Tailwind v4 scans source text. A span built with a template literal
     compiles to no class at all, and every widget quietly becomes one column
     wide — so the map must hold whole literal strings. */
  it('names every size, as literal class strings', () => {
    for (const size of SIZES) {
      expect(SPAN[size]).toBeTypeOf('string')
      expect(SPAN[size]).toMatch(/col-span-\d+/)
      expect(SPAN[size]).not.toContain('${')
      expect(BODY_H[size]).toBeTypeOf('number')
    }
  })

  it('a tall widget gets a taller body, and an auto one is unchanged', () => {
    expect(bodyHeight('md')).toBe(BODY_H.md)
    expect(bodyHeight('md', 'auto')).toBe(BODY_H.md)
    expect(bodyHeight('md', 'tall')).toBeGreaterThan(BODY_H.md)
    // `sm` sizes to its content, and 1.5 × nothing is still nothing
    expect(bodyHeight('sm', 'tall')).toBe(0)
  })

  it('every panel has a height ceiling, and the KPI tile has none', () => {
    // 0 is what the frame reads as "size to content" — a KPI tile is short on
    // purpose and must not be stretched to a chart's height
    expect(panelMaxHeight('sm')).toBe(0)
    expect(panelMaxHeight('sm', 'tall')).toBe(0)

    for (const size of ['md', 'lg', 'xl'] as const) {
      // the ceiling has to clear the body it is meant to hold, or a chart at
      // its declared height would scroll inside its own card
      expect(panelMaxHeight(size)).toBeGreaterThan(bodyHeight(size))
    }
  })

  it('the taller body raises the ceiling with it', () => {
    expect(panelMaxHeight('md', 'tall')).toBeGreaterThan(panelMaxHeight('md'))
    // same chrome either way — the difference is exactly the extra body
    expect(panelMaxHeight('md', 'tall') - panelMaxHeight('md')).toBe(
      bodyHeight('md', 'tall') - bodyHeight('md'),
    )
  })
})

describe('clampSize', () => {
  it('keeps a size the widget offers', () => {
    expect(clampSize(byId.get('ops.a')!, 'md')).toBe('md')
  })

  it('falls back to the first when the stored size is no longer offered', () => {
    expect(clampSize(byId.get('ops.a')!, 'xl')).toBe('sm')
    expect(clampSize(byId.get('ops.b')!, undefined)).toBe('md')
  })
})

describe('widgetAllowed', () => {
  it('requires every key in perms', () => {
    const meta = byId.get('finance.money')!
    expect(widgetAllowed(meta, () => false, 'staff')).toBe(false)
    expect(widgetAllowed(meta, (k) => k === 'pricing.revenue', 'staff')).toBe(true)
  })

  it('accepts any one key in anyPerms', () => {
    const meta: WidgetMeta = { id: 'x', group: 'ops', sizes: ['md'], anyPerms: ['a', 'b'] }
    expect(widgetAllowed(meta, (k) => k === 'b', 'staff')).toBe(true)
    expect(widgetAllowed(meta, () => false, 'staff')).toBe(false)
  })

  it('honours the account kinds a widget declares', () => {
    const meta: WidgetMeta = { id: 'x', group: 'ops', sizes: ['md'], kinds: ['staff'] }
    expect(widgetAllowed(meta, allowAll, 'staff')).toBe(true)
    expect(widgetAllowed(meta, allowAll, 'customer_user')).toBe(false)
  })
})

describe('normalizeLayout', () => {
  it('reads a well-formed layout', () => {
    const out = normalizeLayout({ v: 1, items: [{ id: 'ops.a', size: 'sm' }], hidden: ['x'], seen: ['ops.a'] })
    expect(out?.items).toEqual([{ id: 'ops.a', size: 'sm' }])
    expect(out?.hidden).toEqual(['x'])
  })

  it('returns null for junk rather than throwing', () => {
    expect(normalizeLayout(null)).toBeNull()
    expect(normalizeLayout('nonsense')).toBeNull()
    expect(normalizeLayout({})).toBeNull()
    expect(normalizeLayout({ items: 'no' })).toBeNull()
  })

  it('drops malformed entries and de-duplicates ids', () => {
    const out = normalizeLayout({
      items: [{ id: 'ops.a', size: 'sm' }, { id: 'ops.a', size: 'md' }, { nope: 1 }, null, { id: 42 }],
    })
    expect(out?.items).toEqual([{ id: 'ops.a', size: 'sm' }])
  })

  it('replaces an unknown size rather than rejecting the whole layout', () => {
    expect(normalizeLayout({ items: [{ id: 'ops.a', size: 'enormous' }] })?.items[0].size).toBe('md')
  })
})

describe('resolveLayout', () => {
  it('falls back when there is nothing saved', () => {
    expect(resolveLayout(META, null, FALLBACK).map((i) => i.id)).toEqual(FALLBACK.items.map((i) => i.id))
  })

  it('survives a corrupt layout by way of normalizeLayout returning null', () => {
    expect(resolveLayout(META, normalizeLayout('{{'), FALLBACK).map((i) => i.id)).toEqual(
      FALLBACK.items.map((i) => i.id),
    )
  })

  it('drops an id with no definition — a widget retired in a later release', () => {
    const saved = caughtUp([{ id: 'ops.a', size: 'sm' }, { id: 'ops.gone', size: 'md' }])
    expect(resolveLayout(META, saved, FALLBACK).map((i) => i.id)).toEqual(['ops.a'])
  })

  it('clamps a stored size the widget no longer offers', () => {
    const saved = caughtUp([{ id: 'ops.a', size: 'xl' }])
    expect(resolveLayout(META, saved, FALLBACK)[0].size).toBe('sm')
  })

  /* A layout written before `seen` existed cannot say whether a widget was
     refused or never offered. `hidden` is the record of refusal, so anything
     in neither list is treated as never-offered — and arrives. */
  it('treats a legacy layout with no seen as never having been offered the rest', () => {
    const saved = layout([{ id: 'ops.a', size: 'sm' }])
    // ops.b joins its sibling; finance has no sibling on the page, so it takes
    // the place its group holds in GROUPS rather than landing at the bottom
    expect(resolveLayout(META, saved, FALLBACK).map((i) => i.id)).toEqual(['finance.money', 'ops.a', 'ops.b'])
  })

  it('adds a widget released after the layout was saved, at its group tail', () => {
    // `seen` predates finance.money, so it counts as new
    const saved = layout([{ id: 'ops.a', size: 'sm' }, { id: 'ops.b', size: 'md' }], [], ['ops.a', 'ops.b'])
    const ids = resolveLayout(META, saved, FALLBACK).map((i) => i.id)
    expect(ids).toContain('finance.money')
    // finance sorts before ops in GROUPS, so it lands ahead of the ops pair
    expect(ids).toEqual(['finance.money', 'ops.a', 'ops.b'])
  })

  it('adds it exactly once across two consecutive merges', () => {
    const saved = layout([{ id: 'ops.a', size: 'sm' }], [], ['ops.a'])
    const first = resolveLayout(META, saved, FALLBACK)
    const second = resolveLayout(META, layout(first, [], first.map((i) => i.id)), FALLBACK)
    const count = (items: LayoutItem[]) => items.filter((i) => i.id === 'finance.money').length
    expect(count(first)).toBe(1)
    expect(count(second)).toBe(1)
  })

  it('is idempotent even when seen was never written back', () => {
    const saved = layout([{ id: 'ops.a', size: 'sm' }], [], ['ops.a'])
    const first = resolveLayout(META, saved, FALLBACK)
    const again = resolveLayout(META, layout(first, [], ['ops.a']), FALLBACK)
    expect(again.filter((i) => i.id === 'finance.money')).toHaveLength(1)
  })

  it('leaves an opt-in widget alone', () => {
    const saved = layout([{ id: 'ops.a', size: 'sm' }], [], ['ops.a'])
    expect(resolveLayout(META, saved, FALLBACK).map((i) => i.id)).not.toContain('me.optin')
  })

  it('does not resurrect a widget the user removed on purpose', () => {
    const saved = layout([{ id: 'ops.a', size: 'sm' }], ['finance.money'], ['ops.a', 'finance.money'])
    expect(resolveLayout(META, saved, FALLBACK).map((i) => i.id)).not.toContain('finance.money')
  })

  /* The distinction the whole design rests on: a key that is gone today may be
     back tomorrow, so it must not cost the widget its slot. */
  it('keeps a widget whose permission was revoked, and only hides it at render', () => {
    const saved = caughtUp([
      { id: 'ops.a', size: 'sm' },
      { id: 'finance.money', size: 'sm' },
      { id: 'ops.b', size: 'md' },
    ])
    const merged = resolveLayout(META, saved, FALLBACK)
    expect(merged.map((i) => i.id)).toContain('finance.money')

    const denied = visibleItems(merged, byId, (k) => k !== 'pricing.revenue', 'staff')
    expect(denied.map((i) => i.id)).toEqual(['ops.a', 'ops.b'])

    // and when the key comes back it is exactly where it was — second of three
    const restored = visibleItems(merged, byId, allowAll, 'staff')
    expect(restored.map((i) => i.id)).toEqual(['ops.a', 'finance.money', 'ops.b'])
  })

  it('hides a widget whose definition is unknown to visibleItems', () => {
    const items: LayoutItem[] = [{ id: 'ghost', size: 'md' }]
    expect(visibleItems(items, byId, allowAll, 'staff')).toEqual([])
  })
})

describe('reordering', () => {
  const items: LayoutItem[] = [
    { id: 'ops.a', size: 'sm' },
    { id: 'finance.money', size: 'sm' },
    { id: 'ops.b', size: 'md' },
  ]

  it('moves an item to where another one sits', () => {
    expect(moveByIds(items, 'ops.b', 'ops.a').map((i) => i.id)).toEqual(['ops.b', 'ops.a', 'finance.money'])
  })

  it('moving onto itself changes nothing', () => {
    expect(moveByIds(items, 'ops.a', 'ops.a')).toEqual(items)
  })

  it('preserves length and uniqueness', () => {
    const out = moveByIds(items, 'ops.a', 'ops.b')
    expect(out).toHaveLength(items.length)
    expect(new Set(out.map((i) => i.id)).size).toBe(items.length)
  })

  it('ignores an id that is not there', () => {
    expect(moveByIds(items, 'nope', 'ops.a')).toEqual(items)
  })

  /* An arrow must move a widget one slot *on screen*. Stepping through the
     stored list instead would make it hop over a widget the reader can't see,
     which looks like the button skipped a beat. */
  it('steps through visible neighbours, not stored ones', () => {
    const visible = ['ops.a', 'ops.b'] // finance.money is filtered out
    const out = moveByOffset(items, 'ops.a', 1, visible)
    expect(out.map((i) => i.id)).toEqual(['finance.money', 'ops.b', 'ops.a'])
  })

  it('clamps at both ends and supports jump-to-edge', () => {
    const visible = ['ops.a', 'finance.money', 'ops.b']
    expect(moveByOffset(items, 'ops.a', -1, visible)).toEqual(items)
    expect(moveByOffset(items, 'ops.b', 1, visible)).toEqual(items)
    expect(moveByOffset(items, 'ops.b', -Infinity, visible).map((i) => i.id)[0]).toBe('ops.b')
  })
})

describe('size, show and hide', () => {
  const items: LayoutItem[] = [
    { id: 'ops.a', size: 'sm' },
    { id: 'ops.b', size: 'md' },
  ]

  it('sets one widget’s size and leaves the rest alone', () => {
    const out = setSize(items, 'ops.a', 'md')
    expect(out[0].size).toBe('md')
    expect(out[1]).toEqual(items[1])
  })

  it('hiding removes it from items and remembers the choice', () => {
    const out = hideWidget(items, [], 'ops.a')
    expect(out.items.map((i) => i.id)).toEqual(['ops.b'])
    expect(out.hidden).toEqual(['ops.a'])
  })

  it('hiding twice does not duplicate the memory', () => {
    expect(hideWidget(items, ['ops.a'], 'ops.a').hidden).toEqual(['ops.a'])
  })

  it('showing puts it back next to its own group and clears the memory', () => {
    const start: LayoutItem[] = [{ id: 'finance.money', size: 'sm' }, { id: 'ops.b', size: 'md' }]
    const out = showWidget(start, ['ops.a'], byId.get('ops.a')!, byId)
    expect(out.hidden).toEqual([])
    expect(out.items.map((i) => i.id)).toEqual(['finance.money', 'ops.b', 'ops.a'])
  })

  it('showing something already on the page is a no-op beyond clearing the memory', () => {
    const out = showWidget(items, ['ops.a'], byId.get('ops.a')!, byId)
    expect(out.items).toHaveLength(2)
    expect(out.hidden).toEqual([])
  })
})

describe('toStoredLayout', () => {
  it('rebuilds seen from what exists, so it cannot grow without bound', () => {
    const out = toStoredLayout([{ id: 'ops.a', size: 'sm' }], ['ops.b'], known)
    expect(out.seen).toEqual(['ops.a', 'ops.b'])
  })

  it('forgets ids that have left the registry', () => {
    const out = toStoredLayout([{ id: 'ops.a', size: 'sm' }], ['ops.retired'], known)
    expect(out.seen).toEqual(['ops.a'])
    expect(out.hidden).toEqual([])
  })

  it('round-trips through normalizeLayout', () => {
    const stored = toStoredLayout([{ id: 'ops.a', size: 'sm' }, { id: 'ops.b', size: 'lg' }], [], known)
    expect(normalizeLayout(stored)).toEqual(stored)
  })
})

/* ===== user-built widgets in the merged registry ==========================
   A widget somebody built is a `WidgetMeta` like any other, and the value of
   that is that nothing in this file needed to change to accommodate it. What
   did need locking down is the *wiring*: every layout call has to be handed
   the merged registry, and `useDashboardLayout` has five of them.            */

const CUSTOM: WidgetMeta = { id: 'custom.deadbeef', group: 'custom', sizes: ['md'] }
const MERGED = [...META, CUSTOM]
const mergedById = new Map(MERGED.map((m) => [m.id, m]))
const mergedKnown = new Set(MERGED.map((m) => m.id))

describe('a custom widget through the layout maths', () => {
  const items: LayoutItem[] = [
    { id: 'ops.a', size: 'sm' },
    { id: 'custom.deadbeef', size: 'md' },
  ]

  it('keeps its slot when the registry knows it', () => {
    const out = resolveLayout(MERGED, caughtUp(items), layout([]))
    expect(out.map((i) => i.id)).toEqual(['ops.a', 'custom.deadbeef'])
  })

  /* Rule 1, and the reason the merge must not run early: against the static
     registry alone a custom id looks like a widget that was retired. */
  it('is dropped by the static-only registry, exactly like a retired widget', () => {
    const out = resolveLayout(META, caughtUp(items), layout([]))
    expect(out.map((i) => i.id)).toEqual(['ops.a'])
  })

  /**
   * The asymmetry that makes the loading race dangerous, asserted precisely.
   *
   * `toStoredLayout` copies `items` unfiltered but prunes `hidden` and `seen`
   * against `known`. So a save that runs before `dashboard_widgets` has landed
   * keeps the id in `items` while dropping it from `seen` — and on the next
   * load rule 1 discards it from `items` too. The widget is gone, and nothing
   * anywhere raised.
   *
   * Both halves are asserted so the guard in `useDashboardLayout` cannot be
   * removed as "probably unnecessary".
   */
  it('survives a save against the merged registry', () => {
    const out = toStoredLayout(items, [], mergedKnown)
    expect(out.items.map((i) => i.id)).toEqual(['ops.a', 'custom.deadbeef'])
    expect(out.seen).toContain('custom.deadbeef')
  })

  it('but a save against a half-loaded registry silently forgets it', () => {
    const out = toStoredLayout(items, [], known)
    expect(out.items.map((i) => i.id)).toEqual(['ops.a', 'custom.deadbeef'])
    expect(out.seen).not.toContain('custom.deadbeef')
    // ...and that is what makes it disappear on the next load
    const next = resolveLayout(META, normalizeLayout(out)!, layout([])).map((i) => i.id)
    expect(next).not.toContain('custom.deadbeef')
  })

  it('is filtered at render by the perms the server handed down', () => {
    const gated: WidgetMeta = { ...CUSTOM, perms: ['pricing.revenue'] }
    const map = new Map([...mergedById, [gated.id, gated]])
    const has = (k: string) => k !== 'pricing.revenue'
    expect(visibleItems(items, map, has, 'staff').map((i) => i.id)).toEqual(['ops.a'])
    // rule 4: filtered out of the drawing, still present in the saved payload
    expect(toStoredLayout(items, [], mergedKnown).items).toHaveLength(2)
  })

  it('lands after every other group when shown for the first time', () => {
    const start: LayoutItem[] = [
      { id: 'finance.money', size: 'sm' },
      { id: 'ops.a', size: 'sm' },
      { id: 'me.optin', size: 'md' },
    ]
    const out = showWidget(start, ['custom.deadbeef'], CUSTOM, mergedById)
    expect(out.items.map((i) => i.id).at(-1)).toBe('custom.deadbeef')
  })
})
