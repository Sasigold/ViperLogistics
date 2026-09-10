import {
  addDays,
  addMonths,
  differenceInCalendarDays,
  endOfMonth,
  isSameMonth,
  startOfMonth,
  startOfWeek,
  subDays,
} from 'date-fns'
import { toISODate } from '../../lib/dates'

export interface DateRange {
  from: string
  to: string
}

/**
 * The same span, immediately before the selected one.
 *
 * This is what every "vs. previous period" delta on the dashboard compares
 * against, and it needs no new server surface — the same RPC is simply asked
 * about a different window. The two ranges never touch: a month ending on the
 * 31st is preceded by the window ending on the 30th of the month before.
 */
export function previousRange({ from, to }: DateRange): DateRange {
  const span = Math.max(0, differenceInCalendarDays(new Date(to), new Date(from)))
  const prevTo = subDays(new Date(from), 1)
  return { from: toISODate(subDays(prevTo, span)), to: toISODate(prevTo) }
}

/** the three shortcuts above the date fields */
export const RANGE_PRESETS: { label: string; range: () => DateRange }[] = [
  {
    label: 'השבוע',
    range: () => {
      const s = startOfWeek(new Date(), { weekStartsOn: 0 })
      return { from: toISODate(s), to: toISODate(addDays(s, 6)) }
    },
  },
  {
    label: 'החודש',
    range: () => ({ from: toISODate(startOfMonth(new Date())), to: toISODate(endOfMonth(new Date())) }),
  },
  {
    label: '30 ימים',
    range: () => ({ from: toISODate(subDays(new Date(), 29)), to: toISODate(new Date()) }),
  },
]

export function defaultRange(): DateRange {
  return { from: toISODate(startOfMonth(new Date())), to: toISODate(endOfMonth(new Date())) }
}

/** החודש שלם, מה-1 ועד האחרון בו. */
export function monthRange(d: Date): DateRange {
  return { from: toISODate(startOfMonth(d)), to: toISODate(endOfMonth(d)) }
}

/**
 * החודש שלפני הטווח שנבחר, או שאחריו.
 *
 * הדשבורד נפתח על החודש הנוכחי ונשאר עליו — ולמי שאין לו `dashboard.change_range`
 * (הלקוח, מ-0144) לא הייתה שום דרך לשאול על החודש שעבר. שני חיצים הם התשובה
 * הצרה לזה: תנועה בין חודשים אינה בורר טווח חופשי, והחלון שהיא מייצרת הוא
 * תמיד חודש שלם.
 *
 * **העוגן הוא `from`, והתוצאה היא תמיד חודש שלם.** טווח מותאם שנלחץ עליו חץ
 * נצמד לחודש שהתחיל בו — זו הכרעה ולא תופעת לוואי: כפתור שנקרא "חודש קודם"
 * חייב להנחית על חודש, אחרת "קודם" מודד ממשהו שאיש לא רואה. מי שבחר טווח
 * חופשי ורוצה אותו חזרה מקבל אותו בשני שדות התאריך שלצד החיצים.
 *
 * ‏`from` ולא `to`: טווח שנכתב הפוך (שני השדות בלתי תלויים) עדיין נמדד
 * מהתחלה שלו, ולכן הצעד אינו קופץ בו לכיוון ההפוך.
 */
export function stepMonth(range: DateRange, delta: number): DateRange {
  return monthRange(addMonths(startOfMonth(new Date(range.from)), delta))
}

/** האם הטווח הוא בדיוק חודש קלנדרי — מה שהופך את שם החודש לכותרת נכונה. */
export function isWholeMonth({ from, to }: DateRange): boolean {
  const start = new Date(from)
  return (
    isSameMonth(start, new Date(to)) &&
    from === toISODate(startOfMonth(start)) &&
    to === toISODate(endOfMonth(start))
  )
}
