import { Suspense, useEffect, useMemo, useRef, useState } from 'react'
import {
  Button,
  ErrorState,
  IconButton,
  Input,
  PageHeader,
  Skeleton,
  StickySaveBar,
  useConfirm,
  useToast,
} from '../../components/ui'
import { Download, ICON, LayoutGrid, RefreshCw, STROKE, SlidersHorizontal } from '../../components/ui/icons'
import { fmtDate, toISODate } from '../../lib/dates'
import { errorMessage } from '../../lib/errors'
import { PERM } from '../../lib/permissions'
import { lazyPage } from '../../lib/lazyPage'
import { useAuth } from '../../state/auth'
import { RequirePermission } from '../auth/guards'
import { TaskDrawer, useCanOpenTaskCard } from '../tasks/TaskDrawer'
import { EventFormModal } from '../events/EventFormModal'
import { DashboardProvider } from './dashboardContext'
import { RANGE_PRESETS, defaultRange, isWholeMonth, monthRange, previousRange, stepMonth } from './dashboardRange'
import type { DateRange } from './dashboardRange'
import { DashboardGrid } from './DashboardGrid'
import { MonthStepper } from './MonthStepper'
import { CustomizeDrawer } from './CustomizeDrawer'
import { SavedViewsMenu } from './SavedViewsMenu'
import { ViewSettingsMenu } from './ViewSettingsMenu'
import { useDashboardLayout } from './useDashboardLayout'
import { useDashboardSections } from './useDashboardData'
import {
  hideWidget,
  mergeView,
  moveByIds,
  moveByOffset,
  packingOf,
  setHeight,
  setLock,
  setOpt,
  setSize,
  showWidget,
} from './layout'
import { buildDashboardExport, writeDashboardExport } from './exportDashboard'
import { useReportCatalog } from './builder/useReportCatalog'
import { toUuid } from './builder/customRegistry'
import type { BuilderTarget } from './builder/WidgetBuilderDrawer'
import type { LayoutState } from './layout'
import type { ViewPrefs, WidgetSize } from './dashboardTypes'

/* dnd-kit only exists once someone opens edit mode. The dashboard is the most
   visited screen in the product; its ordinary render should not carry a drag
   library most sessions never activate. */
const DashboardEditGrid = lazyPage(() => import('./DashboardEditGrid'))

/* Same bargain for the builder: pickers, the filter editor and a live preview
   are a screen most sessions never open, and the dashboard's ordinary render
   should not carry them. */
const WidgetBuilderDrawer = lazyPage(() =>
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
  const canOpenTaskCard = useCanOpenTaskCard()
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
  /* ‏0144. הלקוח נשאר על `defaultRange()` — החודש הנוכחי — שהוא בדיוק מה
     שהוא נשאל עליו. הכותרת ממשיכה לומר את התאריכים גם כשאין מה לשנות בהם:
     טווח שלא כתוב הוא טווח שאפשר לטעות בו. */
  const canChangeRange = has(PERM.DASHBOARD_CHANGE_RANGE)
  /**
   * מעבר בין חודשים — לכל מי שהדשבורד נפתח לו, גם בלי `dashboard.change_range`.
   *
   * שתי שאלות שונות, ולכן שני פקדים: "איזה חודש" ו"איזה טווח". ‏0144 סגרה את
   * השנייה בפני הלקוח — בורר טווח חופשי הוא כלי של מי שמסדר את המסך — אבל
   * בדרך היא סגרה גם את הראשונה, והלקוח נשאר נעול על החודש הנוכחי בלי שום דרך
   * לשאול "וכמה היה לי בחודש שעבר". החיצים נותנים בדיוק את זה ולא יותר: החלון
   * שהם מייצרים הוא תמיד חודש שלם, והנתונים שמאחוריו הם אותם נתונים שהטבלה
   * החודשית שלו כבר מציגה שנים־עשר חודשים אחורה (0143). אין כאן חשיפה חדשה,
   * רק דרך לשאול עליה.
   *
   * הכיוון הוא של RTL, כמו בכל בורר חודש אחר במערכת (דוח הנוכחות, הקבלה,
   * הפורטל): ימין הוא אחורה.
   */
  const monthShown = useMemo(() => new Date(range.from), [range.from])
  const onThisMonth = isWholeMonth(range) && range.from === defaultRange().from
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
  const view = layout.view
  const packing = packingOf(view)
  /* Only what the server reads. Everything else a placement can choose is
     redrawn from rows already in hand, and putting it in this bag would put it
     in the query key — so changing a chart to a table would refetch the page. */
  const serverOpts = useMemo(
    () => ({ ...(view?.bucket ? { bucket: view.bucket } : {}), ...(view?.limit ? { limit: view.limit } : {}) }),
    [view?.bucket, view?.limit],
  )
  const sections = useDashboardSections(layout.visible, layout.byId, range, prev, serverOpts)

  /* A saved view opens on the range it was saved with. A preset re-evaluates —
     "this month" saved in March is March's answer in April — while a fixed pair
     is exactly the pair. Applied once per view, and never over a range the
     reader has since typed for themselves. */
  /* Keyed on the *value*, not on the object. `view` is rebuilt from jsonb on
     every layout refetch — and every option click writes the layout — so an
     effect that depended on the object's identity re-ran after each save and
     threw away whatever range the reader had typed since. */
  const rangeKey = view?.range ? JSON.stringify(view.range) : ''
  useEffect(() => {
    if (!rangeKey || !canChangeRange) return
    const r = JSON.parse(rangeKey) as NonNullable<ViewPrefs['range']>
    if ('preset' in r) {
      const p = RANGE_PRESETS.find((x) => x.label === r.preset)
      if (p) setRange(p.range())
    } else {
      setRange({ from: r.from, to: r.to })
    }
  }, [rangeKey, canChangeRange])

  /* Auto-refresh is off unless the view asks for it. A screen on a wall wants
     it; a screen somebody is reading does not, and a dashboard that reloads
     under a cursor is a dashboard that loses your place. */
  const refreshEvery = view?.refresh ?? 0
  /* Through a ref, not as a dependency. `sections` is rebuilt whenever its data
     changes and `refetch` is a fresh closure each time, so depending on it
     would clear and restart the interval on every landing — and a five-minute
     timer that restarts every time anything on the page updates is a timer that
     can be starved indefinitely. */
  const refetchRef = useRef(sections.refetch)
  refetchRef.current = sections.refetch
  useEffect(() => {
    if (refreshEvery <= 0) return
    const t = setInterval(() => refetchRef.current(), refreshEvery * 60_000)
    return () => clearInterval(t)
  }, [refreshEvery])

  const ctx = useMemo(
    () => ({
      range,
      prev,
      today,
      sections,
      /* שני אלה פותחים את כרטיס המשימה, והוא של מנהל המערכת (0108). */
      openTask: canOpenTaskCard ? (id: string) => setTaskDrawer({ open: true, id }) : undefined,
      openNewTask: canOpenTaskCard ? () => setTaskDrawer({ open: true, id: null }) : undefined,
      openNewEvent: () => setEventModal(true),
    }),
    [range, prev, today, sections, canOpenTaskCard],
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
  const onHeight = (id: string, h: 'auto' | 'tall') =>
    layout.edit((s) => ({ ...s, items: setHeight(s.items, id, h) }))
  const onRemove = (id: string) => layout.edit((s) => hideWidget(s, id))
  /**
   * A display choice, saved where it was made.
   *
   * Outside edit mode there is no save bar to press, and a chart that goes back
   * to being a chart on the next load is a control nobody would use twice — so
   * the write follows the click. Inside edit mode it joins the draft like every
   * other edit and waits for the bar, because that is the contract that screen
   * already has.
   */
  const onOpt = canCustomize
    ? (id: string, key: string, value: string | number | boolean | undefined) => {
        const apply = (s: LayoutState) => ({ ...s, items: setOpt(s.items, id, key, value) })
        if (editing) layout.edit(apply)
        else void guard(() => layout.commit(apply))
      }
    : undefined
  /* Only offered to whoever may publish a default — locking a widget on your
     own layout would be locking yourself out of your own screen. */
  const onLock = has(PERM.DASHBOARD_MANAGE_DEFAULT)
    ? (id: string, on: boolean) => layout.edit((s) => ({ ...s, items: setLock(s.items, id, on) }))
    : undefined
  const onView = (patch: Partial<ViewPrefs>) => {
    if (!canCustomize) return
    const apply = (s: LayoutState) => ({ ...s, view: mergeView(s.view, patch) })
    if (editing) layout.edit(apply)
    else void guard(() => layout.commit(apply))
  }
  const onToggle = (id: string, on: boolean) =>
    layout.edit((s) => {
      const meta = layout.byId.get(id)
      if (!meta) return s
      return on ? showWidget(s, meta, layout.byId) : hideWidget(s, id)
    })

  /* Exports the widgets that are on screen, in the order they were arranged —
     the file is the view, not "all the data". Every number comes from the
     section as the server returned it; nothing is recomputed on the way out,
     and a card's own top-N is deliberately not applied. `exportDashboard.ts`
     carries that argument. */
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
              {/* לפני הפריסטים ולפני שדות התאריך, כי הוא הפקד היחיד שיש למי
                  שאין לו `dashboard.change_range` — ומסך שהתנועה שלו קבורה
                  בסוף שורה הוא מסך שאיש לא ימצא בו את התנועה. */}
              <MonthStepper
                month={monthShown}
                onStep={(d) => setRange((r) => stepMonth(r, d))}
                onToday={() => setRange(monthRange(new Date()))}
                atToday={onThisMonth}
              />
              {canChangeRange && (
                <>
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
                </>
              )}
              <div className="flex items-center gap-1.5">
                {/* The refresh is not behind `dashboard.customize`: asking for
                    today's numbers again is not arranging anything. */}
                <IconButton
                  size="sm"
                  variant="ghost"
                  label="רענון"
                  onClick={() => sections.refetch()}
                  disabled={sections.isFetching}
                >
                  <RefreshCw
                    size={ICON.md}
                    strokeWidth={STROKE}
                    className={sections.isFetching ? 'animate-spin' : undefined}
                    aria-hidden
                  />
                </IconButton>
                {has(PERM.DASHBOARD_EXPORT) && (
                  <Button size="sm" variant="ghost" onClick={() => void guard(exportXlsx)}>
                    <Download size={ICON.sm} strokeWidth={STROKE} />
                    ייצוא
                  </Button>
                )}
                {canCustomize && (
                  <>
                    <ViewSettingsMenu
                      view={view}
                      onChange={onView}
                      onRefresh={() => sections.refetch()}
                      refreshing={sections.isFetching}
                      updatedAt={sections.updatedAt}
                    />
                    <SavedViewsMenu
                      views={layout.namedViews}
                      hasOwnLayout={layout.hasOwnLayout}
                      orgDefaults={layout.orgDefaults}
                      currentRange={range}
                      onApply={(row) => void guard(async () => layout.applyView(row, !editing))}
                      onSaveAs={(name) => guard(() => layout.save(name))}
                      onOverwrite={(id) => guard(() => layout.updateView(id))}
                      onRename={(id, name) => guard(() => layout.renameView(id, name))}
                      onDelete={(id) => guard(() => layout.deleteView(id))}
                      onReset={() => guard(layout.reset)}
                      onPublishDefault={(k) => guard(() => layout.saveOrgDefault(k))}
                      onRemoveDefault={(k) => guard(() => layout.deleteOrgDefault(k))}
                      onPinRange={(r) => onView({ range: r })}
                      pinnedRange={view?.range}
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
          {sections.error != null && !editing ? (
            <ErrorState error={sections.error} onRetry={sections.refetch} />
          ) : editing ? (
            <Suspense fallback={<Skeleton className="h-64 w-full" />}>
              <DashboardEditGrid
                items={layout.visible}
                byId={layout.byId}
                packing={packing}
                onMove={onMove}
                onReorder={onReorder}
                onSize={onSize}
                onHeight={onHeight}
                onRemove={onRemove}
                onOpt={onOpt}
                onLock={onLock}
              />
            </Suspense>
          ) : (
            <DashboardGrid items={layout.visible} byId={layout.byId} packing={packing} onOpt={onOpt} />
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
