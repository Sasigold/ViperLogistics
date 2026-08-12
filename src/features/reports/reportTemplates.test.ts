import { describe, expect, it } from 'vitest'
import { CATALOG_0043 } from './catalogFixture'
import { DOMAIN_LABELS, DOMAIN_ORDER, REPORT_TEMPLATES, stateFromTemplate, templatesByDomain } from './reportTemplates'
import { MAX_DIMS, specsFor } from './reportState'
import { specProblems } from '../dashboard/builder/widgetSpec'

/**
 * The drift alarm. Every canned report is held against the catalogue
 * vocabulary 0043 seeds (mirrored in `catalogFixture.ts`): a migration that
 * renames a measure, retires a field, or narrows `allowed_dims` fails here
 * instead of shipping a template that renders a broken panel.
 */

describe('every template validates against the catalogue', () => {
  for (const t of REPORT_TEMPLATES) {
    it(`${t.key} — ${t.title}`, () => {
      const state = stateFromTemplate(t)
      for (const { dim, spec } of specsFor(state, CATALOG_0043)) {
        expect(specProblems(spec, CATALOG_0043), `breakdown ${dim?.field ?? '(summary)'}`).toEqual([])
      }
    })
  }
})

describe('the template list itself', () => {
  it('keys are unique', () => {
    const keys = REPORT_TEMPLATES.map((t) => t.key)
    expect(new Set(keys).size).toBe(keys.length)
  })

  it('no template asks for more panels than the screen offers', () => {
    for (const t of REPORT_TEMPLATES) expect(t.dims.length).toBeLessThanOrEqual(MAX_DIMS)
  })

  it('every domain has a label and at least one template', () => {
    for (const d of DOMAIN_ORDER) {
      expect(DOMAIN_LABELS[d]).toBeTruthy()
      expect(templatesByDomain(d).length).toBeGreaterThan(0)
    }
  })

  it('a template with no breakdown only rides a measure that allows __none__', () => {
    for (const t of REPORT_TEMPLATES.filter((x) => x.dims.length === 0)) {
      const m = CATALOG_0043.measures.find((m) => m.key === t.measure)
      expect(m, t.key).toBeTruthy()
      expect(!m?.allowed_dims || m.allowed_dims.includes('__none__'), t.key).toBe(true)
    }
  })

  it('templates open editable — a fresh state, not a frozen query', () => {
    const t = REPORT_TEMPLATES[0]
    const s = stateFromTemplate(t)
    expect(s.filters).toEqual([])
    expect(s.compare).toBe(false)
    // the preset's dims are copies; editing one must not mutate the template
    s.dims[0].viz = 'donut'
    expect(t.dims[0].viz).not.toBe('donut')
  })
})
