/**
 * ייצוא הדשבורד ל-Excel.
 *
 * מייצא בדיוק את מה שעל המסך: הווידג׳טים הגלויים, לפי הסדר שבו סודרו, כל אחד
 * עם הנתונים שהשרת החזיר לו. זה מה שהופך את הקובץ למשמעותי — הוא לא "כל
 * הנתונים" אלא התצוגה שמישהו בנה לעצמו.
 *
 * שני כללים, שניהם המשך ישיר של `exportAttendance.ts`:
 *
 * 1. שום מספר אינו מחושב כאן. הסכומים מגיעים מהסקשנים כפי שהם, כי המנוע יודע
 *    מה נספר ומה לא — משמרת שממתינה לאישור, משמרת בלי תעריף, שורת קבלן בסכום
 *    אפס. חישוב שני בדפדפן היה מתפצל מהראשון ברגע שמישהו יערוך מדרגת שעות
 *    נוספות בהגדרות.
 * 2. סקשן שחזר `null` אינו נכתב כלל. null הוא "לא בשבילך", ולכן הוא נעדר
 *    מהקובץ במקום להופיע כאפס — אין כאן הכרעת הרשאה שנייה שיכולה לחלוק על זו
 *    של השרת.
 *
 * בניית התוכנית מופרדת מהכתיבה כדי שהכללים יהיו ניתנים לבדיקה בלי ExcelJS
 * ובלי DOM.
 */
import { isCustomId, toUuid } from './builder/customRegistry'
import type { LayoutItem, WidgetDef } from './dashboardTypes'
import type { DateRange } from './dashboardRange'

export interface ExportSheet {
  /** שם הלשונית — שם הווידג׳ט, מקוצר לאורך ש-Excel מרשה */
  name: string
  title: string
  columns: string[]
  rows: (string | number)[][]
}

export interface ExportPlan {
  range: DateRange
  sheets: ExportSheet[]
}

/** Excel: עד 31 תווים, ובלי : \ / ? * [ ] */
export function sheetName(title: string, taken: Set<string>): string {
  const base = title.replace(/[:\\/?*[\]]/g, ' ').trim().slice(0, 28) || 'גיליון'
  let name = base
  let n = 2
  while (taken.has(name)) name = `${base.slice(0, 26)} ${n++}`
  taken.add(name)
  return name
}

const isRecord = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null && !Array.isArray(v)

/**
 * A section is either a list of rows or a bag of totals, and both turn into a
 * sheet the same way — the shape decides, not a per-widget mapping. A widget
 * with no tabular data behind it (the timeline, the quick actions) simply
 * contributes no sheet rather than an empty one.
 */
export function sectionToSheet(title: string, value: unknown, taken: Set<string>): ExportSheet | null {
  if (value === null || value === undefined) return null // "לא בשבילך"

  if (Array.isArray(value)) {
    if (value.length === 0) return null
    const first = value[0]
    if (!isRecord(first)) return null
    const columns = Object.keys(first)
    return {
      name: sheetName(title, taken),
      title,
      columns,
      rows: value.map((r) => columns.map((c) => cell((r as Record<string, unknown>)[c]))),
    }
  }

  if (isRecord(value)) {
    // nested lists inside a totals bag are the interesting part; the scalars
    // become a two-column key/value sheet
    const scalars = Object.entries(value).filter(([, v]) => !Array.isArray(v) && !isRecord(v))
    if (scalars.length === 0) return null
    return {
      name: sheetName(title, taken),
      title,
      columns: ['שדה', 'ערך'],
      rows: scalars.map(([k, v]) => [k, cell(v)]),
    }
  }

  return null
}

function cell(v: unknown): string | number {
  if (v === null || v === undefined) return ''
  if (typeof v === 'number') return v
  if (typeof v === 'boolean') return v ? 'כן' : 'לא'
  if (typeof v === 'string') {
    // numeric strings come back from jsonb for numeric columns; Excel should
    // treat them as numbers so the totals row in the file actually adds up
    const n = Number(v)
    return v !== '' && Number.isFinite(n) ? n : v
  }
  return JSON.stringify(v)
}

/**
 * A user-built widget's result → a sheet.
 *
 * It cannot go through `sectionToSheet`: a custom widget has no section key,
 * and its payload is the uniform `{rows, meta}` the engine returns rather than
 * a bespoke section shape. Both rules survive intact — a `denied` or
 * `unsupported` result contributes no sheet, exactly as `null` does — and the
 * meta disclosures are written as footer rows so the file carries the same
 * caveats the card does. A number in a spreadsheet outlives the screen it was
 * copied from, so it has to travel with what it excludes.
 */
export function customResultToSheet(title: string, value: unknown, taken: Set<string>): ExportSheet | null {
  if (!isRecord(value)) return null
  const meta = isRecord(value.meta) ? value.meta : {}
  if (meta.denied || meta.unsupported) return null
  const rows = value.rows
  if (!Array.isArray(rows) || rows.length === 0) return null

  const body: (string | number)[][] = rows.map((r) => {
    const row = isRecord(r) ? r : {}
    return [cell(row.label), cell(row.value)]
  })

  if (meta.total !== null && meta.total !== undefined) body.push(['סך הכול', cell(meta.total)])
  for (const note of exportNotices(meta)) body.push([note, ''])

  return { name: sheetName(title, taken), title, columns: ['פריט', 'ערך'], rows: body }
}

/** the same caveats the card prints, in the same order */
export function exportNotices(meta: Record<string, unknown>): string[] {
  const out: string[] = []
  if (meta.estimated) out.push(`משוער — לא משויך: ${cell(meta.unallocated)}`)
  if (Number(meta.unrated_shifts ?? 0) > 0) out.push(`משמרות ללא תעריף שאינן נספרות: ${meta.unrated_shifts}`)
  const presence = isRecord(meta.presence) ? meta.presence : null
  if (presence && Number(presence.missing ?? 0) > 0) {
    out.push(`רשומות ללא ערך שאינן נספרות: ${presence.missing}`)
  }
  if (meta.fans_out) out.push('שורה לכל משאית — סכום השורות גדול ממספר המשימות')
  if (meta.truncated) out.push('מוצגות השורות המובילות בלבד')
  if (meta.scope_note) out.push(String(meta.scope_note))
  return out
}

export function buildDashboardExport(
  items: LayoutItem[],
  byId: Map<string, WidgetDef>,
  section: (key: string) => unknown,
  range: DateRange,
  /** results of the user-built widgets, keyed by the row id the server knows */
  customResult?: (rowId: string) => unknown,
): ExportPlan {
  const taken = new Set<string>()
  const sheets: ExportSheet[] = []
  const done = new Set<string>()

  for (const item of items) {
    const def = byId.get(item.id)
    if (!def) continue

    // a built widget answers through dashboard_widgets_run, not a section —
    // without this branch the export silently omits every one of them
    if (isCustomId(item.id)) {
      const uuid = toUuid(item.id)
      if (!uuid || !customResult) continue
      const sheet = customResultToSheet(def.title, customResult(uuid), taken)
      if (sheet) sheets.push(sheet)
      continue
    }

    if (!def.sections?.length) continue
    for (const key of def.sections) {
      // two widgets often share a section (the three contractor tiles all read
      // cost.contractor); the sheet is written once
      if (done.has(key)) continue
      done.add(key)
      const sheet = sectionToSheet(def.title, section(key), taken)
      if (sheet) sheets.push(sheet)
    }
  }

  return { range, sheets }
}

/** ExcelJS is heavy and the export is the only reason this screen needs it. */
export async function writeDashboardExport(plan: ExportPlan): Promise<Blob> {
  const ExcelJS = await import('exceljs')
  const wb = new ExcelJS.Workbook()
  wb.created = new Date()

  for (const sheet of plan.sheets) {
    const ws = wb.addWorksheet(sheet.name, { views: [{ rightToLeft: true }] })
    ws.addRow([sheet.title])
    ws.getRow(1).font = { bold: true, size: 13 }
    ws.addRow([`${plan.range.from} – ${plan.range.to}`])
    ws.addRow([])
    const header = ws.addRow(sheet.columns)
    header.font = { bold: true }
    for (const row of sheet.rows) ws.addRow(row)
    ws.columns.forEach((c) => {
      c.width = 18
    })
  }

  if (plan.sheets.length === 0) wb.addWorksheet('ריק').addRow(['אין נתונים לייצוא'])

  const buf = await wb.xlsx.writeBuffer()
  return new Blob([buf], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' })
}
