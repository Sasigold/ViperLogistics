/**
 * ההכרעה של app.has, בצד הלקוח.
 *
 * הפונקציה יושבת בקובץ משלה ולא לצד ההוקים כי היא טהורה: היא לא נוגעת ברשת,
 * ב-DOM ובשום state. זה מה שמאפשר לבדוק אותה — והיא בדיוק החלק שכדאי לבדוק,
 * כי היא עותק שני של סדר השכבות שמוכרע בשרת, ועותק שני נוטה להיפרד מהמקור.
 */
import type { PermissionDef, UserKind } from '../types/domain'

export type EffectiveSource = 'user' | 'role' | 'kind' | 'default' | 'inherited' | 'none' | 'not_applicable'

/**
 * Resolves what a subject *effectively* gets, mirroring app.has() including the
 * implied_by walk. The editor shows this next to each control so an admin can
 * see that denying a key had no visible effect because a role still grants it —
 * the single most confusing thing about layered permissions.
 *
 * ‏`kind` הוא סוג המשתמש. מאז 0214 ‏`app.has` עונה "לא" על מפתח שאינו חל על
 * הסוג שלו (`applies_to`), ולכן מפתח שהמטריצה אינה מציגה לסוג הזה גם אינו
 * מוענק לו בשום שכבה — לא בירושה ולא בברירת מחדל.
 *
 * ‏`via` הוא המפתח שממנו ההכרעה נגזרה, כשהיא לא נפלה על המפתח עצמו: "מותר
 * בירושה" בלי לומר ממה הוא חצי תשובה.
 */
export function resolveEffective(
  key: string,
  registry: PermissionDef[],
  layers: {
    userGrants: Map<string, boolean>
    roleGrants: Map<string, boolean>
    kindDefaults: Map<string, boolean>
  },
  kind?: UserKind | null,
): { allowed: boolean; source: EffectiveSource; via?: string } {
  const byKey = new Map(registry.map((r) => [r.key, r]))
  const own = byKey.get(key)
  if (kind && own && !own.applies_to.includes(kind)) return { allowed: false, source: 'not_applicable' }
  let current: string | null = key
  let depth = 0
  while (current && depth < 8) {
    const at: string = current
    const inherited = depth > 0
    const u = layers.userGrants.get(at)
    if (u !== undefined) return inherited ? { allowed: u, source: 'inherited', via: at } : { allowed: u, source: 'user' }
    const r = layers.roleGrants.get(at)
    if (r !== undefined) return inherited ? { allowed: r, source: 'inherited', via: at } : { allowed: r, source: 'role' }
    const k = layers.kindDefaults.get(at)
    if (k !== undefined) return inherited ? { allowed: k, source: 'inherited', via: at } : { allowed: k, source: 'kind' }
    if (byKey.get(at)?.default_allowed) {
      return inherited ? { allowed: true, source: 'inherited', via: at } : { allowed: true, source: 'default' }
    }
    current = byKey.get(at)?.implied_by ?? null
    depth += 1
  }
  return { allowed: false, source: 'none' }
}
