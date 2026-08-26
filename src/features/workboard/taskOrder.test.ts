import { describe, expect, it } from 'vitest'
import { byTaskDateTime, byTaskTime } from './grouping'

/* מה שנבדק כאן הוא הכלל ששני מסכים חולקים: הלו״ז ממיין בו את היום, ודף
   האירוע מסדר בו את ההקמה מול הפירוק. המקרה שבגללו הוא נכתב הוא היום שבו
   הפירוק קודם — פירוק ב-06:00 של ציוד מאתמול והקמה ב-18:00 לערב. */

const t = (onsite: string | null, warehouse: string | null = null, date = '2026-03-01') => ({
  task_date: date,
  onsite_start_time: onsite,
  warehouse_start_time: warehouse,
})

describe('byTaskTime', () => {
  it('שעת השטח קובעת', () => {
    expect(byTaskTime(t('06:00'), t('18:00'))).toBeLessThan(0)
    expect(byTaskTime(t('18:00'), t('06:00'))).toBeGreaterThan(0)
  })

  it('שעה חסרה שוקעת לתחתית ולא צפה לראש', () => {
    expect(byTaskTime(t(null), t('18:00'))).toBeGreaterThan(0)
    expect(byTaskTime(t('18:00'), t(null))).toBeLessThan(0)
  })

  it('שעת המחסן מפרידה רק כשהשטח שווה', () => {
    expect(byTaskTime(t('09:00', '05:00'), t('09:00', '07:00'))).toBeLessThan(0)
    /* ...ואינה גוברת על שעת שטח מאוחרת: יציאה ב-05:00 אינה מה שהיום נקרא לפיו */
    expect(byTaskTime(t('18:00', '05:00'), t('06:00', '07:00'))).toBeGreaterThan(0)
  })

  it('תיקו מלא מחזיר אפס, ולכן סדר המקור נשמר', () => {
    expect(byTaskTime(t(null), t(null))).toBe(0)
    expect(byTaskTime(t('09:00', '06:00'), t('09:00', '06:00'))).toBe(0)
  })
})

describe('byTaskDateTime', () => {
  it('התאריך גובר על השעה', () => {
    expect(byTaskDateTime(t('23:00', null, '2026-03-01'), t('01:00', null, '2026-03-02'))).toBeLessThan(0)
  })

  it('ובאותו תאריך — מי שקודם בשעה', () => {
    const setup = t('18:00', null, '2026-03-01')
    const teardown = t('06:00', null, '2026-03-01')
    expect(byTaskDateTime(setup, teardown)).toBeGreaterThan(0)
    /* מיון של הזוג מציב את הפירוק ראשון, וזו כל הבקשה */
    expect([setup, teardown].sort(byTaskDateTime)[0]).toBe(teardown)
  })

  it('ובתאריכים שונים הסדר הכרונולוגי הוא ממילא הקמה ואז פירוק', () => {
    const setup = t('08:00', null, '2026-03-01')
    const teardown = t('08:00', null, '2026-03-03')
    expect([teardown, setup].sort(byTaskDateTime)[0]).toBe(setup)
  })
})
