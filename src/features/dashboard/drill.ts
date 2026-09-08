import { PERM } from '../../lib/permissions'

/**
 * Where a number on the dashboard leads.
 *
 * A summary card answers "how many"; the next question is always "which ones",
 * and the answer is always on another screen. Until now the dashboard had two
 * ways to say that — the task drawer and the event modal — and every chart was
 * a picture you could not press.
 *
 * The pair below is deliberately small and deliberately *pure*: a target is a
 * plain object, `drillHref` turns it into a URL, and a unit test can hold the
 * whole thing without a router. The permission on each target is the same key
 * `router.tsx` guards that route with, and it is checked before the widget
 * offers the click rather than after — a bar that navigates to a page the
 * reader is bounced off is worse than a bar that does nothing.
 *
 * Every parameter name here is one the destination screen already reads
 * (`?date=` on the board, `?task=` on the drawer), or one added alongside it in
 * the same style. A target that would need a screen to learn a new filter is
 * not in this list.
 */

export type DrillTarget =
  | { to: 'customer'; id: string }
  | { to: 'event'; id: string }
  | { to: 'events'; customer?: string; q?: string }
  | { to: 'board'; date?: string; status?: string }
  | { to: 'calendar' }
  | { to: 'contractor'; id: string }
  | { to: 'contractors' }
  | { to: 'vehicles' }
  | { to: 'vehicle'; id: string }
  | { to: 'receipts' }
  | { to: 'reports' }
  | { to: 'shifts' }
  | { to: 'attendance' }
  | { to: 'users' }

/** the key `router.tsx` guards the destination with — `anyPerm` routes list both */
export const DRILL_PERMS: Record<DrillTarget['to'], string[]> = {
  customer: [PERM.CUSTOMERS_VIEW],
  event: [PERM.EVENTS_VIEW],
  events: [PERM.EVENTS_LIST],
  board: [PERM.BOARD_VIEW],
  calendar: [PERM.CALENDAR_VIEW],
  contractor: [PERM.CONTRACTORS_VIEW],
  contractors: [PERM.CONTRACTORS_VIEW],
  vehicles: [PERM.FLEET_VIEW],
  vehicle: [PERM.FLEET_VIEW],
  receipts: [PERM.FINANCE_RECEIPTS_VIEW],
  reports: [PERM.REPORTS_VIEW],
  shifts: [PERM.ATTENDANCE_VIEW_ALL, PERM.PORTAL_ATTENDANCE],
  attendance: [PERM.ATTENDANCE_VIEW_OWN],
  users: [PERM.USERS_VIEW],
}

/** any one of the listed keys is enough — `/shifts` is the only route with two */
export function canDrill(target: DrillTarget, has: (key: string) => boolean): boolean {
  return DRILL_PERMS[target.to].some((p) => has(p))
}

function query(pairs: Record<string, string | undefined>): string {
  const q = new URLSearchParams()
  for (const [k, v] of Object.entries(pairs)) if (v) q.set(k, v)
  const s = q.toString()
  return s ? `?${s}` : ''
}

export function drillHref(target: DrillTarget): string {
  switch (target.to) {
    case 'customer':
      return `/customers/${target.id}`
    case 'event':
      return `/events/${target.id}`
    case 'events':
      return `/events${query({ customer: target.customer, q: target.q })}`
    case 'board':
      /* Both are read at the board's initialisation, alongside `?task=`. A
         parameter the destination ignores would look like a filter and be
         silently dropped, which is worse than not offering it at all. */
      return `/board${query({ date: target.date, status: target.status })}`
    case 'contractor':
      return `/contractors/${target.id}`
    case 'vehicle':
      return `/vehicles/${target.id}`
    case 'calendar':
      return '/calendar'
    case 'contractors':
      return '/contractors'
    case 'vehicles':
      return '/vehicles'
    case 'receipts':
      return '/receipts'
    case 'reports':
      return '/reports'
    case 'shifts':
      return '/shifts'
    case 'attendance':
      return '/attendance'
    case 'users':
      return '/users'
  }
}

/**
 * Is this aggregate row carrying an entity id, or only a name?
 *
 * Before 0151 every aggregate in `dashboard_stats` grouped by name, so a row's
 * key was a display string. A client on this release talking to a server that
 * has not had the migration yet still gets those — and `?customer=<a name>`
 * filters a list to nothing, which reads as a broken screen rather than as a
 * missing migration. So a drill that needs an id asks first.
 */
export function isEntityId(key: string | undefined): key is string {
  return !!key && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(key)
}
