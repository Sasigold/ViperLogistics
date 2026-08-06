import {
  Building2,
  Calendar,
  ClipboardList,
  HardHat,
  LayoutDashboard,
  PartyPopper,
  Settings,
  Users,
} from '../components/ui/icons'
import type { ComponentType } from 'react'

export interface NavItem {
  to: string
  label: string
  /** shorter label for the mobile bottom bar, where a slot is ~4rem wide */
  shortLabel?: string
  icon: ComponentType<{ size?: number | string; strokeWidth?: number | string; className?: string }>
  /** permission resource checked with `can(resource, 'view')` */
  resource: string
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
      { to: '/', label: 'דשבורד', icon: LayoutDashboard, resource: 'dashboard', end: true, primary: true },
      { to: '/calendar', label: 'לוח שנה', icon: Calendar, resource: 'events', primary: true },
      { to: '/board', label: 'לוח עבודה', shortLabel: 'לוח', icon: ClipboardList, resource: 'tasks', badge: 'overdue', primary: true },
    ],
  },
  {
    title: 'נתונים',
    items: [
      { to: '/events', label: 'אירועים', icon: PartyPopper, resource: 'events', primary: true },
      { to: '/customers', label: 'לקוחות', icon: Building2, resource: 'customers' },
      { to: '/users', label: 'עובדים', icon: Users, resource: 'users' },
      { to: '/contractors', label: 'קבלנים', icon: HardHat, resource: 'contractors' },
    ],
  },
  {
    title: 'מערכת',
    items: [{ to: '/settings', label: 'הגדרות', icon: Settings, resource: 'settings' }],
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
  '/settings': 'הגדרות',
  '/portal': 'פורטל קבלן',
}
