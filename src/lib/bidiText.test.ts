import { beforeAll, describe, expect, it } from 'vitest'
import { loadBidi, visualRuns } from './bidiText'

beforeAll(async () => {
  await loadBidi()
})

const RTL = /[֐-ࣿיִ-﷿ﹰ-﻿]/

/**
 * מה שיֵראה על הנייר, משמאל לימין.
 *
 * הבדיקה מדמה את מה ש-fontkit עושה — הופכת כל רצף שיש בו אות ימנית —
 * ומשרשרת. כך היא בודקת את מה שחשוב באמת: לא איך נחתכו הרצפים, אלא איזו
 * שורה יוצאת בסוף. הפונקציה חייבת להישאר תמונת מראה של ההנחה שב-bidiText,
 * ואם fontkit ישנה התנהגות, השתיים ייפרדו והבדיקות ייפלו — וזו הכוונה.
 */
const rendered = (s: string) =>
  visualRuns(s)
    .map((r) => (RTL.test(r.text) ? [...r.text].reverse().join('') : r.text))
    .join('')

/** מילה עברית כפי שהיא נראית כשמצירים אותה משמאל לימין. */
const rev = (s: string) => [...s].reverse().join('')

describe('visualRuns', () => {
  it('עברית טהורה נמסרת בסדר לוגי — ההיפוך של fontkit הוא שמציב אותה', () => {
    expect(visualRuns('שלום')).toEqual([{ text: 'שלום', rtl: true }])
    expect(rendered('שלום')).toBe(rev('שלום'))
  })

  it('לטינית טהורה נמסרת כפי שהיא ואינה נוגעת ב-fontkit', () => {
    expect(visualRuns('Viper Logistics')).toEqual([{ text: 'Viper Logistics', rtl: false }])
  })

  it('הספרות אינן מתהפכות עם העברית שלצדן', () => {
    // זה הבאג שבגללו הקובץ קיים: מחרוזת אחת הייתה מציירת 847667615.
    expect(rendered('ח.פ 516766748')).toBe('516766748 ' + rev('ח.פ'))
  })

  it('תאריך ושעה נשארים בסדר שלהם בתוך שורה עברית', () => {
    expect(rendered('הקמה 12/09/2026 08:00')).toBe('08:00 12/09/2026 ' + rev('הקמה'))
  })

  it('סימן השקל יושב בקצה השמאלי של הסכום', () => {
    expect(rendered('סה״כ 1,180 ₪')).toBe('₪ 1,180 ' + rev('סה״כ'))
  })

  it('סוגריים מתהפכים, ולא רק זזים', () => {
    expect(rendered('הצעה (גרסה 2)')).toBe('(2 ' + rev('גרסה') + ') ' + rev('הצעה'))
  })

  it('מייל וטלפון נשארים קריאים', () => {
    expect(rendered('office@viper-tech.co.il')).toBe('office@viper-tech.co.il')
    expect(rendered('טלפון 050-1234567')).toBe('050-1234567 ' + rev('טלפון'))
  })

  it('מחרוזת ריקה אינה מייצרת רצפים', () => {
    expect(visualRuns('')).toEqual([])
  })
})
