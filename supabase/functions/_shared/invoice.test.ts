import { describe, expect, it } from 'vitest'
import {
  INVOICE_SCHEMA,
  base64UrlToBytes,
  bytesToBase64Url,
  findAttachments,
  gmailQuery,
  header,
  isoDate,
  money,
  normalizeInvoice,
  safeReturnUrl,
  sha256Hex,
  signState,
  verifyState,
} from './invoice'

describe('normalizeInvoice — מה שנשמר מקריאת חשבונית', () => {
  it('חשבונית מלאה', () => {
    const r = normalizeInvoice({
      kind: 'invoice',
      doc_type: 'tax_invoice',
      vendor_name: '  פז   חברת נפט ',
      vendor_tax_id: '520-000-000',
      invoice_number: 'A-100',
      issue_date: '14/03/2026',
      currency: '₪',
      amount_before_vat: '1,000.00',
      vat_amount: 180,
      total_amount: 1180,
      category: 'fuel',
      description: 'דלק',
      recipient_name: 'וייפר מיקור חוץ',
      recipient_tax_id: '51-555123-4',
      lines: [
        { description: 'סולר', quantity: 150, unit_price: 6.666, total: 1000 },
        { description: '   ', quantity: null, unit_price: null, total: 5 },
      ],
      notes: null,
    })
    expect(r).toMatchObject({
      kind: 'invoice',
      vendor_name: 'פז חברת נפט',
      vendor_tax_id: '520000000',
      issue_date: '2026-03-14',
      currency: 'ILS',
      amount_before_vat: 1000,
      vat_amount: 180,
      total_amount: 1180,
      recipient_tax_id: '515551234',
    })
    expect(r.lines).toEqual([{ description: 'סולר', quantity: 150, unit_price: 6.67, total: 1000 }])
  })

  it('זיכוי — הסכומים שליליים גם כשנקראו חיוביים', () => {
    const r = normalizeInvoice({ doc_type: 'credit', amount_before_vat: 50, vat_amount: -9, total_amount: 59 })
    expect([r.amount_before_vat, r.vat_amount, r.total_amount]).toEqual([-50, -9, -59])
  })

  it('לפני מע"מ נגזר כשרק הסה"כ והמע"מ מודפסים', () => {
    expect(normalizeInvoice({ total_amount: 118, vat_amount: 18 }).amount_before_vat).toBe(100)
  })

  it('ערכים לא מוכרים נופלים לברירת מחדל', () => {
    const r = normalizeInvoice({ doc_type: 'x', category: 'y', currency: 'dollars', issue_date: '2026-02-30' })
    expect([r.doc_type, r.category, r.currency, r.issue_date]).toEqual(['other', 'other', 'ILS', null])
    expect(normalizeInvoice(null).kind).toBe('invoice')
  })

  it('הסכמה עומדת במגבלת 16 השדות ה-nullable', () => {
    const count = (o: unknown): number => {
      if (!o || typeof o !== 'object') return 0
      const x = o as Record<string, unknown>
      let n = Array.isArray(x.anyOf) ? 1 : 0
      for (const v of Object.values(x)) n += count(v)
      return n
    }
    expect(count(INVOICE_SCHEMA)).toBeLessThanOrEqual(16)
  })
})

describe('עזרים', () => {
  it('money', () => {
    expect(money('1,234.567 ₪')).toBe(1234.57)
    expect(money('abc')).toBeNull()
    expect(money(1e10)).toBeNull()
  })
  it('isoDate', () => {
    expect(isoDate('2026-12-31')).toBe('2026-12-31')
    expect(isoDate('1.2.2026')).toBe('2026-02-01')
    expect(isoDate('1999-01-01')).toBeNull()
  })
  it('base64url הלוך ושוב', () => {
    const bytes = new Uint8Array([0, 251, 255, 62, 63, 1])
    expect(base64UrlToBytes(bytesToBase64Url(bytes))).toEqual(bytes)
  })
  it('sha256', async () => {
    expect(await sha256Hex(new TextEncoder().encode('abc'))).toBe(
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    )
  })
})

describe('Gmail', () => {
  const now = new Date('2026-10-14T12:00:00Z')

  it('סריקה ראשונה — 60 יום אחורה; אחר כך יומיים לפני הסריקה המלאה', () => {
    const first = gmailQuery('', null, now)
    expect(first).toContain(`after:${Math.floor((now.getTime() - 60 * 86_400_000) / 1000)}`)
    const next = gmailQuery('from:billing@x.com', '2026-10-10T00:00:00Z', now)
    expect(next).toContain(`after:${Math.floor(Date.parse('2026-10-08T00:00:00Z') / 1000)}`)
    expect(next.endsWith('(from:billing@x.com)')).toBe(true)
  })

  it('הקבצים המצורפים: PDF תמיד, תמונה רק כשאינה זעירה', () => {
    const atts = findAttachments({
      mimeType: 'multipart/mixed',
      headers: [{ name: 'Subject', value: 'חשבונית' }],
      parts: [
        { partId: '0', mimeType: 'text/html', filename: '', body: { size: 100 } },
        { partId: '1', mimeType: 'application/octet-stream', filename: 'INV-1.PDF', body: { attachmentId: 'a1', size: 5000 } },
        { partId: '2', mimeType: 'image/png', filename: 'logo.png', body: { attachmentId: 'a2', size: 2000 } },
        {
          partId: '3',
          mimeType: 'multipart/related',
          parts: [{ partId: '3.1', mimeType: 'image/jpeg', filename: 'scan.jpg', body: { attachmentId: 'a3', size: 400_000 } }],
        },
        { partId: '4', mimeType: 'application/pdf', filename: 'huge.pdf', body: { attachmentId: 'a4', size: 50_000_000 } },
      ],
    })
    expect(atts.map((a) => [a.filename, a.mimeType])).toEqual([
      ['INV-1.PDF', 'application/pdf'],
      ['scan.jpg', 'image/jpeg'],
    ])
    expect(header({ headers: [{ name: 'subject', value: 'x' }] }, 'Subject')).toBe('x')
  })
})

describe('OAuth state', () => {
  it('חתום, מאומת, ופג', async () => {
    const token = await signState({ p: 'prof', r: 'https://app.example.com/invoices', e: 2000 }, 'sec')
    expect(await verifyState(token, 'sec', 1000)).toEqual({ p: 'prof', r: 'https://app.example.com/invoices', e: 2000 })
    expect(await verifyState(token, 'other', 1000)).toBeNull()
    expect(await verifyState(token, 'sec', 3000)).toBeNull()
    const [body, sig] = token.split('.')
    expect(await verifyState(`${body}x.${sig}`, 'sec', 1000)).toBeNull()
  })

  it('כתובת חזרה', () => {
    expect(safeReturnUrl('https://app.example.com/invoices')).toBe('https://app.example.com/invoices')
    expect(safeReturnUrl('http://localhost:5173/invoices')).toBe('http://localhost:5173/invoices')
    expect(safeReturnUrl('http://evil.com')).toBeNull()
    expect(safeReturnUrl('javascript:alert(1)')).toBeNull()
    expect(safeReturnUrl('https://u:p@x.com')).toBeNull()
  })
})
