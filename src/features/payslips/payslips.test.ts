import { describe, expect, it } from 'vitest'
import { PDFDocument, StandardFonts } from 'pdf-lib'
import type { PayslipAmounts } from '../../types/domain'
import {
  AMOUNT_KEYS,
  READ_CHUNK,
  chunks,
  costFlags,
  defaultUploadPeriod,
  groupByPeriod,
  pagePath,
  pageRangeLabel,
  parseAmountInput,
  periodLabel,
  periodOptions,
  shiftPeriod,
  slipFileName,
  slipPages,
} from './payslips'
import { PdfReadError, mergePdfs, splitPages } from './payslipPdf'
import { AMOUNT_KEYS as READ_KEYS } from '../../../supabase/functions/_shared/payslip'

const amounts = (over: Partial<PayslipAmounts> = {}): PayslipAmounts => ({
  gross_pay: 12000,
  net_pay: 9000,
  imputed_income: 1000,
  income_tax: 1200,
  employee_national_insurance: 800,
  employee_pension: 720,
  employee_study_fund: null,
  employer_pension: 780,
  employer_severance: 750,
  employer_study_fund: null,
  employer_national_insurance: 500,
  employer_other: null,
  printed_employer_cost: 13030,
  employer_contributions: 2030,
  employer_cost: 13030,
  deductions: 3000,
  source: 'reading',
  updated_at: '2026-10-01T00:00:00Z',
  ...over,
})

describe('חודשים', () => {
  it('תווית בעברית, כמו app.payslip_period_label', () => {
    expect(periodLabel('2026-09-01')).toBe('ספטמבר 2026')
    expect(periodLabel('2031-05-01')).toBe('מאי 2031')
  })
  it('הזזה חוצה שנה', () => {
    expect(shiftPeriod('2026-01-01', -1)).toBe('2025-12-01')
    expect(shiftPeriod('2025-12-01', 1)).toBe('2026-01-01')
    expect(shiftPeriod('2026-03-01', -14)).toBe('2025-01-01')
  })
  it('בהעלאה מוצע החודש הקודם', () => {
    expect(defaultUploadPeriod(new Date(2026, 9, 13))).toBe('2026-09-01')
    expect(defaultUploadPeriod(new Date(2026, 0, 2))).toBe('2025-12-01')
  })
  it('אפשרויות: מהחודש הבא אחורה', () => {
    const opts = periodOptions(new Date(2026, 9, 13), 3)
    expect(opts).toEqual(['2026-11-01', '2026-10-01', '2026-09-01', '2026-08-01', '2026-07-01'])
  })
})

describe('עמודים', () => {
  it('הנתיב בדלי', () => {
    expect(pagePath('b', 3)).toBe('b/3.pdf')
  })
  it('טווח ותווית', () => {
    expect(slipPages(3, 5)).toEqual([3, 4, 5])
    expect(pageRangeLabel(2, 2)).toBe('עמוד 2')
    expect(pageRangeLabel(2, 3)).toBe('עמודים 2–3')
  })
  it('מנות קריאה בגודל של הפונקציה', () => {
    expect(chunks(slipPages(1, 13), READ_CHUNK).map((c) => c.length)).toEqual([6, 6, 1])
  })
  it('שם קובץ להורדה', () => {
    expect(slipFileName('2026-09-01', 'משה / כהן')).toBe('תלוש 09-2026 - משה כהן.pdf')
    expect(slipFileName('2026-09-01')).toBe('תלוש 09-2026.pdf')
  })
})

describe('costFlags', () => {
  it('תלוש שלם ומתיישב — בלי הערות', () => {
    expect(costFlags(amounts())).toEqual([])
  })
  it('בלי סכומים בכלל', () => {
    expect(costFlags(null)[0].tone).toBe('info')
  })
  it('בלי ברוטו — אין עלות', () => {
    expect(costFlags(amounts({ gross_pay: null, employer_cost: null })).map((f) => f.text)).toEqual([
      'חסר ברוטו — אין עלות מעביד',
    ])
  })
  it('בלי ביטוח לאומי מעביד — העלות חלקית', () => {
    expect(costFlags(amounts({ employer_national_insurance: null, printed_employer_cost: null }))).toHaveLength(1)
  })
  it('פער מול העלות שבתלוש — מעל שקל', () => {
    expect(costFlags(amounts({ printed_employer_cost: 13500 })).map((f) => f.tone)).toEqual(['warning'])
    expect(costFlags(amounts({ printed_employer_cost: 13030.6 }))).toEqual([])
  })
})

describe('הטופס', () => {
  it('כל רכיב שהקריאה מחזירה הוא שדה בטופס, ולהפך', () => {
    expect([...AMOUNT_KEYS].sort()).toEqual([...READ_KEYS].sort())
  })
  it('קלט סכום', () => {
    expect(parseAmountInput('1,234.5')).toBe(1234.5)
    expect(parseAmountInput(' ₪ 900 ')).toBe(900)
    expect(parseAmountInput('')).toBeNull()
    expect(parseAmountInput('12a')).toBeNull()
  })
})

describe('groupByPeriod', () => {
  it('החדש ראשון, ותלוש מתקן באותו חודש באותה קבוצה', () => {
    const g = groupByPeriod([
      { id: 'a', period: '2026-08-01' },
      { id: 'b', period: '2026-09-01' },
      { id: 'c', period: '2026-08-01' },
    ])
    expect(g.map((x) => [x.period, x.slips.map((s) => s.id)])).toEqual([
      ['2026-09-01', ['b']],
      ['2026-08-01', ['a', 'c']],
    ])
  })
})

async function pdfWithPages(labels: string[]): Promise<Uint8Array> {
  const doc = await PDFDocument.create()
  const font = await doc.embedFont(StandardFonts.Helvetica)
  for (const l of labels) {
    const page = doc.addPage([200, 200])
    page.drawText(l, { x: 20, y: 100, size: 12, font })
  }
  return doc.save()
}

describe('פיצול ואיחוד', () => {
  it('כל עמוד לקובץ משלו, ושני עמודים חוזרים לקובץ אחד', async () => {
    const parts = await splitPages(await pdfWithPages(['p1', 'p2', 'p3']))
    expect(parts).toHaveLength(3)
    for (const p of parts) expect((await PDFDocument.load(p)).getPageCount()).toBe(1)
    const merged = await mergePdfs([parts[1], parts[2]])
    expect((await PDFDocument.load(merged)).getPageCount()).toBe(2)
    expect(await mergePdfs([parts[0]])).toBe(parts[0])
  })
  it('מה שאינו PDF — שגיאה בעברית', async () => {
    await expect(splitPages(new TextEncoder().encode('not a pdf'))).rejects.toBeInstanceOf(PdfReadError)
  })
})
