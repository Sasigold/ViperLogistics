/**
 * רשימת הריהוט של האירוע — הלוגיקה הטהורה. השורות מגיעות מ-`viperflow_order_items` (0176).
 *
 * מה שמגיע מ-`viperflow_order_items` הוא שורות ההזמנה של ViperFlow כפי שהן:
 * שורות אב, הרכיבים שלהן מיד אחריהן, ושתי שורות לוגיסטיקה שכל הזמנה נושאת
 * (עובדים ומשאית) גם כשהכמות בהן אפס. מה שצריך להופיע במסך הוא **הריהוט**,
 * ולכן כאן יושבות שלוש ההכרעות שהופכות את האחד לשני:
 *
 *   1. **הלוגיסטיקה אינה ריהוט.** ‏`worker` ו-`truck` הן כמות עובדים וכמות
 *      משאיות — הן כבר נכנסו למשימות ולשדה "כמות משאיות" של האירוע (0177),
 *      ולחזור עליהן ברשימה היה מבלבל בין מה שמזיזים למה שמזיזים איתו.
 *   2. **רכיב יושב מתחת לאב שלו ואינו שורה בפני עצמו.** ‏"שולחן עגול 1.8"
 *      עם "מפה לבנה" הוא פריט אחד שיש לו בחירה, ולא שני פריטים. השטלוח של
 *      הסדר ש-ViperFlow שולח כבר שומר על זה — אב, ומיד אחריו הרכיבים שלו —
 *      ואנחנו רק מקפלים אותו בחזרה.
 *   3. **אין מחירים.** אין מה לסנן: לטבלה במסד אין עמודת מחיר (0176 §2).
 *      הקובץ הזה אינו מסתיר כסף — פשוט לא הגיע כסף.
 */
import type { ViperflowOrderItem } from '../../types/domain'

/** שורות שאינן ריהוט אך כן אומרות משהו: כמה עובדים, כמה משאיות. */
export const LOGISTICS_LINE_TYPES = ['worker', 'truck'] as const

export interface FurnitureLine {
  id: string
  name: string
  quantity: number
  spareQuantity: number
  isCustom: boolean
  notes: string | null
  /** הבחירות של הפריט עצמו, כטקסט מוכן לתצוגה: "מפה: מפה לבנה" */
  options: string[]
  /** הרכיבים שנכנסים איתו — שם וכמות בלבד */
  components: { id: string; name: string; quantity: number; options: string[] }[]
}

export interface FurnitureSummary {
  /** כמה שורות ריהוט (אב בלבד) */
  lines: number
  /** סכום הכמויות של שורות האב — "כמה פריטים יוצאים" */
  units: number
  /** כמות עובדים שהוזמנה, אם הוזמנה */
  workers: number | null
  /** כמות משאיות שהוזמנה, אם הוזמנה */
  trucks: number | null
}

/** "מפה: מפה לבנה", או רק הערך כשאין שם קבוצה (רכיב אופציונלי). */
function optionLabels(item: ViperflowOrderItem): string[] {
  const options = Array.isArray(item.options) ? item.options : []
  return options
    .map((o) => {
      const value = (o?.value ?? '').trim()
      if (!value) return ''
      const group = (o?.group ?? '').trim()
      return group ? `${group}: ${value}` : value
    })
    .filter((label) => label !== '')
}

/**
 * מקפל את השורות לרשימה שאפשר לקרוא במחסן.
 *
 * הסדר נשמר לפי `position` — זה הסדר ש-ViperFlow שלח, והוא הסדר שבו ההזמנה
 * נראית גם אצל הלקוח. רכיב שאיבד את האב שלו (הזמנה שנערכה באמצע סנכרון)
 * אינו נזרק אלא מוצג כשורה משל עצמו: פריט שנעלם מהרשימה גרוע מפריט שמופיע
 * בשורה הלא נכונה.
 */
export function furnitureLines(items: ViperflowOrderItem[]): FurnitureLine[] {
  const products = [...items]
    .filter((i) => i.line_type === 'product')
    .sort((a, b) => a.position - b.position)

  const parents = products.filter((i) => !i.is_component)
  const byExternalId = new Map<string, FurnitureLine>()
  const lines: FurnitureLine[] = parents.map((item) => {
    const line: FurnitureLine = {
      id: item.id,
      name: item.name,
      quantity: Number(item.quantity) || 0,
      spareQuantity: Number(item.spare_quantity) || 0,
      isCustom: item.is_custom,
      notes: item.notes,
      options: optionLabels(item),
      components: [],
    }
    if (item.external_item_id) byExternalId.set(item.external_item_id, line)
    return line
  })

  for (const item of products) {
    if (!item.is_component) continue
    const parent = item.parent_external_item_id
      ? byExternalId.get(item.parent_external_item_id)
      : undefined
    if (parent) {
      parent.components.push({
        id: item.id,
        name: item.name,
        quantity: Number(item.quantity) || 0,
        options: optionLabels(item),
      })
    } else {
      lines.push({
        id: item.id,
        name: item.name,
        quantity: Number(item.quantity) || 0,
        spareQuantity: Number(item.spare_quantity) || 0,
        isCustom: item.is_custom,
        notes: item.notes,
        options: optionLabels(item),
        components: [],
      })
    }
  }

  return lines
}

/** הכמות שהוזמנה מסוג שורה לוגיסטי, או null כשלא הוזמנה (אפס אינו הזמנה). */
export function logisticsQuantity(
  items: ViperflowOrderItem[],
  lineType: (typeof LOGISTICS_LINE_TYPES)[number],
): number | null {
  const total = items
    .filter((i) => i.line_type === lineType && !i.is_component)
    .reduce((sum, i) => sum + (Number(i.quantity) || 0), 0)
  return total > 0 ? total : null
}

export function furnitureSummary(items: ViperflowOrderItem[]): FurnitureSummary {
  const lines = furnitureLines(items)
  return {
    lines: lines.length,
    units: lines.reduce((sum, l) => sum + l.quantity, 0),
    workers: logisticsQuantity(items, 'worker'),
    trucks: logisticsQuantity(items, 'truck'),
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
