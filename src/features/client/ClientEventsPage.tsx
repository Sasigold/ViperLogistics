import { useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import { ICON, Plus, STROKE } from '../../components/ui/icons'
import {
  Button,
  DataTable,
  EmptyState,
  FilterBar,
  PageHeader,
  SearchInput,
  StatusPill,
  Tooltip,
} from '../../components/ui'
import type { Column } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { fmtDate } from '../../lib/dates'
import { EventFormModal } from '../events/EventFormModal'
import { RequirePermission } from '../auth/guards'
import { PERM } from '../../lib/permissions'
import type { EventRow } from '../../types/domain'

/**
 * The client's own events. RLS already restricts the rows, so there is no
 * customer filter and no customer column — every row belongs to them.
 *
 * Deliberately not a variant of EventsPage: that screen carries the Excel
 * import/export dialog (a bulk create surface, plus ~1MB of ExcelJS) and links
 * into the staff event detail.
 */
export default function ClientEventsPage() {
  const { has, me, showsEventField } = useAuth()
  const navigate = useNavigate()
  const [q, setQ] = useState('')
  const [createOpen, setCreateOpen] = useState(false)

  const mayCreate = has(PERM.EVENTS_CREATE) && !!me?.customer?.can_create_events
  // resolved outside the memo so it depends on the values themselves —
  // showsEventField is a stable store function and would never invalidate
  const showVolume = showsEventField('volume_m')
  const showTrucks = showsEventField('truck_count')

  const { data: events = [], isLoading, error, refetch } = useQuery({
    queryKey: ['client', 'events', q],
    queryFn: async () => {
      let query = supabase
        .from('events')
        .select('*, statuses(name, color)')
        .is('deleted_at', null)
        .order('event_date', { ascending: false })
        .limit(200)
      if (q.trim())
        query = query.or(`end_client_name.ilike.%${q}%,event_number.ilike.%${q}%,location_text.ilike.%${q}%`)
      const { data, error } = await query
      if (error) throw error
      return data as EventRow[]
    },
  })

  const columns = useMemo<Column<EventRow>[]>(() => {
    const cols: Column<EventRow>[] = [
      {
        key: 'event_date',
        header: 'תאריך',
        width: 120,
        sticky: true,
        fixed: true,
        sortValue: (e) => e.event_date,
        render: (e) => (
          <Link
            to={`/client/events/${e.id}`}
            onClick={(ev) => ev.stopPropagation()}
            className="rounded font-medium tabular text-primary-text hover:underline"
          >
            {fmtDate(e.event_date)}
          </Link>
        ),
      },
      {
        key: 'end_client_name',
        header: 'לקוח האירוע',
        width: 180,
        sortValue: (e) => e.end_client_name,
        render: (e) => <span className="font-medium">{e.end_client_name || '—'}</span>,
      },
      {
        key: 'event_number',
        header: "מס' אירוע",
        width: 110,
        sortValue: (e) => e.event_number,
        render: (e) => <span className="tabular">{e.event_number || '—'}</span>,
      },
      {
        key: 'location_text',
        header: 'מיקום',
        width: 240,
        sortValue: (e) => e.location_text,
        render: (e) =>
          e.location_text ? (
            <Tooltip content={e.location_text}>
              <span className="block truncate">{e.location_text}</span>
            </Tooltip>
          ) : (
            <span className="text-ink-tertiary">—</span>
          ),
      },
    ]
    // the same two rules that shape the form shape the list: a field the
    // client's form never offered should not reappear as a column
    if (showVolume)
      cols.push({
        key: 'volume_m',
        header: 'נפח',
        width: 80,
        align: 'end',
        sortValue: (e) => e.volume_m,
        render: (e) => <span className="tabular">{e.volume_m ?? '—'}</span>,
      })
    if (showTrucks)
      cols.push({
        key: 'truck_count',
        header: 'משאיות',
        width: 90,
        align: 'end',
        sortValue: (e) => e.truck_count,
        render: (e) => <span className="tabular">{e.truck_count ?? '—'}</span>,
      })
    cols.push({
      key: 'status',
      header: 'סטטוס',
      width: 130,
      sortValue: (e) => e.statuses?.name,
      render: (e) => (e.statuses ? <StatusPill color={e.statuses.color}>{e.statuses.name}</StatusPill> : null),
    })
    return cols
  }, [showVolume, showTrucks])

  return (
    <RequirePermission perm={PERM.EVENTS_VIEW}>
      <div className="space-y-4">
        <PageHeader
          title="האירועים שלי"
          subtitle={isLoading ? 'טוען...' : `${events.length} אירועים${q ? ' (מסונן)' : ''}`}
          actions={
            mayCreate && (
              <Button size="sm" variant="primary" onClick={() => setCreateOpen(true)}>
                <Plus size={ICON.sm} strokeWidth={STROKE} />
                אירוע חדש
              </Button>
            )
          }
        >
          <FilterBar onReset={q ? () => setQ('') : undefined}>
            <SearchInput
              className="w-64 max-sm:w-full"
              inputSize="sm"
              placeholder="חיפוש לפי שם, מספר, מיקום..."
              value={q}
              onChange={(e) => setQ(e.target.value)}
              onClear={() => setQ('')}
              aria-label="חיפוש אירועים"
            />
          </FilterBar>
        </PageHeader>

        <DataTable
          rows={events}
          columns={columns}
          getRowId={(e) => e.id}
          loading={isLoading}
          error={error}
          onRetry={() => void refetch()}
          onRowClick={(e) => navigate(`/client/events/${e.id}`)}
          storageKey="client-events"
          pageSize={25}
          empty={
            <EmptyState
              art="calendar"
              title={mayCreate ? 'אין עדיין אירועים' : 'אין אירועים להצגה'}
              description={mayCreate ? 'לחיצה על "אירוע חדש" תפתח את טופס ההעלאה' : undefined}
            />
          }
        />

        {createOpen && <EventFormModal open onClose={() => setCreateOpen(false)} />}
      </div>
    </RequirePermission>
  )
}
