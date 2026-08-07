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
  // Contractors and clients each live in their own portal. Routing them out of
  // the staff shell is also what keeps a staff screen — including one added
  // later, before anyone remembers to gate it — from being reachable by URL.
  const path = location.pathname
  // /my/* הוא המסך של האדם עצמו — שעון ומשמרות — ולכן הוא פתוח לכל סוג
  // משתמש שיש לו את המפתח. עובד קבלן שקיבל התחברות רק כדי להחתים שעון אינו
  // מנהל הקבלן, ואין לו מה לעשות בפורטל.
  const isPersonal = path.startsWith('/my/')
  if (me.profile.user_kind === 'contractor_user' && !path.startsWith('/portal') && !isPersonal) {
    const toPortal = me.profile.is_admin || me.capabilities['portal.view']
    return <Navigate to={toPortal ? '/portal' : '/my/schedule'} replace />
  }
  if (me.profile.user_kind === 'customer_user' && !path.startsWith('/client')) {
    return <Navigate to="/client" replace />
  }
  // staff have no business in the client portal; admins may look, to preview it
  if (me.profile.user_kind === 'staff' && !me.profile.is_admin && path.startsWith('/client')) {
    return <Navigate to="/" replace />
  }
  return <Outlet />
}

/**
 * Gates a whole screen. Takes either a registry key (`perm="tasks.view"`) or
 * the older resource/action pair, which resolves to the same key.
 */
export function RequirePermission({
  resource,
  action = 'view',
  perm,
  children,
}: {
  resource?: string
  action?: PermissionAction
  perm?: string
  children: ReactNode
}) {
  const has = useAuth((s) => s.has)
  const key = perm ?? `${resource}.${action}`
  if (!has(key)) {
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

/**
 * Inline gate for a control rather than a screen. `fallback` is for the cases
 * where hiding a button entirely would leave a confusing hole — pass a disabled
 * version instead.
 */
export function Can({
  perm,
  any,
  children,
  fallback = null,
}: {
  perm?: string
  any?: string[]
  children: ReactNode
  fallback?: ReactNode
}) {
  const has = useAuth((s) => s.has)
  const ok = any ? any.some((k) => has(k)) : perm ? has(perm) : false
  return <>{ok ? children : fallback}</>
}

/** Hook form, for conditions that feed into other logic rather than JSX. */
export function useCan(key: string): boolean {
  return useAuth((s) => s.has(key))
}
