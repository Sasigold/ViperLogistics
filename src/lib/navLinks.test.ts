import { describe, expect, it } from 'vitest'
import { navLinks } from './navLinks'

describe('navLinks', () => {
  it('prefers coordinates over the typed address', () => {
    expect(navLinks({ location_text: 'אולם הגן', location_lat: 32.08, location_lng: 34.78 })).toEqual({
      waze: 'https://waze.com/ul?ll=32.08,34.78&navigate=yes',
      google: 'https://www.google.com/maps/dir/?api=1&destination=32.08,34.78',
    })
  })
  it('falls back to the address text, encoded', () => {
    const l = navLinks({ location_text: ' הרצל 1, תל אביב ' })!
    expect(l.waze).toBe(`https://waze.com/ul?q=${encodeURIComponent('הרצל 1, תל אביב')}&navigate=yes`)
  })
  it('returns null with nothing to navigate to', () => {
    expect(navLinks({ location_text: '  ' })).toBeNull()
    expect(navLinks({ location_lat: 32, location_lng: null })).toBeNull()
  })
})
