import { describe, expect, it } from 'vitest'
import { normalizeQuery, rankSuggestions, scoreSuggestion, shortAddress } from './address'
import type { AddressSuggestion } from '../types/domain'

/**
 * הכתובת נשמרת במלואה במסד ומשמשת לחיפוש; מה שנבדק כאן הוא רק מה שהעין רואה.
 * טעות כאן מסתירה מהמשתמש את הרחוב או את העיר שאליהם הוא אמור להגיע.
 */

describe('shortAddress', () => {
  it('drops the administrative tail an Israeli address drags behind it', () => {
    // נפה, מחוז, מיקוד ו"ישראל" הם שש מילים שלא עוזרות לאף אחד להגיע לאירוע,
    // וגם השכונה שבין הרחוב לעיר לא — נשארים הרחוב והעיר
    expect(
      shortAddress('יפו, שוק מחנה יהודה, זכרון משה, ירושלים, נפת ירושלים, מחוז ירושלים, 9422904, ישראל'),
    ).toBe('יפו, ירושלים')
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

  it('honours a caller that wants more than one part above the city', () => {
    expect(shortAddress('יפו, שוק מחנה יהודה, זכרון משה, ירושלים, מחוז ירושלים, ישראל', 2)).toBe(
      'יפו, שוק מחנה יהודה, ירושלים',
    )
  })

  it('tolerates stray separators', () => {
    expect(shortAddress('הרצל 5,, תל אביב-יפו, ישראל,')).toBe('הרצל 5, תל אביב-יפו')
  })
})

/**
 * מי שמקליד מיקום מקליד את מה שהוא קורא לו, לא את מה שרשום ב-OpenStreetMap.
 * מה שנבדק כאן הוא הפער הזה: שאילתה שנשלחת מנורמלת, ותוצאות שמסודרות מול מה
 * שבאמת הוקלד. כישלון כאן פירושו שהמשתמש לא מוצא מקום שקיים.
 */

describe('normalizeQuery', () => {
  it('expands the abbreviations people type and OSM does not carry', () => {
    expect(normalizeQuery('ת״א דיזנגוף 100')).toBe('תל אביב דיזנגוף 100')
    expect(normalizeQuery('ראשל"צ')).toBe('ראשון לציון')
  })

  it('drops the street prefix that is not part of any street name', () => {
    expect(normalizeQuery("רח' הרצל 5, ירושלים")).toBe('הרצל 5, ירושלים')
  })

  it('strips niqqud and collapses whitespace', () => {
    expect(normalizeQuery('יְרוּשָׁלַיִם')).toBe('ירושלים')
    expect(normalizeQuery('  אש    התורה ')).toBe('אש התורה')
  })

  it('leaves a word that happens to name an Object property alone', () => {
    // חיפוש המילים האלה אינו שכיח, אבל טבלת קיצורים על אובייקט רגיל הייתה
    // מחזירה כאן פונקציה ומזריקה אותה לשאילתה
    expect(normalizeQuery('constructor')).toBe('constructor')
    expect(normalizeQuery('toString')).toBe('toString')
  })

  it('keeps free text as it is', () => {
    expect(normalizeQuery('מחסן ראשי')).toBe('מחסן ראשי')
  })
})

const YESHIVA =
  'ישיבת אש התורה, כיכר בתי מחסה, הרובע היהודי, העיר העתיקה, ירושלים, נפת ירושלים, מחוז ירושלים, 9114001, ישראל'
const SDEROT_STREET = 'התורה, נאות הנשיא, אזור תעשייה, שדרות, נפת אשקלון, מחוז הדרום, 8720178, ישראל'

describe('scoreSuggestion', () => {
  it('gives a full score when every typed word is in the specific part', () => {
    expect(scoreSuggestion('אש התורה', YESHIVA)).toBeGreaterThanOrEqual(1)
  })

  it('scores a name that starts with what was typed above one that merely contains it', () => {
    expect(scoreSuggestion('ישיבת אש', YESHIVA)).toBeGreaterThan(scoreSuggestion('אש התורה', YESHIVA))
  })

  it('counts a word matched only in the administrative tail for less', () => {
    // "אש" נתפס כאן רק בגלל "אשקלון" שבנפה — זו אינה אותה תוצאה
    expect(scoreSuggestion('אש התורה', SDEROT_STREET)).toBeLessThan(scoreSuggestion('אש התורה', YESHIVA))
  })

  it('ignores the definite article, since people type it either way', () => {
    expect(scoreSuggestion('אש תורה', YESHIVA)).toBe(scoreSuggestion('אש התורה', YESHIVA))
  })

  it('is zero when the result has nothing to do with the query', () => {
    expect(scoreSuggestion('קניון מלחה', 'הרצל 5, בת ים, ישראל')).toBe(0)
  })
})

function suggestion(over: Partial<AddressSuggestion>): AddressSuggestion {
  return { provider: 'photon', place_id: 'W1', label: YESHIVA, lat: 31.7746, lng: 35.2324, ...over }
}

describe('rankSuggestions', () => {
  it('puts the place the user meant first, whatever order the providers returned', () => {
    const ranked = rankSuggestions('אש התורה', [
      suggestion({ place_id: 'W439159162', label: SDEROT_STREET, lat: 31.5257, lng: 34.588 }),
      suggestion({ place_id: 'W290725352' }),
    ])
    expect(ranked[0].place_id).toBe('W290725352')
  })

  it('shows the same place once when both providers return it', () => {
    const ranked = rankSuggestions('אש התורה', [
      suggestion({ provider: 'photon', place_id: 'W290725352' }),
      suggestion({ provider: 'nominatim', place_id: 'nominatim:123', lat: 31.77461, lng: 35.23242 }),
    ])
    expect(ranked).toHaveLength(1)
    expect(ranked[0].provider).toBe('photon')
  })

  it('keeps the provider order between results that match equally well', () => {
    const first = suggestion({ place_id: 'W1', label: 'היכל שלמה, המלך גורג, ירושלים, ישראל', lat: 31.77, lng: 35.21 })
    const second = suggestion({ place_id: 'W2', label: 'היכל שלמה, הים, חיפה, ישראל', lat: 32.8, lng: 34.98 })
    expect(rankSuggestions('היכל שלמה', [first, second]).map((s) => s.place_id)).toEqual(['W1', 'W2'])
  })

  it('caps the list so the popover stays readable', () => {
    const many = Array.from({ length: 20 }, (_, i) =>
      suggestion({ place_id: `W${i}`, lat: 31.7 + i / 1000, lng: 35.2 + i / 1000 }),
    )
    expect(rankSuggestions('אש התורה', many)).toHaveLength(8)
  })
})
