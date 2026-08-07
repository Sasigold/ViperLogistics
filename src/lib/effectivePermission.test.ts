import { describe, expect, it } from 'vitest'
import { resolveEffective } from './effectivePermission'
import type { PermissionDef } from '../types/domain'

/**
 * resolveEffective הוא עותק שני של סדר השכבות שמוכרע בשרת ב-app.has, והוא
 * קיים כדי להראות לאדמין *למה* מפתח פתוח או סגור. עותק שני נוטה להיפרד
 * מהמקור בשקט, ולכן הבדיקות כאן כתובות לפי אותו סדר שכבות שמתועד ב-README:
 * חריגה אישית, תפקידים, ברירת מחדל לסוג משתמש, ברירת מחדל של המפתח,
 * ואז המפתח הרחב שממנו הוא נגזר.
 */

function def(key: string, extra: Partial<PermissionDef> = {}): PermissionDef {
  return {
    key,
    module: 'test',
    resource: key.split('.')[0],
    action: key.split('.')[1] ?? 'access',
    label_he: key,
    description_he: null,
    category: 'action',
    default_allowed: false,
    is_dangerous: false,
    applies_to: ['staff'],
    implied_by: null,
    sort_order: 10,
    is_active: true,
    ...extra,
  } as PermissionDef
}

const empty = {
  userGrants: new Map<string, boolean>(),
  roleGrants: new Map<string, boolean>(),
  kindDefaults: new Map<string, boolean>(),
}

describe('resolveEffective', () => {
  it('refuses a key nobody granted and nothing implies', () => {
    expect(resolveEffective('tasks.edit', [def('tasks.edit')], empty)).toEqual({
      allowed: false,
      source: 'none',
    })
  })

  it('takes the registry default when no layer speaks', () => {
    const registry = [def('tasks.view', { default_allowed: true })]
    expect(resolveEffective('tasks.view', registry, empty)).toEqual({
      allowed: true,
      source: 'default',
    })
  })

  it('lets a personal grant beat a role that denies', () => {
    const layers = {
      ...empty,
      userGrants: new Map([['tasks.edit', true]]),
      roleGrants: new Map([['tasks.edit', false]]),
    }
    expect(resolveEffective('tasks.edit', [def('tasks.edit')], layers)).toEqual({
      allowed: true,
      source: 'user',
    })
  })

  it('lets a personal deny beat a role that allows', () => {
    const layers = {
      ...empty,
      userGrants: new Map([['tasks.edit', false]]),
      roleGrants: new Map([['tasks.edit', true]]),
    }
    expect(resolveEffective('tasks.edit', [def('tasks.edit')], layers)).toMatchObject({
      allowed: false,
      source: 'user',
    })
  })

  it('lets a role beat the kind default', () => {
    const layers = {
      ...empty,
      roleGrants: new Map([['tasks.edit', true]]),
      kindDefaults: new Map([['tasks.edit', false]]),
    }
    expect(resolveEffective('tasks.edit', [def('tasks.edit')], layers)).toEqual({
      allowed: true,
      source: 'role',
    })
  })

  it('falls back to the kind default when nothing above it speaks', () => {
    const layers = { ...empty, kindDefaults: new Map([['tasks.edit', true]]) }
    expect(resolveEffective('tasks.edit', [def('tasks.edit')], layers)).toEqual({
      allowed: true,
      source: 'kind',
    })
  })

  // זה מה שמאפשר לפצל הרשאה גסה לדקות בלי לשבור: מי שקיבל "עריכת משימות"
  // ממשיך להזיז משימות עד שאדמין יחליט אחרת.
  it('inherits from the broader key it is implied by', () => {
    const registry = [def('tasks.reschedule', { implied_by: 'tasks.edit' }), def('tasks.edit')]
    const layers = { ...empty, roleGrants: new Map([['tasks.edit', true]]) }
    expect(resolveEffective('tasks.reschedule', registry, layers)).toEqual({
      allowed: true,
      source: 'inherited',
    })
  })

  it('inherits a denial the same way it inherits a grant', () => {
    const registry = [def('tasks.reschedule', { implied_by: 'tasks.edit' }), def('tasks.edit')]
    const layers = { ...empty, userGrants: new Map([['tasks.edit', false]]) }
    expect(resolveEffective('tasks.reschedule', registry, layers)).toMatchObject({ allowed: false })
  })

  // הכשל שנמצא בסקירה: portal.attendance נרשם default_allowed=false אבל
  // implied_by=portal.view, ו-portal.view הוא default_allowed=true — ולכן
  // המפתח נפתר true לכל משתמש והשער עליו לא חסם איש.
  it('walks past its own false default into a broader key that defaults true', () => {
    const registry = [
      def('portal.attendance', { default_allowed: false, implied_by: 'portal.view' }),
      def('portal.view', { default_allowed: true }),
    ]
    expect(resolveEffective('portal.attendance', registry, empty)).toMatchObject({ allowed: true })
  })

  it('refuses once that inherited default is removed', () => {
    const registry = [
      def('portal.attendance', { default_allowed: false, implied_by: null }),
      def('portal.view', { default_allowed: true }),
    ]
    expect(resolveEffective('portal.attendance', registry, empty)).toMatchObject({ allowed: false })
  })

  it('stops rather than looping when keys imply each other', () => {
    const registry = [def('a.one', { implied_by: 'a.two' }), def('a.two', { implied_by: 'a.one' })]
    expect(resolveEffective('a.one', registry, empty)).toEqual({ allowed: false, source: 'none' })
  })

  it('refuses a key that is not in the registry at all', () => {
    expect(resolveEffective('ghost.key', [def('tasks.edit')], empty)).toEqual({
      allowed: false,
      source: 'none',
    })
  })
})
