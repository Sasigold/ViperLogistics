import { describe, expect, it } from 'vitest'
import { CATALOG_0043 } from './catalogFixture'
import { buildReportExport, panelToSheet } from './exportReports'
import { sheetToCsv } from './exportCsv'
import type { ReportPanelData } from './exportReports'
import type { RunResult } from '../dashboard/builder/widgetSpec'
import type { ReportState } from './reportState'

const state: ReportState = {
  v: 1,
  source: 'tasks',
  measure: 'revenue',
  agg: 'sum',
  filters: [{ id: 'f0', field: 'tasks.customer', op: 'eq', value: 'abc' }],
  dims: [{ field: 'tasks.customer' }],
  bucket: 'month',
  compare: false,
  range: { from: '2026-01-01', to: '2026-01-31' },
}

const ok = (total: number, rows: [string, number][], meta: Partial<RunResult['meta']> = {}): RunResult => ({
  rows: rows.map(([label, value], i) => ({ key: `k${i}`, label, color: null, value, n: 1 })),
  meta: { total, unit: 'money', ...meta },
})

const denied: RunResult = { rows: null, meta: { denied: true } }

describe('buildReportExport', () => {
  it('summary sheet first, one sheet per breakdown', () => {
    const plan = buildReportExport(
      state,
      [{ title: 'לקוח', result: ok(300, [['אקמי', 200], ['אחר', 100]]) }],
      CATALOG_0043,
    )
    expect(plan.sheets.map((s) => s.title)).toEqual(['סיכום הדוח', 'לקוח'])
    expect(plan.range).toEqual(state.range)
  })

  it('the summary total is the server meta, and filters are spelled out', () => {
    const plan = buildReportExport(state, [{ title: 'לקוח', result: ok(300, [['אקמי', 999]]) }], CATALOG_0043)
    const summary = plan.sheets[0]
    expect(summary.rows).toContainEqual(['סך הכול', 300])
    // the filter line names the field (fixture labels are the keys) and the op in Hebrew
    const filterRow = summary.rows.find((r) => String(r[0]).startsWith('סינון:'))
    expect(filterRow).toEqual(['סינון: tasks.customer', 'שווה ל abc'])
    // the measure label comes from the catalogue row, whatever it says
    expect(summary.rows).toContainEqual(['מדד', 'revenue'])
  })

  it('a denied panel contributes no sheet — and no zero', () => {
    const plan = buildReportExport(
      state,
      [
        { title: 'לקוח', result: denied },
        { title: 'סוג', result: ok(50, [['הקמה', 50]]) },
      ],
      CATALOG_0043,
    )
    expect(plan.sheets.map((s) => s.title)).toEqual(['סיכום הדוח', 'סוג'])
    const flat = JSON.stringify(plan.sheets)
    expect(flat).not.toContain('לקוח')
  })

  it('compare adds previous/delta columns only when the previous run answered', () => {
    const cmp = { ...state, compare: true }
    const panel: ReportPanelData = {
      title: 'לקוח',
      result: ok(300, [['אקמי', 200]]),
      previous: ok(150, [['אקמי', 100]]),
    }
    const plan = buildReportExport(cmp, [panel], CATALOG_0043)
    const sheet = plan.sheets[1]
    expect(sheet.columns).toEqual(['לקוח', 'ערך', 'תקופה קודמת', 'שינוי %', 'שורות'])
    // rows match by key: 200 vs 100 → +100%
    expect(sheet.rows[0]).toEqual(['אקמי', 200, 100, 100, 1])
    // and the summary carries the two totals
    expect(plan.sheets[0].rows).toContainEqual(['תקופה קודמת', 150])
  })

  it('without a previous answer the sheet stays two-column even when compare is on', () => {
    const cmp = { ...state, compare: true }
    const plan = buildReportExport(cmp, [{ title: 'לקוח', result: ok(300, [['אקמי', 200]]) }], CATALOG_0043)
    expect(plan.sheets[1].columns).toEqual(['לקוח', 'ערך', 'שורות'])
  })
})

describe('panelToSheet', () => {
  it('meta caveats travel as footer rows', () => {
    const sheet = panelToSheet(
      { title: 'משאית', result: ok(10, [['א', 10]], { fans_out: true, truncated: true }) },
      false,
      new Set(),
    )
    const footer = sheet!.rows.map((r) => r[0])
    expect(footer).toContain('שורה לכל משאית — סכום השורות גדול ממספר המשימות')
    expect(footer).toContain('מוצגות השורות המובילות בלבד')
  })

  it('the total row is the server total, not the visible sum', () => {
    // truncated: המנוע ראה 300, הגיליון מציג שורה אחת של 40
    const sheet = panelToSheet({ title: 'לקוח', result: ok(300, [['אקמי', 40]], { truncated: true }) }, false, new Set())
    expect(sheet!.rows).toContainEqual(['סך הכול', 300, ''])
  })

  it('a loading panel writes nothing rather than an empty sheet', () => {
    expect(panelToSheet({ title: 'לקוח' }, false, new Set())).toBeNull()
    expect(panelToSheet({ title: 'לקוח', result: denied }, false, new Set())).toBeNull()
  })
})

describe('sheetToCsv', () => {
  it('starts with a BOM so Excel reads Hebrew as UTF-8', () => {
    const csv = sheetToCsv({ name: 'x', title: 'x', columns: ['לקוח', 'ערך'], rows: [['אקמי', 5]] })
    expect(csv.codePointAt(0)).toBe(0xfeff)
    expect(csv).toContain('אקמי')
  })

  it('quotes per RFC 4180 and ends lines with CRLF', () => {
    const csv = sheetToCsv({
      name: 'x',
      title: 'x',
      columns: ['a', 'b'],
      rows: [['יש, פסיק', 'ציטוט "כפול"']],
    })
    expect(csv).toContain('"יש, פסיק"')
    expect(csv).toContain('"ציטוט ""כפול"""')
    expect(csv.endsWith('\r\n')).toBe(true)
    expect(csv.split('\r\n')).toHaveLength(3) // header, row, trailing empty
  })
})
