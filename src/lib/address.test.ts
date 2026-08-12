import { describe, expect, it } from 'vitest'
import { shortAddress } from './address'

/**
 * הכתובת נשמרת במלואה במסד ומשמשת לחיפוש; מה שנבדק כאן הוא רק מה שהעין רואה.
 * טעות כאן מסתירה מהמשתמש את הרחוב או את העיר שאליהם הוא אמור להגיע.
 */

describe('shortAddress', () => {
  it('drops the administrative tail an Israeli address drags behind it', () => {
    // נפה, מחוז, מיקוד ו"ישראל" הם שש מילים שלא עוזרות לאף אחד להגיע לאירוע
    expect(
      shortAddress('יפו, שוק מחנה יהודה, זכרון משה, ירושלים, נפת ירושלים, מחוז ירושלים, 9422904, ישראל'),
    ).toBe('יפו, שוק מחנה יהודה, ירושלים')
  })

  it('keeps the street and the city when there is nothing between them', () => {
    expect(shortAddress('הרצל 5, תל אביב-יפו, נפת תל אביב, מחוז תל אביב, 6688101, ישראל')).toBe(
      'הרצל 5, תל אביב-יפו',
    )
  })

  it('does not repeat a part that is also the city', () => {
    expect(shortAddress('ירושלים, נפת ירושלים, מחוז ירושלים, ישראל')).toBe('ירושלים')
  })

  it('leaves free text alone — it is not a structured address', () => {
    // מי שהקליד "מחסן ראשי" ביד לא כתב עיר, ואין ממה לקצץ
    expect(shortAddress('מחסן ראשי')).toBe('מחסן ראשי')
  })

  it('gives back the original when every part is noise', () => {
    // עדיף להראות משהו מאשר שורה ריקה במקום המיקום
    expect(shortAddress('מחוז ירושלים, ישראל')).toBe('מחוז ירושלים, ישראל')
  })

  it('handles English results the same way', () => {
    expect(shortAddress('Jaffa Street, Jerusalem, Jerusalem Sub-District, Jerusalem District, Israel')).toBe(
      'Jaffa Street, Jerusalem',
    )
  })

  it('returns nothing for nothing, so the field can hide itself', () => {
    expect(shortAddress(null)).toBe('')
    expect(shortAddress(undefined)).toBe('')
    expect(shortAddress('   ')).toBe('')
  })

  it('honours a caller that wants only one part above the city', () => {
    expect(shortAddress('יפו, שוק מחנה יהודה, זכרון משה, ירושלים, מחוז ירושלים, ישראל', 1)).toBe(
      'יפו, ירושלים',
    )
  })

  it('tolerates stray separators', () => {
    expect(shortAddress('הרצל 5,, תל אביב-יפו, ישראל,')).toBe('הרצל 5, תל אביב-יפו')
  })
})
