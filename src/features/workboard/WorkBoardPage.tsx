import { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'react-router'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useVirtualizer } from '@tanstack/react-virtual'
import { addDays, endOfMonth, startOfMonth, startOfWeek } from 'date-fns'
import {
  AlertTriangle,
  ChevronDown,
  Columns3,
  Filter,
  ICON,
  MapPin,
  Pencil,
  Plus,
  STROKE,
  SlidersHorizontal,
} from '../../components/ui/icons'
import {
  AvatarGroup,
  BulkBar,
  Button,
  Checkbox,
  EmptyState,
  Field,
  IconButton,
  Input,
  MenuLabel,
  Modal,
  PageHeader,
  Popover,
  SegmentedControl,
  Select,
  SkeletonTable,
  StatusPill,
  Tooltip,
  cx,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { useContractors, useCustomers, useExecutionMethods, useStatuses, useTaskTypes, useTrucks } from '../../lib/queries'
import { fmtDate, fmtTime, toISODate } from '../../lib/dates'
import { useIsMobile } from '../../lib/useMediaQuery'
import { TaskDrawer } from '../tasks/TaskDrawer'
import { RequirePermission } from '../auth/guards'
import { BOARD_FIELDS, DEFAULT_HIDDEN_FIELDS } from './boardFields'
import type { BoardLookups } from './boardFields'
import type { WorkBoardRow } from '../../types/domain'

/* ── geometry ─────────────────────────────────────────────────────────────
   The board is transposed: days run across, task fields run down. The field
   legend on the inline-start edge is sticky and never scrolls away.       */

const LEGEND_W = 150
const SPINE_W = 46
const DAY_HEAD_H = 30
const TASK_HEAD_H = 46
const HEADER_H = DAY_HEAD_H + TASK_HEAD_H

const DENSITY = {
  compact: { col: 168, row: 30, tall: 36 },
  comfortable: { col: 208, row: 38, tall: 46 },
} as const
type Density = keyof typeof DENSITY

const SORTS = [
  { key: 'time', label: 'שעה' },
  { key: 'customer', label: 'לקוח' },
  { key: 'status', label: 'סטטוס' },
  { key: 'type', label: 'סוג' },
] as const
type SortKey = (typeof SORTS)[number]['key']

const PREFS_KEY = 'vl-board-prefs'

interface Prefs {
  hidden?: string[]
  density?: Density
  sort?: SortKey
}

function loadPrefs(): Prefs {
  try {
    return JSON.parse(localStorage.getItem(PREFS_KEY) ?? '{}') as Prefs
  } catch {
    return {}
  }
}

type BoardColumn =
  | { kind: 'task'; id: string; row: WorkBoardRow; dayKey: string }
  | { kind: 'spine'; id: string; dayKey: string; count: number }

/** inline cell writes a single column with optimistic-concurrency on updated_at */
function useInlineUpdate() {
  const qc = useQueryClient()
  const toast = useToast()
  return useMutation({
    mutationFn: async ({ row, patch }: { row: WorkBoardRow; patch: Record<string, unknown> }) => {
      const { data, error } = await supabase
        .from('tasks')
        .update(patch)
        .eq('id', row.id)
        .eq('updated_at', row.updated_at)
        .select('id')
      if (error) throw error
      if (!data || data.length === 0) throw new Error('המשימה עודכנה על ידי משתמש אחר — הנתונים רועננו')
    },
    onSettled: () => void qc.invalidateQueries({ queryKey: ['workboard'] }),
    onError: (e) => toast.error((e as Error).message),
  })
}

export default function WorkBoardPage() {
  const { can } = useAuth()
  const canEdit = can('tasks', 'edit')
  const [params] = useSearchParams()
  const prefs = useRef(loadPrefs())
  const isMobile = useIsMobile()
  const [filterSheet, setFilterSheet] = useState(false)

  const weekStart = startOfWeek(new Date(), { weekStartsOn: 0 })
  const [from, setFrom] = useState(params.get('date') || toISODate(weekStart))
  const [to, setTo] = useState(params.get('date') || toISODate(addDays(weekStart, 6)))
  const [filters, setFilters] = useState({ customer: '', status: '', type: '', contractor: '', q: '' })
  const [drawer, setDrawer] = useState<{ open: boolean; taskId: string | null }>({
    open: !!params.get('task'),
    taskId: params.get('task'),
  })
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [bulkOpen, setBulkOpen] = useState(false)
  const [collapsedDays, setCollapsedDays] = useState<Set<string>>(new Set())
  const [hidden, setHidden] = useState<Set<string>>(new Set(prefs.current.hidden ?? DEFAULT_HIDDEN_FIELDS))
  const [density, setDensity] = useState<Density>(prefs.current.density ?? 'comfortable')
  const [sortBy, setSortBy] = useState<SortKey>(prefs.current.sort ?? 'time')

  useEffect(() => {
    try {
      localStorage.setItem(PREFS_KEY, JSON.stringify({ hidden: [...hidden], density, sort: sortBy }))
    } catch {
      /* view preferences are not worth failing over */
    }
  }, [hidden, density, sortBy])

  const { data: customers = [] } = useCustomers()
  const { data: statuses = [] } = useStatuses('task')
  const { data: taskTypes = [] } = useTaskTypes()
  const { data: contractors = [] } = useContractors()
  const { data: methods = [] } = useExecutionMethods()
  const { data: trucks = [] } = useTrucks()
  const inline = useInlineUpdate()

  const { data: rows = [], isLoading } = useQuery({
    queryKey: ['workboard', 'range', from, to, filters],
    queryFn: async () => {
      let q = supabase
        .from('work_board_view')
        .select('*')
        .gte('task_date', from)
        .lte('task_date', to)
        .order('task_date')
        .order('onsite_start_time', { nullsFirst: false })
        .limit(2000)
      if (filters.customer) q = q.eq('customer_id', filters.customer)
      if (filters.status) q = q.eq('status_id', filters.status)
      if (filters.type) q = q.eq('task_type_id', filters.type)
      if (filters.contractor) q = q.eq('contractor_id', filters.contractor)
      if (filters.q.trim())
        q = q.or(
          `title.ilike.%${filters.q}%,end_client_name.ilike.%${filters.q}%,event_number.ilike.%${filters.q}%,location_text.ilike.%${filters.q}%,customer_name.ilike.%${filters.q}%`,
        )
      const { data, error } = await q
      if (error) throw error
      return data as WorkBoardRow[]
    },
  })

  const lookups = useMemo<BoardLookups>(() => ({ statuses, trucks, methods }), [statuses, trucks, methods])
  const patchCell = useCallback(
    (row: WorkBoardRow, patch: Record<string, unknown>) => inline.mutate({ row, patch }),
    [inline],
  )

  const fields = useMemo(() => BOARD_FIELDS.filter((f) => !hidden.has(f.key)), [hidden])
  const metrics = DENSITY[density]

  /** one height array drives both the legend and every task column, so the
   *  grid can never drift out of alignment */
  const rowHeights = useMemo(() => fields.map((f) => (f.tall ? metrics.tall : metrics.row)), [fields, metrics])
  const bodyHeight = rowHeights.reduce((a, b) => a + b, 0)

  const today = toISODate(new Date())

  /* ── group by day, then lay the columns out left-to-right in reading order */

  const { columns, bands, totalWidth, rowsByDay } = useMemo(() => {
    const byDay = new Map<string, WorkBoardRow[]>()
    for (const r of rows) {
      const list = byDay.get(r.task_date)
      if (list) list.push(r)
      else byDay.set(r.task_date, [r])
    }

    const cmp = (a: WorkBoardRow, b: WorkBoardRow) => {
      if (sortBy === 'customer') return (a.customer_name ?? '').localeCompare(b.customer_name ?? '', 'he')
      if (sortBy === 'status') return a.status_name.localeCompare(b.status_name, 'he')
      if (sortBy === 'type') return a.task_type_name.localeCompare(b.task_type_name, 'he')
      const at = a.onsite_start_time ?? a.warehouse_start_time ?? '99:99'
      const bt = b.onsite_start_time ?? b.warehouse_start_time ?? '99:99'
      return at.localeCompare(bt)
    }

    const cols: BoardColumn[] = []
    const bandList: {
      dayKey: string
      start: number
      width: number
      count: number
      overdue: number
      collapsed: boolean
    }[] = []
    /** the same day-grouping the columns are built from, kept in sorted order
     *  so the mobile list and the desktop grid can never disagree */
    const sortedByDay = new Map<string, WorkBoardRow[]>()
    let offset = 0

    for (const dayKey of [...byDay.keys()].sort()) {
      const dayRows = [...byDay.get(dayKey)!].sort(cmp)
      sortedByDay.set(dayKey, dayRows)
      const overdue = dayKey < today ? dayRows.filter((r) => !r.status_is_terminal).length : 0
      const collapsed = collapsedDays.has(dayKey)
      const start = offset

      if (collapsed) {
        cols.push({ kind: 'spine', id: `spine:${dayKey}`, dayKey, count: dayRows.length })
        offset += SPINE_W
      } else {
        for (const row of dayRows) {
          cols.push({ kind: 'task', id: row.id, row, dayKey })
          offset += metrics.col
        }
      }
      bandList.push({ dayKey, start, width: offset - start, count: dayRows.length, overdue, collapsed })
    }

    return { columns: cols, bands: bandList, totalWidth: offset, rowsByDay: sortedByDay }
  }, [rows, sortBy, collapsedDays, metrics.col, today])

  /* ── horizontal virtualization (RTL-aware) ───────────────────────────── */

  const scrollRef = useRef<HTMLDivElement>(null)
  const virtualizer = useVirtualizer({
    horizontal: true,
    isRtl: true,
    count: columns.length,
    getScrollElement: () => scrollRef.current,
    estimateSize: (i) => (columns[i]?.kind === 'spine' ? SPINE_W : metrics.col),
    overscan: 6,
  })
  const virtualItems = virtualizer.getVirtualItems()

  /* ── selection ────────────────────────────────────────────────────────── */

  const taskIds = useMemo(() => rows.map((r) => r.id), [rows])
  const allSelected = taskIds.length > 0 && selected.size === taskIds.length
  const toggleAll = () => setSelected(allSelected ? new Set() : new Set(taskIds))
  const toggleOne = useCallback(
    (id: string) =>
      setSelected((s) => {
        const n = new Set(s)
        if (n.has(id)) n.delete(id)
        else n.add(id)
        return n
      }),
    [],
  )
  const openTask = useCallback((id: string) => setDrawer({ open: true, taskId: id }), [])

  const toggleDay = (dayKey: string) =>
    setCollapsedDays((s) => {
      const n = new Set(s)
      if (n.has(dayKey)) n.delete(dayKey)
      else n.add(dayKey)
      return n
    })

  const setRange = (a: Date, b: Date) => {
    setFrom(toISODate(a))
    setTo(toISODate(b))
  }
  const now = new Date()
  const presets = [
    { label: 'היום', run: () => setRange(now, now) },
    { label: 'השבוע', run: () => setRange(startOfWeek(now, { weekStartsOn: 0 }), addDays(startOfWeek(now, { weekStartsOn: 0 }), 6)) },
    {
      label: 'שבוע הבא',
      run: () =>
        setRange(addDays(startOfWeek(now, { weekStartsOn: 0 }), 7), addDays(startOfWeek(now, { weekStartsOn: 0 }), 13)),
    },
    { label: 'החודש', run: () => setRange(startOfMonth(now), endOfMonth(now)) },
  ]

  const overdueTotal = useMemo(
    () => rows.filter((r) => r.task_date < today && !r.status_is_terminal).length,
    [rows, today],
  )

  const activeFilterCount = Object.values(filters).filter(Boolean).length
  const resetFilters = () => setFilters({ customer: '', status: '', type: '', contractor: '', q: '' })

  /* ── filter controls ──────────────────────────────────────────────────────
     One definition, two homes: a single toolbar row on desktop, and a dialog
     on mobile. Left inline, the six controls stacked to about 400px — most of
     a phone screen — before the board even started.                        */

  const dateFields = (
    <div className="flex items-center gap-1.5">
      <Input
        type="date"
        inputSize="sm"
        className="w-full min-w-0 lg:w-36"
        value={from}
        onChange={(e) => setFrom(e.target.value)}
        aria-label="מתאריך"
      />
      <span className="shrink-0 type-caption text-ink-tertiary">עד</span>
      <Input
        type="date"
        inputSize="sm"
        className="w-full min-w-0 lg:w-36"
        value={to}
        onChange={(e) => setTo(e.target.value)}
        aria-label="עד תאריך"
      />
    </div>
  )

  const presetRow = (
    <div className="scroll-row gap-1">
      {presets.map((p) => (
        <button
          key={p.label}
          onClick={p.run}
          className="scroll-row-item rounded-md px-2 py-1 type-caption font-medium text-ink-tertiary transition-colors hover:bg-hover hover:text-ink"
        >
          {p.label}
        </button>
      ))}
    </div>
  )

  const lookupFilters = (
    <>
      <Select
        className="w-full lg:w-36"
        selectSize="sm"
        value={filters.customer}
        onChange={(e) => setFilters((f) => ({ ...f, customer: e.target.value }))}
        aria-label="לקוח"
      >
        <option value="">כל הלקוחות</option>
        {customers.map((c) => (
          <option key={c.id} value={c.id}>{c.name}</option>
        ))}
      </Select>
      <Select
        className="w-full lg:w-32"
        selectSize="sm"
        value={filters.type}
        onChange={(e) => setFilters((f) => ({ ...f, type: e.target.value }))}
        aria-label="סוג משימה"
      >
        <option value="">כל הסוגים</option>
        {taskTypes.map((t) => (
          <option key={t.id} value={t.id}>{t.name}</option>
        ))}
      </Select>
      <Select
        className="w-full lg:w-32"
        selectSize="sm"
        value={filters.status}
        onChange={(e) => setFilters((f) => ({ ...f, status: e.target.value }))}
        aria-label="סטטוס"
      >
        <option value="">כל הסטטוסים</option>
        {statuses.map((s) => (
          <option key={s.id} value={s.id}>{s.name}</option>
        ))}
      </Select>
      <Select
        className="w-full lg:w-32"
        selectSize="sm"
        value={filters.contractor}
        onChange={(e) => setFilters((f) => ({ ...f, contractor: e.target.value }))}
        aria-label="קבלן"
      >
        <option value="">כל הקבלנים</option>
        {contractors.map((c) => (
          <option key={c.id} value={c.id}>{c.name}</option>
        ))}
      </Select>
    </>
  )

  return (
    <RequirePermission resource="tasks">
      <div className="flex h-full min-h-0 flex-col gap-3">
        <PageHeader
          title="לוח עבודה"
          subtitle={
            <span className="flex flex-wrap items-center gap-x-3 gap-y-1">
              <span className="tabular">{rows.length} משימות</span>
              <span className="tabular">{bands.length} ימים</span>
              {overdueTotal > 0 && (
                <span className="inline-flex items-center gap-1 font-medium text-error-text">
                  <AlertTriangle size={ICON.xs} />
                  {overdueTotal} באיחור
                </span>
              )}
            </span>
          }
          actions={
            <>
              {selected.size > 0 && canEdit && (
                <Button size="sm" onClick={() => setBulkOpen(true)}>
                  <Pencil size={ICON.sm} strokeWidth={STROKE} />
                  עריכה מרובה ({selected.size})
                </Button>
              )}
              {can('tasks', 'create') && (
                <Button size="sm" variant="primary" onClick={() => setDrawer({ open: true, taskId: null })}>
                  <Plus size={ICON.sm} strokeWidth={STROKE} />
                  משימה חדשה
                </Button>
              )}
            </>
          }
        >
          {/* ── mobile toolbar: two rows, everything else behind "סינון" ──── */}
          <div className="surface space-y-2 p-2 lg:hidden">
            {presetRow}
            <div className="flex items-center gap-1.5">
              <Input
                className="min-w-0 flex-1"
                inputSize="sm"
                placeholder="חיפוש..."
                value={filters.q}
                onChange={(e) => setFilters((f) => ({ ...f, q: e.target.value }))}
                aria-label="חיפוש חופשי"
              />
              <Button
                size="sm"
                variant={activeFilterCount > 0 ? 'outlined' : 'secondary'}
                className="shrink-0"
                onClick={() => setFilterSheet(true)}
              >
                <Filter size={ICON.sm} strokeWidth={STROKE} />
                סינון
                {activeFilterCount > 0 && (
                  <span className="inline-flex size-4 items-center justify-center rounded-full bg-primary type-caption font-bold tabular text-on-primary">
                    {activeFilterCount}
                  </span>
                )}
              </Button>
            </div>
            <p className="type-caption tabular text-ink-tertiary">
              {fmtDate(from)} – {fmtDate(to)}
            </p>
          </div>

          {/* ── desktop toolbar: everything inline ───────────────────────── */}
          <div className="surface hidden flex-wrap items-center gap-2 p-2.5 lg:flex">
            {dateFields}
            {presetRow}

            <Input
              className="w-44"
              inputSize="sm"
              placeholder="חיפוש..."
              value={filters.q}
              onChange={(e) => setFilters((f) => ({ ...f, q: e.target.value }))}
              aria-label="חיפוש חופשי"
            />
            {lookupFilters}

            <div className="ms-auto flex items-center gap-1.5">
              <Popover
                trigger={({ toggle, ...aria }) => (
                  <Button size="sm" variant="ghost" onClick={toggle} {...aria}>
                    <SlidersHorizontal size={ICON.sm} strokeWidth={STROKE} />
                    תצוגה
                  </Button>
                )}
              >
                {() => (
                  <div className="w-56 p-1.5">
                    <MenuLabel>צפיפות</MenuLabel>
                    <SegmentedControl
                      block
                      items={[
                        { key: 'comfortable', label: 'מרווח' },
                        { key: 'compact', label: 'צפוף' },
                      ]}
                      value={density}
                      onChange={setDensity}
                    />
                    <MenuLabel>מיון בתוך היום</MenuLabel>
                    <SegmentedControl
                      block
                      items={SORTS.map((s) => ({ key: s.key, label: s.label }))}
                      value={sortBy}
                      onChange={setSortBy}
                    />
                    <div className="mt-2 flex gap-1.5 px-0.5">
                      <Button size="sm" variant="ghost" block onClick={() => setCollapsedDays(new Set(bands.map((b) => b.dayKey)))}>
                        קפל הכל
                      </Button>
                      <Button size="sm" variant="ghost" block onClick={() => setCollapsedDays(new Set())}>
                        פרוס הכל
                      </Button>
                    </div>
                  </div>
                )}
              </Popover>

              <Popover
                trigger={({ toggle, ...aria }) => (
                  <Button size="sm" variant="ghost" onClick={toggle} {...aria}>
                    <Columns3 size={ICON.sm} strokeWidth={STROKE} />
                    שדות
                    <span className="tabular text-ink-tertiary">
                      {fields.length}/{BOARD_FIELDS.length}
                    </span>
                  </Button>
                )}
              >
                {() => (
                  <div className="max-h-80 w-56 overflow-y-auto">
                    <MenuLabel>שורות מוצגות</MenuLabel>
                    {BOARD_FIELDS.map((f) => (
                      <div key={f.key} className="px-2.5 py-1.5">
                        <Checkbox
                          label={f.label}
                          checked={!hidden.has(f.key)}
                          onChange={(on) =>
                            setHidden((h) => {
                              const n = new Set(h)
                              if (on) n.delete(f.key)
                              else n.add(f.key)
                              return n
                            })
                          }
                        />
                      </div>
                    ))}
                  </div>
                )}
              </Popover>
            </div>
          </div>
        </PageHeader>

        {/* ── the board ──────────────────────────────────────────────────── */}
        <div className="surface min-h-0 flex-1 overflow-hidden">
          {isLoading ? (
            <SkeletonTable rows={8} cols={6} />
          ) : rows.length === 0 ? (
            <EmptyState
              art="calendar"
              title="אין משימות בטווח שנבחר"
              description="שנה את טווח התאריכים או נקה את הסינון כדי לראות משימות"
              action={
                can('tasks', 'create') && (
                  <Button variant="primary" size="sm" onClick={() => setDrawer({ open: true, taskId: null })}>
                    <Plus size={ICON.sm} />
                    משימה חדשה
                  </Button>
                )
              }
            />
          ) : isMobile ? (
            /* A transposed 19-row grid needs a mouse and a wide viewport. On a
               phone the same data reads better as a day-by-day card list; the
               drawer still owns every edit. */
            <MobileBoard
              bands={bands}
              rowsByDay={rowsByDay}
              today={today}
              selected={selected}
              onToggle={toggleOne}
              onOpen={openTask}
              onToggleDay={toggleDay}
            />
          ) : (
            <div ref={scrollRef} className="h-full overflow-auto">
              <div className="relative flex" style={{ width: LEGEND_W + totalWidth, minHeight: '100%' }}>
                {/* sticky field legend */}
                <div
                  className="sticky z-30 shrink-0 border-e border-line bg-surface"
                  style={{ insetInlineStart: 0, width: LEGEND_W }}
                >
                  <div
                    className="sticky top-0 z-10 flex items-end border-b border-line bg-subtle px-2.5 pb-2"
                    style={{ height: HEADER_H }}
                  >
                    <Checkbox
                      label={<span className="type-caption font-semibold">בחר הכל</span>}
                      checked={allSelected}
                      indeterminate={selected.size > 0}
                      onChange={toggleAll}
                    />
                  </div>
                  {fields.map((f, i) => (
                    <div
                      key={f.key}
                      className="flex items-center border-b border-line-subtle px-2.5 type-caption font-semibold text-ink-secondary"
                      style={{ height: rowHeights[i] }}
                    >
                      <span className="truncate">{f.label}</span>
                    </div>
                  ))}
                </div>

                {/* virtualized track */}
                <div className="relative" style={{ width: totalWidth }}>
                  {/* header band: day groups + per-task headers */}
                  <div className="sticky top-0 z-20 bg-subtle" style={{ height: HEADER_H }}>
                    {bands.map((b) => {
                      const isToday = b.dayKey === today
                      return (
                        <div
                          key={b.dayKey}
                          className={cx(
                            'absolute top-0 flex items-center gap-1.5 overflow-hidden border-b border-s border-line px-2',
                            isToday ? 'bg-primary-subtle' : b.overdue > 0 ? 'bg-error-subtle' : 'bg-subtle',
                          )}
                          style={{ insetInlineStart: b.start, width: b.width, height: DAY_HEAD_H }}
                        >
                          <button
                            onClick={() => toggleDay(b.dayKey)}
                            aria-expanded={!b.collapsed}
                            aria-label={`${b.collapsed ? 'פריסת' : 'קיפול'} ${fmtDate(b.dayKey)}`}
                            className="flex min-w-0 items-center gap-1 rounded transition-colors hover:text-ink focus-visible:outline-none focus-visible:focus-ring"
                          >
                            <ChevronDown
                              size={ICON.xs}
                              className={cx('shrink-0 transition-transform duration-200', b.collapsed && 'rotate-90 rtl:-rotate-90')}
                            />
                            <span
                              className={cx(
                                'truncate type-caption font-bold tabular',
                                isToday ? 'text-primary-text' : b.overdue > 0 ? 'text-error-text' : 'text-ink-secondary',
                              )}
                            >
                              {fmtDate(b.dayKey)}
                            </span>
                          </button>
                          {isToday && (
                            <span className="shrink-0 rounded-full bg-primary px-1.5 py-px text-[10px] font-bold text-on-primary">
                              היום
                            </span>
                          )}
                          {b.overdue > 0 && !isToday && (
                            <Tooltip content={`${b.overdue} משימות פתוחות שעברו את מועדן`}>
                              <span className="inline-flex shrink-0 items-center gap-0.5 rounded-full bg-error px-1.5 py-px text-[10px] font-bold tabular text-white">
                                <AlertTriangle size={9} />
                                {b.overdue}
                              </span>
                            </Tooltip>
                          )}
                          <span className="ms-auto shrink-0 type-caption tabular text-ink-tertiary">{b.count}</span>
                        </div>
                      )
                    })}

                    {virtualItems.map((vi) => {
                      const col = columns[vi.index]
                      if (!col) return null
                      return (
                        <div
                          key={col.id}
                          className="absolute"
                          style={{ insetInlineStart: vi.start, width: vi.size, top: DAY_HEAD_H, height: TASK_HEAD_H }}
                        >
                          {col.kind === 'spine' ? (
                            <SpineHeader dayKey={col.dayKey} count={col.count} onExpand={() => toggleDay(col.dayKey)} />
                          ) : (
                            <TaskHeader
                              row={col.row}
                              today={today}
                              selected={selected.has(col.row.id)}
                              onToggle={toggleOne}
                              onOpen={openTask}
                            />
                          )}
                        </div>
                      )
                    })}
                  </div>

                  {/* body cells */}
                  <div className="relative" style={{ height: bodyHeight }}>
                    {virtualItems.map((vi) => {
                      const col = columns[vi.index]
                      if (!col) return null
                      if (col.kind === 'spine')
                        return (
                          <div
                            key={col.id}
                            className="absolute top-0 border-s border-line bg-subtle/60"
                            style={{ insetInlineStart: vi.start, width: vi.size, height: bodyHeight }}
                          />
                        )
                      return (
                        <TaskColumn
                          key={col.id}
                          row={col.row}
                          canEdit={canEdit}
                          patch={patchCell}
                          lookups={lookups}
                          fields={fields}
                          heights={rowHeights}
                          selected={selected.has(col.row.id)}
                          style={{ insetInlineStart: vi.start, width: vi.size }}
                        />
                      )
                    })}
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>

        {selected.size > 0 && (
          <BulkBar count={selected.size} onClear={() => setSelected(new Set())}>
            {canEdit && (
              <Button size="sm" variant="primary" onClick={() => setBulkOpen(true)}>
                <Pencil size={ICON.sm} />
                עריכה מרובה
              </Button>
            )}
          </BulkBar>
        )}

        <Modal
          open={filterSheet}
          onClose={() => setFilterSheet(false)}
          title="סינון לוח העבודה"
          description={`${rows.length} משימות בטווח הנוכחי`}
          footer={
            <>
              <Button onClick={resetFilters} disabled={activeFilterCount === 0}>
                ניקוי
              </Button>
              <Button variant="primary" onClick={() => setFilterSheet(false)}>
                הצגה
              </Button>
            </>
          }
        >
          <div className="space-y-4">
            <Field label="טווח תאריכים">{dateFields}</Field>
            <div className="grid gap-3">{lookupFilters}</div>
            <Field label="מיון בתוך היום">
              <SegmentedControl
                block
                items={SORTS.map((s) => ({ key: s.key, label: s.label }))}
                value={sortBy}
                onChange={setSortBy}
              />
            </Field>
          </div>
        </Modal>

        <TaskDrawer open={drawer.open} onClose={() => setDrawer({ open: false, taskId: null })} taskId={drawer.taskId} />
        <BulkEditModal
          open={bulkOpen}
          onClose={() => setBulkOpen(false)}
          taskIds={[...selected]}
          onDone={() => {
            setSelected(new Set())
            setBulkOpen(false)
          }}
        />
      </div>
    </RequirePermission>
  )
}

/* ===== mobile board =======================================================
   Days stack vertically, tasks inside them are cards. Every affordance the
   desktop grid offers through hover — open, select, fold a day — has a real
   target here, and nothing scrolls sideways.                               */

interface Band {
  dayKey: string
  start: number
  width: number
  count: number
  overdue: number
  collapsed: boolean
}

function MobileBoard({
  bands,
  rowsByDay,
  today,
  selected,
  onToggle,
  onOpen,
  onToggleDay,
}: {
  bands: Band[]
  rowsByDay: Map<string, WorkBoardRow[]>
  today: string
  selected: Set<string>
  onToggle: (id: string) => void
  onOpen: (id: string) => void
  onToggleDay: (dayKey: string) => void
}) {
  return (
    <div className="h-full overflow-y-auto">
      {bands.map((band) => {
        const isToday = band.dayKey === today
        const dayRows = rowsByDay.get(band.dayKey) ?? []
        return (
          <section key={band.dayKey}>
            <h3
              className={cx(
                'sticky top-0 z-10 flex items-center gap-2 border-b border-line px-3 py-2 backdrop-blur-sm',
                isToday ? 'bg-primary-subtle' : band.overdue > 0 ? 'bg-error-subtle' : 'bg-subtle',
              )}
            >
              <button
                onClick={() => onToggleDay(band.dayKey)}
                aria-expanded={!band.collapsed}
                className="flex min-w-0 flex-1 items-center gap-1.5 text-start focus-visible:outline-none focus-visible:focus-ring"
              >
                <ChevronDown
                  size={ICON.sm}
                  className={cx('shrink-0 transition-transform duration-200', band.collapsed && 'rotate-90 rtl:-rotate-90')}
                />
                <span
                  className={cx(
                    'truncate type-button tabular',
                    isToday ? 'text-primary-text' : band.overdue > 0 ? 'text-error-text' : 'text-ink-secondary',
                  )}
                >
                  {fmtDate(band.dayKey)}
                </span>
                {isToday && (
                  <span className="shrink-0 rounded-full bg-primary px-1.5 py-px text-[10px] font-bold text-on-primary">
                    היום
                  </span>
                )}
                {band.overdue > 0 && !isToday && (
                  <span className="inline-flex shrink-0 items-center gap-0.5 rounded-full bg-error px-1.5 py-px text-[10px] font-bold tabular text-white">
                    <AlertTriangle size={9} />
                    {band.overdue}
                  </span>
                )}
              </button>
              <span className="shrink-0 type-caption tabular text-ink-tertiary">{band.count}</span>
            </h3>

            {!band.collapsed && (
              <ul className="divide-y divide-line-subtle">
                {dayRows.map((row) => (
                  <li key={row.id}>
                    <MobileTaskCard
                      row={row}
                      overdue={row.task_date < today && !row.status_is_terminal}
                      selected={selected.has(row.id)}
                      onToggle={onToggle}
                      onOpen={onOpen}
                    />
                  </li>
                ))}
              </ul>
            )}
          </section>
        )
      })}
    </div>
  )
}

const MobileTaskCard = memo(function MobileTaskCard({
  row,
  overdue,
  selected,
  onToggle,
  onOpen,
}: {
  row: WorkBoardRow
  overdue: boolean
  selected: boolean
  onToggle: (id: string) => void
  onOpen: (id: string) => void
}) {
  const label = row.end_client_name || row.title || row.customer_name || row.task_type_name
  const time = fmtTime(row.onsite_start_time) || fmtTime(row.warehouse_start_time)
  const team = [
    ...(row.workers ?? []).map((w) => w.name),
    ...(row.drivers ?? []).map((d) => d.name),
    ...(row.contractor_worker_list ?? []).map((w) => w.name),
  ]
  const short = row.worker_count > 0 && team.length < row.worker_count

  return (
    <div className={cx('flex items-stretch gap-2 px-3 py-2.5', selected ? 'bg-selected' : overdue && 'bg-error-subtle/50')}>
      <span
        aria-hidden
        className="w-1 shrink-0 rounded-full"
        style={{ background: row.customer_color ?? 'var(--vl-border-strong)' }}
      />
      <span className="flex items-start pt-0.5">
        <Checkbox checked={selected} onChange={() => onToggle(row.id)} />
      </span>
      <button onClick={() => onOpen(row.id)} className="min-w-0 flex-1 space-y-1 text-start">
        <span className="flex items-center gap-2">
          {time ? (
            <span className={cx('shrink-0 type-button tabular', overdue ? 'text-error-text' : 'text-ink')} dir="ltr">
              {time}
            </span>
          ) : (
            <span className="shrink-0 type-caption text-ink-tertiary">ללא שעה</span>
          )}
          {overdue && <AlertTriangle size={12} className="shrink-0 text-error" aria-label="באיחור" />}
          <StatusPill color={row.status_color} className="ms-auto shrink-0">
            {row.status_name}
          </StatusPill>
        </span>

        <span className="block truncate type-body font-semibold">{label}</span>

        <span className="flex flex-wrap items-center gap-x-2 type-caption text-ink-tertiary">
          <span className="truncate">{row.task_type_name}</span>
          {row.customer_name && <span className="truncate">· {row.customer_name}</span>}
          {row.contractor_name && <span className="truncate">· {row.contractor_name}</span>}
        </span>

        {row.location_text && (
          <span className="flex items-center gap-1 type-caption text-ink-tertiary">
            <MapPin size={ICON.xs} className="shrink-0" />
            <span className="truncate">{row.location_text}</span>
          </span>
        )}

        <span className="flex items-center gap-2 pt-0.5">
          {team.length > 0 ? (
            <AvatarGroup names={team} max={4} size="xs" />
          ) : (
            <span className="type-caption text-ink-tertiary">לא שובץ</span>
          )}
          {row.worker_count > 0 && (
            <span
              className={cx(
                'rounded px-1 type-caption font-bold tabular',
                short ? 'bg-warning-subtle text-warning-text' : 'bg-success-subtle text-success-text',
              )}
            >
              {team.length}/{row.worker_count}
            </span>
          )}
        </span>
      </button>
    </div>
  )
})

/* ===== column header ====================================================== */

const TaskHeader = memo(function TaskHeader({
  row,
  today,
  selected,
  onToggle,
  onOpen,
}: {
  row: WorkBoardRow
  today: string
  selected: boolean
  onToggle: (id: string) => void
  onOpen: (id: string) => void
}) {
  const overdue = row.task_date < today && !row.status_is_terminal
  const label = row.end_client_name || row.title || row.customer_name || row.task_type_name
  const time = fmtTime(row.onsite_start_time) || fmtTime(row.warehouse_start_time)

  return (
    <div
      className={cx(
        'group relative flex h-full flex-col justify-center gap-0.5 border-b border-s border-line px-2',
        selected ? 'bg-selected' : overdue ? 'bg-error-subtle' : 'bg-surface',
      )}
    >
      <span
        aria-hidden
        className="absolute inset-x-0 top-0 h-0.5"
        style={{ background: row.customer_color ?? 'var(--vl-border-strong)' }}
      />
      <div className="flex items-center gap-1.5">
        <Checkbox checked={selected} onChange={() => onToggle(row.id)} />
        {time ? (
          <span className={cx('type-caption font-bold tabular', overdue ? 'text-error-text' : 'text-ink')} dir="ltr">
            {time}
          </span>
        ) : (
          <span className="type-caption text-ink-tertiary">ללא שעה</span>
        )}
        {overdue && (
          <Tooltip content="משימה פתוחה שעברה את מועדה">
            <AlertTriangle size={11} className="shrink-0 text-error" />
          </Tooltip>
        )}
        <IconButton
          label="פתיחת המשימה"
          size="sm"
          bare
          className="ms-auto size-6 opacity-0 transition-opacity group-hover:opacity-100 focus-visible:opacity-100"
          onClick={() => onOpen(row.id)}
        >
          <Pencil size={12} />
        </IconButton>
      </div>
      <Tooltip content={label}>
        <span className="truncate type-caption font-medium text-ink-secondary">{label}</span>
      </Tooltip>
    </div>
  )
})

function SpineHeader({ dayKey, count, onExpand }: { dayKey: string; count: number; onExpand: () => void }) {
  return (
    <button
      onClick={onExpand}
      aria-label={`פריסת ${fmtDate(dayKey)}`}
      className="flex h-full w-full flex-col items-center justify-center gap-1 border-b border-s border-line bg-subtle transition-colors hover:bg-hover"
    >
      <span className="rounded-full bg-ink-tertiary/15 px-1.5 py-px type-caption font-bold tabular text-ink-secondary">
        {count}
      </span>
    </button>
  )
}

/* ===== one task's column of field cells =================================== */

const TaskColumn = memo(
  function TaskColumn({
    row,
    canEdit,
    patch,
    lookups,
    fields,
    heights,
    selected,
    style,
  }: {
    row: WorkBoardRow
    canEdit: boolean
    patch: (row: WorkBoardRow, patch: Record<string, unknown>) => void
    lookups: BoardLookups
    fields: typeof BOARD_FIELDS
    heights: number[]
    selected: boolean
    style: React.CSSProperties
  }) {
    return (
      <div
        className={cx('absolute top-0 border-s border-line', selected ? 'bg-selected' : 'bg-surface')}
        style={{ ...style, position: 'absolute' }}
      >
        {fields.map((f, i) => (
          <div
            key={f.key}
            className="flex items-center overflow-hidden border-b border-line-subtle transition-colors hover:bg-hover"
            style={{ height: heights[i] }}
          >
            <div className="min-w-0 flex-1">{f.render({ row, canEdit, patch, lookups })}</div>
          </div>
        ))}
      </div>
    )
  },
  (a, b) =>
    a.row === b.row &&
    a.canEdit === b.canEdit &&
    a.selected === b.selected &&
    a.fields === b.fields &&
    a.heights === b.heights &&
    a.lookups === b.lookups &&
    a.style.insetInlineStart === b.style.insetInlineStart &&
    a.style.width === b.style.width,
)

/* ===== bulk edit ========================================================== */

function BulkEditModal({ open, onClose, taskIds, onDone }: { open: boolean; onClose: () => void; taskIds: string[]; onDone: () => void }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { data: statuses = [] } = useStatuses('task')
  const { data: contractors = [] } = useContractors()
  const { data: methods = [] } = useExecutionMethods()
  const [patch, setPatch] = useState<Record<string, string>>({})

  const apply = useMutation({
    mutationFn: async () => {
      const clean: Record<string, string> = {}
      for (const [k, v] of Object.entries(patch)) if (v !== '__skip__') clean[k] = v
      if (Object.keys(clean).length === 0) throw new Error('לא נבחרו שדות לעדכון')
      const { data, error } = await supabase.rpc('bulk_update_tasks', { p_task_ids: taskIds, p_patch: clean })
      if (error) throw error
      return data as number
    },
    onSuccess: (count) => {
      toast.success(`${count} משימות עודכנו`)
      void qc.invalidateQueries({ queryKey: ['workboard'] })
      void qc.invalidateQueries({ queryKey: ['calendar'] })
      setPatch({})
      onDone()
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const setIf = (key: string, value: string) => setPatch((p) => ({ ...p, [key]: value }))
  const changed = Object.values(patch).filter((v) => v !== '__skip__').length

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="עריכה מרובה"
      description={`השינויים יחולו על ${taskIds.length} משימות שנבחרו`}
      footer={
        <>
          <Button onClick={onClose}>ביטול</Button>
          <Button variant="primary" loading={apply.isPending} disabled={changed === 0} onClick={() => apply.mutate()}>
            עדכון {changed > 0 && `(${changed} שדות)`}
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <Field label="סטטוס">
          <Select value={patch.status_id ?? '__skip__'} onChange={(e) => setIf('status_id', e.target.value)}>
            <option value="__skip__">ללא שינוי</option>
            {statuses.map((s) => (
              <option key={s.id} value={s.id}>{s.name}</option>
            ))}
          </Select>
        </Field>
        <Field label="תאריך">
          <Input type="date" value={patch.task_date ?? ''} onChange={(e) => setIf('task_date', e.target.value || '__skip__')} />
        </Field>
        <Field label="אופן ביצוע">
          <Select value={patch.execution_method_id ?? '__skip__'} onChange={(e) => setIf('execution_method_id', e.target.value)}>
            <option value="__skip__">ללא שינוי</option>
            {methods.map((m) => (
              <option key={m.id} value={m.id}>{m.name}</option>
            ))}
          </Select>
        </Field>
        <Field label="קבלן">
          <Select value={patch.contractor_id ?? '__skip__'} onChange={(e) => setIf('contractor_id', e.target.value)}>
            <option value="__skip__">ללא שינוי</option>
            <option value="">הסרת קבלן</option>
            {contractors.map((c) => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </Select>
        </Field>
        <Field label="שעת התחלה במחסן">
          <Input type="time" value={patch.warehouse_start_time ?? ''} onChange={(e) => setIf('warehouse_start_time', e.target.value || '__skip__')} />
        </Field>
      </div>
    </Modal>
  )
}
