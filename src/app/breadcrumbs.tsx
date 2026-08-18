import { createContext, useContext, useEffect, useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import { useLocation } from 'react-router'
import { ROUTE_LABELS } from './nav'

/**
 * Lets a detail screen contribute the entity's real name to the header
 * breadcrumb ("לקוחות / אלפא הפקות") instead of a generic "פרטים".
 * Purely presentational — nothing is fetched here.
 */
const Ctx = createContext<{ title: string | null; setTitle: (t: string | null) => void }>({
  title: null,
  setTitle: () => {},
})

export function PageTitleProvider({ children }: { children: ReactNode }) {
  const [title, setTitle] = useState<string | null>(null)
  const value = useMemo(() => ({ title, setTitle }), [title])
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useCurrentPageTitle() {
  return useContext(Ctx).title
}

/** Call from a detail screen once its entity has loaded. */
export function usePageTitle(title: string | null | undefined) {
  const { setTitle } = useContext(Ctx)
  useEffect(() => {
    setTitle(title ?? null)
    return () => setTitle(null)
  }, [title, setTitle])
}

const APP_NAME = 'ViperLogistics'

/**
 * Keeps `document.title` in step with the screen.
 *
 * Every route rendered the same string — the one hardcoded in index.html — so
 * the tab said nothing, twelve entries of browser history all read alike, and a
 * screen reader announced the same title on every navigation, which is the one
 * moment it is relied on to say what just happened. The strings needed for this
 * already existed: `ROUTE_LABELS` for the screen, `usePageTitle` for the entity
 * a detail screen has loaded.
 *
 * Deliberately not `<title>` in JSX: React 19 hoists that, but this has to
 * answer for routes that never render a component of their own.
 */
export function useDocumentTitle() {
  const { pathname } = useLocation()
  const detail = useCurrentPageTitle()

  useEffect(() => {
    const exact = ROUTE_LABELS[pathname]
    const segments = pathname.split('/').filter(Boolean)
    const root = exact ?? ROUTE_LABELS[segments.length === 0 ? '/' : `/${segments[0]}`]
    /* the entity first: a narrow tab strip only keeps the opening characters,
       and "אלפא הפקות" identifies the tab where "לקוחות" cannot. The section
       still follows it, so a row of tabs stays groupable by eye. */
    const parts = [detail, root].filter(Boolean)
    document.title = parts.length ? `${parts.join(' · ')} · ${APP_NAME}` : APP_NAME
  }, [pathname, detail])
}
