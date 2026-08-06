import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import FullCalendar from '@fullcalendar/react'
import dayGridPlugin from '@fullcalendar/daygrid'
import listPlugin from '@fullcalendar/list'
import interactionPlugin from '@fullcalendar/interaction'
import heLocale from '@fullcalendar/core/locales/he'
import type { EventContentArg, EventDropArg } from '@fullcalendar/core'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { Copy, ExternalLink, Filter, ICON, MapPin, Plus, STROKE, Save, X } from '../../components/ui/icons'
import {
  Badge,
  Button,
  EmptyState,
  IconButton,
  Input,
  Modal,
  PageHeader,
  Select,
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
import { fmtDate } from '../../lib/dates'
import { useIsMobile } from '../../lib/useMediaQuery'
import { EventFormModal } from '../events/EventFormModal'
import { chipPaint } from './eventColors'
import type { SavedFilter } from '../../types/domain'

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
  statuses: { name: string; color: string } | null
}

interface Filters {
  customer: string
  status: string
  q: string
}

const emptyFilters: Filters = { customer: '', status: '', q: '' }

const FILTER_LABELS: Record<keyof Filters, string> = {
  q: 'חיפוש',
  customer: 'לקוח',
  status: 'סטטוס',
}

/** A saved filter may predate this screen (it once filtered tasks, by worker,
 *  contractor and task type). Keep only the keys that still mean something. */
function readSavedFilters(raw: Record<string, unknown>): Filters {
  const str = (v: unknown) => (typeof v === 'string' ? v : '')
  return { customer: str(raw.customer), status: str(raw.status), q: str(raw.q) }
}

export default function CalendarPage() {
  const qc = useQueryClient()
  const toast = useToast()
  const navigate = useNavigate()
  const { me, has } = useAuth()
  const { openMenu, menu } = useContextMenu()
  const { prompt, dialog: promptDialog } = usePrompt()
  const isMobile = useIsMobile()

  const [range, setRange] = useState<{ from: string; to: string } | null>(null)
  const [filters, setFilters] = useState<Filters>(emptyFilters)
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [eventModal, setEventModal] = useState(false)
  const calRef = useRef<FullCalendar>(null)

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
          'id, event_date, end_client_name, event_number, location_text, volume_m, truck_count, notes, no_parking, porterage, supplier_pickup, customer_id, status_id, customers(name, color), statuses(name, color)',
        )
        .gte('event_date', range!.from)
        .lte('event_date', range!.to)
        .is('deleted_at', null)
      if (error) throw error
      return data as unknown as CalEvent[]
    },
  })

  const statusById = useMemo(() => new Map(statuses.map((s) => [s.id, s])), [statuses])

  const filtered = useMemo(() => {
    return events.filter((e) => {
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
  }, [events, filters])

  const calEvents = useMemo(
    () =>
      filtered.map((e) => {
        const label = e.end_client_name || e.customers?.name || 'אירוע'
        return {
          id: e.id,
          title: label,
          start: e.event_date,
          allDay: true,
          extendedProps: { event: e, label },
        }
      }),
    [filtered],
  )

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
    mutationFn: async ({ id, date }: { id: string; date: string; undo?: string; message?: string }) => {
      const { error } = await supabase.from('events').update({ event_date: date }).eq('id', id)
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
      toast.error((e as Error).message)
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
  const clearFilter = (k: keyof Filters) => setFilters((f) => ({ ...f, [k]: '' }))

  const filterValueLabel = (k: keyof Filters): string => {
    const v = filters[k]
    if (k === 'q') return v
    if (k === 'customer') return customers.find((c) => c.id === v)?.name ?? v
    return statusById.get(v)?.name ?? v
  }

  /* ── views ────────────────────────────────────────────────────────────────
     A phone can't show a readable month grid *and* the event's details, so it
     opens on the agenda list and keeps the month one tap away.              */

  useEffect(() => {
    const api = calRef.current?.getApi()
    if (!api) return
    const wanted = isMobile ? 'listMonth' : 'dayGridMonth'
    const current = api.view.type
    // only steer the view when crossing the breakpoint, never on every render
    if (isMobile && current === 'dayGridMonth') api.changeView(wanted)
    else if (!isMobile && current === 'listMonth') api.changeView(wanted)
  }, [isMobile])

  /* ── event rendering ──────────────────────────────────────────────────── */

  const renderEvent = useCallback(
    (arg: EventContentArg) => {
      const ev = arg.event.extendedProps.event as CalEvent | undefined
      if (!ev) return <span className="truncate px-1">{arg.event.title}</span>
      const label = arg.event.extendedProps.label as string
      const paint = chipPaint(ev.customers?.color)
      const list = arg.view.type.startsWith('list')
      const status = ev.statuses

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
            <span className="size-2 shrink-0 rounded-full" style={{ background: ev.customers?.color ?? '#64748b' }} />
            <span className="truncate font-medium">{label}</span>
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
              'group/ev relative flex h-full min-w-0 items-center gap-1 overflow-hidden rounded-md py-1 shadow-xs',
              'transition-[filter,box-shadow] duration-150 hover:shadow-md hover:brightness-105',
              // every pixel of a phone's month cell belongs to the name
              isMobile ? 'px-1' : 'px-1.5',
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
            <span className={cx('min-w-0 flex-1 truncate type-caption font-semibold', !isMobile && 'ps-1')}>
              {label}
            </span>
            {/* a month cell on a phone is ~50px wide — the name has to win it */}
            {!isMobile && ev.truck_count != null && ev.truck_count > 0 && (
              <span className="shrink-0 type-caption font-bold tabular opacity-90">{ev.truck_count}🚚</span>
            )}
            {!isMobile && status && (
              <span
                className="size-1.5 shrink-0 rounded-full ring-1 ring-white/40"
                style={{ background: status.color }}
                title={status.name}
              />
            )}
          </span>
        </Tooltip>
      )
    },
    [openMenu, navigate, toast, isMobile],
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

  return (
    <div className="space-y-4">
      {promptDialog}
      {menu}

      <PageHeader
        title="לוח שנה"
        subtitle={range ? `${filtered.length} אירועים בטווח המוצג` : 'טוען...'}
        actions={
          <>
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
            <IconButton
              label="שמירת הסינון הנוכחי"
              size="sm"
              onClick={() => void saveFilter()}
              disabled={activeFilters.length === 0}
            >
              <Save size={ICON.md} strokeWidth={STROKE} />
            </IconButton>
            {has(PERM.EVENTS_CREATE) && (
              <Button size="sm" variant="primary" onClick={() => setEventModal(true)}>
                <Plus size={ICON.sm} strokeWidth={STROKE} />
                אירוע חדש
              </Button>
            )}
          </>
        }
      >
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
      </PageHeader>

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

      <div className="vl-calendar surface relative overflow-hidden p-2 sm:p-3">
        {/* thin top progress line instead of a spinner that blanks the grid */}
        <div
          aria-hidden
          className={cx(
            'pointer-events-none absolute inset-x-0 top-0 h-0.5 bg-primary transition-opacity duration-200',
            isFetching ? 'animate-shimmer opacity-100' : 'opacity-0',
          )}
        />
        <FullCalendar
          ref={calRef}
          plugins={[dayGridPlugin, listPlugin, interactionPlugin]}
          initialView={isMobile ? 'listMonth' : 'dayGridMonth'}
          headerToolbar={{
            start: 'prev,next today',
            center: 'title',
            end: isMobile ? 'listMonth,dayGridMonth' : 'dayGridMonth,dayGridWeek,listMonth',
          }}
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
          datesSet={(info) => setRange({ from: info.startStr.slice(0, 10), to: info.endStr.slice(0, 10) })}
          eventClick={(info) => navigate(`/events/${info.event.id}`)}
          dayMaxEventRows={isMobile ? 2 : 4}
          noEventsContent={() => <EmptyState compact art="calendar" title="אין אירועים בטווח הזה" />}
        />
      </div>

      {legend.length > 0 && (
        <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5 px-1">
          <span className="type-overline">לקוחות בתצוגה</span>
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
