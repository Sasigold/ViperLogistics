import { describe, expect, it } from 'vitest'
import {
  VEHICLE_DOC_MAX_BYTES,
  daysUntil,
  docState,
  docStoragePath,
  expiryLabel,
  formatBytes,
  formatPlate,
  normalizePlate,
  suggestExpiry,
  validateDocFile,
  vehicleModelLine,
  worstDocState,
} from './vehicles'

const VEHICLE = '40000000-0000-0000-0000-000000000019'
/* יום קבוע, כדי שהחבילה לא תיפול ביום שבו היא רצה. */
const TODAY = new Date(2026, 2, 15)

describe('normalizePlate', () => {
  it('משאיר ספרות בלבד, ולכן שתי כתיבות של אותו רכב מזדהות', () => {
    expect(normalizePlate('12-345-67')).toBe('1234567')
    expect(normalizePlate('1234567')).toBe('1234567')
    expect(normalizePlate(' 12 345 67 ')).toBe('1234567')
    expect(normalizePlate('12·345·67')).toBe('1234567')
  })

  it('ריק ו-null מחזירים מחרוזת ריקה', () => {
    expect(normalizePlate('')).toBe('')
    expect(normalizePlate(null)).toBe('')
    expect(normalizePlate(undefined)).toBe('')
  })

  /* זו ההסכמה עם `regexp_replace(plate_number, '[^0-9]', '', 'g')` שהאינדקס
     הייחודי במסד בנוי עליה. שני הצדדים חייבים לגזור את אותו ערך. */
  it('מתעלם מאותיות, כמו הביטוי שבמסד', () => {
    expect(normalizePlate('L-12-345-67')).toBe('1234567')
  })
})

describe('formatPlate', () => {
  it('שבע ספרות הן 12-345-67', () => {
    expect(formatPlate('1234567')).toBe('12-345-67')
  })

  it('שמונה ספרות הן 123-45-678', () => {
    expect(formatPlate('12345678')).toBe('123-45-678')
  })

  it('אורך אחר מוצג כפי שהוקלד ואינו מעוות', () => {
    expect(formatPlate('AB-123')).toBe('AB-123')
    expect(formatPlate('  נגרר 55  ')).toBe('נגרר 55')
    expect(formatPlate(null)).toBe('')
  })
})

describe('daysUntil', () => {
  it('היום הוא אפס, מחר הוא אחד, אתמול הוא מינוס אחד', () => {
    expect(daysUntil('2026-03-15', TODAY)).toBe(0)
    expect(daysUntil('2026-03-16', TODAY)).toBe(1)
    expect(daysUntil('2026-03-14', TODAY)).toBe(-1)
  })

  /* מעבר שעון קיץ בישראל נופל בסוף מרץ, בתוך הטווח הזה. בלי הנרמול ל-UTC
     החיסור היה מחזיר 30.958 ימים והעיגול היה נשאר 31 — אבל טווח ארוך יותר
     היה מצטבר. הבדיקה קיימת כדי שהנרמול לא יוסר. */
  it('אינו זז במעבר שעון קיץ', () => {
    expect(daysUntil('2026-04-15', TODAY)).toBe(31)
  })

  it('תאריך לא תקין אינו זורק', () => {
    expect(daysUntil('לא תאריך', TODAY)).toBe(0)
  })
})

describe('docState', () => {
  it('בלי תאריך פקיעה אין מצב תוקף', () => {
    expect(docState(null, 30, TODAY)).toBe('no_expiry')
  })

  it('אתמול פג', () => {
    expect(docState('2026-03-14', 30, TODAY)).toBe('expired')
  })

  /* יום הפקיעה עצמו הוא עדיין "פג בקרוב" ולא "פג": הטסט תקף עד סוף היום. */
  it('יום הפקיעה עצמו הוא עדיין בתוקף, ומסומן כפג בקרוב', () => {
    expect(docState('2026-03-15', 30, TODAY)).toBe('expiring')
  })

  it('הסף של הסוג הוא מה שמכריע, ולא מספר קבוע', () => {
    expect(docState('2026-04-10', 30, TODAY)).toBe('expiring') // 26 ימים
    expect(docState('2026-04-10', 14, TODAY)).toBe('valid')
    expect(docState('2026-06-01', 90, TODAY)).toBe('expiring')
  })
})

describe('worstDocState', () => {
  it('פג גובר על הכול', () => {
    expect(worstDocState(['valid', 'expiring', 'expired'])).toBe('expired')
  })

  it('ואחריו פג בקרוב', () => {
    expect(worstDocState(['valid', 'expiring', 'no_expiry'])).toBe('expiring')
  })

  it('רשימה ריקה או מסמכים בלי תוקף אינן אומרות דבר על הרכב', () => {
    expect(worstDocState([])).toBe('no_expiry')
    expect(worstDocState(['no_expiry', 'no_expiry'])).toBe('no_expiry')
  })
})

describe('expiryLabel', () => {
  it('היום, מחר ואתמול נאמרים במילים', () => {
    expect(expiryLabel('2026-03-15', TODAY)).toBe('פג היום')
    expect(expiryLabel('2026-03-16', TODAY)).toBe('פג מחר')
    expect(expiryLabel('2026-03-14', TODAY)).toBe('פג אתמול')
  })

  it('ורחוק יותר נאמר בימים, לשני הכיוונים', () => {
    expect(expiryLabel('2026-03-27', TODAY)).toBe('פג בעוד 12 ימים')
    expect(expiryLabel('2026-03-12', TODAY)).toBe('פג לפני 3 ימים')
  })

  it('בלי תאריך אין מה לומר', () => {
    expect(expiryLabel(null, TODAY)).toBe('ללא תאריך פקיעה')
  })
})

describe('suggestExpiry', () => {
  it('שנה קדימה מיום ההוצאה', () => {
    expect(suggestExpiry('2026-03-15', 12)).toBe('2027-03-15')
  })

  /* 31 בינואר + 12 חודשים הוא 31 בינואר. בלי התיקון setMonth היה גולש
     ל-3 במרץ דרך פברואר הקצר. */
  it('סוף חודש אינו גולש לחודש הבא', () => {
    expect(suggestExpiry('2026-01-31', 1)).toBe('2026-02-28')
    expect(suggestExpiry('2026-01-31', 12)).toBe('2027-01-31')
  })

  it('בלי מספר חודשים או בלי תאריך אין הצעה', () => {
    expect(suggestExpiry('2026-03-15', null)).toBe('')
    expect(suggestExpiry('', 12)).toBe('')
  })
})

describe('validateDocFile', () => {
  it('PDF ותמונה עוברים', () => {
    expect(validateDocFile({ name: 'טסט.pdf', type: 'application/pdf', size: 1000 })).toBeNull()
    expect(validateDocFile({ name: 'a.jpg', type: 'image/jpeg', size: 1000 })).toBeNull()
  })

  it('סיומת מכריעה כשהדפדפן לא זיהה סוג', () => {
    expect(validateDocFile({ name: 'a.heic', type: '', size: 1000 })).toBeNull()
  })

  it('קובץ ריק, גדול מדי או מסוג אחר נדחים', () => {
    expect(validateDocFile({ name: 'a.pdf', type: 'application/pdf', size: 0 })).toBe('הקובץ ריק')
    expect(validateDocFile({ name: 'a.pdf', type: 'application/pdf', size: VEHICLE_DOC_MAX_BYTES + 1 })).toMatch(/25MB/)
    expect(validateDocFile({ name: 'a.docx', type: 'application/msword', size: 1000 })).toMatch(/PDF/)
  })
})

describe('docStoragePath', () => {
  /* התיקייה הראשונה חייבת להיות מזהה הרכב — זה מה שפוליסת ה-Storage קוראת. */
  it('התיקייה היא מזהה הרכב והשם הוא uuid', () => {
    expect(docStoragePath(VEHICLE, 'ביטוח חובה.pdf', 'abc')).toBe(`${VEHICLE}/abc.pdf`)
  })

  it('קובץ בלי סיומת אינו מקבל נקודה תלושה', () => {
    expect(docStoragePath(VEHICLE, 'scan', 'abc')).toBe(`${VEHICLE}/abc`)
  })

  it('סיומת מנוקה מתווים שאינם אלפאנומריים', () => {
    expect(docStoragePath(VEHICLE, 'a.PDF ', 'abc')).toBe(`${VEHICLE}/abc.pdf`)
  })
})

describe('vehicleModelLine', () => {
  it('מחבר מה שיש, בלי רווחים כפולים', () => {
    expect(vehicleModelLine({ make: 'מרצדס', model: 'אקטרוס', model_year: 2019 })).toBe('מרצדס אקטרוס 2019')
    expect(vehicleModelLine({ make: 'מרצדס', model: null, model_year: null })).toBe('מרצדס')
    expect(vehicleModelLine({ make: null, model: null, model_year: null })).toBe('')
  })
})

describe('formatBytes', () => {
  it('מציג את מה שאדם קורא', () => {
    expect(formatBytes(500)).toBe('500 B')
    expect(formatBytes(2048)).toBe('2 KB')
    expect(formatBytes(3 * 1024 * 1024)).toBe('3.0 MB')
    expect(formatBytes(null)).toBe('')
  })
})
