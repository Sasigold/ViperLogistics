import { describe, expect, it } from 'vitest'
import { statusOptions } from './statusOptions'
import type { Status } from '../../types/domain'

const st = (id: string, code: string): Status =>
  ({ id, code, name: code, entity: 'task' }) as Status

const STATUSES = [st('d', 'draft'), st('p', 'planned'), st('a', 'assigned')]

describe('statusOptions', () => {
  it('מי שרשאי לפרסם רואה הכול, ואינו נעול', () => {
    const r = statusOptions(STATUSES, 'p', true)
    expect(r.locked).toBe(false)
    expect(r.options.map((s) => s.code)).toEqual(['draft', 'planned', 'assigned'])
  })

  it('מי שאינו רשאי לפרסם אינו רואה "משובץ" על שורה שאינה משובצת', () => {
    const r = statusOptions(STATUSES, 'p', false)
    expect(r.locked).toBe(false)
    expect(r.options.map((s) => s.code)).toEqual(['draft', 'planned'])
  })

  /* זה החלק שנוסף ב-0117: לא רק הכניסה ל"משובץ" שמורה למי שמפרסם, גם היציאה
     ממנו. שורה שכבר פורסמה נעולה בפניו לגמרי — בורר פתוח שכל בחירה בו נדחית
     ב-42501 גרוע מבורר סגור. */
  it('ושורה שכבר פורסמה נעולה בפניו', () => {
    const r = statusOptions(STATUSES, 'a', false)
    expect(r.locked).toBe(true)
    expect(r.options.map((s) => s.code)).toEqual(['assigned'])
  })

  it('אבל מי שרשאי לפרסם כן מוריד אותה', () => {
    const r = statusOptions(STATUSES, 'a', true)
    expect(r.locked).toBe(false)
    expect(r.options).toHaveLength(3)
  })

  it('סטטוס שאינו ברשימה אינו נועל ואינו מפיל', () => {
    const r = statusOptions(STATUSES, null, false)
    expect(r.locked).toBe(false)
    expect(r.options.map((s) => s.code)).toEqual(['draft', 'planned'])
  })
})
