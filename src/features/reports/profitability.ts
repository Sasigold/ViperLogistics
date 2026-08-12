import { exportNotices, sheetName } from '../dashboard/exportDashboard'
import type { ExportPlan, ExportSheet } from '../dashboard/exportDashboard'
import type { DateRange } from '../dashboard/dashboardRange'

/**
 * רווחיות לקוחות — הטיפוסים של תשובת `customer_profitability` (0059) ובניית
 * הייצוא שלה. טהור, כמו כל בוני הייצוא: כל מספר בקובץ הוא מספר שרת — הרווח
 * והאחוז חושבו ב-RPC, והקובץ רק מסדר אותם.
 */

export interface ProfitRow {
  name: string
  color: string | null
  revenue: number
  contractor: number
  payroll: number
  gross: number
  /** null כשאין הכנסות — אחוז מאפס הוא שקר */
  pct: number | null
}

export interface ProfitSummary {
  revenue: number
  contractor: number
  payroll: number | null
  gross: number
  pct: number | null
  unrated_shifts: number | null
  excludes_overhead: boolean
}

export interface ProfitMeta {
  allocated?: number | null
  unallocated?: number | null
  estimated?: boolean
  excludes_overhead?: boolean
  unrated_shifts?: number | null
  truncated?: boolean
  scope_note?: string | null
  denied?: boolean
}

export interface ProfitResult {
  /** null = "לא בשבילך" — מוסכמת המנוע */
  rows: ProfitRow[] | null
  summary?: ProfitSummary
  meta: ProfitMeta
}

export const PROFIT_COLUMNS = ['לקוח', 'הכנסות', 'עלות קבלנים', 'שכר משויך (משוער)', 'רווח גולמי', '% רווח'] as const

export function buildProfitabilityExport(range: DateRange, result: ProfitResult): ExportPlan {
  if (result.rows === null || result.meta.denied) return { range, sheets: [] }

  const taken = new Set<string>()
  const sheets: ExportSheet[] = []

  const s = result.summary
  if (s) {
    const rows: (string | number)[][] = [
      ['הכנסות', s.revenue],
      ['עלות קבלנים', s.contractor],
      ['עלות שכר', s.payroll ?? ''],
      ['רווח גולמי', s.gross],
      ['% רווח', s.pct ?? ''],
    ]
    for (const note of exportNotices(result.meta as Record<string, unknown>)) rows.push([note, ''])
    sheets.push({ name: sheetName('סיכום', taken), title: 'רווחיות — סיכום', columns: ['שדה', 'ערך'], rows })
  }

  const rows: (string | number)[][] = result.rows.map((r) => [
    r.name,
    r.revenue,
    r.contractor,
    r.payroll,
    r.gross,
    r.pct ?? '',
  ])
  for (const note of exportNotices(result.meta as Record<string, unknown>)) rows.push([note])
  sheets.push({
    name: sheetName('רווחיות לקוחות', taken),
    title: 'רווחיות לפי לקוח',
    columns: [...PROFIT_COLUMNS],
    rows,
  })

  return { range, sheets }
}
