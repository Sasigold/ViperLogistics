import { createContext, useContext, useEffect, useMemo, useState } from 'react'
import type { ReactNode } from 'react'

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
