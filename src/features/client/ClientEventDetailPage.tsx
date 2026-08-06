import { useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import { ICON, Pencil, STROKE } from '../../components/ui/icons'
import {
  Button,
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  PageHeader,
  SkeletonCard,
  SkeletonList,
  StatusPill,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { fmtDate, fmtDateLong, fmtHours, fmtTime } from '../../lib/dates'
import { EventFormModal } from '../events/EventFormModal'
import { RequirePermission } from '../auth/guards'
import { PERM } from '../../lib/permissions'
import type { EventRow, WorkBoardRow } from '../../types/domain'

/**
 * Read-mostly view of one event plus its tasks. The staff EventDetailPage is
 * not reused: three of its task columns (team, lead, contractor) resolve to
 * empty for a client because work_board_view is security_invoker and the joins
 * are RLS-nulled, and its row click opens TaskDrawer — a staff editor whose
 * save fails for clients and which reads contractor pricing.
 */
export default function ClientEventDetailPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { has, showsEventField } = useAuth()
  const [editOpen, setEditOpen] = useState(false)

  const { data, isLoading } = useQuery({
    queryKey: ['client', 'event', id],
    queryFn: async () => {
      const [e, contact, sup] = await Promise.all([
        supabase.from('events').select('*, statuses(name, color)').eq('id', id).single(),
        supabase.from('event_contacts').select('*').eq('event_id', id).maybeSingle(),
        supabase.from('event_suppliers').select('supplier_id, suppliers(name)').eq('event_id', id),
      ])
      if (e.error) throw e.error
      return {
        event: e.data as EventRow,
        // RLS returns no row when the contact field is not visible to this user
        contact: contact.data as { contact_name: string | null; contact_phone: string | null } | null,
        suppliers: (sup.data ?? []) as unknown as { supplier_id: string; suppliers: { name: string } }[],
      }
    },
  })

  const { data: tasks = [], isLoading: loadingTasks } = useQuery({
    queryKey: ['client', 'event', id, 'tasks'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('work_board_view')
        .select('*')
        .eq('event_id', id)
        .order('task_date')
      if (error) throw error
      return data as WorkBoardRow[]
    },
  })

  if (isLoading) return <SkeletonCard lines={6} />
  if (!data)
    return (
      <Card>
        <EmptyState art="alert" title="האירוע לא נמצא" description="ייתכן שהאירוע נמחק או שאינו שייך אליך" />
      </Card>
    )

  const { event, contact, suppliers } = data
  const show = showsEventField

  return (
    <RequirePermission perm={PERM.EVENTS_VIEW}>
      <div className="space-y-4">
        <PageHeader
          title={event.end_client_name || 'אירוע'}
          subtitle={fmtDateLong(event.event_date)}
          actions={
            <>
              <Button size="sm" onClick={() => navigate('/client/events')}>
                חזרה לרשימה
              </Button>
              {has(PERM.EVENTS_EDIT) && (
                <Button size="sm" variant="primary" onClick={() => setEditOpen(true)}>
                  <Pencil size={ICON.sm} strokeWidth={STROKE} />
                  עריכה
                </Button>
              )}
            </>
          }
        />

        <Card>
          <CardHeader
            title="פרטי האירוע"
            subtitle={event.statuses ? undefined : 'ללא סטטוס'}
            actions={event.statuses && <StatusPill color={event.statuses.color}>{event.statuses.name}</StatusPill>}
          />
          <CardBody>
            <dl className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              <Fact label="תאריך" value={fmtDate(event.event_date)} />
              {show('event_number') && <Fact label="מספר אירוע" value={event.event_number || '—'} />}
              {show('location') && <Fact label="מיקום" value={event.location_text || '—'} />}
              {show('location_notes') && <Fact label="הערות למיקום" value={event.location_notes || '—'} />}
              {show('volume_m') && <Fact label="נפח במטר" value={event.volume_m != null ? String(event.volume_m) : '—'} />}
              {show('truck_count') && (
                <Fact label="כמות משאיות" value={event.truck_count != null ? String(event.truck_count) : '—'} />
              )}
              {contact && show('contact_phone') && (
                <>
                  <Fact label="איש קשר" value={contact.contact_name || '—'} />
                  <Fact label="טלפון" value={contact.contact_phone || '—'} ltr />
                </>
              )}
              {show('notes') && <Fact label="הערות" value={event.notes || '—'} />}
              {show('addons') && (
                <Fact
                  label="תוספות"
                  value={
                    [event.no_parking && 'אין חניה', event.porterage && 'סבלות', event.supplier_pickup && 'איסוף מספקים']
                      .filter(Boolean)
                      .join(' · ') || '—'
                  }
                />
              )}
              {suppliers.length > 0 && (
                <Fact label="ספקים לאיסוף" value={suppliers.map((s) => s.suppliers?.name).filter(Boolean).join(', ')} />
              )}
            </dl>
          </CardBody>
        </Card>

        <Card>
          <CardHeader title="משימות האירוע" subtitle={loadingTasks ? 'טוען...' : `${tasks.length} משימות`} />
          <CardBody padded={false}>
            {loadingTasks ? (
              <div className="p-4">
                <SkeletonList rows={2} />
              </div>
            ) : tasks.length === 0 ? (
              <EmptyState art="calendar" title="אין משימות" description="משימות ההקמה והפירוק ייווצרו אוטומטית" />
            ) : (
              <ul>
                {tasks.map((t) => (
                  <li
                    key={t.id}
                    className="flex flex-wrap items-center gap-x-3 gap-y-1 border-b border-line-subtle px-4 py-3 last:border-0"
                  >
                    <span className="type-body font-medium">{t.title || t.task_type_name}</span>
                    <StatusPill color={t.status_color}>{t.status_name}</StatusPill>
                    <span className="tabular type-caption text-ink-tertiary">{fmtDate(t.task_date)}</span>
                    {t.onsite_start_time && (
                      <span className="tabular type-caption text-ink-tertiary" dir="ltr">
                        {fmtTime(t.onsite_start_time)}
                      </span>
                    )}
                    {t.hours_count != null && (
                      <span className="type-caption text-ink-tertiary">{fmtHours(t.hours_count)}</span>
                    )}
                    {t.execution_method_name && (
                      <span className="type-caption text-ink-tertiary">· {t.execution_method_name}</span>
                    )}
                  </li>
                ))}
              </ul>
            )}
          </CardBody>
        </Card>

        {editOpen && (
          <EventFormModal open onClose={() => setEditOpen(false)} event={event} contact={contact} supplierIds={suppliers.map((s) => s.supplier_id)} />
        )}
      </div>
    </RequirePermission>
  )
}

function Fact({ label, value, ltr }: { label: string; value: string; ltr?: boolean }) {
  return (
    <div className="min-w-0">
      <dt className="type-caption text-ink-tertiary">{label}</dt>
      <dd className={ltr ? 'mt-0.5 type-body font-medium tabular' : 'mt-0.5 type-body font-medium'} dir={ltr ? 'ltr' : undefined}>
        {value}
      </dd>
    </div>
  )
}
