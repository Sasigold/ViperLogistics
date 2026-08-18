import { describe, expect, it } from 'vitest'
import { filterValue, ilikeAcross } from './postgrestFilter'

describe('filterValue', () => {
  it('מצטט ערך פשוט', () => {
    expect(filterValue('אירוע')).toBe('"אירוע"')
  })

  it('פסיק נשאר בתוך הערך ואינו הופך למפריד', () => {
    expect(filterValue('תל אביב, הרצל 5')).toBe('"תל אביב, הרצל 5"')
  })

  it('ממלט מרכאות כפולות', () => {
    expect(filterValue('אולם "הדר"')).toBe('"אולם \\"הדר\\""')
  })

  it('ממלט לוכסן אחורי לפני שהוא ממלט מרכאות', () => {
    expect(filterValue('a\\b')).toBe('"a\\\\b"')
    expect(filterValue('a\\"b')).toBe('"a\\\\\\"b"')
  })

  it('סוגריים ונקודות אינם דורשים טיפול מיוחד בתוך הציטוט', () => {
    expect(filterValue('(הפקות) בע"מ')).toBe('"(הפקות) בע\\"מ"')
  })
})

describe('ilikeAcross', () => {
  it('בונה תנאי לכל עמודה עם אותו ערך מצוטט', () => {
    expect(ilikeAcross(['title', 'notes'], 'חג')).toBe('title.ilike."%חג%",notes.ilike."%חג%"')
  })

  it('מונח עם פסיק אינו מגדיל את מספר התנאים', () => {
    const out = ilikeAcross(['a', 'b'], 'x,y')
    // שתי עמודות, ולכן בדיוק מפריד אחד ברמה העליונה
    expect(out.split('.ilike.').length - 1).toBe(2)
    expect(out).toBe('a.ilike."%x,y%",b.ilike."%x,y%"')
  })

  it('שומר על % ו-_ כתווי תבנית של ilike', () => {
    expect(ilikeAcross(['a'], '50%')).toBe('a.ilike."%50%%"')
  })
})
