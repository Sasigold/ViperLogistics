import { supabase } from './supabase'
import type { AddressSuggestion } from '../types/domain'

/**
 * Pluggable address-autocomplete provider. To switch to Google Places later,
 * implement AddressProvider and change the export at the bottom — nothing in
 * the UI needs to change.
 */
export interface AddressProvider {
  search(q: string, signal?: AbortSignal): Promise<AddressSuggestion[]>
}

class NominatimProvider implements AddressProvider {
  async search(q: string): Promise<AddressSuggestion[]> {
    if (q.trim().length < 3) return []
    const { data, error } = await supabase.functions.invoke(
      `geocode-proxy?q=${encodeURIComponent(q)}`,
      { method: 'GET' },
    )
    if (error) return []
    return (data as AddressSuggestion[]) ?? []
  }
}

export const addressProvider: AddressProvider = new NominatimProvider()

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
