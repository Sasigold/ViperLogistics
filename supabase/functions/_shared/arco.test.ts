import { describe, expect, it } from 'vitest'
import { EVENT_KEYS, orderNumber, pick, pickSuggestion, routeFromPath, timingSafeEqual } from './arco'

describe('orderNumber', () => {
  // שלושה מקומות מיישמים את אותו כלל — כאן, ב-SQL, ובמודול ה-Firestore
  // שכבר רץ. אם אחד מהם ישתנה, הזמנה אחת תיפתח כשני אירועים.
  it('keeps digits only', () => {
    expect(orderNumber('26000233')).toBe('26000233')
    expect(orderNumber(' #26000233 ')).toBe('26000233')
    expect(orderNumber('הזמנה 26-000-233')).toBe('26000233')
  })

  it('is null when nothing is left', () => {
    expect(orderNumber('')).toBeNull()
    expect(orderNumber(null)).toBeNull()
    expect(orderNumber('---')).toBeNull()
  })
})

describe('timingSafeEqual', () => {
  it('accepts only an exact match', () => {
    expect(timingSafeEqual('secret', 'secret')).toBe(true)
    expect(timingSafeEqual('secret', 'secreT')).toBe(false)
    expect(timingSafeEqual('secret', 'secret ')).toBe(false)
    expect(timingSafeEqual('', '')).toBe(true)
  })
})

describe('pick', () => {
  it('keeps the known keys and drops the rest', () => {
    const out = pick(
      { order_number: '1', volume: 15, internal_cost: 999, note: null, location: '' },
      EVENT_KEYS,
    )
    expect(out).toEqual({ order_number: '1', volume: 15 })
  })
})

describe('pickSuggestion', () => {
  it('takes the first hit inside Israel', () => {
    const out = pickSuggestion([
      { provider: 'google', place_id: 'a', label: 'Nicosia', lat: 35.17, lng: 33.36 },
      { provider: 'google', place_id: 'b', label: 'ירושלים', lat: 31.78, lng: 35.21 },
    ])
    expect(out?.place_id).toBe('b')
  })

  it('is null when nothing usable came back', () => {
    expect(pickSuggestion([])).toBeNull()
    expect(pickSuggestion(null)).toBeNull()
    expect(pickSuggestion([{ lat: 'x', lng: 'y' }])).toBeNull()
  })
})

describe('routeFromPath', () => {
  it('reads the segment after the function name', () => {
    expect(routeFromPath('https://x.supabase.co/functions/v1/arco-intake/event')).toBe('event')
    expect(routeFromPath('https://x.supabase.co/functions/v1/arco-intake/SPEC')).toBe('spec')
    expect(routeFromPath('https://x.supabase.co/functions/v1/arco-intake')).toBe('')
  })
})
