import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router'
import { addDays, parseISO } from 'date-fns'
import {
  Button,
  Card,
  CardBody,
  CardHeader,
  SkeletonList,
  cx,
} from '../../../components/ui'
import {
  Calendar,
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  ClipboardList,
  Clock,
  FileText,
  History,
  ICON,
  PartyPopper,
  Plus,
  STROKE,
} from '../../../components/ui/icons'
import { fmtDate, fmtWeekday, fmtWeekdayShort, toISODate } from '../../../lib/dates'
import { PERM } from '../../../lib/permissions'
import { useAuth } from '../../../state/auth'
import { DayTimeline } from '../parts/DayTimeline'
import { TaskListCard } from '../parts/TaskListCard'
import { useDashboard } from '../dashboardContext'
import { useDrill } from '../useDrill'
import { isEntityId } from '../drill'
import { SeriesCard } from '../parts/SeriesCard'
import { pickForm } from '../seriesOpts'
import type { SeriesRow } from '../seriesOpts'
import { useBoardSlice, useDashboardStats } from '../dashboardQueries'
import type { BoardSlice } from '../dashboardQueries'
import type { WidgetProps } from '../dashboardTypes'

/* ===== today's timeline =================================================== */

export function DayTimelineWidget(_props: WidgetProps) {
  const navigate = useNavigate()
  const { today, openTask } = useDashboard()
  const [selectedDate, setSelectedDate] = useState(today)
  const { data = [], isLoading } = useBoardSlice('today', selectedDate)
  const selectedPillRef = useRef<HTMLButtonElement>(null)

  const isToday = selectedDate === today

  const handlePrevDay = () => {
    setSelectedDate((prev) => toISODate(addDays(parseISO(prev), -1)))
  }

  const handleNextDay = () => {
    setSelectedDate((prev) => toISODate(addDays(parseISO(prev), 1)))
  }

  const handleToday = () => {
    setSelectedDate(today)
  }

  // 31-day scroll strip centered around today (-15 to +15 days)
  const dayStrip = useMemo(() => {
    const base = parseISO(today)
    return Array.from({ length: 31 }, (_, i) => {
      const d = addDays(base, i - 15)
      return toISODate(d)
    })
  }, [today])

  useEffect(() => {
    selectedPillRef.current?.scrollIntoView({ inline: 'center', block: 'nearest', behavior: 'smooth' })
  }, [selectedDate])

  return (
    <Card>
      <CardHeader
        title="ציר הזמן של היום"
        subtitle={isToday ? fmtDate(today) : `${fmtWeekday(selectedDate)}, ${fmtDate(selectedDate)}`}
        icon={<Clock size={ICON.md} strokeWidth={STROKE} />}
        actions={
          <div className="flex items-center gap-1">
            {!isToday && (
              <Button size="sm" variant="outlined" onClick={handleToday}>
                היום
              </Button>
            )}
            <Button size="sm" variant="ghost" onClick={() => navigate(`/board?date=${selectedDate}`)}>
              ללוח העבודה
            </Button>
          </div>
        }
      />
      <CardBody className="space-y-3">
        {/* Day navigation & scroll strip */}
        <div className="flex items-center gap-1 border-b border-line-subtle pb-2">
          {/* RTL: ChevronRight is previous day, ChevronLeft is next day */}
          <Button
            size="sm"
            variant="ghost"
            onClick={handlePrevDay}
            title="יום קודם"
            aria-label="יום קודם"
            className="shrink-0"
          >
            <ChevronRight size={15} />
          </Button>

          {/* Horizontal scrollable days strip */}
          <div className="flex flex-1 items-center gap-1 overflow-x-auto py-0.5 no-scrollbar scroll-smooth">
            {dayStrip.map((d) => {
              const isSelected = d === selectedDate
              const isCurrentToday = d === today
              const dateObj = parseISO(d)
              const dayNum = dateObj.getDate()
              const weekday = fmtWeekdayShort(d)
              return (
                <button
                  key={d}
                  ref={isSelected ? selectedPillRef : undefined}
                  onClick={() => setSelectedDate(d)}
                  className={cx(
                    'flex shrink-0 flex-col items-center justify-center rounded-lg px-2.5 py-1 text-center transition-all',
                    isSelected
                      ? 'bg-brand-primary text-white shadow-xs font-semibold'
                      : 'hover:bg-subtle text-ink-secondary hover:text-ink'
                  )}
                >
                  <span className="type-caption text-[11px] opacity-80">{weekday}</span>
                  <span className="type-caption font-bold text-xs">{dayNum}</span>
                  {isCurrentToday && (
                    <span
                      className={cx(
                        'size-1 rounded-full mt-0.5',
                        isSelected ? 'bg-white' : 'bg-brand-primary'
                      )}
                    />
                  )}
                </button>
              )
            })}
          </div>

          <Button
            size="sm"
            variant="ghost"
            onClick={handleNextDay}
            title="יום הבא"
            aria-label="יום הבא"
            className="shrink-0"
          >
            <ChevronLeft size={15} />
          </Button>
        </div>

        {isLoading ? (
          <SkeletonList rows={4} />
        ) : (
          <DayTimeline tasks={data} onOpen={openTask} isToday={isToday} />
        )}
      </CardBody>
    </Card>
  )
}

/* ===== status breakdown ===================================================
   A donut *and* a bar per status was two pictures of one number stacked in one
   card: 180px of donut plus a row per status, which on a busy month ran to
   twice the height of every card beside it — and on a quiet one left the
   bottom half of the card empty. It is one picture now, and which picture is
   the reader's to choose: the donut answers "what is the shape of the month",
   the list answers "how many, exactly", and the table answers both.         */

/** the donut was this card's face, so it stays first */
export const STATUS_FORMS = ['donut', 'list', 'bar', 'row', 'table'] as const

export function StatusBreakdownWidget({ height, opts }: WidgetProps) {
  const { range } = useDashboard()
  const { data, isLoading, error, refetch } = useDashboardStats(range.from, range.to)
  const raw = data?.by_status
  const go = useDrill({ to: 'board' })
  const total = (raw ?? []).reduce((s, x) => s + Number(x.cnt), 0)

  const rows: SeriesRow[] | undefined = raw?.map((r) => ({
    key: r.id ?? r.name,
    label: r.name,
    value: Number(r.cnt),
    color: r.color,
    hint: total > 0 ? `${r.cnt} · ${Math.round((Number(r.cnt) / total) * 100)}%` : undefined,
  }))

  return (
    <SeriesCard
      title="התפלגות לפי סטטוס"
      subtitle={`${total} משימות בטווח`}
      rows={rows}
      loading={isLoading && !data}
      error={error}
      onRetry={() => void refetch()}
      form={pickForm(STATUS_FORMS, opts)}
      height={height}
      opts={opts}
      seriesName="משימות"
      emptyTitle="אין משימות בטווח"
      emptyDescription="משימה שתיווצר תופיע כאן לפי הסטטוס שלה"
      /* The one drill this card has been implying since it was drawn: a slice
         is a status, and the board can open filtered to it. Before 0151 the row
         carried only a name, so the click had nowhere exact to go.

         `date` travels with it. The donut counts the *dashboard's* range and
         the board opens on a month — without it, clicking a slice while looking
         at July landed on the current month with the filter applied and
         usually no rows at all, which says the opposite of the number that was
         clicked. The board is a month at a time, so this is the month the
         range starts in and not the range itself. */
      onSelect={
        go && ((r) => go({ to: 'board', date: range.from, status: isEntityId(r.key) ? r.key : undefined }))
      }
    />
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

/* ===== quick actions ======================================================
   A full-width strip holding four small buttons and a label was the emptiest
   thing on the page: a row of its own, most of it whitespace, and nothing in it
   that a reader could not reach from the sidebar anyway.

   It is now a grid of tiles that fills whatever width it is given — two on a
   phone, up to six on a wide screen — and it offers every destination the
   reader actually holds a key for rather than the same four for everybody. The
   two that create something stay first and stay marked, because "new event" is
   the reason anyone looks at this card.                                       */

interface QuickAction {
  key: string
  label: string
  hint: string
  icon: typeof Plus
  primary?: boolean
  run: () => void
}

export function QuickActionsWidget(_props: WidgetProps) {
  const navigate = useNavigate()
  const { today, openNewTask, openNewEvent } = useDashboard()
  const { has, canCreateEvent } = useAuth()

  const actions: QuickAction[] = []
  if (canCreateEvent())
    actions.push({
      key: 'event',
      label: 'אירוע חדש',
      hint: 'פתיחת אירוע ולקוח',
      icon: Plus,
      primary: true,
      run: openNewEvent,
    })
  if (has(PERM.TASKS_CREATE) && openNewTask)
    actions.push({ key: 'task', label: 'משימה חדשה', hint: 'משימה בודדת', icon: Plus, primary: true, run: openNewTask })
  if (has(PERM.BOARD_VIEW))
    actions.push({
      key: 'board',
      label: 'לוח היום',
      hint: fmtDate(today),
      icon: ClipboardList,
      run: () => navigate(`/board?date=${today}`),
    })
  if (has(PERM.CALENDAR_VIEW))
    actions.push({ key: 'calendar', label: 'לוח שנה', hint: 'החודש', icon: Calendar, run: () => navigate('/calendar') })
  if (has(PERM.EVENTS_LIST))
    actions.push({ key: 'events', label: 'אירועים', hint: 'הרשימה', icon: PartyPopper, run: () => navigate('/events') })
  if (has(PERM.REPORTS_VIEW))
    actions.push({ key: 'reports', label: 'דוחות', hint: 'בונה הדוחות', icon: FileText, run: () => navigate('/reports') })

  if (actions.length === 0) return null

  return (
    <Card>
      <CardHeader title="פעולות מהירות" compact />
      <CardBody>
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-6">
          {actions.map((a) => (
            <button
              key={a.key}
              type="button"
              onClick={a.run}
              className={cx(
                'flex items-center gap-2.5 rounded-xl border px-3 py-2.5 text-start transition-colors',
                a.primary
                  ? 'border-primary-border bg-primary-subtle/50 hover:bg-primary-subtle'
                  : 'border-line hover:border-line-strong hover:bg-hover',
              )}
            >
              <span
                className={cx(
                  'flex size-8 shrink-0 items-center justify-center rounded-lg',
                  a.primary ? 'bg-primary text-on-primary' : 'bg-subtle text-ink-secondary',
                )}
                aria-hidden
              >
                <a.icon size={ICON.md} strokeWidth={STROKE} />
              </span>
              <span className="min-w-0">
                <span className="block truncate type-body font-semibold">{a.label}</span>
                <span className="block truncate type-caption text-ink-tertiary">{a.hint}</span>
              </span>
            </button>
          ))}
        </div>
      </CardBody>
    </Card>
  )
}
