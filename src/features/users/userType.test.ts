import { describe, expect, it } from 'vitest'
import { kindOfType, userTypeOf } from './userType'

/**
 * ההבחנה כולה יושבת בשתי הפונקציות האלה, ולכן היא נבדקת כאן ולא במסך: מה
 * נשמר במסד (תמיד אחד משלושת ה-`user_kind`) ומה הטופס מראה (ארבע אפשרויות).
 */
describe('kindOfType', () => {
  it('מנהל מערכת נשמר כשורת צוות', () => {
    expect(kindOfType('admin')).toBe('staff')
  })

  it('ושאר הסוגים הם עצמם', () => {
    expect(kindOfType('staff')).toBe('staff')
    expect(kindOfType('customer_user')).toBe('customer_user')
    expect(kindOfType('contractor_user')).toBe('contractor_user')
  })
})

describe('userTypeOf', () => {
  it('אדמין בלי תפקיד צוות הוא "מנהל מערכת"', () => {
    expect(userTypeOf({ user_kind: 'staff', is_admin: true, staff_roles: [] })).toBe('admin')
    expect(userTypeOf({ user_kind: 'staff', is_admin: true })).toBe('admin')
  })

  it('אבל אדמין שהוא גם עובד נשאר צוות', () => {
    expect(userTypeOf({ user_kind: 'staff', is_admin: true, staff_roles: [{ role: 'driver' }] })).toBe(
      'staff',
    )
  })

  it('ועובד שאינו אדמין הוא צוות, עם תפקיד או בלעדיו', () => {
    expect(userTypeOf({ user_kind: 'staff', is_admin: false, staff_roles: [] })).toBe('staff')
    expect(userTypeOf({ user_kind: 'staff', is_admin: false, staff_roles: [{ role: 'worker' }] })).toBe(
      'staff',
    )
  })

  it('משתמשי לקוח וקבלן אינם מושפעים', () => {
    expect(userTypeOf({ user_kind: 'customer_user', is_admin: false })).toBe('customer_user')
    expect(userTypeOf({ user_kind: 'contractor_user', is_admin: false })).toBe('contractor_user')
  })
})
