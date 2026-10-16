import type { MyPermissions } from '../types/domain'

/**
 * הדפים שהבעלים מחליט עליהם (0215).
 *
 * שכבה נפרדת מההרשאות: הרשאה אומרת מה *מותר* (והשרת אוכף), ודף אומר מה
 * *מוצג* בתפריט ונפתח באפליקציה. דף נפתח רק כששניהם מסכימים — הסתרה אינה
 * פותחת דבר ואינה סוגרת נתונים. זו הדרך היחידה להוריד דף ממנהל מערכת,
 * שהמטריצה אינה חלה עליו: ‏`app.has` עונה לו "כן" על כל מפתח.
 *
 * הרשימה כאן היא הרשימה היחידה: כל רשומה בתפריט (`NavItem.page`) וכל נתיב
 * שמאחוריה (`RouteHandle.page`) מצביעים על מפתח ממנה, והמסד שומר את המפתח
 * כטקסט ואינו צריך לדעת מה הוא. כמה רשומות בתפריט יכולות להוביל לאותו דף —
 * "דוח הנוכחות שלי" ו"דוח נוכחות" הם אותו `/attendance` — והסתרה מורידה את
 * כולן. מסכי פרטים (אירוע, לקוח, קבלן, רכב) אינם כאן: הם נפתחים מתוך מסכים
 * אחרים, וההרשאות לבדן מכריעות עליהם.
 */
export interface PageDef {
  key: string
  label: string
  /** כותרת הסקשן בתפריט שהדף יושב בו */
  section: string
  /** מה הדף, למי שמחליט עליו — כשהשם לבדו אינו אומר את זה */
  hint?: string
}

export const PAGES = [
  { key: 'dashboard', label: 'דשבורד', section: 'ראשי' },
  {
    key: 'command',
    label: 'משימות ניהול',
    section: 'ראשי',
    hint: 'המשימות של מנהלי המערכת — יעדים, תזכורות ומד איום. למנהלי מערכת בלבד',
  },
  {
    key: 'portal',
    label: 'כספים ותשלומים',
    section: 'ראשי',
    hint: 'הסיכום הכספי של קבלן. אצל מי שאינו קבלן הוא ריק',
  },
  { key: 'calendar', label: 'לוח שנה', section: 'תפעול' },
  { key: 'board', label: 'לו״ז עבודה', section: 'תפעול' },
  { key: 'events', label: 'אירועים', section: 'תפעול', hint: 'רשימת האירועים. כרטיס אירוע נפתח גם בלעדיה' },
  { key: 'warehouse', label: 'לו״ז מחסן', section: 'תפעול' },
  { key: 'my_schedule', label: 'משמרות', section: 'אישי', hint: 'המשמרות של המשתמש עצמו' },
  { key: 'my_clock', label: 'שעון נוכחות', section: 'אישי', hint: 'החתמת כניסה ויציאה' },
  { key: 'my_staff', label: 'העובדים שלי', section: 'אישי', hint: 'הסגל של קבלן' },
  { key: 'my_crew', label: 'הסגל שלי', section: 'אישי', hint: 'הסגל של לקוח שמבצע בעצמו' },
  { key: 'my_payslips', label: 'תלושי השכר שלי', section: 'אישי', hint: 'התלושים ששויכו לעובד' },
  { key: 'notifications', label: 'התראות', section: 'אישי', hint: 'העדפות ההתראות של המשתמש' },
  { key: 'customers', label: 'לקוחות', section: 'לקוחות ומשאבים' },
  { key: 'users', label: 'עובדים', section: 'לקוחות ומשאבים' },
  { key: 'contractors', label: 'קבלנים', section: 'לקוחות ומשאבים' },
  { key: 'vehicles', label: 'ניהול רכבים', section: 'לקוחות ומשאבים' },
  { key: 'shifts', label: 'לוח משמרות צוות', section: 'צוות ונוכחות', hint: 'השיבוץ של כל הצוות' },
  {
    key: 'attendance',
    label: 'דוח נוכחות',
    section: 'צוות ונוכחות',
    hint: 'כולל "דוח הנוכחות שלי" ו"נוכחות הסגל שלי"',
  },
  { key: 'payslips', label: 'תלושי שכר', section: 'צוות ונוכחות', hint: 'העלאה מרואה החשבון, שיוך לעובדים ועלות מעביד' },
  { key: 'payments', label: 'תשלומי אירועים', section: 'כספים' },
  { key: 'receipts', label: 'רישום תקבולים', section: 'כספים' },
  { key: 'wallet', label: 'ארנק מזומנים', section: 'כספים' },
  {
    key: 'invoices',
    label: 'חשבוניות',
    section: 'כספים',
    hint: 'חשבוניות ספקים: סריקה, תיקייה לכל חודש, ייצוא לרואה החשבון וחיבור Gmail. למנהלי מערכת בלבד',
  },
  { key: 'reports', label: 'דוחות', section: 'דוחות' },
  { key: 'load', label: 'מפת עומסים', section: 'דוחות' },
  { key: 'task_pnl', label: 'רווחיות לפי משימה', section: 'דוחות' },
  { key: 'profitability', label: 'רווחיות לקוחות', section: 'דוחות' },
  { key: 'settings', label: 'הגדרות', section: 'מערכת' },
  { key: 'integrations', label: 'אינטגרציות', section: 'מערכת' },
] as const satisfies readonly PageDef[]

export type PageKey = (typeof PAGES)[number]['key']

/**
 * דפים שאינם מוסתרים ממנהל מערכת בשום הגדרה: מההגדרות מחזירים דף שהוסתר.
 * אותו כלל בשרת — `page_visibility_set` מסרב, ו-`app.hidden_pages` מתעלם.
 */
export const ADMIN_LOCKED_PAGES: ReadonlySet<string> = new Set<PageKey>(['settings'])

const NONE: ReadonlySet<string> = new Set()
const cache = new WeakMap<MyPermissions, ReadonlySet<string>>()

/**
 * הדפים שהוסתרו מהמשתמש המחובר, כפי שהשרת הכריע (`app.hidden_pages`).
 * שרת שעוד אין בו 0215 אינו מחזיר את השדה, ואז דבר אינו מוסתר.
 */
export function hiddenPagesOf(me: MyPermissions | null): ReadonlySet<string> {
  if (!me?.hidden_pages?.length) return NONE
  let set = cache.get(me)
  if (!set) {
    set = new Set(me.hidden_pages)
    cache.set(me, set)
  }
  return set
}

/** שורה של `page_visibility`. שורה בלי תפקיד ובלי משתמש היא של מנהלי המערכת. */
export interface PageVisibilityRow {
  page_key: string
  role_id: string | null
  profile_id: string | null
  visible: boolean
}

/** ‏"ירושה" — אין שורה; "מוצג"/"מוסתר" — שורה עם true/false. */
export type PageSetting = 'inherit' | 'show' | 'hide'

export const settingOf = (visible: boolean | undefined): PageSetting =>
  visible === undefined ? 'inherit' : visible ? 'show' : 'hide'

/** קבוצה שהמשתמש שייך אליה: אחד התפקידים שלו, או "מנהלי מערכת". */
export interface PageGroup {
  label: string
  /** ההגדרה של הקבוצה לדף; undefined — אין לה הגדרה */
  visible?: boolean
}

export type PageSource = 'locked' | 'personal' | 'group' | 'default'

export interface PageResolution {
  visible: boolean
  source: PageSource
  /** הקבוצות שהכריעו, כשההכרעה באה מקבוצה */
  via: string[]
}

/**
 * הבבואה של `app.hidden_pages` (0215), לדף אחד — כדי שמסך העריכה יגיד *למה*
 * דף מוסתר או מוצג. שתיהן משתנות יחד.
 *
 *   1. ההגדרות אינן מוסתרות ממנהל מערכת.
 *   2. הגדרה אישית קובעת.
 *   3. בין הקבוצות: "מוצג" מפורש באחת גובר על "מוסתר" באחרת (bool_or).
 *   4. אחרת — מוצג.
 */
export function resolvePage(
  key: string,
  input: { isAdmin: boolean; personal?: boolean; groups: PageGroup[] },
): PageResolution {
  if (input.isAdmin && ADMIN_LOCKED_PAGES.has(key)) return { visible: true, source: 'locked', via: [] }
  if (input.personal !== undefined) return { visible: input.personal, source: 'personal', via: [] }
  const shows = input.groups.filter((g) => g.visible === true).map((g) => g.label)
  if (shows.length) return { visible: true, source: 'group', via: shows }
  const hides = input.groups.filter((g) => g.visible === false).map((g) => g.label)
  if (hides.length) return { visible: false, source: 'group', via: hides }
  return { visible: true, source: 'default', via: [] }
}
