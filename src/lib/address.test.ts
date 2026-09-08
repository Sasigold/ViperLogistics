import { describe, expect, it } from 'vitest'
import {
  formatCoords,
  normalizeQuery,
  orderSuggestions,
  parseCoords,
  rankSuggestions,
  scoreSuggestion,
  shortAddress,
} from './address'
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

  it('shortens a Google-style label the same way — venue name and city survive', () => {
    // Google מחזיר "שם, כתובת מלאה, ישראל"; מה שהעין צריכה הוא השם והעיר
    expect(shortAddress('אולמי הגן הקסום, הרצל 5, ראשון לציון, ישראל')).toBe('אולמי הגן הקסום, ראשון לציון')
    expect(shortAddress('שדרות רוטשילד 1, תל אביב-יפו, ישראל')).toBe('שדרות רוטשילד 1, תל אביב-יפו')
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

/**
 * Google מדרג בעצמו, כולל סלחנות לשגיאות כתיב שהניקוד המקומי עיוור להן. לכן
 * תוצאות Google נשארות בסדר שהגיעו; דירוג מקומי נשמר רק לנתיב הנסיגה של OSM,
 * שבו שני ספקים עם דירוגים שונים מתמזגים לרשימה אחת.
 */
describe('orderSuggestions', () => {
  const google = (over: Partial<AddressSuggestion>): AddressSuggestion =>
    suggestion({ provider: 'google', ...over })

  it('keeps the server order for Google results, even when local scoring disagrees', () => {
    // מי שהקליד עם שגיאת כתיב מקבל מ-Google את המקום הנכון ראשון, אבל הניקוד
    // המקומי היה נותן לו אפס והופך את הסדר
    const first = google({ place_id: 'g1', label: 'אולמי הגן הקסום, הרצל 5, ראשון לציון, ישראל' })
    const second = google({ place_id: 'g2', label: 'הגן הכסום, יפו, ישראל' })
    expect(orderSuggestions('הגן הכסום', [first, second]).map((s) => s.place_id)).toEqual(['g1', 'g2'])
  })

  it('caps Google results like the ranked list', () => {
    const many = Array.from({ length: 12 }, (_, i) => google({ place_id: `g${i}` }))
    expect(orderSuggestions('אולם', many)).toHaveLength(8)
  })

  it('still ranks OSM results against what was typed', () => {
    const ordered = orderSuggestions('אש התורה', [
      suggestion({ place_id: 'W439159162', label: SDEROT_STREET, lat: 31.5257, lng: 34.588 }),
      suggestion({ place_id: 'W290725352' }),
    ])
    expect(ordered[0].place_id).toBe('W290725352')
  })

  it('returns nothing for nothing', () => {
    expect(orderSuggestions('אולם', [])).toEqual([])
  })
})

/**
 * מיקום שהחיפוש אינו מוצא נשמר כטקסט חופשי, ואז הקואורדינטות הן הדבר היחיד
 * שאובד — ובלעדיהן `app.zone_for_point` (0017) אינו יודע לאיזה אזור האירוע
 * נופל. השדה מקבל את מה שמדביקים מגוגל מפות, ולכן מה שנבדק כאן הוא בדיוק
 * הצורות שמגיעות משם — ומה שאסור לו להישמר כאילו הוא נקודה.
 */
describe('parseCoords', () => {
  it('reads the pair Google Maps puts on the clipboard', () => {
    expect(parseCoords('32.0853, 34.7818')).toEqual({ lat: 32.0853, lng: 34.7818 })
  })

  it('takes a space instead of a comma', () => {
    expect(parseCoords('32.0853 34.7818')).toEqual({ lat: 32.0853, lng: 34.7818 })
  })

  it('reads negatives, and a whole number is a number', () => {
    expect(parseCoords('-33.9, 18')).toEqual({ lat: -33.9, lng: 18 })
  })

  it('drops the @ a map URL drags in front of the pair', () => {
    expect(parseCoords('@31.7683,35.2137')).toEqual({ lat: 31.7683, lng: 35.2137 })
  })

  it('is null for a half-typed pair, so a keystroke never erases the saved point', () => {
    expect(parseCoords('32.0')).toBeNull()
    expect(parseCoords('32.0853,')).toBeNull()
  })

  it('is null for free text — an address is not a point', () => {
    expect(parseCoords('הרצל 5, תל אביב')).toBeNull()
    expect(parseCoords('')).toBeNull()
    expect(parseCoords(null)).toBeNull()
  })

  it('rejects a pair that cannot be a place on earth', () => {
    // 91 מעלות רוחב אינו קיים; זו הקלדה שגויה ולא נקודה
    expect(parseCoords('91, 34.78')).toBeNull()
    expect(parseCoords('32.08, 181')).toBeNull()
  })

  it('round-trips through the formatter that seeds the field', () => {
    expect(parseCoords(formatCoords(32.0853, 34.7818))).toEqual({ lat: 32.0853, lng: 34.7818 })
    expect(formatCoords(null, 34.7818)).toBe('')
    expect(formatCoords(32.0853, null)).toBe('')
  })
})
