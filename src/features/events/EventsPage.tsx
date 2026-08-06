import { Suspense, lazy, useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import { FileSpreadsheet, ICON, Plus, STROKE } from '../../components/ui/icons'
import {
  Button,
  DataTable,
  EmptyState,
  FilterBar,
  PageHeader,
  SearchInput,
  Select,
  Spinner,
  StatusPill,
  Tooltip,
} from '../../components/ui'
import type { Column } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { useCustomers } from '../../lib/queries'
import { fmtDate } from '../../lib/dates'
import { EventFormModal } from './EventFormModal'
import { RequirePermission } from '../auth/guards'
import { PERM } from '../../lib/permissions'
import type { EventRow } from '../../types/domain'

/* ExcelJS is ~1MB — keep it out of the initial bundle and load it only when
   the import/export dialog is actually opened. */
const ExcelDialog = lazy(() => import('../importExport/ExcelDialog').then((m) => ({ default: m.ExcelDialog })))

export default function EventsPage() {
  const { has } = useAuth()
  const navigate = useNavigate()
  const [q, setQ] = useState('')
  const [customer, setCustomer] = useState('')
  const [createOpen, setCreateOpen] = useState(false)
  const [excelOpen, setExcelOpen] = useState(false)
  const { data: customers = [] } = useCustomers()

  const { data: events = [], isLoading, error, refetch } = useQuery({
    queryKey: ['events', 'list', q, customer],
    queryFn: async () => {
      let query = supabase
        .from('events')
        .select('*, customers(name, color), statuses(name, color)')
        .is('deleted_at', null)
        .order('event_date', { ascending: false })
        .limit(200)
      if (customer) query = query.eq('customer_id', customer)
      if (q.trim()) query = query.or(`end_client_name.ilike.%${q}%,event_number.ilike.%${q}%,location_text.ilike.%${q}%`)
      const { data, error } = await query
      if (error) throw error
      return data as EventRow[]
    },
  })

  const columns = useMemo<Column<EventRow>[]>(
    () => [
      {
        key: 'event_date',
        header: 'תאריך',
        width: 120,
        sticky: true,
        fixed: true,
        sortValue: (e) => e.event_date,
        render: (e) => (
          <Link
            to={`/events/${e.id}`}
            onClick={(ev) => ev.stopPropagation()}
            className="rounded font-medium tabular text-primary-text hover:underline"
          >
            {fmtDate(e.event_date)}
          </Link>
        ),
      },
      {
        key: 'customer',
        header: 'לקוח',
        width: 160,
        sortValue: (e) => e.customers?.name,
        render: (e) =>
          e.customers ? (
            <span className="flex items-center gap-1.5">
              <span className="size-2 shrink-0 rounded-full" style={{ background: e.customers.color }} />
              <span className="truncate">{e.customers.name}</span>
            </span>
          ) : (
            <span className="text-ink-tertiary">—</span>
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
      {
        key: 'volume_m',
        header: 'נפח',
        width: 80,
        align: 'end',
        sortValue: (e) => e.volume_m,
        render: (e) => <span className="tabular">{e.volume_m ?? '—'}</span>,
      },
      {
        key: 'truck_count',
        header: 'משאיות',
        width: 90,
        align: 'end',
        sortValue: (e) => e.truck_count,
        render: (e) => <span className="tabular">{e.truck_count ?? '—'}</span>,
      },
      {
        key: 'status',
        header: 'סטטוס',
        width: 130,
        sortValue: (e) => e.statuses?.name,
        render: (e) => (e.statuses ? <StatusPill color={e.statuses.color}>{e.statuses.name}</StatusPill> : null),
      },
    ],
    [],
  )

  const filtered = !!q || !!customer

  return (
    <RequirePermission perm={PERM.EVENTS_VIEW}>
      <div className="space-y-4">
        <PageHeader
          title="אירועים"
          subtitle={isLoading ? 'טוען...' : `${events.length} אירועים${filtered ? ' (מסונן)' : ''}`}
          actions={
            <>
              {(has(PERM.EVENTS_IMPORT) || has(PERM.EVENTS_EXPORT)) && (
                <Button size="sm" onClick={() => setExcelOpen(true)}>
                  <FileSpreadsheet size={ICON.sm} strokeWidth={STROKE} />
                  ייבוא / ייצוא
                </Button>
              )}
              {has(PERM.EVENTS_CREATE) && (
                <Button size="sm" variant="primary" onClick={() => setCreateOpen(true)}>
                  <Plus size={ICON.sm} strokeWidth={STROKE} />
                  אירוע חדש
                </Button>
              )}
            </>
          }
        >
          <FilterBar
            onReset={
              filtered
                ? () => {
                    setQ('')
                    setCustomer('')
                  }
                : undefined
            }
          >
            <SearchInput
              className="w-64 max-sm:w-full"
              inputSize="sm"
              placeholder="חיפוש לפי שם, מספר, מיקום..."
              value={q}
              onChange={(e) => setQ(e.target.value)}
              onClear={() => setQ('')}
              aria-label="חיפוש אירועים"
            />
            <Select className="w-48 max-sm:w-full" selectSize="sm" value={customer} onChange={(e) => setCustomer(e.target.value)} aria-label="סינון לפי לקוח">
              <option value="">כל הלקוחות</option>
              {customers.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </Select>
          </FilterBar>
        </PageHeader>

        <DataTable
          rows={events}
          columns={columns}
          getRowId={(e) => e.id}
          loading={isLoading}
          error={error}
          onRetry={() => void refetch()}
          onRowClick={(e) => navigate(`/events/${e.id}`)}
          storageKey="events"
          pageSize={25}
          defaultSort={{ key: 'event_date', dir: 'desc' }}
          mobileCard={(e) => (
            <div className="space-y-1">
              <div className="flex items-center gap-2">
                <span className="type-caption font-semibold tabular text-primary-text">{fmtDate(e.event_date)}</span>
                {e.event_number && <span className="type-caption tabular text-ink-tertiary">#{e.event_number}</span>}
                {e.statuses && (
                  <StatusPill color={e.statuses.color} className="ms-auto shrink-0">
                    {e.statuses.name}
                  </StatusPill>
                )}
              </div>
              <p className="truncate type-body font-semibold">{e.end_client_name || '—'}</p>
              <div className="flex flex-wrap items-center gap-x-2 type-caption text-ink-tertiary">
                {e.customers && (
                  <span className="inline-flex min-w-0 items-center gap-1">
                    <span className="size-2 shrink-0 rounded-full" style={{ background: e.customers.color }} />
                    <span className="truncate">{e.customers.name}</span>
                  </span>
                )}
                {e.truck_count != null && <span className="tabular">· {e.truck_count} משאיות</span>}
                {e.volume_m != null && <span className="tabular">· נפח {e.volume_m}</span>}
              </div>
              {e.location_text && <p className="truncate type-caption text-ink-tertiary">{e.location_text}</p>}
            </div>
          )}
          empty={
            <EmptyState
              art="calendar"
              title={filtered ? 'אין אירועים תואמים' : 'עדיין אין אירועים'}
              description={
                filtered
                  ? 'נסה לשנות את מונחי החיפוש או לבחור לקוח אחר'
                  : 'צור אירוע ראשון — משימות ההקמה והפירוק ייווצרו אוטומטית'
              }
              action={
                filtered ? (
                  <Button
                    size="sm"
                    onClick={() => {
                      setQ('')
                      setCustomer('')
                    }}
                  >
                    ניקוי סינון
                  </Button>
                ) : (
                  has(PERM.EVENTS_CREATE) && (
                    <Button size="sm" variant="primary" onClick={() => setCreateOpen(true)}>
                      <Plus size={ICON.sm} />
                      אירוע חדש
                    </Button>
                  )
                )
              }
            />
          }
        />

        <EventFormModal open={createOpen} onClose={() => setCreateOpen(false)} />
        {excelOpen && (
          <Suspense
            fallback={
              <div className="fixed inset-0 z-50 flex items-center justify-center scrim">
                <Spinner size={28} />
              </div>
            }
          >
            <ExcelDialog open onClose={() => setExcelOpen(false)} />
          </Suspense>
        )}
      </div>
    </RequirePermission>
  )
}
