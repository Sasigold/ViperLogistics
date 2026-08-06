import { Suspense, lazy } from 'react'
import type { ReactNode } from 'react'
import { createBrowserRouter } from 'react-router'
import AppLayout from './AppLayout'
import LoginPage from '../features/auth/LoginPage'
import { RequireAuth } from '../features/auth/guards'
import { Skeleton } from '../components/ui'

/**
 * Every screen is code-split. Before this, FullCalendar, Recharts and ExcelJS
 * all shipped in the first chunk even when landing on the dashboard — the
 * heaviest cost on the page was code no one had asked for yet.
 *
 * The shell (layout, auth guard, login) stays eager: it is needed on the very
 * first paint, so splitting it would only add a round trip.
 */
const DashboardPage = lazy(() => import('../features/dashboard/DashboardPage'))
const CalendarPage = lazy(() => import('../features/calendar/CalendarPage'))
const WorkBoardPage = lazy(() => import('../features/workboard/WorkBoardPage'))
const EventsPage = lazy(() => import('../features/events/EventsPage'))
const EventDetailPage = lazy(() => import('../features/events/EventDetailPage'))
const CustomersPage = lazy(() => import('../features/customers/CustomersPage'))
const CustomerDetailPage = lazy(() => import('../features/customers/CustomerDetailPage'))
const UsersPage = lazy(() => import('../features/users/UsersPage'))
const ContractorsPage = lazy(() => import('../features/contractors/ContractorsPage'))
const ContractorDetailPage = lazy(() => import('../features/contractors/ContractorDetailPage'))
const PortalPage = lazy(() => import('../features/portal/PortalPage'))
const ClientLayout = lazy(() => import('../features/client/ClientLayout'))
const ClientIndexRedirect = lazy(() => import('../features/client/ClientIndexRedirect'))
const ClientDashboardPage = lazy(() => import('../features/client/ClientDashboardPage'))
const ClientEventsPage = lazy(() => import('../features/client/ClientEventsPage'))
const ClientEventDetailPage = lazy(() => import('../features/client/ClientEventDetailPage'))
const ClientCalendarPage = lazy(() => import('../features/client/ClientCalendarPage'))
const ClientTasksPage = lazy(() => import('../features/client/ClientTasksPage'))
const ClientUsersPage = lazy(() => import('../features/client/ClientUsersPage'))
const SettingsPage = lazy(() => import('../features/settings/SettingsPage'))

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

const page = (node: ReactNode) => <Suspense fallback={<PageFallback />}>{node}</Suspense>

export const router = createBrowserRouter([
  { path: '/login', element: <LoginPage /> },
  {
    element: <RequireAuth />,
    children: [
      { path: '/portal', element: page(<PortalPage />) },
      // the client portal carries its own chrome, so it sits outside AppLayout
      {
        path: '/client',
        element: page(<ClientLayout />),
        children: [
          { index: true, element: page(<ClientIndexRedirect />) },
          { path: 'dashboard', element: page(<ClientDashboardPage />) },
          { path: 'events', element: page(<ClientEventsPage />) },
          { path: 'events/:id', element: page(<ClientEventDetailPage />) },
          { path: 'calendar', element: page(<ClientCalendarPage />) },
          { path: 'tasks', element: page(<ClientTasksPage />) },
          { path: 'users', element: page(<ClientUsersPage />) },
        ],
      },
      {
        element: <AppLayout />,
        children: [
          { path: '/', element: page(<DashboardPage />) },
          { path: '/calendar', element: page(<CalendarPage />) },
          { path: '/board', element: page(<WorkBoardPage />) },
          { path: '/events', element: page(<EventsPage />) },
          { path: '/events/:id', element: page(<EventDetailPage />) },
          { path: '/customers', element: page(<CustomersPage />) },
          { path: '/customers/:id', element: page(<CustomerDetailPage />) },
          { path: '/users', element: page(<UsersPage />) },
          { path: '/contractors', element: page(<ContractorsPage />) },
          { path: '/contractors/:id', element: page(<ContractorDetailPage />) },
          { path: '/settings', element: page(<SettingsPage />) },
        ],
      },
    ],
  },
])
