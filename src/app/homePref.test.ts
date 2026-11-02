import { describe, expect, it } from 'vitest'
import { DEFAULT_HOME_PREF, HOME_PREF_KEY, START_PATH, destinations, launcherTiles, parseHomePref, resolveLanding } from './homePref'
import { NAV_SECTIONS, bottomNavItems, visibleNavSections } from './nav'

const all = () => true
const sections = visibleNavSections(all)

describe('parseHomePref', () => {
  it('בלי העדפה, או בצורה לא צפויה — ברירת המחדל', () => {
    expect(parseHomePref(undefined)).toEqual(DEFAULT_HOME_PREF)
    expect(parseHomePref({})).toEqual(DEFAULT_HOME_PREF)
    expect(parseHomePref({ [HOME_PREF_KEY]: 'x' })).toEqual(DEFAULT_HOME_PREF)
    expect(parseHomePref({ [HOME_PREF_KEY]: { landing: 'calendar' } })).toEqual({ landing: 'auto' })
  })

  it('קורא נחיתה ואריחים, ומסנן אריח שאינו טקסט', () => {
    expect(parseHomePref({ [HOME_PREF_KEY]: { landing: '/start', tiles: ['/calendar', 3] } })).toEqual({
      landing: '/start',
      tiles: ['/calendar'],
    })
  })
})

describe('resolveLanding', () => {
  it('auto ו-/ — אין הפניה', () => {
    expect(resolveLanding({ landing: 'auto' }, sections)).toBeNull()
    expect(resolveLanding({ landing: '/' }, sections)).toBeNull()
  })

  it('דף הפתיחה ומסך גלוי — מפנה אליהם', () => {
    expect(resolveLanding({ landing: START_PATH }, sections)).toBe(START_PATH)
    expect(resolveLanding({ landing: '/calendar' }, sections)).toBe('/calendar')
  })

  it('מסך שאינו גלוי (הרשאה נלקחה / הוסתר) — נופל לברירת המחדל', () => {
    const onlyCalendar = visibleNavSections((p) => p === 'calendar.view')
    expect(resolveLanding({ landing: '/board' }, onlyCalendar)).toBeNull()
    const hidden = visibleNavSections(all, {
      isAdmin: true,
      isEmployee: true,
      isContractor: true,
      isSelfPerformingCustomer: true,
      hasWarehouseSchedule: true,
      hiddenPages: new Set(['start']),
    })
    expect(resolveLanding({ landing: START_PATH }, hidden)).toBeNull()
  })
})

describe('launcherTiles', () => {
  it('בלי בחירה — כל היעדים, בלי דף הפתיחה עצמו ובלי כפילות נתיב', () => {
    const tos = launcherTiles(DEFAULT_HOME_PREF, sections).flatMap((g) => g.items.map((i) => i.to))
    expect(tos).not.toContain(START_PATH)
    expect(new Set(tos).size).toBe(tos.length)
    expect(tos).toEqual(destinations(sections).map((d) => d.item.to))
  })

  it('עם בחירה — רק מה שנבחר, בסדר התפריט, וקבוצה ריקה נעלמת', () => {
    const groups = launcherTiles({ landing: 'auto', tiles: ['/attendance', '/calendar', '/nope'] }, sections)
    expect(groups.flatMap((g) => g.items.map((i) => i.to))).toEqual(['/calendar', '/attendance'])
    expect(groups.every((g) => g.items.length > 0)).toBe(true)
  })
})

describe('דף הפתיחה בתפריט', () => {
  it('פתוח בלי מפתח — למי שיש לו לפחות שני מסכים אחרים', () => {
    const two = visibleNavSections((p) => p === 'calendar.view' || p === 'board.view')
    expect(two.flatMap((s) => s.items.map((i) => i.to))).toContain(START_PATH)
  })

  it('מסך אחד או אף אחד — אין דף פתיחה', () => {
    expect(visibleNavSections(() => false)).toEqual([])
    const one = visibleNavSections((p) => p === 'calendar.view')
    expect(one.flatMap((s) => s.items.map((i) => i.to))).toEqual(['/calendar'])
  })

  it('אינו ממלא משבצת בבר התחתון', () => {
    expect(bottomNavItems(visibleNavSections((p) => p === 'calendar.view')).map((i) => i.to)).toEqual(['/calendar'])
    expect(bottomNavItems(sections).some((i) => i.to === START_PATH)).toBe(false)
  })

  it('רשום ב-NAV_SECTIONS', () => {
    expect(NAV_SECTIONS.flatMap((s) => s.items).some((i) => i.to === START_PATH && i.page === 'start')).toBe(true)
  })
})
