import { Suspense } from 'react'
import type { ReactNode } from 'react'
import { Navigate, createBrowserRouter, useParams } from 'react-router'
import AppLayout from './AppLayout'
import HomeRoute from './HomeRoute'
import LoginPage from '../features/auth/LoginPage'
import ResetPasswordPage from '../features/auth/ResetPasswordPage'
import { RequireAuth } from '../features/auth/guards'
import { PERM } from '../lib/permissions'
import { lazyPage } from '../lib/lazyPage'
import { ErrorBoundary, Skeleton } from '../components/ui'

/**
 * Every screen is code-split. Before this, FullCalendar, Recharts and ExcelJS
 * all shipped in the first chunk even when landing on the dashboard — the
 * heaviest cost on the page was code no one had asked for yet.
 *
 * The shell (layout, auth guard, login) stays eager: it is needed on the very
 * first paint, so splitting it would only add a round trip.
 */
const CalendarPage = lazyPage(() => import('../features/calendar/CalendarPage'))
const WorkBoardPage = lazyPage(() => import('../features/workboard/WorkBoardPage'))
const EventsPage = lazyPage(() => import('../features/events/EventsPage'))
const EventDetailPage = lazyPage(() => import('../features/events/EventDetailPage'))
const CustomersPage = lazyPage(() => import('../features/customers/CustomersPage'))
const CustomerDetailPage = lazyPage(() => import('../features/customers/CustomerDetailPage'))
const UsersPage = lazyPage(() => import('../features/users/UsersPage'))
const ContractorsPage = lazyPage(() => import('../features/contractors/ContractorsPage'))
const ContractorDetailPage = lazyPage(() => import('../features/contractors/ContractorDetailPage'))
const PortalPage = lazyPage(() => import('../features/portal/PortalPage'))
const SettingsPage = lazyPage(() => import('../features/settings/SettingsPage'))
const TimeClockPage = lazyPage(() => import('../features/attendance/TimeClockPage'))
const MySchedulePage = lazyPage(() => import('../features/attendance/MySchedulePage'))
const AttendanceReportPage = lazyPage(() => import('../features/attendance/AttendanceReportPage'))
const ShiftBoardPage = lazyPage(() => import('../features/attendance/ShiftBoardPage'))
const NotificationPreferencesPage = lazyPage(() => import('../features/notifications/NotificationPreferencesPage'))

/** Shaped like a real screen so the chunk swap doesn't flash an empty page. */
function PageFallback() {
  return (
    <div className="space-y-4" role="status" aria-label="טוען את המסך">
      <div className="flex items-center justify-between gap-3">
        <Skeleton className="h-7 w-48" />
        <Skeleton className="h-9 w-32" />
      </div>
      <Skeleton className="h-14 w-full" />
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <Skeleton key={i} className="h-24 w-full" />
        ))}
      </div>
      <Skeleton className="h-72 w-full" />
    </div>
  )
}

/**
 * גבול שגיאה פר-מסך, בתוך ה-shell. הגבול החיצוני ב-main.tsx תופס גם את מה
 * שקורס מחוץ למסך, אבל הוא מחליף את כל העמוד; כאן הניווט והתפריט נשארים,
 * ולכן אפשר פשוט לעבור למסך אחר במקום לטעון מחדש.
 */
const page = (node: ReactNode) => (
  <ErrorBoundary>
    <Suspense fallback={<PageFallback />}>{node}</Suspense>
  </ErrorBoundary>
)

/** Keeps a bookmarked client event link pointing at the same event. */
function ClientEventRedirect() {
  const { id } = useParams<{ id: string }>()
  return <Navigate to={id ? `/events/${id}` : '/events'} replace />
}

export const router = createBrowserRouter([
  { path: '/login', element: <LoginPage /> },
  /* היעד של קישור האיפוס מהמייל. מחוץ ל-RequireAuth בכוונה: הקישור נושא
     סשן recovery, והדף הוא שמכריע אם הוא תקף. eager כמו LoginPage —
     מי שמגיע לכאן עוד אין לו כלום בקאש. */
  { path: '/reset-password', handle: { open: true }, element: <ResetPasswordPage /> },
  {
    element: <RequireAuth />,
    children: [
      { path: '/portal', element: page(<PortalPage />) },

      /* Clients used to live under /client with their own shell. They now use
         the same screens as everyone else, narrowed by their permissions, so
         these only keep old bookmarks and notification links working.
         Removable once the logs are quiet — no earlier than 2027. */
      { path: '/client', element: <Navigate to="/" replace /> },
      { path: '/client/dashboard', element: <Navigate to="/" replace /> },
      { path: '/client/events', element: <Navigate to="/events" replace /> },
      { path: '/client/events/:id', element: <ClientEventRedirect /> },
      { path: '/client/calendar', element: <Navigate to="/calendar" replace /> },
      { path: '/client/tasks', element: <Navigate to="/board" replace /> },
      { path: '/client/users', element: <Navigate to="/users" replace /> },

      {
        element: <AppLayout />,
        children: [
          /* `handle.perm` is what RouteGate reads. Declaring it here rather than
             only inside the screen means a route cannot exist without an answer
             to "who may open this" — the guarantee the /client redirect used to
             provide by accident, and which two screens had already lost.
             `open` marks a route that decides for itself. */
          { path: '/', handle: { open: true }, element: page(<HomeRoute />) },
          { path: '/calendar', handle: { perm: PERM.CALENDAR_VIEW }, element: page(<CalendarPage />) },
          { path: '/board', handle: { perm: PERM.BOARD_VIEW }, element: page(<WorkBoardPage />) },
          { path: '/events', handle: { perm: PERM.EVENTS_VIEW }, element: page(<EventsPage />) },
          { path: '/events/:id', handle: { perm: PERM.EVENTS_VIEW }, element: page(<EventDetailPage />) },
          { path: '/customers', handle: { perm: PERM.CUSTOMERS_VIEW }, element: page(<CustomersPage />) },
          { path: '/customers/:id', handle: { perm: PERM.CUSTOMERS_VIEW }, element: page(<CustomerDetailPage />) },
          { path: '/users', handle: { perm: PERM.USERS_VIEW }, element: page(<UsersPage />) },
          { path: '/contractors', handle: { perm: PERM.CONTRACTORS_VIEW }, element: page(<ContractorsPage />) },
          {
            path: '/contractors/:id',
            handle: { perm: PERM.CONTRACTORS_VIEW },
            element: page(<ContractorDetailPage />),
          },
          /* לוח השיבוץ של כל הצוות. view_all ולא view_own: בשונה מהדוח, כאן
             אין גרסה מצומצמת שמראה לך את עצמך — לזה יש את /my/schedule. */
          {
            path: '/shifts',
            handle: { perm: PERM.ATTENDANCE_VIEW_ALL },
            element: page(<ShiftBoardPage />),
          },
          /* view_own, not view_all: the report widens from "my hours" to "the
             roster's" on the key, so it has always served both. The sidebar
             entry stays on view_all — advertising it and opening it are
             different questions. */
          {
            path: '/attendance',
            handle: { perm: PERM.ATTENDANCE_VIEW_OWN },
            element: page(<AttendanceReportPage />),
          },
          // /my/* הוא המסך של האדם עצמו — שעון ומשמרות — ולכן הוא פתוח לכל סוג
          // משתמש שיש לו את המפתח, כולל עובד קבלן ואיש קשר אצל לקוח.
          {
            path: '/my/schedule',
            handle: { perm: PERM.ATTENDANCE_VIEW_SCHEDULE },
            element: page(<MySchedulePage />),
          },
          { path: '/my/attendance', handle: { perm: PERM.ATTENDANCE_VIEW_OWN }, element: page(<TimeClockPage />) },
          {
            path: '/my/notifications',
            handle: { perm: PERM.NOTIFICATIONS_PREFERENCES },
            element: page(<NotificationPreferencesPage />),
          },
          { path: '/settings', handle: { perm: PERM.SETTINGS_VIEW }, element: page(<SettingsPage />) },
        ],
      },
    ],
  },
])
