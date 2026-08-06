import { useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Copy, Pencil, Plus, Trash2, History } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { Badge, Button, Spinner, useConfirm, useToast } from '../../components/ui'
import { fmtDate, fmtDateLong, fmtHours, fmtTime } from '../../lib/dates'
import { EventFormModal } from './EventFormModal'
import { TaskDrawer } from '../tasks/TaskDrawer'
import { AuditTrail } from '../settings/AuditTrail'
import type { EventRow, WorkBoardRow } from '../../types/domain'

export default function EventDetailPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const qc = useQueryClient()
  const toast = useToast()
  const { me, can, canViewField } = useAuth()
  const { confirm, dialog } = useConfirm()
  const [editOpen, setEditOpen] = useState(false)
  const [taskDrawer, setTaskDrawer] = useState<{ open: boolean; taskId: string | null }>({ open: false, taskId: null })
  const [auditOpen, setAuditOpen] = useState(false)

  const { data, isLoading } = useQuery({
    queryKey: ['events', 'one', id],
    queryFn: async () => {
      const [e, contact, sup] = await Promise.all([
        supabase.from('events').select('*, customers(name, color), statuses(name, color)').eq('id', id).single(),
        supabase.from('event_contacts').select('*').eq('event_id', id).maybeSingle(),
        supabase.from('event_suppliers').select('supplier_id, suppliers(name)').eq('event_id', id),
      ])
      if (e.error) throw e.error
      return {
        event: e.data as EventRow,
        contact: contact.data as { contact_name: string | null; contact_phone: string | null } | null,
        suppliers: (sup.data ?? []) as unknown as { supplier_id: string; suppliers: { name: string } }[],
      }
    },
  })

  const { data: tasks = [] } = useQuery({
    queryKey: ['workboard', 'byEvent', id],
    queryFn: async () => {
      const { data, error } = await supabase.from('work_board_view').select('*').eq('event_id', id).order('task_date')
      if (error) throw error
      return data as WorkBoardRow[]
    },
  })

  if (isLoading || !data) return <Spinner full />
  const { event, contact, suppliers } = data

  const remove = async () => {
    if (!(await confirm('למחוק את האירוע וכל המשימות שלו? ניתן לשחזר מסל המיחזור.'))) return
    const { error } = await supabase.rpc('soft_delete', { p_table: 'events', p_id: event.id })
    if (error) return toast.error(error.message)
    toast.success('האירוע נמחק')
    void qc.invalidateQueries({ queryKey: ['events'] })
    navigate('/events')
  }

  const duplicate = async () => {
    const { data: newId, error } = await supabase.rpc('duplicate_event', { p_event_id: event.id })
    if (error) return toast.error(error.message)
    toast.success('האירוע שוכפל')
    void qc.invalidateQueries({ queryKey: ['events'] })
    navigate(`/events/${newId}`)
  }

  const info: [string, React.ReactNode][] = [
    ['לקוח במערכת', <span key="c" className="inline-flex items-center gap-1.5"><span className="size-2.5 rounded-full" style={{ background: event.customers?.color }} />{event.customers?.name}</span>],
    ['שם לקוח האירוע', event.end_client_name],
    ['מספר אירוע', event.event_number],
    ['מיקום', event.location_text],
    ['הערות למיקום', event.location_notes],
    ['נפח במטר', event.volume_m],
    ['כמות משאיות', event.truck_count],
    ...(canViewField('event', 'contact_phone')
      ? ([['איש קשר', contact?.contact_name], ['טלפון איש קשר', contact?.contact_phone]] as [string, React.ReactNode][])
      : []),
    ['הערות', event.notes],
  ]

  const addons = [
    event.no_parking && 'אין חניה',
    event.porterage && 'סבלות',
    event.supplier_pickup && 'איסוף מספקים',
  ].filter(Boolean)

  return (
    <div className="space-y-4">
      {dialog}
      <div className="flex flex-wrap items-center gap-2">
        <div>
          <h1 className="text-xl font-bold">{event.end_client_name || 'אירוע'}</h1>
          <p className="text-sm text-[var(--muted)]">{fmtDateLong(event.event_date)}</p>
        </div>
        {event.statuses && <Badge color={event.statuses.color}>{event.statuses.name}</Badge>}
        <div className="ms-auto flex flex-wrap gap-2">
          {me?.profile.is_admin && (
            <Button onClick={() => setAuditOpen(true)}><History size={14} /> היסטוריה</Button>
          )}
          {can('events', 'create') && (
            <Button onClick={() => void duplicate()}><Copy size={14} /> שכפול</Button>
          )}
          {can('events', 'edit') && (
            <Button onClick={() => setEditOpen(true)}><Pencil size={14} /> עריכה</Button>
          )}
          {can('events', 'delete') && (
            <Button variant="danger" onClick={() => void remove()}><Trash2 size={14} /> מחיקה</Button>
          )}
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <div className="surface p-4 lg:col-span-1">
          <h2 className="mb-3 text-sm font-bold">פרטי האירוע</h2>
          <dl className="space-y-2 text-sm">
            {info.filter(([, v]) => v != null && v !== '').map(([k, v]) => (
              <div key={k} className="flex justify-between gap-2">
                <dt className="text-[var(--muted)]">{k}</dt>
                <dd className="text-end font-medium">{v}</dd>
              </div>
            ))}
            {addons.length > 0 && (
              <div className="flex justify-between gap-2">
                <dt className="text-[var(--muted)]">תוספות</dt>
                <dd className="flex flex-wrap justify-end gap-1">{addons.map((a) => <Badge key={String(a)}>{a}</Badge>)}</dd>
              </div>
            )}
            {suppliers.length > 0 && (
              <div className="flex justify-between gap-2">
                <dt className="text-[var(--muted)]">ספקים לאיסוף</dt>
                <dd className="flex flex-wrap justify-end gap-1">{suppliers.map((s) => <Badge key={s.supplier_id}>{s.suppliers.name}</Badge>)}</dd>
              </div>
            )}
          </dl>
        </div>

        <div className="surface p-4 lg:col-span-2">
          <div className="mb-3 flex items-center justify-between">
            <h2 className="text-sm font-bold">משימות האירוע</h2>
            {can('tasks', 'create') && (
              <Button onClick={() => setTaskDrawer({ open: true, taskId: null })}>
                <Plus size={14} /> משימה
              </Button>
            )}
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[var(--border)] text-xs text-[var(--muted)]">
                  <th className="px-2 py-1.5 text-start">סוג</th>
                  <th className="px-2 py-1.5 text-start">תאריך</th>
                  <th className="px-2 py-1.5 text-start">שטח</th>
                  <th className="px-2 py-1.5 text-start">משך</th>
                  <th className="px-2 py-1.5 text-start">עובדים</th>
                  <th className="px-2 py-1.5 text-start">אופן ביצוע</th>
                  <th className="px-2 py-1.5 text-start">ראש צוות</th>
                  <th className="px-2 py-1.5 text-start">קבלן</th>
                  <th className="px-2 py-1.5 text-start">סטטוס</th>
                </tr>
              </thead>
              <tbody>
                {tasks.map((t) => (
                  <tr
                    key={t.id}
                    onClick={() => setTaskDrawer({ open: true, taskId: t.id })}
                    className="cursor-pointer border-b border-[var(--border)] last:border-0 hover:bg-[var(--bg)]"
                  >
                    <td className="px-2 py-2 font-medium">{t.title || t.task_type_name}</td>
                    <td className="px-2 py-2 whitespace-nowrap">{fmtDate(t.task_date)}</td>
                    <td className="px-2 py-2 whitespace-nowrap" dir="ltr">
                      {fmtTime(t.onsite_start_time)}{t.onsite_end_time ? `–${fmtTime(t.onsite_end_time)}` : ''}
                    </td>
                    <td className="px-2 py-2">{fmtHours(t.hours_count)}</td>
                    <td className="px-2 py-2">{t.worker_count}</td>
                    <td className="px-2 py-2">{t.execution_method_name}</td>
                    <td className="px-2 py-2">{t.team_lead_name}</td>
                    <td className="px-2 py-2">{t.contractor_name}</td>
                    <td className="px-2 py-2"><Badge color={t.status_color}>{t.status_name}</Badge></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <EventFormModal
        open={editOpen}
        onClose={() => {
          setEditOpen(false)
          void qc.invalidateQueries({ queryKey: ['events', 'one', id] })
        }}
        event={event}
        contact={contact}
        supplierIds={suppliers.map((s) => s.supplier_id)}
      />
      <TaskDrawer
        open={taskDrawer.open}
        onClose={() => {
          setTaskDrawer({ open: false, taskId: null })
          void qc.invalidateQueries({ queryKey: ['workboard', 'byEvent', id] })
        }}
        taskId={taskDrawer.taskId}
        initial={{ event_id: event.id, customer_id: event.customer_id, task_date: event.event_date }}
      />
      {auditOpen && <AuditTrail entity="events" rowId={event.id} onClose={() => setAuditOpen(false)} />}
    </div>
  )
}
