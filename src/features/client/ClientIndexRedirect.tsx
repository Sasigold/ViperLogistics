import { Navigate, useLocation } from 'react-router'
import { Card, EmptyState, Skeleton } from '../../components/ui'
import { useAuth } from '../../state/auth'
import { CLIENT_NAV } from './clientNav'

/**
 * Sends the client to the first section they can actually open. Landing on a
 * fixed default would show a permission-denied card to anyone without that one
 * permission — which is the normal case, not the edge case.
 */
export default function ClientIndexRedirect() {
  const has = useAuth((s) => s.has)
  const me = useAuth((s) => s.me)
  const { pathname } = useLocation()

  if (!me) return <Skeleton className="h-32 w-full" />
  const first = CLIENT_NAV.find((n) => has(n.perm))
  if (!first)
    return (
      <Card>
        <EmptyState
          art="alert"
          title="אין לך עדיין גישה"
          description="לא הוגדרו עבורך הרשאות צפייה. פנה למנהל המערכת כדי לקבל גישה."
        />
      </Card>
    )
  if (first.to === pathname) return null
  return <Navigate to={first.to} replace />
}
