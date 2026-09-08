import { describe, expect, it } from 'vitest'
import { PERM } from '../../lib/permissionKeys'
import { FORMS, GROUPS, GROUP_LABELS, SIZES } from './dashboardTypes'
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

  /* ===== 0151: display forms and per-placement options ====================
     Both are opt-in, and both are only useful if the entry agrees with the
     component. The entry decides what the menu offers; the component decides
     what `pickForm` will accept. Where they disagree the reader picks a form
     and nothing changes, which reads as a broken control. */

  it('offers a real form, and more than one or none at all', () => {
    for (const w of WIDGETS) {
      if (!w.forms) continue
      expect(w.forms.length, `${w.id} declares a single form, which is no choice`).toBeGreaterThan(1)
      for (const f of w.forms) expect(FORMS, `${w.id} offers an unknown form: ${f}`).toContain(f)
      expect(new Set(w.forms).size, `${w.id} lists a form twice`).toBe(w.forms.length)
    }
  })

  /* `forms[0]` is what the widget looked like before anybody was offered a
     choice, and `setOpt` stores "the natural one" as no opinion at all — so a
     duplicate or a reordering here silently changes what every existing layout
     draws. Naming the first form of every entry is how that stays deliberate. */
  it('keeps a stable natural form for every widget that offers a choice', () => {
    const natural = WIDGETS.filter((w) => w.forms).map((w) => `${w.id}:${w.forms![0]}`)
    expect(natural).toEqual([
      'finance.my_spend_by_event:list',
      'finance.my_spend_trend:bar',
      'ops.by_status:donut',
      'cust.tasks_by_customer:bar',
      'hr.workload:row',
      'hr.contractor_split:bar',
      'ops.by_type:bar',
      'ops.by_method:bar',
      'ops.fleet_utilization:row',
      'cust.events_by_customer:bar',
      'cust.events_funnel:bar',
      'hr.hours_by_worker:row',
      'hr.attendance_flags:bar',
      'cust.customer_mix:list',
    ])
  })

  it('declares options with unique keys and sane bounds', () => {
    for (const w of WIDGETS) {
      const keys = (w.options ?? []).map((o) => o.key)
      expect(new Set(keys).size, `${w.id} declares a duplicate option key`).toBe(keys.length)
      for (const o of w.options ?? []) {
        expect(o.label.length, `${w.id}.${o.key} has no label`).toBeGreaterThan(0)
        if (o.kind === 'number') expect(o.min, `${w.id}.${o.key} has an empty range`).toBeLessThan(o.max)
        if (o.kind === 'enum') expect(o.choices.length, `${w.id}.${o.key} has no choices`).toBeGreaterThan(1)
      }
    }
  })

  /* `form` is the frame's own key, written from `def.forms`. A widget that
     also declared it as an option would draw two controls for one setting. */
  it('never declares `form` as an option — the frame owns that one', () => {
    for (const w of WIDGETS) {
      expect((w.options ?? []).some((o) => o.key === 'form'), `${w.id} declares its own form option`).toBe(false)
    }
  })

  /* The server reads exactly two keys out of `p_opts`, and since 0151 they are
     set once on the view. A placement that re-declared one would look like a
     per-card control and quietly change the card beside it. */
  it('never declares an option the server reads', () => {
    for (const w of WIDGETS) {
      for (const o of w.options ?? []) {
        expect(['bucket', 'limit'], `${w.id} declares the page-level option ${o.key}`).not.toContain(o.key)
      }
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
