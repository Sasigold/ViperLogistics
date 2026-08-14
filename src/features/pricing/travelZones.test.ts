/**
 * החשבון שמזין את מפת אזורי הנסיעה.
 *
 * הוא נבדק כאן ולא דרך המסך כי המרחק מהמחסן הוא מה שהמשתמש שופט לפיו את זמן
 * הנסיעה שהוא מזין — והזמן הזה מאריך משמרות ומחשב שכר. טעות בו אינה טעות
 * תצוגה.
 */
import { describe, expect, it } from 'vitest'
import { haversineKm, impliedSpeedKmh, nearestWarehouse, roundTripHours, zoneCenter } from './travelZones'
import type { PricingZone, Warehouse } from '../../types/domain'

const warehouse = (over: Partial<Warehouse>): Warehouse => ({
  id: 'w1',
  name: 'מחסן',
  address: null,
  lat: null,
  lng: null,
  radius_m: null,
  color: '#3563f0',
  notes: null,
  is_active: true,
  sort_order: 0,
  ...over,
})

const zone = (over: Partial<PricingZone>): PricingZone => ({
  id: 'z1',
  customer_id: null,
  name: 'אזור',
  shape: 'polygon',
  points: null,
  center_lat: null,
  center_lng: null,
  radius_km: null,
  travel_hours: 0.5,
  surcharge: 0,
  priority: 100,
  color: '#3563f0',
  notes: null,
  is_active: true,
  deleted_at: null,
  ...over,
})

describe('haversineKm', () => {
  it('תל אביב–ירושלים ≈ 54 ק״מ', () => {
    expect(Math.round(haversineKm([32.0853, 34.7818], [31.7683, 35.2137]))).toBe(54)
  })

  it('אותה נקודה = אפס', () => {
    expect(haversineKm([32.0853, 34.7818], [32.0853, 34.7818])).toBe(0)
  })
})

describe('zoneCenter', () => {
  it('עיגול מיוצג במרכזו', () => {
    expect(zoneCenter(zone({ shape: 'circle', center_lat: 32, center_lng: 34.8, radius_km: 10 }))).toEqual([32, 34.8])
  })

  it('פוליגון מיוצג בממוצע הקודקודים', () => {
    const points: [number, number][] = [
      [32, 34],
      [32, 35],
      [33, 35],
      [33, 34],
    ]
    expect(zoneCenter(zone({ points }))).toEqual([32.5, 34.5])
  })

  it('גאומטריה חסרה אינה נקודה', () => {
    expect(zoneCenter(zone({ shape: 'circle' }))).toBeNull()
    expect(zoneCenter(zone({ points: [] }))).toBeNull()
  })
})

describe('nearestWarehouse', () => {
  const near = warehouse({ id: 'near', name: 'קרוב', lat: 32.1, lng: 34.8 })
  const far = warehouse({ id: 'far', name: 'רחוק', lat: 31.2, lng: 34.8 })

  it('בוחר את הקרוב ומחזיר את המרחק', () => {
    const hit = nearestWarehouse([32.0853, 34.7818], [far, near])
    expect(hit?.warehouse.id).toBe('near')
    expect(hit?.km).toBeLessThan(3)
  })

  // מחסן בלי קואורדינטות הוא מצב תקין (0022): ויתור מודע על אימות מיקום.
  it('מדלג על מחסן בלי קואורדינטות', () => {
    expect(nearestWarehouse([32, 34.8], [warehouse({ id: 'blind' })])).toBeNull()
  })

  it('בלי נקודה אין מה למדוד', () => {
    expect(nearestWarehouse(null, [near])).toBeNull()
  })
})

describe('impliedSpeedKmh', () => {
  it('35 ק״מ בחצי שעה = 70 קמ״ש', () => {
    expect(impliedSpeedKmh(35, 0.5)).toBe(70)
  })

  it('בלי זמן או בלי מרחק אין מהירות', () => {
    expect(impliedSpeedKmh(35, 0)).toBeNull()
    expect(impliedSpeedKmh(35, null)).toBeNull()
    expect(impliedSpeedKmh(null, 0.5)).toBeNull()
    expect(impliedSpeedKmh(0, 0.5)).toBeNull()
  })
})

describe('roundTripHours', () => {
  it('הלוך-חזור הוא כפול הכיוון האחד', () => {
    expect(roundTripHours(0.75)).toBe(1.5)
  })

  it('אזור בלי זמן נסיעה אינו מאריך משמרת', () => {
    expect(roundTripHours(null)).toBe(0)
  })
})
