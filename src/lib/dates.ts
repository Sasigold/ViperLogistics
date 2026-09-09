import { addDays, format, parseISO } from 'date-fns'
import { he } from 'date-fns/locale'

export function fmtDate(d: string | Date | null | undefined): string {
  if (!d) return ''
  const date = typeof d === 'string' ? parseISO(d) : d
  return format(date, 'dd/MM/yyyy', { locale: he })
}

/**
 * שמות ימי השבוע כפי שהם נקראים בעברית, ולא דרך `date-fns`: הלוקאל מחזיר
 * "יום שלישי" בפורמט אחד ו-"יום ג׳" באחר, והצורה המקוצרת שלו משתנה בין
 * גרסאות. לו״ז העבודה מציג את היום מעל התאריך בעמודה צרה, ושם ההבדל בין
 * "יום ג׳" ל-"יום שלישי" הוא ההבדל בין טקסט שנקרא לטקסט שנחתך.
 */
const WEEKDAYS = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת']
const WEEKDAYS_SHORT = ['א׳', 'ב׳', 'ג׳', 'ד׳', 'ה׳', 'ו׳']

const dayIndex = (d: string | Date): number => (typeof d === 'string' ? parseISO(d) : d).getDay()

/** 'יום שלישי' — ושבת היא שבת, בלי "יום" לפניה */
export function fmtWeekday(d: string | Date | null | undefined): string {
  if (!d) return ''
  const i = dayIndex(d)
  if (Number.isNaN(i)) return ''
  return i === 6 ? WEEKDAYS[6] : `יום ${WEEKDAYS[i]}`
}

/** 'יום ג׳' — הצורה שנכנסת לרוחב של עמודת יום בלו״ז */
export function fmtWeekdayShort(d: string | Date | null | undefined): string {
  if (!d) return ''
  const i = dayIndex(d)
  if (Number.isNaN(i)) return ''
  return i === 6 ? WEEKDAYS[6] : `יום ${WEEKDAYS_SHORT[i]}`
}

export function fmtDateLong(d: string | Date | null | undefined): string {
  if (!d) return ''
  const date = typeof d === 'string' ? parseISO(d) : d
  return format(date, 'EEEE, d בMMMM yyyy', { locale: he })
}

/** 'HH:MM[:SS]' -> 'HH:MM' */
export function fmtTime(t: string | null | undefined): string {
  if (!t) return ''
  return t.slice(0, 5)
}

export function toISODate(d: Date): string {
  return format(d, 'yyyy-MM-dd')
}

/** 'אוגוסט 2026' — כותרת חודש בניווט של לו״ז העבודה */
export function fmtMonth(d: Date): string {
  return format(d, 'MMMM yyyy', { locale: he })
}

/** hours as decimal -> 'H:MM' */
export function fmtHours(h: number | null | undefined): string {
  if (h == null) return ''
  const mins = Math.round(h * 60)
  return `${Math.floor(mins / 60)}:${String(mins % 60).padStart(2, '0')}`
}

export function fmtDateTime(d: string | null | undefined): string {
  if (!d) return ''
  return format(parseISO(d), 'dd/MM/yyyy HH:mm', { locale: he })
}

export function fmtMoney(n: number | null | undefined): string {
  if (n == null) return ''
  return new Intl.NumberFormat('he-IL', { style: 'currency', currency: 'ILS', maximumFractionDigits: 0 }).format(n)
}

/**
 * מהמחסן יוצאים לפני שמגיעים לשטח — ולכן שעת מחסן שגדולה משעת השטח היא של
 * הערב שלפני, ולא של הערב שאחרי.
 *
 * זה בדיוק מה ש-`app.warehouse_start_at` עושה בשרת (0163), והעתק שלו כאן
 * הוא במכוון: המסך צריך לומר את היום הנכון בזמן ההקלדה, לפני ששורה נשמרה
 * ולפני שגזירת המשמרת רצה. שני הצדדים חייבים לומר אותו דבר, ולכן הכלל נכתב
 * פעם אחת בכל צד ולא פעם אחת בכל מסך.
 *
 * ‏false כשחסרה אחת מהשתיים: משימה בלי שעת שטח מתחילה בשעת המחסן עצמה, ואין
 * מול מה לסגת.
 */
export function warehouseStartsPreviousDay(
  warehouse: string | null | undefined,
  onsite: string | null | undefined,
): boolean {
  if (!warehouse || !onsite) return false
  return warehouse.slice(0, 5) > onsite.slice(0, 5)
}

/** התאריך שבו ההגעה למחסן נופלת בפועל: יום המשימה, או היום שלפניו */
export function warehouseStartDate(
  taskDate: string,
  warehouse: string | null | undefined,
  onsite: string | null | undefined,
): string {
  return warehouseStartsPreviousDay(warehouse, onsite)
    ? toISODate(addDays(parseISO(taskDate), -1))
    : taskDate
}
