import { NavLink, Outlet } from 'react-router'
import { ICON, LogOut, Moon, STROKE, Sun } from '../../components/ui/icons'
import { Avatar, IconButton, Skeleton, cx } from '../../components/ui'
import { useAuth } from '../../state/auth'
import { NotificationsBell } from '../notifications/NotificationsBell'
import { CLIENT_NAV } from './clientNav'

/**
 * The client portal sits outside AppLayout, like the contractor portal: the
 * staff shell is built around a work board, contractor delegation and pricing,
 * none of which a client should see the shape of, let alone the contents.
 */
export default function ClientLayout() {
  const { me, theme, toggleTheme, signOut, has } = useAuth()

  if (!me)
    return (
      <div className="mx-auto max-w-5xl space-y-4 p-4">
        <Skeleton className="h-14 w-full" />
        <Skeleton className="h-32 w-full" />
      </div>
    )

  const items = CLIENT_NAV.filter((n) => has(n.perm))

  return (
    <div className="min-h-full bg-canvas">
      <header className="sticky top-0 z-30 border-b border-line bg-surface/85 backdrop-blur-md">
        <div className="mx-auto flex h-14 max-w-5xl items-center gap-2.5 px-4">
          <img src="/favicon.svg" className="size-8 shrink-0" alt="ViperLogistics" />
          <div className="min-w-0">
            <h1 className="truncate type-title leading-tight">{me.customer?.name ?? 'פורטל לקוח'}</h1>
            <p className="truncate type-caption text-ink-tertiary">{me.profile.full_name}</p>
          </div>
          <div className="ms-auto flex items-center gap-0.5">
            <NotificationsBell />
            <IconButton
              label={theme === 'light' ? 'מעבר למצב כהה' : 'מעבר למצב בהיר'}
              size="sm"
              onClick={toggleTheme}
            >
              {theme === 'light' ? (
                <Moon size={ICON.md} strokeWidth={STROKE} />
              ) : (
                <Sun size={ICON.md} strokeWidth={STROKE} />
              )}
            </IconButton>
            <IconButton label="התנתקות" size="sm" onClick={() => void signOut()}>
              <LogOut size={ICON.md} strokeWidth={STROKE} />
            </IconButton>
            <Avatar name={me.profile.full_name} size="md" className="ms-1" />
          </div>
        </div>

        {items.length > 1 && (
          <nav className="mx-auto max-w-5xl overflow-x-auto px-4" aria-label="ניווט ראשי">
            <ul className="flex gap-1">
              {items.map((n) => (
                <li key={n.to}>
                  <NavLink
                    to={n.to}
                    className={({ isActive }) =>
                      cx(
                        'flex items-center gap-1.5 whitespace-nowrap border-b-2 px-3 py-2.5 type-button transition-colors',
                        isActive
                          ? 'border-primary text-primary-text'
                          : 'border-transparent text-ink-secondary hover:text-ink',
                      )
                    }
                  >
                    <n.icon size={ICON.md} strokeWidth={STROKE} />
                    {n.label}
                  </NavLink>
                </li>
              ))}
            </ul>
          </nav>
        )}
      </header>

      <div className="mx-auto max-w-5xl space-y-4 p-4">
        <Outlet />
      </div>
    </div>
  )
}
