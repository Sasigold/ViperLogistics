import { describe, expect, it } from 'vitest'
import type { Invoice, InvoicesBoard } from '../../types/domain'
import { invoiceFlags, monthLabel, safeName, shiftMonth, zipEntries } from './invoices'
import { buildInvoiceSheets } from './exportInvoices'
import { buildZip, crc32 } from './zip'

const inv = (o: Partial<Invoice>): Invoice => ({
  id: 'id',
  source: 'upload',
  file_name: 'a.pdf',
  file_path: 'invoices/id.pdf',
  read_status: 'done',
  read_error: null,
  read_at: null,
  doc_type: 'tax_invoice',
  vendor_name: 'פז',
  vendor_tax_id: null,
  invoice_number: null,
  issue_date: '2026-03-14',
  period: '2026-03-01',
  currency: 'ILS',
  amount_before_vat: 100,
  vat_amount: 18,
  total_amount: 118,
  category: 'fuel',
  description: null,
  recipient_name: null,
  recipient_tax_id: null,
  company_id: null,
  company_name: null,
  notes: null,
  reviewed_at: null,
  gmail_from: null,
  gmail_subject: null,
  gmail_date: null,
  created_at: '2026-03-15T00:00:00Z',
  duplicate: false,
  lines: [],
  ...o,
})

describe('חודשים', () => {
  it('מעבר בין חודשים ותווית', () => {
    expect(shiftMonth('2026-01-01', -1)).toBe('2025-12-01')
    expect(shiftMonth('2026-12-01', 1)).toBe('2027-01-01')
    expect(monthLabel('2026-10-01')).toBe('אוקטובר 2026')
  })
})

describe('invoiceFlags', () => {
  it('נקראה ולא אושרה — לבדיקה; סכומים מתיישבים', () => {
    expect(invoiceFlags(inv({}), false)).toEqual(['unreviewed'])
  })
  it('סכומים שאינם מתיישבים, בלי סכום, ונמען שאינו שלנו', () => {
    expect(invoiceFlags(inv({ total_amount: 130, reviewed_at: 'x' }), false)).toEqual(['mismatch'])
    expect(invoiceFlags(inv({ total_amount: null, read_status: 'pending' }), false)).toEqual(['unread', 'no_total'])
    expect(invoiceFlags(inv({ recipient_name: 'משה', reviewed_at: 'x' }), true)).toEqual(['not_ours'])
  })
  it('עיגול של עד שקל אינו "לא מתיישב"', () => {
    expect(invoiceFlags(inv({ total_amount: 118.6, reviewed_at: 'x' }), false)).toEqual([])
  })
})

describe('שמות בתיקייה', () => {
  it('ממוספרים לפי תאריך, בלי תווים אסורים', () => {
    const names = zipEntries([
      inv({ id: 'b', issue_date: '2026-03-20', vendor_name: 'חברת "חשמל"/מחוז', invoice_number: 'X:1' }),
      inv({ id: 'a', issue_date: '2026-03-02', vendor_name: 'פז' }),
      inv({ id: 'c', issue_date: null, vendor_name: null }),
    ]).map((e) => e.name)
    expect(names).toEqual(['001_02-03-2026_פז.pdf', '002_20-03-2026_חברת חשמל מחוז_X 1.pdf', '003_ספק.pdf'])
  })
  it('safeName', () => {
    expect(safeName('  ')).toBe('ללא')
    expect(safeName('a\u0001b')).toBe('a b')
  })
})

describe('ייצוא', () => {
  it('הסיכום והשורות מהשרת, הקבצים לפי סדר התאריך', () => {
    const board: InvoicesBoard = {
      period: '2026-03-01',
      invoices: [
        inv({ id: 'b', issue_date: '2026-03-20', lines: [{ line_no: 1, description: 'סולר', quantity: 1, unit_price: 100, total: 100 }] }),
        inv({ id: 'a', issue_date: '2026-03-02' }),
      ],
      totals: { count: 2, before_vat: 200, vat: 36, total: 236, foreign: 0, unread: 0, unreviewed: 2, missing_total: 0 },
      categories: [{ category: 'fuel', count: 2, total: 236, vat: 36 }],
      months: [],
    }
    const { sheets, files } = buildInvoiceSheets(board)
    expect(files.map((f) => f.id)).toEqual(['a', 'b'])
    expect(sheets.map((s) => s.name)).toEqual(['סיכום', 'חשבוניות', 'שורות'])
    expect(sheets[0].pairs?.[3]).toEqual(['סה"כ כולל מע"מ (₪)', 236])
    expect(sheets[1].footer?.slice(10, 13)).toEqual([200, 36, 236])
    expect(sheets[2].rows).toEqual([[2, 'פז', '', 1, 'סולר', 1, 100, 100]])
  })
})

describe('zip', () => {
  it('crc32', () => {
    expect(crc32(new TextEncoder().encode('hello'))).toBe(0x3610a686)
  })
  it('מבנה: כותרת מקומית, ספרייה מרכזית ורשומת סיום', () => {
    const data = new TextEncoder().encode('%PDF-1.4')
    const zip = buildZip([{ name: 'חשבוניות-2026-03/001_פז.pdf', data }])
    const v = new DataView(zip.buffer)
    expect(v.getUint32(0, true)).toBe(0x04034b50)
    expect(v.getUint16(6, true) & 0x0800).toBe(0x0800)
    const nameLen = v.getUint16(26, true)
    expect(new TextDecoder().decode(zip.subarray(30, 30 + nameLen))).toBe('חשבוניות-2026-03/001_פז.pdf')
    expect(zip.subarray(30 + nameLen, 30 + nameLen + data.length)).toEqual(data)
    const end = zip.length - 22
    expect(v.getUint32(end, true)).toBe(0x06054b50)
    expect(v.getUint16(end + 10, true)).toBe(1)
    expect(v.getUint32(v.getUint32(end + 16, true), true)).toBe(0x02014b50)
  })
})
