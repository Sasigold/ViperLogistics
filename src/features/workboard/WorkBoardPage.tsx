import { memo, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'react-router'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useVirtualizer } from '@tanstack/react-virtual'
import { addDays, differenceInCalendarDays, eachDayOfInterval, endOfMonth, parseISO, startOfMonth, startOfWeek } from 'date-fns'
import {
  AlertTriangle,
  CalendarCheck,
  CalendarDays,
  ChevronDown,
  ChevronUp,
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
import { NEUTRAL, readableOn } from '../../lib/colors'
import { useIsMobile } from '../../lib/useMediaQuery'
import { TaskDrawer } from '../tasks/TaskDrawer'
import { Can, RequirePermission } from '../auth/guards'
import { PERM } from '../../lib/permissions'
import { BOARD_FIELDS, DEFAULT_HIDDEN_FIELDS } from './boardFields'
import type { BoardLookups } from './boardFields'
import { COLOR_BY_OPTIONS, buildTones, clusterDay } from './grouping'
import type { Cluster, ColorBy, GroupTone } from './grouping'
import type { TaskRow, WorkBoardRow } from '../../types/domain'
import { errorMessage } from '../../lib/errors'

/* ── geometry ─────────────────────────────────────────────────────────────
   The board is transposed: days run across, task fields run down. The field
   legend on the inline-start edge is sticky and never scrolls away.       */

const SPINE_W = 46
const DAY_HEAD_H = 30
/** breathing room between one day's run of columns and the next day's */
const DAY_GAP = 10

/** a range wider than this is a report, not a board — empty days stop earning
 *  their width somewhere around a quarter */
const MAX_EMPTY_DAY_SPAN = 120

/**
 * Every dimension the board is drawn from, in one table. `minimal` squeezes the
 * whole frame — legend, header and type as well as the columns — because a
 * narrow column under a comfortable header just moves the crowding rather than
 * removing it. `empty` is the width of a day with nothing on it: an empty
 * Tuesday is information, and a board that hides it reads as a board with no
 * gaps — but it must not end up wider than the real columns beside it.
 */
const DENSITY = {
  comfortable: { col: 208, row: 38, tall: 46, legend: 150, head: 34, empty: 132, fs: '0.8125rem' },
  compact: { col: 168, row: 30, tall: 36, legend: 132, head: 30, empty: 120, fs: '0.78125rem' },
  minimal: { col: 112, row: 26, tall: 32, legend: 104, head: 26, empty: 96, fs: '0.75rem' },
} as const
type Density = keyof typeof DENSITY

/**
 * Which of the two boards to draw. `auto` is the old behaviour — cards below
 * `lg`, grid above — and the other two are the reader overriding it, which is
 * the whole point: a phone in landscape can hold the grid, and someone who
 * wants the grid on a phone is entitled to scroll for it.
 */
const VIEW_MODES = [
  { key: 'auto', label: 'אוטומטי' },
  { key: 'grid', label: 'טבלה' },
  { key: 'cards', label: 'כרטיסים' },
] as const
type ViewMode = (typeof VIEW_MODES)[number]['key']

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
  colorBy?: ColorBy
  emptyDays?: boolean
  view?: ViewMode
}

function loadPrefs(): Prefs {
  try {
    return JSON.parse(localStorage.getItem(PREFS_KEY) ?? '{}') as Prefs
  } catch {
    return {}
  }
}

/**
 * `gapAfter` marks the last column of a day. The gap is carried inside that
 * column's measured size rather than drawn as a column of its own, so the
 * virtualizer's offsets and the day bands' — which we compute ourselves —
 * cannot drift apart.
 */
type BoardColumn = { gapAfter?: boolean } & (
  | {
      kind: 'task'
      id: string
      row: WorkBoardRow
      dayKey: string
      /** the event (or customer) this column belongs to, and its colour */
      groupKey: string
      tone: GroupTone | null
      /** edges of the group, so a run of columns reads as one block */
      first: boolean
      last: boolean
    }
  | { kind: 'spine'; id: string; dayKey: string; count: number }
  | { kind: 'empty'; id: string; dayKey: string }
)

interface Band {
  dayKey: string
  start: number
  width: number
  count: number
  overdue: number
  collapsed: boolean
}

interface DayLayout {
  dayKey: string
  clusters: Cluster[]
  count: number
  overdue: number
  collapsed: boolean
}

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
    onError: (e) => toast.error(errorMessage(e)),
  })
}

export default function WorkBoardPage() {
  const { has } = useAuth()
  const canInline = has(PERM.BOARD_INLINE_EDIT)
  const canBulk = has(PERM.BOARD_BULK_EDIT)
  /**
   * Resolved per cell rather than once for the board: a field carries the key
   * that governs it, so the row can be half-editable. Stable across renders so
   * TaskColumn's memo comparison still holds.
   */
  const canEditCell = useCallback(
    (perm?: string) => canInline && (!perm || has(perm)),
    [canInline, has],
  )
  const [params] = useSearchParams()
  const prefs = useRef(loadPrefs())
  const isMobile = useIsMobile()
  const [filterSheet, setFilterSheet] = useState(false)

  const weekStart = startOfWeek(new Date(), { weekStartsOn: 0 })
  const [from, setFrom] = useState(params.get('date') || toISODate(weekStart))
  const [to, setTo] = useState(params.get('date') || toISODate(addDays(weekStart, 6)))
  const [filters, setFilters] = useState({ customer: '', status: '', type: '', contractor: '', q: '' })
  const [drawer, setDrawer] = useState<{ open: boolean; taskId: string | null; date?: string }>({
    open: !!params.get('task'),
    taskId: params.get('task'),
  })
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [bulkOpen, setBulkOpen] = useState(false)
  const [collapsedDays, setCollapsedDays] = useState<Set<string>>(new Set())
  const [hidden, setHidden] = useState<Set<string>>(new Set(prefs.current.hidden ?? DEFAULT_HIDDEN_FIELDS))
  const [density, setDensity] = useState<Density>(prefs.current.density ?? 'comfortable')
  const [sortBy, setSortBy] = useState<SortKey>(prefs.current.sort ?? 'time')
  const [colorBy, setColorBy] = useState<ColorBy>(prefs.current.colorBy ?? 'event')
  const [showEmptyDays, setShowEmptyDays] = useState(prefs.current.emptyDays ?? true)
  const [viewMode, setViewMode] = useState<ViewMode>(prefs.current.view ?? 'auto')
  /** "go to today" asked for a range that isn't loaded yet — scroll once it is */
  const [jumpPending, setJumpPending] = useState(false)
  const [showFilters, setShowFilters] = useState(false)
  /** the group under the pointer — its whole run lights up, across days */
  const [activeGroup, setActiveGroup] = useState<string | null>(null)
  const toast = useToast()

  useEffect(() => {
    try {
      localStorage.setItem(
        PREFS_KEY,
        JSON.stringify({ hidden: [...hidden], density, sort: sortBy, colorBy, emptyDays: showEmptyDays, view: viewMode }),
      )
    } catch {
      /* view preferences are not worth failing over */
    }
  }, [hidden, density, sortBy, colorBy, showEmptyDays, viewMode])

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

  /**
   * Two different questions, resolved in order. `viewPerm` decides whether a
   * row exists for this reader at all; `hidden` is their own choice among the
   * rows that do. Keeping them apart is what lets the field picker below offer
   * exactly the rows that could come back — a picker listing "צוות" for someone
   * who can never see it would be offering a switch wired to nothing.
   */
  const available = useMemo(() => BOARD_FIELDS.filter((f) => !f.viewPerm || has(f.viewPerm)), [has])
  const fields = useMemo(() => available.filter((f) => !hidden.has(f.key)), [available, hidden])
  const metrics = DENSITY[density]
  const headerH = DAY_HEAD_H + metrics.head
  const canSeeCustomers = has(PERM.CUSTOMERS_VIEW)
  /** cards below `lg` unless the reader has said otherwise */
  const asCards = viewMode === 'auto' ? isMobile : viewMode === 'cards'
  /* A phone holding the grid is already asking a lot of a small screen; the
     type comes down a step there on top of whatever density is set. */
  const boardFontSize = isMobile ? DENSITY.minimal.fs : metrics.fs

  /** one height array drives both the legend and every task column, so the
   *  grid can never drift out of alignment */
  const rowHeights = useMemo(() => fields.map((f) => (f.tall ? metrics.tall : metrics.row)), [fields, metrics])
  const bodyHeight = rowHeights.reduce((a, b) => a + b, 0)

  const today = toISODate(new Date())

  /* ── the day axis ─────────────────────────────────────────────────────────
     Every day in the chosen range gets a column, whether or not anything is
     scheduled on it. A quiet Tuesday is a fact worth seeing; a board built
     only from the days that happen to have tasks silently closes the gaps. */

  const tones = useMemo(() => buildTones(rows, colorBy), [rows, colorBy])

  const dayKeys = useMemo(() => {
    const withRows = [...new Set(rows.map((r) => r.task_date))].sort()
    if (!showEmptyDays || !from || !to) return withRows
    const a = parseISO(from)
    const b = parseISO(to)
    const span = differenceInCalendarDays(b, a)
    if (span < 0 || span > MAX_EMPTY_DAY_SPAN) return withRows
    const all = new Set(eachDayOfInterval({ start: a, end: b }).map(toISODate))
    for (const d of withRows) all.add(d)
    return [...all].sort()
  }, [rows, showEmptyDays, from, to])

  /* ── group by day, then lay the columns out in reading order ───────────── */

  const { columns, bands, totalWidth, daysForList } = useMemo(() => {
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
    const bandList: Band[] = []
    /** the same layout the grid is built from, so the mobile list and the
     *  desktop grid can never disagree about order or colour */
    const dayList: DayLayout[] = []
    let offset = 0

    for (const dayKey of dayKeys) {
      const dayRows = byDay.get(dayKey) ?? []
      const clusters = clusterDay(dayRows, colorBy, tones, cmp)
      const overdue = dayKey < today ? dayRows.filter((r) => !r.status_is_terminal).length : 0
      const collapsed = collapsedDays.has(dayKey)
      const start = offset

      if (dayRows.length === 0) {
        cols.push({ kind: 'empty', id: `empty:${dayKey}`, dayKey })
        offset += metrics.empty
      } else if (collapsed) {
        cols.push({ kind: 'spine', id: `spine:${dayKey}`, dayKey, count: dayRows.length })
        offset += SPINE_W
      } else {
        for (const cluster of clusters) {
          cluster.rows.forEach((row, i) => {
            cols.push({
              kind: 'task',
              id: row.id,
              row,
              dayKey,
              groupKey: cluster.key,
              tone: cluster.tone,
              first: i === 0,
              last: i === cluster.rows.length - 1,
            })
            offset += metrics.col
          })
        }
      }

      /* the band is measured before the gap is added, so it ends flush with
         its last column instead of reaching into the space after it */
      bandList.push({ dayKey, start, width: offset - start, count: dayRows.length, overdue, collapsed })
      dayList.push({ dayKey, clusters, count: dayRows.length, overdue, collapsed })

      if (dayKey !== dayKeys[dayKeys.length - 1]) {
        cols[cols.length - 1].gapAfter = true
        offset += DAY_GAP
      }
    }

    return { columns: cols, bands: bandList, totalWidth: offset, daysForList: dayList }
  }, [rows, dayKeys, sortBy, collapsedDays, metrics.col, metrics.empty, today, colorBy, tones])

  /* ── horizontal virtualization (RTL-aware) ───────────────────────────── */

  const scrollRef = useRef<HTMLDivElement>(null)
  const cardsRef = useRef<HTMLDivElement>(null)
  const virtualizer = useVirtualizer({
    horizontal: true,
    isRtl: true,
    count: columns.length,
    getScrollElement: () => scrollRef.current,
    estimateSize: (i) => {
      const col = columns[i]
      const gap = col?.gapAfter ? DAY_GAP : 0
      if (col?.kind === 'spine') return SPINE_W + gap
      if (col?.kind === 'empty') return metrics.empty + gap
      return metrics.col + gap
    },
    overscan: 6,
  })
  const virtualItems = virtualizer.getVirtualItems()

  /* react-virtual memoises its measurements on `count`/`getItemKey`/lanes and
     deliberately not on `estimateSize`, so changing density alone leaves every
     column at its old width — the row heights come from React and shrank, the
     widths did not. `measure()` drops the size cache and forces the estimate
     to be asked again. Layout effect, not effect: the track's total width is
     ours and updates immediately, so a frame with the new track and the old
     columns would be a visible jump. Keyed on `columns` rather than on the
     metrics: which column carries a day's trailing gap can move without the
     count changing, and that is exactly the case react-virtual cannot see. */
  useLayoutEffect(() => {
    virtualizer.measure()
  }, [virtualizer, columns])

  /* Day bands aren't virtualized — they're absolutely placed over the same
     track — so they're clipped to what the viewport can actually reach. */
  const viewport = useMemo(() => {
    if (virtualItems.length === 0) return { start: 0, end: 0 }
    const last = virtualItems[virtualItems.length - 1]
    return { start: virtualItems[0].start, end: last.start + last.size }
  }, [virtualItems])
  const overlaps = (start: number, width: number) => start < viewport.end && start + width > viewport.start
  const visibleBands = bands.filter((b) => overlaps(b.start, b.width))

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
  /** an empty day's only affordance: start the day that isn't there yet */
  const newTaskOn = useCallback((dayKey: string) => setDrawer({ open: true, taskId: null, date: dayKey }), [])
  const hoverGroup = useCallback((key: string | null) => setActiveGroup(key), [])

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

  /* ── jump to today ────────────────────────────────────────────────────────
     Not `virtualizer.scrollToIndex`: virtual-core reads a horizontal offset as
     `scrollLeft * -1` under RTL but writes it back unnegated, so every scroll
     it performs here would land on the mirror image of the target. The offset
     we need is one we already compute — a day band's `start` — so the scroller
     is driven directly, with the sign the library itself reads by.          */

  const scrollToToday = useCallback(() => {
    const band = bands.find((b) => b.dayKey === today)
    if (!band) return false
    if (asCards) {
      const section = cardsRef.current?.querySelector(`[data-day="${today}"]`)
      section?.scrollIntoView({ behavior: 'smooth', block: 'start' })
      return !!section
    }
    const el = scrollRef.current
    if (!el) return false
    /* `start` is measured along the track, and the legend is sticky *over* it
       rather than pushing it, so it needs no allowance here. */
    const offset = Math.max(0, band.start - 8)
    el.scrollTo({ left: getComputedStyle(el).direction === 'rtl' ? -offset : offset, behavior: 'smooth' })
    return true
  }, [bands, today, asCards])

  const goToToday = () => {
    // a folded day would otherwise "arrive" as a 46px spine
    setCollapsedDays((s) => (s.has(today) ? new Set([...s].filter((d) => d !== today)) : s))
    if (today >= from && today <= to) {
      if (!scrollToToday()) toast.info('אין משימות היום בטווח המוצג')
      return
    }
    const weekStart = startOfWeek(now, { weekStartsOn: 0 })
    setRange(weekStart, addDays(weekStart, 6))
    setJumpPending(true)
  }

  /* the range change has to round-trip to the server before today has a column
     to scroll to; the flag clears after one attempt either way */
  useEffect(() => {
    if (!jumpPending || isLoading) return
    if (!scrollToToday()) toast.info('אין משימות היום בטווח המוצג')
    setJumpPending(false)
  }, [jumpPending, isLoading, scrollToToday, toast])

  const overdueTotal = useMemo(
    () => rows.filter((r) => r.task_date < today && !r.status_is_terminal).length,
    [rows, today],
  )

  const workingDays = useMemo(() => bands.filter((b) => b.count > 0).length, [bands])
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
      {/* Both lists arrive already scoped by RLS. A filter over one option, or
          over none, is a control that cannot change what you see — so the test
          is what came back, which covers a client with a single company and a
          staff member without the key alike. */}
      {customers.length > 1 && (
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
      )}
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
      {contractors.length > 0 && (
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
      )}
    </>
  )

  return (
    <RequirePermission perm={PERM.BOARD_VIEW}>
      <div className="flex h-full min-h-0 flex-col gap-2">
        {/* ── compact header & toolbar ─────────────────────────────────── */}
        <div className="flex shrink-0 flex-col gap-2">
          {/* Main top bar */}
          <div className="surface flex flex-wrap items-center justify-between gap-2 p-2 rounded-xl">
            {/* Title & Stats */}
            <div className="flex items-center gap-2.5 min-w-0">
              <h1 className="type-title font-bold text-ink shrink-0">לוח עבודה</h1>
              <div className="hidden sm:flex flex-wrap items-center gap-1.5 type-caption text-ink-tertiary">
                <span className="tabular font-medium text-ink bg-subtle px-2 py-0.5 rounded-full">{rows.length} משימות</span>
                <span className="tabular bg-subtle px-2 py-0.5 rounded-full">{workingDays} ימי עבודה</span>
                {colorBy === 'event' && tones.size > 0 && <span className="tabular bg-subtle px-2 py-0.5 rounded-full">{tones.size} אירועים</span>}
                {overdueTotal > 0 && (
                  <span className="inline-flex items-center gap-1 font-medium text-error-text bg-error-subtle px-2 py-0.5 rounded-full">
                    <AlertTriangle size={ICON.xs} />
                    {overdueTotal} באיחור
                  </span>
                )}
              </div>
            </div>

            {/* Main actions & inline search/date controls */}
            <div className="flex flex-wrap items-center gap-1.5 ms-auto">
              <div className="hidden lg:flex items-center gap-1.5">
                {presetRow}
                <div className="h-4 w-px bg-line shrink-0 mx-0.5" aria-hidden />
                {dateFields}
              </div>

              <Input
                className="w-28 sm:w-36 lg:w-40"
                inputSize="sm"
                placeholder="חיפוש..."
                value={filters.q}
                onChange={(e) => setFilters((f) => ({ ...f, q: e.target.value }))}
                aria-label="חיפוש חופשי"
              />

              {/* icon only on purpose: the preset row above already says "היום",
                  and it means something else — narrow the range to one day */}
              <IconButton label="מעבר לעמודה של היום" size="sm" onClick={goToToday}>
                <CalendarCheck size={ICON.sm} strokeWidth={STROKE} />
              </IconButton>

              <Button
                size="sm"
                variant={showFilters || activeFilterCount > 0 ? 'outlined' : 'secondary'}
                onClick={() => setShowFilters((v) => !v)}
                className="shrink-0"
              >
                <Filter size={ICON.sm} strokeWidth={STROKE} />
                <span className="hidden sm:inline">סינון</span>
                {activeFilterCount > 0 && (
                  <span className="inline-flex size-4 items-center justify-center rounded-full bg-primary type-caption font-bold tabular text-on-primary text-[10px]">
                    {activeFilterCount}
                  </span>
                )}
                {showFilters ? <ChevronUp size={ICON.xs} /> : <ChevronDown size={ICON.xs} />}
              </Button>

              <Popover
                trigger={({ toggle, ...aria }) => (
                  <Button size="sm" variant="ghost" onClick={toggle} {...aria}>
                    <SlidersHorizontal size={ICON.sm} strokeWidth={STROKE} />
                    <span className="hidden sm:inline">תצוגה</span>
                  </Button>
                )}
              >
                {() => (
                  <div className="w-60 p-1.5">
                    <MenuLabel>סוג תצוגה</MenuLabel>
                    <SegmentedControl
                      block
                      items={VIEW_MODES.map((v) => ({ key: v.key, label: v.label }))}
                      value={viewMode}
                      onChange={setViewMode}
                    />
                    <p className="px-0.5 pt-1 type-caption text-ink-tertiary">
                      {viewMode === 'auto'
                        ? 'טבלה במסך רחב, כרטיסים במסך צר'
                        : viewMode === 'grid'
                          ? 'הטבלה המלאה בכל גודל מסך — במובייל נגללת לצדדים'
                          : 'כרטיסים לפי ימים בכל גודל מסך'}
                    </p>
                    <MenuLabel>צביעה לפי</MenuLabel>
                    <SegmentedControl
                      block
                      items={COLOR_BY_OPTIONS.map((o) => ({ key: o.key, label: o.label }))}
                      value={colorBy}
                      onChange={setColorBy}
                    />
                    <p className="px-0.5 pt-1 type-caption text-ink-tertiary">
                      {colorBy === 'event'
                        ? 'משימות של אותו אירוע נצבעות באותו גוון ומוצגות זו לצד זו'
                        : colorBy === 'customer'
                          ? 'כל לקוח בצבע שלו'
                          : 'ללא צביעה — רק הסטטוס צבוע'}
                    </p>
                    <div className="mt-2 px-0.5">
                      <Checkbox
                        label="הצגת ימים ריקים"
                        checked={showEmptyDays}
                        onChange={setShowEmptyDays}
                      />
                    </div>
                    <MenuLabel>צפיפות</MenuLabel>
                    <SegmentedControl
                      block
                      items={[
                        { key: 'comfortable', label: 'מרווח' },
                        { key: 'compact', label: 'צפוף' },
                        { key: 'minimal', label: 'מינימלי' },
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
                      <Button
                        size="sm"
                        variant="ghost"
                        block
                        onClick={() => setCollapsedDays(new Set(bands.filter((b) => b.count > 0).map((b) => b.dayKey)))}
                      >
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
                    <span className="hidden sm:inline">שדות</span>
                    <span className="tabular text-ink-tertiary text-xs">
                      {fields.length}/{available.length}
                    </span>
                  </Button>
                )}
              >
                {() => (
                  <div className="max-h-80 w-56 overflow-y-auto">
                    <MenuLabel>שורות מוצגות</MenuLabel>
                    {available.map((f) => (
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

              {selected.size > 0 && canBulk && (
                <Button size="sm" onClick={() => setBulkOpen(true)}>
                  <Pencil size={ICON.sm} strokeWidth={STROKE} />
                  <span className="hidden sm:inline">עריכה ({selected.size})</span>
                </Button>
              )}

              {has(PERM.TASKS_CREATE) && (
                <Button size="sm" variant="primary" onClick={() => setDrawer({ open: true, taskId: null })}>
                  <Plus size={ICON.sm} strokeWidth={STROKE} />
                  <span className="hidden sm:inline">משימה חדשה</span>
                </Button>
              )}
            </div>
          </div>

          {/* Secondary Collapsible Filters Row */}
          {showFilters && (
            <div className="surface flex flex-wrap items-center gap-2 p-2 rounded-xl text-sm transition-all duration-150">
              <div className="lg:hidden flex flex-wrap items-center gap-1.5 w-full pb-2 border-b border-line-subtle">
                {presetRow}
                {dateFields}
              </div>
              {lookupFilters}
              {activeFilterCount > 0 && (
                <Button size="sm" variant="ghost" className="text-ink-tertiary ms-auto" onClick={resetFilters}>
                  איפוס סינון
                </Button>
              )}
            </div>
          )}
        </div>

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
                has(PERM.TASKS_CREATE) && (
                  <Button variant="primary" size="sm" onClick={() => setDrawer({ open: true, taskId: null })}>
                    <Plus size={ICON.sm} />
                    משימה חדשה
                  </Button>
                )
              }
            />
          ) : asCards ? (
            /* A transposed 19-row grid wants a mouse and a wide viewport, so on
               a phone the same data reads better as a day-by-day card list by
               default — but "טבלה" in the view menu overrides that, and the
               drawer still owns every edit either way. */
            <MobileBoard
              containerRef={cardsRef}
              days={daysForList}
              today={today}
              selected={selected}
              canCreate={has(PERM.TASKS_CREATE)}
              onToggle={toggleOne}
              onOpen={openTask}
              onToggleDay={toggleDay}
              onNewTask={newTaskOn}
            />
          ) : (
            <div
              ref={scrollRef}
              className="h-full overflow-auto"
              style={{ '--vl-board-fs': boardFontSize } as React.CSSProperties}
            >
              <div className="relative flex" style={{ width: metrics.legend + totalWidth, minHeight: '100%' }}>
                {/* sticky field legend */}
                <div
                  className="sticky z-30 shrink-0 border-e border-line bg-surface"
                  style={{ insetInlineStart: 0, width: metrics.legend }}
                >
                  <div
                    className="sticky top-0 z-10 flex items-end justify-center border-b border-line bg-subtle px-2.5 pb-2"
                    style={{ height: headerH }}
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
                      className="flex items-center justify-center border-b border-line-subtle px-2.5 text-center type-caption font-semibold text-ink-secondary"
                      style={{ height: rowHeights[i] }}
                    >
                      <span className="truncate">{f.label}</span>
                    </div>
                  ))}
                </div>

                {/* virtualized track */}
                <div className="relative" style={{ width: totalWidth }}>
                  {/* header band: day groups + event bands + per-task headers */}
                  <div className="sticky top-0 z-20 bg-subtle" style={{ height: headerH }}>
                    {visibleBands.map((b) => {
                      const isToday = b.dayKey === today
                      const quiet = b.count === 0
                      return (
                        <div
                          key={b.dayKey}
                          className={cx(
                            'absolute top-0 flex items-center justify-center gap-1.5 overflow-hidden border-b border-s border-line px-2',
                            isToday
                              ? 'bg-[var(--vl-board-today)]'
                              : b.overdue > 0
                                ? 'bg-[var(--vl-board-overdue)]'
                                : 'bg-[var(--vl-board-band)]',
                          )}
                          style={{ insetInlineStart: b.start, width: b.width, height: DAY_HEAD_H }}
                        >
                          <button
                            onClick={() => !quiet && toggleDay(b.dayKey)}
                            disabled={quiet}
                            aria-expanded={quiet ? undefined : !b.collapsed}
                            aria-label={quiet ? fmtDate(b.dayKey) : `${b.collapsed ? 'פריסת' : 'קיפול'} ${fmtDate(b.dayKey)}`}
                            className="flex min-w-0 items-center gap-1 rounded transition-colors hover:text-ink focus-visible:outline-none focus-visible:focus-ring disabled:pointer-events-none"
                          >
                            {!quiet && (
                              <ChevronDown
                                size={ICON.xs}
                                className={cx('shrink-0 transition-transform duration-200', b.collapsed && 'rotate-90 rtl:-rotate-90')}
                              />
                            )}
                            <span
                              className={cx(
                                'truncate type-caption font-bold tabular',
                                quiet
                                  ? 'text-ink-tertiary'
                                  : isToday
                                    ? 'text-primary-text'
                                    : b.overdue > 0
                                      ? 'text-error-text'
                                      : 'text-ink-secondary',
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
                          {/* out of the flow, or it would push the date off centre */}
                          {!quiet && (
                            <span className="absolute inset-y-0 end-2 flex items-center type-caption tabular text-ink-tertiary">
                              {b.count}
                            </span>
                          )}
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
                          style={{
                            insetInlineStart: vi.start,
                            width: vi.size - (col.gapAfter ? DAY_GAP : 0),
                            top: DAY_HEAD_H,
                            height: metrics.head,
                          }}
                        >
                          {col.kind === 'spine' ? (
                            <SpineHeader dayKey={col.dayKey} count={col.count} onExpand={() => toggleDay(col.dayKey)} />
                          ) : col.kind === 'empty' ? (
                            <div className="h-full border-b border-s border-line bg-subtle/40" />
                          ) : (
                            <TaskHeader
                              row={col.row}
                              today={today}
                              groupKey={col.groupKey}
                              showCustomer={canSeeCustomers}
                              selected={selected.has(col.row.id)}
                              onToggle={toggleOne}
                              onOpen={openTask}
                              onHover={hoverGroup}
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
                      const width = vi.size - (col.gapAfter ? DAY_GAP : 0)
                      if (col.kind === 'spine')
                        return (
                          <div
                            key={col.id}
                            className="absolute top-0 border-s border-line bg-subtle/60"
                            style={{ insetInlineStart: vi.start, width, height: bodyHeight }}
                          />
                        )
                      if (col.kind === 'empty')
                        return (
                          <EmptyDayColumn
                            key={col.id}
                            dayKey={col.dayKey}
                            canCreate={has(PERM.TASKS_CREATE)}
                            onNewTask={newTaskOn}
                            style={{ insetInlineStart: vi.start, width, height: bodyHeight }}
                          />
                        )
                      return (
                        <TaskColumn
                          key={col.id}
                          row={col.row}
                          canEditCell={canEditCell}
                          patch={patchCell}
                          lookups={lookups}
                          fields={fields}
                          heights={rowHeights}
                          selected={selected.has(col.row.id)}
                          tone={col.tone}
                          groupKey={col.groupKey}
                          first={col.first}
                          last={col.last}
                          active={activeGroup === col.groupKey}
                          onHover={hoverGroup}
                          style={{ insetInlineStart: vi.start, width }}
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
            {canBulk && (
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
            <Field label="צביעה לפי" hint="משימות של אותו אירוע מקבלות את אותו צבע">
              <SegmentedControl
                block
                items={COLOR_BY_OPTIONS.map((o) => ({ key: o.key, label: o.label }))}
                value={colorBy}
                onChange={setColorBy}
              />
            </Field>
            <Checkbox label="הצגת ימים ריקים" checked={showEmptyDays} onChange={setShowEmptyDays} />
          </div>
        </Modal>

        <TaskDrawer
          open={drawer.open}
          onClose={() => setDrawer({ open: false, taskId: null })}
          taskId={drawer.taskId}
          initial={drawer.date ? ({ task_date: drawer.date } as Partial<TaskRow>) : undefined}
        />
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

function MobileBoard({
  containerRef,
  days,
  today,
  selected,
  canCreate,
  onToggle,
  onOpen,
  onToggleDay,
  onNewTask,
}: {
  /** so "go to today" can find a day's section without a global id */
  containerRef: React.Ref<HTMLDivElement>
  days: DayLayout[]
  today: string
  selected: Set<string>
  canCreate: boolean
  onToggle: (id: string) => void
  onOpen: (id: string) => void
  onToggleDay: (dayKey: string) => void
  onNewTask: (dayKey: string) => void
}) {
  return (
    <div ref={containerRef} className="h-full overflow-y-auto">
      {days.map((day) => {
        const isToday = day.dayKey === today
        const quiet = day.count === 0
        return (
          <section key={day.dayKey} data-day={day.dayKey}>
            <h3
              className={cx(
                'sticky top-0 z-10 flex items-center gap-1.5 border-b border-line px-2.5 py-1.5 backdrop-blur-sm',
                isToday
                  ? 'bg-[var(--vl-board-today)]'
                  : day.overdue > 0
                    ? 'bg-[var(--vl-board-overdue)]'
                    : 'bg-[var(--vl-board-band)]',
              )}
            >
              <button
                onClick={() => !quiet && onToggleDay(day.dayKey)}
                disabled={quiet}
                aria-expanded={quiet ? undefined : !day.collapsed}
                className="flex min-w-0 flex-1 items-center gap-1.5 text-start focus-visible:outline-none focus-visible:focus-ring disabled:pointer-events-none"
              >
                {!quiet && (
                  <ChevronDown
                    size={ICON.sm}
                    className={cx('shrink-0 transition-transform duration-200', day.collapsed && 'rotate-90 rtl:-rotate-90')}
                  />
                )}
                <span
                  className={cx(
                    'truncate type-button tabular',
                    quiet
                      ? 'text-ink-tertiary'
                      : isToday
                        ? 'text-primary-text'
                        : day.overdue > 0
                          ? 'text-error-text'
                          : 'text-ink-secondary',
                  )}
                >
                  {fmtDate(day.dayKey)}
                </span>
                {isToday && (
                  <span className="shrink-0 rounded-full bg-primary px-1.5 py-px text-[10px] font-bold text-on-primary">
                    היום
                  </span>
                )}
                {day.overdue > 0 && !isToday && (
                  <span className="inline-flex shrink-0 items-center gap-0.5 rounded-full bg-error px-1.5 py-px text-[10px] font-bold tabular text-white">
                    <AlertTriangle size={9} />
                    {day.overdue}
                  </span>
                )}
              </button>
              {/* a quiet day is one line, not a section — a week with four of
                  them shouldn't push the actual work off the screen */}
              {quiet ? (
                <>
                  <span className="type-caption text-ink-tertiary">אין משימות</span>
                  {canCreate && (
                    <IconButton label={`משימה חדשה ל-${fmtDate(day.dayKey)}`} size="sm" bare onClick={() => onNewTask(day.dayKey)}>
                      <Plus size={ICON.sm} strokeWidth={STROKE} />
                    </IconButton>
                  )}
                </>
              ) : (
                <span className="shrink-0 type-caption tabular text-ink-tertiary">{day.count}</span>
              )}
            </h3>

            {!quiet &&
              !day.collapsed &&
              day.clusters.map((cluster) => (
                <div key={cluster.key}>
                  {cluster.tone && (
                    <div
                      className="flex items-center gap-1.5 border-b border-line-subtle px-2.5 py-0.5"
                      style={{ background: cluster.tone.tintStrong }}
                    >
                      <span
                        className="inline-flex size-4 shrink-0 items-center justify-center rounded-full text-[10px] font-bold tabular text-white"
                        style={{ background: cluster.tone.solid }}
                      >
                        {cluster.tone.index}
                      </span>
                      <span className="truncate type-caption font-semibold" style={{ color: cluster.tone.solid }}>
                        {cluster.label}
                      </span>
                      {cluster.rows.length > 1 && (
                        <span className="ms-auto shrink-0 type-caption tabular text-ink-tertiary">
                          {cluster.rows.length} משימות
                        </span>
                      )}
                    </div>
                  )}
                  <ul className="divide-y divide-line-subtle">
                    {cluster.rows.map((row) => (
                      <li key={row.id}>
                        <MobileTaskCard
                          row={row}
                          tone={cluster.tone}
                          overdue={row.task_date < today && !row.status_is_terminal}
                          selected={selected.has(row.id)}
                          onToggle={onToggle}
                          onOpen={onOpen}
                        />
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
          </section>
        )
      })}
    </div>
  )
}

const MobileTaskCard = memo(function MobileTaskCard({
  row,
  tone,
  overdue,
  selected,
  onToggle,
  onOpen,
}: {
  row: WorkBoardRow
  tone: GroupTone | null
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
    <div
      className={cx(
        'flex items-stretch gap-1.5 px-2.5 py-1.5',
        selected ? 'bg-selected' : overdue && 'bg-[var(--vl-board-overdue)]',
      )}
      style={!selected && tone ? { background: tone.tint } : undefined}
    >
      <span
        aria-hidden
        className="w-1 shrink-0 rounded-full"
        style={{ background: tone?.solid ?? row.customer_color ?? 'var(--vl-border-strong)' }}
      />
      <span className="flex items-start pt-0.5">
        <Checkbox checked={selected} onChange={() => onToggle(row.id)} />
      </span>
      <button onClick={() => onOpen(row.id)} className="min-w-0 flex-1 space-y-0.5 text-start">
        <span className="flex items-center gap-1.5">
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

        <span className="block truncate type-button font-semibold">{label}</span>

        <span className="flex flex-wrap items-center gap-x-1.5 type-caption text-ink-tertiary">
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

        <span className="flex items-center gap-1.5">
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
  groupKey,
  showCustomer,
  selected,
  onToggle,
  onOpen,
  onHover,
}: {
  row: WorkBoardRow
  today: string
  groupKey: string
  /** the customer's identity is a permission; without it the header falls back */
  showCustomer: boolean
  selected: boolean
  onToggle: (id: string) => void
  onOpen: (id: string) => void
  onHover: (key: string | null) => void
}) {
  const overdue = row.task_date < today && !row.status_is_terminal
  const label = showCustomer
    ? (row.customer_name ?? 'ללא לקוח')
    : row.end_client_name || row.title || row.task_type_name
  /* The fill is the customer's own colour, straight from settings, so a
     regular can find their customer's columns without reading a word. The
     label flips between near-black and white by the fill's luminance —
     `color-mix(…, black N%)` only holds over a tint, never over a solid. */
  const fill = (showCustomer && row.customer_color) || NEUTRAL

  return (
    <div
      onMouseEnter={() => onHover(groupKey)}
      onMouseLeave={() => onHover(null)}
      className={cx(
        'group relative flex h-full items-center gap-1 border-b border-line px-1.5',
        selected && 'bg-selected',
      )}
      style={selected ? undefined : { background: fill, color: readableOn(fill) }}
    >
      <Checkbox checked={selected} onChange={() => onToggle(row.id)} />
      <Tooltip content={label}>
        <span className="min-w-0 flex-1 truncate text-center type-caption font-bold">{label}</span>
      </Tooltip>
      {overdue && (
        <Tooltip content="משימה פתוחה שעברה את מועדה">
          {/* currentColor, not text-error: red is unreadable on half the palette */}
          <AlertTriangle size={11} className="shrink-0" />
        </Tooltip>
      )}
      <IconButton
        label="פתיחת המשימה"
        size="sm"
        bare
        className="size-5 shrink-0 opacity-0 transition-opacity group-hover:opacity-100 focus-visible:opacity-100"
        /* inline so it beats the ghost variant's own colour, which would go
           dark-on-dark the moment a customer picks a deep hue */
        style={{ color: 'inherit' }}
        onClick={() => onOpen(row.id)}
      >
        <Pencil size={12} />
      </IconButton>
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

/* ===== a day with nothing on it =========================================== */

function EmptyDayColumn({
  dayKey,
  canCreate,
  onNewTask,
  style,
}: {
  dayKey: string
  canCreate: boolean
  onNewTask: (dayKey: string) => void
  style: React.CSSProperties
}) {
  return (
    <div
      className="absolute top-0 flex flex-col items-center justify-center gap-2 border-s border-line bg-subtle/40"
      style={style}
    >
      <CalendarDays size={ICON.lg} className="text-ink-tertiary/60" strokeWidth={STROKE} />
      <span className="type-caption text-ink-tertiary">אין משימות</span>
      {canCreate && (
        <Button size="sm" variant="ghost" onClick={() => onNewTask(dayKey)}>
          <Plus size={ICON.sm} strokeWidth={STROKE} />
          משימה
        </Button>
      )}
    </div>
  )
}

/* ===== one task's column of field cells =================================== */

const TaskColumn = memo(
  function TaskColumn({
    row,
    canEditCell,
    patch,
    lookups,
    fields,
    heights,
    selected,
    tone,
    groupKey,
    first,
    last,
    active,
    onHover,
    style,
  }: {
    row: WorkBoardRow
    canEditCell: (perm?: string) => boolean
    patch: (row: WorkBoardRow, patch: Record<string, unknown>) => void
    lookups: BoardLookups
    fields: typeof BOARD_FIELDS
    heights: number[]
    selected: boolean
    tone: GroupTone | null
    groupKey: string
    first: boolean
    last: boolean
    active: boolean
    onHover: (key: string | null) => void
    style: React.CSSProperties
  }) {
    /* The group's own colour draws its outer edges, so a run of columns reads
       as one block; the seams inside the run stay quiet. Both edges are inset
       shadows rather than a border and a shadow: the column carries no border
       of its own any more, and a leading edge declared as a border-*colour*
       with no width would silently draw nothing. */
    const edges =
      tone && (first || last)
        ? {
            boxShadow: [first && `inset 1px 0 0 0 ${tone.border}`, last && `inset -1px 0 0 0 ${tone.border}`]
              .filter(Boolean)
              .join(', '),
          }
        : undefined

    return (
      <div
        onMouseEnter={() => onHover(groupKey)}
        onMouseLeave={() => onHover(null)}
        className={cx('absolute top-0', selected ? 'bg-selected' : 'bg-surface')}
        style={{
          ...style,
          position: 'absolute',
          /* the same wash the header carries — a column whose body was paler
             than its own heading read as two different things stacked */
          ...(tone && !selected ? { background: active ? tone.tintStrong : tone.tint } : null),
          ...edges,
        }}
      >
        {fields.map((f, i) => (
          <div
            key={f.key}
            className="flex items-center justify-center overflow-hidden border-b border-line-subtle transition-colors hover:bg-hover"
            style={{ height: heights[i] }}
          >
            <div className="min-w-0 flex-1 text-center">
              {f.render({ row, canEdit: canEditCell(f.editPerm), patch, lookups })}
            </div>
          </div>
        ))}
      </div>
    )
  },
  (a, b) =>
    a.row === b.row &&
    a.canEditCell === b.canEditCell &&
    a.selected === b.selected &&
    a.fields === b.fields &&
    a.heights === b.heights &&
    a.lookups === b.lookups &&
    a.tone === b.tone &&
    a.active === b.active &&
    a.first === b.first &&
    a.last === b.last &&
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
    onError: (e) => toast.error(errorMessage(e)),
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
        {/* Each control is gated by the same key the column trigger checks, so
            the modal can't offer a change the database will reject. */}
        <Can perm={PERM.TASKS_CHANGE_STATUS}>
          <Field label="סטטוס">
            <Select value={patch.status_id ?? '__skip__'} onChange={(e) => setIf('status_id', e.target.value)}>
              <option value="__skip__">ללא שינוי</option>
              {statuses.map((s) => (
                <option key={s.id} value={s.id}>{s.name}</option>
              ))}
            </Select>
          </Field>
        </Can>
        <Can perm={PERM.TASKS_RESCHEDULE}>
          <Field label="תאריך">
            <Input type="date" value={patch.task_date ?? ''} onChange={(e) => setIf('task_date', e.target.value || '__skip__')} />
          </Field>
        </Can>
        <Can perm={PERM.TASKS_CHANGE_EXECUTION_METHOD}>
          <Field label="אופן ביצוע">
            <Select value={patch.execution_method_id ?? '__skip__'} onChange={(e) => setIf('execution_method_id', e.target.value)}>
              <option value="__skip__">ללא שינוי</option>
              {methods.map((m) => (
                <option key={m.id} value={m.id}>{m.name}</option>
              ))}
            </Select>
          </Field>
        </Can>
        <Can perm={PERM.TASKS_DELEGATE}>
          <Field label="קבלן">
            <Select value={patch.contractor_id ?? '__skip__'} onChange={(e) => setIf('contractor_id', e.target.value)}>
              <option value="__skip__">ללא שינוי</option>
              <option value="">הסרת קבלן</option>
              {contractors.map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </Select>
          </Field>
        </Can>
        <Can perm={PERM.TASKS_RESCHEDULE}>
          <Field label="שעת התחלה במחסן">
            <Input type="time" value={patch.warehouse_start_time ?? ''} onChange={(e) => setIf('warehouse_start_time', e.target.value || '__skip__')} />
          </Field>
        </Can>
      </div>
    </Modal>
  )
}
