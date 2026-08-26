import { Link } from 'react-router'
import { Bar, BarChart, Cell, Legend, Line, LineChart, Tooltip as RTooltip, XAxis, YAxis } from 'recharts'
import {
  Card,
  CardBody,
  CardHeader,
  DataTable,
  EmptyState,
  SkeletonCard,
  SkeletonList,
  StatCard,
  fmtHoursShort,
  fmtMoney,
} from '../../../components/ui'
import type { Column } from '../../../components/ui'
import { AlertTriangle, CheckCheck, ICON, STROKE, Truck, Users } from '../../../components/ui/icons'
import { fmtDate } from '../../../lib/dates'
import { ChartTooltip } from '../parts/ChartTooltip'
import { ChartFrame } from '../parts/ChartFrame'
import { useDashboard, useSection } from '../dashboardContext'
import type { WidgetProps } from '../dashboardTypes'

const AXIS = { tick: { fontSize: 11, fill: 'var(--vl-text-tertiary)' }, axisLine: false, tickLine: false } as const

/* ===== simple category charts ============================================= */

function sectionBars(cfg: {
  section: string
  title: string
  subtitle?: string
  dataKey: string
  seriesName: string
  fill?: string
  layout?: 'vertical' | 'horizontal'
}) {
  function SectionBars({ height }: WidgetProps) {
    const { data, isLoading } = useSection<{ name: string; color?: string }[]>(cfg.section)
    if (data === null) return null
    const vertical = cfg.layout === 'vertical'

    return (
      <ChartFrame
        title={cfg.title}
        subtitle={cfg.subtitle}
        loading={isLoading && !data}
        empty={!data?.length}
        height={height}
      >
        <BarChart
          data={data ?? []}
          layout={vertical ? 'vertical' : undefined}
          margin={vertical ? { top: 4, right: 12, bottom: 4, left: 4 } : { top: 4, right: 4, bottom: 4, left: -20 }}
        >
          {vertical ? (
            <>
              <XAxis type="number" {...AXIS} allowDecimals={false} />
              <YAxis type="category" dataKey="name" width={86} {...AXIS} />
            </>
          ) : (
            <>
              <XAxis dataKey="name" {...AXIS} interval={0} angle={-25} textAnchor="end" height={54} />
              <YAxis {...AXIS} allowDecimals={false} />
            </>
          )}
          <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip />} />
          <Bar
            dataKey={cfg.dataKey}
            name={cfg.seriesName}
            fill={cfg.fill ?? 'var(--vl-primary)'}
            radius={vertical ? [0, 6, 6, 0] : [6, 6, 0, 0]}
            maxBarSize={vertical ? 18 : 44}
          >
            {(data ?? []).map((r, i) => (
              <Cell key={i} fill={r.color ?? cfg.fill ?? 'var(--vl-primary)'} />
            ))}
          </Bar>
        </BarChart>
      </ChartFrame>
    )
  }
  SectionBars.displayName = `SectionBars(${cfg.section})`
  return SectionBars
}

export const TasksByTypeWidget = sectionBars({
  section: 'tasks.by_type',
  title: 'משימות לפי סוג',
  dataKey: 'cnt',
  seriesName: 'משימות',
})

export const TasksByMethodWidget = sectionBars({
  section: 'tasks.by_method',
  title: 'משימות לפי אופן ביצוע',
  dataKey: 'cnt',
  seriesName: 'משימות',
  fill: '#0ea5e9',
})

export const EventsByCustomerWidget = sectionBars({
  section: 'events.by_customer',
  title: 'כמות אירועים לפי לקוח',
  dataKey: 'cnt',
  seriesName: 'אירועים',
})

export const EventsFunnelWidget = sectionBars({
  section: 'events.funnel',
  title: 'אירועים לפי סטטוס',
  dataKey: 'cnt',
  seriesName: 'אירועים',
})

export const HoursByWorkerWidget = sectionBars({
  section: 'attendance.hours_by_worker',
  title: 'שעות לפי עובד',
  dataKey: 'hours',
  seriesName: 'שעות',
  layout: 'vertical',
  fill: '#0ea5e9',
})

export const FleetUtilizationWidget = sectionBars({
  section: 'fleet.utilization',
  title: 'ניצולת משאיות',
  subtitle: 'ימי פעילות בטווח',
  dataKey: 'days',
  seriesName: 'ימים',
  layout: 'vertical',
  fill: '#64748b',
})

export const AttendanceFlagsWidget = sectionBars({
  section: 'attendance.flags',
  title: 'חריגות נוכחות',
  dataKey: 'cnt',
  seriesName: 'רשומות',
  fill: '#f59e0b',
})

/* ===== trend ============================================================== */

export function TasksTrendWidget({ height }: WidgetProps) {
  const { data, isLoading } = useSection<{ bucket: string; tasks: number; events: number }[]>('tasks.trend')
  if (data === null) return null

  return (
    <ChartFrame title="מגמת משימות ואירועים" loading={isLoading && !data} empty={!data?.length} height={height}>
      <LineChart data={data ?? []} margin={{ top: 8, right: 8, bottom: 4, left: -20 }}>
        <XAxis dataKey="bucket" {...AXIS} tickFormatter={(v: string) => fmtDate(v)} />
        <YAxis {...AXIS} allowDecimals={false} />
        <RTooltip content={<ChartTooltip />} />
        <Legend wrapperStyle={{ fontSize: 11 }} />
        <Line type="monotone" dataKey="tasks" name="משימות" stroke="var(--vl-primary)" strokeWidth={2} dot={false} />
        <Line type="monotone" dataKey="events" name="אירועים" stroke="#1fa189" strokeWidth={2} dot={false} />
      </LineChart>
    </ChartFrame>
  )
}

/* ===== operational gaps ===================================================
   Three widgets that answer "what is about to go wrong" rather than "what
   happened". Each one is a count plus the rows behind it, because a count on
   its own tells you to go looking somewhere else.                           */

interface Understaffed {
  count: number
  rows: { id: string; task_date: string; label: string | null; needed: number; assigned: number }[]
}

export function UnderstaffedWidget(_props: WidgetProps) {
  const { openTask } = useDashboard()
  const { data, isLoading } = useSection<Understaffed>('tasks.understaffed')
  if (data === null) return null

  return (
    <Card>
      <CardHeader
        title="משימות בתת-איוש"
        subtitle={data ? `${data.count} משימות פתוחות` : undefined}
        icon={<Users size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody padded={false}>
        {isLoading && !data ? (
          <div className="p-4">
            <SkeletonList rows={3} />
          </div>
        ) : !data?.rows.length ? (
          <EmptyState compact art="check" title="כל המשימות מאוישות" />
        ) : (
          <ul>
            {data.rows.map((r) => (
              <li key={r.id}>
                <button
                  onClick={() => openTask?.(r.id)}
                  disabled={!openTask}
                  className="flex w-full items-center gap-2.5 border-b border-line-subtle px-4 py-2.5 text-start transition-colors last:border-0 hover:bg-hover disabled:cursor-default disabled:hover:bg-transparent"
                >
                  <span className="min-w-0 flex-1">
                    <span className="block truncate type-body font-medium">{r.label ?? 'ללא שם'}</span>
                    <span className="block type-caption tabular text-ink-tertiary">{fmtDate(r.task_date)}</span>
                  </span>
                  <span className="shrink-0 rounded-full bg-warning-subtle px-2 py-0.5 type-caption font-semibold tabular text-warning-text">
                    {r.assigned}/{r.needed}
                  </span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </CardBody>
    </Card>
  )
}

export function NoTruckWidget(_props: WidgetProps) {
  const { data, isLoading } = useSection<{ count: number }>('tasks.no_truck')
  if (isLoading && data === undefined) return <SkeletonCard lines={0} />
  if (data === null || data === undefined) return null
  return (
    <StatCard
      icon={<Truck size={ICON.xl} strokeWidth={STROKE} />}
      label="משימות ללא משאית"
      value={data.count}
      tone={data.count > 0 ? '#f59e0b' : '#22c55e'}
      hint={data.count > 0 ? 'פתוחות, בלי משאית ובלי טקסט חופשי' : 'לכל המשימות יש משאית'}
    />
  )
}

interface Pending {
  count: number
  hours: number
  rows: { id: string; work_date: string; full_name: string; actual_hours: number }[]
}

export function AttendancePendingWidget(_props: WidgetProps) {
  const { data, isLoading } = useSection<Pending>('attendance.pending')
  if (data === null) return null

  return (
    <Card>
      <CardHeader
        title="דיווחי נוכחות לאישור"
        subtitle={data ? `${fmtHoursShort(Number(data.hours))} ממתינות` : undefined}
        icon={<CheckCheck size={ICON.md} strokeWidth={STROKE} />}
        actions={
          <Link to="/attendance" className="rounded px-1.5 py-1 type-caption text-primary-text hover:bg-hover">
            לדוח
          </Link>
        }
      />
      <CardBody padded={false}>
        {isLoading && !data ? (
          <div className="p-4">
            <SkeletonList rows={3} />
          </div>
        ) : !data?.rows.length ? (
          <EmptyState compact art="check" title="אין דיווחים שממתינים" />
        ) : (
          <ul>
            {data.rows.map((r) => (
              <li
                key={r.id}
                className="flex items-center gap-2.5 border-b border-line-subtle px-4 py-2.5 last:border-0"
              >
                <span className="min-w-0 flex-1 truncate type-body">{r.full_name}</span>
                <span className="shrink-0 type-caption tabular text-ink-tertiary">{fmtDate(r.work_date)}</span>
                <span className="shrink-0 type-caption tabular font-semibold">
                  {fmtHoursShort(Number(r.actual_hours))}
                </span>
              </li>
            ))}
          </ul>
        )}
      </CardBody>
    </Card>
  )
}

/* ===== customers ========================================================== */

export function CustomersInactiveWidget(_props: WidgetProps) {
  const { data, isLoading } = useSection<{ name: string; color: string; last_event: string | null }[]>(
    'customers.inactive',
  )
  if (data === null) return null

  return (
    <Card>
      <CardHeader title="לקוחות ללא פעילות" subtitle="אין אירועים בטווח שנבחר" />
      <CardBody padded={false}>
        {isLoading && !data ? (
          <div className="p-4">
            <SkeletonList rows={3} />
          </div>
        ) : !data?.length ? (
          <EmptyState compact art="check" title="לכל הלקוחות הפעילים יש אירוע בטווח" />
        ) : (
          <ul>
            {data.map((c) => (
              <li
                key={c.name}
                className="flex items-center gap-2.5 border-b border-line-subtle px-4 py-2.5 last:border-0"
              >
                <span className="size-2 shrink-0 rounded-full" style={{ background: c.color }} aria-hidden />
                <span className="min-w-0 flex-1 truncate type-body">{c.name}</span>
                <span className="shrink-0 type-caption tabular text-ink-tertiary">
                  {c.last_event ? `אחרון: ${fmtDate(c.last_event)}` : 'אף פעם'}
                </span>
              </li>
            ))}
          </ul>
        )}
      </CardBody>
    </Card>
  )
}

export function EventVolumeWidget(_props: WidgetProps) {
  const { data, isLoading } = useSection<{ volume_m: number; trucks: number; events: number }>('events.volume')
  if (isLoading && data === undefined) return <SkeletonCard lines={0} />
  if (data === null || data === undefined) return null
  return (
    <StatCard
      icon={<Truck size={ICON.xl} strokeWidth={STROKE} />}
      label="נפח מטען בטווח"
      value={`${Number(data.volume_m).toLocaleString('he-IL')} מ״ק`}
      tone="#64748b"
      hint={`${data.trucks} משאיות · ${data.events} אירועים`}
    />
  )
}

export function UnratedShiftsBadgeWidget(_props: WidgetProps) {
  const { data } = useSection<{ unrated_shifts: number; pending_shifts: number }>('cost.payroll')
  if (!data) return null
  const total = Number(data.unrated_shifts) + Number(data.pending_shifts)
  if (total === 0) return null
  return (
    <StatCard
      icon={<AlertTriangle size={ICON.xl} strokeWidth={STROKE} />}
      label="משמרות שאינן בעלות השכר"
      value={total}
      tone="#f59e0b"
      hint={`${data.unrated_shifts} ללא תעריף · ${data.pending_shifts} ממתינות לאישור`}
    />
  )
}

/* ===== customer leaderboard =============================================== */

interface LeaderRow {
  name: string
  color: string
  events: number
  tasks: number
  revenue: number | null
  last_event: string | null
}

export function CustomerLeaderboardWidget(_props: WidgetProps) {
  const { data, isLoading } = useSection<LeaderRow[]>('customers.leaderboard')
  if (data === null) return null

  // `revenue` arrives null for a reader without pricing.revenue — the column
  // disappears rather than showing a row of dashes
  const showMoney = (data ?? []).some((r) => r.revenue !== null)

  const columns: Column<LeaderRow>[] = [
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
    { key: 'events', header: 'אירועים', align: 'end', render: (r) => r.events, sortValue: (r) => Number(r.events) },
    { key: 'tasks', header: 'משימות', align: 'end', render: (r) => r.tasks, sortValue: (r) => Number(r.tasks) },
    ...(showMoney
      ? [
          {
            key: 'revenue',
            header: 'הכנסות',
            align: 'end' as const,
            render: (r: LeaderRow) => (r.revenue === null ? '—' : fmtMoney(Number(r.revenue))),
            sortValue: (r: LeaderRow) => Number(r.revenue ?? 0),
          },
        ]
      : []),
    {
      key: 'last',
      header: 'אירוע אחרון',
      align: 'end',
      render: (r) => (r.last_event ? fmtDate(r.last_event) : '—'),
      sortValue: (r) => r.last_event ?? '',
    },
  ]

  return (
    <Card>
      <CardHeader title="לקוחות מובילים" subtitle="בטווח שנבחר" />
      <CardBody padded={false}>
        <DataTable
          rows={data ?? []}
          columns={columns}
          getRowId={(r) => r.name}
          loading={isLoading && !data}
          dense
          defaultSort={{ key: 'events', dir: 'desc' }}
          empty={<EmptyState compact art="table" title="אין פעילות בטווח" />}
        />
      </CardBody>
    </Card>
  )
}

export function HeadcountWidget(_props: WidgetProps) {
  const { data, isLoading } = useSection<{ active: number; staff: number }>('hr.headcount')
  if (isLoading && data === undefined) return <SkeletonCard lines={0} />
  if (data === null || data === undefined) return null
  return (
    <StatCard
      icon={<Users size={ICON.xl} strokeWidth={STROKE} />}
      label="סגל פעיל"
      value={data.staff}
      tone="#22c55e"
      hint={`${data.active} חשבונות פעילים בסך הכול`}
    />
  )
}

export function EventTrucksWidget(_props: WidgetProps) {
  const { data, isLoading } = useSection<{ trucks: number; events: number }>('events.volume')
  if (isLoading && data === undefined) return <SkeletonCard lines={0} />
  if (data === null || data === undefined) return null
  return (
    <StatCard
      icon={<Truck size={ICON.xl} strokeWidth={STROKE} />}
      label="משאיות נדרשות"
      value={data.trucks}
      tone="#0ea5e9"
      hint={`על פני ${data.events} אירועים`}
    />
  )
}
