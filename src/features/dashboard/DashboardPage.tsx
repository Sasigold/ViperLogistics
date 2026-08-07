import { useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import { addDays, differenceInCalendarDays, endOfMonth, startOfMonth, startOfWeek, subDays } from 'date-fns'
import { Bar, BarChart, Cell, Pie, PieChart, ResponsiveContainer, Tooltip as RTooltip, XAxis, YAxis } from 'recharts'
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
  AvatarGroup,
  Button,
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  PageHeader,
  ProgressBar,
  Skeleton,
  SkeletonCard,
  SkeletonList,
  StatCard,
  StatusPill,
  Tooltip,
  fmtMoney,
  fmtRelative,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { fmtDate, fmtTime, toISODate } from '../../lib/dates'
import { useIsPhone } from '../../lib/useMediaQuery'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { TaskDrawer } from '../tasks/TaskDrawer'
import { EventFormModal } from '../events/EventFormModal'
import type { WorkBoardRow } from '../../types/domain'

interface Stats {
  events_count: number
  tasks_count: number
  tasks_today: number
  tasks_week: number
  tasks_overdue: number
  available_workers: number
  by_customer: { name: string; color: string; cnt: number }[]
  by_contractor: { name: string; cnt: number }[]
  by_worker: { name: string; cnt: number }[]
  by_status: { name: string; color: string; cnt: number }[]
  /** null כשאין למשתמש pricing.revenue — ה-RPC מחזיר null ולא מסתיר את המפתח */
  revenue: { total: number; priced_tasks: number; by_customer: { name: string; color: string; total: number }[] } | null
}

const CHART_H = 250

/* Recharts' default tooltip ignores the theme; this one uses our surfaces. */
function ChartTooltip({ active, payload, label }: { active?: boolean; payload?: { name?: string; value?: number; payload?: { name?: string } }[]; label?: string }) {
  if (!active || !payload?.length) return null
  return (
    <div className="rounded-lg border border-line bg-raised px-2.5 py-1.5 shadow-lg">
      <p className="type-caption font-semibold text-ink">{label ?? payload[0]?.payload?.name}</p>
      {payload.map((p, i) => (
        <p key={i} className="type-caption tabular text-ink-secondary">
          {p.name}: <span className="font-bold text-ink">{p.value}</span>
        </p>
      ))}
    </div>
  )
}

export default function DashboardPage() {
  const navigate = useNavigate()
  const { has } = useAuth()
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

  const { data: stats, isLoading } = useQuery({
    queryKey: ['dashboard', from, to],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('dashboard_stats', { p_from: from, p_to: to })
      if (error) throw error
      return data as Stats
    },
  })

  const { data: prev } = useQuery({
    queryKey: ['dashboard', prevRange.from, prevRange.to],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('dashboard_stats', { p_from: prevRange.from, p_to: prevRange.to })
      if (error) throw error
      return data as Stats
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
              <div className="flex items-center gap-1.5">
                <input
                  type="date"
                  value={from}
                  onChange={(e) => setFrom(e.target.value)}
                  aria-label="מתאריך"
                  className="h-9 min-w-0 flex-1 rounded-md border border-line bg-surface px-2 text-[0.8125rem] tabular outline-none focus:border-primary focus:ring-2 focus:ring-[var(--vl-focus-ring)] sm:h-8 sm:flex-none"
                />
                <span className="shrink-0 type-caption text-ink-tertiary">–</span>
                <input
                  type="date"
                  value={to}
                  onChange={(e) => setTo(e.target.value)}
                  aria-label="עד תאריך"
                  className="h-9 min-w-0 flex-1 rounded-md border border-line bg-surface px-2 text-[0.8125rem] tabular outline-none focus:border-primary focus:ring-2 focus:ring-[var(--vl-focus-ring)] sm:h-8 sm:flex-none"
                />
              </div>
            </div>
          }
        />

        {/* ── KPIs ─────────────────────────────────────────────────────────
            Only the two range-scoped metrics carry a delta: the rest are
            "as of today" and have no previous-period equivalent.          */}
        {isLoading || !stats ? (
          <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
            {Array.from({ length: 6 }).map((_, i) => (
              <SkeletonCard key={i} lines={0} />
            ))}
          </div>
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
            <StatCard
              icon={<Users size={ICON.xl} strokeWidth={STROKE} />}
              label="עובדים זמינים היום"
              value={stats.available_workers}
              tone="#22c55e"
              onClick={() => navigate('/users')}
            />
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
          {has(PERM.EVENTS_CREATE) && (
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

        {/* ── charts ──────────────────────────────────────────────────────── */}
        <div className="grid gap-4 lg:grid-cols-3">
          <ChartCard title="משימות לפי לקוח" empty={!stats?.by_customer.length} loading={isLoading}>
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
          </ChartCard>

          <ChartCard title="עומס עובדים" subtitle="שיבוצים בטווח" empty={!stats?.by_worker.length} loading={isLoading}>
            <BarChart data={stats?.by_worker ?? []} layout="vertical" margin={{ top: 4, right: 12, bottom: 4, left: 4 }}>
              <XAxis type="number" tick={{ fontSize: 11, fill: 'var(--vl-text-tertiary)' }} allowDecimals={false} axisLine={false} tickLine={false} />
              <YAxis type="category" dataKey="name" width={86} tick={{ fontSize: 11, fill: 'var(--vl-text-tertiary)' }} axisLine={false} tickLine={false} />
              <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip />} />
              <Bar dataKey="cnt" name="שיבוצים" fill="var(--vl-primary)" radius={[0, 6, 6, 0]} maxBarSize={18} />
            </BarChart>
          </ChartCard>

          <ChartCard title="התפלגות קבלנים" empty={!stats?.by_contractor.length} loading={isLoading}>
            <BarChart data={stats?.by_contractor ?? []} margin={{ top: 4, right: 4, bottom: 4, left: -20 }}>
              <XAxis dataKey="name" tick={{ fontSize: 11, fill: 'var(--vl-text-tertiary)' }} axisLine={false} tickLine={false} interval={0} angle={-25} textAnchor="end" height={54} />
              <YAxis tick={{ fontSize: 11, fill: 'var(--vl-text-tertiary)' }} allowDecimals={false} axisLine={false} tickLine={false} />
              <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip />} />
              <Bar dataKey="cnt" name="משימות" fill="#f59e0b" radius={[6, 6, 0, 0]} maxBarSize={44} />
            </BarChart>
          </ChartCard>
        </div>

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

/* ===== chart shell ======================================================== */

function ChartCard({
  title,
  subtitle,
  children,
  empty,
  loading,
}: {
  title: string
  subtitle?: string
  children: React.ReactElement
  empty?: boolean
  loading?: boolean
}) {
  return (
    <Card>
      <CardHeader title={title} subtitle={subtitle} />
      <CardBody>
        {loading ? (
          <Skeleton className="w-full" style={{ height: CHART_H }} />
        ) : empty ? (
          <div style={{ height: CHART_H }} className="flex items-center justify-center">
            <EmptyState compact art="table" title="אין נתונים בטווח" />
          </div>
        ) : (
          <ResponsiveContainer width="100%" height={CHART_H}>
            {children}
          </ResponsiveContainer>
        )}
      </CardBody>
    </Card>
  )
}

/* ===== today's timeline ===================================================
   Tasks laid on an hour axis so overlaps and gaps are visible at a glance.
   Everything is derived from onsite_start_time / hours_count — no new data. */

function DayTimeline({ tasks, onOpen }: { tasks: WorkBoardRow[]; onOpen: (id: string) => void }) {
  const timed = tasks.filter((t) => t.onsite_start_time)
  const untimed = tasks.filter((t) => !t.onsite_start_time)
  /* An hour axis needs horizontal room to mean anything: on a phone every bar
     collapses to a sliver and the ruler's labels collide. There the same tasks
     are simply listed in time order. */
  const isPhone = useIsPhone()

  const { startHour, endHour } = useMemo(() => {
    if (timed.length === 0) return { startHour: 6, endHour: 22 }
    let min = 24
    let max = 0
    for (const t of timed) {
      const s = Number(t.onsite_start_time!.slice(0, 2))
      const dur = t.hours_count ?? 2
      const e = t.onsite_end_time ? Number(t.onsite_end_time.slice(0, 2)) + 1 : s + Math.ceil(dur)
      min = Math.min(min, s)
      max = Math.max(max, e)
    }
    return { startHour: Math.max(0, min - 1), endHour: Math.min(24, Math.max(max + 1, min + 4)) }
  }, [timed])

  const span = Math.max(1, endHour - startHour)
  const pos = (time: string) => {
    const [h, m] = time.split(':').map(Number)
    return ((h + m / 60 - startHour) / span) * 100
  }

  if (tasks.length === 0)
    return <EmptyState compact art="check" title="אין משימות מתוזמנות היום" description="לוח נקי — אין מה לתאם" />

  const hours = Array.from({ length: span + 1 }, (_, i) => startHour + i)

  return (
    <div className="space-y-3">
      {timed.length > 0 && isPhone && (
        <ul className="space-y-1.5">
          {timed.map((t) => {
            const label = t.end_client_name || t.title || t.customer_name || t.task_type_name
            const team = [...(t.workers ?? []).map((w) => w.name), ...(t.drivers ?? []).map((d) => d.name)]
            return (
              <li key={t.id}>
                <button
                  onClick={() => onOpen(t.id)}
                  className="flex w-full items-center gap-2 rounded-lg p-2 text-start transition-colors hover:bg-hover"
                >
                  <span
                    aria-hidden
                    className="h-8 w-1 shrink-0 rounded-full"
                    style={{ background: t.customer_color ?? '#64748b' }}
                  />
                  <span className="shrink-0 type-caption font-bold tabular" dir="ltr">
                    {fmtTime(t.onsite_start_time)}
                    {t.onsite_end_time && `–${fmtTime(t.onsite_end_time)}`}
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate type-body font-medium">{label}</span>
                    <span className="block truncate type-caption text-ink-tertiary">{t.task_type_name}</span>
                  </span>
                  {team.length > 0 && <AvatarGroup names={team} max={2} size="xs" />}
                </button>
              </li>
            )
          })}
        </ul>
      )}

      {timed.length > 0 && !isPhone && (
        <div>
          {/* hour ruler */}
          <div className="relative mb-1.5 h-4">
            {hours.map((h) => (
              <span
                key={h}
                className="absolute -translate-x-1/2 type-caption tabular text-ink-tertiary rtl:translate-x-1/2"
                style={{ insetInlineStart: `${((h - startHour) / span) * 100}%` }}
              >
                {String(h).padStart(2, '0')}
              </span>
            ))}
          </div>

          <div className="max-h-64 space-y-1 overflow-y-auto pe-1">
            {timed.map((t) => {
              const start = pos(t.onsite_start_time!)
              const endTime = t.onsite_end_time
              const width = endTime
                ? Math.max(6, pos(endTime) - start)
                : Math.max(6, ((t.hours_count ?? 2) / span) * 100)
              const label = t.end_client_name || t.title || t.customer_name || t.task_type_name
              const team = [...(t.workers ?? []).map((w) => w.name), ...(t.drivers ?? []).map((d) => d.name)]
              return (
                <div key={t.id} className="relative h-8 rounded-md bg-subtle/50">
                  {/* hour gridlines */}
                  {hours.map((h) => (
                    <span
                      key={h}
                      aria-hidden
                      className="absolute inset-y-0 w-px bg-line-subtle"
                      style={{ insetInlineStart: `${((h - startHour) / span) * 100}%` }}
                    />
                  ))}
                  <Tooltip
                    content={
                      <span className="block space-y-0.5">
                        <span className="block font-bold">{label}</span>
                        <span className="block opacity-80">{t.task_type_name}</span>
                        <span className="block tabular opacity-80">
                          {fmtTime(t.onsite_start_time)}
                          {endTime && ` – ${fmtTime(endTime)}`}
                        </span>
                        {t.location_text && <span className="block opacity-70">{t.location_text}</span>}
                      </span>
                    }
                  >
                    <button
                      onClick={() => onOpen(t.id)}
                      className="absolute inset-y-0.5 flex items-center gap-1.5 overflow-hidden rounded px-1.5 text-start shadow-xs transition-[filter] hover:brightness-105 focus-visible:outline-none focus-visible:focus-ring"
                      style={{
                        insetInlineStart: `${Math.max(0, Math.min(start, 97))}%`,
                        width: `${Math.min(width, 100 - Math.max(0, Math.min(start, 97)))}%`,
                        background: `color-mix(in srgb, ${t.customer_color ?? '#64748b'} 18%, transparent)`,
                        borderInlineStart: `3px solid ${t.customer_color ?? '#64748b'}`,
                      }}
                    >
                      <span className="truncate type-caption font-semibold text-ink">{label}</span>
                      {team.length > 0 && <AvatarGroup names={team} max={2} size="xs" />}
                    </button>
                  </Tooltip>
                </div>
              )
            })}
          </div>
        </div>
      )}

      {untimed.length > 0 && (
        <div className="rounded-lg border border-dashed border-line p-2.5">
          <p className="mb-1.5 type-caption font-semibold text-ink-tertiary">ללא שעה ({untimed.length})</p>
          <div className="flex flex-wrap gap-1.5">
            {untimed.map((t) => (
              <button
                key={t.id}
                onClick={() => onOpen(t.id)}
                className="inline-flex items-center gap-1.5 rounded-full border border-line bg-surface px-2 py-0.5 type-caption transition-colors hover:bg-hover"
              >
                <span className="size-1.5 rounded-full" style={{ background: t.customer_color ?? '#64748b' }} />
                {t.end_client_name || t.title || t.task_type_name}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

/* ===== compact task list ================================================== */

function TaskListCard({
  title,
  subtitle,
  icon,
  tasks,
  loading,
  showDate,
  showUpdated,
  emptyTitle,
  emptyDescription,
  onOpen,
}: {
  title: string
  subtitle?: string
  icon?: React.ReactNode
  tasks: WorkBoardRow[]
  loading?: boolean
  showDate?: boolean
  showUpdated?: boolean
  emptyTitle: string
  emptyDescription?: string
  onOpen: (id: string) => void
}) {
  return (
    <Card>
      <CardHeader
        title={title}
        subtitle={subtitle}
        icon={icon}
        actions={
          <Link to="/board" className="rounded px-1.5 py-1 type-caption text-primary-text transition-colors hover:bg-hover">
            הכל
          </Link>
        }
      />
      <CardBody padded={false}>
        {loading ? (
          <div className="p-4">
            <SkeletonList rows={4} />
          </div>
        ) : tasks.length === 0 ? (
          <EmptyState compact art="check" title={emptyTitle} description={emptyDescription} />
        ) : (
          <ul>
            {tasks.map((t) => {
              const label = t.end_client_name || t.title || t.customer_name || t.task_type_name
              const time = fmtTime(t.onsite_start_time)
              return (
                <li key={t.id}>
                  <button
                    onClick={() => onOpen(t.id)}
                    className="flex w-full items-center gap-2.5 border-b border-line-subtle px-4 py-2.5 text-start transition-colors last:border-0 hover:bg-hover"
                  >
                    <span
                      className="h-8 w-1 shrink-0 rounded-full"
                      style={{ background: t.customer_color ?? 'var(--vl-border-strong)' }}
                      aria-hidden
                    />
                    <span className="min-w-0 flex-1">
                      <span className="flex items-center gap-1.5">
                        <span className="truncate type-body font-medium">{label}</span>
                      </span>
                      <span className="flex items-center gap-1.5 type-caption text-ink-tertiary">
                        <span className="truncate">{t.task_type_name}</span>
                        {showDate && <span className="tabular">· {fmtDate(t.task_date)}</span>}
                        {time && !showUpdated && (
                          <span className="tabular" dir="ltr">
                            · {time}
                          </span>
                        )}
                        {showUpdated && <span>· {fmtRelative(t.updated_at)}</span>}
                      </span>
                    </span>
                    <StatusPill color={t.status_color} className="shrink-0">
                      {t.status_name}
                    </StatusPill>
                  </button>
                </li>
              )
            })}
          </ul>
        )}
      </CardBody>
    </Card>
  )
}
