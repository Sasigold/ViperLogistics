import { Suspense, lazy, useMemo, useState } from 'react'
import { Button, Input, PageHeader, Skeleton, StickySaveBar, useToast } from '../../components/ui'
import { ICON, LayoutGrid, STROKE, SlidersHorizontal } from '../../components/ui/icons'
import { fmtDate, toISODate } from '../../lib/dates'
import { errorMessage } from '../../lib/errors'
import { PERM } from '../../lib/permissions'
import { useAuth } from '../../state/auth'
import { RequirePermission } from '../auth/guards'
import { TaskDrawer } from '../tasks/TaskDrawer'
import { EventFormModal } from '../events/EventFormModal'
import { DashboardProvider } from './dashboardContext'
import { RANGE_PRESETS, defaultRange, previousRange } from './dashboardRange'
import type { DateRange } from './dashboardRange'
import { DashboardGrid } from './DashboardGrid'
import { CustomizeDrawer } from './CustomizeDrawer'
import { SavedViewsMenu } from './SavedViewsMenu'
import { useDashboardLayout } from './useDashboardLayout'
import { WIDGETS, WIDGETS_BY_ID } from './registry'
import { hideWidget, moveByIds, moveByOffset, setSize, showWidget } from './layout'
import type { WidgetSize } from './dashboardTypes'

/* dnd-kit only exists once someone opens edit mode. The dashboard is the most
   visited screen in the product; its ordinary render should not carry a drag
   library most sessions never activate. */
const DashboardEditGrid = lazy(() => import('./DashboardEditGrid'))

/**
 * The dashboard shell.
 *
 * It owns three things and nothing else: the date range, the two overlays that
 * have to be hosted once for the whole page, and the grid. What appears in the
 * grid, how wide each thing is and in what order, is data — `registry.tsx` for
 * the catalogue, `layout.ts` for the maths, `useDashboardLayout` for where it
 * is stored.
 */
export default function DashboardPage() {
  const has = useAuth((s) => s.has)
  const toast = useToast()
  const [range, setRange] = useState<DateRange>(defaultRange)
  const [taskDrawer, setTaskDrawer] = useState<{ open: boolean; id: string | null }>({ open: false, id: null })
  const [eventModal, setEventModal] = useState(false)
  const [editing, setEditing] = useState(false)
  const [catalogue, setCatalogue] = useState(false)

  const today = toISODate(new Date())
  const prev = useMemo(() => previousRange(range), [range])
  const layout = useDashboardLayout()
  const canCustomize = has(PERM.DASHBOARD_CUSTOMIZE)

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

  /* Every edit goes through `layout.edit`, and every one of them works in id
     space. The rendered list is a permission-filtered subset of the stored
     one, so an index from the grid does not address the same element as an
     index into storage. */
  const visibleIds = layout.visible.map((i) => i.id)
  const onMove = (id: string, offset: number) =>
    layout.edit((s) => ({ ...s, items: moveByOffset(s.items, id, offset, visibleIds) }))
  const onReorder = (activeId: string, overId: string) =>
    layout.edit((s) => ({ ...s, items: moveByIds(s.items, activeId, overId) }))
  const onSize = (id: string, size: WidgetSize) =>
    layout.edit((s) => ({ ...s, items: setSize(s.items, id, size) }))
  const onRemove = (id: string) => layout.edit((s) => hideWidget(s.items, s.hidden, id))
  const onToggle = (id: string, on: boolean) =>
    layout.edit((s) => {
      const meta = WIDGETS_BY_ID.get(id)
      if (!meta) return s
      return on ? showWidget(s.items, s.hidden, meta, WIDGETS_BY_ID) : hideWidget(s.items, s.hidden, id)
    })

  const guard = async (run: () => Promise<unknown>) => {
    try {
      await run()
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

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
              {canCustomize && (
                <div className="flex items-center gap-1.5">
                  <SavedViewsMenu
                    views={layout.namedViews}
                    hasOwnLayout={layout.hasOwnLayout}
                    onApply={layout.applyView}
                    onSaveAs={(name) => guard(() => layout.save(name))}
                    onDelete={(id) => guard(() => layout.deleteView(id))}
                    onReset={() => guard(layout.reset)}
                    onPublishDefault={(k) => guard(() => layout.saveOrgDefault(k))}
                  />
                  <Button size="sm" variant={editing ? 'primary' : 'ghost'} onClick={() => setEditing((v) => !v)}>
                    <LayoutGrid size={ICON.sm} strokeWidth={STROKE} />
                    {editing ? 'סיום עריכה' : 'התאמה אישית'}
                  </Button>
                </div>
              )}
            </div>
          }
        />

        {editing && (
          <div className="flex flex-wrap items-center gap-2">
            <Button size="sm" onClick={() => setCatalogue(true)}>
              <SlidersHorizontal size={ICON.sm} strokeWidth={STROKE} />
              הוספת ווידג׳טים
            </Button>
            <span className="type-caption text-ink-tertiary">
              גררו מהידית, או השתמשו בחצים — הסדר והגודל נשמרים לחשבון שלכם
            </span>
          </div>
        )}

        <DashboardProvider value={ctx}>
          {editing ? (
            <Suspense fallback={<Skeleton className="h-64 w-full" />}>
              <DashboardEditGrid
                items={layout.visible}
                byId={WIDGETS_BY_ID}
                onMove={onMove}
                onReorder={onReorder}
                onSize={onSize}
                onRemove={onRemove}
              />
            </Suspense>
          ) : (
            <DashboardGrid items={layout.visible} byId={WIDGETS_BY_ID} />
          )}
        </DashboardProvider>

        {editing && (
          <StickySaveBar
            dirty={layout.dirty}
            saving={layout.saving}
            onSave={() => void guard(() => layout.save())}
            onReset={layout.discard}
          />
        )}

        <CustomizeDrawer
          open={catalogue}
          onClose={() => setCatalogue(false)}
          items={layout.visible}
          hidden={layout.hidden}
          widgets={WIDGETS}
          onToggle={onToggle}
          onMove={onMove}
        />

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
