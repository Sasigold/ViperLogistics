import { describe, expect, it } from 'vitest'
import { applicableRoleIds, inheritedScopes } from './effectiveScopes'
import type { PermissionRole, PermissionScope } from '../types/domain'

/**
 * עותק של app.my_role_ids ו-app.scope_rows. המקרה שהוליד אותו: משתמש
 * "מחסן" (0196) שקיבל calendar.view אישית וראה לוח ריק, כי ההיקף "own" של
 * התפקיד המשיך לחול עליו והמסך אמר "ללא הגבלת נתונים".
 */

function role(id: string, extra: Partial<PermissionRole> = {}): PermissionRole {
  return {
    id,
    key: id,
    name_he: id,
    description_he: null,
    user_kind: null,
    is_system: true,
    sort_order: 0,
    is_active: true,
    deleted_at: null,
    ...extra,
  }
}

function scope(id: string, extra: Partial<PermissionScope>): PermissionScope {
  return {
    id,
    profile_id: null,
    role_id: null,
    resource: 'events',
    scope_type: 'own',
    scope_values: [],
    days_back: null,
    days_forward: null,
    ...extra,
  }
}

describe('applicableRoleIds', () => {
  it('drops roles of another user kind, inactive and deleted ones', () => {
    const roles = [
      role('wh', { user_kind: 'customer_user' }),
      role('staff', { user_kind: 'staff' }),
      role('off', { is_active: false }),
      role('gone', { deleted_at: '2026-01-01' }),
      role('any'),
    ]
    expect(applicableRoleIds(roles, ['wh', 'staff', 'off', 'gone', 'any'], 'customer_user')).toEqual(['wh', 'any'])
  })

  it('ignores roles that are not assigned', () => {
    expect(applicableRoleIds([role('a'), role('b')], ['b'], 'staff')).toEqual(['b'])
  })

  it('the contractor manager hat beats the contractor worker one', () => {
    const roles = [role('contractor_worker'), role('contractor_manager')]
    expect(applicableRoleIds(roles, ['contractor_worker', 'contractor_manager'], 'contractor_user')).toEqual([
      'contractor_manager',
    ])
    expect(applicableRoleIds(roles, ['contractor_worker'], 'contractor_user')).toEqual(['contractor_worker'])
  })
})

describe('inheritedScopes', () => {
  const roleOwnEvents = scope('r1', { role_id: 'wh', resource: 'events' })
  const roleOwnTasks = scope('r2', { role_id: 'wh', resource: 'tasks' })

  it('role rows bind while the user has none of their own', () => {
    expect(inheritedScopes([roleOwnEvents, roleOwnTasks], ['wh'], [])).toEqual([roleOwnEvents, roleOwnTasks])
  })

  it("a user row on a resource replaces the role's rows there — and only there", () => {
    const all = scope('u1', { profile_id: 'p', resource: 'events', scope_type: 'all' })
    expect(inheritedScopes([roleOwnEvents, roleOwnTasks], ['wh'], [all])).toEqual([roleOwnTasks])
  })

  it('rows of roles that do not apply are not inherited', () => {
    expect(inheritedScopes([roleOwnEvents], ['other'], [])).toEqual([])
  })
})
