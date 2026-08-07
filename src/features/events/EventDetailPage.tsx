import { useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Banknote, Copy, ICON, Pencil, Plus, STROKE, Trash2 } from '../../components/ui/icons'
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
  fmtMoney,
  useConfirm,
  useToast,
} from '../../components/ui'
import type { Column } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { fmtDate, fmtDateLong, fmtHours, fmtTime } from '../../lib/dates'
import { usePageTitle } from '../../app/breadcrumbs'
import { EventFormModal } from './EventFormModal'
import { TaskDrawer } from '../tasks/TaskDrawer'
import { EventActivityLog } from './EventActivityLog'
import type { EventRow, WorkBoardRow } from '../../types/domain'

export default function EventDetailPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const qc = useQueryClient()
  const toast = useToast()
  const { has, canViewField } = useAuth()
  const { confirm, dialog } = useConfirm()
  const [editOpen, setEditOpen] = useState(false)
  const [taskDrawer, setTaskDrawer] = useState<{ open: boolean; taskId: string | null }>({ open: false, taskId: null })

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

  /**
   * מחיר האירוע הוא סכום מחירי המשימות שלו — אין עמודת מחיר על האירוע עצמו.
   * work_board_view כבר מחזירה null ב-customer_price למי שאין לו pricing.view,
   * ולכן די בבדיקה הזו כדי שהכרטיס לא יופיע בכלל, בלי גידור נוסף כאן.
   */
  const pricing = useMemo(() => {
    const priced = tasks.filter((t) => t.customer_price != null)
    if (!priced.length) return null
    return {
      rows: priced.map((t) => ({
        id: t.id,
        label: t.title || t.task_type_name,
        price: Number(t.customer_price),
        isManual: !!t.price_is_manual,
      })),
      total: priced.reduce((sum, t) => sum + Number(t.customer_price), 0),
      unpriced: tasks.length - priced.length,
    }
  }, [tasks])

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
      // העמודה נוספת רק כשיש בכלל מחירים לראות — למי שאין לו pricing.view
      // work_board_view מחזירה null, וכותרת עמודה ריקה היא רעש.
      ...(pricing
        ? ([
            {
              key: 'price',
              header: 'מחיר ללקוח',
              width: 120,
              align: 'end',
              sortValue: (t) => t.customer_price,
              render: (t) =>
                t.customer_price == null ? (
                  <span className="text-ink-tertiary">—</span>
                ) : (
                  <span dir="ltr" className="tabular">
                    {fmtMoney(t.customer_price)}
                  </span>
                ),
            },
          ] as Column<WorkBoardRow>[])
        : []),
    ],
    [pricing],
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

  /** one-line recap of an auto-created task, so the two sections read at a glance */
  const sectionLine = (code: 'setup' | 'teardown') => {
    const t = tasks.find((x) => x.task_type_code === code)
    if (!t) return null
    return (
      [
        fmtDate(t.task_date),
        fmtTime(t.onsite_start_time),
        t.worker_count ? `${t.worker_count} עובדים` : null,
        t.hours_count != null ? `${fmtHours(t.hours_count)} שעות` : null,
        t.execution_method_name,
      ]
        .filter(Boolean)
        .join(' · ') || null
    )
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
    ['הקמה', sectionLine('setup')],
    ['פירוק', sectionLine('teardown')],
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
            {has(PERM.EVENTS_DUPLICATE) && (
              <Button size="sm" onClick={() => void duplicate()}>
                <Copy size={ICON.sm} strokeWidth={STROKE} />
                שכפול
              </Button>
            )}
            {has(PERM.EVENTS_EDIT) && (
              <Button size="sm" variant="primary" onClick={() => setEditOpen(true)}>
                <Pencil size={ICON.sm} strokeWidth={STROKE} />
                עריכה
              </Button>
            )}
            {has(PERM.EVENTS_DELETE) && (
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

        {pricing && (
          <Card className="lg:col-span-1">
            <CardHeader
              title="תמחור"
              subtitle="המחיר שהלקוח משלם"
              icon={<Banknote size={ICON.md} strokeWidth={STROKE} />}
            />
            <CardBody>
              <dl className="divide-y divide-line-subtle">
                {pricing.rows.map((r) => (
                  <div key={r.id} className="flex items-start justify-between gap-3 py-2 first:pt-0">
                    <dt className="min-w-0 shrink type-caption text-ink-tertiary">
                      {r.label}
                      {r.isManual && <span className="ms-1.5 text-warning-text">ידני</span>}
                    </dt>
                    <dd dir="ltr" className="shrink-0 tabular-nums type-body font-medium">
                      {fmtMoney(r.price)}
                    </dd>
                  </div>
                ))}
                <div className="flex items-baseline justify-between gap-3 pt-2">
                  <dt className="type-body font-semibold">סך הכול</dt>
                  <dd dir="ltr" className="tabular-nums type-title font-semibold">
                    {fmtMoney(pricing.total)}
                  </dd>
                </div>
              </dl>
              {pricing.unpriced > 0 && (
                <p className="mt-2 type-caption text-ink-tertiary">
                  {pricing.unpriced} משימות ללא מחיר עדיין
                </p>
              )}
            </CardBody>
          </Card>
        )}

        <div className={pricing ? 'lg:col-span-3' : 'lg:col-span-2'}>
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
                {has(PERM.TASKS_CREATE) && (
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
                  has(PERM.TASKS_CREATE) && (
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

      {has(PERM.EVENTS_ACTIVITY_LOG) && <EventActivityLog eventId={event.id} />}

      <EventFormModal
        open={editOpen}
        onClose={() => {
          setEditOpen(false)
          void qc.invalidateQueries({ queryKey: ['events', 'one', id] })
          // the setup/teardown sections write onto the tasks below
          void qc.invalidateQueries({ queryKey: ['workboard', 'byEvent', id] })
          // and whatever the save moved has just been written to the log
          void qc.invalidateQueries({ queryKey: ['event_activity', id] })
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
    </div>
  )
}
