import { createContext, useContext } from 'react'
import type { ReactNode } from 'react'
import type { DateRange } from './dashboardRange'

/**
 * What every widget needs from the page and cannot fetch for itself: the date
 * range the header controls, and the two overlays that must be hosted once at
 * page level rather than once per widget.
 *
 * Data is deliberately *not* here — widgets call the query hooks in
 * `dashboardQueries.ts` and react-query dedupes them. A context carrying
 * payloads would make every widget re-render whenever any of them refetched.
 */
export interface DashboardCtxValue {
  range: DateRange
  /** the same span immediately before `range`, for "vs. previous period" */
  prev: DateRange
  today: string
  openTask: (id: string) => void
  openNewTask: () => void
  openNewEvent: () => void
}

const Ctx = createContext<DashboardCtxValue | null>(null)

export function DashboardProvider({ value, children }: { value: DashboardCtxValue; children: ReactNode }) {
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useDashboard(): DashboardCtxValue {
  const v = useContext(Ctx)
  if (!v) throw new Error('useDashboard must be used inside a DashboardProvider')
  return v
}
