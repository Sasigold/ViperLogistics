import { Link } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import { Bar, BarChart, Cell, Tooltip as RTooltip, XAxis, YAxis } from 'recharts'
import { Card, CardBody, CardHeader, EmptyState, ProgressBar, Skeleton } from '../../../components/ui'
import { AlertTriangle, CalendarDays, ICON, STROKE } from '../../../components/ui/icons'
import { supabase } from '../../../lib/supabase'
import { TaskListCard } from '../parts/TaskListCard'
import { fmtDate } from '../../../lib/dates'
import { ChartTooltip } from '../parts/ChartTooltip'
import { ChartFrame } from '../parts/ChartFrame'
import { useDashboard } from '../dashboardContext'
import { useDashboardStats } from '../dashboardQueries'
import type { WidgetProps } from '../dashboardTypes'
import type { DashboardStats, WorkBoardRow } from '../../../types/domain'

/* Axis styling is identical everywhere, and a chart whose ticks are a shade
   off reads as a different chart. */
const TICK = { fontSize: 11, fill: 'var(--vl-text-tertiary)' } as const
const AXIS = { tick: TICK, axisLine: false, tickLine: false } as const

/** counted categories along the bottom, labels tilted so long names survive */
function categoryBars(cfg: {
  title: string
  subtitle?: string
  select: (s: DashboardStats) => { name: string; cnt: number | string; color?: string }[] | null | undefined
  fill?: string
  seriesName: string
}) {
  function CategoryBarsWidget({ height }: WidgetProps) {
    const { range } = useDashboard()
    const { data, isLoading } = useDashboardStats(range.from, range.to)
    const rows = data ? cfg.select(data) : undefined

    // null means the reader holds no key for this section — the widget is
    // omitted rather than drawn empty, because an empty chart claims "no data
    // in range", which is a different and wrong statement
    if (!isLoading && data && (rows === null || rows === undefined)) return null

    return (
      <ChartFrame title={cfg.title} subtitle={cfg.subtitle} loading={isLoading} empty={!rows?.length} height={height}>
        <BarChart data={rows ?? []} margin={{ top: 4, right: 4, bottom: 4, left: -20 }}>
          <XAxis dataKey="name" {...AXIS} interval={0} angle={-25} textAnchor="end" height={54} />
          <YAxis {...AXIS} allowDecimals={false} />
          <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip />} />
          <Bar dataKey="cnt" name={cfg.seriesName} fill={cfg.fill} radius={[6, 6, 0, 0]} maxBarSize={44}>
            {(rows ?? []).map((r, i) => (
              <Cell key={i} fill={r.color ?? cfg.fill ?? 'var(--vl-primary)'} />
            ))}
          </Bar>
        </BarChart>
      </ChartFrame>
    )
  }
  CategoryBarsWidget.displayName = `CategoryBars(${cfg.title})`
  return CategoryBarsWidget
}

export const TasksByCustomerWidget = categoryBars({
  title: 'משימות לפי לקוח',
  select: (s) => s.by_customer,
  seriesName: 'משימות',
})

export const ContractorSplitWidget = categoryBars({
  title: 'התפלגות קבלנים',
  select: (s) => s.by_contractor,
  seriesName: 'משימות',
  fill: '#f59e0b',
})

/* ===== worker load ========================================================
   Horizontal, unlike the others: these are people's names, and a name tilted
   at 25° on a bottom axis is a name you have to lean sideways to read.      */

export function WorkerLoadWidget({ height }: WidgetProps) {
  const { range } = useDashboard()
  const { data, isLoading } = useDashboardStats(range.from, range.to)
  const rows = data?.by_worker

  if (!isLoading && data && !rows) return null

  return (
    <ChartFrame title="עומס עובדים" subtitle="שיבוצים בטווח" loading={isLoading} empty={!rows?.length} height={height}>
      <BarChart data={rows ?? []} layout="vertical" margin={{ top: 4, right: 12, bottom: 4, left: 4 }}>
        <XAxis type="number" {...AXIS} allowDecimals={false} />
        <YAxis type="category" dataKey="name" width={86} {...AXIS} />
        <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip />} />
        <Bar dataKey="cnt" name="שיבוצים" fill="var(--vl-primary)" radius={[0, 6, 6, 0]} maxBarSize={18} />
      </BarChart>
    </ChartFrame>
  )
}

/* ===== what is booked =====================================================
   The task lists answer "what is happening"; this answers "what is booked".  */

export function NextEventsWidget(_props: WidgetProps) {
  const { range } = useDashboard()
  const { data } = useDashboardStats(range.from, range.to)
  const events = data?.next_events ?? []
  if (!events.length) return null

  return (
    <Card>
      <CardHeader title="האירועים הקרובים" icon={<CalendarDays size={ICON.md} strokeWidth={STROKE} />} />
      <CardBody padded={false}>
        <ul>
          {events.map((e) => (
            <li key={e.id} className="border-b border-line-subtle last:border-0">
              <Link
                to={`/events/${e.id}`}
                className="flex items-center gap-3 px-4 py-2.5 transition-colors hover:bg-hover"
              >
                <span className="w-24 shrink-0 tabular type-body font-medium text-primary-text">
                  {fmtDate(e.event_date)}
                </span>
                <span className="min-w-0 flex-1 truncate">{e.end_client_name || 'ללא שם'}</span>
                {e.event_number && (
                  <span className="shrink-0 tabular type-caption text-ink-tertiary">{e.event_number}</span>
                )}
              </Link>
            </li>
          ))}
        </ul>
      </CardBody>
    </Card>
  )
}

/* ===== customer concentration =============================================
   The same numbers as "הכנסות לפי לקוח", asked a different question: not who
   pays the most, but how much of the business rests on one of them. */

export function CustomerMixWidget({ height }: WidgetProps) {
  const { range } = useDashboard()
  const { data: stats, isLoading } = useDashboardStats(range.from, range.to)
  const rows = stats?.revenue?.by_customer
  if (stats && !rows) return null

  const total = (rows ?? []).reduce((s, r) => s + Number(r.total), 0)
  const top = (rows ?? [])[0]
  const share = total > 0 && top ? Math.round((Number(top.total) / total) * 100) : 0

  return (
    <Card>
      <CardHeader
        title="תמהיל לקוחות"
        subtitle={top ? `${top.name} — ${share}% מההכנסות` : undefined}
      />
      <CardBody>
        {isLoading && !rows ? (
          <Skeleton className="w-full" style={{ height }} />
        ) : !rows?.length ? (
          <EmptyState compact art="table" title="אין הכנסות בטווח" />
        ) : (
          <div className="space-y-2.5">
            {rows.slice(0, 6).map((r) => (
              <ProgressBar
                key={r.name}
                value={Number(r.total)}
                max={total}
                color={r.color}
                label={r.name}
                hint={`${Math.round((Number(r.total) / total) * 100)}%`}
              />
            ))}
          </div>
        )}
      </CardBody>
    </Card>
  )
}

/* ===== overdue list =======================================================
   The overdue counter says how many; this says which. */

export function OverdueListWidget(_props: WidgetProps) {
  const { today, openTask } = useDashboard()
  const { data = [], isLoading } = useQuery({
    queryKey: ['dashboard', 'overdue', today],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('work_board_view')
        .select('*')
        .lt('task_date', today)
        .eq('status_is_terminal', false)
        .order('task_date')
        .limit(8)
      if (error) throw error
      return data as WorkBoardRow[]
    },
  })

  return (
    <TaskListCard
      title="רשימת האיחורים"
      subtitle={`${data.length} משימות שתאריכן עבר`}
      icon={<AlertTriangle size={ICON.md} strokeWidth={STROKE} />}
      tasks={data}
      loading={isLoading}
      showDate
      emptyTitle="אין משימות באיחור"
      emptyDescription="כל מה שתאריכו עבר נסגר"
      onOpen={openTask}
    />
  )
}
