import { describe, expect, it } from 'vitest'
import { buildDashboardExport, customResultToSheet, sectionToSheet, sheetName } from './exportDashboard'
import type { LayoutItem, WidgetDef } from './dashboardTypes'

const RANGE = { from: '2026-03-01', to: '2026-03-31' }

const widget = (id: string, title: string, sections?: string[]): WidgetDef =>
  ({
    id,
    title,
    description: '',
    group: 'finance',
    sizes: ['sm'],
    sections,
    Component: () => null,
  }) as unknown as WidgetDef

describe('sheetName', () => {
  it('strips the characters Excel refuses', () => {
    expect(sheetName('a/b\\c?d*e[f]g:h', new Set())).toBe('a b c d e f g h')
  })

  it('truncates to what Excel allows', () => {
    expect(sheetName('א'.repeat(60), new Set()).length).toBeLessThanOrEqual(31)
  })

  it('de-duplicates rather than overwriting a sheet', () => {
    const taken = new Set<string>()
    expect(sheetName('כספים', taken)).toBe('כספים')
    expect(sheetName('כספים', taken)).toBe('כספים 2')
    expect(sheetName('כספים', taken)).toBe('כספים 3')
  })

  it('never returns an empty name', () => {
    expect(sheetName('***', new Set())).toBe('גיליון')
  })
})

describe('sectionToSheet', () => {
  /* The rule the whole export rests on: `null` is the server saying this
     section is not for this reader. Writing it as a zero would put a number in
     an accounting file that nobody was allowed to see. */
  it('omits a section the reader holds no key for', () => {
    expect(sectionToSheet('עלות שכר', null, new Set())).toBeNull()
  })

  it('omits an empty section rather than writing a headerless sheet', () => {
    expect(sectionToSheet('x', [], new Set())).toBeNull()
    expect(sectionToSheet('x', undefined, new Set())).toBeNull()
  })

  it('turns a list of rows into columns and rows', () => {
    const sheet = sectionToSheet('לפי לקוח', [{ name: 'אקמי', cnt: 3 }], new Set())
    expect(sheet?.columns).toEqual(['name', 'cnt'])
    expect(sheet?.rows).toEqual([['אקמי', 3]])
  })

  it('turns a totals bag into key/value pairs', () => {
    const sheet = sectionToSheet('שכר', { total: 700, shifts: 4 }, new Set())
    expect(sheet?.columns).toEqual(['שדה', 'ערך'])
    expect(sheet?.rows).toEqual([
      ['total', 700],
      ['shifts', 4],
    ])
  })

  it('leaves nested lists out of the totals sheet instead of stringifying them', () => {
    const sheet = sectionToSheet('שכר', { total: 700, by_customer: [{ name: 'a' }] }, new Set())
    expect(sheet?.rows).toEqual([['total', 700]])
  })

  /* jsonb hands back numerics as strings. Left as text, every money column in
     the file would be un-summable in Excel — which is the one thing a
     spreadsheet is for. */
  it('reads a numeric string back as a number', () => {
    const sheet = sectionToSheet('x', [{ total: '1234.50', name: 'אקמי' }], new Set())
    expect(sheet?.rows[0][0]).toBe(1234.5)
    expect(sheet?.rows[0][1]).toBe('אקמי')
  })

  it('writes booleans and nulls as something a human reads', () => {
    const sheet = sectionToSheet('x', [{ ok: true, no: false, missing: null }], new Set())
    expect(sheet?.rows[0]).toEqual(['כן', 'לא', ''])
  })
})

describe('buildDashboardExport', () => {
  const byId = new Map([
    ['a', widget('a', 'עלות שכר', ['cost.payroll'])],
    ['b', widget('b', 'שעות נוספות', ['cost.payroll'])], // same section
    ['c', widget('c', 'ציר הזמן')], // no section at all
    ['d', widget('d', 'לפי לקוח', ['events.by_customer'])],
  ])
  const items: LayoutItem[] = [
    { id: 'a', size: 'sm' },
    { id: 'b', size: 'sm' },
    { id: 'c', size: 'lg' },
    { id: 'd', size: 'md' },
  ]
  const data: Record<string, unknown> = {
    'cost.payroll': { total: 700 },
    'events.by_customer': [{ name: 'אקמי', cnt: 2 }],
  }

  it('writes a shared section once, not once per widget', () => {
    const plan = buildDashboardExport(items, byId, (k) => data[k], RANGE)
    expect(plan.sheets).toHaveLength(2)
    expect(plan.sheets.map((s) => s.title)).toEqual(['עלות שכר', 'לפי לקוח'])
  })

  it('skips widgets with no data behind them', () => {
    const plan = buildDashboardExport(items, byId, (k) => data[k], RANGE)
    expect(plan.sheets.map((s) => s.title)).not.toContain('ציר הזמן')
  })

  /* The file mirrors the screen, so re-arranging the dashboard re-arranges the
     workbook. A shared section takes its title from whichever widget reaches
     it first — which is also the one the reader sees first. */
  it('follows the order the widgets were arranged in', () => {
    const reversed = [...items].reverse()
    const plan = buildDashboardExport(reversed, byId, (k) => data[k], RANGE)
    expect(plan.sheets.map((s) => s.title)).toEqual(['לפי לקוח', 'שעות נוספות'])
  })

  it('produces nothing at all when every section is forbidden', () => {
    const plan = buildDashboardExport(items, byId, () => null, RANGE)
    expect(plan.sheets).toEqual([])
  })

  it('carries the range so the file says what period it covers', () => {
    expect(buildDashboardExport(items, byId, (k) => data[k], RANGE).range).toEqual(RANGE)
  })
})

/* ===== user-built widgets =================================================
   The export reads sections by key, and a built widget has no key. Without an
   explicit branch it contributes nothing and nobody notices — the file just
   quietly omits the widget somebody made on purpose.                         */

describe('customResultToSheet', () => {
  const taken = () => new Set<string>()

  it('writes the rows and a total', () => {
    const sheet = customResultToSheet(
      'הכנסות לפי לקוח',
      { rows: [{ label: 'אקמי', value: 1200 }, { label: 'לקוח ב', value: 800 }], meta: { total: 2000 } },
      taken(),
    )
    expect(sheet?.rows).toEqual([
      ['אקמי', 1200],
      ['לקוח ב', 800],
      ['סך הכול', 2000],
    ])
  })

  /* The null rule, unchanged: the server declining is not a zero, so it is
     absent from the file rather than present as nothing. */
  it('writes no sheet for a result the reader may not see', () => {
    expect(customResultToSheet('רווח', { rows: null, meta: { denied: true } }, taken())).toBeNull()
  })

  it('writes no sheet for a spec the catalogue lost', () => {
    expect(customResultToSheet('ישן', { rows: null, meta: { unsupported: 'revenue_v0' } }, taken())).toBeNull()
  })

  it('writes no sheet when there is nothing in range', () => {
    expect(customResultToSheet('ריק', { rows: [], meta: { total: 0 } }, taken())).toBeNull()
  })

  /* A number in a spreadsheet outlives the card it was copied from, so the
     caveats have to travel with it. */
  it('carries the disclosures into the file', () => {
    const sheet = customResultToSheet(
      'שכר לפי לקוח',
      {
        rows: [{ label: 'אקמי', value: 500 }],
        meta: {
          total: 500,
          estimated: true,
          unallocated: 120,
          unrated_shifts: 3,
          presence: { present: 8, missing: 2, zero: 1 },
          truncated: true,
          scope_note: 'משמרות מאושרות בלבד',
        },
      },
      taken(),
    )
    const notes = (sheet?.rows ?? []).map((r) => String(r[0]))
    expect(notes.some((n) => n.includes('משוער'))).toBe(true)
    expect(notes.some((n) => n.includes('ללא תעריף'))).toBe(true)
    expect(notes.some((n) => n.includes('ללא ערך'))).toBe(true)
    expect(notes.some((n) => n.includes('המובילות'))).toBe(true)
    expect(notes).toContain('משמרות מאושרות בלבד')
  })

  it('ignores a payload that is not a run result', () => {
    expect(customResultToSheet('x', null, taken())).toBeNull()
    expect(customResultToSheet('x', [1, 2, 3], taken())).toBeNull()
  })
})

describe('buildDashboardExport with a built widget', () => {
  const def = {
    id: 'custom.00000000000000000000000000000001',
    group: 'custom' as const,
    title: 'הכנסות לפי לקוח',
    description: '',
    sizes: ['md'] as const,
    Component: (() => null) as never,
  }
  const byId = new Map([[def.id, def]])
  const range = { from: '2026-01-01', to: '2026-01-31' }

  it('turns the run result into a sheet', () => {
    const plan = buildDashboardExport(
      [{ id: def.id, size: 'md' }],
      byId,
      () => undefined,
      range,
      () => ({ rows: [{ label: 'אקמי', value: 10 }], meta: { total: 10 } }),
    )
    expect(plan.sheets.map((s) => s.title)).toEqual(['הכנסות לפי לקוח'])
  })

  it('omits it when nothing supplies custom results', () => {
    const plan = buildDashboardExport([{ id: def.id, size: 'md' }], byId, () => undefined, range)
    expect(plan.sheets).toEqual([])
  })
})
