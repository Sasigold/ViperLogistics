import { afterEach, describe, expect, it, vi } from 'vitest'
import { actionError, errorMessage } from './errors'

/**
 * מה שהמיפוי הזה צריך להבטיח הוא שתי הבטחות מנוגדות: שטקסט של Postgres לא
 * מגיע למשתמש, ושהודעה שנכתבה במפורש בגוף RPC כן מגיעה אליו כמות שהיא —
 * כי היא ההסבר *למה* השרת סירב, והיא כבר בעברית.
 */

afterEach(() => vi.unstubAllGlobals())

describe('errorMessage', () => {
  it('maps a unique violation by code, not by its English text', () => {
    expect(errorMessage({ code: '23505', message: 'duplicate key value violates unique constraint "x"' }))
      .toBe('הערך הזה כבר קיים במערכת.')
  })

  it('maps an RLS refusal', () => {
    expect(errorMessage({ code: '42501', message: 'permission denied for table tasks' }))
      .toBe('אין לך הרשאה לבצע את הפעולה הזו.')
  })

  it('maps a missing row from PostgREST', () => {
    expect(errorMessage({ code: 'PGRST116' })).toBe('הרשומה לא נמצאה.')
  })

  // זה הלב: raise exception 'טקסט' בגוף RPC הוא הודעה למשתמש
  it('passes through a message a function raised deliberately', () => {
    const msg = 'לא ניתן להתחיל משמרת לפני השעה 18:00'
    expect(errorMessage({ message: msg })).toBe(msg)
  })

  it('passes through an authored message even when it carries an unmapped code', () => {
    const msg = 'שעת היציאה חייבת להיות אחרי שעת הכניסה'
    expect(errorMessage({ code: 'P0001', message: msg })).toBe(msg)
  })

  it('replaces raw engine text that happens to be in Hebrew-free English', () => {
    const out = errorMessage({ message: 'new row violates row-level security policy for table "tasks"' })
    expect(out).not.toContain('row-level security')
    expect(out).not.toContain('tasks')
  })

  it('does not leak table or column names from a constraint violation', () => {
    const out = errorMessage({ message: 'insert or update on table "task_assignments" violates foreign key constraint "fk_x"' })
    expect(out).not.toContain('task_assignments')
    expect(out).not.toContain('fk_x')
  })

  it('reports being offline rather than whatever the fetch threw', () => {
    vi.stubGlobal('navigator', { onLine: false })
    expect(errorMessage(new TypeError('Failed to fetch'))).toBe('אין חיבור לרשת. בדוק את החיבור ונסה שוב.')
  })

  it('recognises a failed fetch even when the browser still believes it is online', () => {
    vi.stubGlobal('navigator', { onLine: true })
    expect(errorMessage(new TypeError('Failed to fetch'))).toBe('אין חיבור לרשת. בדוק את החיבור ונסה שוב.')
  })

  it('falls back to something generic rather than empty for null', () => {
    expect(errorMessage(null)).toBeTruthy()
    expect(errorMessage(undefined)).toBeTruthy()
  })
})

describe('actionError', () => {
  it('names the action that failed alongside the reason', () => {
    const out = actionError('שמירת האירוע', { code: '23505' })
    expect(out).toContain('שמירת האירוע')
    expect(out).toContain('כבר קיים')
  })

  it('does not staple a generic reason onto the action twice', () => {
    const out = actionError('שמירת האירוע', new Error('something exploded'))
    expect(out).toBe('שמירת האירוע נכשלה. נסה שוב.')
  })
})
