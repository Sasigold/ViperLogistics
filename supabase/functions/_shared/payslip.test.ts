import { describe, expect, it } from 'vitest'
import { AMOUNT_KEYS, PAYSLIP_SCHEMA, amount, bytesToBase64, employeeNo, mapLimit, normalizeReading } from './payslip'

describe('normalizeReading — מה שנשמר מקריאת עמוד', () => {
  it('תלוש מלא: החודש, הזהות והסכומים', () => {
    const r = normalizeReading({
      kind: 'payslip',
      employee_name: '  כהן   משה ',
      employee_number: '17',
      period_month: 9,
      period_year: 2026,
      page_index: 1,
      page_total: 2,
      amounts: { gross_pay: 12000, net_pay: '9,000.50', employer_pension: 780, employer_severance: null },
      notes: null,
    })
    expect(r).toEqual({
      kind: 'payslip',
      employee_name: 'כהן משה',
      employee_no: '17',
      period: '2026-09-01',
      page_index: 1,
      page_total: 2,
      amounts: { gross_pay: 12000, net_pay: 9000.5, employer_pension: 780 },
      notes: null,
    })
  })

  it('עמוד שאינו תלוש — בלי זהות ובלי סכומים, גם אם המודל החזיר', () => {
    const r = normalizeReading({ kind: 'other', employee_name: 'ריכוז', amounts: { gross_pay: 500000 } })
    expect(r.kind).toBe('other')
    expect(r.employee_name).toBeNull()
    expect(r.amounts).toEqual({})
  })

  it('חודש חלקי או לא סביר — אין חודש', () => {
    expect(normalizeReading({ period_month: 13, period_year: 2026 }).period).toBeNull()
    expect(normalizeReading({ period_month: 5 }).period).toBeNull()
    expect(normalizeReading({ period_month: 5, period_year: 1999 }).period).toBeNull()
  })

  it('"דף 3 מתוך 2" אינו מספור — האינדקס נזרק', () => {
    const r = normalizeReading({ page_index: 3, page_total: 2 })
    expect(r.page_index).toBeNull()
    expect(r.page_total).toBe(2)
  })

  it('תשובה שבורה אינה מפילה — עמוד תלוש ריק', () => {
    expect(normalizeReading(null)).toMatchObject({ kind: 'payslip', amounts: {}, period: null })
  })
})

describe('employeeNo — מספר עובד, לעולם לא תעודת זהות', () => {
  it('מנקה רווחים וסימנים', () => {
    expect(employeeNo(' 00 17 ')).toBe('0017')
    expect(employeeNo(42)).toBe('42')
  })
  it('תשע ספרות בדיוק הן ת.ז. — נזרקות', () => {
    expect(employeeNo('012345678')).toBeNull()
    expect(employeeNo('01234567-8')).toBeNull()
  })
  it('ריק — null', () => {
    expect(employeeNo('')).toBeNull()
    expect(employeeNo(null)).toBeNull()
  })
})

describe('amount', () => {
  it('מעגל לאגורות ומקבל מחרוזת עם פסיקים ו-₪', () => {
    expect(amount(1234.567)).toBe(1234.57)
    expect(amount('₪ 1,234.5')).toBe(1234.5)
  })
  it('דוחה מה שאינו מספר סופי או גדול מהעמודה', () => {
    expect(amount('abc')).toBeNull()
    expect(amount(Number.NaN)).toBeNull()
    expect(amount(1e10)).toBeNull()
    expect(amount(null)).toBeNull()
  })
})

describe('PAYSLIP_SCHEMA', () => {
  it('כל רכיב בסכמה הוא עמודה, וכולם חובה (structured outputs)', () => {
    const a = PAYSLIP_SCHEMA.properties.amounts
    expect(Object.keys(a.properties).sort()).toEqual([...AMOUNT_KEYS].sort())
    expect([...a.required].sort()).toEqual([...AMOUNT_KEYS].sort())
    expect([...PAYSLIP_SCHEMA.required].sort()).toEqual(Object.keys(PAYSLIP_SCHEMA.properties).sort())
  })
})

describe('bytesToBase64', () => {
  it('זהה ל-Buffer, גם מעל גודל המנה', () => {
    const bytes = new Uint8Array(100_000).map((_, i) => (i * 31) % 256)
    expect(bytesToBase64(bytes)).toBe(Buffer.from(bytes).toString('base64'))
  })
})

describe('mapLimit', () => {
  it('שומר על הסדר ואינו עובר את המגבלה', async () => {
    let active = 0
    let peak = 0
    const out = await mapLimit([30, 10, 20, 5, 15], 2, async (ms) => {
      active++
      peak = Math.max(peak, active)
      await new Promise((r) => setTimeout(r, ms))
      active--
      return ms * 2
    })
    expect(out).toEqual([60, 20, 40, 10, 30])
    expect(peak).toBe(2)
  })
})
