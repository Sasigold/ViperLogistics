/**
 * היקף הנתונים בפועל — הבבואה של `app.scope_rows` (0214) בצד הלקוח.
 *
 * עד 0214 שורה אישית אחת, מכל סוג שהוא, החליפה את **כל** ההגבלות שבאו
 * מהתפקיד על אותו מודול. חלון תאריכים שנוסף לעובד ביטל לו בשקט את "רק מה
 * שמשויך אליי", כלומר הגבלה פתחה גישה. מעכשיו ההחלפה היא לפי סוג: שורה
 * אישית מסוג מסוים מחליפה רק את שורות התפקיד מאותו סוג, ו"ללא הגבלה"
 * אישית (`all`) היא הדרך המפורשת היחידה לבטל את כולן.
 *
 * והכלל השני של 0214: רשימה ריקה אינה "בלי הגבלה" אלא "שום דבר". הגבלה
 * שנוספה ועוד לא נבחרו בה ערכים סוגרת — היא לא פותחת.
 *
 * הקובץ טהור (בלי רשת ובלי React) כדי שאפשר יהיה לבדוק אותו, כי עותק שני של
 * הכרעה שנעשית בשרת נוטה להיפרד מהמקור בשקט.
 */
import type { PermissionRole, PermissionScope, ScopeType, UserKind } from '../types/domain'

/**
 * התפקידים שבתוקף לאדם — הבבואה של `app.my_role_ids()`: תפקיד שנקשר לסוג
 * משתמש אחר אינו חל (0067), ועובד קבלן נבלע במי שהוא גם מנהל קבלן או עובד
 * שמביא סגל (0104). ההיקפים של תפקיד שאינו בתוקף אינם חלים, ולכן המסך אינו
 * מציג אותם כהגבלה.
 */
export function effectiveRoleIds(roles: PermissionRole[], heldIds: string[], kind: UserKind): string[] {
  const held = roles.filter(
    (r) => heldIds.includes(r.id) && r.is_active && !r.deleted_at && (!r.user_kind || r.user_kind === kind),
  )
  const manager = held.some((r) => r.key === 'contractor_manager' || r.key === 'staff_contractor')
  return held.filter((r) => r.key !== 'contractor_worker' || !manager).map((r) => r.id)
}

export interface EffectiveScope {
  /** שורה אישית "ללא הגבלה" — כל הגבלות התפקיד בוטלו */
  lifted: boolean
  /** השורות שחלות בפועל */
  rows: PermissionScope[]
  /** שורות תפקיד שהוחלפו בשורה אישית מאותו סוג (או בוטלו ב"ללא הגבלה") */
  overridden: PermissionScope[]
}

/**
 * ‏`personal` הן השורות של המשתמש עצמו, ו-`fromRoles` הן השורות של כל
 * התפקידים שבתוקף לו. שורת `all` של תפקיד אינה מגבילה דבר, ולכן היא
 * אינה נספרת כהגבלה שחלה.
 */
export function effectiveScope(
  resource: string,
  personal: PermissionScope[],
  fromRoles: PermissionScope[],
): EffectiveScope {
  const mine = personal.filter((s) => s.resource === resource)
  const roles = fromRoles.filter((s) => s.resource === resource && s.scope_type !== 'all')
  if (mine.some((s) => s.scope_type === 'all')) {
    return { lifted: true, rows: mine.filter((s) => s.scope_type === 'all'), overridden: roles }
  }
  const replaced = new Set(mine.map((s) => s.scope_type))
  return {
    lifted: false,
    rows: [...mine, ...roles.filter((s) => !replaced.has(s.scope_type))],
    overridden: roles.filter((s) => replaced.has(s.scope_type)),
  }
}

/**
 * מימד מזהים אחד, כמו ש-`app.scope_ids` עונה עליו: ‏null — המימד אינו מוגבל;
 * מערך ריק — מוגבל לשום דבר; אחרת — המזהים המותרים.
 */
export function scopeIds(rows: PermissionScope[], type: ScopeType): string[] | null {
  const of = rows.filter((r) => r.scope_type === type)
  if (!of.length) return null
  return [...new Set(of.flatMap((r) => r.scope_values))]
}

export interface ScopeContext {
  userKind: UserKind
  customerName?: string | null
  contractorName?: string | null
  /** שם להצגה של מזהה במימד נתון (לקוח, סטטוס, משאית...) */
  nameOf: (type: ScopeType, id: string) => string
}

const NOUN: Record<string, string> = { events: 'אירועים', tasks: 'משימות', customers: 'לקוחות', contractors: 'קבלנים' }
const ONE: Record<string, string> = { events: 'אירוע', tasks: 'משימה', customers: 'לקוח', contractors: 'קבלן' }

/**
 * מה המשתמש רואה במודול, במשפטים. השורה הראשונה היא תמיד הגדר של סוג
 * המשתמש — משתמש לקוח לעולם אינו רואה לקוח אחר, ומשתמש קבלן רואה רק מה
 * שהואצל לקבלן שלו — כי זה בדיוק מה שהמשפט "ללא הגבלה" הסתיר.
 */
export function describeScope(resource: string, eff: EffectiveScope, ctx: ScopeContext): string[] {
  const noun = NOUN[resource] ?? resource
  const lines: string[] = []

  if (ctx.userKind === 'customer_user' && (resource === 'events' || resource === 'tasks')) {
    lines.push(`רק ${noun} של ${ctx.customerName ?? 'הלקוח שלו'} — לעולם לא של לקוח אחר`)
  } else if (ctx.userKind === 'contractor_user' && resource === 'tasks') {
    lines.push(`רק משימות שהואצלו ל${ctx.contractorName ?? 'קבלן שלו'}`)
  } else if (ctx.userKind === 'contractor_user' && resource === 'events') {
    lines.push(`רק אירועים שיש בהם משימה שהואצלה ל${ctx.contractorName ?? 'קבלן שלו'}`)
  } else if (resource === 'customers' && ctx.userKind === 'customer_user') {
    lines.push(`רק ${ctx.customerName ?? 'הלקוח שלו'}`)
  } else if (resource === 'contractors' && ctx.userKind === 'contractor_user') {
    lines.push(`רק ${ctx.contractorName ?? 'הקבלן שלו'}`)
  }

  if (eff.lifted) {
    lines.push(
      eff.overridden.length
        ? 'ללא הגבלה נוספת — ההגבלות שמגיעות מהתפקיד בוטלו למשתמש הזה'
        : 'ללא הגבלה נוספת',
    )
    return lines
  }

  const own = eff.rows.some((r) => r.scope_type === 'own')
  if (own) lines.push(`רק ${noun} שהוא משובץ אליהם (או שיצר בעצמו)`)

  for (const type of ['customers', 'contractors', 'task_types', 'statuses', 'execution_methods', 'trucks'] as const) {
    const ids = scopeIds(eff.rows, type)
    if (ids === null) continue
    if (!ids.length) {
      lines.push(`הוגדרה הגבלת ${TYPE_NOUN[type]} בלי לבחור אף ערך — לא יראה אף ${ONE[resource] ?? noun}`)
      continue
    }
    lines.push(`רק ${TYPE_NOUN[type]}: ${ids.map((id) => ctx.nameOf(type, id)).join(', ')}`)
  }

  const back = maxOf(eff.rows, 'days_back')
  const fwd = maxOf(eff.rows, 'days_forward')
  if (back !== null || fwd !== null) {
    const parts = [
      back !== null ? `${back} ימים אחורה` : 'בלי גבול אחורה',
      fwd !== null ? `${fwd} ימים קדימה` : 'בלי גבול קדימה',
    ]
    lines.push(`חלון תאריכים: ${parts.join(', ')}`)
  }

  if (!lines.length) lines.push(ctx.userKind === 'staff' ? `כל ה${noun}` : 'ללא הגבלה נוספת')
  return lines
}

const TYPE_NOUN: Record<string, string> = {
  customers: 'לקוחות',
  contractors: 'קבלנים',
  task_types: 'סוגי משימות',
  statuses: 'סטטוסים',
  execution_methods: 'אופני ביצוע',
  trucks: 'משאיות',
}

/** החלון הרחב גובר, כמו ב-`app.scope_date_from/to`. */
function maxOf(rows: PermissionScope[], col: 'days_back' | 'days_forward'): number | null {
  const vals = rows.filter((r) => r.scope_type === 'date_window' && r[col] != null).map((r) => r[col] as number)
  return vals.length ? Math.max(...vals) : null
}
