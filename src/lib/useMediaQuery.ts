import { useEffect, useState } from 'react'

/**
 * One place that answers "how wide is the viewport right now?".
 *
 * Layout that can be expressed in CSS should stay in CSS — these hooks exist
 * for the cases where the *component tree* differs between phone and desktop
 * (the work board renders cards instead of a virtualized grid, the calendar
 * opens on a different view), where rendering both and hiding one would mean
 * mounting FullCalendar or a virtualizer twice.
 */
export function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(() =>
    typeof window === 'undefined' ? false : window.matchMedia(query).matches,
  )

  useEffect(() => {
    const mql = window.matchMedia(query)
    const sync = () => setMatches(mql.matches)
    sync()
    mql.addEventListener('change', sync)
    return () => mql.removeEventListener('change', sync)
  }, [query])

  return matches
}

/** Below Tailwind's `lg` — the width at which the sidebar gives way to the bottom bar. */
export const useIsMobile = () => useMediaQuery('(max-width: 1023.98px)')

/** Below Tailwind's `md` — phones, where tables become cards. */
export const useIsPhone = () => useMediaQuery('(max-width: 767.98px)')
