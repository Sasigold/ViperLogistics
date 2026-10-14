/**
 * הייצוא לרואה החשבון (0233): קובץ ZIP לחודש —
 *
 *   חשבוניות-2026-10/
 *     חשבוניות-2026-10.xlsx        סיכום, רשימת החשבוניות, והשורות
 *     001_02-10-2026_פז_A-100.pdf  כל חשבונית, ממוספרת לפי התאריך
 *     …
 *
 * הסכומים והסיכום הם מה שהשרת החזיר (`invoices_board`) — אין כאן חישוב כסף,
 * רק סידור. בניית הטבלאות טהורה (`buildInvoiceSheets`) כדי שתיבדק בלי DOM.
 */
import type { InvoicesBoard } from '../../types/domain'
import {
  CATEGORY_LABELS,
  DOC_TYPE_LABELS,
  SOURCE_LABELS,
  fmtInvoiceDate,
  monthKey,
  monthLabel,
  zipEntries,
} from './invoices'
import { buildZip } from './zip'
import type { ZipEntry } from './zip'

type Cell = string | number | null

export interface Sheet {
  name: string
  title?: string
  pairs?: [string, Cell][]
  header: string[]
  /** רוחב לכל עמודה */
  widths: number[]
  /** אינדקסים של עמודות כסף — מעוצבות כמספר עם שתי ספרות */
  money: number[]
  rows: Cell[][]
  footer?: Cell[]
}

export function buildInvoiceSheets(board: InvoicesBoard): { sheets: Sheet[]; files: { id: string; name: string }[] } {
  const entries = zipEntries(board.invoices)
  const t = board.totals

  const summary: Sheet = {
    name: 'סיכום',
    title: `חשבוניות ספקים — ${monthLabel(board.period)}`,
    pairs: [
      ['מספר חשבוניות', t.count],
      ['סה"כ לפני מע"מ (₪)', t.before_vat],
      ['מע"מ (₪)', t.vat],
      ['סה"כ כולל מע"מ (₪)', t.total],
      ...(t.foreign > 0 ? ([['חשבוניות במטבע זר (לא בסיכום)', t.foreign]] as [string, Cell][]) : []),
    ],
    header: ['סוג הוצאה', 'חשבוניות', 'מע"מ', 'סה"כ כולל מע"מ'],
    widths: [28, 12, 14, 18],
    money: [2, 3],
    rows: board.categories.map((c) => [CATEGORY_LABELS[c.category] ?? c.category, c.count, c.vat, c.total]),
  }

  const list: Sheet = {
    name: 'חשבוניות',
    header: [
      'מס׳',
      'קובץ',
      'תאריך',
      'ספק',
      'ח.פ. ספק',
      'מספר חשבונית',
      'סוג מסמך',
      'סוג הוצאה',
      'תיאור',
      'עבור',
      'לפני מע"מ',
      'מע"מ',
      'סה"כ',
      'מטבע',
      'מקור',
      'הערות',
    ],
    widths: [6, 34, 12, 24, 13, 16, 16, 20, 28, 22, 13, 11, 13, 7, 9, 28],
    money: [10, 11, 12],
    rows: entries.map(({ invoice: i, name }, n) => [
      n + 1,
      name,
      fmtInvoiceDate(i.issue_date),
      i.vendor_name ?? '',
      i.vendor_tax_id ?? '',
      i.invoice_number ?? '',
      DOC_TYPE_LABELS[i.doc_type],
      CATEGORY_LABELS[i.category],
      i.description ?? '',
      i.company_name ?? i.recipient_name ?? '',
      i.amount_before_vat,
      i.vat_amount,
      i.total_amount,
      i.currency,
      SOURCE_LABELS[i.source],
      i.notes ?? '',
    ]),
    footer: ['', 'סה"כ (₪)', '', '', '', '', '', '', '', '', t.before_vat, t.vat, t.total, 'ILS', '', ''],
  }

  const lines: Sheet = {
    name: 'שורות',
    header: ['מס׳ חשבונית בקובץ', 'ספק', 'מספר חשבונית', 'שורה', 'תיאור', 'כמות', 'מחיר יחידה', 'סה"כ שורה'],
    widths: [10, 24, 16, 7, 40, 9, 13, 13],
    money: [6, 7],
    rows: entries.flatMap(({ invoice: i }, n) =>
      i.lines.map((l) => [n + 1, i.vendor_name ?? '', i.invoice_number ?? '', l.line_no, l.description, l.quantity, l.unit_price, l.total]),
    ),
  }

  return { sheets: [summary, list, lines], files: entries.map((e) => ({ id: e.invoice.id, name: e.name })) }
}

async function writeWorkbook(sheets: Sheet[]): Promise<Uint8Array> {
  const ExcelJS = (await import('exceljs')).default
  const wb = new ExcelJS.Workbook()
  wb.creator = 'ViperLogistics'
  const HEAD_FILL = { type: 'pattern' as const, pattern: 'solid' as const, fgColor: { argb: 'FFE8EEF9' } }
  const thin = { style: 'thin' as const, color: { argb: 'FFD0D5DD' } }
  const MONEY = '#,##0.00'

  for (const s of sheets) {
    const ws = wb.addWorksheet(s.name, { views: [{ rightToLeft: true }] })
    if (s.title) {
      ws.addRow([s.title]).font = { bold: true, size: 15 }
      ws.addRow([])
    }
    for (const [label, value] of s.pairs ?? []) {
      const row = ws.addRow([label, value])
      row.getCell(1).font = { bold: true }
      row.getCell(1).fill = HEAD_FILL
      if (typeof value === 'number' && label.includes('₪')) row.getCell(2).numFmt = MONEY
    }
    if (s.pairs?.length) ws.addRow([])
    const head = ws.addRow(s.header)
    head.font = { bold: true }
    head.eachCell((c) => {
      c.fill = HEAD_FILL
      c.border = { bottom: thin }
    })
    const firstData = ws.rowCount + 1
    for (const r of s.rows) ws.addRow(r.map((v) => v ?? ''))
    if (s.footer) {
      const f = ws.addRow(s.footer.map((v) => v ?? ''))
      f.font = { bold: true }
      f.eachCell((c) => (c.border = { top: thin }))
    }
    for (const col of s.money) {
      for (let r = firstData; r <= ws.rowCount; r++) ws.getRow(r).getCell(col + 1).numFmt = MONEY
    }
    s.widths.forEach((w, i) => (ws.getColumn(i + 1).width = w))
  }
  return new Uint8Array((await wb.xlsx.writeBuffer()) as ArrayBuffer)
}

/** בונה את ה-ZIP של החודש ומוריד אותו. `loadPdf` מביא קובץ לפי מזהה. */
export async function exportInvoicesZip(
  board: InvoicesBoard,
  loadPdf: (id: string) => Promise<Blob>,
  onProgress?: (done: number, total: number) => void,
): Promise<void> {
  const { sheets, files } = buildInvoiceSheets(board)
  const folder = `חשבוניות-${monthKey(board.period)}`
  const entries: ZipEntry[] = [{ name: `${folder}/${folder}.xlsx`, data: await writeWorkbook(sheets) }]

  let done = 0
  onProgress?.(0, files.length)
  for (const f of files) {
    const blob = await loadPdf(f.id)
    entries.push({ name: `${folder}/${f.name}`, data: new Uint8Array(await blob.arrayBuffer()) })
    onProgress?.(++done, files.length)
  }

  const zip = buildZip(entries)
  const url = URL.createObjectURL(new Blob([zip as BlobPart], { type: 'application/zip' }))
  const a = document.createElement('a')
  a.href = url
  a.download = `${folder}.zip`
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 60_000)
}
