import { Calendar, ClipboardList, LayoutDashboard, PartyPopper, Users } from '../../components/ui/icons'
import { PERM } from '../../lib/permissions'
import type { ComponentType } from 'react'

export interface ClientNavItem {
  to: string
  label: string
  icon: ComponentType<{ size?: number | string; strokeWidth?: number | string; className?: string }>
  /** registry key checked with `has(key)` */
  perm: string
}

/**
 * The client portal's sections, in the order a client works through them.
 * Every one is gated: the owner decides per user which of these exist at all,
 * so a portal with a single visible section is a normal configuration.
 */
export const CLIENT_NAV: ClientNavItem[] = [
  { to: '/client/dashboard', label: 'סקירה', icon: LayoutDashboard, perm: PERM.DASHBOARD_VIEW },
  { to: '/client/events', label: 'אירועים', icon: PartyPopper, perm: PERM.EVENTS_VIEW },
  { to: '/client/calendar', label: 'לוח שנה', icon: Calendar, perm: PERM.CALENDAR_VIEW },
  { to: '/client/tasks', label: 'משימות', icon: ClipboardList, perm: PERM.TASKS_VIEW },
  { to: '/client/users', label: 'משתמשים', icon: Users, perm: PERM.USERS_VIEW },
]
