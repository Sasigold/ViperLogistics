import { useEffect, useId, useRef, useState } from 'react'
import type { CSSProperties, KeyboardEvent, ReactNode } from 'react'
import { NavLink, useLocation, useNavigate } from 'react-router'
import { ChevronDown, ICON, STROKE, Search, Star, X } from '../components/ui/icons'
import { Tooltip, cx } from '../components/ui'
import { useAuth } from '../state/auth'
import { useMediaQuery } from '../lib/useMediaQuery'
import { CommandNavBadge } from '../features/command/CommandNavBadge'
import { activeNavSection, filterNavItems, navNeedsFolding } from './nav'
import type { NavItem, NavSection } from './nav'

const OPEN_KEY = 'vl-nav-open'
const FAV_KEY = 'vl-nav-fav'

/* העדפות תצוגה של הדפדפן הזה בלבד — מצב פרטי או אחסון חסום מחזירים ריק */
function readList(key: string): string[] | null {
  try {
    const v = JSON.parse(localStorage.getItem(key) ?? 'null')
    return Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : null
  } catch {
    return null
  }
}
function writeList(key: string, v: string[]) {
  try {
    localStorage.setItem(key, JSON.stringify(v))
  } catch {
    /* אין אחסון — ההעדפה פשוט לא תישמר */
  }
}

const toneStyle = (tone: number | undefined): CSSProperties | undefined =>
  tone === undefined
    ? undefined
    : {
        color: `var(--vl-ev-${tone})`,
        backgroundColor: `color-mix(in srgb, var(--vl-ev-${tone}) 13%, transparent)`,
      }

/**
 * התפריט עצמו: חיפוש, מועדפים, וקבוצות שנפתחות ונסגרות.
 *
 * רק הקבוצה של הדף הנוכחי נפתחת מעצמה; מה שהמשתמש פתח או סגר נשמר בדפדפן.
 * המועדפים נשמרים לכל משתמש בנפרד (מכשיר משותף), ומסוננים מול מה שגלוי לו
 * עכשיו — רשומה שההרשאה אליה נלקחה נעלמת גם מהמועדפים. תפריט קצר (עובד
 * שטח, קבלן) מוצג פתוח כולו, ובמצב מכווץ בדסקטופ — פס אייקונים כמו קודם.
 */
export function SidebarNav({ sections, collapsed }: { sections: NavSection[]; collapsed: boolean }) {
  const isDesktop = useMediaQuery('(min-width: 1024px)')
  const rail = collapsed && isDesktop
  const meId = useAuth((s) => s.me?.profile.id ?? '')
  const { pathname } = useLocation()
  const navigate = useNavigate()

  const active = activeNavSection(sections, pathname)
  const folding = navNeedsFolding(sections)
  const [open, setOpen] = useState<string[]>(() => readList(OPEN_KEY) ?? [])
  const favKey = `${FAV_KEY}:${meId}`
  const [fav, setFav] = useState<string[]>(() => readList(favKey) ?? [])
  const [query, setQuery] = useState('')
  const searchRef = useRef<HTMLInputElement>(null)

  useEffect(() => setFav(readList(favKey) ?? []), [favKey])
  // the group of the page you land on opens itself, and stays open after
  useEffect(() => {
    if (active) setOpen((o) => (o.includes(active) ? o : [...o, active]))
  }, [active])
  useEffect(() => writeList(OPEN_KEY, open), [open])
  useEffect(() => setQuery(''), [pathname])

  const toggleGroup = (id: string) => setOpen((o) => (o.includes(id) ? o.filter((x) => x !== id) : [...o, id]))
  const toggleFav = (to: string) =>
    setFav((f) => {
      const next = f.includes(to) ? f.filter((x) => x !== to) : [...f, to]
      writeList(favKey, next)
      return next
    })

  const top = sections.filter((s) => s.placement === 'top')
  const groups = sections.filter((s) => !s.placement)
  const footer = sections.filter((s) => s.placement === 'footer')
  const flat = sections.flatMap((s) => s.items)
  const favorites = fav.map((to) => flat.find((i) => i.to === to)).filter((i): i is NavItem => !!i)
  const hits = filterNavItems(sections, query)

  if (rail) {
    return (
      <nav className="min-h-0 flex-1 space-y-2 overflow-y-auto px-2 pb-3 pt-1" aria-label="ניווט ראשי">
        {sections.map((section, n) => (
          <div key={section.id}>
            {n > 0 && <div className="mx-auto mb-2 h-px w-6 bg-line-subtle" aria-hidden />}
            <ul className="space-y-0.5">
              {section.items.map((item) => (
                <li key={item.to + item.label}>
                  <Tooltip content={item.label} placement="end">
                    <NavRow item={item} rail />
                  </Tooltip>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </nav>
    )
  }

  const onSearchKey = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Escape') setQuery('')
    if (e.key === 'Enter' && hits[0]) navigate(hits[0].to)
  }

  const row = (item: NavItem, inGroup = false) => (
    <li key={item.to + item.label} className="group/row relative">
      <NavRow item={item} inGroup={inGroup} />
      <FavButton item={item} on={fav.includes(item.to)} onToggle={toggleFav} />
    </li>
  )

  return (
    <>
      {folding && (
        <div className="px-2 pb-2">
          <label className="flex h-9 items-center gap-2 rounded-lg border border-line bg-canvas px-2.5 text-ink-tertiary transition-colors focus-within:border-primary-border focus-within:focus-ring">
            <Search size={ICON.sm} strokeWidth={STROKE} className="shrink-0" aria-hidden />
            <input
              ref={searchRef}
              id="sidebar-search"
              type="search"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={onSearchKey}
              placeholder="מעבר לדף..."
              aria-label="חיפוש בתפריט"
              autoComplete="off"
              className="min-w-0 flex-1 bg-transparent type-body text-ink outline-none placeholder:text-ink-tertiary [&::-webkit-search-cancel-button]:hidden"
            />
            {query && (
              <button
                type="button"
                onClick={() => {
                  setQuery('')
                  searchRef.current?.focus()
                }}
                aria-label="ניקוי החיפוש"
                className="rounded p-0.5 hover:bg-hover hover:text-ink focus-visible:outline-none focus-visible:focus-ring"
              >
                <X size={ICON.sm} strokeWidth={STROKE} />
              </button>
            )}
          </label>
        </div>
      )}

      <nav className="min-h-0 flex-1 overflow-y-auto px-2 pb-3" aria-label="ניווט ראשי">
        {query.trim() ? (
          hits.length ? (
            <ul className="space-y-0.5">{hits.map((i) => row(i))}</ul>
          ) : (
            <p className="px-3 py-2 type-caption text-ink-tertiary">אין דף בשם "{query.trim()}"</p>
          )
        ) : (
          <div className="space-y-1">
            {top.map((s) => (
              <ul key={s.id} className="space-y-0.5">
                {s.items.map((i) => row(i))}
              </ul>
            ))}

            {favorites.length > 0 && (
              <div className="pt-2">
                <p className="flex items-center gap-1.5 px-3 pb-1 type-overline">
                  <Star size={ICON.xs} strokeWidth={STROKE} className="fill-warning text-warning" aria-hidden />
                  מועדפים
                </p>
                <ul className="space-y-0.5">{favorites.map((i) => row(i))}</ul>
              </div>
            )}

            {(top.length > 0 || favorites.length > 0) && <div className="mx-2 my-2 h-px bg-line-subtle" aria-hidden />}

            {groups.map((s) =>
              /* קבוצה של רשומה אחת (לאדמין, "אישי" = רק התראות) היא שורה, לא כותרת */
              folding && s.items.length === 1 ? (
                <ul key={s.id}>{row(s.items[0])}</ul>
              ) : folding ? (
                <Group key={s.id} section={s} open={open.includes(s.id)} onToggle={() => toggleGroup(s.id)}>
                  {s.items.map((i) => row(i, true))}
                </Group>
              ) : (
                <div key={s.id} className="pb-2">
                  <p className="px-3 pb-1 pt-1 type-overline">{s.title}</p>
                  <ul className="space-y-0.5">{s.items.map((i) => row(i))}</ul>
                </div>
              ),
            )}
          </div>
        )}
      </nav>

      {footer.length > 0 && !query.trim() && (
        <div className="shrink-0 border-t border-line-subtle px-2 py-2">
          <ul className="space-y-0.5">{footer.flatMap((s) => s.items).map((i) => row(i))}</ul>
        </div>
      )}
    </>
  )
}

function Group({
  section,
  open,
  onToggle,
  children,
}: {
  section: NavSection
  open: boolean
  onToggle: () => void
  children: ReactNode
}) {
  const panelId = useId()
  const Icon = section.icon
  return (
    <div>
      <button
        type="button"
        onClick={onToggle}
        aria-expanded={open}
        aria-controls={panelId}
        className="flex h-9 w-full items-center gap-2.5 rounded-lg px-2 type-button text-ink transition-colors duration-150 hover:bg-hover focus-visible:outline-none focus-visible:focus-ring"
      >
        <span className="grid size-6 shrink-0 place-items-center rounded-md" style={toneStyle(section.tone)} aria-hidden>
          {Icon && <Icon size={ICON.sm} strokeWidth={STROKE} />}
        </span>
        <span className="truncate font-semibold">{section.title}</span>
        <span className="ms-auto type-caption tabular text-ink-tertiary">{section.items.length}</span>
        <ChevronDown
          size={ICON.sm}
          strokeWidth={STROKE}
          aria-hidden
          className={cx('shrink-0 text-ink-tertiary transition-transform duration-150', !open && 'rotate-90')}
        />
      </button>
      {open && (
        <ul id={panelId} className="mb-1.5 ms-[1.3rem] mt-0.5 space-y-0.5 border-s border-line ps-1.5">
          {children}
        </ul>
      )}
    </div>
  )
}

function NavRow({ item, rail, inGroup }: { item: NavItem; rail?: boolean; inGroup?: boolean }) {
  const { to, label, icon: Icon, end, badge } = item
  return (
    <NavLink
      to={to}
      end={end}
      className={({ isActive }) =>
        cx(
          'relative flex items-center gap-2.5 rounded-lg type-button transition-colors duration-150',
          'focus-visible:outline-none focus-visible:focus-ring',
          rail ? 'justify-center py-2' : cx('py-2 pe-8', inGroup ? 'ps-2.5' : 'ps-3'),
          isActive ? 'bg-selected font-semibold text-primary-text' : 'text-ink-secondary hover:bg-hover hover:text-ink',
        )
      }
    >
      <Icon size={ICON.md} strokeWidth={STROKE} className="shrink-0" />
      {!rail && <span className="truncate">{label}</span>}
      {badge === 'command' && <CommandNavBadge compact={rail} />}
    </NavLink>
  )
}

/** הכוכב — מופיע במעבר עכבר או בפוקוס, ונשאר דלוק על מועדף */
function FavButton({ item, on, onToggle }: { item: NavItem; on: boolean; onToggle: (to: string) => void }) {
  const label = on ? `הסרת "${item.label}" מהמועדפים` : `הוספת "${item.label}" למועדפים`
  return (
    <button
      type="button"
      onClick={() => onToggle(item.to)}
      aria-label={label}
      aria-pressed={on}
      title={on ? 'הסרה מהמועדפים' : 'הוספה למועדפים'}
      className={cx(
        'absolute inset-y-0 end-1 my-auto grid size-6 place-items-center rounded-md text-ink-tertiary transition-opacity',
        'hover:bg-hover hover:text-ink focus-visible:opacity-100 focus-visible:outline-none focus-visible:focus-ring',
        on ? 'opacity-100' : 'opacity-0 group-hover/row:opacity-100 pointer-coarse:opacity-40',
      )}
    >
      <Star size={ICON.sm} strokeWidth={STROKE} className={cx(on && 'fill-warning text-warning')} />
    </button>
  )
}
