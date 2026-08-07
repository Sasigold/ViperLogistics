/**
 * ההכרעה של app.has, בצד הלקוח.
 *
 * הפונקציה יושבת בקובץ משלה ולא לצד ההוקים כי היא טהורה: היא לא נוגעת ברשת,
 * ב-DOM ובשום state. זה מה שמאפשר לבדוק אותה — והיא בדיוק החלק שכדאי לבדוק,
 * כי היא עותק שני של סדר השכבות שמוכרע בשרת, ועותק שני נוטה להיפרד מהמקור.
 */
import type { PermissionDef } from '../types/domain'

/**
 * Resolves what a subject *effectively* gets, mirroring app.has() including the
 * implied_by walk. The editor shows this next to each control so an admin can
 * see that denying a key had no visible effect because a role still grants it —
 * the single most confusing thing about layered permissions.
 */
export function resolveEffective(
  key: string,
  registry: PermissionDef[],
  layers: {
    userGrants: Map<string, boolean>
    roleGrants: Map<string, boolean>
    kindDefaults: Map<string, boolean>
  },
): { allowed: boolean; source: 'user' | 'role' | 'kind' | 'default' | 'inherited' | 'none' } {
  const byKey = new Map(registry.map((r) => [r.key, r]))
  let current: string | null = key
  let depth = 0
  while (current && depth < 8) {
    const u = layers.userGrants.get(current)
    if (u !== undefined) return { allowed: u, source: depth === 0 ? 'user' : 'inherited' }
    const r = layers.roleGrants.get(current)
    if (r !== undefined) return { allowed: r, source: depth === 0 ? 'role' : 'inherited' }
    const k = layers.kindDefaults.get(current)
    if (k !== undefined) return { allowed: k, source: depth === 0 ? 'kind' : 'inherited' }
    if (byKey.get(current)?.default_allowed) {
      return { allowed: true, source: depth === 0 ? 'default' : 'inherited' }
    }
    current = byKey.get(current)?.implied_by ?? null
    depth += 1
  }
  return { allowed: false, source: 'none' }
}
