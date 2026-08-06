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
  icon: ComponentType<{ size?: number | string; strokeWidth?: number | string; className?: string }>
  /** permission resource checked with `can(resource, 'view')` */
  resource: string
  /** key of a live counter rendered as a badge */
  badge?: 'overdue'
  end?: boolean
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
      { to: '/', label: 'דשבורד', icon: LayoutDashboard, resource: 'dashboard', end: true },
      { to: '/calendar', label: 'לוח שנה', icon: Calendar, resource: 'events' },
      { to: '/board', label: 'לוח עבודה', icon: ClipboardList, resource: 'tasks', badge: 'overdue' },
    ],
  },
  {
    title: 'נתונים',
    items: [
      { to: '/events', label: 'אירועים', icon: PartyPopper, resource: 'events' },
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
