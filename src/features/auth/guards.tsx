import type { ReactNode } from 'react'
import { Navigate, Outlet, useLocation, useMatches } from 'react-router'
import { Truck } from '../../components/ui/icons'
import { Button, Card, EmptyState, Spinner } from '../../components/ui'
import { useAuth } from '../../state/auth'
import { errorMessage } from '../../lib/errors'
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

/**
 * מה שנראה כשטעינת ההרשאות נכשלה. בלי זה המסך היה ספינר בלי סוף: `me` נשאר
 * null, וה-guard מצייר את מסך העלייה כל עוד אין לו.
 */
function BootFailed({ error, onRetry }: { error: unknown; onRetry: () => void }) {
  return (
    <div className="flex h-full items-center justify-center bg-canvas p-4">
      <Card className="w-full max-w-md">
        <EmptyState
          art="alert"
          title="לא הצלחנו לטעון את ההרשאות שלך"
          description={errorMessage(error)}
          action={
            <>
              <Button variant="primary" size="sm" onClick={onRetry}>
                נסה שוב
              </Button>
              <Button variant="ghost" size="sm" onClick={() => void useAuth.getState().signOut()}>
                התנתקות
              </Button>
            </>
          }
        />
      </Card>
    </div>
  )
}

export function RequireAuth() {
  const { session, booted, me, meError, refreshMe } = useAuth()
  const location = useLocation()

  if (!booted) return <Booting />
  if (!session) return <Navigate to="/login" replace />
  if (!me) {
    return meError ? <BootFailed error={meError} onRetry={() => void refreshMe()} /> : <Booting />
  }
  // The contractor portal is a genuinely different shell — a financial
  // dashboard over delegated work — so a contractor still gets routed to it.
  // Clients no longer are: they use the same screens as everyone else, and
  // RouteGate below decides which of those they may open.
  const path = location.pathname
  // /my/* הוא המסך של האדם עצמו — שעון ומשמרות — ולכן הוא פתוח לכל סוג
  // משתמש שיש לו את המפתח. עובד קבלן שקיבל התחברות רק כדי להחתים שעון אינו
  // מנהל הקבלן, ואין לו מה לעשות בפורטל.
  const isPersonal = path.startsWith('/my/')
  if (me.profile.user_kind === 'contractor_user' && !path.startsWith('/portal') && !isPersonal) {
    const toPortal = me.profile.is_admin || me.capabilities['portal.view']
    return <Navigate to={toPortal ? '/portal' : '/my/schedule'} replace />
  }
  // and the other way round. `portal.view` cannot carry this on its own — it is
  // `default_allowed`, so everyone resolves true for it — and /portal sits
  // outside AppLayout, so RouteGate never sees it. Admins may look, to preview.
  if (me.profile.user_kind !== 'contractor_user' && !me.profile.is_admin && path.startsWith('/portal')) {
    return <Navigate to="/" replace />
  }
  return <Outlet />
}

function NoPermissionCard() {
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

/**
 * What a route declares about itself. `perm` is the registry key needed to open
 * it; `open` marks the handful that gate themselves (the landing route, which
 * has to *choose* a screen rather than refuse one).
 */
export interface RouteHandle {
  perm?: string
  open?: true
}

/**
 * The screen-level gate, resolved from the route table rather than from who is
 * asking. It replaces the `user_kind` prefix redirect that used to keep clients
 * out of the staff tree — and it is strictly stronger, because that only kept
 * one kind of user out of one subtree, while this refuses any user any route
 * whose key they lack.
 *
 * A route that declares nothing is refused rather than served. That is the
 * whole point: the old redirect was also the reason a new screen was unreachable
 * before someone remembered to gate it, and two screens had already slipped
 * through with no gate at all. Denying by default puts that guarantee back
 * somewhere it cannot be forgotten — you cannot add a route without answering
 * the question.
 */
export function RouteGate({ children }: { children: ReactNode }) {
  const has = useAuth((s) => s.has)
  const matches = useMatches()

  const handle = [...matches]
    .reverse()
    .map((m) => m.handle as RouteHandle | undefined)
    .find((h) => h?.perm || h?.open)

  if (!handle) {
    if (import.meta.env.DEV) {
      console.error('[RouteGate] this route declares no permission key:', matches.at(-1)?.pathname)
    }
    return <NoPermissionCard />
  }
  if (handle.open) return <>{children}</>
  return has(handle.perm!) ? <>{children}</> : <NoPermissionCard />
}

/**
 * Gates a whole screen from inside it. Takes either a registry key
 * (`perm="tasks.view"`) or the older resource/action pair, which resolves to
 * the same key. The route gate above decides first; this stays as the layer
 * that travels with the component.
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
  if (!has(key)) return <NoPermissionCard />
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
