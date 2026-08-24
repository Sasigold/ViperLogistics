import { supabase } from './supabase'
import type { AddressSuggestion } from '../types/domain'

/**
 * Pluggable address-autocomplete provider. The actual switch to Google Places
 * happened server-side (in the `geocode-proxy` edge function, keyed by a
 * secret); this seam stays for the next swap — implement AddressProvider and
 * change the export at the bottom, nothing in the UI needs to change.
 */
export interface AddressProvider {
  search(q: string, signal?: AbortSignal): Promise<AddressSuggestion[]>
}

/** מאיזה אורך מתחילים לחפש. שם מקום בעברית יכול להיות קצר ("יד ושם"). */
export const MIN_QUERY_CHARS = 2

/* ===== סלחנות בהקלדה ====================================================
   מי שמקליד מקום לא מקליד את מה שרשום ב-OpenStreetMap. הוא כותב "אש התורה"
   כשהשם המלא הוא "ישיבת אש התורה", מקצר "ת״א", מוסיף "רח'" לפני שם הרחוב
   ומדביק לפעמים טקסט מנוקד. שלושה דברים סוגרים את הפער: נרמול של מה שנשלח
   לספק (כאן), חיפוש עמיד לשמות חלקיים (Photon, בפונקציית הקצה), ודירוג של מה
   שחזר מול מה שבאמת הוקלד (בהמשך הקובץ). */

const NIQQUD = /[\u0591-\u05C7]/g
const DOUBLE_QUOTES = /[\u05F4\u201C\u201D]/g
const SINGLE_QUOTES = /[\u05F3\u2018\u2019`]/g

/**
 * קיצורים שנפוצים בהקלדה ואינם קיימים כשם ב-OSM. ההחלפה היא לפי מילה שלמה,
 * לא לפי תת-מחרוזת: `\b` ב-JavaScript מבוסס על [A-Za-z0-9_] ולכן חסר משמעות
 * בין אותיות עבריות. ערך ריק פירושו "השמט את המילה".
 */
const ALIASES = new Map<string, string>([
  ['ת"א', 'תל אביב'],
  ['ב"ש', 'באר שבע'],
  ['פ"ת', 'פתח תקווה'],
  ['ר"ג', 'רמת גן'],
  ['ב"ב', 'בני ברק'],
  ['כ"ס', 'כפר סבא'],
  ['ראשל"צ', 'ראשון לציון'],
  ['י"ם', 'ירושלים'],
  ['י-ם', 'ירושלים'],
  ["רח'", ''],
  ['רחוב', ''],
  ["שד'", 'שדרות'],
])

/**
 * מנרמל את מה שהוקלד לפני שהוא נשלח לספק — ניקוד, גרשיים טיפוגרפיים, קיצורים
 * ומילות קישור מיותרות. הטקסט שהמשתמש רואה בשדה אינו משתנה; זו שאילתה בלבד.
 */
export function normalizeQuery(raw: string): string {
  const unified = (raw ?? '')
    .replace(NIQQUD, '')
    .replace(DOUBLE_QUOTES, '"')
    .replace(SINGLE_QUOTES, "'")

  const out: string[] = []
  for (const token of unified.split(/\s+/)) {
    if (!token) continue
    const alias = ALIASES.get(token)
    if (alias === undefined) out.push(token)
    else if (alias) out.push(alias)
  }
  return out.join(' ').replace(/^[,;\s]+|[,;\s]+$/g, '')
}

/** משטח טקסט להשוואה: בלי ניקוד, בלי פיסוק, אותיות קטנות, רווח יחיד. */
function fold(s: string): string {
  return s
    .replace(NIQQUD, '')
    .toLowerCase()
    .replace(/["'`.,;:()[\]{}/\\|–—_-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
}

function words(s: string): string[] {
  return fold(s).split(' ').filter(Boolean)
}

/** "התורה" ו"תורה" הן אותה מילה לצורך התאמה; ה"א הידיעה אינה הבדל אמיתי. */
function bare(t: string): string {
  return t.length > 3 && t.startsWith('ה') ? t.slice(1) : t
}

/** התאמה סלחנית: תחילית לכל כיוון, עם או בלי ה"א הידיעה. */
function tokenMatches(q: string, t: string): boolean {
  if (t.startsWith(q)) return true
  if (t.length >= 2 && q.startsWith(t)) return true
  const bq = bare(q)
  const bt = bare(t)
  return bt.startsWith(bq) || (bt.length >= 2 && bq.startsWith(bt))
}

/**
 * עד כמה ההצעה עונה על מה שהוקלד.
 *
 * 0 — אף מילה שהוקלדה אינה מופיעה בכתובת.
 * 1 — כל מילה שהוקלדה מופיעה בחלק הספציפי של הכתובת (השם והרחוב), ולא רק
 *     בזנב המנהלי שבו "ירושלים" מופיעה גם בשלוש רמות מעל.
 * עד 1.15 — תוספת כשהשם עצמו מתחיל בדיוק במה שהוקלד.
 *
 * זה נחוץ מפני שהתוצאות מגיעות משני ספקים בשתי שיטות דירוג שונות, ומה שחוזר
 * ראשון אינו בהכרח מה שהמשתמש חיפש.
 */
export function scoreSuggestion(query: string, label: string): number {
  const qs = words(query)
  if (qs.length === 0) return 0

  const parts = (label ?? '')
    .split(',')
    .map((p) => fold(p))
    .filter(Boolean)
  // שתי החוליות הראשונות הן השם והרחוב — שם ההתאמה שווה כפליים
  const head = parts.slice(0, 2).flatMap((p) => p.split(' ')).filter(Boolean)
  const tail = parts.slice(2).flatMap((p) => p.split(' ')).filter(Boolean)

  let hits = 0
  for (const q of qs) {
    if (head.some((t) => tokenMatches(q, t))) hits += 2
    else if (tail.some((t) => tokenMatches(q, t))) hits += 1
  }

  const base = hits / (2 * qs.length)
  const prefix = parts[0]?.startsWith(fold(query)) ? 0.15 : 0
  return base + prefix
}

/**
 * אותו מקום מגיע משני ספקים עם מזהים שונים לגמרי. מעבר למזהה ה-OSM שפונקציית
 * הקצה כבר מאחדת לפיו, שתי הצעות באותן קואורדינטות (עד כ-11 מ') ובאותו שם הן
 * אותה שורה מבחינת מי שקורא את הרשימה.
 */
function sameSpotKey(s: AddressSuggestion): string {
  return `${s.lat.toFixed(4)},${s.lng.toFixed(4)}|${fold(s.label.split(',')[0] ?? '')}`
}

/** מסיר כפילויות ומסדר לפי קרבה למה שהוקלד. הסדר המקורי מכריע בתיקו. */
export function rankSuggestions(
  query: string,
  items: AddressSuggestion[],
  limit = 8,
): AddressSuggestion[] {
  const seen = new Set<string>()
  const unique = items.filter((s) => {
    const keys = [s.place_id, sameSpotKey(s)]
    if (keys.some((k) => seen.has(k))) return false
    for (const k of keys) seen.add(k)
    return true
  })

  return unique
    .map((s, i) => ({ s, i, score: scoreSuggestion(query, s.label) }))
    .sort((a, b) => b.score - a.score || a.i - b.i)
    .slice(0, limit)
    .map((x) => x.s)
}

/**
 * `rankSuggestions` נולד כדי למזג שני ספקי OSM עם שיטות דירוג שאינן מסכימות זו
 * עם זו. Google מגיע כבר מדורג — קוהרנטי וסלחני לשגיאות כתיב — וניקוד לפי
 * תחיליות רק יקלקל אותו: שם שהוקלד עם שגיאת כתיב מקבל אפס מול כל תווית.
 * רשימה מעורבת לא קיימת — פונקציית הקצה מחזירה או Google בלבד או OSM בלבד.
 */
export function orderSuggestions(query: string, items: AddressSuggestion[]): AddressSuggestion[] {
  if (items.length > 0 && items.every((s) => s.provider === 'google')) return items.slice(0, 8)
  return rankSuggestions(query, items)
}

/**
 * הספק בפועל: פונקציית הקצה `geocode-proxy`. כשמפתח Google מוגדר שם, החיפוש הוא
 * Google Places (שמות עסקים, אולמות, סלחנות לשגיאות כתיב); אחרת — Photon (חיפוש
 * סלחני לשמות) ו-Nominatim (כתובת מדויקת). הסידור הסופי נעשה כאן, מול הטקסט
 * שהוקלד.
 */
class ProxyProvider implements AddressProvider {
  async search(q: string): Promise<AddressSuggestion[]> {
    const query = normalizeQuery(q)
    if (query.length < MIN_QUERY_CHARS) return []
    const { data, error } = await supabase.functions.invoke(
      `geocode-proxy?q=${encodeURIComponent(query)}`,
      { method: 'GET' },
    )
    if (error) return []
    return orderSuggestions(query, (data as AddressSuggestion[]) ?? [])
  }
}

export const addressProvider: AddressProvider = new ProxyProvider()

/**
 * מה שנשמר ב-`location_text` הוא ה-display_name המלא של הספק — שרשרת של כל רמות
 * המנהל עד המדינה: "יפו, שוק מחנה יהודה, זכרון משה, ירושלים, נפת ירושלים, מחוז
 * ירושלים, 9422904, ישראל". הרמות העליונות לא אומרות כלום למי שקורא את המסך, אבל
 * הן תופסות שתי שורות בכל מקום שבו מיקום מוצג.
 *
 * הקיצור הוא בתצוגה בלבד. הערך המלא נשאר במסד — הוא מזין את `search_tsv`, את
 * פילטרי ה-ilike ואת ההעתקה ללוח — ולכן אסור לקצר בזמן כתיבה.
 */
const NOISE = [
  /^ישראל$/,
  /^israel$/i,
  /^[\d\s-]+$/, // מיקוד
  /^מחוז\s/,
  /^נפת\s/,
  /sub-?district/i,
  /\bdistrict\b/i,
]

/**
 * @param keep כמה חלקים מהתחילת הכתובת לשמור מעל שם העיר.
 * @returns הכתובת המקוצרת, או '' כשאין מה להציג.
 */
export function shortAddress(text: string | null | undefined, keep = 1): string {
  const raw = (text ?? '').trim()
  if (!raw) return ''

  const parts = raw
    .split(',')
    .map((p) => p.trim())
    .filter(Boolean)
  // טקסט חופשי שמישהו הקליד ("מחסן ראשי") אינו כתובת מובנית ואין ממה לקצץ
  if (parts.length < 2) return raw

  const kept = parts.filter((p) => !NOISE.some((re) => re.test(p)))
  // כתובת שכולה רעש — עדיף להראות את המקור מאשר כלום
  if (kept.length === 0) return raw

  const city = kept[kept.length - 1]
  const head = kept.slice(0, -1).slice(0, keep)
  return [...new Set([...head, city])].join(', ')
}
