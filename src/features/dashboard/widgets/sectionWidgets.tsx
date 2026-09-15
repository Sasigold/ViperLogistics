import { useState } from 'react'
import { Link } from 'react-router'
import { Legend, Line, LineChart, Tooltip as RTooltip, XAxis, YAxis } from 'recharts'
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
import {
  AlertTriangle,
  CheckCheck,
  Clock,
  ICON,
  LogIn,
  LogOut,
  MapPin,
  STROKE,
  Truck,
  UserCheck,
  Users,
} from '../../../components/ui/icons'
import { fmtDate } from '../../../lib/dates'
import { ChartTooltip } from '../parts/ChartTooltip'
import { ChartFrame } from '../parts/ChartFrame'
import { useDashboard, useSection } from '../dashboardContext'
import { useCustomerDrill, useDrill } from '../useDrill'
import { SeriesCard } from '../parts/SeriesCard'
import { CATEGORY_FORMS, RANK_FORMS, pickForm } from '../seriesOpts'
import type { SeriesRow } from '../seriesOpts'
import type { DrillTarget } from '../drill'
import type { WidgetProps } from '../dashboardTypes'

const AXIS = { tick: { fontSize: 11, fill: 'var(--vl-text-tertiary)' }, axisLine: false, tickLine: false } as const

/* ===== simple category charts ============================================= */

/**
 * A counted category out of one server section.
 *
 * `layout` used to be the whole of the display decision and it was made once,
 * here, forever: vertical for names, horizontal for everything else. It is now
 * only the *first* answer — the same reasoning that made it right by default
 * ("a name tilted 25° is a name you read sideways") is not a reason to refuse
 * a reader who wants the same numbers as a table.
 */
function sectionBars(cfg: {
  section: string
  title: string
  subtitle?: string
  dataKey: string
  seriesName: string
  fill?: string
  layout?: 'vertical' | 'horizontal'
  format?: (v: number) => string
  drill?: { probe: DrillTarget; of: (row: SeriesRow) => DrillTarget }
  /**
   * The row's label is a customer's name.
   *
   * `dashboard_sections` still groups `events.by_customer` by name — 0151 only
   * reached `dashboard_stats` — so there is no id in the row, and `?q=` is not
   * the answer: the events list searches the end client, the event number and
   * the location, never the customer. The name is resolved through the
   * customers list instead, which is one small cached query the events screen
   * and the board already make.
   */
  customerDrill?: boolean
  emptyTitle?: string
  emptyDescription?: string
}) {
  const forms = cfg.layout === 'vertical' ? RANK_FORMS : CATEGORY_FORMS
  function SectionBars({ height, opts }: WidgetProps) {
    const raw = useSection<Record<string, unknown>[]>(cfg.section)
    const go = useDrill(cfg.drill?.probe ?? { to: 'board' })
    const toCustomer = useCustomerDrill(!!cfg.customerDrill && !!go)
    if (raw.data === null) return null

    const rows: SeriesRow[] | undefined = raw.data?.map((r) => ({
      key: String(r.id ?? r.name),
      label: String(r.name ?? ''),
      value: Number(r[cfg.dataKey] ?? 0),
      color: typeof r.color === 'string' ? r.color : undefined,
    }))

    return (
      <SeriesCard
        title={cfg.title}
        subtitle={cfg.subtitle}
        rows={rows}
        loading={raw.isLoading && !raw.data}
        error={raw.error}
        form={pickForm(forms, opts)}
        height={height}
        opts={opts}
        seriesName={cfg.seriesName}
        format={cfg.format}
        fill={cfg.fill}
        emptyTitle={cfg.emptyTitle ?? 'אין נתונים בטווח'}
        emptyDescription={cfg.emptyDescription}
        onSelect={
          toCustomer ? (r) => go?.(toCustomer(r.label)) : cfg.drill && go ? (r) => go(cfg.drill!.of(r)) : undefined
        }
      />
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
  drill: { probe: { to: 'board' }, of: () => ({ to: 'board' }) },
  emptyDescription: 'לא נוצרו משימות בטווח שנבחר',
})

export const TasksByMethodWidget = sectionBars({
  section: 'tasks.by_method',
  title: 'משימות לפי אופן ביצוע',
  dataKey: 'cnt',
  seriesName: 'משימות',
  fill: '#0ea5e9',
  drill: { probe: { to: 'board' }, of: () => ({ to: 'board' }) },
  emptyDescription: 'לא נוצרו משימות בטווח שנבחר',
})

export const EventsByCustomerWidget = sectionBars({
  section: 'events.by_customer',
  title: 'כמות אירועים לפי לקוח',
  dataKey: 'cnt',
  seriesName: 'אירועים',
  drill: { probe: { to: 'events' }, of: () => ({ to: 'events' }) },
  customerDrill: true,
  emptyDescription: 'לא נקבעו אירועים בטווח שנבחר',
})

export const EventsFunnelWidget = sectionBars({
  section: 'events.funnel',
  title: 'אירועים לפי סטטוס',
  dataKey: 'cnt',
  seriesName: 'אירועים',
  drill: { probe: { to: 'events' }, of: () => ({ to: 'events' }) },
  emptyDescription: 'לא נקבעו אירועים בטווח שנבחר',
})

export const HoursByWorkerWidget = sectionBars({
  section: 'attendance.hours_by_worker',
  title: 'שעות לפי עובד',
  dataKey: 'hours',
  seriesName: 'שעות',
  layout: 'vertical',
  fill: '#0ea5e9',
  format: fmtHoursShort,
  drill: { probe: { to: 'attendance' }, of: () => ({ to: 'attendance' }) },
  emptyDescription: 'לא דווחו שעות בטווח שנבחר',
})

export const FleetUtilizationWidget = sectionBars({
  section: 'fleet.utilization',
  title: 'ניצולת משאיות',
  subtitle: 'ימי פעילות בטווח',
  dataKey: 'days',
  seriesName: 'ימים',
  layout: 'vertical',
  fill: '#64748b',
  drill: { probe: { to: 'vehicles' }, of: () => ({ to: 'vehicles' }) },
  emptyDescription: 'אף רכב לא שובץ בטווח שנבחר',
})

export const AttendanceFlagsWidget = sectionBars({
  section: 'attendance.flags',
  title: 'חריגות נוכחות',
  dataKey: 'cnt',
  seriesName: 'רשומות',
  fill: '#f59e0b',
  drill: { probe: { to: 'attendance' }, of: () => ({ to: 'attendance' }) },
  emptyTitle: 'אין חריגות בטווח',
  emptyDescription: 'כל הדיווחים בטווח תקינים',
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

/* ===== active and recent shifts (last 24 hours) =========================== */

interface RecentShiftWorker {
  id: string
  profile_id: string
  worker_name: string
  phone: string | null
  work_site: string | null
  task_or_event: string | null
  clock_in_at: string
  clock_out_at: string | null
  is_active: boolean
  status: string
  actual_hours: number | null
  duration_minutes: number
}

interface ActiveAndRecentShiftsData {
  active_count: number
  total_count: number
  shifts: RecentShiftWorker[]
}

function fmtTimeOfDay(isoString: string | null | undefined): string {
  if (!isoString) return ''
  try {
    const d = new Date(isoString)
    return d.toLocaleTimeString('he-IL', {
      hour: '2-digit',
      minute: '2-digit',
      timeZone: 'Asia/Jerusalem',
    })
  } catch {
    return ''
  }
}

function fmtDateOrToday(isoString: string | null | undefined): string {
  if (!isoString) return ''
  try {
    const d = new Date(isoString)
    const now = new Date()
    const isToday =
      d.getDate() === now.getDate() &&
      d.getMonth() === now.getMonth() &&
      d.getFullYear() === now.getFullYear()
    if (isToday) return 'היום'
    return d.toLocaleDateString('he-IL', {
      day: 'numeric',
      month: 'numeric',
      timeZone: 'Asia/Jerusalem',
    })
  } catch {
    return ''
  }
}

function fmtDurationMins(minutes: number): string {
  if (!minutes || minutes <= 0) return '0 דק׳'
  const h = Math.floor(minutes / 60)
  const m = minutes % 60
  if (h === 0) return `${m} דק׳`
  if (m === 0) return `${h} שעות`
  return `${h} שעות ו-${m} דק׳`
}

export function ActiveAndRecentShiftsWidget(_props: WidgetProps) {
  const { data, isLoading } = useSection<ActiveAndRecentShiftsData>('attendance.active_and_recent')
  const [filter, setFilter] = useState<'all' | 'active' | 'completed'>('all')

  if (data === null) return null

  const shifts = data?.shifts ?? []
  const activeCount = data?.active_count ?? 0
  const totalCount = shifts.length
  const completedCount = totalCount - activeCount

  const filtered = shifts.filter((s) => {
    if (filter === 'active') return s.is_active
    if (filter === 'completed') return !s.is_active
    return true
  })

  return (
    <Card>
      <CardHeader
        title="עובדים במשמרת / 24 שעות האחרונות"
        subtitle={
          activeCount > 0 ? (
            <span className="flex items-center gap-1.5 text-success-text font-medium">
              <span className="inline-block size-2 rounded-full bg-success animate-pulse" />
              <span>{activeCount} עובדים במשמרת כעת</span>
              <span className="text-ink-tertiary font-normal">· {totalCount} ב-24 שעות האחרונות</span>
            </span>
          ) : (
            `אין עובדים פעילים כעת · ${totalCount} ב-24 שעות האחרונות`
          )
        }
        icon={<UserCheck size={ICON.md} strokeWidth={STROKE} />}
        actions={
          <Link to="/attendance" className="rounded px-2 py-1 type-caption font-medium text-primary-text hover:bg-hover">
            לדוח נוכחות
          </Link>
        }
      />
      {shifts.length > 0 && (
        <div className="flex items-center gap-1 border-b border-line-subtle px-4 py-2 bg-subtle/30 text-xs">
          <button
            type="button"
            onClick={() => setFilter('all')}
            className={`rounded px-2.5 py-1 font-medium transition-colors ${
              filter === 'all' ? 'bg-surface shadow-xs text-ink font-semibold' : 'text-ink-secondary hover:text-ink'
            }`}
          >
            הכל ({totalCount})
          </button>
          <button
            type="button"
            onClick={() => setFilter('active')}
            className={`flex items-center gap-1.5 rounded px-2.5 py-1 font-medium transition-colors ${
              filter === 'active' ? 'bg-surface shadow-xs text-success-text font-semibold' : 'text-ink-secondary hover:text-ink'
            }`}
          >
            <span className="size-1.5 rounded-full bg-success" />
            במשמרת כעת ({activeCount})
          </button>
          <button
            type="button"
            onClick={() => setFilter('completed')}
            className={`rounded px-2.5 py-1 font-medium transition-colors ${
              filter === 'completed' ? 'bg-surface shadow-xs text-ink font-semibold' : 'text-ink-secondary hover:text-ink'
            }`}
          >
            הסתיימו ({completedCount})
          </button>
        </div>
      )}
      <CardBody padded={false}>
        {isLoading && !data ? (
          <div className="p-4">
            <SkeletonList rows={3} />
          </div>
        ) : filtered.length === 0 ? (
          <EmptyState
            compact
            art="check"
            title={
              filter === 'active'
                ? 'אין עובדים במשמרת כעת'
                : filter === 'completed'
                  ? 'אין משמרות שהסתיימו ב-24 השעות האחרונות'
                  : 'אין עובדים במשמרת או ב-24 השעות האחרונות'
            }
          />
        ) : (
          <ul className="max-h-[360px] divide-y divide-line-subtle overflow-y-auto">
            {filtered.map((r) => (
              <li
                key={r.id}
                className="flex flex-col sm:flex-row sm:items-center justify-between gap-2.5 px-4 py-3 hover:bg-hover/40 transition-colors"
              >
                {/* Worker Identity and status */}
                <div className="flex items-center gap-3 min-w-0">
                  <div
                    className={`flex size-9 shrink-0 items-center justify-center rounded-full text-xs font-bold ${
                      r.is_active
                        ? 'bg-success-subtle text-success-text ring-2 ring-success/30'
                        : 'bg-subtle text-ink-secondary'
                    }`}
                  >
                    {r.worker_name.trim().charAt(0)}
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="font-semibold text-ink type-body truncate">{r.worker_name}</span>
                      {r.is_active ? (
                        <span className="inline-flex items-center gap-1 rounded-full bg-success-subtle px-2 py-0.5 text-xs font-medium text-success-text">
                          <span className="size-1.5 rounded-full bg-success animate-pulse" />
                          במשמרת כעת
                        </span>
                      ) : (
                        <span className="inline-flex items-center rounded-full bg-subtle px-1.5 py-0.5 text-xs text-ink-tertiary">
                          הסתיימה ({fmtDurationMins(r.duration_minutes)})
                        </span>
                      )}
                    </div>
                    <div className="mt-0.5 flex items-center gap-2 text-xs text-ink-tertiary flex-wrap">
                      {r.task_or_event && (
                        <span className="inline-flex items-center gap-0.5 text-ink-secondary">
                          <MapPin size={11} className="shrink-0 text-primary-text" />
                          <span className="truncate max-w-[150px]">{r.task_or_event}</span>
                        </span>
                      )}
                      {r.work_site && !r.task_or_event && (
                        <span className="inline-flex items-center gap-0.5">
                          <MapPin size={11} className="shrink-0 text-ink-tertiary" />
                          <span>{r.work_site === 'field' ? 'שטח' : r.work_site === 'warehouse' ? 'מחסן' : r.work_site}</span>
                        </span>
                      )}
                      {r.phone && (
                        <a href={`tel:${r.phone}`} className="hover:text-primary-text transition-colors">
                          {r.phone}
                        </a>
                      )}
                    </div>
                  </div>
                </div>

                {/* Clock In / Out Times */}
                <div className="flex items-center gap-4 shrink-0 ps-12 sm:ps-0 text-xs">
                  {/* Clock-in */}
                  <div className="flex flex-col items-start sm:items-end">
                    <span className="flex items-center gap-1 text-ink-tertiary">
                      <LogIn size={11} className="text-success-text shrink-0" />
                      <span>כניסה</span>
                    </span>
                    <span className="font-semibold tabular text-ink mt-0.5">
                      {fmtTimeOfDay(r.clock_in_at)}{' '}
                      <span className="text-ink-tertiary font-normal text-[11px]">({fmtDateOrToday(r.clock_in_at)})</span>
                    </span>
                  </div>

                  {/* Clock-out */}
                  <div className="flex flex-col items-start sm:items-end">
                    <span className="flex items-center gap-1 text-ink-tertiary">
                      <LogOut size={11} className="text-ink-tertiary shrink-0" />
                      <span>יציאה</span>
                    </span>
                    {r.clock_out_at ? (
                      <span className="font-semibold tabular text-ink mt-0.5">
                        {fmtTimeOfDay(r.clock_out_at)}{' '}
                        <span className="text-ink-tertiary font-normal text-[11px]">({fmtDateOrToday(r.clock_out_at)})</span>
                      </span>
                    ) : (
                      <span className="text-warning-text font-medium mt-0.5 flex items-center gap-1">
                        <Clock size={11} />
                        <span>טרם יצא</span>
                      </span>
                    )}
                  </div>
                </div>
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
