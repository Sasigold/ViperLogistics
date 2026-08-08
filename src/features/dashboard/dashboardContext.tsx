import { createContext, useContext, useMemo } from 'react'
import type { ReactNode } from 'react'
import type { DateRange } from './dashboardRange'
import type { DashboardSections } from './useDashboardData'

/**
 * What every widget needs from the page and cannot fetch for itself.
 *
 * Two different things live here for two different reasons. The range and the
 * overlays are page-level state. The *sections*, though, are here because the
 * server has to be told up front which ones to compute — that question can
 * only be answered by looking at the whole grid, so the request is issued once
 * at this level and handed down.
 *
 * Anything a widget can fetch on its own still does: `dashboardQueries.ts`
 * holds those, and react-query dedupes eight tiles asking the same question
 * into one request.
 */
export interface DashboardCtxValue {
  range: DateRange
  /** the same span immediately before `range`, for "vs. previous period" */
  prev: DateRange
  today: string
  sections: DashboardSections
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

/**
 * One section, typed at the call site.
 *
 * `null` and `undefined` mean different things and the caller has to be able
 * to tell them apart: `undefined` is "not loaded yet", `null` is the server
 * saying this section is not for this reader. The first draws a skeleton, the
 * second removes the widget from the page.
 */
export function useSection<T>(key: string): {
  data: T | null | undefined
  prev: T | null | undefined
  isLoading: boolean
  error: unknown
} {
  const { sections } = useDashboard()
  const data = sections.section(key) as T | null | undefined
  const prev = sections.prevSection(key) as T | null | undefined
  return useMemo(
    () => ({ data, prev, isLoading: sections.isLoading, error: sections.error }),
    [data, prev, sections.isLoading, sections.error],
  )
}
