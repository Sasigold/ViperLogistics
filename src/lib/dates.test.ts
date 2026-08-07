import { describe, expect, it } from 'vitest'
import { fmtDate, fmtHours, fmtMoney, fmtTime, toISODate } from './dates'

/**
 * העיצוב כאן הוא המקום היחיד שממיר שעות עשרוניות למה שאדם קורא, והוא מזין
 * את דוח הנוכחות. טעות עיגול כאן היא טעות בשעות שמישהו רואה כשכר שלו.
 */

describe('fmtHours', () => {
  it('splits a decimal hour into hours and minutes', () => {
    expect(fmtHours(1.5)).toBe('1:30')
    expect(fmtHours(8)).toBe('8:00')
    expect(fmtHours(0.25)).toBe('0:15')
  })

  it('pads the minutes so the column stays aligned', () => {
    expect(fmtHours(2.1)).toBe('2:06')
  })

  it('rounds to the nearest minute rather than truncating', () => {
    // 7.999h הוא 479.94 דקות — 480 ולא 479, אחרת 8 שעות מוצגות כ-7:59
    expect(fmtHours(7.999)).toBe('8:00')
  })

  it('carries into the next hour when rounding crosses 60', () => {
    expect(fmtHours(1.9999)).toBe('2:00')
  })

  it('gives back nothing for nothing, and does not print 0:00 for null', () => {
    expect(fmtHours(null)).toBe('')
    expect(fmtHours(undefined)).toBe('')
    expect(fmtHours(0)).toBe('0:00')
  })
})

describe('fmtTime', () => {
  it('drops the seconds Postgres sends on a time column', () => {
    expect(fmtTime('07:00:00')).toBe('07:00')
    expect(fmtTime('18:30')).toBe('18:30')
  })

  it('stays empty for a missing time', () => {
    expect(fmtTime(null)).toBe('')
  })
})

describe('fmtDate', () => {
  it('renders a date-only string as day/month/year', () => {
    expect(fmtDate('2026-03-09')).toBe('09/03/2026')
  })

  it('stays empty rather than printing Invalid Date', () => {
    expect(fmtDate(null)).toBe('')
    expect(fmtDate(undefined)).toBe('')
    expect(fmtDate('')).toBe('')
  })
})

describe('toISODate', () => {
  it('formats in local time, so a date does not slip a day near midnight', () => {
    // toISOString() היה מחזיר כאן את היום הקודם בכל אזור זמן חיובי
    expect(toISODate(new Date(2026, 2, 9, 0, 30))).toBe('2026-03-09')
  })
})

describe('fmtMoney', () => {
  it('stays empty for null instead of showing ₪0', () => {
    expect(fmtMoney(null)).toBe('')
    expect(fmtMoney(undefined)).toBe('')
  })

  it('renders a shekel amount', () => {
    expect(fmtMoney(400)).toContain('400')
  })
})
