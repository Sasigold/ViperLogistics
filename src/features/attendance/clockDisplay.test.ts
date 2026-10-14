import { describe, expect, it } from 'vitest'
import { clockTime, dayLabel, fmtHM, minutesBetween, overtimeState, ringArcs, shortDate } from './clockDisplay'

describe('fmtHM', () => {
  it('formats minutes as H:MM', () => {
    expect(fmtHM(0)).toBe('0:00')
    expect(fmtHM(384)).toBe('6:24')
    expect(fmtHM(59.9)).toBe('0:59')
    expect(fmtHM(-5)).toBe('0:00')
  })
})

describe('minutesBetween', () => {
  it('signs by order', () => {
    expect(minutesBetween('2026-10-14T10:00:00Z', '2026-10-14T11:30:00Z')).toBe(90)
    expect(minutesBetween('2026-10-14T11:30:00Z', '2026-10-14T10:00:00Z')).toBe(-90)
  })
})

describe('ringArcs', () => {
  it('fills the base arc proportionally', () => {
    expect(ringArcs(384, 480)).toEqual({ base: 0.8, over: 0 })
  })
  it('nothing without a planned length', () => {
    expect(ringArcs(100, 0)).toEqual({ base: 0, over: 0 })
  })
  it('splits time past the planned end into the over arc, capped at one turn', () => {
    const r = ringArcs(540, 480, 60)
    expect(r.base).toBe(1)
    expect(r.over).toBe(0)
    const late = ringArcs(420, 480, 60) // started late, already past end
    expect(late.base).toBeCloseTo(0.75)
    expect(late.over).toBeCloseTo(0.125)
  })
  it('over never exceeds worked time', () => {
    expect(ringArcs(10, 480, 60).over).toBeCloseTo(10 / 480)
  })
})

describe('overtimeState', () => {
  const end = '2026-10-14T18:00:00Z'
  it('counts down before the end, up after it', () => {
    expect(overtimeState(Date.parse('2026-10-14T16:24:00Z'), end)).toEqual({ kind: 'until', minutes: 96 })
    expect(overtimeState(Date.parse('2026-10-14T18:30:00Z'), end)).toEqual({ kind: 'over', minutes: 30 })
    expect(overtimeState(Date.now(), null)).toBeNull()
  })
})

describe('labels', () => {
  it('dayLabel names today and tomorrow', () => {
    const now = new Date(2026, 9, 14, 9, 0)
    expect(dayLabel(new Date(2026, 9, 14, 18, 0).toISOString(), now)).toBe('היום')
    expect(dayLabel(new Date(2026, 9, 15, 8, 0).toISOString(), now)).toBe('מחר')
  })
  it('clockTime and shortDate', () => {
    expect(clockTime(null)).toBe('—')
    expect(clockTime('nope')).toBe('—')
    expect(shortDate('2026-10-12')).toBe('12.10')
  })
})
