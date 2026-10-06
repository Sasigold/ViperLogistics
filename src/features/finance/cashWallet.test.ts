import { describe, expect, it } from 'vitest'
import { entryTitle, isManual, walletRange, walletRangeError } from './cashWallet'

const base = { label: null, event_name: null, event_number: null, customer_name: null }

describe('entryTitle', () => {
  it('uses the typed label for manual rows', () => {
    expect(entryTitle({ ...base, source: 'expense', label: 'קניתי אוטו' })).toBe('קניתי אוטו')
    expect(entryTitle({ ...base, source: 'income', label: null })).toBe('הכנסה ידנית')
  })
  it('names the event of a cash payment', () => {
    expect(entryTitle({ ...base, source: 'payment', event_name: 'משפחת כהן', event_number: '12' })).toBe(
      'משפחת כהן #12',
    )
  })
  it('falls back to the customer when the event is gone', () => {
    expect(entryTitle({ ...base, source: 'payment', customer_name: 'שיא עיצובים' })).toBe('שיא עיצובים')
    expect(entryTitle({ ...base, source: 'payment' })).toBe('תשלום במזומן')
  })
})

describe('isManual', () => {
  it('only manual rows are removable from the wallet', () => {
    expect(isManual({ source: 'payment' })).toBe(false)
    expect(isManual({ source: 'expense' })).toBe(true)
    expect(isManual({ source: 'income' })).toBe(true)
  })
})

describe('walletRange', () => {
  const today = new Date(2026, 9, 6)
  it('"all" runs from the start up to today', () => {
    expect(walletRange('all', today)).toEqual({ from: '2000-01-01', to: '2026-10-06' })
  })
  it('month presets match the payments screen', () => {
    expect(walletRange('month', today)).toEqual({ from: '2026-10-01', to: '2026-10-31' })
  })
})

describe('walletRangeError', () => {
  it('rejects a reversed or empty range, and allows a long one', () => {
    expect(walletRangeError('', '2026-01-01')).not.toBeNull()
    expect(walletRangeError('2026-02-01', '2026-01-01')).not.toBeNull()
    expect(walletRangeError('2000-01-01', '2026-10-06')).toBeNull()
  })
})
