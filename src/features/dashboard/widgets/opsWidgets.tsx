import { useNavigate } from 'react-router'
import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip as RTooltip } from 'recharts'
import {
  Button,
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  ProgressBar,
  Skeleton,
  SkeletonList,
} from '../../../components/ui'
import { Calendar, CalendarDays, ClipboardList, Clock, History, ICON, Plus, STROKE } from '../../../components/ui/icons'
import { fmtDate } from '../../../lib/dates'
import { PERM } from '../../../lib/permissions'
import { useAuth } from '../../../state/auth'
import { ChartTooltip } from '../parts/ChartTooltip'
import { DayTimeline } from '../parts/DayTimeline'
import { TaskListCard } from '../parts/TaskListCard'
import { useDashboard } from '../dashboardContext'
import { useBoardSlice, useDashboardStats } from '../dashboardQueries'
import type { BoardSlice } from '../dashboardQueries'
import type { WidgetProps } from '../dashboardTypes'

/* ===== today's timeline =================================================== */

export function DayTimelineWidget(_props: WidgetProps) {
  const navigate = useNavigate()
  const { today, openTask } = useDashboard()
  const { data = [], isLoading } = useBoardSlice('today', today)

  return (
    <Card>
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
      <CardBody>{isLoading ? <SkeletonList rows={4} /> : <DayTimeline tasks={data} onOpen={openTask} />}</CardBody>
    </Card>
  )
}

/* ===== status breakdown ===================================================
   A donut plus a bar per status. The donut answers "what is the shape of the
   month", the bars answer "how many, exactly" — which a donut cannot.       */

export function StatusBreakdownWidget({ height }: WidgetProps) {
  const { range } = useDashboard()
  const { data, isLoading } = useDashboardStats(range.from, range.to)
  const rows = data?.by_status ?? []
  const total = rows.reduce((s, x) => s + Number(x.cnt), 0)

  return (
    <Card>
      <CardHeader title="התפלגות לפי סטטוס" subtitle={`${total} משימות בטווח`} />
      <CardBody>
        {isLoading || !data ? (
          <Skeleton className="w-full" style={{ height }} />
        ) : rows.length === 0 ? (
          <EmptyState compact art="table" title="אין נתונים בטווח" />
        ) : (
          <>
            <div className="relative">
              <ResponsiveContainer width="100%" height={180}>
                <PieChart>
                  <Pie
                    data={rows}
                    dataKey="cnt"
                    nameKey="name"
                    innerRadius={58}
                    outerRadius={82}
                    paddingAngle={2}
                    stroke="none"
                  >
                    {rows.map((s, i) => (
                      <Cell key={i} fill={s.color} />
                    ))}
                  </Pie>
                  <RTooltip content={<ChartTooltip />} />
                </PieChart>
              </ResponsiveContainer>
              <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
                <span className="type-display tabular leading-none">{total}</span>
                <span className="type-caption text-ink-tertiary">משימות</span>
              </div>
            </div>
            <div className="mt-4 space-y-2.5">
              {rows.map((s) => (
                <ProgressBar
                  key={s.name}
                  value={Number(s.cnt)}
                  max={total}
                  color={s.color}
                  label={
                    <span className="flex items-center gap-1.5">
                      <span className="size-2 rounded-full" style={{ background: s.color }} />
                      {s.name}
                    </span>
                  }
                  hint={`${s.cnt} · ${Math.round((Number(s.cnt) / total) * 100)}%`}
                />
              ))}
            </div>
          </>
        )}
      </CardBody>
    </Card>
  )
}

/* ===== the three task lists =============================================== */

function taskList(cfg: {
  slice: BoardSlice
  title: string
  subtitle?: string
  icon: typeof Clock
  showDate?: boolean
  showUpdated?: boolean
  emptyTitle: string
  emptyDescription?: string
  limit?: number
}) {
  function TaskListWidget(_props: WidgetProps) {
    const { today, openTask } = useDashboard()
    const { data = [], isLoading } = useBoardSlice(cfg.slice, today)
    const Icon = cfg.icon
    const rows = cfg.limit ? data.slice(0, cfg.limit) : data
    return (
      <TaskListCard
        title={cfg.title}
        subtitle={cfg.subtitle ?? `${data.length} משימות`}
        icon={<Icon size={ICON.md} strokeWidth={STROKE} />}
        tasks={rows}
        loading={isLoading}
        showDate={cfg.showDate}
        showUpdated={cfg.showUpdated}
        emptyTitle={cfg.emptyTitle}
        emptyDescription={cfg.emptyDescription}
        onOpen={openTask}
      />
    )
  }
  TaskListWidget.displayName = `TaskList(${cfg.slice})`
  return TaskListWidget
}

export const TodayListWidget = taskList({
  slice: 'today',
  title: 'משימות היום',
  icon: Clock,
  limit: 8,
  emptyTitle: 'אין משימות היום',
  emptyDescription: 'יום פנוי — או שעדיין לא שובצו משימות',
})

export const UpcomingListWidget = taskList({
  slice: 'upcoming',
  title: 'משימות קרובות',
  subtitle: '7 הימים הבאים',
  icon: CalendarDays,
  showDate: true,
  emptyTitle: 'אין משימות בשבוע הקרוב',
  emptyDescription: 'ניתן לשבץ משימות מלוח העבודה או מלוח השנה',
})

export const RecentListWidget = taskList({
  slice: 'recent',
  title: 'עודכן לאחרונה',
  subtitle: '8 השינויים האחרונים',
  icon: History,
  showDate: true,
  showUpdated: true,
  emptyTitle: 'אין פעילות אחרונה',
  emptyDescription: 'שינויים במשימות יופיעו כאן',
})

/* ===== quick actions ====================================================== */

export function QuickActionsWidget(_props: WidgetProps) {
  const navigate = useNavigate()
  const { today, openNewTask, openNewEvent } = useDashboard()
  const { has, canCreateEvent } = useAuth()

  return (
    <div className="flex flex-wrap items-center gap-2">
      <span className="type-overline">פעולות מהירות</span>
      {canCreateEvent() && (
        <Button size="sm" variant="primary" onClick={openNewEvent}>
          <Plus size={ICON.sm} strokeWidth={STROKE} />
          אירוע חדש
        </Button>
      )}
      {has(PERM.TASKS_CREATE) && (
        <Button size="sm" onClick={openNewTask}>
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
  )
}
