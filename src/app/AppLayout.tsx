import { NavLink, Outlet } from 'react-router'
import {
  Calendar,
  ClipboardList,
  LayoutDashboard,
  PartyPopper,
  Users,
  Building2,
  HardHat,
  Settings,
  Moon,
  Sun,
  LogOut,
  Search,
  Truck,
  Menu,
} from 'lucide-react'
import { useState } from 'react'
import { useAuth } from '../state/auth'
import { cx } from '../components/ui'
import { NotificationsBell } from '../features/notifications/NotificationsBell'
import { CommandPalette } from '../features/search/CommandPalette'

const nav = [
  { to: '/', label: 'דשבורד', icon: LayoutDashboard, resource: 'dashboard' },
  { to: '/calendar', label: 'לוח שנה', icon: Calendar, resource: 'events' },
  { to: '/board', label: 'לוח עבודה', icon: ClipboardList, resource: 'tasks' },
  { to: '/events', label: 'אירועים', icon: PartyPopper, resource: 'events' },
  { to: '/customers', label: 'לקוחות', icon: Building2, resource: 'customers' },
  { to: '/users', label: 'עובדים', icon: Users, resource: 'users' },
  { to: '/contractors', label: 'קבלנים', icon: HardHat, resource: 'contractors' },
  { to: '/settings', label: 'הגדרות', icon: Settings, resource: 'settings' },
]

export default function AppLayout() {
  const { me, theme, toggleTheme, signOut, can } = useAuth()
  const [searchOpen, setSearchOpen] = useState(false)
  const [mobileNav, setMobileNav] = useState(false)
  const items = nav.filter((n) => can(n.resource, 'view'))

  return (
    <div className="flex h-full">
      {/* sidebar */}
      <aside
        className={cx(
          'fixed inset-y-0 start-0 z-40 w-56 shrink-0 border-e border-[var(--border)] bg-[var(--panel)] transition-transform lg:static lg:translate-x-0',
          mobileNav ? 'translate-x-0' : 'translate-x-full lg:translate-x-0',
        )}
      >
        <div className="flex items-center gap-2 px-4 py-4">
          <div className="flex size-8 items-center justify-center rounded-lg bg-brand-600 text-white">
            <Truck size={16} />
          </div>
          <span className="font-bold">ViperLogistics</span>
        </div>
        <nav className="space-y-0.5 px-2">
          {items.map(({ to, label, icon: Icon }) => (
            <NavLink
              key={to}
              to={to}
              end={to === '/'}
              onClick={() => setMobileNav(false)}
              className={({ isActive }) =>
                cx(
                  'flex items-center gap-2.5 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
                  isActive
                    ? 'bg-brand-500/10 text-brand-600 dark:text-brand-300'
                    : 'text-[var(--muted)] hover:bg-[var(--bg)] hover:text-[var(--text)]',
                )
              }
            >
              <Icon size={16} />
              {label}
            </NavLink>
          ))}
        </nav>
      </aside>
      {mobileNav && <div className="fixed inset-0 z-30 bg-black/30 lg:hidden" onClick={() => setMobileNav(false)} />}

      {/* main */}
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center gap-2 border-b border-[var(--border)] bg-[var(--panel)] px-4 py-2">
          <button className="lg:hidden" onClick={() => setMobileNav(true)}>
            <Menu size={18} />
          </button>
          <button
            onClick={() => setSearchOpen(true)}
            className="flex w-64 max-w-full items-center gap-2 rounded-lg border border-[var(--border)] bg-[var(--bg)] px-3 py-1.5 text-sm text-[var(--muted)] hover:border-brand-400"
          >
            <Search size={14} />
            חיפוש...
            <kbd className="ms-auto rounded border border-[var(--border)] px-1 text-[10px]">Ctrl+K</kbd>
          </button>
          <div className="ms-auto flex items-center gap-1">
            <NotificationsBell />
            <button
              onClick={toggleTheme}
              className="rounded-lg p-2 text-[var(--muted)] hover:bg-[var(--bg)]"
              title="מצב תצוגה"
            >
              {theme === 'light' ? <Moon size={16} /> : <Sun size={16} />}
            </button>
            <div className="mx-2 hidden text-sm sm:block">
              <span className="font-medium">{me?.profile.full_name}</span>
            </div>
            <button onClick={() => void signOut()} className="rounded-lg p-2 text-[var(--muted)] hover:bg-[var(--bg)]" title="התנתקות">
              <LogOut size={16} />
            </button>
          </div>
        </header>
        <main className="min-h-0 flex-1 overflow-y-auto p-4">
          <Outlet />
        </main>
      </div>
      <CommandPalette open={searchOpen} onClose={() => setSearchOpen(false)} />
    </div>
  )
}
