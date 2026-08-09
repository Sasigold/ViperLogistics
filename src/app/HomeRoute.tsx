import { Suspense } from 'react'
import { Navigate } from 'react-router'
import { Card, EmptyState, Skeleton } from '../components/ui'
import { useAuth } from '../state/auth'
import { PERM } from '../lib/permissions'
import { lazyPage } from '../lib/lazyPage'
import { NAV_SECTIONS, navItemVisible } from './nav'

const DashboardPage = lazyPage(() => import('../features/dashboard/DashboardPage'))

/**
 * What `/` means depends on what you can open.
 *
 * Landing everyone on the dashboard shows a permission-denied card to anyone
 * without `dashboard.view` — which is the normal case, not the edge case: the
 * driver and worker roles do not have it, and neither does a client who was
 * given events only. So the route sends you to the first destination in the
 * sidebar you can actually reach, and only says "no access" when there is
 * genuinely nowhere to go.
 *
 * This is the client portal's index redirect, generalised. It was right there
 * and wrong everywhere else.
 */
export default function HomeRoute() {
  const has = useAuth((s) => s.has)
  const me = useAuth((s) => s.me)

  if (!me) return <Skeleton className="h-32 w-full" />
  if (has(PERM.DASHBOARD_VIEW)) {
    return (
      <Suspense fallback={<Skeleton className="h-96 w-full" />}>
        <DashboardPage />
      </Suspense>
    )
  }

  // `to !== '/'` keeps the dashboard entry from redirecting this route to itself
  const first = NAV_SECTIONS.flatMap((s) => s.items).find((n) => n.to !== '/' && navItemVisible(n, has))
  if (first) return <Navigate to={first.to} replace />

  return (
    <Card>
      <EmptyState
        art="alert"
        title="אין לך עדיין גישה"
        description="לא הוגדרו עבורך הרשאות צפייה. פנה למנהל המערכת כדי לקבל גישה."
      />
    </Card>
  )
}
