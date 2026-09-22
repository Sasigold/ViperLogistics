/**
 * רשימת הריהוט של האירוע — הלוגיקה הטהורה.
 *
 * מאז 0187 יש לרשימה **שני מקורות**, ושניהם נגמרים באותה צורה
 * (`ViperflowSpec`): ‏`viperflow-spec` מושכת אותה חיה מה-API עם תמונות, וכאן
 * יושב גם התרגום של מה ששמור אצלנו (`viperflow_order_items`, 0176) — הנפילה
 * הרכה למקרה שה-API אינו זמין. מסך אחד, שתי דרכים למלא אותו.
 *
 * ארבע ההכרעות שמכתיבות איך נראית הרשימה:
 *
 *   1. **הלוגיסטיקה אינה ריהוט.** ‏`worker` ו-`truck` הן כמות עובדים וכמות
 *      משאיות — הן כבר נכנסו למשימות, לשדה "כמות משאיות" ולמחיר (0177,
 *      0187) — ולחזור עליהן ברשימה היה מבלבל בין מה שמזיזים למה שמזיזים
 *      איתו. הן נאמרות פעם אחת, בתחתית.
 *
 *   2. **בלי בנים** (0187). שורת רכיב היא בחירה *בתוך* האב — "מפה לבנה"
 *      מתחת ל"שולחן עגול" — ובתעודת המשלוח של ViperFlow היא אינה שורה. מה
 *      שנבחר כבר כתוב על האב עצמו (`options`: "צבע: ירוק"), ולכן לא אובד
 *      דבר: מה שנשאר הוא מה שבאמת עולה על המשאית.
 *
 *   3. **אין מחירים.** אין מה לסנן: לטבלה במסד אין עמודת מחיר (0176 §2),
 *      ופונקציית הקצה בונה את תשובתה שדה-שדה בלי שניים מהם.
 *
 *   4. **התמונות אינן נשמרות.** הן כתובות בקטלוג של ViperFlow ונקראות בכל
 *      פתיחה. מה שאינו נשמר גם אינו מתיישן, ואינו תופס נפח.
 */
import type { ViperflowOrderItem, ViperflowSpec, ViperflowSpecLine } from '../../types/domain'

export interface FurnitureSummary {
  /** כמה שורות ריהוט */
  lines: number
  /** סכום הכמויות — "כמה פריטים יוצאים" */
  units: number
  /** כמות עובדים שהוזמנה, אם הוזמנה */
  workers: number | null
  /** כמות משאיות שהוזמנה, אם הוזמנה */
  trucks: number | null
}

/** "מפה: מפה לבנה", או רק הערך כשאין שם קבוצה. */
function optionLabels(options: ViperflowOrderItem['options']): string[] {
  return (Array.isArray(options) ? options : [])
    .map((o) => {
      const value = (o?.value ?? '').trim()
      if (!value) return ''
      const group = (o?.group ?? '').trim()
      return group ? `${group}: ${value}` : value
    })
    .filter((label) => label !== '')
}

/**
 * השורות ששמורות אצלנו, באותה צורה שה-API מחזיר.
 *
 * הסדר נשמר לפי `position` — זה הסדר ש-ViperFlow שלח, והוא הסדר שבו ההזמנה
 * נראית גם אצל הלקוח. ‏`image_url` הוא null תמיד: תמונה אינה נשמרת אצלנו,
 * וזו בדיוק הסיבה שהמסך מעדיף את המקור החי.
 */
export function specLinesFromItems(items: ViperflowOrderItem[]): ViperflowSpecLine[] {
  return [...items]
    .filter((i) => i.line_type === 'product' && !i.is_component)
    .sort((a, b) => a.position - b.position)
    .map((item) => ({
      id: item.id,
      name: item.name,
      quantity: Number(item.quantity) || 0,
      spare_quantity: Number(item.spare_quantity) || 0,
      notes: item.notes,
      is_custom: item.is_custom,
      options: optionLabels(item.options),
      image_url: null,
    }))
}

/** המפרט כפי שאפשר להרכיב אותו ממה ששמור — בלי תמונות, ובלי קריאת רשת. */
export function specFromItems(
  items: ViperflowOrderItem[],
  link?: {
    order_number: string | null
    last_synced_at: string | null
    truck_quantity?: number | null
    worker_quantity?: number | null
  } | null,
): ViperflowSpec {
  return {
    order_number: link?.order_number ?? null,
    last_synced_at: link?.last_synced_at ?? null,
    fetched_at: link?.last_synced_at ?? '',
    truncated: false,
    // ‏0193: שתי הכמויות מגיעות מה-view, שסופר בדיוק את השורות שהמתרגם ספר
    // (רשימת השמות של החיבור). ספירה כאן הייתה סופרת גם פיקוח ו"תוספת",
    // והכיתוב היה סותר את שדה "כמות משאיות" של אותו אירוע.
    workers: link?.worker_quantity ?? null,
    trucks: link?.truck_quantity ?? null,
    lines: specLinesFromItems(items),
  }
}

export function specSummary(spec: ViperflowSpec): FurnitureSummary {
  return {
    lines: spec.lines.length,
    units: spec.lines.reduce((sum, l) => sum + l.quantity, 0),
    workers: spec.workers,
    trucks: spec.trucks,
  }
}

/** "3 שורות · 46 פריטים" — מה שנכתב מתחת לכותרת. */
export function furnitureSummaryText(summary: FurnitureSummary): string {
  const parts = [
    summary.lines === 1 ? 'שורה אחת' : `${summary.lines} שורות`,
    `${summary.units} פריטים`,
  ]
  if (summary.trucks !== null) {
    parts.push(summary.trucks === 1 ? 'משאית אחת' : `${summary.trucks} משאיות`)
  }
  if (summary.workers !== null) {
    parts.push(summary.workers === 1 ? 'עובד אחד' : `${summary.workers} עובדים`)
  }
  return parts.join(' · ')
}
