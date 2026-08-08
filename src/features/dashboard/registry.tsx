import {
  AlertTriangle,
  Banknote,
  Calendar,
  CalendarDays,
  ClipboardList,
  Clock,
  History,
  ICON,
  PartyPopper,
  STROKE,
  Users,
  Zap,
} from '../../components/ui/icons'
import { fmtMoney } from '../../components/ui'
import { PERM } from '../../lib/permissions'
import type { DashboardLayout, WidgetDef } from './dashboardTypes'
import { statKpi } from './widgets/kpi'
import {
  DayTimelineWidget,
  QuickActionsWidget,
  RecentListWidget,
  StatusBreakdownWidget,
  TodayListWidget,
  UpcomingListWidget,
} from './widgets/opsWidgets'
import {
  ContractorSplitWidget,
  NextEventsWidget,
  TasksByCustomerWidget,
  WorkerLoadWidget,
} from './widgets/chartWidgets'

const icon = (I: typeof Clock) => <I size={ICON.md} strokeWidth={STROKE} />

/**
 * The catalogue.
 *
 * One array is the whole contract: the grid draws from it, the customise
 * drawer lists it, the merge decides what is new by looking at it, and the
 * server fan-out will read `sections` off it. Adding a widget is adding an
 * entry — nothing else has to know.
 *
 * **`id` is permanent.** It is the key a user's saved layout stores, so
 * renaming one silently relocates every dashboard in the company. Retire an
 * id rather than reuse it.
 */
export const WIDGETS: WidgetDef[] = [
  /* ── כספים ─────────────────────────────────────────────────────────────── */
  {
    id: 'finance.revenue_total',
    title: 'הכנסות בטווח',
    description: 'סך המחירים של המשימות המתומחרות בטווח, מול התקופה הקודמת',
    group: 'finance',
    icon: icon(Banknote),
    perms: [PERM.PRICING_REVENUE],
    sizes: ['sm'],
    defaultOn: true,
    usesRange: true,
    wantsDelta: true,
    Component: statKpi({
      label: 'הכנסות בטווח',
      icon: Banknote,
      tone: '#1fa189',
      delta: true,
      select: (s) => (s.revenue ? Number(s.revenue.total) : null),
      format: (v) => fmtMoney(v),
    }),
  },

  /* ── תפעול ─────────────────────────────────────────────────────────────── */
  {
    id: 'ops.tasks_count',
    title: 'משימות בטווח',
    description: 'כמה משימות מתוזמנות בטווח התאריכים שנבחר',
    group: 'ops',
    icon: icon(ClipboardList),
    sizes: ['sm'],
    defaultOn: true,
    usesRange: true,
    wantsDelta: true,
    Component: statKpi({
      label: 'משימות בטווח',
      icon: ClipboardList,
      delta: true,
      select: (s) => s.tasks_count,
      to: '/board',
    }),
  },
  {
    id: 'ops.tasks_today',
    title: 'משימות היום',
    description: 'מונה המשימות של היום — אינו מושפע מטווח התאריכים',
    group: 'ops',
    icon: icon(Clock),
    sizes: ['sm'],
    defaultOn: true,
    Component: statKpi({ label: 'משימות היום', icon: Clock, tone: '#8b5cf6', select: (s) => s.tasks_today }),
  },
  {
    id: 'ops.tasks_week',
    title: 'משימות השבוע',
    description: 'מונה המשימות של השבוע הנוכחי',
    group: 'ops',
    icon: icon(Calendar),
    sizes: ['sm'],
    defaultOn: true,
    Component: statKpi({
      label: 'משימות השבוע',
      icon: Calendar,
      tone: '#0ea5e9',
      select: (s) => s.tasks_week,
      to: '/board',
    }),
  },
  {
    id: 'ops.tasks_overdue',
    title: 'משימות באיחור',
    description: 'משימות שתאריכן עבר והסטטוס שלהן אינו סופי',
    group: 'ops',
    icon: icon(AlertTriangle),
    sizes: ['sm'],
    defaultOn: true,
    Component: statKpi({
      label: 'משימות באיחור',
      icon: AlertTriangle,
      tone: '#ef4444',
      invertDelta: true,
      select: (s) => s.tasks_overdue,
      to: '/board',
    }),
  },
  {
    id: 'ops.day_timeline',
    title: 'ציר הזמן של היום',
    description: 'משימות היום על ציר שעות — חפיפות ופערים במבט אחד',
    group: 'ops',
    icon: icon(Clock),
    perms: [PERM.BOARD_VIEW],
    sizes: ['lg', 'xl'],
    defaultOn: true,
    Component: DayTimelineWidget,
  },
  {
    id: 'ops.by_status',
    title: 'התפלגות לפי סטטוס',
    description: 'טבעת ומקרא של המשימות בטווח, לפי סטטוס',
    group: 'ops',
    icon: icon(Zap),
    sizes: ['md', 'lg'],
    defaultOn: true,
    usesRange: true,
    Component: StatusBreakdownWidget,
  },
  {
    id: 'ops.today_list',
    title: 'משימות היום (רשימה)',
    description: 'שמונה המשימות הראשונות של היום, לפי שעה',
    group: 'ops',
    icon: icon(Clock),
    perms: [PERM.BOARD_VIEW],
    sizes: ['md', 'lg'],
    defaultOn: true,
    Component: TodayListWidget,
  },
  {
    id: 'ops.upcoming_list',
    title: 'משימות קרובות',
    description: 'שבעת הימים הבאים',
    group: 'ops',
    icon: icon(CalendarDays),
    perms: [PERM.BOARD_VIEW],
    sizes: ['md', 'lg'],
    defaultOn: true,
    Component: UpcomingListWidget,
  },
  {
    id: 'ops.recent_list',
    title: 'עודכן לאחרונה',
    description: 'שמונה השינויים האחרונים במשימות',
    group: 'ops',
    icon: icon(History),
    perms: [PERM.BOARD_VIEW],
    sizes: ['md', 'lg'],
    defaultOn: true,
    Component: RecentListWidget,
  },
  {
    id: 'cust.tasks_by_customer',
    title: 'משימות לפי לקוח',
    description: 'עמודות בצבע הלקוח, שנים־עשר המובילים',
    group: 'customers',
    icon: icon(ClipboardList),
    perms: [PERM.CUSTOMERS_VIEW],
    sizes: ['md', 'lg'],
    defaultOn: true,
    usesRange: true,
    Component: TasksByCustomerWidget,
  },

  /* ── לקוחות ────────────────────────────────────────────────────────────── */
  {
    id: 'cust.events_count',
    title: 'אירועים בטווח',
    description: 'כמה אירועים בטווח התאריכים שנבחר, מול התקופה הקודמת',
    group: 'customers',
    icon: icon(CalendarDays),
    sizes: ['sm'],
    defaultOn: true,
    usesRange: true,
    wantsDelta: true,
    Component: statKpi({
      label: 'אירועים בטווח',
      icon: CalendarDays,
      delta: true,
      select: (s) => s.events_count,
      to: '/events',
    }),
  },
  {
    id: 'cust.next_events',
    title: 'האירועים הקרובים',
    description: 'חמשת האירועים הבאים — מה שכבר הוזמן, להבדיל ממה שקורה היום',
    group: 'customers',
    icon: icon(PartyPopper),
    sizes: ['md', 'lg', 'xl'],
    defaultOn: true,
    Component: NextEventsWidget,
  },

  /* ── כוח אדם ───────────────────────────────────────────────────────────── */
  {
    id: 'hr.available_workers',
    title: 'עובדים זמינים היום',
    description: 'עובדי צוות פעילים שאין להם שיבוץ היום',
    group: 'people',
    icon: icon(Users),
    perms: [PERM.DASHBOARD_ALL_WORKERS],
    sizes: ['sm'],
    defaultOn: true,
    Component: statKpi({
      label: 'עובדים זמינים היום',
      icon: Users,
      tone: '#22c55e',
      select: (s) => s.available_workers,
      to: '/users',
    }),
  },
  {
    id: 'hr.workload',
    title: 'עומס עובדים',
    description: 'כמה שיבוצים יש לכל עובד בטווח',
    group: 'people',
    icon: icon(Users),
    perms: [PERM.DASHBOARD_ALL_WORKERS],
    sizes: ['md', 'lg'],
    defaultOn: true,
    usesRange: true,
    Component: WorkerLoadWidget,
  },
  {
    id: 'hr.contractor_split',
    title: 'התפלגות קבלנים',
    description: 'כמה משימות הואצלו לכל קבלן בטווח',
    group: 'people',
    icon: icon(Users),
    perms: [PERM.DASHBOARD_CONTRACTORS],
    sizes: ['md', 'lg'],
    defaultOn: true,
    usesRange: true,
    Component: ContractorSplitWidget,
  },

  /* ── אישי ──────────────────────────────────────────────────────────────── */
  {
    id: 'me.quick_actions',
    title: 'פעולות מהירות',
    description: 'אירוע חדש, משימה חדשה, ומעבר ללוחות',
    group: 'me',
    icon: icon(Zap),
    sizes: ['xl'],
    defaultOn: true,
    Component: QuickActionsWidget,
  },
]

export const WIDGETS_BY_ID = new Map(WIDGETS.map((w) => [w.id, w]))
export const WIDGET_IDS = new Set(WIDGETS.map((w) => w.id))

/**
 * The layout a user with nothing saved gets, and the layout the "reset" button
 * returns to.
 *
 * The order below reproduces the pre-widget dashboard exactly — KPI row, quick
 * actions, timeline beside the status donut, upcoming events, the three task
 * lists, the three charts. That is the point of it: turning the page into
 * widgets is not supposed to be a redesign, and anything that moved would be a
 * change nobody asked for.
 *
 * Every `defaultOn` widget must appear here. One that does not would be
 * re-added by `resolveLayout` on every single load — `registry.test.ts` holds
 * that invariant.
 */
export const BUILT_IN_DEFAULT: DashboardLayout = {
  v: 1,
  items: [
    { id: 'cust.events_count', size: 'sm' },
    { id: 'ops.tasks_count', size: 'sm' },
    { id: 'ops.tasks_today', size: 'sm' },
    { id: 'ops.tasks_week', size: 'sm' },
    { id: 'ops.tasks_overdue', size: 'sm' },
    { id: 'hr.available_workers', size: 'sm' },
    { id: 'finance.revenue_total', size: 'sm' },

    { id: 'me.quick_actions', size: 'xl' },

    { id: 'ops.day_timeline', size: 'lg' },
    { id: 'ops.by_status', size: 'md' },

    { id: 'cust.next_events', size: 'xl' },

    { id: 'ops.today_list', size: 'md' },
    { id: 'ops.upcoming_list', size: 'md' },
    { id: 'ops.recent_list', size: 'md' },

    { id: 'cust.tasks_by_customer', size: 'md' },
    { id: 'hr.workload', size: 'md' },
    { id: 'hr.contractor_split', size: 'md' },
  ],
  hidden: [],
  seen: WIDGETS.map((w) => w.id),
}
