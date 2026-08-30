import {
  Banknote,
  BarChart3,
  Bell,
  Building2,
  Calendar,
  CalendarClock,
  CalendarDays,
  ClipboardList,
  Clock,
  FileText,
  HardHat,
  LayoutDashboard,
  PartyPopper,
  Percent,
  Settings,
  TrendingUp,
  Truck,
  Users,
} from '../components/ui/icons'
import type { ComponentType } from 'react'
import { PERM } from '../lib/permissions'
import type { MyPermissions } from '../types/domain'

/**
 * מי המשתמש *הוא*, להבדיל ממה שמותר לו.
 *
 * המפתחות עונים על "מה מותר", ולמנהל מערכת הם עונים תמיד כן — `app.has`
 * מחזיר true לאדמין בהגדרה. זה נכון להרשאות, ולא נכון למסכים ששייכים לאדם
 * מסוים: לשעון הנוכחות של מי שאינו עובד אין מה להחתים, ולמסך "העובדים שלי"
 * של מי שאינו קבלן אין סגל להראות. שלושת הדגלים כאן הם מה שמפריד בין השניים,
 * ולכן הם *מצטרפים* למפתח ולא מחליפים אותו.
 */
export interface NavAudience {
  /** מנהל מערכת — עוקף את טבלת ההרשאות, ולכן צריך גדר שאינה מפתח */
  isAdmin: boolean
  /** מוגדר גם כעובד: יש לו תפקיד צוות (עובד / נהג / ראש צוות) */
  isEmployee: boolean
  /** קבלן, או עובד שמביא גם סגל משלו (0075) */
  isContractor: boolean
  /** לקוח שמבצע את המשימות שלו בעצמו, ולכן מנהל סגל משלו (0133) */
  isSelfPerformingCustomer: boolean
}

/** בלי הקשר — הכול פתוח. ברירת המחדל של בדיקות ושל קריאות ישנות. */
export const ANY_AUDIENCE: NavAudience = {
  isAdmin: false,
  isEmployee: true,
  isContractor: true,
  isSelfPerformingCustomer: true,
}

export function navAudience(me: MyPermissions | null): NavAudience {
  if (!me)
    return { isAdmin: false, isEmployee: false, isContractor: false, isSelfPerformingCustomer: false }
  return {
    isAdmin: me.profile.is_admin,
    isEmployee: (me.roles ?? []).length > 0,
    isContractor: !!me.profile.contractor_id || me.profile.user_kind === 'contractor_user',
    isSelfPerformingCustomer: !!me.customer?.performed_by_enabled,
  }
}

/**
 * מסך אישי של עובד — שעון ומשמרות.
 *
 * מנהל מערכת שאינו מוגדר גם כעובד אינו רואה אותם: הוא אינו ברוסטר, אין לו
 * שיבוצים, והמסכים היו מציגים לו יום ריק לנצח. מי שאינו אדמין ממשיך להיות
 * מוכרע במפתח בלבד — עובד קבלן, למשל, מחזיק שעון בלי שורת `staff_roles`.
 */
export const forEmployees = (a: NavAudience) => !a.isAdmin || a.isEmployee

/** מסך של קבלן, ולא של מי שמחזיק במקרה את המפתח שלו. */
export const forContractors = (a: NavAudience) => a.isContractor

/**
 * מסך של לקוח שמבצע בעצמו (0133).
 *
 * אותו נימוק של `forContractors`: המפתח ניתן לתפקיד `customer_manager` כולו,
 * כי השער האמיתי הוא הדגל פר-לקוח — ובלי הגדר הזו כל מנהל אצל לקוח היה רואה
 * רשומת סגל שתמיד תישאר ריקה.
 */
export const forSelfPerformingCustomers = (a: NavAudience) => a.isSelfPerformingCustomer

export interface NavItem {
  to: string
  label: string
  /** shorter label for the mobile bottom bar, where a slot is ~4rem wide */
  shortLabel?: string
  icon: ComponentType<{ size?: number | string; strokeWidth?: number | string; className?: string }>
  /** registry key checked with `has(perm)` — omit only when `anyPerm` is given */
  perm?: string
  /**
   * For a destination that two audiences reach through two different keys, the
   * way `/shifts` is the roster to a shift coordinator and the contractor's own
   * staff to a contractor. Holding any one of them shows the entry.
   */
  anyPerm?: string[]
  /**
   * Hides this entry from whoever holds any of these keys — for a destination
   * that two entries point at, where the wider one already covers the narrower.
   */
  hiddenBy?: string[]
  /**
   * גדר נוספת, על *מי שקורא* ולא על מה שמותר לו. יעד שמכריז עליה מוצג רק
   * למי שהפרדיקט מחזיר לו true — ראו `forEmployees` / `forContractors`.
   */
  audience?: (a: NavAudience) => boolean
  end?: boolean
  /** competes for one of the four slots in the mobile bottom bar */
  primary?: boolean
}

export interface NavSection {
  title: string
  items: NavItem[]
}

/**
 * Grouping the nine destinations into three named sections turns a flat list
 * into something scannable — you look for a *kind* of screen first, then the
 * screen. Order within each section follows how often the screen is opened.
 */
export const NAV_SECTIONS: NavSection[] = [
  {
    title: 'תפעול',
    items: [
      { to: '/', label: 'דשבורד', icon: LayoutDashboard, perm: PERM.DASHBOARD_VIEW, end: true, primary: true },
      /* הסיכום הכספי של הקבלן — הדשבורד שלו, ולכן הוא יושב לצד הדשבורד ולא
         בסקשן הנתונים. הוא גם הרשומה הראשונה שמנהל קבלן רואה, ולכן `/` מפנה
         אליו מעצמו דרך HomeRoute. */
      { to: '/portal', label: 'כספים ותשלומים', shortLabel: 'כספים', icon: Banknote, perm: PERM.PORTAL_VIEW, primary: true },
      { to: '/calendar', label: 'לוח שנה', icon: Calendar, perm: PERM.CALENDAR_VIEW, primary: true },
      { to: '/board', label: 'לו״ז עבודה', shortLabel: 'לו״ז', icon: ClipboardList, perm: PERM.BOARD_VIEW, primary: true },
    ],
  },
  {
    // הסקשן הזה הוא היחיד שעובד מן השורה — ועובד קבלן שקיבל התחברות —
    // רואה בכלל, ולכן הוא יושב לפני הנתונים ולא אחריהם.
    title: 'הנוכחות שלי',
    items: [
      {
        to: '/my/schedule',
        label: 'משמרות',
        shortLabel: 'משמרות',
        icon: CalendarClock,
        perm: PERM.ATTENDANCE_VIEW_SCHEDULE,
        audience: forEmployees,
      },
      {
        to: '/my/attendance',
        label: 'שעון נוכחות',
        shortLabel: 'שעון',
        icon: Clock,
        perm: PERM.ATTENDANCE_VIEW_OWN,
        audience: forEmployees,
      },
      /* אותו מסך של "דוח נוכחות" שלמטה, מצומצם לשורות של המשתמש עצמו — השרת
         כבר מחזיר רק אותן. מי שמחזיק view_all מגיע אליו דרך הרשומה בסקשן
         "נתונים", ומנהל קבלן דרך "נוכחות הסגל שלי" שמתחתיה; אצל שניהם הרשומה
         הזאת נעלמת במקום להכפיל את היעד תחת כותרת צרה מדי. עובד קבלן אינו
         מחזיק אף אחד מהשניים (המודול portal סגור לו), ולכן הוא רואה אותה. */
      {
        to: '/attendance',
        label: 'דוח הנוכחות שלי',
        shortLabel: 'דוח',
        icon: FileText,
        perm: PERM.ATTENDANCE_VIEW_OWN,
        hiddenBy: [PERM.ATTENDANCE_VIEW_ALL, PERM.PORTAL_ATTENDANCE],
        audience: forEmployees,
      },
      /* הצד השני של אותה הכרעה: הסגל של הקבלן. `attendance_report` כבר תוחם
         אותו לקבלן של הקורא, ולכן זה אותו מסך בהיקף אחר — ומוסתר ממי שמחזיק
         view_all, שרואה את הרשומה הרחבה יותר ב"נתונים". */
      {
        to: '/attendance',
        label: 'נוכחות הסגל שלי',
        shortLabel: 'נוכחות',
        icon: Clock,
        perm: PERM.PORTAL_ATTENDANCE,
        hiddenBy: [PERM.ATTENDANCE_VIEW_ALL],
      },
      /* הסגל של הקבלן, ולכן רק לקבלן: המפתח לבדו הראה את המסך גם למנהל
         מערכת (שעוקף כל מפתח) ולכל איש משרד שקיבל אותו בטעות, ולשניהם אין
         סגל משלהם — `my_contractor_workers` היה מחזיר להם רשימה ריקה. */
      { to: '/my/staff', label: 'העובדים שלי', icon: Users, perm: PERM.PORTAL_MANAGE_WORKERS, audience: forContractors },
      /* המקבילה של הלקוח שמבצע בעצמו (0133) — אותה רשומה, מאגר אחר. */
      {
        to: '/my/crew',
        label: 'הסגל שלי',
        icon: Users,
        perm: PERM.CUSTOMERS_MANAGE_OWN_STAFF,
        audience: forSelfPerformingCustomers,
      },
      { to: '/my/notifications', label: 'התראות', icon: Bell, perm: PERM.NOTIFICATIONS_PREFERENCES },
    ],
  },
  {
    title: 'נתונים',
    items: [
      { to: '/events', label: 'אירועים', icon: PartyPopper, perm: PERM.EVENTS_LIST, primary: true },
      { to: '/customers', label: 'לקוחות', icon: Building2, perm: PERM.CUSTOMERS_VIEW },
      { to: '/users', label: 'עובדים', icon: Users, perm: PERM.USERS_VIEW },
      { to: '/contractors', label: 'קבלנים', icon: HardHat, perm: PERM.CONTRACTORS_VIEW },
      { to: '/vehicles', label: 'ניהול רכבים', shortLabel: 'רכבים', icon: Truck, perm: PERM.FLEET_VIEW },
      /* shortLabel 'שיבוץ' ולא 'משמרות': מי שרואה את הרשומה הזאת רואה במקביל
         גם את "משמרות" שלמעלה, ושתי רשומות באותו שם הן שתי רשומות שאי אפשר
         לבחור ביניהן. */
      {
        to: '/shifts',
        label: 'לוח משמרות צוות',
        shortLabel: 'שיבוץ',
        icon: CalendarDays,
        anyPerm: [PERM.ATTENDANCE_VIEW_ALL, PERM.PORTAL_ATTENDANCE],
      },
      { to: '/attendance', label: 'דוח נוכחות', shortLabel: 'נוכחות', icon: Clock, perm: PERM.ATTENDANCE_VIEW_ALL },
      { to: '/reports', label: 'דוחות', shortLabel: 'דוחות', icon: BarChart3, perm: PERM.REPORTS_VIEW },
      /* שני דפי הרווחיות הם יעדים ולא לשוניות של "דוחות": הם המסכים שנפתחים
         הכי הרבה בסקשן הזה, והדרך היחידה אליהם הייתה שני קישורים בתוך שורת
         התבניות של /reports — מקום שצריך לדעת עליו כדי למצוא אותו. */
      { to: '/reports/task-pnl', label: 'רווחיות לפי משימה', shortLabel: 'רווחיות', icon: Percent, perm: PERM.REPORTS_VIEW },
      { to: '/reports/profitability', label: 'רווחיות לקוחות', shortLabel: 'לקוחות', icon: TrendingUp, perm: PERM.REPORTS_VIEW },
      { to: '/receipts', label: 'רישום תקבולים', shortLabel: 'תקבולים', icon: Banknote, perm: PERM.FINANCE_RECEIPTS_VIEW },
    ],
  },
  {
    title: 'מערכת',
    items: [{ to: '/settings', label: 'הגדרות', icon: Settings, perm: PERM.SETTINGS_VIEW }],
  },
]

/**
 * מי רואה רשומה בתפריט. אותה תשובה משרתת את הסרגל, את הבר התחתון ואת
 * ההפניה של `/`, כדי שמסך שהתפריט מציג יהיה גם המסך שהבית שולח אליו.
 */
export function navItemVisible(
  item: NavItem,
  has: (perm: string) => boolean,
  audience: NavAudience = ANY_AUDIENCE,
): boolean {
  const held = item.anyPerm ? item.anyPerm.some(has) : has(item.perm!)
  return held && !item.hiddenBy?.some(has) && (item.audience?.(audience) ?? true)
}

/** הסקשנים שנשארים אחרי הסינון — בלי סקשן שהתרוקן. */
export function visibleNavSections(
  has: (perm: string) => boolean,
  audience: NavAudience = ANY_AUDIENCE,
  sections = NAV_SECTIONS,
): NavSection[] {
  return sections
    .map((s) => ({ ...s, items: s.items.filter((n) => navItemVisible(n, has, audience)) }))
    .filter((s) => s.items.length > 0)
}

/**
 * The bottom bar has five slots: four destinations plus "עוד", which opens the
 * full menu. Items flagged `primary` claim the four first; if permissions hide
 * some of them, the next visible destinations fill the gaps rather than leaving
 * the bar half-empty.
 */
export function bottomNavItems(sections: NavSection[], slots = 4): NavItem[] {
  const flat = sections.flatMap((s) => s.items)
  const chosen = flat.filter((i) => i.primary).slice(0, slots)
  if (chosen.length < slots) {
    for (const item of flat) {
      if (chosen.length === slots) break
      if (!chosen.includes(item)) chosen.push(item)
    }
  }
  return chosen
}

/** Static crumb labels; detail screens add their own via `usePageTitle`. */
export const ROUTE_LABELS: Record<string, string> = {
  '/': 'דשבורד',
  '/calendar': 'לוח שנה',
  '/board': 'לו״ז עבודה',
  '/events': 'אירועים',
  '/customers': 'לקוחות',
  '/users': 'עובדים',
  '/contractors': 'קבלנים',
  '/vehicles': 'ניהול רכבים',
  '/attendance': 'דוח נוכחות',
  '/shifts': 'לוח משמרות צוות',
  '/reports': 'דוחות',
  '/reports/profitability': 'רווחיות לקוחות',
  '/reports/task-pnl': 'רווחיות לפי משימה',
  '/receipts': 'רישום תקבולים',
  '/my/schedule': 'משמרות',
  '/my/attendance': 'שעון נוכחות',
  '/my/notifications': 'התראות',
  '/my/staff': 'העובדים שלי',
  '/my/crew': 'הסגל שלי',
  '/settings': 'הגדרות',
  '/portal': 'כספים ותשלומים',
}
