import { useAuth } from '../state/auth'
import { navAudience, visibleNavSections } from './nav'
import { parseHomePref } from './homePref'
import type { HomePref } from './homePref'

/** ההעדפה של המשתמש המחובר, מתוך ה-session (user_metadata). */
export function useHomePref(): HomePref {
  const meta = useAuth((s) => s.session?.user.user_metadata)
  return parseHomePref(meta)
}

export function useVisibleSections() {
  const has = useAuth((s) => s.has)
  const me = useAuth((s) => s.me)
  return visibleNavSections(has, navAudience(me))
}
