import { describe, expect, it } from 'vitest'
import { describeScope, effectiveRoleIds, effectiveScope, scopeIds } from './scopes'
import type { PermissionRole, PermissionScope, ScopeType } from '../types/domain'

function roleDef(id: string, key: string, user_kind: PermissionRole['user_kind']): PermissionRole {
  return {
    id,
    key,
    name_he: key,
    description_he: null,
    user_kind,
    is_system: true,
    sort_order: 10,
    is_active: true,
    deleted_at: null,
  }
}

describe('effectiveRoleIds', () => {
  const roles = [
    roleDef('w', 'worker', 'staff'),
    roleDef('cv', 'customer_viewer', 'customer_user'),
    roleDef('sc', 'staff_contractor', null),
    roleDef('cm', 'contractor_manager', 'contractor_user'),
    roleDef('cw', 'contractor_worker', 'contractor_user'),
  ]

  it('drops a role bound to another kind of user', () => {
    expect(effectiveRoleIds(roles, ['w', 'cv'], 'customer_user')).toEqual(['cv'])
  })

  it('keeps a role with no kind for anyone', () => {
    expect(effectiveRoleIds(roles, ['w', 'sc'], 'staff')).toEqual(['w', 'sc'])
  })

  it('lets the contractor manager hat win over the worker hat', () => {
    expect(effectiveRoleIds(roles, ['cm', 'cw'], 'contractor_user')).toEqual(['cm'])
    expect(effectiveRoleIds(roles, ['cw'], 'contractor_user')).toEqual(['cw'])
  })
})

/**
 * ‏effectiveScope היא העותק של `app.scope_rows` (0214), ומה שהיא מכריעה הוא
 * בדיוק מה שהשתבש אצל עובד הלקוח שראה פתאום את כל האירועים: שורה אישית אחת
 * ביטלה את "רק מה שמשויך אליי" של התפקיד.
 */

let seq = 0
function row(scope_type: ScopeType, extra: Partial<PermissionScope> = {}): PermissionScope {
  seq += 1
  return {
    id: `s${seq}`,
    profile_id: null,
    role_id: null,
    resource: 'events',
    scope_type,
    scope_values: [],
    days_back: null,
    days_forward: null,
    ...extra,
  }
}

const mine = (t: ScopeType, extra: Partial<PermissionScope> = {}) => row(t, { profile_id: 'me', ...extra })
const role = (t: ScopeType, extra: Partial<PermissionScope> = {}) => row(t, { role_id: 'r1', ...extra })

describe('effectiveScope', () => {
  it('applies the role rows when the person has none', () => {
    const eff = effectiveScope('events', [], [role('own')])
    expect(eff.lifted).toBe(false)
    expect(eff.rows.map((r) => r.scope_type)).toEqual(['own'])
  })

  it('keeps the role "own" when a personal row of another type is added', () => {
    const eff = effectiveScope(
      'events',
      [mine('date_window', { days_back: 7, days_forward: 30 })],
      [role('own')],
    )
    expect(eff.rows.map((r) => r.scope_type).sort()).toEqual(['date_window', 'own'])
    expect(eff.overridden).toEqual([])
  })

  it('replaces only the role rows of the same type', () => {
    const roleCustomers = role('customers', { scope_values: ['a', 'b'] })
    const eff = effectiveScope('events', [mine('customers', { scope_values: ['a'] })], [roleCustomers, role('own')])
    expect(scopeIds(eff.rows, 'customers')).toEqual(['a'])
    expect(eff.rows.some((r) => r.scope_type === 'own')).toBe(true)
    expect(eff.overridden).toEqual([roleCustomers])
  })

  it('lifts every role restriction only with an explicit personal "all"', () => {
    const own = role('own')
    const eff = effectiveScope('events', [mine('all')], [own])
    expect(eff.lifted).toBe(true)
    expect(eff.rows.map((r) => r.scope_type)).toEqual(['all'])
    expect(eff.overridden).toEqual([own])
  })

  it('ignores rows of other resources', () => {
    const eff = effectiveScope('events', [mine('all', { resource: 'tasks' })], [role('own')])
    expect(eff.lifted).toBe(false)
    expect(eff.rows.map((r) => r.scope_type)).toEqual(['own'])
  })

  it('does not count a role-level "all" as a restriction', () => {
    const eff = effectiveScope('events', [], [role('all')])
    expect(eff.rows).toEqual([])
  })
})

describe('scopeIds', () => {
  it('is null when the dimension is not restricted', () => {
    expect(scopeIds([row('own')], 'customers')).toBeNull()
  })

  // fail-closed: הגבלה שנוספה ועוד לא נבחר בה ערך סוגרת, לא פותחת
  it('is an empty list — nothing — when the restriction has no values yet', () => {
    expect(scopeIds([row('customers')], 'customers')).toEqual([])
  })

  it('unions the values of several rows of the same type', () => {
    expect(
      scopeIds([row('customers', { scope_values: ['a'] }), row('customers', { scope_values: ['b', 'a'] })], 'customers'),
    ).toEqual(['a', 'b'])
  })
})

describe('describeScope', () => {
  const ctx = {
    customerName: 'ארקו',
    contractorName: 'מחמוד',
    nameOf: (_t: ScopeType, id: string) => `שם-${id}`,
  }

  it('always says a customer user sees only their own customer', () => {
    const lines = describeScope('events', effectiveScope('events', [mine('all')], []), {
      ...ctx,
      userKind: 'customer_user',
    })
    expect(lines[0]).toContain('רק אירועים של ארקו')
    expect(lines.join(' ')).not.toContain('בכל הלקוחות')
  })

  it('says a contractor user sees only what was delegated to them', () => {
    const lines = describeScope('tasks', effectiveScope('tasks', [], []), { ...ctx, userKind: 'contractor_user' })
    expect(lines[0]).toContain('שהואצלו למחמוד')
  })

  it('spells out "own" for an assigned-only role', () => {
    const lines = describeScope('events', effectiveScope('events', [], [role('own')]), {
      ...ctx,
      userKind: 'customer_user',
    })
    expect(lines).toContain('רק אירועים שהוא משובץ אליהם (או שיצר בעצמו)')
  })

  it('warns that an empty list shows nothing', () => {
    const lines = describeScope('events', effectiveScope('events', [mine('customers')], []), {
      ...ctx,
      userKind: 'staff',
    })
    expect(lines.join(' ')).toContain('לא יראה אף אירוע')
  })

  it('names the chosen values', () => {
    const lines = describeScope(
      'tasks',
      effectiveScope('tasks', [mine('customers', { resource: 'tasks', scope_values: ['x'] })], []),
      { ...ctx, userKind: 'staff' },
    )
    expect(lines).toContain('רק לקוחות: שם-x')
  })

  it('says everything for unrestricted staff', () => {
    expect(describeScope('events', effectiveScope('events', [], []), { ...ctx, userKind: 'staff' })).toEqual([
      'כל האירועים',
    ])
  })
})
