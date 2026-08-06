import type { ReactNode } from 'react'
import { Navigate, Outlet, useLocation } from 'react-router'
import { Truck } from '../../components/ui/icons'
import { Card, EmptyState, Spinner } from '../../components/ui'
import { useAuth } from '../../state/auth'
import type { PermissionAction } from '../../types/domain'

/** Branded boot screen — better than a bare spinner on a cold load. */
function Booting() {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-4 bg-canvas" role="status" aria-label="טוען">
      <span className="flex size-12 animate-shimmer items-center justify-center rounded-2xl bg-primary text-on-primary shadow-lg">
        <Truck size={24} strokeWidth={1.75} />
      </span>
      <Spinner size={20} />
    </div>
  )
}

export function RequireAuth() {
  const { session, booted, me } = useAuth()
  const location = useLocation()

  if (!booted) return <Booting />
  if (!session) return <Navigate to="/login" replace />
  if (!me) return <Booting />
  // contractors live in their own portal
  if (me.profile.user_kind === 'contractor_user' && !location.pathname.startsWith('/portal')) {
    return <Navigate to="/portal" replace />
  }
  return <Outlet />
}

export function RequirePermission({
  resource,
  action = 'view',
  children,
}: {
  resource: string
  action?: PermissionAction
  children: ReactNode
}) {
  const can = useAuth((s) => s.can)
  if (!can(resource, action)) {
    return (
      <Card className="mx-auto max-w-md">
        <EmptyState
          art="alert"
          title="אין הרשאה"
          description="אין לך הרשאה לצפות בעמוד זה. פנה למנהל המערכת אם דרושה לך גישה."
        />
      </Card>
    )
  }
  return <>{children}</>
}
