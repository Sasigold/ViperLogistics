import type { ReactNode } from 'react'
import { Navigate, Outlet, useMatches } from 'react-router'
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

  if (!booted) return <Booting />
  if (!session) return <Navigate to="/login" replace />
  if (!me) {
    return meError ? <BootFailed error={meError} onRetry={() => void refreshMe()} /> : <Booting />
  }
  // Nobody is routed by `user_kind` any more. Contractors were the last ones
  // who were: a redirect kept them inside /portal and out of everything else,
  // which is also why permissions they already held — board.view and
  // calendar.view, granted to the contractor roles in 0066 §7ד — were
  // unreachable code. They now use the same screens as staff and clients,
  // and RouteGate below decides which of those they may open.
  //
  // What made the redirect necessary was that the four portal keys were
  // `default_allowed`, so every staff user resolved them true and they could
  // not gate a route. 0071 §1 turns that off, which is what lets the question
  // "who may open this" go back to the route table where the rest of it lives.
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
  /**
   * For a screen that genuinely serves two audiences through two keys — the
   * shift board is the roster to a coordinator holding `attendance.view_all`
   * and to a contractor holding `portal.attendance`, and the server already
   * answers both (`shift_roster`, 0034). Holding any one of them opens it.
   */
  anyPerm?: string[]
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
    .find((h) => h?.perm || h?.anyPerm?.length || h?.open)

  if (!handle) {
    if (import.meta.env.DEV) {
      console.error('[RouteGate] this route declares no permission key:', matches.at(-1)?.pathname)
    }
    return <NoPermissionCard />
  }
  if (handle.open) return <>{children}</>
  const ok = handle.anyPerm ? handle.anyPerm.some(has) : has(handle.perm!)
  return ok ? <>{children}</> : <NoPermissionCard />
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
  any,
  children,
}: {
  resource?: string
  action?: PermissionAction
  perm?: string
  /** Any one of these opens the screen — the `anyPerm` of a route, in-component. */
  any?: string[]
  children: ReactNode
}) {
  const has = useAuth((s) => s.has)
  const ok = any ? any.some(has) : has(perm ?? `${resource}.${action}`)
  if (!ok) return <NoPermissionCard />
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
