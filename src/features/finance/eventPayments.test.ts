import { describe, expect, it } from 'vitest'
import {
  commissionError,
  commissionNote,
  lineLabel,
  matchesFilter,
  overpayWarning,
  parseAmount,
  parseCommission,
  paymentState,
  presetRange,
  rangeError,
} from './eventPayments'

describe('paymentState', () => {
  it('reads the five states', () => {
    expect(paymentState(50000, 50000)).toBe('paid')
    expect(paymentState(50000, 20000)).toBe('partial')
    expect(paymentState(50000, 0)).toBe('unpaid')
    expect(paymentState(50000, 60000)).toBe('credit')
    expect(paymentState(0, 0)).toBe('none')
  })

  it('a cancelled event that was paid is a credit, not "paid"', () => {
    expect(paymentState(0, 1000)).toBe('credit')
  })

  it('does not see a debt in floating-point dust', () => {
    expect(paymentState(0.3, 0.1 + 0.2)).toBe('paid')
  })
})

describe('matchesFilter', () => {
  it('"open" is everything with a balance left', () => {
    expect(matchesFilter(100, 0, 'open')).toBe(true)
    expect(matchesFilter(100, 40, 'open')).toBe(true)
    expect(matchesFilter(100, 100, 'open')).toBe(false)
    expect(matchesFilter(0, 0, 'open')).toBe(false)
  })

  it('each state filter is exactly that state', () => {
    expect(matchesFilter(100, 40, 'partial')).toBe(true)
    expect(matchesFilter(100, 40, 'unpaid')).toBe(false)
    expect(matchesFilter(100, 100, 'paid')).toBe(true)
    expect(matchesFilter(100, 0, 'all')).toBe(true)
  })
})

describe('lineLabel', () => {
  it('a share below 100% is a commission', () => {
    expect(lineLabel({ label: 'ריהוט ישן', pct: 70 })).toBe('עמלה — ריהוט ישן')
  })

  it('a full line and the logistics line keep their names', () => {
    expect(lineLabel({ label: 'הובלות', pct: 100 })).toBe('הובלות')
    expect(lineLabel({ label: 'לוגיסטיקה', pct: null })).toBe('לוגיסטיקה')
  })
})

describe('parseAmount', () => {
  it('accepts money the way people type it', () => {
    expect(parseAmount('20000')).toBe(20000)
    expect(parseAmount('20,000')).toBe(20000)
    expect(parseAmount('₪ 1,250.5')).toBe(1250.5)
    expect(parseAmount(' 99.99 ')).toBe(99.99)
  })

  it('rejects what the server would reject', () => {
    expect(parseAmount('')).toBeNull()
    expect(parseAmount('0')).toBeNull()
    expect(parseAmount('-50')).toBeNull()
    expect(parseAmount('10.555')).toBeNull()
    expect(parseAmount('abc')).toBeNull()
  })
})

describe('overpayWarning', () => {
  it('is silent within the balance', () => {
    expect(overpayWarning(20000, 50000)).toBeNull()
    expect(overpayWarning(50000, 50000)).toBeNull()
    expect(overpayWarning(null, 50000)).toBeNull()
  })

  it('warns above the balance, and when nothing is due', () => {
    expect(overpayWarning(60000, 50000)).not.toBeNull()
    expect(overpayWarning(100, 0)).not.toBeNull()
  })
})

describe('presetRange', () => {
  const today = new Date(2026, 9, 6) // 6 באוקטובר 2026

  it('the month, the month before, three months, the year', () => {
    expect(presetRange('month', today)).toEqual({ from: '2026-10-01', to: '2026-10-31' })
    expect(presetRange('prev_month', today)).toEqual({ from: '2026-09-01', to: '2026-09-30' })
    expect(presetRange('quarter', today)).toEqual({ from: '2026-08-01', to: '2026-10-31' })
    expect(presetRange('year', today)).toEqual({ from: '2026-01-01', to: '2026-12-31' })
  })

  it('crosses the year boundary backwards', () => {
    expect(presetRange('prev_month', new Date(2027, 0, 15))).toEqual({ from: '2026-12-01', to: '2026-12-31' })
  })
})

describe('rangeError', () => {
  it('accepts a year, refuses more, and refuses a reversed range', () => {
    expect(rangeError('2026-01-01', '2026-12-31')).toBeNull()
    expect(rangeError('2026-01-01', '2027-06-30')).not.toBeNull()
    expect(rangeError('2026-10-31', '2026-10-01')).not.toBeNull()
    expect(rangeError('', '2026-10-01')).not.toBeNull()
  })
})

describe('manual commission (0212)', () => {
  const money = (n: number) => `${n} ₪`

  it('a manual-commission line is a commission even without a percent', () => {
    expect(lineLabel({ label: 'כיסאות', pct: null, manual_commission: true })).toBe('עמלה — כיסאות')
    expect(lineLabel({ label: 'כיסאות', pct: null, manual_commission: true, commission: 100 })).toBe('עמלה — כיסאות')
  })

  it('zero is a commission; empty, negative and three decimals are not', () => {
    expect(parseCommission('0')).toBe(0)
    expect(parseCommission('1,250.5')).toBe(1250.5)
    expect(parseCommission('₪ 100')).toBe(100)
    expect(parseCommission('')).toBeNull()
    expect(parseCommission('-5')).toBeNull()
    expect(parseCommission('1.234')).toBeNull()
  })

  it('a commission above the amount is refused, equal is fine', () => {
    expect(commissionError(1001, 1000)).toBe('העמלה גבוהה מהסכום')
    expect(commissionError(1000, 1000)).toBeNull()
    expect(commissionError(null, 1000)).toBe('סכום לא תקין')
  })

  it('says when no commission was set, when it is current, and when the spec moved', () => {
    expect(commissionNote({ gross: 1000, commission: null }, money)).toEqual({
      tone: 'warning',
      text: 'לא נקבעה עמלה · הסכום 1000 ₪',
    })
    expect(commissionNote({ gross: 1000, commission: 100, commission_basis: 1000, commission_stale: false }, money)).toEqual({
      tone: 'muted',
      text: 'עמלה ידנית מתוך 1000 ₪',
    })
    const stale = commissionNote({ gross: 2000, commission: 100, commission_basis: 1000, commission_stale: true }, money)
    expect(stale.tone).toBe('warning')
    expect(stale.text).toContain('המפרט השתנה לאחר קביעת העמלה')
    expect(stale.text).toContain('1000 ₪')
    expect(stale.text).toContain('2000 ₪')
  })
})
