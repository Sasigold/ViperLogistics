/**
 * ההכרעות של שורת המשמרת בדוח הנוכחות.
 *
 * הן נבדקות כאן ולא דרך המסך משתי סיבות: הן מכריעות מה העובד רואה על השעות
 * שלו — "חסר" מול "נוכח" — ואותה פונקציה מזינה גם את השורה וגם את אריח
 * "שעות חסרות", כך שסטייה ביניהן היא דוח שסותר את עצמו.
 */
import { describe, expect, it } from 'vitest'
import { SHORTFALL_TOLERANCE_H, shiftShortfall, shiftTone } from './shiftFormat'
import type { AttendanceReportRow } from '../../types/domain'

type ToneInput = Parameters<typeof shiftTone>[0]

const shift = (over: Partial<ToneInput> = {}): ToneInput => ({
  status: 'approved',
  clock_out_at: '2024-05-23T14:00:00Z',
  planned_hours: 9,
  actual_hours: 9,
  pay: { version: 1, paid_hours: 9, worked_hours: 9, base_hours: 9, overtime_hours: 0, topup_hours: 0, is_rest_day: false },
  ...over,
}) as AttendanceReportRow

describe('shiftShortfall', () => {
  it('מודד את הפער בין המתוכנן לבפועל', () => {
    expect(shiftShortfall(9, 7)).toBe(2)
  })

  it('משמרת מלאה אינה חסרה', () => {
    expect(shiftShortfall(9, 9)).toBe(0)
  })

  it('שעות מעבר למתוכנן אינן חוסר שלילי', () => {
    expect(shiftShortfall(9, 10.5)).toBe(0)
  })

  it('משמרת בלי שיבוץ אינה חסרה — אין מולה מה להשוות', () => {
    expect(shiftShortfall(null, 4)).toBe(0)
    expect(shiftShortfall(0, 4)).toBe(0)
  })

  it('פער של פחות מדקה הוא עיגול ולא חוסר', () => {
    expect(shiftShortfall(9, 9 - SHORTFALL_TOLERANCE_H / 2)).toBe(0)
    expect(shiftShortfall(9, 9 - SHORTFALL_TOLERANCE_H)).toBeCloseTo(SHORTFALL_TOLERANCE_H, 10)
  })

  it('החתמה בלי שעות בפועל חסרה את כל המשמרת', () => {
    expect(shiftShortfall(9, null)).toBe(9)
  })
})

describe('shiftTone', () => {
  it('משמרת מאושרת ומלאה היא נוכחות', () => {
    expect(shiftTone(shift())).toBe('present')
  })

  it('שעות נוספות גוברות על נוכחות רגילה', () => {
    expect(shiftTone(shift({ actual_hours: 10.5, pay: { ...shift().pay, overtime_hours: 1.5 } }))).toBe('overtime')
  })

  it('שעות שנפלו מהמתוכנן מסומנות כחוסר', () => {
    expect(shiftTone(shift({ actual_hours: 7 }))).toBe('short')
  })

  it('ממתין לאישור גובר גם על משמרת שהשעות בה מושלמות', () => {
    expect(shiftTone(shift({ status: 'pending' }))).toBe('pending')
  })

  it('נדחה גובר על החוסר שבתוכו', () => {
    expect(shiftTone(shift({ status: 'rejected', actual_hours: 7 }))).toBe('rejected')
  })

  it('משמרת פתוחה אינה חסרה — היא פשוט לא הסתיימה', () => {
    expect(shiftTone(shift({ clock_out_at: null, actual_hours: null }))).toBe('open')
  })

  it('משמרת בלי שיבוץ נחשבת נוכחות מלאה', () => {
    expect(shiftTone(shift({ planned_hours: null, actual_hours: 3 }))).toBe('present')
  })
})
