/**
 * ההכרעות של שורת המשמרת בדוח הנוכחות.
 *
 * הן נבדקות כאן ולא דרך המסך משתי סיבות: הן מכריעות מה העובד רואה על השעות
 * שלו — "חסר" מול "נוכח" — ואותה פונקציה מזינה גם את השורה וגם את אריח
 * "שעות חסרות", כך שסטייה ביניהן היא דוח שסותר את עצמו.
 */
import { describe, expect, it } from 'vitest'
import {
  SHORTFALL_TOLERANCE_H,
  clockPointUrl,
  fmtCoords,
  fmtWorkEnd,
  shiftEndLocation,
  shiftLocation,
  shiftShortfall,
  shiftTone,
} from './shiftFormat'
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

describe('shiftLocation', () => {
  const at = (over: Partial<Parameters<typeof shiftLocation>[0]> = {}) => ({
    clock_in_place: null,
    work_place: null,
    work_site: null,
    ...over,
  })

  it('דיווח ידני מציג את המיקום שנכתב בו', () => {
    expect(shiftLocation(at({ clock_in_place: 'המחסן בראשון' }))).toBe('המחסן בראשון')
  })

  it('המלל שנכתב על הרשומה גובר על המחסן הגזור', () => {
    expect(
      shiftLocation(at({ clock_in_place: 'אולמי הגן', work_place: 'מרכז לוגיסטי', work_site: 'warehouse' })),
    ).toBe('אולמי הגן')
  })

  it('משמרת שיצאה ממחסן מציגה את שמו ולא את המילה "מחסן"', () => {
    expect(shiftLocation(at({ work_place: 'מרכז לוגיסטי', work_site: 'warehouse' }))).toBe('מרכז לוגיסטי')
  })

  it('בלי שם מחסן נשאר סוג האתר', () => {
    expect(shiftLocation(at({ work_site: 'warehouse' }))).toBe('מחסן')
    expect(shiftLocation(at({ work_site: 'field' }))).toBe('שטח')
  })

  // מיקום שהומצא הוא מה שהיה כאן קודם: כל דיווח ידני הוצג כאילו היה במחסן
  it('כשאין מה לומר לא נאמר דבר', () => {
    expect(shiftLocation(at())).toBeNull()
    expect(shiftLocation(at({ clock_in_place: '   ' }))).toBeNull()
  })
})

/**
 * הקצה השני של אותה שורה. הוא נבדק בנפרד כי הוא נשען על שדות אחרים לגמרי —
 * ‏`clock_out_place` ולא `clock_in_place`, והמחסן שחוזרים אליו ולא זה שיוצאים
 * ממנו — ומשמרת שיצאה מהמחסן וסיימה בשטח היא בדיוק המקרה שבו שתי הפונקציות
 * חייבות לענות תשובות שונות (0166).
 */
describe('shiftEndLocation', () => {
  const at = (over: Partial<Parameters<typeof shiftEndLocation>[0]> = {}) => ({
    clock_out_place: null,
    end_work_place: null,
    end_work_site: null,
    ...over,
  })

  it('מציג את המחסן שחוזרים אליו', () => {
    expect(shiftEndLocation(at({ end_work_place: 'מרכז לוגיסטי', end_work_site: 'warehouse' }))).toBe(
      'מרכז לוגיסטי',
    )
  })

  it('והמלל שנכתב על הרשומה גובר גם כאן', () => {
    expect(
      shiftEndLocation(at({ clock_out_place: 'אולמי הגן', end_work_place: 'מרכז לוגיסטי', end_work_site: 'warehouse' })),
    ).toBe('אולמי הגן')
  })

  it('משמרת שנגמרה בשטח אומרת שטח', () => {
    expect(shiftEndLocation(at({ end_work_site: 'field' }))).toBe('שטח')
  })

  it('ובלי סיום ידוע לא נאמר דבר', () => {
    expect(shiftEndLocation(at())).toBeNull()
  })

  // זה המקרה שבגללו יש שתי פונקציות ולא אחת
  it('יציאה מהמחסן וסיום בשטח הן שתי תשובות שונות לאותה שורה', () => {
    const row = {
      clock_in_place: null,
      work_place: 'מרכז לוגיסטי',
      work_site: 'warehouse' as const,
      clock_out_place: null,
      end_work_place: null,
      end_work_site: 'field' as const,
    }
    expect(shiftLocation(row)).toBe('מרכז לוגיסטי')
    expect(shiftEndLocation(row)).toBe('שטח')
  })
})

/**
 * הנקודה שנדגמה בהחתמה. שתי הפונקציות מחזירות null על אותו קלט חסר, כי
 * חצי נקודה אינה מקום — ורוחב וגובה שנכתבו זה בלי זה הם סיכה על קו המשווה.
 */
describe('clockPointUrl / fmtCoords', () => {
  it('בונה קישור עם סיכה על הנקודה', () => {
    expect(clockPointUrl(32.1, 34.8)).toBe(
      'https://www.openstreetmap.org/?mlat=32.1&mlon=34.8#map=17/32.1/34.8',
    )
  })

  it('בלי נקודה אין קישור', () => {
    expect(clockPointUrl(null, 34.8)).toBeNull()
    expect(clockPointUrl(32.1, null)).toBeNull()
    expect(clockPointUrl(undefined, undefined)).toBeNull()
  })

  it('הנקודה נכתבת בחמש ספרות אחרי הנקודה', () => {
    expect(fmtCoords(32.1, 34.8)).toBe('32.10000, 34.80000')
    expect(fmtCoords(null, 34.8)).toBeNull()
  })

  // אפס הוא קו המשווה, לא "אין נקודה"
  it('אפס אינו היעדר', () => {
    expect(fmtCoords(0, 0)).toBe('0.00000, 0.00000')
    expect(clockPointUrl(0, 0)).not.toBeNull()
  })
})

/**
 * ‏`shift_end` נושא בתוכו את הנסיעה חזרה למחסן (0079 §4), ולכן זו הפונקציה
 * היחידה שמפרידה בין "סיימנו לעבוד" ל"הגענו". מ-0159 היא גם מה שכתוב לעובד
 * במגירת המשמרת במקום משך הנסיעה, ולכן הטעות בה היא שעה שגויה על המסך ולא
 * מספר עזר.
 *
 * הזמנים כאן נכתבים בלי אזור זמן במכוון: `parseISO` קורא אותם כשעון מקומי,
 * וכך הבדיקה אומרת את אותו דבר בכל מכונה שהיא רצה בה.
 */
describe('fmtWorkEnd', () => {
  it('מחסירה את הנסיעה משעת הסיום', () => {
    expect(fmtWorkEnd('2024-05-23T17:00:00', 1)).toBe('16:00')
  })

  it('גם כשהיא חצי שעה', () => {
    expect(fmtWorkEnd('2024-05-23T17:00:00', 0.5)).toBe('16:30')
  })

  it('חציית חצות מחזירה את השעה של היום שלפני', () => {
    expect(fmtWorkEnd('2024-05-24T00:30:00', 1)).toBe('23:30')
  })

  it('בלי נסיעה אין שתי שעות, ולכן אין מה להציג', () => {
    expect(fmtWorkEnd('2024-05-23T17:00:00', 0)).toBe('')
    expect(fmtWorkEnd('2024-05-23T17:00:00', null)).toBe('')
    expect(fmtWorkEnd('2024-05-23T17:00:00', undefined)).toBe('')
  })
})
