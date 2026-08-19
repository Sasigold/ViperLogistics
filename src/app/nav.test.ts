import { describe, expect, it } from 'vitest'
import { PERM } from '../lib/permissions'
import { bottomNavItems, navItemVisible, visibleNavSections } from './nav'
import type { NavItem } from './nav'

/**
 * התפריט הוא מה שמכריע לאן `/` שולח משתמש שאין לו דשבורד (HomeRoute), ולכן
 * "מה רואה כל פרסונה" אינו שאלה קוסמטית. עד 0071 הקבלן לא ראה את הסרגל בכלל —
 * הוא ישב מחוץ ל-`AppLayout` — ומרגע שהוא בפנים, הרשימה הזאת היא כל המסך שלו.
 *
 * ‏`has` כאן הוא סט מפתחות ולא שרת: מה שנבדק הוא הסינון, לא ההכרעה. הסטים
 * למטה מועתקים מהתפקידים ב-0011/0019/0066/0067/0071.
 */
function hasFrom(keys: string[]) {
  const set = new Set(keys)
  return (perm: string) => set.has(perm)
}

const CONTRACTOR_MANAGER = [
  PERM.PORTAL_VIEW,
  PERM.PORTAL_ATTENDANCE,
  PERM.PORTAL_ASSIGN_WORKERS,
  PERM.PORTAL_VIEW_FINANCIALS,
  PERM.PORTAL_MANAGE_WORKERS,
  PERM.CALENDAR_VIEW,
  PERM.BOARD_VIEW,
  PERM.BOARD_VIEW_STAFFING,
  PERM.TASKS_VIEW,
  PERM.ATTENDANCE_VIEW_OWN,
  PERM.ATTENDANCE_VIEW_SCHEDULE,
  PERM.ATTENDANCE_CLOCK,
  PERM.NOTIFICATIONS_PREFERENCES,
]

const CONTRACTOR_WORKER = [
  PERM.CALENDAR_VIEW,
  PERM.BOARD_VIEW,
  PERM.TASKS_VIEW,
  PERM.ATTENDANCE_VIEW_OWN,
  PERM.ATTENDANCE_VIEW_SCHEDULE,
  PERM.ATTENDANCE_CLOCK,
  PERM.NOTIFICATIONS_PREFERENCES,
]

/**
 * עובד צוות מן השורה. מ-0079 הוא מחזיק `events.view` — דף האירוע שהוא משובץ
 * אליו — אבל לא את `events.list`, ולכן "אירועים" אינו בתפריט שלו. זה בדיוק
 * הפיצול ש-0080 עשה, וזו הפרסונה שמוכיחה אותו.
 */
const STAFF_WORKER = [...CONTRACTOR_WORKER, PERM.EVENTS_VIEW]

/**
 * מנהל אצל הלקוח, אחרי 0074. פרסונה שלא הייתה כאן — וזו הסיבה שאיש לא ראה
 * שהוא מקבל "דוחות" מ-`reports.view` שנגזר מ-`dashboard.view`, ושלושה פריטי
 * נוכחות מ-`attendance.view_own` שתפקידו העניק לו במפורש מאז 0011.
 */
const CUSTOMER_MANAGER = [
  PERM.DASHBOARD_VIEW,
  PERM.CALENDAR_VIEW,
  PERM.BOARD_VIEW,
  PERM.BOARD_VIEW_STAFFING,
  PERM.TASKS_VIEW,
  PERM.EVENTS_VIEW,
  /* נגזר מ-`events.view` ואינו חסום לו, ולכן השרת פותר אותו true. הרשימות
     כאן הן מה ש-`app.has` החזיר, ולא מה שהוענק במפורש. */
  PERM.EVENTS_LIST,
  PERM.PRICING_VIEW,
  PERM.FINANCE_CUSTOMER_SPEND,
  PERM.NOTIFICATIONS_PREFERENCES,
]

/**
 * העובד שגם מביא סגל (0075). הוא מחזיק את שני הסטים במקביל, ולכן התפריט שלו
 * הוא האיחוד — לא אחד מהם.
 */
const STAFF_CONTRACTOR = [
  PERM.CALENDAR_VIEW,
  PERM.BOARD_VIEW,
  PERM.TASKS_VIEW,
  PERM.ATTENDANCE_VIEW_OWN,
  PERM.ATTENDANCE_VIEW_SCHEDULE,
  PERM.ATTENDANCE_CLOCK,
  PERM.NOTIFICATIONS_PREFERENCES,
  PERM.PORTAL_VIEW,
  PERM.PORTAL_VIEW_FINANCIALS,
  PERM.PORTAL_MANAGE_WORKERS,
  PERM.PORTAL_ASSIGN_WORKERS,
  PERM.PORTAL_ATTENDANCE,
]

/** רכז משמרות: רואה את כל הצוות, ואינו קבלן. */
const COORDINATOR = [
  PERM.CALENDAR_VIEW,
  PERM.BOARD_VIEW,
  PERM.ATTENDANCE_VIEW_ALL,
  PERM.ATTENDANCE_VIEW_OWN,
  PERM.ATTENDANCE_VIEW_SCHEDULE,
  PERM.NOTIFICATIONS_PREFERENCES,
]

function destinations(keys: string[]): string[] {
  return visibleNavSections(hasFrom(keys)).flatMap((s) => s.items.map((i) => i.to))
}

function labelsFor(keys: string[], to: string): string[] {
  return visibleNavSections(hasFrom(keys))
    .flatMap((s) => s.items)
    .filter((i) => i.to === to)
    .map((i) => i.label)
}

describe('navItemVisible', () => {
  const item = (extra: Partial<NavItem>): NavItem =>
    ({ to: '/x', label: 'x', icon: (() => null) as never, ...extra }) as NavItem

  it('נשען על perm כשאין anyPerm', () => {
    expect(navItemVisible(item({ perm: 'a' }), hasFrom(['a']))).toBe(true)
    expect(navItemVisible(item({ perm: 'a' }), hasFrom(['b']))).toBe(false)
  })

  it('anyPerm נפתח על מפתח אחד מתוך כמה', () => {
    const it2 = item({ anyPerm: ['a', 'b'] })
    expect(navItemVisible(it2, hasFrom(['b']))).toBe(true)
    expect(navItemVisible(it2, hasFrom(['a', 'b']))).toBe(true)
    expect(navItemVisible(it2, hasFrom(['c']))).toBe(false)
  })

  it('hiddenBy גובר גם על anyPerm', () => {
    expect(navItemVisible(item({ anyPerm: ['a'], hiddenBy: ['z'] }), hasFrom(['a', 'z']))).toBe(false)
  })
})

describe('מה רואה כל פרסונה', () => {
  it('מנהל קבלן — כספים, לוח שנה, לו״ז, והנוכחות שלו ושל הסגל', () => {
    const seen = destinations(CONTRACTOR_MANAGER)
    expect(seen).toEqual(
      expect.arrayContaining([
        '/portal',
        '/calendar',
        '/board',
        '/my/schedule',
        '/my/attendance',
        '/attendance',
        '/my/staff',
        '/shifts',
        '/my/notifications',
      ]),
    )
    // הדשבורד המשרדי, ומסכי המשרד, נשארים בחוץ
    for (const blocked of ['/', '/events', '/customers', '/users', '/contractors', '/reports', '/receipts', '/settings'])
      expect(seen).not.toContain(blocked)
  })

  it('עובד קבלן — אותם מסכים של עובד מן השורה, ובלי הפורטל', () => {
    const seen = destinations(CONTRACTOR_WORKER)
    expect(seen).toEqual(
      expect.arrayContaining(['/calendar', '/board', '/my/schedule', '/my/attendance', '/attendance', '/my/notifications']),
    )
    for (const blocked of ['/portal', '/my/staff', '/shifts', '/contractors', '/settings'])
      expect(seen).not.toContain(blocked)
  })

  it('ועובד קבלן רואה בדיוק מה שעובד צוות רואה', () => {
    expect(destinations(CONTRACTOR_WORKER).sort()).toEqual(destinations(STAFF_WORKER).sort())
  })

  it('דף האירוע פתוח לעובד הצוות, ורשימת האירועים אינה בתפריט שלו', () => {
    expect(STAFF_WORKER).toContain(PERM.EVENTS_VIEW)
    expect(destinations(STAFF_WORKER)).not.toContain('/events')
  })

  it('מנהל אצל הלקוח — הדשבורד, האירועים והלו״ז שלו, בלי דוחות ובלי נוכחות', () => {
    const seen = destinations(CUSTOMER_MANAGER)
    expect(seen).toEqual(expect.arrayContaining(['/', '/calendar', '/board', '/events', '/my/notifications']))
    /* ‏`/reports` נגזר אצלו מ-`dashboard.view` עד 0074, ושלושת פריטי הנוכחות
       הגיעו מ-`attendance.view_own` שהתפקיד העניק לו. ללקוח אין שעון. */
    for (const blocked of [
      '/reports',
      '/my/attendance',
      '/my/schedule',
      '/attendance',
      '/shifts',
      '/portal',
      '/my/staff',
      '/receipts',
      '/customers',
      '/users',
      '/contractors',
      '/settings',
    ])
      expect(seen).not.toContain(blocked)
  })

  it('העובד שגם קבלן — הכובעים מצטרפים ולא מחליפים זה את זה', () => {
    const seen = destinations(STAFF_CONTRACTOR)
    // הצד השעתי שלו
    expect(seen).toEqual(expect.arrayContaining(['/calendar', '/board', '/my/schedule', '/my/attendance']))
    // ובנוסף הצד הקבלני
    expect(seen).toEqual(expect.arrayContaining(['/portal', '/my/staff', '/attendance', '/shifts']))
    // מה שלא נפתח לו: מסכי המשרד
    for (const blocked of ['/events', '/customers', '/users', '/contractors', '/reports', '/settings'])
      expect(seen).not.toContain(blocked)
  })

  it('...וכל מה שעובד רגיל רואה, הוא רואה גם', () => {
    const worker = destinations(STAFF_WORKER)
    const dual = destinations(STAFF_CONTRACTOR)
    /* פרט ל"דוח הנוכחות שלי", שאותה רשומה עצמה מוסתרת אצלו לטובת "נוכחות
       הסגל שלי" — אותו יעד, ניסוח רחב יותר. */
    for (const to of worker) expect(dual).toContain(to)
  })
})

/**
 * שלוש רשומות מצביעות על `/attendance`, וכל אחת מהן מנוסחת לקהל אחר. שתיים
 * שיופיעו יחד הן שתי רשומות שאי אפשר לבחור ביניהן, ולכן `hiddenBy` הוא מה
 * שמפריד — וזה מה שנבדק כאן, לכל קהל בנפרד.
 */
describe('הרשומות אל /attendance סותרות זו את זו', () => {
  it.each([
    ['מנהל קבלן', CONTRACTOR_MANAGER, 'נוכחות הסגל שלי'],
    ['עובד', STAFF_WORKER, 'דוח הנוכחות שלי'],
    ['רכז משמרות', COORDINATOR, 'דוח נוכחות'],
    ['העובד שגם קבלן', STAFF_CONTRACTOR, 'נוכחות הסגל שלי'],
  ])('%s רואה רשומה אחת בלבד', (_who, keys, label) => {
    expect(labelsFor(keys as string[], '/attendance')).toEqual([label])
  })
})

describe('bottomNavItems', () => {
  it('ממלא ארבע משבצות למנהל קבלן, בלי כפילות', () => {
    const items = bottomNavItems(visibleNavSections(hasFrom(CONTRACTOR_MANAGER)))
    expect(items).toHaveLength(4)
    expect(new Set(items.map((i) => i.to)).size).toBe(4)
  })
})
