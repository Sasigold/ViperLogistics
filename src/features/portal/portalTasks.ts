/**
 * סיכום המשימות של הקבלן — הלוגיקה שמאחורי הרשימה (0172).
 *
 * שני כללים מחזיקים את הקובץ הזה, ושניהם על אותו ציר:
 *
 * 1. **הכסף מגיע מהשרת, ולא מחושב כאן מחדש.** ‏`contractor_tasks` מחזיר
 *    `null` במחיר למי שאינו רשאי לראות אותו, ו-`null` אינו אפס: משימה בלי
 *    מחיר גלוי אינה משימה ששווה כלום. הסיכום כאן סוכם רק את מה שחזר, וסופר
 *    בנפרד כמה שורות לא נשאו מחיר — כדי שהמסך יוכל לומר "מתוך N משימות,
 *    ל-M אין עדיין תמחור" במקום להציג סכום שנראה שלם.
 * 2. **מה ששולם הוא `paid_amount` ובהיעדרו `price`.** זו אותה הכרעה של
 *    ‏`contractor_dashboard` ושל כרטיס הקבלן: המשרד יכול לשלם סכום אחר
 *    מהצפוי, והשורה זוכרת את שניהם.
 *
 * הפרדה מהמסך אינה קוסמטית: שני הכללים האלה הם מה שאפשר לבדוק בלי React
 * ובלי רשת.
 */
import type { PortalTaskRow } from '../../types/domain'

/** מה שהשורה נקראת: הכותרת שהוקלדה, ובהיעדרה שם סוג המשימה. */
export function taskLabel(row: PortalTaskRow): string {
  return row.title || row.task_type_name
}

/** מה ששולם בפועל על השורה: הסכום שנרשם, ובהיעדרו המחיר. */
export function paidAmountOf(row: PortalTaskRow): number | null {
  if (!row.paid_at) return null
  return row.paid_amount ?? row.price
}

/** סך הקנסות שירדו מהמחיר (0093). ‏0 כשאין פירוט או כשלא היו קנסות. */
export function penaltyOf(row: PortalTaskRow): number {
  return row.price_parts?.penalty_total ?? 0
}

export interface PortalTaskTotals {
  tasks: number
  /** משימות בסטטוס סופי — "בוצעו" */
  completed: number
  /** שורות שחזרו בלי מחיר: אין הרשאה לראות אותו, או שאיש עוד לא תמחר */
  unpriced: number
  expected: number
  paid: number
  unpaid: number
  paidTasks: number
  penalties: number
}

/**
 * הסיכום של השורות **שהוצגו**.
 *
 * הוא אינו מחליף את `contractor_dashboard`: שם הסכום הוא של כל הטווח, וכאן
 * הוא של הרשימה שחזרה — ושתיהן שוות כל עוד הרשימה לא נקטעה בתקרה. המסך
 * מציג את שלו בכרטיסים ואת זה בתחתית הטבלה, ואומר במפורש כשהם נפרדים.
 */
export function summarize(rows: PortalTaskRow[]): PortalTaskTotals {
  let expected = 0
  let paid = 0
  let unpaid = 0
  let unpriced = 0
  let completed = 0
  let paidTasks = 0
  let penalties = 0

  for (const r of rows) {
    if (r.is_terminal) completed += 1
    penalties += penaltyOf(r)
    if (r.price == null) {
      unpriced += 1
    } else {
      expected += r.price
    }
    if (r.paid_at) {
      paidTasks += 1
      paid += paidAmountOf(r) ?? 0
    } else {
      unpaid += r.price ?? 0
    }
  }

  return { tasks: rows.length, completed, unpriced, expected, paid, unpaid, paidTasks, penalties }
}
