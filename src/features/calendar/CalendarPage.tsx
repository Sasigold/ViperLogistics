import { useCallback, useMemo, useRef, useState } from 'react'
import FullCalendar from '@fullcalendar/react'
import dayGridPlugin from '@fullcalendar/daygrid'
import timeGridPlugin from '@fullcalendar/timegrid'
import listPlugin from '@fullcalendar/list'
import interactionPlugin from '@fullcalendar/interaction'
import heLocale from '@fullcalendar/core/locales/he'
import type { EventContentArg, EventDropArg } from '@fullcalendar/core'
import type { EventResizeDoneArg } from '@fullcalendar/interaction'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { ClipboardList, Copy, Filter, ICON, Plus, STROKE, Save, Users, X } from '../../components/ui/icons'
import {
  Badge,
  Button,
  EmptyState,
  IconButton,
  Input,
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
import { useContractors, useCustomers, useStaff, useStatuses, useTaskTypes } from '../../lib/queries'
import { fmtDate, fmtTime } from '../../lib/dates'
import { TaskDrawer } from '../tasks/TaskDrawer'
import { EventFormModal } from '../events/EventFormModal'
import { chipPaint } from './eventColors'
import type { SavedFilter } from '../../types/domain'

interface CalTask {
  id: string
  task_date: string
  onsite_start_time: string | null
  onsite_end_time: string | null
  title: string | null
  customer_id: string | null
  contractor_id: string | null
  status_id: string
  task_type_id: string
  event_id: string | null
  events: { end_client_name: string | null; event_number: string | null; location_text: string | null } | null
  customers: { name: string; color: string } | null
  task_types: { name: string } | null
  task_assignments: { profile_id: string }[]
}

interface Filters {
  customer: string
  worker: string
  contractor: string
  status: string
  taskType: string
  q: string
}

const emptyFilters: Filters = { customer: '', worker: '', contractor: '', status: '', taskType: '', q: '' }

const FILTER_LABELS: Record<keyof Filters, string> = {
  q: 'חיפוש',
  customer: 'לקוח',
  worker: 'עובד',
  contractor: 'קבלן',
  status: 'סטטוס',
  taskType: 'סוג',
}

export default function CalendarPage() {
  const qc = useQueryClient()
  const toast = useToast()
  const navigate = useNavigate()
  const { me, can } = useAuth()
  const { openMenu, menu } = useContextMenu()
  const { prompt, dialog: promptDialog } = usePrompt()

  const [range, setRange] = useState<{ from: string; to: string } | null>(null)
  const [filters, setFilters] = useState<Filters>(emptyFilters)
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [drawerTask, setDrawerTask] = useState<string | null>(null)
  const [drawerOpen, setDrawerOpen] = useState(false)
  const [eventModal, setEventModal] = useState(false)
  const calRef = useRef<FullCalendar>(null)

  const canEdit = can('tasks', 'edit')

  const { data: customers = [] } = useCustomers()
  const { data: staffList = [] } = useStaff()
  const { data: contractors = [] } = useContractors()
  const { data: statuses = [] } = useStatuses('task')
  const { data: taskTypes = [] } = useTaskTypes()

  const { data: tasks = [], isFetching } = useQuery({
    queryKey: ['calendar', 'tasks', range],
    enabled: !!range,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('tasks')
        .select(
          'id, task_date, onsite_start_time, onsite_end_time, title, customer_id, contractor_id, status_id, task_type_id, event_id, events(end_client_name, event_number, location_text), customers(name, color), task_types(name), task_assignments(profile_id)',
        )
        .gte('task_date', range!.from)
        .lte('task_date', range!.to)
        .is('deleted_at', null)
      if (error) throw error
      return data as unknown as CalTask[]
    },
  })

  const staffById = useMemo(() => new Map(staffList.map((p) => [p.id, p.full_name])), [staffList])
  const statusById = useMemo(() => new Map(statuses.map((s) => [s.id, s])), [statuses])

  const filtered = useMemo(() => {
    return tasks.filter((t) => {
      if (filters.customer && t.customer_id !== filters.customer) return false
      if (filters.contractor && t.contractor_id !== filters.contractor) return false
      if (filters.status && t.status_id !== filters.status) return false
      if (filters.taskType && t.task_type_id !== filters.taskType) return false
      if (filters.worker && !t.task_assignments.some((a) => a.profile_id === filters.worker)) return false
      if (filters.q) {
        const hay = [t.title, t.events?.end_client_name, t.events?.event_number, t.events?.location_text, t.customers?.name, t.task_types?.name]
          .filter(Boolean)
          .join(' ')
        if (!hay.includes(filters.q)) return false
      }
      return true
    })
  }, [tasks, filters])

  const calEvents = useMemo(
    () =>
      filtered.map((t) => {
        const label = t.title || t.events?.end_client_name || t.customers?.name || 'משימה'
        const start = t.onsite_start_time ? `${t.task_date}T${t.onsite_start_time}` : t.task_date
        const end =
          t.onsite_start_time && t.onsite_end_time && t.onsite_end_time > t.onsite_start_time
            ? `${t.task_date}T${t.onsite_end_time}`
            : undefined
        return {
          id: t.id,
          title: `${t.task_types?.name ?? ''} · ${label}`,
          start,
          end,
          allDay: !t.onsite_start_time,
          extendedProps: { task: t, label },
        }
      }),
    [filtered],
  )

  /** Customers present in the current view — doubles as a colour legend. */
  const legend = useMemo(() => {
    const seen = new Map<string, { name: string; color: string; count: number }>()
    for (const t of filtered) {
      if (!t.customers) continue
      const key = t.customer_id ?? t.customers.name
      const hit = seen.get(key)
      if (hit) hit.count++
      else seen.set(key, { name: t.customers.name, color: t.customers.color, count: 1 })
    }
    return [...seen.entries()].sort((a, b) => b[1].count - a[1].count).slice(0, 8)
  }, [filtered])

  /* ── single write path for drag + resize, with undo ───────────────────── */

  const patchTask = useMutation({
    mutationFn: async ({ id, patch }: { id: string; patch: Record<string, unknown>; undo?: Record<string, unknown>; message?: string }) => {
      const { error } = await supabase.from('tasks').update(patch).eq('id', id)
      if (error) throw error
    },
    onSuccess: (_d, vars) => {
      toast.success(vars.message ?? 'המשימה עודכנה', {
        undo: vars.undo ? () => patchTask.mutate({ id: vars.id, patch: vars.undo!, message: 'השינוי בוטל' }) : undefined,
      })
      void qc.invalidateQueries({ queryKey: ['calendar'] })
      void qc.invalidateQueries({ queryKey: ['workboard'] })
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
        toast.warning('אין לך הרשאה לשנות משימות')
        return
      }
      const d = arg.event.start
      if (!d) return
      const task = arg.event.extendedProps.task as CalTask
      const date = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
      const time = arg.event.allDay ? null : `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`

      const patch: Record<string, unknown> = { task_date: date }
      if (time) patch.onsite_start_time = time

      const undo: Record<string, unknown> = { task_date: task.task_date }
      if (time) undo.onsite_start_time = task.onsite_start_time

      patchTask.mutate({ id: arg.event.id, patch, undo, message: `הועבר ל-${fmtDate(date)}${time ? ` ${time}` : ''}` })
    },
    [canEdit, patchTask, toast],
  )

  /** Dragging the bottom edge writes onsite_end_time — the same column and
   *  the same permission as every other inline edit on a task. */
  const onResize = useCallback(
    (arg: EventResizeDoneArg) => {
      if (!canEdit) {
        arg.revert()
        toast.warning('אין לך הרשאה לשנות משימות')
        return
      }
      const end = arg.event.end
      if (!end) {
        arg.revert()
        return
      }
      const task = arg.event.extendedProps.task as CalTask
      const endTime = `${String(end.getHours()).padStart(2, '0')}:${String(end.getMinutes()).padStart(2, '0')}`
      patchTask.mutate({
        id: arg.event.id,
        patch: { onsite_end_time: endTime },
        undo: { onsite_end_time: task.onsite_end_time },
        message: `שעת הסיום עודכנה ל-${endTime}`,
      })
    },
    [canEdit, patchTask, toast],
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
      placeholder: 'למשל: משימות דחופות של אלפא',
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
    if (k === 'worker') return staffById.get(v) ?? v
    if (k === 'contractor') return contractors.find((c) => c.id === v)?.name ?? v
    if (k === 'status') return statusById.get(v)?.name ?? v
    return taskTypes.find((t) => t.id === v)?.name ?? v
  }

  /* ── event rendering ──────────────────────────────────────────────────── */

  const renderEvent = useCallback(
    (arg: EventContentArg) => {
      const task = arg.event.extendedProps.task as CalTask | undefined
      if (!task) return <span className="truncate px-1">{arg.event.title}</span>
      const label = arg.event.extendedProps.label as string
      const paint = chipPaint(task.customers?.color)
      const timeGrid = arg.view.type.startsWith('timeGrid')
      const list = arg.view.type.startsWith('list')
      const status = statusById.get(task.status_id)
      const team = task.task_assignments.map((a) => staffById.get(a.profile_id)).filter((n): n is string => !!n)
      const time = fmtTime(task.onsite_start_time)
      const endTime = fmtTime(task.onsite_end_time)

      if (list) {
        return (
          <span className="flex min-w-0 items-center gap-2">
            <span className="size-2 shrink-0 rounded-full" style={{ background: task.customers?.color ?? '#64748b' }} />
            <span className="truncate font-medium">{label}</span>
            <span className="truncate type-caption text-ink-tertiary">{task.task_types?.name}</span>
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
              <span className="block opacity-90">
                {task.task_types?.name}
                {task.customers && ` · ${task.customers.name}`}
              </span>
              {task.events?.location_text && (
                <span className="block opacity-80">📍 {task.events.location_text}</span>
              )}
              <span className="block tabular opacity-80">
                🕐 {time || 'ללא שעה'}
                {endTime && ` – ${endTime}`}
              </span>
              {team.length > 0 && <span className="block opacity-80">👥 {team.join(', ')}</span>}
              {status && <span className="block opacity-80">● {status.name}</span>}
              {task.events?.event_number && <span className="block opacity-60">#{task.events.event_number}</span>}
            </span>
          }
        >
          <span
            onContextMenu={(e) =>
              openMenu(e, [
                {
                  key: 'open',
                  label: 'פתיחת המשימה',
                  icon: <ClipboardList size={ICON.sm} />,
                  onClick: () => {
                    setDrawerTask(task.id)
                    setDrawerOpen(true)
                  },
                },
                {
                  key: 'board',
                  label: 'הצגה בלוח העבודה',
                  icon: <Users size={ICON.sm} />,
                  onClick: () => navigate(`/board?task=${task.id}&date=${task.task_date}`),
                },
                { key: 'sep1', label: '', separator: true },
                {
                  key: 'filter',
                  label: `סינון לפי ${task.customers?.name ?? 'לקוח'}`,
                  icon: <Filter size={ICON.sm} />,
                  disabled: !task.customer_id,
                  onClick: () => setFilters((f) => ({ ...f, customer: task.customer_id ?? '' })),
                },
                {
                  key: 'copy',
                  label: 'העתקת פרטי המשימה',
                  icon: <Copy size={ICON.sm} />,
                  onClick: () => {
                    const text = [
                      label,
                      task.task_types?.name,
                      task.customers?.name,
                      fmtDate(task.task_date),
                      time && `${time}${endTime ? `–${endTime}` : ''}`,
                      task.events?.location_text,
                      team.length ? team.join(', ') : null,
                    ]
                      .filter(Boolean)
                      .join(' · ')
                    void navigator.clipboard?.writeText(text).then(
                      () => toast.success('הפרטים הועתקו'),
                      () => toast.error('ההעתקה נכשלה'),
                    )
                  },
                },
              ])
            }
            className={cx(
              'group/ev relative flex h-full min-w-0 overflow-hidden rounded-md shadow-xs',
              'transition-[filter,box-shadow] duration-150 hover:shadow-md hover:brightness-105',
              timeGrid ? 'flex-col gap-0.5 p-1.5' : 'items-center gap-1 px-1.5 py-1',
            )}
            style={{ background: paint.background, color: paint.color }}
          >
            <span
              aria-hidden
              className="absolute inset-y-0 start-0 w-1 rounded-s-md"
              style={{ background: paint.railColor }}
            />
            {timeGrid ? (
              <>
                <span className="flex items-center gap-1 ps-1">
                  {time && <span className="shrink-0 type-caption font-bold tabular opacity-95">{time}</span>}
                  {status && (
                    <span
                      className="size-1.5 shrink-0 rounded-full ring-1 ring-white/40"
                      style={{ background: status.color }}
                      title={status.name}
                    />
                  )}
                </span>
                <span className="truncate ps-1 type-caption font-semibold leading-tight">{label}</span>
                <span className="truncate ps-1 type-caption opacity-80">{task.task_types?.name}</span>
                {team.length > 0 && (
                  <span className="mt-auto ps-1 type-caption opacity-85">
                    {team.length} {team.length === 1 ? 'משובץ' : 'משובצים'}
                  </span>
                )}
              </>
            ) : (
              <>
                {time && <span className="shrink-0 ps-1 type-caption font-bold tabular opacity-95">{time}</span>}
                <span className="min-w-0 flex-1 truncate type-caption font-semibold">{label}</span>
                {status && (
                  <span
                    className="size-1.5 shrink-0 rounded-full ring-1 ring-white/40"
                    style={{ background: status.color }}
                    title={status.name}
                  />
                )}
              </>
            )}
          </span>
        </Tooltip>
      )
    },
    [statusById, staffById, openMenu, navigate, toast],
  )

  return (
    <div className="space-y-4">
      {promptDialog}
      {menu}

      <PageHeader
        title="לוח שנה"
        subtitle={range ? `${filtered.length} משימות בטווח המוצג` : 'טוען...'}
        actions={
          <>
            {savedFilters.length > 0 && (
              <Select
                className="w-44"
                selectSize="sm"
                value=""
                aria-label="פילטרים שמורים"
                onChange={(e) => {
                  const f = savedFilters.find((s) => s.id === e.target.value)
                  if (f) {
                    setFilters({ ...emptyFilters, ...(f.filters as Partial<Filters>) })
                    setFiltersOpen(true)
                  }
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
            <IconButton label="שמירת הסינון הנוכחי" size="sm" onClick={() => void saveFilter()} disabled={activeFilters.length === 0}>
              <Save size={ICON.md} strokeWidth={STROKE} />
            </IconButton>
            {can('events', 'create') && (
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
          <div className="flex flex-wrap items-center gap-1.5">
            {activeFilters.map((k) => (
              <span
                key={k}
                className="inline-flex items-center gap-1 rounded-full border border-primary-border bg-primary-subtle py-0.5 pe-1 ps-2 type-caption font-medium text-primary-text"
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
              className="rounded-md px-2 py-0.5 type-caption text-ink-tertiary transition-colors hover:bg-hover hover:text-ink"
            >
              ניקוי הכל
            </button>
          </div>
        )}

        {filtersOpen && (
          <div className="surface grid animate-slide-up gap-2 p-3 sm:grid-cols-2 lg:grid-cols-6">
            <Input
              placeholder="חיפוש חופשי..."
              inputSize="sm"
              value={filters.q}
              onChange={(e) => setFilters((f) => ({ ...f, q: e.target.value }))}
            />
            <Select selectSize="sm" value={filters.customer} onChange={(e) => setFilters((f) => ({ ...f, customer: e.target.value }))}>
              <option value="">כל הלקוחות</option>
              {customers.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </Select>
            <Select selectSize="sm" value={filters.worker} onChange={(e) => setFilters((f) => ({ ...f, worker: e.target.value }))}>
              <option value="">כל העובדים</option>
              {staffList.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.full_name}
                </option>
              ))}
            </Select>
            <Select selectSize="sm" value={filters.contractor} onChange={(e) => setFilters((f) => ({ ...f, contractor: e.target.value }))}>
              <option value="">כל הקבלנים</option>
              {contractors.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </Select>
            <Select selectSize="sm" value={filters.status} onChange={(e) => setFilters((f) => ({ ...f, status: e.target.value }))}>
              <option value="">כל הסטטוסים</option>
              {statuses.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
            </Select>
            <Select selectSize="sm" value={filters.taskType} onChange={(e) => setFilters((f) => ({ ...f, taskType: e.target.value }))}>
              <option value="">כל הסוגים</option>
              {taskTypes.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.name}
                </option>
              ))}
            </Select>
          </div>
        )}
      </PageHeader>

      <div className="surface relative overflow-hidden p-3">
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
          plugins={[dayGridPlugin, timeGridPlugin, listPlugin, interactionPlugin]}
          initialView="dayGridMonth"
          headerToolbar={{ start: 'prev,next today', center: 'title', end: 'dayGridMonth,timeGridWeek,timeGridDay,listWeek' }}
          buttonText={{ month: 'חודש', week: 'שבוע', day: 'יום', list: 'סדר יום', today: 'היום' }}
          locale={heLocale}
          direction="rtl"
          height="auto"
          editable={canEdit}
          eventResizableFromStart={false}
          events={calEvents}
          eventContent={renderEvent}
          eventDrop={onDrop}
          eventResize={onResize}
          datesSet={(info) => setRange({ from: info.startStr.slice(0, 10), to: info.endStr.slice(0, 10) })}
          eventClick={(info) => {
            setDrawerTask(info.event.id)
            setDrawerOpen(true)
          }}
          dayMaxEventRows={4}
          nowIndicator
          scrollTime="07:00:00"
          slotEventOverlap={false}
          expandRows
          noEventsContent={() => <EmptyState compact art="calendar" title="אין משימות בטווח הזה" />}
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

      <TaskDrawer open={drawerOpen} onClose={() => setDrawerOpen(false)} taskId={drawerTask} />
      <EventFormModal open={eventModal} onClose={() => setEventModal(false)} />
    </div>
  )
}
