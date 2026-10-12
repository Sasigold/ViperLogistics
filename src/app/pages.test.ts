import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { ADMIN_LOCKED_PAGES, PAGES, hiddenPagesOf, resolvePage, settingOf } from './pages'
import { NAV_SECTIONS } from './nav'
import type { MyPermissions } from '../types/domain'

const me = (hidden?: string[]) => ({ hidden_pages: hidden }) as unknown as MyPermissions

describe('resolvePage — הבבואה של app.hidden_pages (0215)', () => {
  it('בלי שום הגדרה — מוצג, ברירת מחדל', () => {
    expect(resolvePage('calendar', { isAdmin: false, groups: [] })).toEqual({
      visible: true,
      source: 'default',
      via: [],
    })
  })

  it('קבוצה שמסתירה — מוסתר, ואומר מי', () => {
    const r = resolvePage('my_schedule', { isAdmin: true, groups: [{ label: 'מנהלי מערכת', visible: false }] })
    expect(r).toEqual({ visible: false, source: 'group', via: ['מנהלי מערכת'] })
  })

  it('"מוצג" מפורש בקבוצה אחת גובר על "מוסתר" באחרת', () => {
    const r = resolvePage('calendar', {
      isAdmin: false,
      groups: [
        { label: 'עובד', visible: false },
        { label: 'ראש צוות', visible: true },
      ],
    })
    expect(r).toEqual({ visible: true, source: 'group', via: ['ראש צוות'] })
  })

  it('קבוצה בלי הגדרה אינה מבטלת הסתרה של קבוצה אחרת', () => {
    const r = resolvePage('calendar', {
      isAdmin: false,
      groups: [{ label: 'עובד', visible: false }, { label: 'ראש צוות' }],
    })
    expect(r.visible).toBe(false)
  })

  it('הגדרה אישית גוברת על הקבוצות — לשני הכיוונים', () => {
    const groups = [{ label: 'מנהלי מערכת', visible: false }]
    expect(resolvePage('portal', { isAdmin: true, personal: true, groups }).visible).toBe(true)
    expect(resolvePage('board', { isAdmin: false, personal: false, groups: [] })).toEqual({
      visible: false,
      source: 'personal',
      via: [],
    })
  })

  it('ההגדרות אינן מוסתרות ממנהל מערכת בשום הגדרה', () => {
    expect(ADMIN_LOCKED_PAGES.has('settings')).toBe(true)
    const r = resolvePage('settings', { isAdmin: true, personal: false, groups: [{ label: 'x', visible: false }] })
    expect(r).toEqual({ visible: true, source: 'locked', via: [] })
  })

  it('אבל ממי שאינו מנהל מערכת — כן', () => {
    expect(resolvePage('settings', { isAdmin: false, personal: false, groups: [] }).visible).toBe(false)
  })

  it('settingOf ממפה שורה לשלושת המצבים', () => {
    expect(settingOf(undefined)).toBe('inherit')
    expect(settingOf(true)).toBe('show')
    expect(settingOf(false)).toBe('hide')
  })
})

describe('hiddenPagesOf', () => {
  it('שרת בלי 0215 — אין שדה, ושום דבר אינו מוסתר', () => {
    expect(hiddenPagesOf(null).size).toBe(0)
    expect(hiddenPagesOf(me(undefined)).size).toBe(0)
  })

  it('מחזיר את מה שהשרת הכריע, ואותו אובייקט לאותו me', () => {
    const m = me(['portal', 'my_schedule'])
    const a = hiddenPagesOf(m)
    expect([...a].sort()).toEqual(['my_schedule', 'portal'])
    expect(hiddenPagesOf(m)).toBe(a)
  })
})

describe('רשימת הדפים מול התפריט והנתב', () => {
  const items = NAV_SECTIONS.flatMap((s) => s.items)
  const keys = PAGES.map((p) => p.key as string)

  it('כל מפתח ייחודי ועומד בבדיקה של המסד', () => {
    expect(new Set(keys).size).toBe(keys.length)
    for (const k of keys) expect(k).toMatch(/^[a-z][a-z0-9_]{0,47}$/)
  })

  it('כל רשומה בתפריט מצביעה על דף מהרשימה', () => {
    for (const i of items) expect(keys).toContain(i.page)
  })

  it('לכל דף יש לפחות רשומה אחת בתפריט', () => {
    for (const k of keys) expect(items.some((i) => i.page === k)).toBe(true)
  })

  it('רשומות שמובילות לאותו נתיב — אותו דף', () => {
    const byPath = new Map<string, Set<string>>()
    for (const i of items) byPath.set(i.to, (byPath.get(i.to) ?? new Set()).add(i.page))
    for (const [, pages] of byPath) expect(pages.size).toBe(1)
  })

  it('הדף יושב בסקשן שאחת הרשומות שלו נמצאת בו', () => {
    for (const p of PAGES) {
      const sections = NAV_SECTIONS.filter((s) => s.items.some((i) => i.page === p.key)).map((s) => s.title)
      expect(sections).toContain(p.section)
    }
  })

  /* ‏RouteGate חוסם דף מוסתר לפי `handle.page`. נתיב שמופיע בתפריט בלי
     להכריז על הדף שלו ייפתח בהקלדה גם אחרי שהוסתר — ולכן הבדיקה קוראת את
     טבלת הנתיבים עצמה (ייבוא שלה היה מושך את כל המסכים לסביבת node). */
  it('כל נתיב בתפריט מכריז בנתב על אותו דף', () => {
    const src = readFileSync(new URL('./router.tsx', import.meta.url), 'utf8')
    const declared = new Map<string, string>()
    for (const m of src.matchAll(/path: '([^']+)',\s*handle: \{[^}]*page: '([a-z_]+)'/g)) declared.set(m[1], m[2])
    for (const i of items) {
      if (i.to === '/') continue // הבית בוחר בעצמו: HomeRoute שואל על 'dashboard'
      expect(declared.get(i.to), i.to).toBe(i.page)
    }
  })
})
