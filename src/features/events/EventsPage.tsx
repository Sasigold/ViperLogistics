import { Suspense, useMemo, useState } from 'react'
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
  Switch,
  Tooltip,
} from '../../components/ui'
import type { Column } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { useCustomFormFields, useCustomers, useStatuses } from '../../lib/queries'
import { fmtDate } from '../../lib/dates'
import { shortAddress } from '../../lib/address'
import { EventFormModal } from './EventFormModal'
import { formatCustomValue } from './CustomFieldInput'
import { RequirePermission } from '../auth/guards'
import { PERM } from '../../lib/permissions'
import { lazyPage } from '../../lib/lazyPage'
import type { EventRow } from '../../types/domain'

/**
 * שורת הרשימה. ‏`EventRow.statuses` נושא שם וצבע בלבד — כאן צריך גם את
 * ה-`code`, כי הוא הזהות היציבה של "בוטל" (השם ניתן לעריכה בהגדרות). אותה
 * הכרעה, ומאותו נימוק, כמו `CalEvent` בלוח השנה.
 */
type EventListRow = EventRow & { statuses: { name: string; color: string; code: string | null } | null }

/** הסטטוס שהרשימה מסתירה כברירת מחדל. מזוהה ב-`code` ולא בשם. */
const CANCELLED = 'cancelled'

/* ExcelJS is ~1MB — keep it out of the initial bundle and load it only when
   the import/export dialog is actually opened. */
const ExcelDialog = lazyPage(() => import('../importExport/ExcelDialog').then((m) => ({ default: m.ExcelDialog })))

export default function EventsPage() {
  const { me, has, canCreateEvent, showsEventField } = useAuth()
  const navigate = useNavigate()
  const [q, setQ] = useState('')
  const [customer, setCustomer] = useState('')
  const [createOpen, setCreateOpen] = useState(false)
  const [excelOpen, setExcelOpen] = useState(false)
  /* אירוע שבוטל אינו עבודה שתקרה, והרשימה היא רשימת עבודה — הוא נשאר במקומו
     ובהיסטוריה שלו, ואינו מוצג עד שמבקשים אותו. אותו הסדר של לוח השנה. */
  const [showCancelled, setShowCancelled] = useState(false)
  const { data: customers = [] } = useCustomers()
  const { data: statuses = [] } = useStatuses('event')
  const cancelledStatus = statuses.find((s) => s.code === CANCELLED)

  const { data: events = [], isLoading, error, refetch } = useQuery({
    queryKey: ['events', 'list', q, customer, showCancelled, cancelledStatus?.id ?? null],
    queryFn: async () => {
      let query = supabase
        .from('events')
        .select('*, customers(name, color), statuses(name, color, code)')
        .is('deleted_at', null)
        .order('event_date', { ascending: false })
        .limit(200)
      if (customer) query = query.eq('customer_id', customer)
      /* בשרת ולא בלקוח: לשאילתה יש תקרה של 200 שורות, וסינון אחרי החזרה היה
         מבזבז ממנה מקומות על אירועים שאיש לא יראה. ‏`is.null` בתוך ה-`or`
         כי `status_id <> x` הוא NULL לאירוע בלי סטטוס — והוא היה נופל. */
      if (!showCancelled && cancelledStatus)
        query = query.or(`status_id.is.null,status_id.neq.${cancelledStatus.id}`)
      if (q.trim()) query = query.or(`end_client_name.ilike.%${q}%,event_number.ilike.%${q}%,location_text.ilike.%${q}%`)
      const { data, error } = await query
      if (error) throw error
      return data as EventListRow[]
    },
  })

  /* חגורה שנייה על אותה הכרעה: תשובה מה-cache יכולה להגיע לפני שרשימת
     הסטטוסים נטענה, וכשהיא נטענת השאילתה ממילא נשאלת מחדש. */
  const visible = useMemo(
    () => (showCancelled ? events : events.filter((e) => e.statuses?.code !== CANCELLED)),
    [events, showCancelled],
  )

  /* Two rules shape the table, and they are the same two that shape the form:
     a field the reader's company configured off should not reappear as a
     column, and neither should one their field permissions hide. Resolved out
     here so the memo depends on the answers rather than on the store function,
     which is stable and would never invalidate. */
  const showCustomer = customers.length > 1
  const showNumber = showsEventField('event_number')
  const showLocation = showsEventField('location')
  const showVolume = showsEventField('volume_m')
  const showTrucks = showsEventField('truck_count')

  /* Custom fields belong to one customer, so they only become columns once
     the table is narrowed to one — either by the filter, or because the
     reader is bound to a company. Across all customers they would be a wall
     of empty cells, one group per company. */
  const scopedCustomer = me?.profile.customer_id ?? customer ?? null
  const { data: customFields } = useCustomFormFields(scopedCustomer || null)

  const columns = useMemo<Column<EventListRow>[]>(() => {
    const hidden = new Set<string>()
    if (!showCustomer) hidden.add('customer')
    if (!showNumber) hidden.add('event_number')
    if (!showLocation) hidden.add('location_text')
    if (!showVolume) hidden.add('volume_m')
    if (!showTrucks) hidden.add('truck_count')
    const all: Column<EventListRow>[] = [
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
              <span className="block truncate">{shortAddress(e.location_text)}</span>
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
      ...customFields
        .filter((f) => showsEventField(f.field_key))
        .map<Column<EventListRow>>((f) => ({
          key: f.field_key,
          header: f.label_he,
          width: 140,
          sortValue: (e) => formatCustomValue(f, e.custom_fields?.[f.field_key]) || undefined,
          render: (e) => {
            const v = formatCustomValue(f, e.custom_fields?.[f.field_key])
            return v ? <span className="block truncate">{v}</span> : <span className="text-ink-tertiary">—</span>
          },
        })),
    ]
    return all.filter((c) => !hidden.has(c.key))
  }, [showCustomer, showNumber, showLocation, showVolume, showTrucks, customFields, showsEventField])

  const filtered = !!q || !!customer || showCancelled

  return (
    <RequirePermission perm={PERM.EVENTS_VIEW}>
      <div className="space-y-4">
        <PageHeader
          title="אירועים"
          subtitle={isLoading ? 'טוען...' : `${visible.length} אירועים${filtered ? ' (מסונן)' : ''}`}
          actions={
            <>
              {(has(PERM.EVENTS_IMPORT) || has(PERM.EVENTS_EXPORT)) && (
                <Button size="sm" onClick={() => setExcelOpen(true)}>
                  <FileSpreadsheet size={ICON.sm} strokeWidth={STROKE} />
                  ייבוא / ייצוא
                </Button>
              )}
              {canCreateEvent() && (
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
                    setShowCancelled(false)
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
            {showCustomer && (
              <Select className="w-48 max-sm:w-full" selectSize="sm" value={customer} onChange={(e) => setCustomer(e.target.value)} aria-label="סינון לפי לקוח">
                <option value="">כל הלקוחות</option>
                {customers.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </Select>
            )}
            {cancelledStatus && (
              <Switch
                checked={showCancelled}
                onChange={setShowCancelled}
                label={`הצגת אירועים בסטטוס "${cancelledStatus.name}"`}
              />
            )}
          </FilterBar>
        </PageHeader>

        <DataTable
          rows={visible}
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
                {showNumber && e.event_number && (
                  <span className="type-caption tabular text-ink-tertiary">#{e.event_number}</span>
                )}
                {e.statuses && (
                  <StatusPill color={e.statuses.color} className="ms-auto shrink-0">
                    {e.statuses.name}
                  </StatusPill>
                )}
              </div>
              <p className="truncate type-body font-semibold">{e.end_client_name || '—'}</p>
              <div className="flex flex-wrap items-center gap-x-2 type-caption text-ink-tertiary">
                {showCustomer && e.customers && (
                  <span className="inline-flex min-w-0 items-center gap-1">
                    <span className="size-2 shrink-0 rounded-full" style={{ background: e.customers.color }} />
                    <span className="truncate">{e.customers.name}</span>
                  </span>
                )}
                {showTrucks && e.truck_count != null && <span className="tabular">· {e.truck_count} משאיות</span>}
                {showVolume && e.volume_m != null && <span className="tabular">· נפח {e.volume_m}</span>}
              </div>
              {showLocation && e.location_text && (
                <p className="truncate type-caption text-ink-tertiary">{shortAddress(e.location_text)}</p>
              )}
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
                  canCreateEvent() && (
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
