import { Link } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import { Button, Card, CardBody, CardHeader, EmptyState, fmtMoney } from '../../../components/ui'
import { AlertTriangle, CalendarDays, ICON, Plus, STROKE } from '../../../components/ui/icons'
import { supabase } from '../../../lib/supabase'
import { TaskListCard } from '../parts/TaskListCard'
import { fmtDate } from '../../../lib/dates'
import { SeriesCard } from '../parts/SeriesCard'
import { CATEGORY_FORMS, RANK_FORMS, pickForm } from '../seriesOpts'
import type { SeriesRow } from '../seriesOpts'
import { useDashboard } from '../dashboardContext'
import { useDashboardStats } from '../dashboardQueries'
import { useCustomerDrill, useDrill } from '../useDrill'
import { isEntityId } from '../drill'
import type { DrillTarget } from '../drill'
import type { WidgetProps } from '../dashboardTypes'
import type { DashboardStats, WorkBoardRow } from '../../../types/domain'

/**
 * Counted categories.
 *
 * Was a bar chart and nothing else. It is now a `SeriesCard`, which is the
 * same bar chart until somebody asks for a different one — the rows are
 * already in hand, so a donut or a table costs a re-render and no round trip.
 * `drill` is the other half: a bar you can press is the difference between
 * "four for that customer" and "which four".
 */
function categoryBars(cfg: {
  title: string
  subtitle?: string
  select: (
    s: DashboardStats,
  ) => { id?: string; name: string; cnt: number | string; color?: string }[] | null | undefined
  fill?: string
  seriesName: string
  forms?: readonly ('bar' | 'row' | 'donut' | 'table' | 'list')[]
  /** where one row leads; the probe decides whether the click is offered at all */
  drill?: { probe: DrillTarget; of: (row: SeriesRow) => DrillTarget }
  /** the row's label is a customer's name — resolved to an id, see `useCustomerDrill` */
  customerDrill?: boolean
  emptyTitle?: string
  emptyDescription?: string
  emptyAction?: 'newEvent'
}) {
  const forms = cfg.forms ?? CATEGORY_FORMS
  function CategoryBarsWidget({ height, opts }: WidgetProps) {
    const { range, openNewEvent } = useDashboard()
    const { data, isLoading, error, refetch } = useDashboardStats(range.from, range.to)
    const raw = data ? cfg.select(data) : undefined
    const go = useDrill(cfg.drill?.probe ?? { to: 'events' })
    const toCustomer = useCustomerDrill(!!cfg.customerDrill && !!go)

    // null means the reader holds no key for this section — the widget is
    // omitted rather than drawn empty, because an empty chart claims "no data
    // in range", which is a different and wrong statement
    if (!isLoading && data && (raw === null || raw === undefined)) return null

    /* `key` is the entity id from 0151 and falls back to the name against an
       older server — which is exactly what `isEntityId` asks about before a
       drill uses it as one. */
    const rows: SeriesRow[] | undefined = raw?.map((r) => ({
      key: r.id ?? r.name,
      label: r.name,
      value: Number(r.cnt),
      color: r.color,
    }))

    return (
      <SeriesCard
        title={cfg.title}
        subtitle={cfg.subtitle}
        rows={rows}
        loading={isLoading}
        error={error}
        onRetry={() => void refetch()}
        form={pickForm(forms, opts)}
        height={height}
        opts={opts}
        seriesName={cfg.seriesName}
        fill={cfg.fill}
        emptyTitle={cfg.emptyTitle ?? 'אין נתונים בטווח'}
        emptyDescription={cfg.emptyDescription}
        emptyAction={
          cfg.emptyAction === 'newEvent' ? (
            <Button size="sm" onClick={openNewEvent}>
              <Plus size={ICON.sm} strokeWidth={STROKE} />
              אירוע חדש
            </Button>
          ) : undefined
        }
        onSelect={
          go && cfg.drill
            ? (r) =>
                go(
                  isEntityId(r.key) || !toCustomer ? cfg.drill!.of(r) : toCustomer(r.label),
                )
            : undefined
        }
      />
    )
  }
  CategoryBarsWidget.displayName = `CategoryBars(${cfg.title})`
  return CategoryBarsWidget
}

export const TasksByCustomerWidget = categoryBars({
  title: 'משימות לפי לקוח',
  select: (s) => s.by_customer,
  seriesName: 'משימות',
  /* Since 0151 the row carries the customer's id, so the click filters the
     events list to that customer exactly. `useCustomerDrill` is the fallback
     for a server that has not had the migration: it resolves the name through
     the customers list rather than guessing. */
  drill: {
    probe: { to: 'events' },
    of: (r) => (isEntityId(r.key) ? { to: 'events', customer: r.key } : { to: 'events' }),
  },
  customerDrill: true,
  emptyDescription: 'אין משימות משויכות ללקוח בטווח שנבחר',
  emptyAction: 'newEvent',
})

export const ContractorSplitWidget = categoryBars({
  title: 'התפלגות קבלנים',
  select: (s) => s.by_contractor,
  seriesName: 'משימות',
  fill: '#f59e0b',
  /* 0151 again: the row is a contractor, and a contractor has a card. */
  drill: {
    probe: { to: 'contractors' },
    of: (r) => (isEntityId(r.key) ? { to: 'contractor', id: r.key } : { to: 'contractors' }),
  },
  emptyDescription: 'לא הואצלו משימות לקבלנים בטווח',
})

/* ===== worker load ========================================================
   Horizontal first, unlike the others: these are people's names, and a name
   tilted at 25° on a bottom axis is a name you have to lean sideways to read.
   It is only first now, not only — the reader can still ask for the rest.   */

export const WorkerLoadWidget = categoryBars({
  title: 'עומס עובדים',
  subtitle: 'שיבוצים בטווח',
  select: (s) => s.by_worker,
  seriesName: 'שיבוצים',
  forms: RANK_FORMS,
  drill: { probe: { to: 'shifts' }, of: () => ({ to: 'shifts' }) },
  emptyDescription: 'אין שיבוצים בטווח שנבחר',
})

/* ===== what is booked =====================================================
   The task lists answer "what is happening"; this answers "what is booked".  */

export function NextEventsWidget(_props: WidgetProps) {
  const { range, openNewEvent } = useDashboard()
  const { data, isLoading } = useDashboardStats(range.from, range.to)
  const events = data?.next_events ?? []

  /* Until 0151 this returned `null` with nothing booked — and it is a
     full-width card that ships on by default, so the commonest state of a quiet
     month was a silent gap in the middle of the page. An empty state that says
     so, and offers the one action that would fill it, is both more honest and
     the reason the gap is no longer a gap. `null` is still the answer while the
     stats have not landed: a skeleton belongs to the tiles. */
  if (isLoading && !data) return null

  return (
    <Card>
      <CardHeader title="האירועים הקרובים" icon={<CalendarDays size={ICON.md} strokeWidth={STROKE} />} />
      <CardBody padded={events.length === 0}>
        {events.length === 0 ? (
          <EmptyState
            compact
            art="calendar"
            title="אין אירועים קרובים"
            description="אירוע שייקבע יופיע כאן ובלוח השנה"
            action={
              <Button size="sm" onClick={openNewEvent}>
                <Plus size={ICON.sm} strokeWidth={STROKE} />
                אירוע חדש
              </Button>
            }
          />
        ) : (
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
        )}
      </CardBody>
    </Card>
  )
}

/* ===== customer concentration =============================================
   The same numbers as "הכנסות לפי לקוח", asked a different question: not who
   pays the most, but how much of the business rests on one of them. */

/** the list form was this card's only form until 0151 — so it stays first */
export const MIX_FORMS = ['list', 'donut', 'row', 'bar', 'table'] as const

export function CustomerMixWidget({ height, opts }: WidgetProps) {
  const { range } = useDashboard()
  const { data: stats, isLoading, error, refetch } = useDashboardStats(range.from, range.to)
  const raw = stats?.revenue?.by_customer
  const go = useDrill({ to: 'events' })
  const toCustomer = useCustomerDrill(!!go)
  if (stats && !raw) return null

  const total = (raw ?? []).reduce((s, r) => s + Number(r.total), 0)
  const top = (raw ?? [])[0]
  const share = total > 0 && top ? Math.round((Number(top.total) / total) * 100) : 0

  const rows: SeriesRow[] | undefined = raw?.map((r) => ({
    key: r.id ?? r.name,
    label: r.name,
    value: Number(r.total),
    color: r.color,
    hint: total > 0 ? `${Math.round((Number(r.total) / total) * 100)}%` : undefined,
  }))

  return (
    <SeriesCard
      title="תמהיל לקוחות"
      subtitle={top ? `${top.name} — ${share}% מההכנסות` : undefined}
      rows={rows}
      loading={isLoading}
      error={error}
      onRetry={() => void refetch()}
      form={pickForm(MIX_FORMS, opts)}
      height={height}
      /* six was the hard-coded slice before it was a setting; keeping it as the
         default means the card looks the same until somebody changes it */
      opts={{ top: 6, ...opts }}
      seriesName="הכנסות"
      format={fmtMoney}
      emptyTitle="אין הכנסות בטווח"
      emptyDescription="אין משימות מתומחרות בטווח שנבחר"
      onSelect={
        go &&
        ((r) =>
          isEntityId(r.key)
            ? go({ to: 'events', customer: r.key })
            : toCustomer && go(toCustomer(r.label)))
      }
    />
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
        /* משימה שתאריכה עבר והיא עדיין לא פורסמה לעובד. `status_is_terminal`
           היה המדד עד 0063, שבו ירדו "הושלם" ו"בוטל" ולמשימה לא נשאר סטטוס
           סוגר — ומאז הוא היה מחזיר את כל ההיסטוריה. */
        .or('status_code.is.null,status_code.neq.assigned')
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
