import { describe, expect, it } from 'vitest'
import { buildProfitabilityExport } from './profitability'
import type { ProfitResult } from './profitability'

const range = { from: '2026-01-01', to: '2026-01-31' }

const result: ProfitResult = {
  rows: [
    { name: 'אקמי', color: '#f00', revenue: 1000, contractor: 300, payroll: 200, gross: 500, pct: 50 },
    { name: 'ללא רווח', color: null, revenue: 0, contractor: 10, payroll: 0, gross: -10, pct: null },
  ],
  summary: { revenue: 1000, contractor: 310, payroll: 200, gross: 490, pct: 49, unrated_shifts: 2, excludes_overhead: true },
  meta: { estimated: true, unallocated: 120, truncated: true, scope_note: 'הערה', unrated_shifts: 2 },
}

describe('buildProfitabilityExport', () => {
  it('summary sheet then detail sheet, both from server numbers', () => {
    const plan = buildProfitabilityExport(range, result)
    expect(plan.sheets.map((s) => s.title)).toEqual(['רווחיות — סיכום', 'רווחיות לפי לקוח'])
    expect(plan.sheets[0].rows).toContainEqual(['רווח גולמי', 490])
    // per-row gross is the server's, not revenue-contractor-payroll recomputed
    expect(plan.sheets[1].rows[0]).toEqual(['אקמי', 1000, 300, 200, 500, 50])
  })

  it('a null pct exports as empty, not as zero', () => {
    const plan = buildProfitabilityExport(range, result)
    expect(plan.sheets[1].rows[1]).toEqual(['ללא רווח', 0, 10, 0, -10, ''])
  })

  it('the caveats travel with both sheets', () => {
    const plan = buildProfitabilityExport(range, result)
    for (const sheet of plan.sheets) {
      const flat = sheet.rows.map((r) => String(r[0]))
      expect(flat).toContain('מוצגות השורות המובילות בלבד')
      expect(flat.some((x) => x.startsWith('משוער'))).toBe(true)
    }
  })

  it('denied → an empty plan, no sheets and no zeros', () => {
    expect(buildProfitabilityExport(range, { rows: null, meta: { denied: true } }).sheets).toEqual([])
  })
})
