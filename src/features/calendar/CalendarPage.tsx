import { useCallback, useMemo, useRef, useState } from 'react'
import FullCalendar from '@fullcalendar/react'
import dayGridPlugin from '@fullcalendar/daygrid'
import timeGridPlugin from '@fullcalendar/timegrid'
import listPlugin from '@fullcalendar/list'
import interactionPlugin from '@fullcalendar/interaction'
import heLocale from '@fullcalendar/core/locales/he'
import type { EventDropArg } from '@fullcalendar/core'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Plus, Save } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { Button, Input, Select, useToast } from '../../components/ui'
import { useContractors, useCustomers, useStaff, useStatuses, useTaskTypes } from '../../lib/queries'
import { TaskDrawer } from '../tasks/TaskDrawer'
import { EventFormModal } from '../events/EventFormModal'
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

export default function CalendarPage() {
  const qc = useQueryClient()
  const toast = useToast()
  const { me, can } = useAuth()
  const [range, setRange] = useState<{ from: string; to: string } | null>(null)
  const [filters, setFilters] = useState<Filters>(emptyFilters)
  const [drawerTask, setDrawerTask] = useState<string | null>(null)
  const [drawerOpen, setDrawerOpen] = useState(false)
  const [eventModal, setEventModal] = useState(false)
  const calRef = useRef<FullCalendar>(null)

  const { data: customers = [] } = useCustomers()
  const { data: staffList = [] } = useStaff()
  const { data: contractors = [] } = useContractors()
  const { data: statuses = [] } = useStatuses('task')
  const { data: taskTypes = [] } = useTaskTypes()

  const { data: tasks = [] } = useQuery({
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
        const end = t.onsite_start_time && t.onsite_end_time && t.onsite_end_time > t.onsite_start_time
          ? `${t.task_date}T${t.onsite_end_time}`
          : undefined
        return {
          id: t.id,
          title: `${t.task_types?.name ?? ''} · ${label}`,
          start,
          end,
          allDay: !t.onsite_start_time,
          backgroundColor: t.customers?.color ?? '#64748b',
          textColor: '#ffffff',
        }
      }),
    [filtered],
  )

  const moveTask = useMutation({
    mutationFn: async ({ id, date, time }: { id: string; date: string; time: string | null }) => {
      const patch: Record<string, unknown> = { task_date: date }
      if (time) patch.onsite_start_time = time
      const { error } = await supabase.from('tasks').update(patch).eq('id', id)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('המשימה עודכנה')
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
      if (!can('tasks', 'edit')) {
        arg.revert()
        return
      }
      const d = arg.event.start
      if (!d) return
      const date = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
      const time = arg.event.allDay ? null : `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
      moveTask.mutate({ id: arg.event.id, date, time })
    },
    [can, moveTask],
  )

  // saved filters
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
    const name = prompt('שם הפילטר:')
    if (!name || !me) return
    const { error } = await supabase.from('saved_filters').insert({ profile_id: me.profile.id, screen: 'calendar', name, filters })
    if (error) toast.error(error.message)
    else void qc.invalidateQueries({ queryKey: ['saved_filters'] })
  }

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <h1 className="text-xl font-bold">לוח שנה</h1>
        <div className="ms-auto flex flex-wrap items-center gap-2">
          {savedFilters.length > 0 && (
            <Select
              className="w-36"
              value=""
              onChange={(e) => {
                const f = savedFilters.find((s) => s.id === e.target.value)
                if (f) setFilters({ ...emptyFilters, ...(f.filters as Partial<Filters>) })
              }}
            >
              <option value="">פילטרים שמורים...</option>
              {savedFilters.map((f) => (
                <option key={f.id} value={f.id}>{f.name}</option>
              ))}
            </Select>
          )}
          <Button onClick={() => void saveFilter()} title="שמירת פילטר נוכחי">
            <Save size={14} />
          </Button>
          {can('events', 'create') && (
            <Button variant="primary" onClick={() => setEventModal(true)}>
              <Plus size={14} /> אירוע חדש
            </Button>
          )}
        </div>
      </div>

      <div className="surface flex flex-wrap items-center gap-2 p-2.5">
        <Input className="w-44" placeholder="חיפוש חופשי..." value={filters.q} onChange={(e) => setFilters((f) => ({ ...f, q: e.target.value }))} />
        <Select className="w-36" value={filters.customer} onChange={(e) => setFilters((f) => ({ ...f, customer: e.target.value }))}>
          <option value="">כל הלקוחות</option>
          {customers.map((c) => (
            <option key={c.id} value={c.id}>{c.name}</option>
          ))}
        </Select>
        <Select className="w-36" value={filters.worker} onChange={(e) => setFilters((f) => ({ ...f, worker: e.target.value }))}>
          <option value="">כל העובדים</option>
          {staffList.map((p) => (
            <option key={p.id} value={p.id}>{p.full_name}</option>
          ))}
        </Select>
        <Select className="w-36" value={filters.contractor} onChange={(e) => setFilters((f) => ({ ...f, contractor: e.target.value }))}>
          <option value="">כל הקבלנים</option>
          {contractors.map((c) => (
            <option key={c.id} value={c.id}>{c.name}</option>
          ))}
        </Select>
        <Select className="w-32" value={filters.status} onChange={(e) => setFilters((f) => ({ ...f, status: e.target.value }))}>
          <option value="">כל הסטטוסים</option>
          {statuses.map((s) => (
            <option key={s.id} value={s.id}>{s.name}</option>
          ))}
        </Select>
        <Select className="w-32" value={filters.taskType} onChange={(e) => setFilters((f) => ({ ...f, taskType: e.target.value }))}>
          <option value="">כל הסוגים</option>
          {taskTypes.map((t) => (
            <option key={t.id} value={t.id}>{t.name}</option>
          ))}
        </Select>
        {JSON.stringify(filters) !== JSON.stringify(emptyFilters) && (
          <Button variant="ghost" onClick={() => setFilters(emptyFilters)}>ניקוי</Button>
        )}
      </div>

      <div className="surface p-3">
        <FullCalendar
          ref={calRef}
          plugins={[dayGridPlugin, timeGridPlugin, listPlugin, interactionPlugin]}
          initialView="dayGridMonth"
          headerToolbar={{ start: 'prev,next today', center: 'title', end: 'dayGridMonth,timeGridWeek,timeGridDay,listWeek' }}
          buttonText={{ month: 'חודש', week: 'שבוע', day: 'יום', list: 'סדר יום', today: 'היום' }}
          locale={heLocale}
          direction="rtl"
          height="auto"
          editable={can('tasks', 'edit')}
          events={calEvents}
          eventDrop={onDrop}
          datesSet={(info) => {
            setRange({ from: info.startStr.slice(0, 10), to: info.endStr.slice(0, 10) })
          }}
          eventClick={(info) => {
            setDrawerTask(info.event.id)
            setDrawerOpen(true)
          }}
          dayMaxEventRows={4}
          nowIndicator
        />
      </div>

      <TaskDrawer open={drawerOpen} onClose={() => setDrawerOpen(false)} taskId={drawerTask} />
      <EventFormModal open={eventModal} onClose={() => setEventModal(false)} />
    </div>
  )
}
