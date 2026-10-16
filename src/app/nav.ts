import {
  Banknote,
  BarChart3,
  Bell,
  Building2,
  Calendar,
  CalendarClock,
  CalendarRange,
  ClipboardList,
  Clock,
  ContactRound,
  FileClock,
  Flame,
  HandCoins,
  HardHat,
  Landmark,
  LayoutDashboard,
  ListTodo,
  PartyPopper,
  Percent,
  Plug,
  ReceiptText,
  ScrollText,
  Settings,
  Timer,
  TrendingUp,
  Truck,
  User,
  UsersRound,
  Wallet,
  Warehouse,
} from '../components/ui/icons'
import type { ComponentType } from 'react'
import { PERM } from '../lib/permissions'
import type { MyPermissions } from '../types/domain'
import { hiddenPagesOf } from './pages'
import type { PageKey } from './pages'

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
  /**
   * לו״ז המחסן רלוונטי לו (0196): איש צוות או אדמין — תמיד; משתמש לקוח —
   * רק כשהמודול פתוח ללקוח שלו; קבלן — לעולם לא.
   */
  hasWarehouseSchedule: boolean
  /**
   * הדפים שהבעלים הסתיר ממנו (0215) — הגדר היחידה כאן שאינה "מי הוא" אלא
   * "מה הוחלט עליו", ולכן היא עוברת גם על מנהל מערכת. חסר = דבר אינו מוסתר.
   */
  hiddenPages?: ReadonlySet<string>
}

/** בלי הקשר — הכול פתוח. ברירת המחדל של בדיקות ושל קריאות ישנות. */
export const ANY_AUDIENCE: NavAudience = {
  isAdmin: false,
  isEmployee: true,
  isContractor: true,
  isSelfPerformingCustomer: true,
  hasWarehouseSchedule: true,
}

export function navAudience(me: MyPermissions | null): NavAudience {
  if (!me)
    return {
      isAdmin: false,
      isEmployee: false,
      isContractor: false,
      isSelfPerformingCustomer: false,
      hasWarehouseSchedule: false,
    }
  return {
    isAdmin: me.profile.is_admin,
    isEmployee: (me.roles ?? []).length > 0,
    isContractor: !!me.profile.contractor_id || me.profile.user_kind === 'contractor_user',
    isSelfPerformingCustomer: !!me.customer?.performed_by_enabled,
    hasWarehouseSchedule:
      me.profile.is_admin ||
      me.profile.user_kind === 'staff' ||
      (me.profile.user_kind === 'customer_user' && !!me.customer?.warehouse_schedule_enabled),
    hiddenPages: hiddenPagesOf(me),
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

/**
 * לו״ז המחסן (0196) — אותו נימוק של `forSelfPerformingCustomers`: המפתח ניתן
 * לתפקיד `customer_manager` כולו, והדגל פר-לקוח הוא השער. בלעדיו כל מנהל
 * אצל לקוח היה רואה לו״ז שתמיד יישאר ריק.
 */
export const forWarehouseSchedule = (a: NavAudience) => a.hasWarehouseSchedule

/**
 * משימות ניהול (0227) — של מנהלי המערכת בלבד. המפתח `command.view` כבר אינו
 * ניתן לאיש אחר (`applies_to` ריק); הגדר הזו אומרת את אותו דבר במפורש.
 */
export const forAdmins = (a: NavAudience) => a.isAdmin

export interface NavItem {
  to: string
  /** הדף שהרשומה מובילה אליו (0215) — מה שהבעלים מסתיר או מציג */
  page: PageKey
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
  /** מונה ליד הרשומה — מה שהוא סופר מוכרע ב-AppLayout (0227: 'command' = משימות באיחור) */
  badge?: 'command'
  /** competes for one of the four slots in the mobile bottom bar */
  primary?: boolean
}

/** גוון הקבוצה — אחד מצבעי האירועים (`--vl-ev-N`), כדי שיתפקד גם במצב כהה */
export type NavTone = 0 | 1 | 4 | 5 | 7 | 11

export interface NavSection {
  /** מפתח יציב — לזיכרון הקבוצות הפתוחות; הכותרת יכולה להשתנות */
  id: string
  title: string
  /** אייקון הקבוצה בכותרת שנפתחת ונסגרת */
  icon?: NavItem['icon']
  tone?: NavTone
  /**
   * 'top' — בלי כותרת ובלי קיפול, בראש התפריט (הבית);
   * 'footer' — בתחתית, מתחת לקבוצות (הגדרות, שנפתחות לעיתים רחוקות).
   * חסר = קבוצה שנפתחת ונסגרת.
   */
  placement?: 'top' | 'footer'
  items: NavItem[]
}

/**
 * הקבוצות נקבעות לפי *מה מחפשים* — מסך תפעולי, אדם או משאב, צוות, כסף או
 * דוח — ולא לפי "נתונים" כללי: עד עכשיו 16 מסכים ישבו תחת כותרת אחת. כל קבוצה
 * עד חמש רשומות, והתפריט מראה פתוחה רק את הקבוצה של הדף הנוכחי (AppLayout).
 * בתוך קבוצה הסדר הוא לפי תדירות הפתיחה. קבוצה שהתרוקנה בסינון נעלמת, ולכן
 * עובד שטח או קבלן עדיין רואים תפריט קצר.
 */
export const NAV_SECTIONS: NavSection[] = [
  {
    id: 'home',
    title: 'ראשי',
    placement: 'top',
    items: [
      {
        to: '/',
        page: 'dashboard',
        label: 'דשבורד',
        icon: LayoutDashboard,
        perm: PERM.DASHBOARD_VIEW,
        end: true,
        primary: true,
      },
      /* ‏0227: המשימות של מנהלי המערכת. התג האדום — כמה מהן באיחור. */
      {
        to: '/command',
        page: 'command',
        label: 'משימות ניהול',
        shortLabel: 'משימות',
        icon: ListTodo,
        perm: PERM.COMMAND_VIEW,
        audience: forAdmins,
        badge: 'command',
      },
      /* הסיכום הכספי של הקבלן — הדשבורד שלו, ולכן הוא יושב לצד הדשבורד ולא
         בקבוצת הכספים. הוא גם הרשומה הראשונה שמנהל קבלן רואה, ולכן `/` מפנה
         אליו מעצמו דרך HomeRoute. */
      {
        to: '/portal',
        page: 'portal',
        label: 'כספים ותשלומים',
        shortLabel: 'כספים',
        icon: Landmark,
        perm: PERM.PORTAL_VIEW,
        primary: true,
      },
    ],
  },
  {
    id: 'ops',
    title: 'תפעול',
    icon: ClipboardList,
    tone: 0,
    items: [
      { to: '/calendar', page: 'calendar', label: 'לוח שנה', icon: Calendar, perm: PERM.CALENDAR_VIEW, primary: true },
      {
        to: '/board',
        page: 'board',
        label: 'לו״ז עבודה',
        shortLabel: 'לו״ז',
        icon: ClipboardList,
        perm: PERM.BOARD_VIEW,
        primary: true,
      },
      { to: '/events', page: 'events', label: 'אירועים', icon: PartyPopper, perm: PERM.EVENTS_LIST, primary: true },
      /* ‏0196: הכנה והחזרה במחסן לכל אירוע. בלי `primary`, כדי שלא ידחוק את
         "אירועים" מהבר התחתון של מנהל הלקוח; ליוזר "מחסן", שזה המסך היחיד
         שלו, הבר ממלא את עצמו ממה שנשאר גלוי ממילא. */
      {
        to: '/warehouse',
        page: 'warehouse',
        label: 'לו״ז מחסן',
        shortLabel: 'מחסן',
        icon: Warehouse,
        perm: PERM.WAREHOUSE_VIEW,
        audience: forWarehouseSchedule,
      },
    ],
  },
  {
    // הקבוצה הזו היא היחידה שעובד מן השורה — ועובד קבלן שקיבל התחברות —
    // רואה בכלל, ולכן היא יושבת לפני האנשים והכסף ולא אחריהם.
    id: 'mine',
    title: 'אישי',
    icon: User,
    tone: 11,
    items: [
      {
        to: '/my/schedule',
        page: 'my_schedule',
        label: 'משמרות',
        shortLabel: 'משמרות',
        icon: CalendarClock,
        perm: PERM.ATTENDANCE_VIEW_SCHEDULE,
        audience: forEmployees,
      },
      {
        to: '/my/attendance',
        page: 'my_clock',
        label: 'שעון נוכחות',
        shortLabel: 'שעון',
        icon: Clock,
        perm: PERM.ATTENDANCE_VIEW_OWN,
        audience: forEmployees,
      },
      /* אותו מסך של "דוח נוכחות" שבקבוצת הצוות, מצומצם לשורות של המשתמש עצמו —
         השרת כבר מחזיר רק אותן. מי שמחזיק view_all מגיע אליו דרך הרשומה
         בקבוצת הצוות, ומנהל קבלן דרך "נוכחות הסגל שלי" שמתחתיה; אצל שניהם
         הרשומה הזאת נעלמת במקום להכפיל את היעד תחת כותרת צרה מדי. עובד קבלן
         אינו מחזיק אף אחד מהשניים (המודול portal סגור לו), ולכן הוא רואה אותה. */
      {
        to: '/attendance',
        page: 'attendance',
        label: 'דוח הנוכחות שלי',
        shortLabel: 'דוח',
        icon: FileClock,
        perm: PERM.ATTENDANCE_VIEW_OWN,
        hiddenBy: [PERM.ATTENDANCE_VIEW_ALL, PERM.PORTAL_ATTENDANCE],
        audience: forEmployees,
      },
      /* הצד השני של אותה הכרעה: הסגל של הקבלן. `attendance_report` כבר תוחם
         אותו לקבלן של הקורא, ולכן זה אותו מסך בהיקף אחר — ומוסתר ממי שמחזיק
         view_all, שרואה את הרשומה הרחבה יותר בקבוצת הצוות. */
      {
        to: '/attendance',
        page: 'attendance',
        label: 'נוכחות הסגל שלי',
        shortLabel: 'נוכחות',
        icon: Timer,
        perm: PERM.PORTAL_ATTENDANCE,
        hiddenBy: [PERM.ATTENDANCE_VIEW_ALL],
      },
      /* הסגל של הקבלן, ולכן רק לקבלן: המפתח לבדו הראה את המסך גם למנהל
         מערכת (שעוקף כל מפתח) ולכל איש משרד שקיבל אותו בטעות, ולשניהם אין
         סגל משלהם — `my_contractor_workers` היה מחזיר להם רשימה ריקה. */
      {
        to: '/my/staff',
        page: 'my_staff',
        label: 'העובדים שלי',
        icon: UsersRound,
        perm: PERM.PORTAL_MANAGE_WORKERS,
        audience: forContractors,
      },
      /* המקבילה של הלקוח שמבצע בעצמו (0133) — אותה רשומה, מאגר אחר. */
      {
        to: '/my/crew',
        page: 'my_crew',
        label: 'הסגל שלי',
        icon: UsersRound,
        perm: PERM.CUSTOMERS_MANAGE_OWN_STAFF,
        audience: forSelfPerformingCustomers,
      },
      /* ‏0218: התלושים ששויכו לעובד. */
      {
        to: '/my/payslips',
        page: 'my_payslips',
        label: 'תלושי השכר שלי',
        shortLabel: 'תלושים',
        icon: ScrollText,
        perm: PERM.PAYSLIPS_VIEW_OWN,
        audience: forEmployees,
      },
      {
        to: '/my/notifications',
        page: 'notifications',
        label: 'התראות',
        icon: Bell,
        perm: PERM.NOTIFICATIONS_PREFERENCES,
      },
    ],
  },
  {
    id: 'resources',
    title: 'לקוחות ומשאבים',
    icon: Building2,
    tone: 1,
    items: [
      { to: '/customers', page: 'customers', label: 'לקוחות', icon: Building2, perm: PERM.CUSTOMERS_VIEW },
      { to: '/users', page: 'users', label: 'עובדים', icon: ContactRound, perm: PERM.USERS_VIEW },
      { to: '/contractors', page: 'contractors', label: 'קבלנים', icon: HardHat, perm: PERM.CONTRACTORS_VIEW },
      {
        to: '/vehicles',
        page: 'vehicles',
        label: 'ניהול רכבים',
        shortLabel: 'רכבים',
        icon: Truck,
        perm: PERM.FLEET_VIEW,
      },
    ],
  },
  {
    id: 'crew',
    title: 'צוות ונוכחות',
    icon: UsersRound,
    tone: 4,
    items: [
      /* shortLabel 'שיבוץ' ולא 'משמרות': מי שרואה את הרשומה הזאת רואה במקביל
         גם את "משמרות" שבקבוצה האישית, ושתי רשומות באותו שם הן שתי רשומות
         שאי אפשר לבחור ביניהן. */
      {
        to: '/shifts',
        page: 'shifts',
        label: 'לוח משמרות צוות',
        shortLabel: 'שיבוץ',
        icon: CalendarRange,
        anyPerm: [PERM.ATTENDANCE_VIEW_ALL, PERM.PORTAL_ATTENDANCE],
      },
      {
        to: '/attendance',
        page: 'attendance',
        label: 'דוח נוכחות',
        shortLabel: 'נוכחות',
        icon: Timer,
        perm: PERM.ATTENDANCE_VIEW_ALL,
      },
      /* ‏0218: העלאת התלושים מרואה החשבון, שיוך ועלות מעביד. */
      {
        to: '/payslips',
        page: 'payslips',
        label: 'תלושי שכר',
        shortLabel: 'תלושים',
        icon: ScrollText,
        anyPerm: [PERM.PAYSLIPS_MANAGE, PERM.PAYSLIPS_EMPLOYER_COST],
      },
    ],
  },
  {
    id: 'money',
    title: 'כספים',
    icon: Wallet,
    tone: 5,
    items: [
      /* ‏0205: לא לשונית של "תקבולים" — השאלה כאן היא על אירועים ("מה שולם
         מהאירועים של החודש"), ושם על כסף שנכנס ("מה נכנס החודש"). */
      {
        to: '/payments',
        page: 'payments',
        label: 'תשלומי אירועים',
        shortLabel: 'תשלומים',
        icon: HandCoins,
        perm: PERM.FINANCE_EVENT_PAYMENTS_VIEW,
      },
      {
        to: '/receipts',
        page: 'receipts',
        label: 'רישום תקבולים',
        shortLabel: 'תקבולים',
        icon: Banknote,
        perm: PERM.FINANCE_RECEIPTS_VIEW,
      },
      /* ‏0207: כמה מזומן יש ביד — כל תשלום שהתקבל במזומן, פחות ההוצאות. */
      {
        to: '/wallet',
        page: 'wallet',
        label: 'ארנק מזומנים',
        shortLabel: 'ארנק',
        icon: Wallet,
        perm: PERM.FINANCE_CASH_WALLET_VIEW,
      },
      /* ‏0233: חשבוניות ספקים — סריקה, תיקייה לחודש וייצוא לרואה החשבון. */
      {
        to: '/invoices',
        page: 'invoices',
        label: 'חשבוניות',
        icon: ReceiptText,
        perm: PERM.INVOICES_MANAGE,
        audience: forAdmins,
      },
    ],
  },
  {
    id: 'reports',
    title: 'דוחות',
    icon: BarChart3,
    tone: 7,
    items: [
      {
        to: '/reports',
        page: 'reports',
        label: 'דוחות',
        shortLabel: 'דוחות',
        icon: BarChart3,
        perm: PERM.REPORTS_VIEW,
        /* שלוש הרשומות שאחריה יושבות מתחת לנתיב שלה — בלי `end` היא נצבעת
           פעילה גם כשפתוחה מפת העומסים */
        end: true,
      },
      /* מפת העומסים יושבת ראשונה בין הדוחות (0173): היא השאלה שנשאלת לפני
         שמקבלים עבודה נוספת, ולא אחרי שהחודש נגמר. */
      {
        to: '/reports/load',
        page: 'load',
        label: 'מפת עומסים',
        shortLabel: 'עומסים',
        icon: Flame,
        perm: PERM.REPORTS_LOAD,
      },
      /* שני דפי הרווחיות הם יעדים ולא לשוניות של "דוחות": הם המסכים שנפתחים
         הכי הרבה בקבוצה הזו, והדרך היחידה אליהם הייתה שני קישורים בתוך שורת
         התבניות של /reports — מקום שצריך לדעת עליו כדי למצוא אותו. */
      {
        to: '/reports/task-pnl',
        page: 'task_pnl',
        label: 'רווחיות לפי משימה',
        shortLabel: 'רווחיות',
        icon: Percent,
        perm: PERM.REPORTS_VIEW,
      },
      {
        to: '/reports/profitability',
        page: 'profitability',
        label: 'רווחיות לקוחות',
        shortLabel: 'לקוחות',
        icon: TrendingUp,
        perm: PERM.REPORTS_VIEW,
      },
    ],
  },
  {
    id: 'system',
    title: 'מערכת',
    placement: 'footer',
    items: [
      { to: '/settings', page: 'settings', label: 'הגדרות', icon: Settings, perm: PERM.SETTINGS_VIEW },
      {
        to: '/integrations',
        page: 'integrations',
        label: 'אינטגרציות',
        shortLabel: 'חיבורים',
        icon: Plug,
        perm: PERM.INTEGRATIONS_VIEW,
      },
    ],
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
  return (
    held &&
    !item.hiddenBy?.some(has) &&
    (item.audience?.(audience) ?? true) &&
    !audience.hiddenPages?.has(item.page)
  )
}

/** הרשומות בתפריט שמובילות לדף (0215) — לרוב אחת; ל"דוח נוכחות" שלוש. */
export function pageEntries(page: string, sections = NAV_SECTIONS): NavItem[] {
  return sections.flatMap((s) => s.items).filter((i) => i.page === page)
}

/**
 * האם ההרשאות לבדן פותחות את הדף — בלי גדרות "מי הוא" ובלי הסתרה. מסך
 * העריכה של הדפים שואל את זה על משתמש או תפקיד אחר, שאין לו `navAudience`,
 * כדי לומר ליד דף ש"מוצג" אינו "פתוח" כשההרשאות סוגרות אותו.
 */
export function pagePermitted(page: string, has: (perm: string) => boolean, sections = NAV_SECTIONS): boolean {
  return pageEntries(page, sections).some(
    (i) => (i.anyPerm ? i.anyPerm.some(has) : has(i.perm!)) && !i.hiddenBy?.some(has),
  )
}

/** המפתחות שהדף נשען עליהם — כדי לדעת אם הוא רלוונטי לסוג משתמש בכלל. */
export function pagePerms(page: string, sections = NAV_SECTIONS): string[] {
  return [...new Set(pageEntries(page, sections).flatMap((i) => i.anyPerm ?? (i.perm ? [i.perm] : [])))]
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
/**
 * עובד שטח — מי שאין לו דשבורד, רשימת אירועים או פורטל, אבל יש לו שעון נוכחות
 * (עובד, נהג, עובד קבלן עם התחברות). אצלו "הדבר הראשון" הוא השעון והמשמרות,
 * לא לוח השנה והלו״ז שמגיעים מהתפקיד: עד עכשיו הוא נחת בלוח השנה, והשעון
 * ישב במשבצת הרביעית בבר התחתון — הכי רחוק מהאגודל.
 */
export const FIELD_HOME = ['/my/attendance', '/my/schedule'] as const

export function isFieldUser(sections: NavSection[]): boolean {
  const flat = sections.flatMap((s) => s.items)
  return (
    flat.some((i) => i.to === FIELD_HOME[0]) &&
    /* דשבורד, רשימת אירועים או פורטל קבלן — יש לו "בית" משרדי משלו */
    !flat.some((i) => i.to === '/' || i.to === '/events' || i.to === '/portal')
  )
}

export function bottomNavItems(sections: NavSection[], slots = 4): NavItem[] {
  const flat = sections.flatMap((s) => s.items)
  const first = isFieldUser(sections)
    ? FIELD_HOME.map((to) => flat.find((i) => i.to === to)).filter((i): i is NavItem => !!i)
    : []
  const chosen = [...first, ...flat.filter((i) => i.primary && !first.includes(i))].slice(0, slots)
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
  '/warehouse': 'לו״ז מחסן',
  '/command': 'משימות ניהול',
  '/events': 'אירועים',
  '/customers': 'לקוחות',
  '/users': 'עובדים',
  '/contractors': 'קבלנים',
  '/vehicles': 'ניהול רכבים',
  '/attendance': 'דוח נוכחות',
  '/shifts': 'לוח משמרות צוות',
  '/reports': 'דוחות',
  '/reports/load': 'מפת עומסים',
  '/reports/profitability': 'רווחיות לקוחות',
  '/reports/task-pnl': 'רווחיות לפי משימה',
  '/receipts': 'רישום תקבולים',
  '/payments': 'תשלומי אירועים',
  '/wallet': 'ארנק מזומנים',
  '/payslips': 'תלושי שכר',
  '/invoices': 'חשבוניות',
  '/my/schedule': 'משמרות',
  '/my/attendance': 'שעון נוכחות',
  '/my/payslips': 'תלושי השכר שלי',
  '/my/notifications': 'התראות',
  '/my/staff': 'העובדים שלי',
  '/my/crew': 'הסגל שלי',
  '/settings': 'הגדרות',
  '/integrations': 'אינטגרציות',
  '/portal': 'כספים ותשלומים',
}

/**
 * הקבוצה של הדף הנוכחי — היא נפתחת מעצמה בתפריט. ההתאמה הארוכה ביותר
 * מנצחת, כדי ש-/reports/load ייחשב למפת העומסים ולא ל"דוחות", ופירוט
 * (/events/123) שייך לרשימה שמעליו.
 */
export function activeNavSection(sections: NavSection[], pathname: string): string | null {
  let best: { id: string; len: number } | null = null
  for (const s of sections)
    for (const i of s.items) {
      const hit = i.to === '/' ? pathname === '/' : pathname === i.to || pathname.startsWith(i.to + '/')
      if (hit && (!best || i.to.length > best.len)) best = { id: s.id, len: i.to.length }
    }
  return best?.id ?? null
}

/**
 * תפריט קצר — עובד שטח, קבלן, משתמש מחסן — מוצג פתוח כולו: לקפל קבוצה של
 * שתי רשומות רק מוסיף לחיצה. הקיפול מתחיל כשיש יותר ממה שנכנס במבט אחד.
 */
export const NAV_FOLD_FROM = 10

export function navNeedsFolding(sections: NavSection[]): boolean {
  return sections.filter((s) => !s.placement).reduce((n, s) => n + s.items.length, 0) >= NAV_FOLD_FROM
}

/** החיפוש בתפריט — לפי שם הרשומה או שם הקבוצה שלה. */
export function filterNavItems(sections: NavSection[], query: string): NavItem[] {
  const q = query.trim()
  if (!q) return []
  return sections.flatMap((s) => s.items.filter((i) => i.label.includes(q) || s.title.includes(q)))
}
