import { useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import { addDays, differenceInCalendarDays, endOfMonth, startOfMonth, startOfWeek, subDays } from 'date-fns'
import { Bar, BarChart, Cell, Pie, PieChart, ResponsiveContainer, Tooltip as RTooltip, XAxis, YAxis } from 'recharts'
import { ChartTooltip } from './parts/ChartTooltip'
import { ChartFrame } from './parts/ChartFrame'
import { DayTimeline } from './parts/DayTimeline'
import { TaskListCard } from './parts/TaskListCard'
import {
  AlertTriangle,
  Banknote,
  Calendar,
  CalendarDays,
  ClipboardList,
  Clock,
  History,
  ICON,
  Plus,
  STROKE,
  Users,
} from '../../components/ui/icons'
import {
  Button,
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  ErrorState,
  Input,
  PageHeader,
  ProgressBar,
  Skeleton,
  SkeletonCard,
  SkeletonList,
  StatCard,
  fmtMoney,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { fmtDate, toISODate } from '../../lib/dates'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { TaskDrawer } from '../tasks/TaskDrawer'
import { EventFormModal } from '../events/EventFormModal'
import type { DashboardStats, WorkBoardRow } from '../../types/domain'

export default function DashboardPage() {
  const navigate = useNavigate()
  const { has, canCreateEvent } = useAuth()
  const [from, setFrom] = useState(toISODate(startOfMonth(new Date())))
  const [to, setTo] = useState(toISODate(endOfMonth(new Date())))
  const [taskDrawer, setTaskDrawer] = useState<{ open: boolean; id: string | null }>({ open: false, id: null })
  const [eventModal, setEventModal] = useState(false)

  const today = toISODate(new Date())

  /** Same range length, immediately before the selected one — powers the
   *  "vs. previous period" deltas without any new server surface. */
  const prevRange = useMemo(() => {
    const span = Math.max(0, differenceInCalendarDays(new Date(to), new Date(from)))
    const prevTo = subDays(new Date(from), 1)
    return { from: toISODate(subDays(prevTo, span)), to: toISODate(prevTo) }
  }, [from, to])

  const { data: stats, isLoading, error, refetch } = useQuery({
    queryKey: ['dashboard', from, to],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('dashboard_stats', { p_from: from, p_to: to })
      if (error) throw error
      return data as DashboardStats
    },
  })

  const { data: prev } = useQuery({
    queryKey: ['dashboard', prevRange.from, prevRange.to],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('dashboard_stats', { p_from: prevRange.from, p_to: prevRange.to })
      if (error) throw error
      return data as DashboardStats
    },
  })

  /* Today / upcoming / recently-touched all read the existing board view. */
  const { data: todayTasks = [], isLoading: loadingToday } = useQuery({
    queryKey: ['dashboard', 'today', today],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('work_board_view')
        .select('*')
        .eq('task_date', today)
        .order('onsite_start_time', { nullsFirst: false })
        .limit(60)
      if (error) throw error
      return data as WorkBoardRow[]
    },
  })

  const { data: upcoming = [], isLoading: loadingUpcoming } = useQuery({
    queryKey: ['dashboard', 'upcoming', today],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('work_board_view')
        .select('*')
        .gt('task_date', today)
        .lte('task_date', toISODate(addDays(new Date(), 7)))
        .order('task_date')
        .order('onsite_start_time', { nullsFirst: false })
        .limit(8)
      if (error) throw error
      return data as WorkBoardRow[]
    },
  })

  const { data: recent = [], isLoading: loadingRecent } = useQuery({
    queryKey: ['dashboard', 'recent'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('work_board_view')
        .select('*')
        .order('updated_at', { ascending: false })
        .limit(8)
      if (error) throw error
      return data as WorkBoardRow[]
    },
  })

  const openTask = (id: string) => setTaskDrawer({ open: true, id })

  const totalByStatus = stats?.by_status.reduce((s, x) => s + Number(x.cnt), 0) ?? 0

  const presets = [
    { label: 'השבוע', run: () => { const s = startOfWeek(new Date(), { weekStartsOn: 0 }); setFrom(toISODate(s)); setTo(toISODate(addDays(s, 6))) } },
    { label: 'החודש', run: () => { setFrom(toISODate(startOfMonth(new Date()))); setTo(toISODate(endOfMonth(new Date()))) } },
    { label: '30 ימים', run: () => { setFrom(toISODate(subDays(new Date(), 29))); setTo(today) } },
  ]

  return (
    <RequirePermission perm={PERM.DASHBOARD_VIEW}>
      <div className="space-y-4">
        <PageHeader
          title="דשבורד"
          subtitle={`${fmtDate(from)} – ${fmtDate(to)}`}
          actions={
            /* on a phone this is the widest control on the screen, so the
               presets scroll and the two date fields share one row */
            <div className="flex w-full flex-col gap-1.5 sm:w-auto sm:flex-row sm:items-center">
              <div className="scroll-row gap-1">
                {presets.map((p) => (
                  <button
                    key={p.label}
                    onClick={p.run}
                    className="scroll-row-item rounded-md px-2 py-1 type-caption font-medium text-ink-tertiary transition-colors hover:bg-hover hover:text-ink"
                  >
                    {p.label}
                  </button>
                ))}
              </div>
              <div className="flex flex-wrap items-center gap-1.5">
                <Input
                  type="date"
                  inputSize="sm"
                  className="min-h-9 grow basis-32 tabular sm:min-h-0 sm:w-36 sm:grow-0 sm:basis-auto"
                  value={from}
                  onChange={(e) => setFrom(e.target.value)}
                  aria-label="מתאריך"
                />
                <span className="shrink-0 type-caption text-ink-tertiary">–</span>
                <Input
                  type="date"
                  inputSize="sm"
                  className="min-h-9 grow basis-32 tabular sm:min-h-0 sm:w-36 sm:grow-0 sm:basis-auto"
                  value={to}
                  onChange={(e) => setTo(e.target.value)}
                  aria-label="עד תאריך"
                />
              </div>
            </div>
          }
        />

        {/* דשבורד שנכשל היה מצייר שלדים לנצח: isLoading יורד ל-false ו-stats
            נשאר undefined, ולכן התנאי שמתחתיו נשאר אמת. הודעה עם "נסה שוב"
            היא ההבדל בין "עוד רגע" ל"לא נטען". */}
        {/* ── KPIs ─────────────────────────────────────────────────────────
            Only the two range-scoped metrics carry a delta: the rest are
            "as of today" and have no previous-period equivalent.          */}
        {isLoading || !stats ? (
          /* דשבורד שנכשל היה מצייר שלדים לנצח: isLoading יורד ל-false ו-stats
             נשאר undefined, ולכן התנאי הזה נשאר אמת. ההודעה היא ההבדל בין
             "עוד רגע" ל"לא נטען". */
          error ? (
            <ErrorState error={error} onRetry={() => void refetch()} />
          ) : (
            <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
              {Array.from({ length: 6 }).map((_, i) => (
                <SkeletonCard key={i} lines={0} />
              ))}
            </div>
          )
        ) : (
          <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
            <StatCard
              icon={<CalendarDays size={ICON.xl} strokeWidth={STROKE} />}
              label="אירועים בטווח"
              value={stats.events_count}
              delta={prev ? stats.events_count - prev.events_count : null}
              hint="מול התקופה הקודמת"
              onClick={() => navigate('/events')}
            />
            <StatCard
              icon={<ClipboardList size={ICON.xl} strokeWidth={STROKE} />}
              label="משימות בטווח"
              value={stats.tasks_count}
              delta={prev ? stats.tasks_count - prev.tasks_count : null}
              hint="מול התקופה הקודמת"
              onClick={() => navigate('/board')}
            />
            <StatCard
              icon={<Clock size={ICON.xl} strokeWidth={STROKE} />}
              label="משימות היום"
              value={stats.tasks_today}
              tone="#8b5cf6"
              onClick={() => navigate(`/board?date=${today}`)}
            />
            <StatCard
              icon={<Calendar size={ICON.xl} strokeWidth={STROKE} />}
              label="משימות השבוע"
              value={stats.tasks_week}
              tone="#0ea5e9"
              onClick={() => navigate('/board')}
            />
            <StatCard
              icon={<AlertTriangle size={ICON.xl} strokeWidth={STROKE} />}
              label="משימות באיחור"
              value={stats.tasks_overdue}
              tone="#ef4444"
              onClick={() => navigate('/board')}
            />
            {/* null — ולא 0 — למי שאינו רואה סטטיסטיקות של כלל העובדים */}
            {stats.available_workers !== null && (
              <StatCard
                icon={<Users size={ICON.xl} strokeWidth={STROKE} />}
                label="עובדים זמינים היום"
                value={stats.available_workers}
                tone="#22c55e"
                onClick={() => navigate('/users')}
              />
            )}
            {/* הכנסות מלקוחות — נפרד מהתשלומים לקבלנים, ובהרשאה נפרדת */}
            {stats.revenue && (
              <StatCard
                icon={<Banknote size={ICON.xl} strokeWidth={STROKE} />}
                label="הכנסות בטווח"
                value={fmtMoney(stats.revenue.total)}
                tone="#1fa189"
                hint={`${stats.revenue.priced_tasks} משימות מתומחרות`}
                delta={prev?.revenue ? stats.revenue.total - prev.revenue.total : null}
              />
            )}
          </div>
        )}

        {/* ── quick actions ───────────────────────────────────────────────── */}
        <div className="flex flex-wrap items-center gap-2">
          <span className="type-overline">פעולות מהירות</span>
          {canCreateEvent() && (
            <Button size="sm" variant="primary" onClick={() => setEventModal(true)}>
              <Plus size={ICON.sm} strokeWidth={STROKE} />
              אירוע חדש
            </Button>
          )}
          {has(PERM.TASKS_CREATE) && (
            <Button size="sm" onClick={() => setTaskDrawer({ open: true, id: null })}>
              <Plus size={ICON.sm} strokeWidth={STROKE} />
              משימה חדשה
            </Button>
          )}
          <Button size="sm" onClick={() => navigate(`/board?date=${today}`)}>
            <ClipboardList size={ICON.sm} strokeWidth={STROKE} />
            לוח היום
          </Button>
          <Button size="sm" onClick={() => navigate('/calendar')}>
            <Calendar size={ICON.sm} strokeWidth={STROKE} />
            לוח שנה
          </Button>
        </div>

        {/* ── timeline + status breakdown ─────────────────────────────────── */}
        <div className="grid gap-4 lg:grid-cols-3">
          <Card className="lg:col-span-2">
            <CardHeader
              title="ציר הזמן של היום"
              subtitle={fmtDate(today)}
              icon={<Clock size={ICON.md} strokeWidth={STROKE} />}
              actions={
                <Button size="sm" variant="ghost" onClick={() => navigate(`/board?date=${today}`)}>
                  ללוח העבודה
                </Button>
              }
            />
            <CardBody>
              {loadingToday ? (
                <SkeletonList rows={4} />
              ) : (
                <DayTimeline tasks={todayTasks} onOpen={openTask} />
              )}
            </CardBody>
          </Card>

          <Card>
            <CardHeader title="התפלגות לפי סטטוס" subtitle={`${totalByStatus} משימות בטווח`} />
            <CardBody>
              {isLoading || !stats ? (
                <Skeleton className="h-56 w-full" />
              ) : stats.by_status.length === 0 ? (
                <EmptyState compact art="table" title="אין נתונים בטווח" />
              ) : (
                <>
                  <div className="relative">
                    <ResponsiveContainer width="100%" height={180}>
                      <PieChart>
                        <Pie
                          data={stats.by_status}
                          dataKey="cnt"
                          nameKey="name"
                          innerRadius={58}
                          outerRadius={82}
                          paddingAngle={2}
                          stroke="none"
                        >
                          {stats.by_status.map((s, i) => (
                            <Cell key={i} fill={s.color} />
                          ))}
                        </Pie>
                        <RTooltip content={<ChartTooltip />} />
                      </PieChart>
                    </ResponsiveContainer>
                    <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
                      <span className="type-display tabular leading-none">{totalByStatus}</span>
                      <span className="type-caption text-ink-tertiary">משימות</span>
                    </div>
                  </div>
                  <div className="mt-4 space-y-2.5">
                    {stats.by_status.map((s) => (
                      <ProgressBar
                        key={s.name}
                        value={Number(s.cnt)}
                        max={totalByStatus}
                        color={s.color}
                        label={
                          <span className="flex items-center gap-1.5">
                            <span className="size-2 rounded-full" style={{ background: s.color }} />
                            {s.name}
                          </span>
                        }
                        hint={`${s.cnt} · ${Math.round((Number(s.cnt) / totalByStatus) * 100)}%`}
                      />
                    ))}
                  </div>
                </>
              )}
            </CardBody>
          </Card>
        </div>

        {/* Came from the client dashboard, kept for everyone: the tasks lists
            below answer "what is happening", this answers "what is booked". */}
        {!!stats?.next_events.length && (
          <Card>
            <CardHeader title="האירועים הקרובים" icon={<CalendarDays size={ICON.md} strokeWidth={STROKE} />} />
            <CardBody padded={false}>
              <ul>
                {stats.next_events.map((e) => (
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
        )}

        {/* ── task lists ──────────────────────────────────────────────────── */}
        <div className="grid gap-4 lg:grid-cols-3">
          <TaskListCard
            title="משימות היום"
            subtitle={`${todayTasks.length} משימות`}
            icon={<Clock size={ICON.md} strokeWidth={STROKE} />}
            tasks={todayTasks.slice(0, 8)}
            loading={loadingToday}
            emptyTitle="אין משימות היום"
            emptyDescription="יום פנוי — או שעדיין לא שובצו משימות"
            onOpen={openTask}
          />
          <TaskListCard
            title="משימות קרובות"
            subtitle="7 הימים הבאים"
            icon={<CalendarDays size={ICON.md} strokeWidth={STROKE} />}
            tasks={upcoming}
            loading={loadingUpcoming}
            showDate
            emptyTitle="אין משימות בשבוע הקרוב"
            emptyDescription="ניתן לשבץ משימות מלוח העבודה או מלוח השנה"
            onOpen={openTask}
          />
          <TaskListCard
            title="עודכן לאחרונה"
            subtitle="8 השינויים האחרונים"
            icon={<History size={ICON.md} strokeWidth={STROKE} />}
            tasks={recent}
            loading={loadingRecent}
            showDate
            showUpdated
            emptyTitle="אין פעילות אחרונה"
            emptyDescription="שינויים במשימות יופיעו כאן"
            onOpen={openTask}
          />
        </div>

        {/* ── charts ──────────────────────────────────────────────────────
            A section the reader holds no key for arrives as null rather than
            an empty array, and is dropped rather than drawn empty: an empty
            chart says "no data this range", which is a different claim.   */}
        {(stats?.by_customer || stats?.by_worker || stats?.by_contractor || isLoading) && (
          <div className="grid gap-4 lg:grid-cols-3">
            {(isLoading || stats?.by_customer) && (
              <ChartFrame title="משימות לפי לקוח" empty={!stats?.by_customer?.length} loading={isLoading}>
                <BarChart data={stats?.by_customer ?? []} margin={{ top: 4, right: 4, bottom: 4, left: -20 }}>
                  <XAxis dataKey="name" tick={{ fontSize: 11, fill: 'var(--vl-text-tertiary)' }} axisLine={false} tickLine={false} interval={0} angle={-25} textAnchor="end" height={54} />
                  <YAxis tick={{ fontSize: 11, fill: 'var(--vl-text-tertiary)' }} allowDecimals={false} axisLine={false} tickLine={false} />
                  <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip />} />
                  <Bar dataKey="cnt" name="משימות" radius={[6, 6, 0, 0]} maxBarSize={44}>
                    {(stats?.by_customer ?? []).map((c, i) => (
                      <Cell key={i} fill={c.color} />
                    ))}
                  </Bar>
                </BarChart>
              </ChartFrame>
            )}

            {(isLoading || stats?.by_worker) && (
              <ChartFrame title="עומס עובדים" subtitle="שיבוצים בטווח" empty={!stats?.by_worker?.length} loading={isLoading}>
                <BarChart data={stats?.by_worker ?? []} layout="vertical" margin={{ top: 4, right: 12, bottom: 4, left: 4 }}>
                  <XAxis type="number" tick={{ fontSize: 11, fill: 'var(--vl-text-tertiary)' }} allowDecimals={false} axisLine={false} tickLine={false} />
                  <YAxis type="category" dataKey="name" width={86} tick={{ fontSize: 11, fill: 'var(--vl-text-tertiary)' }} axisLine={false} tickLine={false} />
                  <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip />} />
                  <Bar dataKey="cnt" name="שיבוצים" fill="var(--vl-primary)" radius={[0, 6, 6, 0]} maxBarSize={18} />
                </BarChart>
              </ChartFrame>
            )}

            {(isLoading || stats?.by_contractor) && (
              <ChartFrame title="התפלגות קבלנים" empty={!stats?.by_contractor?.length} loading={isLoading}>
                <BarChart data={stats?.by_contractor ?? []} margin={{ top: 4, right: 4, bottom: 4, left: -20 }}>
                  <XAxis dataKey="name" tick={{ fontSize: 11, fill: 'var(--vl-text-tertiary)' }} axisLine={false} tickLine={false} interval={0} angle={-25} textAnchor="end" height={54} />
                  <YAxis tick={{ fontSize: 11, fill: 'var(--vl-text-tertiary)' }} allowDecimals={false} axisLine={false} tickLine={false} />
                  <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip />} />
                  <Bar dataKey="cnt" name="משימות" fill="#f59e0b" radius={[6, 6, 0, 0]} maxBarSize={44} />
                </BarChart>
              </ChartFrame>
            )}
          </div>
        )}

        <TaskDrawer
          open={taskDrawer.open}
          onClose={() => setTaskDrawer({ open: false, id: null })}
          taskId={taskDrawer.id}
        />
        <EventFormModal open={eventModal} onClose={() => setEventModal(false)} />
      </div>
    </RequirePermission>
  )
}
