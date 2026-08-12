import { useEffect, useState } from 'react'
import { Link, NavLink, Outlet, useLocation, useNavigate } from 'react-router'
import {
  ArrowRight,
  ChevronLeft,
  ICON,
  LogOut,
  Menu,
  Moon,
  PanelLeftClose,
  PanelLeftOpen,
  STROKE,
  Search,
  Sun,
  User,
  WifiOff,
  X,
} from '../components/ui/icons'
import { Avatar, Divider, IconButton, Kbd, MenuItem, MenuSeparator, Popover, Tooltip, cx } from '../components/ui'
import { useAuth } from '../state/auth'
import { RouteGate } from '../features/auth/guards'
import { NotificationsBell } from '../features/notifications/NotificationsBell'
import { usePushNavigation, usePushSync } from '../features/notifications/pushQueries'
import { CommandPalette } from '../features/search/CommandPalette'
import { ROUTE_LABELS, bottomNavItems, visibleNavSections } from './nav'
import type { NavItem, NavSection } from './nav'
import { PageTitleProvider, useCurrentPageTitle } from './breadcrumbs'
import { useOnline } from '../lib/useOnline'

const COLLAPSE_KEY = 'vl-nav-collapsed'

const KIND_LABELS: Record<string, string> = {
  staff: 'צוות',
  customer_user: 'משתמש לקוח',
  contractor_user: 'קבלן',
}

export default function AppLayout() {
  const { me, theme, toggleTheme, signOut, has } = useAuth()
  const [searchOpen, setSearchOpen] = useState(false)
  const [mobileNav, setMobileNav] = useState(false)
  const [collapsed, setCollapsed] = useState(() => localStorage.getItem(COLLAPSE_KEY) === '1')
  const location = useLocation()
  const navigate = useNavigate()

  const online = useOnline()

  // מיישר את מנוי הדחיפה של הדפדפן מול המסד בכל עלייה. ראו את ההסבר
  // ב-pushQueries: זה מה שממלא את מקומו של pushsubscriptionchange, שאין
  // ל-Service Worker דרך לטפל בו בלי session.
  usePushSync()
  usePushNavigation(navigate)

  useEffect(() => localStorage.setItem(COLLAPSE_KEY, collapsed ? '1' : '0'), [collapsed])
  useEffect(() => setMobileNav(false), [location.pathname])

  // Ctrl/Cmd+K anywhere opens the palette
  useEffect(() => {
    const h = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault()
        setSearchOpen(true)
      }
    }
    window.addEventListener('keydown', h)
    return () => window.removeEventListener('keydown', h)
  }, [])

  const sections = visibleNavSections(has)

  return (
    <PageTitleProvider>
      <div className="flex h-full bg-canvas">
        <a
          href="#main"
          className="sr-only focus:not-sr-only focus:fixed focus:top-3 focus:start-3 focus:z-[90] focus:rounded-md focus:bg-primary focus:px-3 focus:py-2 focus:type-button focus:text-on-primary"
        >
          דילוג לתוכן הראשי
        </a>

        {/* ── sidebar ─────────────────────────────────────────────────────── */}
        <aside
          className={cx(
            'fixed inset-y-0 start-0 z-50 flex shrink-0 flex-col border-e border-line bg-surface',
            'transition-[width,transform] duration-200 ease-[cubic-bezier(.4,0,.2,1)]',
            'lg:static lg:translate-x-0',
            // wider as a mobile drawer, where it is the only thing on screen
            collapsed ? 'w-72 lg:w-[4.25rem]' : 'w-72 lg:w-60',
            mobileNav ? 'translate-x-0 shadow-overlay' : 'max-lg:ltr:-translate-x-full max-lg:rtl:translate-x-full',
          )}
        >
          <div className={cx('flex h-14 shrink-0 items-center gap-2.5 px-3', collapsed && 'lg:justify-center')}>
            <Link
              to="/"
              className="flex min-w-0 items-center gap-2.5 rounded-lg focus-visible:outline-none focus-visible:focus-ring"
            >
              <span className={cx('truncate type-title', collapsed && 'lg:hidden')}>ViperLogistics</span>
              <img src="/icons/icon-192.png" alt="ViperLogistics" className="size-8 shrink-0 rounded-md" />
            </Link>
            <IconButton
              label="סגירת התפריט"
              size="sm"
              bare
              className="ms-auto lg:hidden"
              onClick={() => setMobileNav(false)}
            >
              <X size={ICON.md} />
            </IconButton>
          </div>

          <nav className="min-h-0 flex-1 space-y-4 overflow-y-auto px-2 pb-3" aria-label="ניווט ראשי">
            {sections.map((section) => (
              <div key={section.title}>
                <p className={cx('px-3 pb-1.5 type-overline', collapsed && 'lg:hidden')}>{section.title}</p>
                {collapsed && <div className="mx-auto mb-2 hidden h-px w-6 bg-line-subtle lg:block" aria-hidden />}
                <ul className="space-y-0.5">
                  {section.items.map(({ to, label, icon: Icon, end }) => {
                    const link = (
                      <NavLink
                        to={to}
                        end={end}
                        className={({ isActive }) =>
                          cx(
                            'group relative flex items-center gap-2.5 rounded-lg px-3 py-2 type-button transition-colors duration-150',
                            'focus-visible:outline-none focus-visible:focus-ring',
                            collapsed && 'lg:justify-center lg:px-0',
                            isActive
                              ? 'bg-selected text-primary-text'
                              : 'text-ink-secondary hover:bg-hover hover:text-ink',
                          )
                        }
                      >
                        {({ isActive }) => (
                          <>
                            {/* active rail on the inline-start edge */}
                            <span
                              aria-hidden
                              className={cx(
                                'absolute inset-y-1.5 start-0 w-0.5 rounded-full bg-primary transition-opacity duration-150',
                                isActive ? 'opacity-100' : 'opacity-0',
                              )}
                            />
                            <Icon size={ICON.md} strokeWidth={STROKE} className="shrink-0" />
                            <span className={cx('truncate', collapsed && 'lg:hidden')}>{label}</span>
                          </>
                        )}
                      </NavLink>
                    )
                    return (
                      <li key={to}>
                        {collapsed ? (
                          <Tooltip content={label} placement="end">
                            {link}
                          </Tooltip>
                        ) : (
                          link
                        )}
                      </li>
                    )
                  })}
                </ul>
              </div>
            ))}
          </nav>

          <div className="hidden shrink-0 border-t border-line-subtle p-2 lg:block">
            <button
              onClick={() => setCollapsed((v) => !v)}
              aria-label={collapsed ? 'הרחבת התפריט' : 'כיווץ התפריט'}
              className={cx(
                'flex w-full items-center gap-2.5 rounded-lg px-3 py-2 type-button text-ink-tertiary transition-colors',
                'hover:bg-hover hover:text-ink focus-visible:outline-none focus-visible:focus-ring',
                collapsed && 'justify-center px-0',
              )}
            >
              {collapsed ? <PanelLeftOpen size={ICON.md} strokeWidth={STROKE} /> : <PanelLeftClose size={ICON.md} strokeWidth={STROKE} />}
              {!collapsed && <span>כיווץ</span>}
            </button>
          </div>
        </aside>

        {mobileNav && (
          <div
            className="fixed inset-0 z-40 scrim lg:hidden"
            onClick={() => setMobileNav(false)}
            aria-hidden
          />
        )}

        {/* ── main column ─────────────────────────────────────────────────── */}
        <div className="flex min-w-0 flex-1 flex-col">
          <header className="sticky top-0 z-30 flex h-14 shrink-0 items-center gap-2 border-b border-line bg-surface/85 px-3 backdrop-blur-md sm:px-4">
            <BackButton />

            {/* on mobile the sidebar is reached from the bottom bar's "עוד", so
                the header wears the brand mark instead of a hamburger — the
                mark alone, because the name is width the breadcrumb needs */}
            <Link
              to="/"
              aria-label="ViperLogistics — לדף הבית"
              className="flex shrink-0 items-center rounded-lg focus-visible:outline-none focus-visible:focus-ring lg:hidden"
            >
              <img src="/icons/icon-192.png" alt="" className="size-7 shrink-0 rounded-md" />
            </Link>

            <Breadcrumbs />

            <button
              onClick={() => setSearchOpen(true)}
              className={cx(
                'ms-auto flex h-9 items-center gap-2 rounded-lg border border-line bg-canvas px-3 type-body text-ink-tertiary',
                'transition-colors hover:border-line-strong hover:text-ink-secondary focus-visible:outline-none focus-visible:focus-ring',
                'w-9 justify-center md:w-60 md:justify-start',
              )}
              aria-label="חיפוש גלובלי"
            >
              <Search size={ICON.sm} className="shrink-0" strokeWidth={STROKE} />
              <span className="hidden md:inline">חיפוש...</span>
              {/* the hint lives on a wrapper: `hidden` on Kbd itself would fight
                  the component's own `inline-flex` and lose */}
              <span className="ms-auto hidden md:block">
                <Kbd>Ctrl K</Kbd>
              </span>
            </button>

            <div className="flex items-center gap-0.5">
              <NotificationsBell />
              <IconButton
                label={theme === 'light' ? 'מעבר למצב כהה' : 'מעבר למצב בהיר'}
                size="sm"
                onClick={toggleTheme}
              >
                {theme === 'light' ? <Moon size={ICON.md} strokeWidth={STROKE} /> : <Sun size={ICON.md} strokeWidth={STROKE} />}
              </IconButton>

              <Popover
                trigger={({ toggle, ...aria }) => (
                  <button
                    onClick={toggle}
                    {...aria}
                    className="ms-1 flex items-center gap-2 rounded-lg p-1 transition-colors hover:bg-hover focus-visible:outline-none focus-visible:focus-ring"
                  >
                    <Avatar name={me?.profile.full_name ?? '?'} size="md" />
                    <span className="hidden min-w-0 text-start lg:block">
                      <span className="block max-w-32 truncate type-body font-medium leading-tight">
                        {me?.profile.full_name}
                      </span>
                      <span className="block type-caption text-ink-tertiary">
                        {me?.profile.is_admin ? 'מנהל מערכת' : KIND_LABELS[me?.profile.user_kind ?? ''] ?? ''}
                      </span>
                    </span>
                  </button>
                )}
              >
                {(close) => (
                  <div className="w-60">
                    <div className="flex items-center gap-2.5 px-2.5 py-2">
                      <Avatar name={me?.profile.full_name ?? '?'} size="lg" />
                      <div className="min-w-0">
                        <p className="truncate type-body font-semibold">{me?.profile.full_name}</p>
                        <p className="truncate type-caption text-ink-tertiary" dir="ltr">
                          {me?.profile.email ?? '—'}
                        </p>
                      </div>
                    </div>
                    <MenuSeparator />
                    <div className="px-2.5 pb-1 pt-0.5">
                      <span className="inline-flex items-center gap-1.5 rounded-full bg-subtle px-2 py-0.5 type-caption font-medium text-ink-secondary">
                        <User size={ICON.xs} />
                        {me?.profile.is_admin ? 'מנהל מערכת' : KIND_LABELS[me?.profile.user_kind ?? ''] ?? 'משתמש'}
                      </span>
                    </div>
                    <MenuSeparator />
                    <MenuItem
                      icon={theme === 'light' ? <Moon size={ICON.sm} /> : <Sun size={ICON.sm} />}
                      onClick={() => {
                        toggleTheme()
                        close()
                      }}
                    >
                      {theme === 'light' ? 'מצב כהה' : 'מצב בהיר'}
                    </MenuItem>
                    <MenuItem icon={<LogOut size={ICON.sm} />} danger onClick={() => void signOut()}>
                      התנתקות
                    </MenuItem>
                  </div>
                )}
              </Popover>
            </div>
          </header>

          {/* מוצג רק כשאין רשת: המסכים ממשיכים לצייר מהמטמון (ראו sw.ts),
              והפס אומר למה הנתונים עלולים להיות לא עדכניים ולמה כתיבה תיכשל */}
          {!online && (
            <div
              role="status"
              className="flex items-center justify-center gap-2 border-b border-warning-border bg-warning-subtle px-3 py-1.5 type-caption text-warning-text"
            >
              <WifiOff size={ICON.sm} strokeWidth={STROKE} className="shrink-0" />
              אין חיבור לרשת — מוצגים נתונים שנשמרו במכשיר
            </div>
          )}

          <main
            id="main"
            className={cx(
              'min-h-0 flex-1 flex flex-col',
              /* The board owns its own scrolling, so `main` does not scroll —
                 which also meant nothing here left room for the bottom bar,
                 and the last field rows sat underneath it with no way to
                 reach them. The padding gives the board's own scroller an end
                 that is on the screen. */
              location.pathname.startsWith('/board') || location.pathname === '/my/schedule'
                ? 'p-2 pb-shell sm:p-2.5 sm:pb-shell lg:p-3 lg:pb-3 overflow-hidden'
                : 'overflow-y-auto overscroll-contain p-3 pb-shell sm:p-4 sm:pb-shell lg:p-6 lg:pb-6',
            )}
          >
            <RouteGate>
              <Outlet />
            </RouteGate>
          </main>
        </div>

        <BottomNav sections={sections} onMore={() => setMobileNav(true)} />

        <CommandPalette open={searchOpen} onClose={() => setSearchOpen(false)} />
      </div>
    </PageTitleProvider>
  )
}

/* ===== BottomNav ==========================================================
   The phone's primary navigation. Four destinations plus "עוד", which opens
   the same sidebar the desktop shows permanently — so nothing is reachable
   on one form factor and lost on the other.                                */

function BottomNav({ sections, onMore }: { sections: NavSection[]; onMore: () => void }) {
  const items = bottomNavItems(sections)
  if (items.length === 0) return null

  return (
    <nav
      aria-label="ניווט ראשי"
      /* below the sidebar's scrim (z-40) so opening "עוד" dims the bar too */
      className="fixed inset-x-0 bottom-0 z-30 border-t border-line bg-surface/95 pb-safe backdrop-blur-md lg:hidden"
    >
      <ul className="flex items-stretch">
        {items.map((item) => (
          <li key={item.to} className="min-w-0 flex-1">
            <BottomNavLink item={item} />
          </li>
        ))}
        <li className="min-w-0 flex-1">
          <button
            onClick={onMore}
            aria-label="פתיחת התפריט המלא"
            className={cx(
              'flex h-14 w-full flex-col items-center justify-center gap-0.5 px-1 text-ink-tertiary',
              'transition-colors duration-150 active:bg-hover focus-visible:outline-none focus-visible:focus-ring',
            )}
          >
            <Menu size={ICON.lg} strokeWidth={STROKE} aria-hidden />
            <span className="type-caption font-medium leading-none">עוד</span>
          </button>
        </li>
      </ul>
    </nav>
  )
}

function BottomNavLink({ item }: { item: NavItem }) {
  const { to, label, shortLabel, icon: Icon, end } = item
  return (
    <NavLink
      to={to}
      end={end}
      className={({ isActive }) =>
        cx(
          'relative flex h-14 flex-col items-center justify-center gap-0.5 px-1',
          'transition-colors duration-150 active:bg-hover focus-visible:outline-none focus-visible:focus-ring',
          isActive ? 'text-primary-text' : 'text-ink-tertiary',
        )
      }
    >
      {({ isActive }) => (
        <>
          <span
            aria-hidden
            className={cx(
              'absolute inset-x-3 top-0 h-0.5 rounded-b-full bg-primary transition-opacity duration-150',
              isActive ? 'opacity-100' : 'opacity-0',
            )}
          />
          <Icon size={ICON.lg} strokeWidth={isActive ? 2.25 : STROKE} aria-hidden />
          <span className="max-w-full truncate type-caption font-medium leading-none">
            {shortLabel ?? label}
          </span>
        </>
      )}
    </NavLink>
  )
}

/* ===== BackButton =========================================================
   Always in the bar, on every screen — a phone has no browser chrome to fall
   back on, and "where was I" is the one question the breadcrumb can't answer.

   A tab opened straight onto a deep link has nothing behind it: react-router
   stamps that first entry with the key 'default', and there the button goes
   home instead of walking out of the app.                                  */

function BackButton() {
  const navigate = useNavigate()
  const { key, pathname } = useLocation()
  const fresh = key === 'default'

  return (
    <IconButton
      label={fresh ? 'לדף הבית' : 'חזרה'}
      size="sm"
      className="shrink-0"
      disabled={fresh && pathname === '/'}
      onClick={() => (fresh ? navigate('/') : navigate(-1))}
    >
      {/* the app is RTL, where "back" points at the start edge — to the right */}
      <ArrowRight size={ICON.md} strokeWidth={STROKE} className="ltr:rotate-180" />
    </IconButton>
  )
}

/* ===== Breadcrumbs ========================================================
   Section > page > entity. The entity name arrives from the detail screen
   through PageTitleProvider once its data has loaded.                     */

function Breadcrumbs() {
  const { pathname } = useLocation()
  const detailTitle = useCurrentPageTitle()

  const segments = pathname.split('/').filter(Boolean)
  /* מסך שיש לו שם משלו בטבלה — גם אם הנתיב שלו מקונן, כמו /my/schedule — הוא
     יעד ולא פירוט של יעד אחר: השם שלו הוא כל השובל, בלי קטע-אב שאין מאחוריו
     מסך להוביל אליו. */
  const exact = ROUTE_LABELS[pathname]
  const rootPath = exact ? pathname : segments.length === 0 ? '/' : `/${segments[0]}`
  const rootLabel = exact ?? ROUTE_LABELS[rootPath] ?? rootPath
  const isDetail = !exact && segments.length > 1

  return (
    <nav aria-label="מיקום נוכחי" className="min-w-0 flex-1">
      <ol className="flex min-w-0 items-center gap-1">
        {/* on a phone the trail collapses to the deepest crumb — the parent is
            one tap away in the bottom bar, so spelling it out only steals width */}
        <li className={cx('min-w-0', isDetail && 'hidden sm:block')}>
          {isDetail ? (
            <Link
              to={rootPath}
              className="truncate rounded type-body text-ink-tertiary transition-colors hover:text-ink focus-visible:outline-none focus-visible:focus-ring"
            >
              {rootLabel}
            </Link>
          ) : (
            <span className="truncate type-body font-semibold text-ink">{rootLabel}</span>
          )}
        </li>
        {isDetail && (
          <>
            <ChevronLeft size={ICON.sm} className="hidden shrink-0 text-ink-tertiary sm:block" aria-hidden />
            <li className="min-w-0">
              <span className="block truncate type-body font-semibold text-ink sm:max-w-[16rem]">
                {detailTitle ?? 'פרטים'}
              </span>
            </li>
          </>
        )}
      </ol>
    </nav>
  )
}

/** exported for the portal shell, which sits outside AppLayout */
export { Divider }
