import { useCallback, useMemo, useRef, useState } from 'react'
import FullCalendar from '@fullcalendar/react'
import dayGridPlugin from '@fullcalendar/daygrid'
import listPlugin from '@fullcalendar/list'
import interactionPlugin from '@fullcalendar/interaction'
import heLocale from '@fullcalendar/core/locales/he'
import type { EventContentArg, EventDropArg } from '@fullcalendar/core'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import {
  CalendarDays,
  Check,
  ChevronDown,
  Copy,
  ExternalLink,
  Filter,
  ICON,
  LayoutGrid,
  List,
  MapPin,
  Plus,
  STROKE,
  Save,
  X,
} from '../../components/ui/icons'
import {
  Badge,
  Button,
  EmptyState,
  IconButton,
  Input,
  MenuItem,
  MenuLabel,
  Modal,
  PageHeader,
  Popover,
  Select,
  Switch,
  Tooltip,
  cx,
  useContextMenu,
  usePrompt,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { useCustomers, useStatuses } from '../../lib/queries'
import { fmtDate, toISODate } from '../../lib/dates'
import { KIND_LABEL, holidaysInRange, isDayOff } from '../../lib/hebrewHolidays'
import type { Holiday } from '../../lib/hebrewHolidays'
import { useIsMobile } from '../../lib/useMediaQuery'
import { useSwipeNav } from '../../lib/useSwipeNav'
import { EventFormModal } from '../events/EventFormModal'
import { NEUTRAL, chipPaint } from '../../lib/colors'
import type { SavedFilter } from '../../types/domain'
import { errorMessage } from '../../lib/errors'

/** The calendar shows *events* — the thing that is scheduled on a date. Their
 *  tasks (הקמה, פירוק, …) live on the work board, where a day's worth of
 *  operational detail has room to breathe. */
interface CalEvent {
  id: string
  event_date: string
  end_client_name: string | null
  event_number: string | null
  location_text: string | null
  volume_m: number | null
  truck_count: number | null
  notes: string | null
  no_parking: boolean
  porterage: boolean
  supplier_pickup: boolean
  customer_id: string
  status_id: string | null
  customers: { name: string; color: string } | null
  statuses: { name: string; color: string; code: string | null } | null
}

interface Filters {
  customer: string
  status: string
  q: string
  /** A cancelled event is still an event — it keeps its date and its history —
   *  but it is not work anyone is doing, so it stays out of the grid until
   *  asked for. The one filter that is on by *not* being set. */
  showCancelled: boolean
}

const emptyFilters: Filters = { customer: '', status: '', q: '', showCancelled: false }

const FILTER_LABELS: Record<keyof Filters, string> = {
  q: 'חיפוש',
  customer: 'לקוח',
  status: 'סטטוס',
  showCancelled: 'מבוטלים',
}

/** A saved filter may predate this screen (it once filtered tasks, by worker,
 *  contractor and task type). Keep only the keys that still mean something. */
function readSavedFilters(raw: Record<string, unknown>): Filters {
  const str = (v: unknown) => (typeof v === 'string' ? v : '')
  return {
    customer: str(raw.customer),
    status: str(raw.status),
    q: str(raw.q),
    showCancelled: raw.showCancelled === true,
  }
}

/** The status whose events the grid hides by default. Matched on `code` and
 *  not on the name, which the settings screen lets anyone rewrite. */
const CANCELLED = 'cancelled'

/* ── views ──────────────────────────────────────────────────────────────────
   The month grid is the calendar people mean when they say "לוח שנה", so it
   is what every screen size opens on. The other two stay one tap away — from
   the toolbar on a desktop, and from the "תצוגה" menu on a phone, where three
   more buttons in the toolbar cost a row the grid needs.                    */

type ViewKey = 'dayGridMonth' | 'dayGridWeek' | 'listMonth'

const VIEWS: { key: ViewKey; label: string; icon: typeof CalendarDays }[] = [
  { key: 'dayGridMonth', label: 'חודש', icon: CalendarDays },
  { key: 'dayGridWeek', label: 'שבוע', icon: LayoutGrid },
  { key: 'listMonth', label: 'סדר יום', icon: List },
]

export default function CalendarPage() {
  const qc = useQueryClient()
  const toast = useToast()
  const navigate = useNavigate()
  const { me, has, canCreateEvent } = useAuth()
  const { openMenu, menu } = useContextMenu()
  const { prompt, dialog: promptDialog } = usePrompt()
  const isMobile = useIsMobile()

  const [range, setRange] = useState<{ from: string; to: string } | null>(null)
  const [filters, setFilters] = useState<Filters>(emptyFilters)
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [eventModal, setEventModal] = useState(false)
  const [view, setView] = useState<ViewKey>('dayGridMonth')
  /** What the toolbar would have said — the phone draws it itself now. */
  const [nav, setNav] = useState<{ title: string; showsToday: boolean }>({ title: '', showsToday: true })
  const calRef = useRef<FullCalendar>(null)

  const changeView = useCallback((next: ViewKey) => {
    calRef.current?.getApi().changeView(next)
    setView(next)
  }, [])

  /* ── swiping the grid ───────────────────────────────────────────────────
     A phone has no room for a row of navigation buttons over a month that is
     already fighting for every pixel, so the grid itself is the control: drag
     it right for the next period, left for the previous one — the direction
     the page reads in, with the grid following the finger the whole way. A
     drag that starts on an event belongs to the event (that is how it is
     moved to another day), and a drag that is mostly vertical belongs to the
     page's scroll.                                                          */

  const {
    surfaceRef: swipeRef,
    trackStyle,
    active: swiping,
    swipeHandlers,
  } = useSwipeNav({
    onNext: useCallback(() => calRef.current?.getApi().next(), []),
    onPrev: useCallback(() => calRef.current?.getApi().prev(), []),
    enabled: isMobile,
    pointers: 'touch',
    ignore: '.fc-event, .fc-popover, button, a, input, select',
  })

  // dragging an event rewrites events.event_date, which the column trigger
  // judges against events.change_date — gate the UI by the same key
  const canEdit = has(PERM.CALENDAR_DRAG)

  const { data: customers = [] } = useCustomers()
  const { data: statuses = [] } = useStatuses('event')

  const { data: events = [], isFetching } = useQuery({
    queryKey: ['calendar', 'events', range],
    enabled: !!range,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('events')
        .select(
          'id, event_date, end_client_name, event_number, location_text, volume_m, truck_count, notes, no_parking, porterage, supplier_pickup, customer_id, status_id, customers(name, color), statuses(name, color, code)',
        )
        .gte('event_date', range!.from)
        .lte('event_date', range!.to)
        .is('deleted_at', null)
      if (error) throw error
      return data as unknown as CalEvent[]
    },
  })

  const statusById = useMemo(() => new Map(statuses.map((s) => [s.id, s])), [statuses])
  const cancelledStatus = useMemo(() => statuses.find((s) => s.code === CANCELLED), [statuses])

  const filtered = useMemo(() => {
    return events.filter((e) => {
      // an explicit "status: בוטל" filter outranks the toggle — asking for the
      // cancelled ones by name is asking to see them
      if (!filters.showCancelled && filters.status !== cancelledStatus?.id) {
        if (e.statuses?.code === CANCELLED) return false
      }
      if (filters.customer && e.customer_id !== filters.customer) return false
      if (filters.status && e.status_id !== filters.status) return false
      if (filters.q) {
        const hay = [e.end_client_name, e.event_number, e.location_text, e.customers?.name, e.notes]
          .filter(Boolean)
          .join(' ')
        if (!hay.includes(filters.q)) return false
      }
      return true
    })
  }, [events, filters, cancelledStatus])

  const eventChips = useMemo(
    () =>
      filtered.map((e) => {
        const label = e.end_client_name || e.customers?.name || 'אירוע'
        return {
          id: e.id,
          title: label,
          start: e.event_date,
          allDay: true,
          extendedProps: { event: e, label, holidayRank: 1 },
        }
      }),
    [filtered],
  )

  /* ── חגים ומועדים ────────────────────────────────────────────────────────
     מחושבים מקומית לטווח שהתצוגה ביקשה, ולכן הם שם עוד לפני שהאירועים
     חוזרים מהשרת. כצ׳יפים ולא כרקע של התא: כך אותו מועד נראה גם בחודש, גם
     בשבוע וגם בסדר היום, ובלי הנחות על ה-DOM הפנימי של FullCalendar.      */

  const holidays = useMemo(
    () => (range ? holidaysInRange(range.from, range.to) : new Map<string, Holiday>()),
    [range],
  )

  const holidayChips = useMemo(
    () =>
      [...holidays.values()].map((h) => ({
        id: `holiday:${h.date}`,
        title: h.name,
        start: h.date,
        allDay: true,
        // חג אינו אירוע שאפשר לגרור ליום אחר
        editable: false,
        startEditable: false,
        durationEditable: false,
        extendedProps: { holiday: h, holidayRank: 0 },
      })),
    [holidays],
  )

  /** החג ראשון בכל יום — הוא ההקשר שכל השאר נקרא בתוכו */
  const calEvents = useMemo(() => [...holidayChips, ...eventChips], [holidayChips, eventChips])

  /** The key to the grid's colours: every status, whether or not the range
   *  happens to hold one, because a legend that appears and disappears is not
   *  a legend. The count next to each is what the range does hold. */
  const statusLegend = useMemo(() => {
    const counts = new Map<string, number>()
    for (const e of filtered) if (e.status_id) counts.set(e.status_id, (counts.get(e.status_id) ?? 0) + 1)
    return statuses.map((s) => ({ ...s, count: counts.get(s.id) ?? 0 }))
  }, [filtered, statuses])

  /** Customers present in the current view — doubles as a colour legend. */
  const legend = useMemo(() => {
    const seen = new Map<string, { name: string; color: string; count: number }>()
    for (const e of filtered) {
      if (!e.customers) continue
      const key = e.customer_id ?? e.customers.name
      const hit = seen.get(key)
      if (hit) hit.count++
      else seen.set(key, { name: e.customers.name, color: e.customers.color, count: 1 })
    }
    return [...seen.entries()].sort((a, b) => b[1].count - a[1].count).slice(0, 8)
  }, [filtered])

  /* ── the calendar's only write path: dragging an event to another day ──── */

  const moveEvent = useMutation({
    /**
     * Through the RPC rather than straight at the table. `events_update` is
     * staff-only since 0014 — the RPC is the only path that runs the customer's
     * form config — so a direct write here would mean the drag handle works for
     * some people and silently fails for others. The patch carries one key, and
     * both `validate_event_payload` and `apply_event_task_block` only act on
     * the keys they are given, so nothing else on the event moves with it. The
     * column trigger still runs, so `events.change_date` is still required.
     */
    mutationFn: async ({ id, date }: { id: string; date: string; undo?: string; message?: string }) => {
      const { error } = await supabase.rpc('update_event', {
        p_event_id: id,
        payload: { event_date: date },
      })
      if (error) throw error
    },
    onSuccess: (_d, vars) => {
      toast.success(vars.message ?? 'האירוע עודכן', {
        undo: vars.undo
          ? () => moveEvent.mutate({ id: vars.id, date: vars.undo!, message: 'השינוי בוטל' })
          : undefined,
      })
      void qc.invalidateQueries({ queryKey: ['calendar'] })
      void qc.invalidateQueries({ queryKey: ['events'] })
    },
    onError: (e) => {
      toast.error(errorMessage(e))
      void qc.invalidateQueries({ queryKey: ['calendar'] })
    },
  })

  const onDrop = useCallback(
    (arg: EventDropArg) => {
      if (!canEdit) {
        arg.revert()
        toast.warning('אין לך הרשאה לשנות אירועים')
        return
      }
      const d = arg.event.start
      if (!d) return
      const ev = arg.event.extendedProps.event as CalEvent
      const date = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
      moveEvent.mutate({ id: arg.event.id, date, undo: ev.event_date, message: `הועבר ל-${fmtDate(date)}` })
    },
    [canEdit, moveEvent, toast],
  )

  /* ── saved filters ────────────────────────────────────────────────────── */

  const { data: savedFilters = [] } = useQuery({
    queryKey: ['saved_filters', 'calendar'],
    enabled: !!me,
    queryFn: async () => {
      const { data, error } = await supabase.from('saved_filters').select('*').eq('screen', 'calendar').order('name')
      if (error) throw error
      return data as SavedFilter[]
    },
  })

  const saveFilter = async () => {
    const name = await prompt('שם הפילטר', '', {
      title: 'שמירת סינון נוכחי',
      placeholder: 'למשל: אירועי אלפא שאושרו',
    })
    if (!name || !me) return
    const { error } = await supabase.from('saved_filters').insert({ profile_id: me.profile.id, screen: 'calendar', name, filters })
    if (error) toast.error(error.message)
    else {
      toast.success('הסינון נשמר')
      void qc.invalidateQueries({ queryKey: ['saved_filters'] })
    }
  }

  const activeFilters = (Object.keys(filters) as (keyof Filters)[]).filter((k) => filters[k])
  const clearFilter = (k: keyof Filters) =>
    setFilters((f) => ({ ...f, [k]: k === 'showCancelled' ? false : '' }))

  const filterValueLabel = (k: keyof Filters): string => {
    if (k === 'showCancelled') return 'מוצגים'
    const v = filters[k]
    if (k === 'q') return v
    if (k === 'customer') return customers.find((c) => c.id === v)?.name ?? v
    return statusById.get(v)?.name ?? v
  }

  /* ── event rendering ──────────────────────────────────────────────────── */

  const renderEvent = useCallback(
    (arg: EventContentArg) => {
      const holiday = arg.event.extendedProps.holiday as Holiday | undefined
      if (holiday) {
        /* בלי מילוי מלא גם כשזה שבתון: הצבע של הצ׳יפים שייך לסטטוסים, וחג
           שנצבע כמותם היה נקרא כאירוע. הרקע של היום עצמו נושא את המשקל. */
        return (
          <span
            className={cx(
              'flex min-w-0 items-center gap-1 rounded px-1 py-px type-caption',
              'vl-holiday-chip',
              isDayOff(holiday) && 'font-bold',
            )}
            title={`${holiday.name} — ${KIND_LABEL[holiday.kind]}`}
          >
            <span aria-hidden className="vl-holiday-dot" />
            <span className="truncate">{holiday.name}</span>
          </span>
        )
      }
      const ev = arg.event.extendedProps.event as CalEvent | undefined
      if (!ev) return <span className="truncate px-1">{arg.event.title}</span>
      const label = arg.event.extendedProps.label as string
      const list = arg.view.type.startsWith('list')
      const status = ev.statuses
      /* The chip is painted by *status*, not by customer. On a phone the chip
         is nine pixels of text — a border or a dot at that size is decoration,
         while the fill is the only thing that reads across a whole month. The
         customer keeps a dot at the leading edge, and only where there is more
         than one customer to tell apart. */
      const paint = chipPaint(status?.color ?? ev.customers?.color)
      const cancelled = status?.code === CANCELLED
      const showCustomerDot = customers.length > 1 && !!ev.customers

      const contextItems = [
        {
          key: 'open',
          label: 'פתיחת האירוע',
          icon: <ExternalLink size={ICON.sm} />,
          onClick: () => navigate(`/events/${ev.id}`),
        },
        {
          key: 'filter',
          label: `סינון לפי ${ev.customers?.name ?? 'לקוח'}`,
          icon: <Filter size={ICON.sm} />,
          disabled: !ev.customer_id,
          onClick: () => setFilters((f) => ({ ...f, customer: ev.customer_id ?? '' })),
        },
        {
          key: 'copy',
          label: 'העתקת פרטי האירוע',
          icon: <Copy size={ICON.sm} />,
          onClick: () => {
            const text = [
              label,
              ev.customers?.name,
              fmtDate(ev.event_date),
              ev.event_number && `אירוע #${ev.event_number}`,
              ev.location_text,
              ev.truck_count != null ? `${ev.truck_count} משאיות` : null,
            ]
              .filter(Boolean)
              .join(' · ')
            void navigator.clipboard?.writeText(text).then(
              () => toast.success('הפרטים הועתקו'),
              () => toast.error('ההעתקה נכשלה'),
            )
          },
        },
      ]

      if (list) {
        return (
          <span
            className="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1"
            onContextMenu={(e) => openMenu(e, contextItems)}
          >
            {/* same key as the grid: the dot is the status, not the customer */}
            <span
              className="size-2 shrink-0 rounded-full"
              style={{ background: status?.color ?? ev.customers?.color ?? NEUTRAL }}
            />
            <span className={cx('truncate font-medium', cancelled && 'line-through opacity-70')}>{label}</span>
            {ev.customers && <span className="truncate type-caption text-ink-tertiary">{ev.customers.name}</span>}
            {ev.location_text && (
              <span className="inline-flex min-w-0 items-center gap-0.5 type-caption text-ink-tertiary">
                <MapPin size={ICON.xs} className="shrink-0" />
                <span className="truncate">{ev.location_text}</span>
              </span>
            )}
            {status && <Badge color={status.color}>{status.name}</Badge>}
          </span>
        )
      }

      return (
        <Tooltip
          placement="bottom"
          content={
            <span className="block space-y-1 py-0.5">
              <span className="block font-bold">{label}</span>
              {ev.customers && <span className="block opacity-90">{ev.customers.name}</span>}
              {ev.location_text && <span className="block opacity-80">📍 {ev.location_text}</span>}
              {ev.truck_count != null && <span className="block opacity-80">🚚 {ev.truck_count} משאיות</span>}
              {ev.volume_m != null && <span className="block opacity-80">נפח {ev.volume_m}</span>}
              {status && <span className="block opacity-80">● {status.name}</span>}
              {ev.event_number && <span className="block opacity-60">#{ev.event_number}</span>}
            </span>
          }
        >
          <span
            onContextMenu={(e) => openMenu(e, contextItems)}
            className={cx(
              // `vl-cal-chip` is the handle the day popover styles itself by:
              // inside it the chip is a row you read, not a marker in a 50px cell
              'vl-cal-chip group/ev relative flex h-full min-w-0 items-center gap-1 overflow-hidden rounded-md shadow-xs',
              'transition-[filter,box-shadow] duration-150 hover:shadow-md hover:brightness-105',
              // every pixel of a phone's month cell belongs to the name: the
              // chip shrinks to a marker so two or three of them fit a cell
              isMobile ? 'px-1 py-0.5 max-sm:rounded-sm max-sm:px-0.5 max-sm:py-0' : 'px-1.5 py-1',
              // a cancelled event is shown only when asked for, and when it is
              // shown it must never be mistaken for live work
              cancelled && 'opacity-60 saturate-50',
            )}
            style={{ background: paint.background, color: paint.color }}
          >
            {!isMobile && (
              <span
                aria-hidden
                className="absolute inset-y-0 start-0 w-1 rounded-s-md"
                style={{ background: paint.railColor }}
              />
            )}
            {showCustomerDot && (
              <span
                aria-hidden
                className={cx('size-1.5 shrink-0 rounded-full ring-1 ring-white/40', !isMobile && 'ms-1')}
                style={{ background: ev.customers!.color }}
                title={ev.customers!.name}
              />
            )}
            <span
              className={cx(
                'min-w-0 flex-1 truncate type-caption font-semibold',
                isMobile ? 'max-sm:text-[0.5625rem] max-sm:leading-[0.9375rem]' : !showCustomerDot && 'ps-1',
                cancelled && 'line-through',
              )}
            >
              {label}
            </span>
            {/* a month cell on a phone is ~50px wide — the name has to win it */}
            {!isMobile && ev.truck_count != null && ev.truck_count > 0 && (
              <span className="shrink-0 type-caption font-bold tabular opacity-90">{ev.truck_count}🚚</span>
            )}
            {/* no status dot: the chip itself is the status colour now */}
          </span>
        </Tooltip>
      )
    },
    [openMenu, navigate, toast, isMobile, customers.length],
  )

  /* ── filter controls, shared by the desktop panel and the mobile sheet ─── */

  const filterControls = (
    <>
      <Input
        placeholder="חיפוש חופשי..."
        inputSize="sm"
        value={filters.q}
        onChange={(e) => setFilters((f) => ({ ...f, q: e.target.value }))}
        aria-label="חיפוש אירועים"
      />
      {/* `customers_select` already scoped the list, so a filter over one
          option can only offer the filter you are already in */}
      {customers.length > 1 && (
        <Select
          selectSize="sm"
          value={filters.customer}
          onChange={(e) => setFilters((f) => ({ ...f, customer: e.target.value }))}
          aria-label="לקוח"
        >
          <option value="">כל הלקוחות</option>
          {customers.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </Select>
      )}
      <Select
        selectSize="sm"
        value={filters.status}
        onChange={(e) => setFilters((f) => ({ ...f, status: e.target.value }))}
        aria-label="סטטוס"
      >
        <option value="">כל הסטטוסים</option>
        {statuses.map((s) => (
          <option key={s.id} value={s.id}>
            {s.name}
          </option>
        ))}
      </Select>
      {cancelledStatus && (
        <div className="flex items-center sm:col-span-2 lg:col-span-1">
          <Switch
            checked={filters.showCancelled}
            onChange={(v) => setFilters((f) => ({ ...f, showCancelled: v }))}
            label={`הצגת אירועים בסטטוס "${cancelledStatus.name}"`}
          />
        </div>
      )}
      {savedFilters.length > 0 && (
        <Select
          selectSize="sm"
          value=""
          aria-label="פילטרים שמורים"
          onChange={(e) => {
            const f = savedFilters.find((s) => s.id === e.target.value)
            if (f) setFilters(readSavedFilters(f.filters))
          }}
        >
          <option value="">פילטרים שמורים...</option>
          {savedFilters.map((f) => (
            <option key={f.id} value={f.id}>
              {f.name}
            </option>
          ))}
        </Select>
      )}
    </>
  )

  /* ── the header, minus its title on a phone ─────────────────────────────
     The bottom bar already says "לוח שנה" and the screen is unmistakably a
     calendar, so on a phone the title and its event count are two rows of
     glass between the toolbar and the grid. The actions and the active-filter
     chips stay — those are controls, not labels. */

  const headerActions = (
    <>
      {/* on a phone the three view buttons would take a toolbar row of
          their own — they fold into a menu next to "סינון" instead */}
      {isMobile && (
        <Popover
          trigger={({ toggle, ...aria }) => (
            <Button size="sm" variant="secondary" onClick={toggle} {...aria}>
              <CalendarDays size={ICON.sm} strokeWidth={STROKE} />
              {VIEWS.find((v) => v.key === view)?.label ?? 'תצוגה'}
              <ChevronDown size={ICON.sm} strokeWidth={STROKE} />
            </Button>
          )}
        >
          {(close) => (
            <>
              <MenuLabel>תצוגה</MenuLabel>
              {VIEWS.map((v) => (
                <MenuItem
                  key={v.key}
                  icon={<v.icon size={ICON.sm} />}
                  shortcut={view === v.key ? <Check size={ICON.sm} /> : undefined}
                  onClick={() => {
                    changeView(v.key)
                    close()
                  }}
                >
                  {v.label}
                </MenuItem>
              ))}
            </>
          )}
        </Popover>
      )}
      <Button
        size="sm"
        variant={activeFilters.length > 0 ? 'outlined' : 'secondary'}
        onClick={() => setFiltersOpen((v) => !v)}
        aria-expanded={filtersOpen}
      >
        <Filter size={ICON.sm} strokeWidth={STROKE} />
        סינון
        {activeFilters.length > 0 && (
          <span className="inline-flex size-4 items-center justify-center rounded-full bg-primary type-caption font-bold tabular text-on-primary">
            {activeFilters.length}
          </span>
        )}
      </Button>
      {has(PERM.CALENDAR_SAVE_FILTERS) && (
        <IconButton
          label="שמירת הסינון הנוכחי"
          size="sm"
          onClick={() => void saveFilter()}
          disabled={activeFilters.length === 0}
        >
          <Save size={ICON.md} strokeWidth={STROKE} />
        </IconButton>
      )}
      {canCreateEvent() && (
        <Button size="sm" variant="primary" onClick={() => setEventModal(true)}>
          <Plus size={ICON.sm} strokeWidth={STROKE} />
          אירוע חדש
        </Button>
      )}
    </>
  )

  const headerExtras = (
    <>
      {/* active-filter chips stay visible even when the panel is folded */}
      {activeFilters.length > 0 && (
        <div className="scroll-row gap-1.5 sm:flex-wrap">
          {activeFilters.map((k) => (
            <span
              key={k}
              className="scroll-row-item inline-flex items-center gap-1 rounded-full border border-primary-border bg-primary-subtle py-0.5 pe-1 ps-2 type-caption font-medium text-primary-text"
            >
              <span className="opacity-70">{FILTER_LABELS[k]}:</span>
              <span className="max-w-40 truncate">{filterValueLabel(k)}</span>
              <button
                onClick={() => clearFilter(k)}
                aria-label={`הסרת סינון ${FILTER_LABELS[k]}`}
                className="rounded-full p-0.5 opacity-60 transition-opacity hover:opacity-100"
              >
                <X size={11} />
              </button>
            </span>
          ))}
          <button
            onClick={() => setFilters(emptyFilters)}
            className="scroll-row-item rounded-md px-2 py-0.5 type-caption text-ink-tertiary transition-colors hover:bg-hover hover:text-ink"
          >
            ניקוי הכל
          </button>
        </div>
      )}

      {/* on desktop the panel unfolds in place; on mobile it becomes a dialog
          so it can never push the calendar off the bottom of the screen */}
      {filtersOpen && !isMobile && (
        <div className="surface grid animate-slide-up gap-2 p-3 sm:grid-cols-2 lg:grid-cols-4">{filterControls}</div>
      )}
    </>
  )

  return (
    /* the month grid is the tallest thing this app scrolls, and the bottom bar
       floats over it — the page keeps its own clearance so the last week row
       (and the legend under it) can always be scrolled clear of the bar */
    <div className="space-y-4 max-lg:pb-shell">
      {promptDialog}
      {menu}

      {isMobile ? (
        <div className="space-y-3">
          <div className="flex w-full flex-wrap items-center gap-2">{headerActions}</div>
          {headerExtras}
        </div>
      ) : (
        <PageHeader
          title="לוח שנה"
          subtitle={range ? `${filtered.length} אירועים בטווח המוצג` : 'טוען...'}
          actions={headerActions}
        >
          {headerExtras}
        </PageHeader>
      )}

      <Modal
        open={filtersOpen && isMobile}
        onClose={() => setFiltersOpen(false)}
        title="סינון אירועים"
        description={`${filtered.length} אירועים מוצגים`}
        footer={
          <>
            <Button onClick={() => setFilters(emptyFilters)} disabled={activeFilters.length === 0}>
              ניקוי
            </Button>
            <Button variant="primary" onClick={() => setFiltersOpen(false)}>
              הצגה
            </Button>
          </>
        }
      >
        <div className="grid gap-3">{filterControls}</div>
      </Modal>

      {/* not `overflow-hidden`: the day's popover ("+2") is portalled inside
          this card and a day in the last row would have it clipped away */}
      <div ref={swipeRef} className="vl-calendar surface relative p-2 sm:p-3 touch-pan-y" {...swipeHandlers}>
        {/* thin top progress line instead of a spinner that blanks the grid */}
        <div
          aria-hidden
          className={cx(
            'pointer-events-none absolute inset-x-3 top-0 h-0.5 rounded-b-full bg-primary transition-opacity duration-200',
            isFetching ? 'animate-shimmer opacity-100' : 'opacity-0',
          )}
        />
        {/* the phone's toolbar: the period's name, and nothing else — moving
            between periods is the swipe. "היום" is the one jump a swipe cannot
            make in one gesture, so it appears only once you have swiped away
            from the period today is in, and leaves again when you are back. */}
        {isMobile && (
          <div className="mb-2 flex items-center justify-center gap-2 px-1">
            <h2 className="truncate type-title font-bold">{nav.title}</h2>
            {!nav.showsToday && (
              <button
                onClick={() => calRef.current?.getApi().today()}
                className="shrink-0 rounded-full border border-line px-2.5 py-0.5 type-caption font-medium text-primary-text transition-colors hover:bg-hover"
              >
                היום
              </button>
            )}
          </div>
        )}
        {/* the clip is only on while the grid is off its mark: with it on for
            good, a day's "+2" popover in the last row would be cut away */}
        <div className={cx(swiping && 'overflow-hidden')}>
          <div style={trackStyle}>
            <FullCalendar
              ref={calRef}
              plugins={[dayGridPlugin, listPlugin, interactionPlugin]}
              initialView="dayGridMonth"
              // on a phone the grid carries its own title above, and the swipe
              // replaces prev/next — the toolbar is a row the month can have back
              headerToolbar={
                isMobile
                  ? false
                  : {
                      start: 'prev,next today',
                      center: 'title',
                      end: 'dayGridMonth,dayGridWeek,listMonth',
                    }
              }
              buttonText={{ month: 'חודש', week: 'שבוע', day: 'יום', list: 'סדר יום', today: 'היום' }}
              locale={heLocale}
              direction="rtl"
              height="auto"
              editable={canEdit}
              eventStartEditable={canEdit}
              eventDurationEditable={false}
              events={calEvents}
              eventContent={renderEvent}
              eventDrop={onDrop}
              datesSet={(info) => {
                setRange({ from: info.startStr.slice(0, 10), to: info.endStr.slice(0, 10) })
                setView(info.view.type as ViewKey)
                const now = new Date()
                // the *period* the view is on (the month, the week), not the grid's
                // visible days — a month grid also shows a few of its neighbours'
                setNav({
                  title: info.view.title,
                  showsToday: now >= info.view.currentStart && now < info.view.currentEnd,
                })
              }}
              eventClick={(info) => {
                // חג הוא תווית, לא יעד
                if (info.event.extendedProps.holiday) return
                navigate(`/events/${info.event.id}`)
              }}
              /* החג פותח את היום; אחריו האירועים בסדר הרגיל */
              eventOrder="holidayRank,start,-duration,allDay,title"
              /* היום עצמו נצבע, כדי שגם כשהצ׳יפ נבלע ב-"+3" עדיין רואים
                 שזה יום שאי אפשר לתכנן עליו עבודה */
              dayCellClassNames={(arg) => {
                const h = holidays.get(toISODate(arg.date))
                if (!h) return []
                return isDayOff(h) ? ['vl-holiday-day', 'vl-holiday-day-off'] : ['vl-holiday-day']
              }}
              /* events, not rows: a cell shows three of them and says how many it
                 is holding back, rather than spending one of the three saying it */
              dayMaxEvents={isMobile ? 3 : 4}
              /* "+2" and nothing else — "עוד 2" costs half the width of a cell on
                 a phone, and the number is the whole message */
              moreLinkContent={(arg) => `+${arg.num}`}
              moreLinkHint={(n) => `עוד ${n} אירועים ביום הזה`}
              /* the link opens the day itself: every event it has, in a panel over
                 the grid, each one still a tap away from its own screen */
              moreLinkClick="popover"
              dayPopoverFormat={{ weekday: 'long', day: 'numeric', month: 'long' }}
              noEventsContent={() => <EmptyState compact art="calendar" title="אין אירועים בטווח הזה" />}
            />
          </div>
        </div>
      </div>

      {/* the key to the grid's colours. Each entry is also the filter for its
          own status, and the cancelled one carries the toggle that reveals it
          — it is where you look when you wonder where a cancelled event went */}
      {statusLegend.length > 0 && (
        <div className="scroll-row gap-x-1 gap-y-1.5 px-1 sm:flex-wrap sm:gap-x-2">
          <span className="scroll-row-item type-overline pe-1">סטטוס</span>
          {statusLegend.map((s) => {
            const isCancelled = s.code === CANCELLED
            const hidden = isCancelled && !filters.showCancelled && filters.status !== s.id
            const active = filters.status === s.id
            return (
              <button
                key={s.id}
                onClick={() => setFilters((f) => ({ ...f, status: f.status === s.id ? '' : s.id }))}
                aria-pressed={active}
                className={cx(
                  'scroll-row-item inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 type-caption transition-colors',
                  active ? 'bg-selected font-semibold text-ink' : 'text-ink-secondary hover:bg-hover',
                  hidden && 'opacity-50',
                )}
              >
                <span
                  className="size-2.5 shrink-0 rounded-sm"
                  style={{ background: s.color, opacity: hidden ? 0.5 : 1 }}
                />
                <span className={cx(hidden && 'line-through')}>{s.name}</span>
                {!hidden && <span className="tabular text-ink-tertiary">{s.count}</span>}
              </button>
            )
          })}
          {cancelledStatus && (
            <button
              onClick={() => setFilters((f) => ({ ...f, showCancelled: !f.showCancelled }))}
              className="scroll-row-item rounded-md px-2 py-0.5 type-caption text-primary-text transition-colors hover:bg-hover"
            >
              {filters.showCancelled ? 'הסתרת מבוטלים' : 'הצגת מבוטלים'}
            </button>
          )}
        </div>
      )}

      {/* a legend of one is not a legend — it just names the company you are
          already inside, which is what a client sees once RLS has scoped the rows */}
      {legend.length > 1 && (
        <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5 px-1">
          <span className="type-overline">לקוחות בתצוגה</span>
          {/* the customer's colour is the dot on the chip, not its fill */}
          {legend.map(([id, c]) => (
            <button
              key={id}
              onClick={() => setFilters((f) => ({ ...f, customer: f.customer === id ? '' : id }))}
              className={cx(
                'inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 type-caption transition-colors',
                filters.customer === id ? 'bg-selected font-semibold text-ink' : 'text-ink-secondary hover:bg-hover',
              )}
            >
              <span className="size-2 shrink-0 rounded-full" style={{ background: c.color }} />
              {c.name}
              <span className="tabular text-ink-tertiary">{c.count}</span>
            </button>
          ))}
        </div>
      )}

      <EventFormModal open={eventModal} onClose={() => setEventModal(false)} />
    </div>
  )
}
