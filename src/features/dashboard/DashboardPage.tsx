import { useMemo, useState } from 'react'
import { Input, PageHeader } from '../../components/ui'
import { fmtDate, toISODate } from '../../lib/dates'
import { PERM } from '../../lib/permissions'
import { useAuth } from '../../state/auth'
import { RequirePermission } from '../auth/guards'
import { TaskDrawer } from '../tasks/TaskDrawer'
import { EventFormModal } from '../events/EventFormModal'
import { DashboardProvider } from './dashboardContext'
import { RANGE_PRESETS, defaultRange, previousRange } from './dashboardRange'
import type { DateRange } from './dashboardRange'
import { DashboardGrid } from './DashboardGrid'
import { BUILT_IN_DEFAULT, WIDGETS, WIDGETS_BY_ID } from './registry'
import { resolveLayout, visibleItems } from './layout'

/**
 * The dashboard shell.
 *
 * Everything that used to be written out here is a widget now: the page owns
 * the date range, the two overlays that have to be hosted once, and the grid.
 * Which widgets appear, how wide they are and in what order is data — see
 * `registry.tsx` for the catalogue and `layout.ts` for the maths.
 */
export default function DashboardPage() {
  const { has, me } = useAuth()
  const [range, setRange] = useState<DateRange>(defaultRange)
  const [taskDrawer, setTaskDrawer] = useState<{ open: boolean; id: string | null }>({ open: false, id: null })
  const [eventModal, setEventModal] = useState(false)

  const today = toISODate(new Date())
  const prev = useMemo(() => previousRange(range), [range])

  // no persistence yet — the built-in default is the layout
  const items = useMemo(() => resolveLayout(WIDGETS, null, BUILT_IN_DEFAULT), [])
  const visible = useMemo(
    () => visibleItems(items, WIDGETS_BY_ID, has, me?.profile.user_kind),
    [items, has, me?.profile.user_kind],
  )

  const ctx = useMemo(
    () => ({
      range,
      prev,
      today,
      openTask: (id: string) => setTaskDrawer({ open: true, id }),
      openNewTask: () => setTaskDrawer({ open: true, id: null }),
      openNewEvent: () => setEventModal(true),
    }),
    [range, prev, today],
  )

  return (
    <RequirePermission perm={PERM.DASHBOARD_VIEW}>
      <div className="space-y-4">
        <PageHeader
          title="דשבורד"
          subtitle={`${fmtDate(range.from)} – ${fmtDate(range.to)}`}
          actions={
            /* on a phone this is the widest control on the screen, so the
               presets scroll and the two date fields share one row */
            <div className="flex w-full flex-col gap-1.5 sm:w-auto sm:flex-row sm:items-center">
              <div className="scroll-row gap-1">
                {RANGE_PRESETS.map((p) => (
                  <button
                    key={p.label}
                    onClick={() => setRange(p.range())}
                    className="scroll-row-item rounded-md px-2 py-1 type-caption font-medium text-ink-tertiary transition-colors hover:bg-hover hover:text-ink"
                  >
                    {p.label}
                  </button>
                ))}
              </div>
              <div className="flex flex-wrap items-center gap-1.5">
                <Input
                  type="date"
                  inputSize="sm"
                  className="min-h-9 grow basis-32 tabular sm:min-h-0 sm:w-36 sm:grow-0 sm:basis-auto"
                  value={range.from}
                  onChange={(e) => setRange((r) => ({ ...r, from: e.target.value }))}
                  aria-label="מתאריך"
                />
                <span className="shrink-0 type-caption text-ink-tertiary">–</span>
                <Input
                  type="date"
                  inputSize="sm"
                  className="min-h-9 grow basis-32 tabular sm:min-h-0 sm:w-36 sm:grow-0 sm:basis-auto"
                  value={range.to}
                  onChange={(e) => setRange((r) => ({ ...r, to: e.target.value }))}
                  aria-label="עד תאריך"
                />
              </div>
            </div>
          }
        />

        <DashboardProvider value={ctx}>
          <DashboardGrid items={visible} byId={WIDGETS_BY_ID} />
        </DashboardProvider>

        <TaskDrawer
          open={taskDrawer.open}
          onClose={() => setTaskDrawer({ open: false, id: null })}
          taskId={taskDrawer.id}
        />
        <EventFormModal open={eventModal} onClose={() => setEventModal(false)} />
      </div>
    </RequirePermission>
  )
}
