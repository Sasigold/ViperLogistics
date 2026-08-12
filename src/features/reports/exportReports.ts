import { exportNotices, sheetName } from '../dashboard/exportDashboard'
import { AGG_LABELS, BUCKET_LABELS, OP_LABELS } from '../dashboard/builder/widgetSpec'
import { pctDelta } from '../../components/ui/format'
import type { ExportPlan, ExportSheet } from '../dashboard/exportDashboard'
import type { Catalog, RunResult } from '../dashboard/builder/widgetSpec'
import type { ReportState } from './reportState'

/**
 * ייצוא מסך הדוחות ל-Excel. אותם שני כללים של `exportDashboard.ts`, בלי חריגים:
 *
 * 1. שום מספר אינו מחושב כאן — הסכומים הם `meta.total` של המנוע, שמחושב לפני
 *    תקרת השורות, ולכן "סך הכול" בקובץ נכון גם כשהגיליון מציג 50 שורות בלבד.
 *    היוצא היחיד הוא אחוז השינוי מול התקופה הקודמת, שהוא יחס בין שני מספרי
 *    שרת ולא סכימה.
 * 2. פאנל שנדחה (`denied`/`unsupported`) אינו נכתב כלל — null הוא "לא בשבילך",
 *    והקובץ אינו מכריע הכרעת הרשאה שנייה.
 *
 * הבנייה טהורה כדי שהכללים ייבדקו בלי ExcelJS ובלי DOM; הכתיבה עוברת דרך
 * `writeDashboardExport`, שכבר יודע RTL וגיליון "ריק".
 */

/** מה שהמסך יודע על פאנל אחד, בצורה שאינה תלויה ב-React */
export interface ReportPanelData {
  /** שם הפילוח, או null לפאנל הסיכום חסר-הפילוח */
  title: string | null
  result?: RunResult
  previous?: RunResult
}

const fmt = (v: number | null | undefined): string | number => (v === null || v === undefined ? '' : v)

export function buildReportExport(
  state: ReportState,
  panels: ReportPanelData[],
  cat: Catalog,
): ExportPlan {
  const taken = new Set<string>()
  const sheets: ExportSheet[] = []

  const measure = cat.measures.find((m) => m.key === state.measure && m.source_key === state.source)
  const first = panels.find((p) => p.result?.rows != null)

  /* ── גיליון הסיכום ─────────────────────────────────────────────────── */
  const summary: (string | number)[][] = [
    ['מדד', measure?.label_he ?? state.measure],
    ['סוג חישוב', AGG_LABELS[state.agg] ?? state.agg],
    ['קיבוץ זמן', BUCKET_LABELS[state.bucket] ?? state.bucket],
  ]
  for (const f of state.filters) {
    const def = cat.fields.find((x) => x.key === f.field)
    summary.push([
      `סינון: ${def?.label_he ?? f.field}`,
      `${OP_LABELS[f.op] ?? f.op} ${Array.isArray(f.value) ? f.value.join(', ') : (f.value ?? '')}`.trim(),
    ])
  }
  if (first?.result) {
    summary.push(['סך הכול', fmt(first.result.meta.total)])
    if (state.compare && first.previous?.rows != null) {
      const cur = Number(first.result.meta.total ?? 0)
      const prev = Number(first.previous.meta.total ?? 0)
      summary.push(['תקופה קודמת', fmt(first.previous.meta.total)])
      const delta = pctDelta(cur, prev)
      if (delta !== null) summary.push(['שינוי %', delta])
    }
  }
  sheets.push({ name: sheetName('סיכום', taken), title: 'סיכום הדוח', columns: ['שדה', 'ערך'], rows: summary })

  /* ── גיליון לכל פילוח ─────────────────────────────────────────────── */
  for (const panel of panels) {
    const sheet = panelToSheet(panel, state.compare, taken)
    if (sheet) sheets.push(sheet)
  }

  return { range: state.range, sheets }
}

/** פאנל אחד → גיליון, או כלום אם השרת סירב */
export function panelToSheet(panel: ReportPanelData, compare: boolean, taken: Set<string>): ExportSheet | null {
  const result = panel.result
  if (!result || result.rows === null) return null // "לא בשבילך" — או עדיין נטען
  if (result.meta.denied || result.meta.unsupported) return null

  const title = panel.title ?? 'סיכום'
  const withPrev = compare && panel.previous?.rows != null
  const prevByKey = new Map((panel.previous?.rows ?? []).map((r) => [r.key ?? r.label, r.value]))

  const columns = [title, 'ערך', ...(withPrev ? ['תקופה קודמת', 'שינוי %'] : []), 'שורות']
  const rows: (string | number)[][] = result.rows.map((r) => {
    const base: (string | number)[] = [r.label, fmt(r.value)]
    if (withPrev) {
      const prev = prevByKey.get(r.key ?? r.label)
      const delta = r.value !== null && prev != null ? pctDelta(Number(r.value), Number(prev)) : null
      base.push(fmt(prev ?? null), delta === null ? '' : delta)
    }
    base.push(r.n)
    return base
  })

  // השורה התחתונה של השרת, לא סכום העמודה — ואחריה ההסתייגויות, כדי שהקובץ
  // יסביר את עצמו גם אחרי שהמסך נסגר
  const total: (string | number)[] = ['סך הכול', fmt(result.meta.total)]
  if (withPrev) total.push(fmt(panel.previous?.meta.total ?? null), '')
  total.push('')
  rows.push(total)
  for (const note of exportNotices(result.meta as Record<string, unknown>)) rows.push([note])

  return { name: sheetName(title, taken), title, columns, rows }
}
