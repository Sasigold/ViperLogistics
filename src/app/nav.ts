import {
  Bell,
  Building2,
  Calendar,
  CalendarClock,
  ClipboardList,
  Clock,
  HardHat,
  LayoutDashboard,
  PartyPopper,
  Settings,
  Users,
} from '../components/ui/icons'
import type { ComponentType } from 'react'
import { PERM } from '../lib/permissions'

export interface NavItem {
  to: string
  label: string
  /** shorter label for the mobile bottom bar, where a slot is ~4rem wide */
  shortLabel?: string
  icon: ComponentType<{ size?: number | string; strokeWidth?: number | string; className?: string }>
  /** registry key checked with `has(perm)` */
  perm: string
  /** key of a live counter rendered as a badge */
  badge?: 'overdue'
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
      { to: '/calendar', label: 'לוח שנה', icon: Calendar, perm: PERM.CALENDAR_VIEW, primary: true },
      { to: '/board', label: 'לוח עבודה', shortLabel: 'לוח', icon: ClipboardList, perm: PERM.BOARD_VIEW, badge: 'overdue', primary: true },
    ],
  },
  {
    // הסקשן הזה הוא היחיד שעובד מן השורה — ועובד קבלן שקיבל התחברות —
    // רואה בכלל, ולכן הוא יושב לפני הנתונים ולא אחריהם.
    title: 'הנוכחות שלי',
    items: [
      { to: '/my/schedule', label: 'לוח המשמרות שלי', shortLabel: 'משמרות', icon: CalendarClock, perm: PERM.ATTENDANCE_VIEW_SCHEDULE },
      { to: '/my/attendance', label: 'שעון נוכחות', shortLabel: 'שעון', icon: Clock, perm: PERM.ATTENDANCE_VIEW_OWN },
      { to: '/my/notifications', label: 'התראות', icon: Bell, perm: PERM.NOTIFICATIONS_PREFERENCES },
    ],
  },
  {
    title: 'נתונים',
    items: [
      { to: '/events', label: 'אירועים', icon: PartyPopper, perm: PERM.EVENTS_VIEW, primary: true },
      { to: '/customers', label: 'לקוחות', icon: Building2, perm: PERM.CUSTOMERS_VIEW },
      { to: '/users', label: 'עובדים', icon: Users, perm: PERM.USERS_VIEW },
      { to: '/contractors', label: 'קבלנים', icon: HardHat, perm: PERM.CONTRACTORS_VIEW },
      { to: '/attendance', label: 'דוח נוכחות', shortLabel: 'נוכחות', icon: Clock, perm: PERM.ATTENDANCE_VIEW_ALL },
    ],
  },
  {
    title: 'מערכת',
    items: [{ to: '/settings', label: 'הגדרות', icon: Settings, perm: PERM.SETTINGS_VIEW }],
  },
]

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
  '/board': 'לוח עבודה',
  '/events': 'אירועים',
  '/customers': 'לקוחות',
  '/users': 'עובדים',
  '/contractors': 'קבלנים',
  '/attendance': 'דוח נוכחות',
  '/my/schedule': 'לוח המשמרות שלי',
  '/my/attendance': 'שעון נוכחות',
  '/my/notifications': 'התראות',
  '/settings': 'הגדרות',
  '/portal': 'פורטל קבלן',
}
