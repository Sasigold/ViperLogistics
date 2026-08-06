import { createBrowserRouter } from 'react-router'
import AppLayout from './AppLayout'
import LoginPage from '../features/auth/LoginPage'
import { RequireAuth } from '../features/auth/guards'
import DashboardPage from '../features/dashboard/DashboardPage'
import CalendarPage from '../features/calendar/CalendarPage'
import WorkBoardPage from '../features/workboard/WorkBoardPage'
import EventsPage from '../features/events/EventsPage'
import EventDetailPage from '../features/events/EventDetailPage'
import CustomersPage from '../features/customers/CustomersPage'
import CustomerDetailPage from '../features/customers/CustomerDetailPage'
import UsersPage from '../features/users/UsersPage'
import ContractorsPage from '../features/contractors/ContractorsPage'
import ContractorDetailPage from '../features/contractors/ContractorDetailPage'
import PortalPage from '../features/portal/PortalPage'
import SettingsPage from '../features/settings/SettingsPage'

export const router = createBrowserRouter([
  { path: '/login', element: <LoginPage /> },
  {
    element: <RequireAuth />,
    children: [
      { path: '/portal', element: <PortalPage /> },
      {
        element: <AppLayout />,
        children: [
          { path: '/', element: <DashboardPage /> },
          { path: '/calendar', element: <CalendarPage /> },
          { path: '/board', element: <WorkBoardPage /> },
          { path: '/events', element: <EventsPage /> },
          { path: '/events/:id', element: <EventDetailPage /> },
          { path: '/customers', element: <CustomersPage /> },
          { path: '/customers/:id', element: <CustomerDetailPage /> },
          { path: '/users', element: <UsersPage /> },
          { path: '/contractors', element: <ContractorsPage /> },
          { path: '/contractors/:id', element: <ContractorDetailPage /> },
          { path: '/settings', element: <SettingsPage /> },
        ],
      },
    ],
  },
])
