import { describe, expect, it } from 'vitest'
import { PERM } from '../../lib/permissionKeys'
import { GROUPS, GROUP_LABELS, SIZES } from './dashboardTypes'
import { SECTIONS } from './sections'
import { BUILT_IN_DEFAULT, WIDGETS, WIDGETS_BY_ID } from './registry'
import { normalizeLayout, resolveLayout } from './layout'

const PERM_KEYS = new Set<string>(Object.values(PERM))

describe('the widget registry', () => {
  it('has unique ids', () => {
    const ids = WIDGETS.map((w) => w.id)
    expect(new Set(ids).size).toBe(ids.length)
  })

  /* The id is what a saved layout stores. A loose convention here is what stops
     `revenue` and `finance.revenue` from both existing a year from now. */
  it('names every id <group-ish>.<thing>', () => {
    for (const w of WIDGETS) expect(w.id).toMatch(/^[a-z]+\.[a-z_]+$/)
  })

  it('declares at least one size, and only real ones', () => {
    for (const w of WIDGETS) {
      expect(w.sizes.length).toBeGreaterThan(0)
      for (const s of w.sizes) expect(SIZES).toContain(s)
    }
  })

  it('belongs to a known group', () => {
    for (const w of WIDGETS) expect(GROUPS).toContain(w.group)
  })

  it('has a title and a description for the catalogue', () => {
    for (const w of WIDGETS) {
      expect(w.title.length).toBeGreaterThan(0)
      expect(w.description.length).toBeGreaterThan(0)
    }
  })

  /* An unknown section key is skipped by the server rather than raised — that
     is what lets an old server serve a new client — so a typo here has no
     symptom at all: the widget returns null forever and simply never appears. */
  it('only requests sections the server knows how to compute', () => {
    for (const w of WIDGETS) {
      for (const s of w.sections ?? []) {
        expect(SECTIONS, `${w.id} requests an unknown section: ${s}`).toContain(s)
      }
    }
  })

  it('asks for a section only when it needs one', () => {
    for (const w of WIDGETS) {
      if (w.sections) expect(w.sections.length, `${w.id} declares an empty sections array`).toBeGreaterThan(0)
    }
  })

  /* `wantsDelta` costs a second round trip over the previous period. It is
     only meaningful for a widget whose numbers move with the range. */
  it('only wants a delta when it reacts to the range', () => {
    for (const w of WIDGETS) {
      if (w.wantsDelta) expect(w.usesRange, `${w.id} wants a delta but ignores the range`).toBe(true)
    }
  })

  /* A typo in a permission key fails open — `has('dashbord.view')` is false
     for everyone, so the widget silently disappears for the whole company
     rather than erroring anywhere. Checking against the catalogue is the only
     place that mistake is cheap to catch. */
  it('only names permission keys that exist in the registry', () => {
    for (const w of WIDGETS) {
      for (const p of [...(w.perms ?? []), ...(w.anyPerms ?? [])]) {
        expect(PERM_KEYS, `${w.id} names an unknown key: ${p}`).toContain(p)
      }
    }
  })
})

describe('the built-in default', () => {
  it('references only widgets that exist', () => {
    for (const item of BUILT_IN_DEFAULT.items) {
      expect(WIDGETS_BY_ID.has(item.id), `unknown widget in default layout: ${item.id}`).toBe(true)
    }
  })

  it('gives every widget a size it actually offers', () => {
    for (const item of BUILT_IN_DEFAULT.items) {
      expect(WIDGETS_BY_ID.get(item.id)!.sizes, `${item.id} @ ${item.size}`).toContain(item.size)
    }
  })

  it('lists no widget twice', () => {
    const ids = BUILT_IN_DEFAULT.items.map((i) => i.id)
    expect(new Set(ids).size).toBe(ids.length)
  })

  /* The invariant behind rule 2 of the merge: a `defaultOn` widget missing
     from the default would be treated as new on every single load for anyone
     who has nothing saved, and re-appended forever. */
  it('contains every defaultOn widget', () => {
    const inDefault = new Set(BUILT_IN_DEFAULT.items.map((i) => i.id))
    for (const w of WIDGETS) {
      if (w.defaultOn) expect(inDefault, `${w.id} is defaultOn but missing from the default`).toContain(w.id)
    }
  })

  it('contains nothing that is not defaultOn', () => {
    for (const item of BUILT_IN_DEFAULT.items) {
      expect(WIDGETS_BY_ID.get(item.id)!.defaultOn, `${item.id} is in the default but not defaultOn`).toBe(true)
    }
  })

  it('is a layout the reader accepts, unchanged', () => {
    expect(normalizeLayout(BUILT_IN_DEFAULT)).toEqual(BUILT_IN_DEFAULT)
  })

  it('resolves to itself — a fresh user sees exactly the default', () => {
    const out = resolveLayout(WIDGETS, null, BUILT_IN_DEFAULT)
    expect(out.map((i) => i.id)).toEqual(BUILT_IN_DEFAULT.items.map((i) => i.id))
  })
})

/* ===== the reserved namespace =============================================
   User-built widgets are `custom.<uuid-hex>`, which does not match the id
   convention above — a uuid has digits in it. That is fine because this suite
   only walks `WIDGETS`, but it is only fine while the prefix stays reserved:
   a hand-written `custom.something` would collide with a built one and the
   two would fight over the same slot in every saved layout. */
describe('the custom namespace', () => {
  it('is not used by any hand-written widget', () => {
    for (const w of WIDGETS) expect(w.id.startsWith('custom.')).toBe(false)
  })

  it('has a label, like every other group', () => {
    for (const g of GROUPS) expect(GROUP_LABELS[g]).toBeTruthy()
  })
})
