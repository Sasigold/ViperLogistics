import { memo, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useVirtualizer } from '@tanstack/react-virtual'
import { addMonths, differenceInCalendarDays, eachDayOfInterval, endOfMonth, isSameMonth, parseISO, startOfMonth } from 'date-fns'
import {
  AlertTriangle,
  CalendarCheck,
  CalendarDays,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  ChevronUp,
  Columns3,
  Filter,
  ICON,
  MapPin,
  Plus,
  STROKE,
  Search,
  SlidersHorizontal,
} from '../../components/ui/icons'
import {
  Button,
  Checkbox,
  EmptyState,
  ErrorState,
  IconButton,
  Input,
  MenuLabel,
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
import {
  useContractors,
  useCustomers,
  useExecutionMethods,
  useStaff,
  useStatuses,
  useTaskTypes,
  useTrucks,
} from '../../lib/queries'
import { fmtDate, fmtMonth, fmtTime, toISODate } from '../../lib/dates'
import { shortAddress } from '../../lib/address'
import { NEUTRAL, readableOn } from '../../lib/colors'
import { useIsMobile } from '../../lib/useMediaQuery'
import { useDragScroll } from '../../lib/useDragScroll'
import { KIND_LABEL, holidaysInRange, isDayOff } from '../../lib/hebrewHolidays'
import type { Holiday } from '../../lib/hebrewHolidays'
import { TaskDrawer } from '../tasks/TaskDrawer'
import { RequirePermission } from '../auth/guards'
import { PERM } from '../../lib/permissions'
import { BOARD_FIELDS, DEFAULT_HIDDEN_FIELDS } from './boardFields'
import type { BoardLookups } from './boardFields'
import { COLOR_BY_OPTIONS, buildTones, clusterDay, isOverdue } from './grouping'
import type { Cluster, ColorBy, GroupTone } from './grouping'
import type { StaffRole, TaskRow, WorkBoardRow } from '../../types/domain'
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

/** the crumb of air above and below the team cell's list of names */
const TEAM_ROW_PAD = 4

/**
 * How long a press on a column's name waits to see whether a second one is
 * coming. Shorter than the cells' own window: here the wait is spent *before*
 * the single-press action rather than after it, and a navigation that hesitates
 * is felt.
 */
const HEADER_CLICK_MS = 280

/**
 * Every dimension the board is drawn from, in one table. `minimal` squeezes the
 * whole frame — legend, header and type as well as the columns — because a
 * narrow column under a comfortable header just moves the crowding rather than
 * removing it. `empty` is the width of a day with nothing on it: an empty
 * Tuesday is information, and a board that hides it reads as a board with no
 * gaps — but it must not end up wider than the real columns beside it.
 *
 * `line` is the height of one name in the team cell, and the number the row's
 * own height is computed from — see `teamRowHeight`.
 */
const DENSITY = {
  comfortable: { col: 208, row: 38, tall: 46, legend: 150, head: 34, empty: 132, fs: '0.8125rem', line: 17 },
  compact: { col: 168, row: 30, tall: 36, legend: 132, head: 30, empty: 120, fs: '0.78125rem', line: 16 },
  minimal: { col: 112, row: 26, tall: 32, legend: 104, head: 26, empty: 96, fs: '0.75rem', line: 15 },
  /* A whole month of days at once is a different job from reading one of them.
     This one narrows the *column* and the type inside it and nothing else: the
     rows keep the heights of `minimal`, because a shorter row would cut what a
     narrower one only wraps, and the reason to want a month on one screen is
     never "show me less of each day". */
  micro: { col: 74, row: 26, tall: 32, legend: 84, head: 26, empty: 58, fs: '0.6875rem', line: 14 },
} as const
type Density = keyof typeof DENSITY

const DENSITY_OPTIONS: { key: Density; label: string }[] = [
  { key: 'comfortable', label: 'מרווח' },
  { key: 'compact', label: 'צפוף' },
  { key: 'minimal', label: 'מינימלי' },
  { key: 'micro', label: 'זעיר' },
]

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

/**
 * מערך ריק *אחד* לכל ברירות המחדל של השאילתות בעמוד הזה.
 *
 * ‏`const { data: rows = [] }` נראה תמים, אבל כל עוד השאילתה לא החזירה — כלומר
 * בדיוק בזמן הכניסה למסך ובזמן החלפת חודש — הוא מייצר מערך *חדש* בכל render.
 * המערך הזה הוא התלות של `tones`, של `dayKeys` ושל `columns`, ולכן כל השרשרת
 * מחושבת מחדש, `columns` מקבל זהות חדשה, ה-layout effect שמודד את הווירטואלייזר
 * רץ שוב, `measure()` מבקש render — וחוזר חלילה. אחרי חמישים סיבובים React
 * עוצר את הלולאה עם שגיאה #185 ("Maximum update depth exceeded"), וזה מה
 * שהמשתמש ראה ככרטיס "משהו נשבר במסך הזה".
 *
 * קבוע יחיד שומר על זהות יציבה, והשרשרת נחה עד שיש נתונים אמיתיים.
 */
const EMPTY: never[] = []

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
    }
  | { kind: 'spine'; id: string; dayKey: string; count: number }
  | { kind: 'empty'; id: string; dayKey: string }
)

interface Band {
  dayKey: string
  start: number
  width: number
  count: number
  collapsed: boolean
}

interface DayLayout {
  dayKey: string
  clusters: Cluster[]
  count: number
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

/**
 * Staffing is not a column on `tasks`, so the staffing cells cannot ride the
 * patch above: a team lead, a worker and a driver are each a row in
 * `task_assignments`, and RLS there is granular per role. One row in, one row
 * out — no read-modify-write of the whole set, so two dispatchers assigning
 * two different people at the same moment do not overwrite each other.
 */
function useAssignmentUpdate() {
  const qc = useQueryClient()
  const toast = useToast()
  return useMutation({
    mutationFn: async ({
      row,
      role,
      profileId,
      on,
    }: {
      row: WorkBoardRow
      role: StaffRole
      profileId: string
      on: boolean
    }) => {
      if (!on) {
        const { error } = await supabase
          .from('task_assignments')
          .delete()
          .eq('task_id', row.id)
          .eq('profile_id', profileId)
          .eq('role', role)
        if (error) throw error
        return
      }
      /* one lead per task is a unique index, so the seat is cleared first */
      if (role === 'team_lead') {
        const { error } = await supabase
          .from('task_assignments')
          .delete()
          .eq('task_id', row.id)
          .eq('role', 'team_lead')
        if (error) throw error
      }
      const { error } = await supabase
        .from('task_assignments')
        .insert({ task_id: row.id, profile_id: profileId, role, work_site: 'field' })
      if (error) throw error
    },
    onSettled: () => void qc.invalidateQueries({ queryKey: ['workboard'] }),
    onError: (e) => toast.error(errorMessage(e)),
  })
}

export default function WorkBoardPage() {
  const { has } = useAuth()
  const canInline = has(PERM.BOARD_INLINE_EDIT)
  const canOpenEvent = has(PERM.EVENTS_VIEW)
  const navigate = useNavigate()
  /**
   * Resolved per cell rather than once for the board: a field carries the key
   * that governs it, so the row can be half-editable. Stable across renders so
   * TaskColumn's memo comparison still holds.
   */
  const canEditCell = useCallback(
    (perm?: string) => canInline && (!perm || has(perm)),
    [canInline, has],
  )
  const [params, setParams] = useSearchParams()
  const prefs = useRef(loadPrefs())
  const isMobile = useIsMobile()

  /**
   * The board is a month at a time. Two free date pickers plus four presets
   * were six controls answering a question that has one natural answer — the
   * month you are working in — and a range nobody chose deliberately (a week
   * starting on whatever Sunday) was the default. `?date=` still decides which
   * month opens, so a link from the calendar or a notification lands right.
   */
  const [month, setMonth] = useState(() => {
    const d = params.get('date')
    return startOfMonth(d ? parseISO(d) : new Date())
  })
  const from = toISODate(month)
  const to = toISODate(endOfMonth(month))
  const [filters, setFilters] = useState({ customer: '', status: '', type: '', contractor: '', q: '' })
  const [drawer, setDrawer] = useState<{ open: boolean; taskId: string | null; date?: string }>({
    open: !!params.get('task'),
    taskId: params.get('task'),
  })
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
  /** phone only — the field lives behind its icon until it is asked for */
  const [searchOpen, setSearchOpen] = useState(false)
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
  const { data: statuses = EMPTY } = useStatuses('task')
  const { data: taskTypes = EMPTY } = useTaskTypes()
  const { data: contractors = EMPTY } = useContractors()
  const { data: methods = EMPTY } = useExecutionMethods()
  const { data: trucks = EMPTY } = useTrucks()
  /* only fetched for the staffing cells, and those are gated by the same key */
  const { data: staff = EMPTY } = useStaff(has(PERM.BOARD_VIEW_STAFFING))
  const inline = useInlineUpdate()
  const staffing = useAssignmentUpdate()

  const { data: rows = EMPTY, isLoading, error: rowsError, refetch: refetchRows } = useQuery({
    queryKey: ['workboard', 'range', from, to, filters],
    queryFn: async () => {
      let q = supabase
        .from('work_board_view')
        .select('*')
        .gte('task_date', from)
        .lte('task_date', to)
        /* an event that was cancelled is work that will not happen, and a
           schedule is a list of work that will — its tasks are not deleted
           (the event page and the log still have them), only unlisted here */
        .eq('event_is_cancelled', false)
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

  const lookups = useMemo<BoardLookups>(
    () => ({ statuses, trucks, methods, contractors, staff }),
    [statuses, trucks, methods, contractors, staff],
  )
  const patchCell = useCallback(
    (row: WorkBoardRow, patch: Record<string, unknown>) => inline.mutate({ row, patch }),
    [inline],
  )
  const assignCell = useCallback(
    (row: WorkBoardRow, role: StaffRole, profileId: string, on: boolean) =>
      staffing.mutate({ row, role, profileId, on }),
    [staffing],
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
     type comes down a step there on top of whatever density is set — but never
     back *up*, so choosing "זעיר" on a phone still gets the smallest type. */
  const boardFontSize =
    isMobile && (density === 'comfortable' || density === 'compact') ? DENSITY.minimal.fs : metrics.fs

  /**
   * The team row lists everyone by name, so its height is the size of the
   * biggest crew on the board rather than a constant — one row per person,
   * with a ceiling so a single 30-strong day can't push every other field off
   * the screen (that crew scrolls inside its own cell).
   */
  const teamRowHeight = useMemo(() => {
    const most = rows.reduce(
      (m, r) =>
        Math.max(
          m,
          (r.workers?.length ?? 0) + (r.drivers?.length ?? 0) + (r.contractor_worker_list?.length ?? 0),
        ),
      0,
    )
    return Math.max(metrics.tall, most * metrics.line + TEAM_ROW_PAD)
  }, [rows, metrics])

  /** one height array drives both the legend and every task column, so the
   *  grid can never drift out of alignment */
  const rowHeights = useMemo(
    () =>
      fields.map((f) =>
        f.key === 'team'
          ? teamRowHeight
          : f.grow
            ? metrics.row * f.grow
            : f.tall
              ? metrics.tall
              : metrics.row,
      ),
    [fields, metrics, teamRowHeight],
  )
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

  /* חגים ומועדים לימים שעל הלוח. ‏`dayKeys` ולא הטווח המבוקש: יום שנשר
     מהלוח (בלי משימות, כשהימים הריקים מוסתרים) גם לא צריך חג. */
  const holidays = useMemo(
    () => (dayKeys.length ? holidaysInRange(dayKeys[0], dayKeys[dayKeys.length - 1]) : new Map<string, Holiday>()),
    [dayKeys],
  )

  /* ── group by day, then lay the columns out in reading order ───────────── */

  const { columns, bands, totalWidth, daysForList, sizeKey } = useMemo(() => {
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
      /* the hour the crew is due on site, and only that one: a warehouse
         call at 05:00 is not what the day is read by, and letting it stand
         in for a missing on-site time put those tasks first */
      const at = a.onsite_start_time ?? '99:99'
      const bt = b.onsite_start_time ?? '99:99'
      if (at !== bt) return at.localeCompare(bt)
      /* same on-site hour (or none at all) — leaving is the next thing that
         separates them, then the name, so the order never wobbles */
      const aw = a.warehouse_start_time ?? '99:99'
      const bw = b.warehouse_start_time ?? '99:99'
      if (aw !== bw) return aw.localeCompare(bw)
      return (a.customer_name ?? '').localeCompare(b.customer_name ?? '', 'he')
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
          cluster.rows.forEach((row) => {
            cols.push({
              kind: 'task',
              id: row.id,
              row,
              dayKey,
              groupKey: cluster.groupKey,
              tone: cluster.tone,
            })
            offset += metrics.col
          })
        }
      }

      /* the band is measured before the gap is added, so it ends flush with
         its last column instead of reaching into the space after it */
      bandList.push({ dayKey, start, width: offset - start, count: dayRows.length, collapsed })
      dayList.push({ dayKey, clusters, count: dayRows.length, collapsed })

      if (dayKey !== dayKeys[dayKeys.length - 1]) {
        cols[cols.length - 1].gapAfter = true
        offset += DAY_GAP
      }
    }

    /* חתימה סקלרית של כל מה שרוחב עמודה נגזר ממנו — סוג העמודה והאם היא
       נושאת את הרווח של סוף היום. היא, ולא זהות המערך, מה שמפעיל את המדידה
       מחדש: כך רענון של `columns` שאינו משנה דבר ברוחבים אינו יכול לגרור
       render נוסף, וגם לא לולאה. */
    const sizeKey = `${metrics.col}/${metrics.empty}/${cols.map((c) => (c.gapAfter ? c.kind[0].toUpperCase() : c.kind[0])).join('')}`

    return { columns: cols, bands: bandList, totalWidth: offset, daysForList: dayList, sizeKey }
  }, [rows, dayKeys, sortBy, collapsedDays, metrics.col, metrics.empty, colorBy, tones])

  /* ── horizontal virtualization (RTL-aware) ───────────────────────────── */

  const scrollRef = useRef<HTMLDivElement>(null)
  const cardsRef = useRef<HTMLDivElement>(null)

  /* בעכבר אפשר גם לתפוס את הלוח ולמשוך אותו. התנאי הוא גם המפתח שמפעיל את
     ההאזנה מחדש: המיכל עצמו קיים רק בתצוגת הטבלה, ורק אחרי שהנתונים הגיעו. */
  useDragScroll(scrollRef, !asCards && !isLoading && rows.length > 0)

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
     count changing, and that is exactly the case react-virtual cannot see.

     התלות היא `sizeKey` ולא `columns` עצמו — מחרוזת שנגזרת מאותם נתונים בדיוק,
     אבל שנשארת שווה לעצמה כשהמערך נבנה מחדש בלי שרוחב כלשהו זז. ‏`measure()`
     מבקש render, ו-render שמייצר `columns` חדש היה מחזיר אותנו לכאן: זו הלולאה
     שהפילה את המסך בשגיאה #185. */
  useLayoutEffect(() => {
    virtualizer.measure()
  }, [virtualizer, sizeKey])

  /* Day bands aren't virtualized — they're absolutely placed over the same
     track — so they're clipped to what the viewport can actually reach. */
  const viewport = useMemo(() => {
    if (virtualItems.length === 0) return { start: 0, end: 0 }
    const last = virtualItems[virtualItems.length - 1]
    return { start: virtualItems[0].start, end: last.start + last.size }
  }, [virtualItems])
  const overlaps = (start: number, width: number) => start < viewport.end && start + width > viewport.start
  const visibleBands = bands.filter((b) => overlaps(b.start, b.width))

  /**
   * ‏?task= ו-?date= נקראו עד כה רק ב-useState initializer שלמעלה, כלומר רק
   * בטעינת המסך. לחיצה על התראה שנייה בזמן שהלוח כבר פתוח החליפה את ה-URL ולא
   * עשתה דבר — וזה בדיוק המצב שאחרי שהפעמון הפך ללחיץ. הקריאה כאן היא על
   * שינוי הפרמטרים, ולכן היא מכסה גם את הנחיתה הראשונה וגם את כל הבאות.
   *
   * ‏TaskDrawer שולף את המשימה לפי המזהה בעצמו, ולכן היא נפתחת גם כשהחודש
   * שמאחוריה עוד נטען.
   */
  const taskParam = params.get('task')
  const dateParam = params.get('date')
  useEffect(() => {
    if (dateParam) setMonth(startOfMonth(parseISO(dateParam)))
  }, [dateParam])
  useEffect(() => {
    if (taskParam) setDrawer({ open: true, taskId: taskParam })
  }, [taskParam])

  const openTask = useCallback((id: string) => setDrawer({ open: true, taskId: id }), [])
  /** stable, because TaskHeader is memoised on a shallow prop compare */
  const openEvent = useCallback((id: string) => void navigate(`/events/${id}`), [navigate])
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

  const now = new Date()
  const shiftMonth = (by: number) => setMonth((m) => addMonths(m, by))

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
    if (isSameMonth(month, now)) {
      if (!scrollToToday()) toast.info('אין משימות היום בטווח המוצג')
      return
    }
    setMonth(startOfMonth(now))
    setJumpPending(true)
  }

  /* the range change has to round-trip to the server before today has a column
     to scroll to; the flag clears after one attempt either way */
  useEffect(() => {
    if (!jumpPending || isLoading) return
    if (!scrollToToday()) toast.info('אין משימות היום בטווח המוצג')
    setJumpPending(false)
  }, [jumpPending, isLoading, scrollToToday, toast])

  /* "באיחור" נמדד לפי הפרסום ולא לפי `status_is_terminal`. מאז 0063 אין
     למשימה סטטוס סוגר בכלל — טיוטה, מתוכנן ומשובץ, וזהו — ולכן הבדיקה
     הישנה הייתה מסמנת כל משימה שתאריכה עבר. מה שבאמת פספסנו הוא משימה
     שהתאריך שלה חלף והיא עדיין לא הגיעה לעובד. */
  const overdueTotal = useMemo(() => rows.filter(isOverdue(today)).length, [rows, today])

  const workingDays = useMemo(() => bands.filter((b) => b.count > 0).length, [bands])
  const activeFilterCount = Object.values(filters).filter(Boolean).length
  const resetFilters = () => setFilters({ customer: '', status: '', type: '', contractor: '', q: '' })

  /* ── filter controls ──────────────────────────────────────────────────────
     One definition, two homes: a single toolbar row on desktop, and a dialog
     on mobile. Left inline, the six controls stacked to about 400px — most of
     a phone screen — before the board even started.                        */

  /* One control for the whole date question: which month. The arrows are
     logical — "back" is the inline-end side under RTL — so the chevrons point
     the way the reader's eye travels. */
  const monthNav = (
    <div className="flex shrink-0 items-center gap-0.5 rounded-lg bg-subtle p-0.5">
      <IconButton label="חודש קודם" size="sm" bare onClick={() => shiftMonth(-1)}>
        <ChevronRight size={ICON.sm} strokeWidth={STROKE} className="rtl:rotate-0 ltr:rotate-180" />
      </IconButton>
      <button
        onClick={() => setMonth(startOfMonth(now))}
        title="חזרה לחודש הנוכחי"
        className={cx(
          'min-w-24 rounded-md px-2 py-0.5 text-center type-caption font-bold transition-colors hover:bg-hover',
          isSameMonth(month, now) ? 'text-ink' : 'text-ink-secondary',
        )}
      >
        {fmtMonth(month)}
      </button>
      <IconButton label="חודש הבא" size="sm" bare onClick={() => shiftMonth(1)}>
        <ChevronLeft size={ICON.sm} strokeWidth={STROKE} className="rtl:rotate-0 ltr:rotate-180" />
      </IconButton>
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
              <h1 className="type-title font-bold text-ink shrink-0">לו״ז עבודה</h1>
              {monthNav}
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
              {/* On a phone the field alone took a whole row of a toolbar that
                  has five other controls in it, and search is the one thing
                  here nobody uses twice in a row — so it folds into its icon
                  and opens over the toolbar when it is actually wanted. */}
              <Input
                className="hidden w-36 sm:block lg:w-40"
                inputSize="sm"
                placeholder="חיפוש..."
                value={filters.q}
                onChange={(e) => setFilters((f) => ({ ...f, q: e.target.value }))}
                aria-label="חיפוש חופשי"
              />
              <IconButton
                label={searchOpen ? 'סגירת החיפוש' : 'חיפוש'}
                size="sm"
                className="sm:hidden"
                variant={filters.q ? 'outlined' : undefined}
                onClick={() => setSearchOpen((v) => !v)}
              >
                <Search size={ICON.sm} strokeWidth={STROKE} />
              </IconButton>

              {/* icon only on purpose: this scrolls to today's column, while
                  the month title beside it jumps to today's *month* */}
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
                    <SegmentedControl block items={DENSITY_OPTIONS} value={density} onChange={setDensity} />
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

              {has(PERM.TASKS_CREATE) && (
                <Button size="sm" variant="primary" onClick={() => setDrawer({ open: true, taskId: null })}>
                  <Plus size={ICON.sm} strokeWidth={STROKE} />
                  <span className="hidden sm:inline">משימה חדשה</span>
                </Button>
              )}
            </div>
          </div>

          {searchOpen && (
            <div className="surface flex items-center gap-1.5 p-2 rounded-xl sm:hidden">
              <Input
                className="flex-1"
                inputSize="sm"
                autoFocus
                placeholder="חיפוש..."
                value={filters.q}
                onChange={(e) => setFilters((f) => ({ ...f, q: e.target.value }))}
                aria-label="חיפוש חופשי"
              />
              <Button
                size="sm"
                variant="ghost"
                onClick={() => {
                  setFilters((f) => ({ ...f, q: '' }))
                  setSearchOpen(false)
                }}
              >
                סגירה
              </Button>
            </div>
          )}

          {/* Secondary Collapsible Filters Row */}
          {showFilters && (
            <div className="surface flex flex-wrap items-center gap-2 p-2 rounded-xl text-sm transition-all duration-150">
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
          ) : rowsError != null ? (
            <ErrorState error={rowsError} onRetry={() => void refetchRows()} />
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
              holidays={holidays}
              canCreate={has(PERM.TASKS_CREATE)}
              onOpen={openTask}
              onToggleDay={toggleDay}
              onNewTask={newTaskOn}
            />
          ) : (
            <div
              ref={scrollRef}
              className="h-full overflow-auto"
              style={
                {
                  '--vl-board-fs': boardFontSize,
                  '--vl-board-line': `${metrics.line}px`,
                } as React.CSSProperties
              }
            >
              <div className="relative flex" style={{ width: metrics.legend + totalWidth, minHeight: '100%' }}>
                {/* sticky field legend */}
                <div
                  className="sticky z-30 shrink-0 border-e border-line bg-surface"
                  style={{ insetInlineStart: 0, width: metrics.legend }}
                >
                  {/* empty, but it still has to hold the legend level with the
                      day band and the column headers beside it */}
                  <div
                    className="sticky top-0 z-10 border-b border-line bg-subtle"
                    style={{ height: headerH }}
                  />
                  {fields.map((f, i) => (
                    <div
                      key={f.key}
                      className="flex items-center justify-center border-b border-line-subtle px-2.5 text-center type-caption font-semibold text-ink-secondary"
                      style={{ height: rowHeights[i] }}
                    >
                      {/* the legend narrows with the board, so its own labels
                          are the first thing the tightest widths cut */}
                      <Tooltip content={f.label}>
                        <span className="truncate">{f.label}</span>
                      </Tooltip>
                    </div>
                  ))}
                </div>

                {/* virtualized track */}
                <div className="relative" style={{ width: totalWidth }}>
                  {/* header band: day groups + event bands + per-task headers */}
                  {/* bg-surface, not bg-subtle: the strip runs the whole track
                      and a tinted one filled the gap between two days, so the
                      header read as continuous over a body that is not */}
                  <div className="sticky top-0 z-20 bg-surface" style={{ height: headerH }}>
                    {visibleBands.map((b) => {
                      const isToday = b.dayKey === today
                      const quiet = b.count === 0
                      const holiday = holidays.get(b.dayKey)
                      return (
                        <div
                          key={b.dayKey}
                          className={cx(
                            'absolute top-0 flex items-center justify-center gap-1.5 overflow-hidden border-b border-s border-line px-2',
                            /* a past day is a past day — the tasks on it carry
                               their own overdue mark, and painting the whole
                               band red turned every old week into a wall */
                            isToday
                              ? 'bg-[var(--vl-board-today)]'
                              : /* שבתון נצבע, מועד שאין בו שבתון מקבל רמז, ושאר
                                   הימים נשארים כפי שהיו */
                                isDayOff(holiday)
                                ? 'bg-[var(--vl-board-holiday)]'
                                : holiday
                                  ? 'bg-[var(--vl-board-holiday-soft)]'
                                  : 'bg-[var(--vl-board-band)]',
                          )}
                          style={{ insetInlineStart: b.start, width: b.width, height: DAY_HEAD_H }}
                        >
                          {/* the date is a label. Folding a day from here was
                              one careless click away from hiding a day's work,
                              and the width menu now covers the same need */}
                          <span
                            className={cx(
                              'truncate type-caption font-bold tabular',
                              quiet ? 'text-ink-tertiary' : isToday ? 'text-primary-text' : 'text-ink-secondary',
                            )}
                          >
                            {fmtDate(b.dayKey)}
                          </span>
                          {isToday && (
                            <span className="shrink-0 rounded-full bg-primary px-1.5 py-px text-[10px] font-bold text-on-primary">
                              היום
                            </span>
                          )}
                          {holiday && (
                            <Tooltip content={`${holiday.name} — ${KIND_LABEL[holiday.kind]}`}>
                              <span
                                className={cx(
                                  'truncate type-caption',
                                  isDayOff(holiday) ? 'font-bold text-warning-text' : 'text-ink-secondary',
                                )}
                              >
                                {holiday.name}
                              </span>
                            </Tooltip>
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
                              groupKey={col.groupKey}
                              showCustomer={canSeeCustomers}
                              canOpenEvent={canOpenEvent}
                              onOpen={openTask}
                              onOpenEvent={openEvent}
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
                            narrow={metrics.empty < 96}
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
                          assign={assignCell}
                          lookups={lookups}
                          fields={fields}
                          heights={rowHeights}
                          tone={col.tone}
                          groupKey={col.groupKey}
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

        <TaskDrawer
          open={drawer.open}
          onClose={() => {
            setDrawer({ open: false, taskId: null })
            /* ‏?task= יורד עם המגירה. אחרת לחיצה חוזרת על אותה התראה לא הייתה
               משנה את הפרמטר, והאפקט שלמעלה לא היה נורה שנית. */
            if (params.has('task')) {
              const next = new URLSearchParams(params)
              next.delete('task')
              setParams(next, { replace: true })
            }
          }}
          taskId={drawer.taskId}
          initial={drawer.date ? ({ task_date: drawer.date } as Partial<TaskRow>) : undefined}
        />
      </div>
    </RequirePermission>
  )
}

/* ===== mobile board =======================================================
   Days stack vertically, tasks inside them are cards. Every affordance the
   desktop grid offers through hover — open a task, fold a day — has a real
   target here, and nothing scrolls sideways.                               */

function MobileBoard({
  containerRef,
  days,
  today,
  holidays,
  canCreate,
  onOpen,
  onToggleDay,
  onNewTask,
}: {
  /** so "go to today" can find a day's section without a global id */
  containerRef: React.Ref<HTMLDivElement>
  days: DayLayout[]
  today: string
  holidays: Map<string, Holiday>
  canCreate: boolean
  onOpen: (id: string) => void
  onToggleDay: (dayKey: string) => void
  onNewTask: (dayKey: string) => void
}) {
  return (
    <div ref={containerRef} className="h-full overflow-y-auto">
      {days.map((day) => {
        const isToday = day.dayKey === today
        const quiet = day.count === 0
        const holiday = holidays.get(day.dayKey)
        return (
          <section key={day.dayKey} data-day={day.dayKey}>
            <h3
              className={cx(
                'sticky top-0 z-10 flex items-center gap-1.5 border-b border-line px-2.5 py-1.5 backdrop-blur-sm',
                isToday
                  ? 'bg-[var(--vl-board-today)]'
                  : isDayOff(holiday)
                    ? 'bg-[var(--vl-board-holiday)]'
                    : holiday
                      ? 'bg-[var(--vl-board-holiday-soft)]'
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
                    quiet ? 'text-ink-tertiary' : isToday ? 'text-primary-text' : 'text-ink-secondary',
                  )}
                >
                  {fmtDate(day.dayKey)}
                </span>
                {isToday && (
                  <span className="shrink-0 rounded-full bg-primary px-1.5 py-px text-[10px] font-bold text-on-primary">
                    היום
                  </span>
                )}
                {holiday && (
                  <span
                    className={cx(
                      'truncate type-caption',
                      isDayOff(holiday) ? 'font-bold text-warning-text' : 'text-ink-secondary',
                    )}
                  >
                    {holiday.name}
                  </span>
                )}
              </button>
              {/* a quiet day is one line, not a section — a week with four of
                  them shouldn't push the actual work off the screen */}
              {quiet && (
                <>
                  <span className="type-caption text-ink-tertiary">אין משימות</span>
                  {canCreate && (
                    <IconButton label={`משימה חדשה ל-${fmtDate(day.dayKey)}`} size="sm" bare onClick={() => onNewTask(day.dayKey)}>
                      <Plus size={ICON.sm} strokeWidth={STROKE} />
                    </IconButton>
                  )}
                </>
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
                          overdue={isOverdue(today)(row)}
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
  onOpen,
}: {
  row: WorkBoardRow
  tone: GroupTone | null
  overdue: boolean
  onOpen: (id: string) => void
}) {
  const label = row.end_client_name || row.title || row.customer_name || row.task_type_name
  const time = fmtTime(row.onsite_start_time) || fmtTime(row.warehouse_start_time)
  const team = [
    ...(row.workers ?? []).map((w) => w.name),
    ...(row.drivers ?? []).map((d) => d.name),
    ...(row.contractor_worker_list ?? []).map((w) => w.name),
  ]

  return (
    <div
      className={cx('flex items-stretch gap-1.5 px-2.5 py-1.5', overdue && 'bg-[var(--vl-board-overdue)]')}
      style={tone ? { background: tone.tint } : undefined}
    >
      <span
        aria-hidden
        className="w-1 shrink-0 rounded-full"
        style={{ background: tone?.solid ?? row.customer_color ?? 'var(--vl-border-strong)' }}
      />
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
            <span className="truncate">{shortAddress(row.location_text)}</span>
          </span>
        )}

        {/* every name, not a stack of initials: knowing who is on the job is
            the question this line exists to answer */}
        <span className="flex flex-wrap items-center gap-x-1.5 gap-y-0.5">
          {team.length > 0 ? (
            team.map((name) => (
              <span key={name} className="rounded bg-subtle px-1 type-caption text-ink-secondary">
                {name}
              </span>
            ))
          ) : (
            <span className="type-caption text-ink-tertiary">לא שובץ</span>
          )}
          {/* how many the job calls for — not how many of them are seated yet:
              the names right beside it are the answer to that */}
          {row.worker_count > 0 && (
            <span className="rounded bg-subtle px-1 type-caption font-bold tabular text-ink-secondary">
              {row.worker_count} עובדים
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
  groupKey,
  showCustomer,
  canOpenEvent,
  onOpen,
  onOpenEvent,
  onHover,
}: {
  row: WorkBoardRow
  groupKey: string
  /** the customer's identity is a permission; without it the header falls back */
  showCustomer: boolean
  canOpenEvent: boolean
  onOpen: (id: string) => void
  onOpenEvent: (eventId: string) => void
  onHover: (key: string | null) => void
}) {
  const label = showCustomer
    ? (row.customer_name ?? 'ללא לקוח')
    : row.end_client_name || row.title || row.task_type_name
  /* The fill is the customer's own colour, straight from settings, so a
     regular can find their customer's columns without reading a word. The
     label flips between near-black and white by the fill's luminance —
     `color-mix(…, black N%)` only holds over a tint, never over a solid. */
  const fill = (showCustomer && row.customer_color) || NEUTRAL
  /* A task with no event, or a reader who may not open one, opens no event —
     the second press still opens the task, which is the point of the name. */
  const eventId = canOpenEvent ? row.event_id : null

  /* One press goes to the event, two open the task. The first press has to
     wait out the window before it navigates: leaving for the event page on
     press one would unmount the board before press two ever arrived. */
  const pending = useRef<ReturnType<typeof setTimeout> | null>(null)
  useEffect(() => () => void (pending.current && clearTimeout(pending.current)), [])
  const onName = () => {
    if (pending.current) {
      clearTimeout(pending.current)
      pending.current = null
      onOpen(row.id)
      return
    }
    pending.current = setTimeout(() => {
      pending.current = null
      if (eventId) onOpenEvent(eventId)
    }, HEADER_CLICK_MS)
  }

  return (
    <div
      onMouseEnter={() => onHover(groupKey)}
      onMouseLeave={() => onHover(null)}
      className="group relative flex h-full items-center justify-center border-b border-line px-1.5"
      style={{ background: fill, color: readableOn(fill) }}
    >
      {/* nothing sits beside the name. The pencil that used to live here was a
          five-pixel target against the edge of a column the reader is dragging
          past, and every graze of it opened the task for editing — the name
          itself still opens it on a double press. */}
      <Tooltip content={eventId ? `${label} — לחיצה לאירוע, לחיצה כפולה למשימה` : `${label} — לחיצה כפולה למשימה`}>
        <button
          onClick={onName}
          className={cx(
            'min-w-0 max-w-full touch-manipulation truncate text-center type-caption font-bold',
            /* the underline promises the event page — without one to go to,
               the name is still pressable but promises nothing */
            eventId && 'hover:underline',
          )}
        >
          {label}
        </button>
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

/* ===== a day with nothing on it =========================================== */

function EmptyDayColumn({
  dayKey,
  canCreate,
  narrow,
  onNewTask,
  style,
}: {
  dayKey: string
  canCreate: boolean
  /** at the narrowest widths the words do not fit — the icon has to carry it */
  narrow: boolean
  onNewTask: (dayKey: string) => void
  style: React.CSSProperties
}) {
  return (
    <div
      className="absolute top-0 flex flex-col items-center justify-center gap-2 border-s border-line bg-subtle/40"
      style={style}
    >
      <CalendarDays size={narrow ? ICON.md : ICON.lg} className="text-ink-tertiary/60" strokeWidth={STROKE} />
      {!narrow && <span className="type-caption text-ink-tertiary">אין משימות</span>}
      {canCreate &&
        (narrow ? (
          <IconButton label={`משימה חדשה ל-${fmtDate(dayKey)}`} size="sm" onClick={() => onNewTask(dayKey)}>
            <Plus size={ICON.sm} strokeWidth={STROKE} />
          </IconButton>
        ) : (
          <Button size="sm" variant="ghost" onClick={() => onNewTask(dayKey)}>
            <Plus size={ICON.sm} strokeWidth={STROKE} />
            משימה
          </Button>
        ))}
    </div>
  )
}

/* ===== one task's column of field cells =================================== */

const TaskColumn = memo(
  function TaskColumn({
    row,
    canEditCell,
    patch,
    assign,
    lookups,
    fields,
    heights,
    tone,
    groupKey,
    active,
    onHover,
    style,
  }: {
    row: WorkBoardRow
    canEditCell: (perm?: string) => boolean
    patch: (row: WorkBoardRow, patch: Record<string, unknown>) => void
    assign: (row: WorkBoardRow, role: StaffRole, profileId: string, on: boolean) => void
    lookups: BoardLookups
    fields: typeof BOARD_FIELDS
    heights: number[]
    tone: GroupTone | null
    groupKey: string
    active: boolean
    onHover: (key: string | null) => void
    style: React.CSSProperties
  }) {
    /* A run of columns used to be bracketed by a dark line on each outer edge.
       It read as a frame around the group and cut the board into boxes, so the
       block is now held together by its fill alone — a heavier wash of the
       group's own hue, which is the same signal without the ruling. */
    return (
      <div
        onMouseEnter={() => onHover(groupKey)}
        onMouseLeave={() => onHover(null)}
        className="absolute top-0 bg-surface"
        style={{
          ...style,
          position: 'absolute',
          /* the same wash the header carries — a column whose body was paler
             than its own heading read as two different things stacked */
          ...(tone ? { background: active ? tone.tintStrong : tone.tint } : null),
        }}
      >
        {fields.map((f, i) => (
          <div
            key={f.key}
            className="flex items-center justify-center overflow-hidden border-b border-line-subtle transition-colors hover:bg-hover"
            style={{ height: heights[i] }}
          >
            {/* no scroller inside the cell: the row that needs the room — the
                team list — is measured to fit its longest crew, so everyone is
                on screen at once and the board grows instead of hiding them */}
            <div className="min-w-0 flex-1 text-center">
              {f.render({ row, canEdit: canEditCell(f.editPerm), can: canEditCell, patch, assign, lookups })}
            </div>
          </div>
        ))}
      </div>
    )
  },
  (a, b) =>
    a.row === b.row &&
    a.canEditCell === b.canEditCell &&
    a.assign === b.assign &&
    a.fields === b.fields &&
    a.heights === b.heights &&
    a.lookups === b.lookups &&
    a.tone === b.tone &&
    a.active === b.active &&
    a.style.insetInlineStart === b.style.insetInlineStart &&
    a.style.width === b.style.width,
)
