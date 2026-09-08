import { describe, expect, it } from 'vitest'
import { PERM } from '../../lib/permissionKeys'
import { DRILL_PERMS, canDrill, drillHref } from './drill'
import type { DrillTarget } from './drill'

const PERM_KEYS = new Set<string>(Object.values(PERM))

/* One of each, so the exhaustive switch in `drillHref` has to answer for all of
   them and a target added without a URL fails here rather than in a click. */
const EVERY: DrillTarget[] = [
  { to: 'customer', id: 'c1' },
  { to: 'event', id: 'e1' },
  { to: 'events' },
  { to: 'board' },
  { to: 'calendar' },
  { to: 'contractor', id: 'k1' },
  { to: 'contractors' },
  { to: 'vehicles' },
  { to: 'vehicle', id: 'v1' },
  { to: 'receipts' },
  { to: 'reports' },
  { to: 'shifts' },
  { to: 'attendance' },
  { to: 'users' },
]

describe('drill targets', () => {
  it('every kind produces an absolute path', () => {
    for (const t of EVERY) expect(drillHref(t)).toMatch(/^\//)
  })

  /* The permission on each target is the key `router.tsx` guards that route
     with. A typo here does not fail loudly — it just silently hides a drill, or
     worse, offers one that bounces. */
  it('every kind is gated by at least one real permission key', () => {
    for (const t of EVERY) {
      const keys = DRILL_PERMS[t.to]
      expect(keys.length).toBeGreaterThan(0)
      for (const k of keys) expect(PERM_KEYS).toContain(k)
    }
  })

  it('names the row it was given', () => {
    expect(drillHref({ to: 'customer', id: 'abc' })).toBe('/customers/abc')
    expect(drillHref({ to: 'event', id: 'abc' })).toBe('/events/abc')
    expect(drillHref({ to: 'vehicle', id: 'abc' })).toBe('/vehicles/abc')
    expect(drillHref({ to: 'contractor', id: 'abc' })).toBe('/contractors/abc')
  })

  it('adds only the query parameters that were asked for', () => {
    expect(drillHref({ to: 'events' })).toBe('/events')
    expect(drillHref({ to: 'events', customer: 'c1' })).toBe('/events?customer=c1')
    expect(drillHref({ to: 'events', q: 'דני' })).toBe(`/events?q=${encodeURIComponent('דני')}`)
    expect(drillHref({ to: 'board', date: '2026-03-01' })).toBe('/board?date=2026-03-01')
  })

  /* An empty string is what an unresolved lookup produces, and `?customer=`
     with nothing after it would filter the list to no customer at all. */
  it('drops an empty parameter rather than filtering on nothing', () => {
    expect(drillHref({ to: 'events', customer: '' })).toBe('/events')
  })
})

describe('canDrill', () => {
  const holds = (...keys: string[]) => (k: string) => keys.includes(k)

  it('is false without the destination route’s key', () => {
    expect(canDrill({ to: 'customer', id: 'c1' }, () => false)).toBe(false)
    expect(canDrill({ to: 'customer', id: 'c1' }, holds(PERM.CUSTOMERS_VIEW))).toBe(true)
  })

  /* `/shifts` is the one route `router.tsx` guards with `anyPerm` — the roster
     answers two audiences from one query, and either key opens it. */
  it('accepts any one key where the route does', () => {
    expect(canDrill({ to: 'shifts' }, holds(PERM.PORTAL_ATTENDANCE))).toBe(true)
    expect(canDrill({ to: 'shifts' }, holds(PERM.ATTENDANCE_VIEW_ALL))).toBe(true)
    expect(canDrill({ to: 'shifts' }, holds(PERM.BOARD_VIEW))).toBe(false)
  })
})
