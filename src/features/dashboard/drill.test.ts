import { describe, expect, it } from 'vitest'
import { PERM } from '../../lib/permissionKeys'
import { DRILL_PERMS, canDrill, drillHref, isEntityId } from './drill'
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
    expect(drillHref({ to: 'board', status: 'abc' })).toBe('/board?status=abc')
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

describe('isEntityId', () => {
  /* The whole point: a row from a server without 0151 carries a display name
     where a newer one carries a uuid, and `?customer=<a name>` filters a list
     to nothing — which reads as a broken screen, not a missing migration. */
  it('tells a uuid from a name', () => {
    expect(isEntityId('10000000-0000-0000-0000-000000000371')).toBe(true)
    expect(isEntityId('10000000-0000-0000-0000-000000000371'.toUpperCase())).toBe(true)
    expect(isEntityId('לקוח 37')).toBe(false)
    expect(isEntityId('')).toBe(false)
    expect(isEntityId(undefined)).toBe(false)
  })

  it('is not fooled by something merely uuid-shaped', () => {
    expect(isEntityId('10000000-0000-0000-0000-00000000037')).toBe(false)
    expect(isEntityId('10000000000000000000000000000371')).toBe(false)
    expect(isEntityId('zzzzzzzz-0000-0000-0000-000000000371')).toBe(false)
  })
})
