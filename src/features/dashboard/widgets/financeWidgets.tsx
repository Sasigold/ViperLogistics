import type { ComponentType, ReactNode } from 'react'
import { Bar, BarChart, Cell, Legend, Line, ComposedChart, Tooltip as RTooltip, XAxis, YAxis } from 'recharts'
import {
  Card,
  CardBody,
  CardHeader,
  DataTable,
  EmptyState,
  ProgressBar,
  SkeletonCard,
  StatCard,
  Tooltip,
  fmtMoney,
} from '../../../components/ui'
import type { Column } from '../../../components/ui'
import { AlertTriangle, Banknote, HardHat, ICON, Info, STROKE, Wallet } from '../../../components/ui/icons'
import { fmtDate } from '../../../lib/dates'
import { ChartTooltip } from '../parts/ChartTooltip'
import { ChartFrame } from '../parts/ChartFrame'
import { useDashboard, useSection } from '../dashboardContext'
import { useDashboardStats } from '../dashboardQueries'
import type { WidgetProps } from '../dashboardTypes'

const AXIS = { tick: { fontSize: 11, fill: 'var(--vl-text-tertiary)' }, axisLine: false, tickLine: false } as const
const shekel = (v: number) => fmtMoney(v)

/* ===== shapes the server sends ============================================ */

interface Payroll {
  total: number
  bonus: number
  paid_hours: number
  overtime_hours: number
  actual_hours: number
  shifts: number
  workers: number
  unrated_shifts: number
  pending_shifts: number
  pending_hours: number
}

interface ContractorCost {
  expected: number
  paid: number
  unpaid: number
  unpaid_rows: number
  zero_rows: number
  rows: number
  aging: { d0_30: number; d31_60: number; d60: number }
}

interface Margin {
  revenue: number
  contractor: number
  payroll: number
  gross: number
  pct: number | null
  unrated_shifts: number
}

/* ===== a KPI backed by a section ==========================================
   `statKpi` reads dashboard_stats; this reads a section. Same tile, different
   source — and the same rule about null, which is why it is a factory and not
   twelve copies.                                                            */

export function sectionKpi<T>(cfg: {
  section: string
  /**
   * מחרוזת, או פונקציה של הנתון.
   *
   * ‏0143 הביא את המקרה שדרש את זה: אותו סכום בדיוק הוא "סכום לתשלום לוייפר"
   * ללקוח שמבצע בעצמו, ו"סכום כולל של האירועים" ללקוח שמביא עבודה ומקבל
   * עליה עמלה. הכרטיס זהה ורק המילים משתנות, ולכן זו כותרת ולא ווידג׳ט שני
   * — והקונפיגורציה של הלקוח היא שמכריעה, לא שמו.
   */
  label: string | ((v: T) => string)
  icon: ComponentType<{ size?: number; strokeWidth?: number }>
  select: (v: T) => number | null | undefined
  format?: (v: number) => ReactNode
  tone?: string
  invertDelta?: boolean
  delta?: boolean
  hint?: (v: T) => ReactNode
}): ComponentType<WidgetProps> {
  function SectionKpi(_props: WidgetProps) {
    const { data, prev, isLoading } = useSection<T>(cfg.section)
    if (isLoading && data === undefined) return <SkeletonCard lines={0} />
    // null = the reader holds no key for this section
    if (data === null || data === undefined) return null

    const value = cfg.select(data)
    if (value === null || value === undefined) return null
    const before = cfg.delta && prev ? cfg.select(prev) : null
    const Icon = cfg.icon
    const label = typeof cfg.label === 'function' ? cfg.label(data) : cfg.label

    return (
      <StatCard
        icon={<Icon size={ICON.xl} strokeWidth={STROKE} />}
        label={label}
        value={cfg.format ? cfg.format(value) : value}
        tone={cfg.tone}
        invertDelta={cfg.invertDelta}
        delta={before === null || before === undefined ? null : Math.round((value - before) * 100) / 100}
        hint={cfg.hint?.(data)}
      />
    )
  }
  SectionKpi.displayName = `SectionKpi(${cfg.section})`
  return SectionKpi
}

/* ===== payroll ============================================================
   Every payroll figure carries the same two caveats, so they are rendered as
   hints rather than left to a tooltip nobody opens: the number counts approved
   shifts only, and a shift with no hourly rate is not counted at all.       */

function payrollCaveat(p: Payroll): ReactNode {
  const notes: string[] = []
  if (p.unrated_shifts > 0) notes.push(`${p.unrated_shifts} משמרות ללא תעריף אינן נספרות`)
  if (p.pending_shifts > 0) notes.push(`${p.pending_shifts} ממתינות לאישור`)
  return notes.length ? notes.join(' · ') : 'מאושרות בלבד'
}

export const PayrollTotalWidget = sectionKpi<Payroll>({
  section: 'cost.payroll',
  label: 'עלות שכר',
  icon: Wallet,
  tone: '#8b5cf6',
  delta: true,
  select: (p) => Number(p.total),
  format: shekel,
  hint: payrollCaveat,
})

export const PayrollOvertimeWidget = sectionKpi<Payroll>({
  section: 'cost.payroll',
  label: 'שעות נוספות',
  icon: AlertTriangle,
  tone: '#f59e0b',
  select: (p) => Number(p.overtime_hours),
  hint: (p) => `מתוך ${p.paid_hours} שעות לתשלום`,
})

export const PayrollBonusWidget = sectionKpi<Payroll>({
  section: 'cost.payroll',
  label: 'בונוסים',
  icon: Banknote,
  tone: '#22c55e',
  select: (p) => Number(p.bonus),
  format: shekel,
  hint: () => 'כלול בעלות השכר, לא נוסף עליה',
})

export const HoursTotalWidget = sectionKpi<{ actual_hours: number; shifts: number; workers: number }>({
  section: 'attendance.hours',
  label: 'שעות עבודה',
  icon: Wallet,
  tone: '#0ea5e9',
  delta: true,
  select: (h) => Number(h.actual_hours),
  hint: (h) => `${h.shifts} משמרות · ${h.workers} עובדים`,
})

/* ===== contractor cost ==================================================== */

export const ContractorCostWidget = sectionKpi<ContractorCost>({
  section: 'cost.contractor',
  label: 'עלות קבלנים',
  icon: HardHat,
  tone: '#f59e0b',
  delta: true,
  select: (c) => Number(c.expected),
  format: shekel,
  hint: (c) => `שולם ${fmtMoney(Number(c.paid))}`,
})

export const ContractorUnpaidWidget = sectionKpi<ContractorCost>({
  section: 'cost.contractor',
  label: 'יתרה לקבלנים',
  icon: Wallet,
  tone: '#ef4444',
  invertDelta: true,
  delta: true,
  select: (c) => Number(c.unpaid),
  format: shekel,
  // `price` is not null default 0, so a sum alone cannot tell "no price
  // agreed" from "agreed nothing". The row count is what makes them different.
  hint: (c) =>
    c.zero_rows > 0
      ? `${c.unpaid_rows} משימות · ${c.zero_rows} ללא מחיר שסוכם`
      : `${c.unpaid_rows} משימות ממתינות`,
})

export function ContractorAgingWidget({ height }: WidgetProps) {
  const { data, isLoading } = useSection<ContractorCost>('cost.contractor')
  if (data === null) return null

  const aging = data?.aging
  const rows = aging
    ? [
        { name: 'עד 30 יום', value: Number(aging.d0_30), color: '#22c55e' },
        { name: '31–60', value: Number(aging.d31_60), color: '#f59e0b' },
        { name: 'מעל 60', value: Number(aging.d60), color: '#ef4444' },
      ]
    : []
  const total = rows.reduce((s, r) => s + r.value, 0)

  return (
    <Card>
      <CardHeader title="יתרה לקבלנים לפי התיישנות" subtitle={total ? fmtMoney(total) : undefined} />
      <CardBody>
        {isLoading && !data ? (
          <div style={{ height }} />
        ) : total === 0 ? (
          <EmptyState compact art="check" title="אין יתרה פתוחה" />
        ) : (
          <div className="space-y-2.5">
            {rows.map((r) => (
              <ProgressBar
                key={r.name}
                value={r.value}
                max={total}
                color={r.color}
                label={r.name}
                hint={fmtMoney(r.value)}
              />
            ))}
          </div>
        )}
      </CardBody>
    </Card>
  )
}

/* ===== gross margin =======================================================
   Named "רווח גולמי" and not "רווח והפסד", because there is no expenses
   table, no overheads, no VAT and no receipts anywhere in the schema. The
   disclosure sits on the card rather than in a tooltip: a number this easy to
   misread should carry its own limits.                                      */

const MARGIN_NOTE =
  'הכנסות מתומחרות פחות עלות קבלנים ועלות שכר מאושרת. ' +
  'אינו כולל תקורה, שכר מנהלה, רכב, ביטוח, פחת, מע״מ ותשלומים שלא נגבו. ' +
  'ההכנסה מיוחסת לתאריך המשימה, ועלות השכר לתאריך המשמרת.'

export function GrossMarginWidget(_props: WidgetProps) {
  const { data, prev, isLoading } = useSection<Margin>('margin.summary')
  if (isLoading && data === undefined) return <SkeletonCard lines={2} />
  if (data === null || data === undefined) return null

  const gross = Number(data.gross)
  const before = prev ? Number(prev.gross) : null
  const lines = [
    { label: 'הכנסות', value: Number(data.revenue), tone: 'text-success-text' },
    { label: 'עלות קבלנים', value: -Number(data.contractor), tone: 'text-ink-secondary' },
    { label: 'עלות שכר', value: -Number(data.payroll), tone: 'text-ink-secondary' },
  ]

  return (
    <Card>
      <CardHeader
        title="רווח גולמי"
        subtitle="אינו כולל תקורה"
        actions={
          <Tooltip content={<span className="block max-w-xs">{MARGIN_NOTE}</span>}>
            <span className="text-ink-tertiary" aria-label="מה נכלל בחישוב">
              <Info size={ICON.md} strokeWidth={STROKE} />
            </span>
          </Tooltip>
        }
      />
      <CardBody>
        <div className="flex items-baseline gap-2">
          <span className="type-display tabular leading-none">{fmtMoney(gross)}</span>
          {data.pct !== null && (
            <span className="type-body tabular text-ink-tertiary">{Number(data.pct).toFixed(1)}%</span>
          )}
        </div>
        {before !== null && (
          <p className="mt-1 type-caption text-ink-tertiary">
            מול {fmtMoney(before)} בתקופה הקודמת
          </p>
        )}

        <ul className="mt-4 space-y-1.5">
          {lines.map((l) => (
            <li key={l.label} className="flex items-center justify-between type-body">
              <span className="text-ink-secondary">{l.label}</span>
              <span className={`tabular ${l.tone}`}>{fmtMoney(l.value)}</span>
            </li>
          ))}
        </ul>

        {data.unrated_shifts > 0 && (
          <p className="mt-3 rounded-md bg-warning-subtle px-2 py-1.5 type-caption text-warning-text">
            {data.unrated_shifts} משמרות ללא תעריף אינן נספרות בעלות השכר
          </p>
        )}
      </CardBody>
    </Card>
  )
}

export function MarginTrendWidget({ height }: WidgetProps) {
  const { data, isLoading } = useSection<{ bucket: string; revenue: number; contractor: number; payroll: number; gross: number }[]>(
    'margin.trend',
  )
  if (data === null) return null

  return (
    <ChartFrame
      title="הכנסות מול עלויות לאורך זמן"
      subtitle="עמודות = הכנסה ועלויות · קו = רווח גולמי"
      loading={isLoading && !data}
      empty={!data?.length}
      height={height}
    >
      <ComposedChart data={data ?? []} margin={{ top: 8, right: 8, bottom: 4, left: -12 }}>
        <XAxis dataKey="bucket" {...AXIS} tickFormatter={(v: string) => fmtDate(v)} />
        <YAxis {...AXIS} width={64} tickFormatter={(v: number) => String(Math.round(v / 1000)) + 'k'} />
        <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip />} />
        <Legend wrapperStyle={{ fontSize: 11 }} />
        <Bar dataKey="revenue" name="הכנסות" fill="#1fa189" radius={[4, 4, 0, 0]} maxBarSize={28} />
        <Bar dataKey="contractor" name="קבלנים" stackId="cost" fill="#f59e0b" maxBarSize={28} />
        <Bar dataKey="payroll" name="שכר" stackId="cost" fill="#8b5cf6" radius={[4, 4, 0, 0]} maxBarSize={28} />
        <Line type="monotone" dataKey="gross" name="רווח גולמי" stroke="var(--vl-primary)" strokeWidth={2} dot={false} />
      </ComposedChart>
    </ChartFrame>
  )
}

/* ===== margin by customer =================================================
   The one place the shift↔task grain mismatch has to be faced. Payroll is
   allocated across the tasks a shift names, which is an estimate — so the
   card says so, shows what could not be allocated, and refuses to print a
   percentage once that share is big enough to make one misleading.          */

interface MarginByCustomer {
  rows: { name: string; color: string; revenue: number; contractor: number; payroll: number }[]
  unallocated: number
  allocated: number
}

export function MarginByCustomerWidget(_props: WidgetProps) {
  const { data, isLoading } = useSection<MarginByCustomer>('margin.by_customer')
  if (data === null) return null

  const rows = (data?.rows ?? []).map((r) => ({
    ...r,
    gross: Number(r.revenue) - Number(r.contractor) - Number(r.payroll),
  }))
  const totalPayroll = Number(data?.allocated ?? 0) + Number(data?.unallocated ?? 0)
  const unallocatedShare = totalPayroll > 0 ? Number(data?.unallocated ?? 0) / totalPayroll : 0
  // an estimate this rough should not be dressed up as a percentage
  const showPct = unallocatedShare <= 0.25

  const columns: Column<(typeof rows)[number]>[] = [
    {
      key: 'name',
      header: 'לקוח',
      sticky: true,
      render: (r) => (
        <span className="flex items-center gap-2">
          <span className="size-2 shrink-0 rounded-full" style={{ background: r.color }} aria-hidden />
          <span className="truncate">{r.name}</span>
        </span>
      ),
      sortValue: (r) => r.name,
    },
    { key: 'revenue', header: 'הכנסות', align: 'end', render: (r) => fmtMoney(Number(r.revenue)), sortValue: (r) => Number(r.revenue) },
    { key: 'contractor', header: 'קבלנים', align: 'end', render: (r) => fmtMoney(Number(r.contractor)), sortValue: (r) => Number(r.contractor) },
    { key: 'payroll', header: 'שכר (משוער)', align: 'end', render: (r) => fmtMoney(Number(r.payroll)), sortValue: (r) => Number(r.payroll) },
    {
      key: 'gross',
      header: 'רווח גולמי',
      align: 'end',
      render: (r) => (
        <span className={r.gross < 0 ? 'text-error-text' : 'text-success-text'}>{fmtMoney(r.gross)}</span>
      ),
      sortValue: (r) => r.gross,
    },
    ...(showPct
      ? [
          {
            key: 'pct',
            header: '%',
            align: 'end' as const,
            render: (r: (typeof rows)[number]) =>
              Number(r.revenue) > 0 ? `${((r.gross / Number(r.revenue)) * 100).toFixed(1)}%` : '—',
          },
        ]
      : []),
  ]

  return (
    <Card>
      <CardHeader
        title="רווח גולמי לפי לקוח"
        subtitle="עלות השכר מוקצית למשימות לפי שעות — הערכה"
      />
      <CardBody padded={false}>
        <DataTable
          rows={rows}
          columns={columns}
          getRowId={(r) => r.name}
          loading={isLoading && !data}
          dense
          empty={<EmptyState compact art="table" title="אין נתונים בטווח" />}
        />
      </CardBody>
      {Number(data?.unallocated ?? 0) > 0 && (
        <div className="border-t border-line-subtle px-4 py-2.5">
          <p className="type-caption text-ink-tertiary">
            {fmtMoney(Number(data!.unallocated))} עלות שכר לא שויכה ללקוח — משמרות מחסן ודיווחים ידניים
            {!showPct && ' · אחוזי הרווח מוסתרים כי החלק הלא-משויך גדול מדי'}
          </p>
        </div>
      )}
    </Card>
  )
}

/* ===== revenue quality ====================================================
   The quietest way this system loses money: a task with no pricing row is
   absent from every total, so "revenue in range" looks plausible exactly when
   it is incomplete.                                                         */

interface PricingQuality {
  total: number
  unpriced: number
  manual: number
  auto: number
  unpriced_list: { id: string; task_date: string; label: string }[]
}

export function UnpricedTasksWidget(_props: WidgetProps) {
  const { data, isLoading } = useSection<PricingQuality>('pricing.quality')
  if (isLoading && data === undefined) return <SkeletonCard lines={0} />
  if (data === null || data === undefined) return null

  return (
    <StatCard
      icon={<AlertTriangle size={ICON.xl} strokeWidth={STROKE} />}
      label="משימות ללא תמחור"
      value={data.unpriced}
      tone={data.unpriced > 0 ? '#f59e0b' : '#22c55e'}
      hint={data.unpriced > 0 ? `מתוך ${data.total} משימות בטווח — אינן בסך ההכנסות` : 'כל המשימות מתומחרות'}
    />
  )
}

export function PayrollByWorkerWidget({ height }: WidgetProps) {
  const { data, isLoading } = useSection<{ name: string; total: number; hours: number }[]>('cost.payroll_by_worker')
  if (data === null) return null

  return (
    <ChartFrame title="עלות שכר לפי עובד" loading={isLoading && !data} empty={!data?.length} height={height}>
      <BarChart data={data ?? []} layout="vertical" margin={{ top: 4, right: 12, bottom: 4, left: 4 }}>
        <XAxis type="number" {...AXIS} />
        <YAxis type="category" dataKey="name" width={86} {...AXIS} />
        <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip />} />
        <Bar dataKey="total" name="שכר" fill="#8b5cf6" radius={[0, 6, 6, 0]} maxBarSize={18} />
      </BarChart>
    </ChartFrame>
  )
}

export function CostByContractorWidget({ height }: WidgetProps) {
  const { data, isLoading } = useSection<{ name: string; expected: number; paid: number }[]>('cost.by_contractor')
  if (data === null) return null

  return (
    <ChartFrame title="עלות לפי קבלן" loading={isLoading && !data} empty={!data?.length} height={height}>
      <BarChart data={data ?? []} layout="vertical" margin={{ top: 4, right: 12, bottom: 4, left: 4 }}>
        <XAxis type="number" {...AXIS} />
        <YAxis type="category" dataKey="name" width={86} {...AXIS} />
        <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip />} />
        <Legend wrapperStyle={{ fontSize: 11 }} />
        <Bar dataKey="expected" name="מחויב" fill="#f59e0b" radius={[0, 6, 6, 0]} maxBarSize={14} />
        <Bar dataKey="paid" name="שולם" fill="#22c55e" radius={[0, 6, 6, 0]} maxBarSize={14} />
      </BarChart>
    </ChartFrame>
  )
}

export function RevenueTrendWidget({ height }: WidgetProps) {
  const { data, isLoading } = useSection<{ bucket: string; total: number }[]>('revenue.trend')
  if (data === null) return null

  return (
    <ChartFrame title="מגמת הכנסות" loading={isLoading && !data} empty={!data?.length} height={height}>
      <BarChart data={data ?? []} margin={{ top: 8, right: 8, bottom: 4, left: -12 }}>
        <XAxis dataKey="bucket" {...AXIS} tickFormatter={(v: string) => fmtDate(v)} />
        <YAxis {...AXIS} width={64} tickFormatter={(v: number) => String(Math.round(v / 1000)) + 'k'} />
        <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip />} />
        <Bar dataKey="total" name="הכנסות" fill="#1fa189" radius={[6, 6, 0, 0]} maxBarSize={40} />
      </BarChart>
    </ChartFrame>
  )
}

/* `dashboard_stats.revenue.by_customer` has been computed and returned since
   0026 and never drawn. No new server surface is needed for this one — it was
   already on the wire. */
export function RevenueByCustomerWidget({ height }: WidgetProps) {
  const { range } = useDashboard()
  const { data: stats, isLoading } = useDashboardStats(range.from, range.to)
  const data = stats?.revenue?.by_customer
  if (stats && !data) return null
  return (
    <ChartFrame title="הכנסות לפי לקוח" loading={isLoading && !data} empty={!data?.length} height={height}>
      <BarChart data={data ?? []} margin={{ top: 4, right: 4, bottom: 4, left: -12 }}>
        <XAxis dataKey="name" {...AXIS} interval={0} angle={-25} textAnchor="end" height={54} />
        <YAxis {...AXIS} width={64} tickFormatter={(v: number) => String(Math.round(v / 1000)) + 'k'} />
        <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip />} />
        <Bar dataKey="total" name="הכנסות" radius={[6, 6, 0, 0]} maxBarSize={44}>
          {(data ?? []).map((r, i) => (
            <Cell key={i} fill={r.color} />
          ))}
        </Bar>
      </BarChart>
    </ChartFrame>
  )
}

export const ContractorPaidWidget = sectionKpi<ContractorCost>({
  section: 'cost.contractor',
  label: 'שולם לקבלנים',
  icon: Banknote,
  tone: '#22c55e',
  select: (c) => Number(c.paid),
  format: shekel,
  hint: (c) =>
    Number(c.expected) > 0
      ? `${Math.round((Number(c.paid) / Number(c.expected)) * 100)}% ממה שסוכם`
      : 'לא סוכם סכום',
})

export const RevenueForecastWidget = sectionKpi<{ total: number; tasks: number }>({
  section: 'revenue.forecast',
  label: 'תחזית הכנסות',
  icon: Banknote,
  tone: '#1fa189',
  select: (f) => Number(f.total),
  format: shekel,
  hint: (f) => `${f.tasks} משימות עתידיות מתומחרות`,
})

export function PayrollTrendWidget({ height }: WidgetProps) {
  const { data, isLoading } = useSection<{ bucket: string; total: number; hours: number }[]>('cost.payroll_trend')
  if (data === null) return null

  return (
    <ChartFrame title="מגמת עלות שכר" loading={isLoading && !data} empty={!data?.length} height={height}>
      <BarChart data={data ?? []} margin={{ top: 8, right: 8, bottom: 4, left: -12 }}>
        <XAxis dataKey="bucket" {...AXIS} tickFormatter={(v: string) => fmtDate(v)} />
        <YAxis {...AXIS} width={64} tickFormatter={(v: number) => String(Math.round(v / 1000)) + 'k'} />
        <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip />} />
        <Bar dataKey="total" name="שכר" fill="#8b5cf6" radius={[6, 6, 0, 0]} maxBarSize={40} />
      </BarChart>
    </ChartFrame>
  )
}

/* Where the direct cost actually goes. Two bars rather than a donut: with two
   slices a donut is a worse ratio chart than a pair of bars, and the absolute
   numbers matter as much as the split. */
export function CostStructureWidget(_props: WidgetProps) {
  const { data, isLoading } = useSection<Margin>('margin.summary')
  if (isLoading && data === undefined) return <SkeletonCard lines={2} />
  if (data === null || data === undefined) return null

  const contractor = Number(data.contractor)
  const payroll = Number(data.payroll)
  const total = contractor + payroll

  return (
    <Card>
      <CardHeader title="הרכב עלות ישירה" subtitle={total > 0 ? fmtMoney(total) : undefined} />
      <CardBody>
        {total === 0 ? (
          <EmptyState compact art="table" title="אין עלות רשומה בטווח" />
        ) : (
          <div className="space-y-2.5">
            <ProgressBar value={contractor} max={total} color="#f59e0b" label="קבלנים" hint={fmtMoney(contractor)} />
            <ProgressBar value={payroll} max={total} color="#8b5cf6" label="שכר" hint={fmtMoney(payroll)} />
          </div>
        )}
      </CardBody>
    </Card>
  )
}

/* Average revenue per event, derived rather than queried: both numbers are
   already on the wire from dashboard_stats, and a third figure computed from
   two of them is not worth a section of its own. */
export function AvgPerEventWidget(_props: WidgetProps) {
  const { range } = useDashboard()
  const { data, isLoading } = useDashboardStats(range.from, range.to)
  if (isLoading && !data) return <SkeletonCard lines={0} />
  if (!data?.revenue) return null
  const events = Number(data.events_count)
  const total = Number(data.revenue.total)
  return (
    <StatCard
      icon={<Banknote size={ICON.xl} strokeWidth={STROKE} />}
      label="הכנסה ממוצעת לאירוע"
      value={events > 0 ? fmtMoney(total / events) : '—'}
      tone="#1fa189"
      hint={events > 0 ? `${events} אירועים בטווח` : 'אין אירועים בטווח'}
    />
  )
}

/* How much of the pricing was decided by the engine and how much by hand. A
   rising manual share is how a pricing rule quietly stops matching reality. */
export function ManualPricingShareWidget(_props: WidgetProps) {
  const { data, isLoading } = useSection<PricingQuality>('pricing.quality')
  if (isLoading && data === undefined) return <SkeletonCard lines={2} />
  if (data === null || data === undefined) return null

  const priced = Number(data.manual) + Number(data.auto)
  return (
    <Card>
      <CardHeader title="תמחור ידני מול אוטומטי" subtitle={`${priced} משימות מתומחרות`} />
      <CardBody>
        {priced === 0 ? (
          <EmptyState compact art="table" title="אין משימות מתומחרות בטווח" />
        ) : (
          <div className="space-y-2.5">
            <ProgressBar value={Number(data.auto)} max={priced} color="#1fa189" label="לפי מחשבון" hint={String(data.auto)} />
            <ProgressBar value={Number(data.manual)} max={priced} color="#f59e0b" label="ידני" hint={String(data.manual)} />
          </div>
        )}
      </CardBody>
    </Card>
  )
}
