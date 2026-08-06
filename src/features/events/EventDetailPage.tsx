import { useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Copy, History, ICON, Pencil, Plus, STROKE, Trash2 } from '../../components/ui/icons'
import {
  AvatarGroup,
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  DataTable,
  EmptyState,
  PageHeader,
  SkeletonCard,
  SkeletonTable,
  StatusPill,
  useConfirm,
  useToast,
} from '../../components/ui'
import type { Column } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { fmtDate, fmtDateLong, fmtHours, fmtTime } from '../../lib/dates'
import { usePageTitle } from '../../app/breadcrumbs'
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

  const { data: tasks = [], isLoading: loadingTasks } = useQuery({
    queryKey: ['workboard', 'byEvent', id],
    queryFn: async () => {
      const { data, error } = await supabase.from('work_board_view').select('*').eq('event_id', id).order('task_date')
      if (error) throw error
      return data as WorkBoardRow[]
    },
  })

  usePageTitle(data?.event.end_client_name ?? null)

  const columns = useMemo<Column<WorkBoardRow>[]>(
    () => [
      {
        key: 'type',
        header: 'משימה',
        width: 160,
        fixed: true,
        sortValue: (t) => t.title ?? t.task_type_name,
        render: (t) => <span className="font-medium">{t.title || t.task_type_name}</span>,
      },
      {
        key: 'date',
        header: 'תאריך',
        width: 110,
        sortValue: (t) => t.task_date,
        render: (t) => <span className="tabular">{fmtDate(t.task_date)}</span>,
      },
      {
        key: 'window',
        header: 'שעות בשטח',
        width: 130,
        sortValue: (t) => t.onsite_start_time,
        render: (t) => (
          <span className="tabular" dir="ltr">
            {fmtTime(t.onsite_start_time) || '—'}
            {t.onsite_end_time ? `–${fmtTime(t.onsite_end_time)}` : ''}
          </span>
        ),
      },
      {
        key: 'hours',
        header: 'משך',
        width: 80,
        align: 'end',
        sortValue: (t) => t.hours_count,
        render: (t) => <span className="tabular">{fmtHours(t.hours_count) || '—'}</span>,
      },
      {
        key: 'team',
        header: 'צוות',
        width: 150,
        render: (t) => {
          const names = [
            ...(t.workers ?? []).map((w) => w.name),
            ...(t.drivers ?? []).map((d) => d.name),
            ...(t.contractor_worker_list ?? []).map((w) => w.name),
          ]
          return names.length ? (
            <span className="flex items-center gap-1.5">
              <AvatarGroup names={names} max={3} size="xs" />
              <span className="type-caption tabular text-ink-tertiary">
                {names.length}/{t.worker_count || '—'}
              </span>
            </span>
          ) : (
            <span className="type-caption text-ink-tertiary">לא שובץ</span>
          )
        },
      },
      {
        key: 'method',
        header: 'אופן ביצוע',
        width: 140,
        sortValue: (t) => t.execution_method_name,
        render: (t) => t.execution_method_name || <span className="text-ink-tertiary">—</span>,
      },
      {
        key: 'lead',
        header: 'ראש צוות',
        width: 130,
        sortValue: (t) => t.team_lead_name,
        render: (t) => t.team_lead_name || <span className="text-ink-tertiary">—</span>,
      },
      {
        key: 'contractor',
        header: 'קבלן',
        width: 130,
        sortValue: (t) => t.contractor_name,
        render: (t) => t.contractor_name || <span className="text-ink-tertiary">—</span>,
      },
      {
        key: 'status',
        header: 'סטטוס',
        width: 130,
        sortValue: (t) => t.status_name,
        render: (t) => <StatusPill color={t.status_color}>{t.status_name}</StatusPill>,
      },
    ],
    [],
  )

  if (isLoading || !data) {
    return (
      <div className="space-y-4">
        <SkeletonCard lines={1} />
        <div className="grid gap-4 lg:grid-cols-3">
          <SkeletonCard className="lg:col-span-1" lines={6} />
          <div className="surface lg:col-span-2">
            <SkeletonTable rows={5} cols={5} />
          </div>
        </div>
      </div>
    )
  }

  const { event, contact, suppliers } = data

  const remove = async () => {
    if (
      !(await confirm('למחוק את האירוע וכל המשימות שלו? ניתן לשחזר מסל המיחזור.', {
        title: 'מחיקת אירוע',
        confirmLabel: 'מחיקה',
      }))
    )
      return
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
    [
      'לקוח במערכת',
      event.customers ? (
        <span key="customer" className="inline-flex items-center gap-1.5">
          <span className="size-2.5 rounded-full" style={{ background: event.customers.color }} />
          {event.customers.name}
        </span>
      ) : null,
    ],
    ['שם לקוח האירוע', event.end_client_name],
    ['מספר אירוע', event.event_number],
    ['מיקום', event.location_text],
    ['הערות למיקום', event.location_notes],
    ['נפח במטר', event.volume_m],
    ['כמות משאיות', event.truck_count],
    ...(canViewField('event', 'contact_phone')
      ? ([
          ['איש קשר', contact?.contact_name],
          [
            'טלפון איש קשר',
            contact?.contact_phone ? (
              <a key="phone" href={`tel:${contact.contact_phone}`} dir="ltr" className="text-primary-text hover:underline">
                {contact.contact_phone}
              </a>
            ) : null,
          ],
        ] as [string, React.ReactNode][])
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

      <PageHeader
        title={
          <span className="flex flex-wrap items-center gap-2.5">
            {event.end_client_name || 'אירוע'}
            {event.statuses && <StatusPill color={event.statuses.color}>{event.statuses.name}</StatusPill>}
          </span>
        }
        subtitle={
          <span className="flex flex-wrap items-center gap-x-3">
            <span>{fmtDateLong(event.event_date)}</span>
            {event.event_number && <span className="tabular">· אירוע #{event.event_number}</span>}
            {event.location_text && <span>· {event.location_text}</span>}
          </span>
        }
        actions={
          <>
            {me?.profile.is_admin && (
              <Button size="sm" variant="ghost" onClick={() => setAuditOpen(true)}>
                <History size={ICON.sm} strokeWidth={STROKE} />
                היסטוריה
              </Button>
            )}
            {can('events', 'create') && (
              <Button size="sm" onClick={() => void duplicate()}>
                <Copy size={ICON.sm} strokeWidth={STROKE} />
                שכפול
              </Button>
            )}
            {can('events', 'edit') && (
              <Button size="sm" variant="primary" onClick={() => setEditOpen(true)}>
                <Pencil size={ICON.sm} strokeWidth={STROKE} />
                עריכה
              </Button>
            )}
            {can('events', 'delete') && (
              <Button size="sm" variant="danger" onClick={() => void remove()}>
                <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                מחיקה
              </Button>
            )}
          </>
        }
      />

      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-1">
          <CardHeader title="פרטי האירוע" />
          <CardBody>
            <dl className="divide-y divide-line-subtle">
              {info
                .filter(([, v]) => v != null && v !== '')
                .map(([k, v]) => (
                  <div key={k} className="flex items-start justify-between gap-3 py-2 first:pt-0 last:pb-0">
                    <dt className="shrink-0 type-caption text-ink-tertiary">{k}</dt>
                    <dd className="min-w-0 text-end type-body font-medium">{v}</dd>
                  </div>
                ))}
              {addons.length > 0 && (
                <div className="flex items-start justify-between gap-3 py-2">
                  <dt className="shrink-0 type-caption text-ink-tertiary">תוספות</dt>
                  <dd className="flex flex-wrap justify-end gap-1">
                    {addons.map((a) => (
                      <Badge key={String(a)} tone="info">
                        {a}
                      </Badge>
                    ))}
                  </dd>
                </div>
              )}
              {suppliers.length > 0 && (
                <div className="flex items-start justify-between gap-3 py-2 last:pb-0">
                  <dt className="shrink-0 type-caption text-ink-tertiary">ספקים לאיסוף</dt>
                  <dd className="flex flex-wrap justify-end gap-1">
                    {suppliers.map((s) => (
                      <Badge key={s.supplier_id}>{s.suppliers.name}</Badge>
                    ))}
                  </dd>
                </div>
              )}
            </dl>
          </CardBody>
        </Card>

        <div className="lg:col-span-2">
          <DataTable
            rows={tasks}
            columns={columns}
            getRowId={(t) => t.id}
            loading={loadingTasks}
            dense
            storageKey="event-tasks"
            onRowClick={(t) => setTaskDrawer({ open: true, taskId: t.id })}
            defaultSort={{ key: 'date', dir: 'asc' }}
            mobileCard={(t) => {
              const names = [
                ...(t.workers ?? []).map((w) => w.name),
                ...(t.drivers ?? []).map((d) => d.name),
                ...(t.contractor_worker_list ?? []).map((w) => w.name),
              ]
              return (
                <div className="space-y-1">
                  <div className="flex items-center gap-2">
                    <span className="type-caption font-semibold tabular">{fmtDate(t.task_date)}</span>
                    <span className="type-caption tabular text-ink-tertiary" dir="ltr">
                      {fmtTime(t.onsite_start_time) || '—'}
                      {t.onsite_end_time ? `–${fmtTime(t.onsite_end_time)}` : ''}
                    </span>
                    <StatusPill color={t.status_color} className="ms-auto shrink-0">
                      {t.status_name}
                    </StatusPill>
                  </div>
                  <p className="truncate type-body font-semibold">{t.title || t.task_type_name}</p>
                  <div className="flex items-center gap-2">
                    {names.length > 0 ? (
                      <AvatarGroup names={names} max={4} size="xs" />
                    ) : (
                      <span className="type-caption text-ink-tertiary">לא שובץ</span>
                    )}
                    {t.contractor_name && <span className="truncate type-caption text-ink-tertiary">{t.contractor_name}</span>}
                  </div>
                </div>
              )
            }}
            toolbar={
              <div className="flex w-full items-center gap-2">
                <h2 className="type-title">משימות האירוע</h2>
                <span className="type-caption tabular text-ink-tertiary">{tasks.length}</span>
                {can('tasks', 'create') && (
                  <Button size="sm" className="ms-auto" onClick={() => setTaskDrawer({ open: true, taskId: null })}>
                    <Plus size={ICON.sm} strokeWidth={STROKE} />
                    משימה
                  </Button>
                )}
              </div>
            }
            empty={
              <EmptyState
                art="table"
                title="אין משימות לאירוע"
                description="משימות הקמה ופירוק נוצרות אוטומטית עם האירוע; ניתן להוסיף משימות נוספות ידנית"
                action={
                  can('tasks', 'create') && (
                    <Button size="sm" variant="primary" onClick={() => setTaskDrawer({ open: true, taskId: null })}>
                      <Plus size={ICON.sm} />
                      משימה חדשה
                    </Button>
                  )
                }
              />
            }
          />
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
