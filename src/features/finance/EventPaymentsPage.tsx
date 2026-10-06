import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router'
import { AlertTriangle, Banknote, HandCoins, ICON, Receipt as ReceiptIcon, STROKE, XCircle } from '../../components/ui/icons'
import {
  Badge,
  Button,
  Card,
  CardBody,
  DataTable,
  EmptyState,
  FilterBar,
  Input,
  Modal,
  PageHeader,
  SearchInput,
  SegmentedControl,
  StatCard,
  cx,
  fmtMoney,
} from '../../components/ui'
import type { Column } from '../../components/ui'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { fmtDate } from '../../lib/dates'
import type { EventPaymentRow } from '../../types/domain'
import { useEventPaymentsDashboard } from '../dashboard/dashboardQueries'
import { EventPaymentsCard } from './EventPaymentsCard'
import { useEventPaymentsList } from './eventPaymentQueries'
import {
  PRESET_LABELS,
  STATE_LABELS,
  STATE_TONES,
  matchesFilter,
  paymentState,
  presetRange,
  rangeError,
} from './eventPayments'
import type { PaymentFilter, RangePreset } from './eventPayments'

const FILTERS: { key: PaymentFilter; label: string }[] = [
  { key: 'all', label: 'הכול' },
  { key: 'open', label: 'פתוחים' },
  { key: 'unpaid', label: 'לא שולם' },
  { key: 'partial', label: 'חלקי' },
  { key: 'paid', label: 'שולם' },
]

const PRESETS: RangePreset[] = ['month', 'prev_month', 'quarter', 'year']

/**
 * תשלומי אירועים (0203): כל האירועים של לקוחות שהמודול פתוח להם, בטווח
 * תאריכי האירוע — כמה מגיע, כמה שולם, מה היתרה. לחיצה על שורה פותחת את
 * היסטוריית התשלומים של האירוע ואת "אוסף תשלום", אותו תוכן בדיוק כמו בדף
 * האירוע.
 *
 * פס הסיכום אינו נספר כאן אלא נשאל מ-`event_payments_dashboard` — אותה פונקציה
 * שמזינה את כרטיסי הדשבורד, כדי שהמסכים לא יסתרו זה את זה.
 */
export default function EventPaymentsPage() {
  const navigate = useNavigate()
  const [range, setRange] = useState(() => presetRange('month', new Date()))
  const [preset, setPreset] = useState<RangePreset | null>('month')
  const [filter, setFilter] = useState<PaymentFilter>('all')
  const [search, setSearch] = useState('')
  const [openRow, setOpenRow] = useState<EventPaymentRow | null>(null)

  const invalid = rangeError(range.from, range.to)
  const { data: rows = [], isLoading, error, refetch } = useEventPaymentsList(range.from, range.to, !invalid)
  const { data: summary } = useEventPaymentsDashboard(range.from, range.to, !invalid)

  const manyCustomers = useMemo(() => new Set(rows.map((r) => r.customer_id)).size > 1, [rows])

  const visible = useMemo(() => {
    const q = search.trim().toLowerCase()
    return rows.filter(
      (r) =>
        matchesFilter(Number(r.due), Number(r.paid), filter) &&
        (!q ||
          (r.end_client_name ?? '').toLowerCase().includes(q) ||
          (r.event_number ?? '').toLowerCase().includes(q) ||
          r.customer_name.toLowerCase().includes(q)),
    )
  }, [rows, filter, search])

  const pickPreset = (p: RangePreset) => {
    setPreset(p)
    setRange(presetRange(p, new Date()))
  }

  const columns: Column<EventPaymentRow>[] = [
    {
      key: 'event_date',
      header: 'תאריך',
      sticky: true,
      fixed: true,
      width: 110,
      render: (r) => <span className="tabular">{fmtDate(r.event_date)}</span>,
      sortValue: (r) => r.event_date,
    },
    {
      key: 'event',
      header: 'אירוע',
      minWidth: 180,
      render: (r) => (
        <span className="flex min-w-0 items-center gap-2">
          <span className={cx('truncate font-medium', r.cancelled && 'text-ink-tertiary line-through')}>
            {r.end_client_name || 'אירוע'}
          </span>
          {r.event_number && <span className="shrink-0 tabular type-caption text-ink-tertiary">#{r.event_number}</span>}
          {r.cancelled && <Badge tone="neutral">בוטל</Badge>}
        </span>
      ),
      sortValue: (r) => r.end_client_name ?? '',
    },
    ...(manyCustomers
      ? [
          {
            key: 'customer',
            header: 'לקוח',
            render: (r: EventPaymentRow) => (
              <span className="flex items-center gap-2">
                <span
                  className="size-2 shrink-0 rounded-full"
                  style={{ background: r.customer_color ?? '#8a93a5' }}
                  aria-hidden
                />
                <span className="truncate">{r.customer_name}</span>
              </span>
            ),
            sortValue: (r: EventPaymentRow) => r.customer_name,
          },
        ]
      : []),
    {
      key: 'due',
      header: 'מגיע',
      align: 'end',
      render: (r) => <span className="tabular">{fmtMoney(Number(r.due))}</span>,
      sortValue: (r) => Number(r.due),
    },
    {
      key: 'paid',
      header: 'שולם',
      align: 'end',
      render: (r) => <span className="tabular text-success-text">{fmtMoney(Number(r.paid))}</span>,
      sortValue: (r) => Number(r.paid),
    },
    {
      key: 'balance',
      header: 'יתרה',
      align: 'end',
      render: (r) => (
        <span
          className={cx(
            'tabular font-semibold',
            Number(r.balance) > 0 ? 'text-error-text' : Number(r.balance) < 0 ? 'text-info-text' : 'text-success-text',
          )}
        >
          {fmtMoney(Number(r.balance))}
        </span>
      ),
      sortValue: (r) => Number(r.balance),
    },
    {
      key: 'state',
      header: 'מצב',
      render: (r) => {
        const s = paymentState(Number(r.due), Number(r.paid))
        return <Badge tone={STATE_TONES[s]}>{STATE_LABELS[s]}</Badge>
      },
      sortValue: (r) => paymentState(Number(r.due), Number(r.paid)),
    },
    {
      key: 'last_paid_at',
      header: 'תשלום אחרון',
      render: (r) =>
        r.last_paid_at ? (
          <span className="tabular type-caption text-ink-secondary">
            {fmtDate(r.last_paid_at)}
            {r.payments_count > 1 && <span className="text-ink-tertiary"> · {r.payments_count} תשלומים</span>}
          </span>
        ) : (
          <span className="type-caption text-ink-tertiary">—</span>
        ),
      sortValue: (r) => r.last_paid_at ?? '',
    },
  ]

  return (
    <RequirePermission perm={PERM.FINANCE_EVENT_PAYMENTS_VIEW}>
      <div className="space-y-4">
        <PageHeader
          title="תשלומי אירועים"
          subtitle="כמה מגיע על כל אירוע, כמה שולם ומה נשאר — לפי תאריך האירוע"
        >
          <FilterBar>
            {/* גלילה ולא דחיסה: בטלפון חמש התוויות רחבות מהמסך */}
            <div className="max-w-full overflow-x-auto">
              <SegmentedControl<RangePreset | 'custom'>
                items={[
                  ...PRESETS.map((p) => ({ key: p, label: PRESET_LABELS[p] })),
                  { key: 'custom' as const, label: 'טווח' },
                ]}
                value={preset ?? 'custom'}
                onChange={(k) => (k === 'custom' ? setPreset(null) : pickPreset(k))}
              />
            </div>
            <div className="flex items-center gap-1.5">
              <Input
                type="date"
                aria-label="מתאריך"
                value={range.from}
                onChange={(e) => {
                  setPreset(null)
                  setRange((r) => ({ ...r, from: e.target.value }))
                }}
                className="w-40"
              />
              <span className="type-caption text-ink-tertiary">עד</span>
              <Input
                type="date"
                aria-label="עד תאריך"
                value={range.to}
                onChange={(e) => {
                  setPreset(null)
                  setRange((r) => ({ ...r, to: e.target.value }))
                }}
                className="w-40"
              />
            </div>
            <SearchInput
              placeholder="חיפוש לפי שם או מספר אירוע"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              onClear={() => setSearch('')}
              className="w-56"
            />
          </FilterBar>
        </PageHeader>

        {invalid && (
          <p className="flex items-center gap-2 rounded-lg border border-warning-border bg-warning-subtle px-3 py-2 type-caption text-warning-text">
            <AlertTriangle size={ICON.sm} strokeWidth={STROKE} />
            {invalid}
          </p>
        )}

        {summary && (
          <div className="grid gap-3 sm:grid-cols-3">
            <StatCard
              icon={<Banknote size={ICON.xl} strokeWidth={STROKE} />}
              label="סה״כ מגיע"
              value={fmtMoney(Number(summary.due))}
              tone="#a855f7"
              hint={`${summary.events} אירועים בטווח`}
            />
            <StatCard
              icon={<ReceiptIcon size={ICON.xl} strokeWidth={STROKE} />}
              label="שולם"
              value={fmtMoney(Number(summary.paid))}
              tone="#22c55e"
              hint={`${summary.paid_events} אירועים שולמו במלואם`}
            />
            <StatCard
              icon={<XCircle size={ICON.xl} strokeWidth={STROKE} />}
              label="עוד לא שולם"
              value={fmtMoney(Number(summary.unpaid))}
              tone="#ef4444"
              hint={`${summary.open_events} אירועים עם יתרה`}
            />
          </div>
        )}

        <Card>
          <div className="flex flex-wrap items-center gap-2 border-b border-line-subtle p-3">
            <div className="max-w-full overflow-x-auto">
              <SegmentedControl<PaymentFilter> items={FILTERS} value={filter} onChange={setFilter} />
            </div>
            <span className="ms-auto type-caption text-ink-tertiary">{visible.length} אירועים</span>
          </div>
          <CardBody padded={false}>
            <DataTable
              rows={invalid ? [] : visible}
              columns={columns}
              getRowId={(r) => r.event_id}
              loading={isLoading && !invalid}
              error={error}
              onRetry={() => void refetch()}
              onRowClick={setOpenRow}
              storageKey="event-payments"
              defaultSort={{ key: 'event_date', dir: 'asc' }}
              empty={
                <EmptyState
                  compact
                  art="table"
                  title={rows.length ? 'אין אירועים שעונים על הסינון' : 'אין אירועים בטווח'}
                  description={
                    rows.length
                      ? undefined
                      : 'מוצגים אירועים של לקוחות שתשלומי אירועים מופעלים אצלם (בכרטיס הלקוח)'
                  }
                />
              }
              mobileCard={(r) => {
                const s = paymentState(Number(r.due), Number(r.paid))
                return (
                  <div className="space-y-1.5">
                    <div className="flex items-center gap-2">
                      <span className="type-caption font-semibold tabular text-primary-text">
                        {fmtDate(r.event_date)}
                      </span>
                      {r.event_number && (
                        <span className="type-caption tabular text-ink-tertiary">#{r.event_number}</span>
                      )}
                      <Badge tone={STATE_TONES[s]} className="ms-auto shrink-0">
                        {STATE_LABELS[s]}
                      </Badge>
                    </div>
                    <p className="truncate type-body font-semibold">{r.end_client_name || 'אירוע'}</p>
                    <p className="flex flex-wrap gap-x-3 type-caption text-ink-secondary tabular">
                      <span>מגיע {fmtMoney(Number(r.due))}</span>
                      <span className="text-success-text">שולם {fmtMoney(Number(r.paid))}</span>
                      <span className={Number(r.balance) > 0 ? 'text-error-text' : ''}>
                        יתרה {fmtMoney(Number(r.balance))}
                      </span>
                    </p>
                  </div>
                )
              }}
            />
          </CardBody>
        </Card>

        <Modal
          open={!!openRow}
          onClose={() => setOpenRow(null)}
          size="lg"
          title={
            <span className="flex flex-wrap items-center gap-2">
              <HandCoins size={ICON.md} strokeWidth={STROKE} />
              {openRow?.end_client_name || 'אירוע'}
              {openRow?.event_number && (
                <span className="tabular type-caption text-ink-tertiary">#{openRow.event_number}</span>
              )}
            </span>
          }
          description={openRow ? `${fmtDate(openRow.event_date)} · ${openRow.customer_name}` : undefined}
          footer={
            openRow && (
              <>
                <Button className="me-auto" onClick={() => navigate(`/events/${openRow.event_id}`)}>
                  לדף האירוע
                </Button>
                <Button onClick={() => setOpenRow(null)}>סגירה</Button>
              </>
            )
          }
        >
          {openRow && <EventPaymentsCard eventId={openRow.event_id} bare />}
        </Modal>
      </div>
    </RequirePermission>
  )
}
