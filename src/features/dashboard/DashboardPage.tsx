import { Suspense, lazy, useMemo, useState } from 'react'
import { Button, Input, PageHeader, Skeleton, StickySaveBar, useConfirm, useToast } from '../../components/ui'
import { Download, ICON, LayoutGrid, STROKE, SlidersHorizontal } from '../../components/ui/icons'
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
import { useDashboardSections } from './useDashboardData'
import { hideWidget, moveByIds, moveByOffset, setSize, showWidget } from './layout'
import { buildDashboardExport, writeDashboardExport } from './exportDashboard'
import { useReportCatalog } from './builder/useReportCatalog'
import { toUuid } from './builder/customRegistry'
import type { BuilderTarget } from './builder/WidgetBuilderDrawer'
import type { WidgetSize } from './dashboardTypes'

/* dnd-kit only exists once someone opens edit mode. The dashboard is the most
   visited screen in the product; its ordinary render should not carry a drag
   library most sessions never activate. */
const DashboardEditGrid = lazy(() => import('./DashboardEditGrid'))

/* Same bargain for the builder: pickers, the filter editor and a live preview
   are a screen most sessions never open, and the dashboard's ordinary render
   should not carry them. */
const WidgetBuilderDrawer = lazy(() =>
  import('./builder/WidgetBuilderDrawer').then((m) => ({ default: m.WidgetBuilderDrawer })),
)

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
  const [builder, setBuilder] = useState<BuilderTarget | null>(null)

  const today = toISODate(new Date())
  const prev = useMemo(() => previousRange(range), [range])
  const layout = useDashboardLayout()
  const canCustomize = has(PERM.DASHBOARD_CUSTOMIZE)
  const custom = layout.customWidgets
  /* The catalogue is only needed by the builder, so it is fetched by the page
     rather than the drawer: opening the editor should not wait a round trip
     before it can draw its first picker. */
  const reportCatalog = useReportCatalog()
  const confirmDelete = useConfirm()

  const ownIds = useMemo(
    () => new Set(custom.rows.filter((r) => r.is_mine).map((r) => `custom.${r.id.replace(/-/g, '')}`)),
    [custom.rows],
  )

  const editCustom = (widgetId: string) => {
    const uuid = toUuid(widgetId)
    const row = custom.rows.find((r) => r.id === uuid)
    if (row) setBuilder({ row })
  }

  /* Soft-deleted, so every layout still holding the id degrades quietly:
     `resolveLayout` drops an id it cannot resolve, which is the same path a
     retired hand-written widget takes. */
  const deleteCustom = async (widgetId: string) => {
    const uuid = toUuid(widgetId)
    if (!uuid) return
    const def = layout.byId.get(widgetId)
    const ok = await confirmDelete.confirm(
      `למחוק את "${def?.title ?? 'הווידג׳ט'}"? הוא יוסר גם ממי שהוסיף אותו לדשבורד שלו.`,
      { title: 'מחיקת ווידג׳ט', confirmLabel: 'מחיקה', tone: 'danger' },
    )
    if (!ok) return
    await guard(() => custom.remove(uuid))
  }

  /* The union of the visible widgets' sections has to be known before the
     first widget renders — the server is told what to compute — so the request
     is issued here and handed down rather than fetched per widget. */
  const sections = useDashboardSections(layout.visible, layout.byId, range, prev)

  const ctx = useMemo(
    () => ({
      range,
      prev,
      today,
      sections,
      openTask: (id: string) => setTaskDrawer({ open: true, id }),
      openNewTask: () => setTaskDrawer({ open: true, id: null }),
      openNewEvent: () => setEventModal(true),
    }),
    [range, prev, today, sections],
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
      const meta = layout.byId.get(id)
      if (!meta) return s
      return on ? showWidget(s.items, s.hidden, meta, layout.byId) : hideWidget(s.items, s.hidden, id)
    })

  /* Exports exactly what is on screen, in the order it was arranged — the
     file is the view, not "all the data". Every number comes from the section
     as the server returned it; nothing is recomputed on the way out. */
  const exportXlsx = async () => {
    const plan = buildDashboardExport(
      layout.visible,
      layout.byId,
      sections.section,
      range,
      sections.customResult,
    )
    const blob = await writeDashboardExport(plan)
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `dashboard-${range.from}-${range.to}.xlsx`
    a.click()
    URL.revokeObjectURL(url)
    if (plan.sheets.length === 0) toast.info('אין נתונים לייצוא בווידג׳טים המוצגים')
  }

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
              <div className="flex items-center gap-1.5">
                {has(PERM.DASHBOARD_EXPORT) && (
                  <Button size="sm" variant="ghost" onClick={() => void guard(exportXlsx)}>
                    <Download size={ICON.sm} strokeWidth={STROKE} />
                    ייצוא
                  </Button>
                )}
                {canCustomize && (
                  <>
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
                  </>
                )}
              </div>
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
                byId={layout.byId}
                onMove={onMove}
                onReorder={onReorder}
                onSize={onSize}
                onRemove={onRemove}
              />
            </Suspense>
          ) : (
            <DashboardGrid items={layout.visible} byId={layout.byId} />
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
          widgets={layout.widgets}
          onToggle={onToggle}
          onMove={onMove}
          canBuild={custom.canBuild}
          ownIds={ownIds}
          onNew={(variant) => setBuilder({ row: null, variant })}
          onEdit={editCustom}
          onDelete={(id) => void deleteCustom(id)}
        />

        {/* mounted only once someone asks for it, so the lazy chunk is not
            fetched on an ordinary dashboard load */}
        {builder && (
          <Suspense fallback={null}>
            <WidgetBuilderDrawer
              open
              target={builder}
              catalog={reportCatalog.catalog}
              catalogLoading={reportCatalog.isLoading}
              range={range}
              saving={custom.saving}
              onClose={() => setBuilder(null)}
              onSave={async (input) => {
                const id = await custom.save(input)
                /* A brand-new widget is invisible until it is on the layout,
                   and nobody builds one in order to hide it. An edit changes
                   nothing about placement. */
                if (!input.id) onToggle(`custom.${id.replace(/-/g, '')}`, true)
              }}
            />
          </Suspense>
        )}

        {confirmDelete.dialog}

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
