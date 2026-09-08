import { useCallback, useMemo } from 'react'
import { useNavigate } from 'react-router'
import { useAuth } from '../../state/auth'
import { useCustomers } from '../../lib/queries'
import { canDrill, drillHref } from './drill'
import type { DrillTarget } from './drill'

/**
 * "Take me to the rows behind this number", or `undefined`.
 *
 * The `undefined` is the point, and it is the same idiom `openTask` already
 * uses in `dashboardContext`: a widget that gets nothing back stops drawing
 * itself as pressable, instead of offering a click that lands on a guard. So
 * the caller asks about the target it would navigate to, not about a key.
 *
 *   const drill = useDrill({ to: 'customer', id: '' })
 *   <SeriesCard onSelect={drill && ((r) => drill({ to: 'customer', id: r.key }))} />
 *
 * The probe carries a placeholder id because permission is a property of the
 * *route*, never of the row: `/customers/:id` is one key whichever customer is
 * behind it.
 */
export function useDrill(probe: DrillTarget): ((target: DrillTarget) => void) | undefined {
  const has = useAuth((s) => s.has)
  const navigate = useNavigate()
  const allowed = canDrill(probe, has)

  const go = useCallback(
    (target: DrillTarget) => {
      if (!canDrill(target, has)) return
      navigate(drillHref(target))
    },
    [has, navigate],
  )

  return allowed ? go : undefined
}

/**
 * A customer's name → the events list filtered to that customer.
 *
 * `dashboard_stats.by_customer` carries a name and no id — it counts tasks and
 * has never had to identify anybody — so the id has to come from somewhere.
 * `?q=` was the obvious shortcut and it is wrong: the events list searches the
 * end client, the event number and the location, never the customer, so the
 * click would land on an empty table and read as a broken feature.
 *
 * The customers list is one small cached query shared with the events screen,
 * the board and the calendar, and it is only asked for when a widget actually
 * declares this drill.
 */
export function useCustomerDrill(enabled: boolean): ((name: string) => DrillTarget) | undefined {
  const { data = [] } = useCustomers(enabled)
  const byName = useMemo(() => new Map(data.map((c) => [c.name, c.id])), [data])
  if (!enabled) return undefined
  return (name: string) => {
    const id = byName.get(name)
    /* No match — a task counted under a name the customers table no longer has,
       or a list that has not landed yet. The unfiltered list is a worse answer
       than the filtered one and a much better answer than a dead bar. */
    return id ? { to: 'events', customer: id } : { to: 'events' }
  }
}
