import { describe, expect, it } from 'vitest'
import { condState, setCondState } from './pricingSchema'
import type { PriceTest } from '../../types/domain'

/* עורך התנאי בשלושה מצבים (0118). מה שנשמר כאן הוא לא רק הכתיבה החדשה אלא
   גם ההבטחה שקונפיגים קיימים אינם נפגעים: תנאי על שדה אחר שורד, ומבחן מספרי
   על אותו שדה רוכב איתו. */

const T = (field: string, op: PriceTest['op'], value?: unknown): PriceTest =>
  value === undefined ? { field, op } : { field, op, value }

describe('condState', () => {
  it('קורא את שלושת המצבים', () => {
    expect(condState([T('is_transport_only', 'is_true')], 'is_transport_only')).toBe('true')
    expect(condState([T('is_transport_only', 'is_false')], 'is_transport_only')).toBe('false')
    expect(condState([], 'is_transport_only')).toBe('off')
  })

  it('ומתעלם ממבחן שאינו בוליאני על אותו שדה', () => {
    expect(condState([T('travel_hours', 'gt', 2)], 'travel_hours')).toBe('off')
  })
})

describe('setCondState', () => {
  it('כותב is_true ו-is_false', () => {
    expect(setCondState([], 'is_transport_only', 'false')).toEqual({
      all: [T('is_transport_only', 'is_false')],
    })
    expect(setCondState([], 'is_transport_only', 'true')).toEqual({
      all: [T('is_transport_only', 'is_true')],
    })
  })

  it('ו-off מסיר את השורה ולא כותב שלילה', () => {
    const before = [T('requires_team_lead', 'is_true'), T('is_transport_only', 'is_false')]
    expect(setCondState(before, 'is_transport_only', 'off')).toEqual({
      all: [T('requires_team_lead', 'is_true')],
    })
  })

  it('רשימה שהתרוקנה חוזרת כ-null ולא כ-{all: []}', () => {
    expect(setCondState([T('porterage', 'is_true')], 'porterage', 'off')).toBeNull()
  })

  it('החלפת מצב אינה מכפילה את השורה', () => {
    const once = setCondState([], 'is_transport_only', 'true')
    const tests = once && 'all' in once ? once.all : []
    const twice = setCondState(tests, 'is_transport_only', 'false')
    expect(twice).toEqual({ all: [T('is_transport_only', 'is_false')] })
  })

  it('תנאי על שדה אחר שורד', () => {
    const before = [T('requires_team_lead', 'is_true')]
    expect(setCondState(before, 'is_transport_only', 'false')).toEqual({
      all: [T('requires_team_lead', 'is_true'), T('is_transport_only', 'is_false')],
    })
  })

  /* זה מה שמחזיק קונפיגים קיימים: הסינון הוא על הצמד (שדה, אופרטור בוליאני)
     ולא על השדה לבדו, ולכן מבחן מספרי על אותו שדה אינו נמחק בעריכה. */
  it('ומבחן מספרי על אותו שדה אינו נמחק', () => {
    const before = [T('travel_hours', 'gt', 2)]
    expect(setCondState(before, 'travel_hours', 'true')).toEqual({
      all: [T('travel_hours', 'gt', 2), T('travel_hours', 'is_true')],
    })
  })
})
