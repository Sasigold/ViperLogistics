/**
 * ההכרעה של app.scope_rows, בצד הלקוח.
 *
 * כמו effectivePermission: עותק שני של מה שמוכרע בשרת, טהור כדי שאפשר יהיה
 * לבדוק אותו. הוא קיים בשביל מסך "נתונים" של משתמש — שהציג רק את השורות
 * האישיות ואמר "ללא הגבלת נתונים" גם כשתפקיד צמצם את המשתמש ל"רק מה שמשויך
 * אליי" (כך קרה עם תפקיד "מחסן", 0196: הענקה אישית של calendar.view פתחה את
 * הלוח, וההיקף של התפקיד השאיר אותו ריק).
 */
import type { PermissionRole, PermissionScope, UserKind } from '../types/domain'

/**
 * The roles that actually apply to a profile — mirrors app.my_role_ids (0104):
 * active, not deleted, matching the user kind (0067), and the contractor
 * manager's hat beats the contractor worker's.
 */
export function applicableRoleIds(roles: PermissionRole[], assigned: string[], userKind: UserKind): string[] {
  const mine = roles.filter(
    (r) => assigned.includes(r.id) && r.is_active && !r.deleted_at && (!r.user_kind || r.user_kind === userKind),
  )
  const managerHat = mine.some((r) => r.key === 'contractor_manager' || r.key === 'staff_contractor')
  return mine.filter((r) => r.key !== 'contractor_worker' || !managerHat).map((r) => r.id)
}

/**
 * The role scope rows that still bind a user — mirrors app.scope_rows (0085):
 * any row of the user's own for a resource replaces every role row for that
 * resource, so role rows count only on resources the user has none on.
 */
export function inheritedScopes(
  roleScopes: PermissionScope[],
  roleIds: string[],
  ownScopes: PermissionScope[],
): PermissionScope[] {
  const overridden = new Set(ownScopes.map((s) => s.resource))
  return roleScopes.filter((s) => s.role_id && roleIds.includes(s.role_id) && !overridden.has(s.resource))
}
