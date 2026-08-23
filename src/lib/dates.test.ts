import { describe, expect, it } from 'vitest'
import { fmtDate, fmtHours, fmtMoney, fmtTime, fmtWeekday, fmtWeekdayShort, toISODate } from './dates'

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

describe('fmtWeekday', () => {
  it('names the day above the date in the board', () => {
    // 09/03/2026 הוא יום שני
    expect(fmtWeekday('2026-03-09')).toBe('יום שני')
    expect(fmtWeekday('2026-03-13')).toBe('יום שישי')
  })

  it('calls Saturday by its name, without "יום" before it', () => {
    expect(fmtWeekday('2026-03-14')).toBe('שבת')
    expect(fmtWeekdayShort('2026-03-14')).toBe('שבת')
  })

  it('shortens to the form a narrow day column can hold', () => {
    expect(fmtWeekdayShort('2026-03-08')).toBe('יום א׳')
    expect(fmtWeekdayShort('2026-03-09')).toBe('יום ב׳')
    expect(fmtWeekdayShort('2026-03-13')).toBe('יום ו׳')
  })

  it('reads the local day, so a date does not slip near midnight', () => {
    // parseISO של תאריך-בלבד הוא חצות מקומית; toISOString היה מזיז אותו יום
    expect(fmtWeekday(new Date(2026, 2, 9, 0, 30))).toBe('יום שני')
    expect(fmtWeekday(new Date(2026, 2, 9, 23, 30))).toBe('יום שני')
  })

  it('stays empty for nothing rather than printing Invalid Date', () => {
    expect(fmtWeekday(null)).toBe('')
    expect(fmtWeekday(undefined)).toBe('')
    expect(fmtWeekdayShort('')).toBe('')
  })
})
