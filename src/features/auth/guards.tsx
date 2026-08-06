import type { ReactNode } from 'react'
import { Navigate, Outlet } from 'react-router'
import { useAuth } from '../../state/auth'
import { Spinner } from '../../components/ui'
import type { PermissionAction } from '../../types/domain'

export function RequireAuth() {
  const { session, booted, me } = useAuth()
  if (!booted) return <Spinner full />
  if (!session) return <Navigate to="/login" replace />
  if (!me) return <Spinner full />
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
      <div className="flex h-60 flex-col items-center justify-center gap-2 text-[var(--muted)]">
        <p className="text-lg font-semibold">אין הרשאה</p>
        <p className="text-sm">אין לך הרשאה לצפות בעמוד זה</p>
      </div>
    )
  }
  return <>{children}</>
}
