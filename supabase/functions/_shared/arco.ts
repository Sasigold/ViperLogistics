// החצי הטהור של אינטגרציית ארקו — בלי שום import של Deno, כדי ש-vitest יוכל
// לכסות אותו (אותו שיקול שכתוב ב-vitest.config.ts על `_shared/viperflow.ts`).
//
// שלושה דברים יושבים כאן: השוואת הסוד המשותף בזמן קבוע, ניקוי מספר ההזמנה
// (אותו כלל בדיוק שה-SQL מיישם ב-`app.arco_order_number` — שני צדדים של אותו
// מפתח חייבים להסכים עליו), ובחירת התוצאה מתוך הצעות הגיאוקודינג.

/** השוואה בזמן קבוע. אורך שונה נענה מיד — האורך אינו סוד. */
export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}

/**
 * מספר ההזמנה, ספרות בלבד.
 *
 * זהה ל-`app.arco_order_number` במסד ולמה שמודול ה-Firestore בתרחיש כבר
 * עושה היום (`replace(order_number; "[^0-9]"; "")`). שלושת המקומות חייבים
 * להסכים: הם המפתח שמחבר הזמנה, מסמך ואירוע.
 */
export function orderNumber(raw: unknown): string | null {
  const digits = String(raw ?? '').replace(/[^0-9]/g, '')
  return digits === '' ? null : digits
}

/** מה שהתרחיש בצד השני רשאי לשלוח. כל שאר המפתחות נזרקים לפני המסד. */
export const EVENT_KEYS = [
  'order_number',
  'customer_name',
  'location',
  'location_notes',
  'order_date',
  'event_status',
  'truck_quantity',
  'volume',
  'supplier_collection',
  'parking',
  'porterage',
  'operational_contact_name',
  'operational_contact_phone',
  'operational_notes',
  'setup_date_and_time',
  'setup_method',
  'setup_crew_size',
  'setup_hours_quantity',
  'setup_execution_contractor',
  'dismantling_date_and_time',
  'dismantling_method',
  'dismantling_crew_size',
  'dismantling_hours_quantity',
  'dismantling_execution_contractor',
  'origami_order_id',
] as const

export const SPEC_KEYS = ['order_number', 'file', 'title', 'origami_order_id'] as const

/**
 * רק המפתחות המוכרים עוברים.
 *
 * לא מטעמי אבטחה — המסד קורא בשם כל שדה ואינו נוגע במה שאינו מכיר — אלא
 * כדי ש-`arco_deliveries.payload` יישאר מה שאפשר לקרוא כשמשהו לא עבד. מעטפה
 * שנושאת חמישים שדות של Origami היא מעטפה שאיש לא יקרא.
 */
export function pick(body: unknown, keys: readonly string[]): Record<string, unknown> {
  const src = (body ?? {}) as Record<string, unknown>
  const out: Record<string, unknown> = {}
  for (const k of keys) {
    if (src[k] !== undefined && src[k] !== null && src[k] !== '') out[k] = src[k]
  }
  return out
}

export interface Suggestion {
  provider: string
  place_id: string
  label: string
  lat: number
  lng: number
}

/**
 * ההצעה שנבחרת מתוך תשובת הגיאוקודר.
 *
 * הראשונה, ובלבד שהיא בתוך גבולות ישראל. ‏`geocode-proxy` כבר מדרג ומגביל
 * למלבן הישראלי, והבדיקה כאן היא חגורה שנייה: פין שנופל בקפריסין ייתן לאירוע
 * אזור תמחור שגוי — כלומר **מחיר שגוי שנשלח ללקוח** — וזה גרוע מאירוע בלי
 * פין, שרק ממתין שהרכז יסמן אותו.
 */
export function pickSuggestion(list: unknown): Suggestion | null {
  if (!Array.isArray(list)) return null
  for (const raw of list) {
    const s = raw as Partial<Suggestion>
    const lat = Number(s?.lat)
    const lng = Number(s?.lng)
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue
    if (lat < 29.4 || lat > 33.45 || lng < 34.2 || lng > 35.95) continue
    return {
      provider: String(s.provider ?? ''),
      place_id: String(s.place_id ?? ''),
      label: String(s.label ?? ''),
      lat,
      lng,
    }
  }
  return null
}

/** הנתיב אחרי שם הפונקציה: '/event' או '/spec'. */
export function routeFromPath(url: string): string {
  const segments = new URL(url).pathname.split('/').filter(Boolean)
  const i = segments.indexOf('arco-intake')
  return i >= 0 && segments.length > i + 1 ? segments[i + 1].toLowerCase() : ''
}
