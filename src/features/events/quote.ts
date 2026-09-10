/**
 * הצעת מחיר ללקוח הקצה — הלוגיקה הטהורה (0169).
 *
 * המסמך פונה אל **הלקוח של הלקוח**: קיסר מביאה את האירוע, ומי שקורא את
 * ההצעה ומשלם עליה הוא בעל השמחה. לכן "לכבוד" נבנה מ-`end_client_name`
 * ומ-`event_contacts`, ולא מאנשי הקשר של הלקוח שבמערכת.
 *
 * הקובץ הזה אינו יודע דבר על PDF, על Supabase ועל React. הוא ממיר את מה
 * שדף האירוע כבר החזיק — משימות, תוספות מחיר, פרטי החברה — למודל שורות
 * וסכומים, וזה מה שנבדק ב-`quote.test.ts`. הציור יושב ב-`quotePdf.ts`.
 */
import type { CompanyDetails, EventPriceAddon, WorkBoardRow } from '../../types/domain'

/** שורה במסמך: משימה, או תוספת מחיר שיושבת עליה. */
export interface QuoteLine {
  /** מזהה יציב לסימון במסך. משימה = מזהה המשימה; תוספת = מזהה התוספת */
  id: string
  kind: 'task' | 'addon'
  label: string
  /** "12/09/2026 · 08:00", או תאריך בלבד כשאין שעה */
  whenText: string
  amount: number
}

export interface QuoteTotals {
  subtotal: number
  vatAmount: number
  total: number
}

export const COMPANY_SETTINGS_KEY = 'company.details'

/** נקרא כשאין עדיין שורה בהגדרות — כדי שהמסך לא יתרסק על מסד ריק. */
export const EMPTY_COMPANY: CompanyDetails = {
  name: '',
  tax_id: '',
  phone: '',
  email: '',
  logo_path: null,
  vat_pct: 18,
  quote_footer: 'מסמך זה נוצר ע״י וייפר מערכות',
}

function two(n: number): string {
  return n < 10 ? `0${n}` : String(n)
}

/**
 * תאריך ושעה של משימה, כפי שהם מודפסים.
 *
 * התאריך מגיע כ-`YYYY-MM-DD` והשעה כ-`HH:MM:SS`; שניהם נחתכים ידנית ולא
 * דרך `Date`, כי `new Date('2026-09-12')` הוא UTC והדפסה באזור זמן שלילי
 * הייתה מזיזה את התאריך יום אחורה. אותו נימוק שכתוב ב-`lib/dates.ts`.
 */
export function taskWhenText(taskDate: string | null, startTime: string | null): string {
  if (!taskDate) return ''
  const [y, m, d] = taskDate.split('-')
  if (!y || !m || !d) return ''
  const date = `${two(Number(d))}/${two(Number(m))}/${y}`
  const time = startTime ? startTime.slice(0, 5) : ''
  return time ? `${date} · ${time}` : date
}

/**
 * השורות של המסמך, בסדר שבו הן מודפסות.
 *
 * הסדר הוא בדיוק הסדר של כרטיס התמחור בדף האירוע: משימה, ומתחתיה תוספות
 * המחיר שלה. "שעתיים המתנה בשער" היא משפט על ההקמה, ומי שקורא את השורה
 * שלה צריך לראות אותו שם ולא בגוש נפרד בסוף — זו כל הסיבה ש-0113 דרשה
 * הערה על כל תוספת. תוספת שהמשימה שלה אינה ברשימה אינה נעלמת: היא נספרת
 * ומקבלת שורה בסוף.
 *
 * משימה בלי מחיר נכנסת כ-0 ולא נשמטת. המסך מציג סימון לכל שורה, והשמטה
 * שקטה של שורה שהמפיק מצפה לראות גרועה משורה שהוא מוריד בעצמו.
 */
export function buildQuoteLines(tasks: WorkBoardRow[], addons: EventPriceAddon[]): QuoteLine[] {
  const lines: QuoteLine[] = []
  const seen = new Set<string>()

  for (const t of tasks) {
    seen.add(t.id)
    lines.push({
      id: t.id,
      kind: 'task',
      label: t.title || t.task_type_name,
      whenText: taskWhenText(t.task_date, t.onsite_start_time),
      amount: Number(t.customer_price ?? 0),
    })
    for (const a of addons.filter((x) => x.task_id === t.id)) {
      lines.push({ id: a.id, kind: 'addon', label: a.note, whenText: '', amount: Number(a.amount) })
    }
  }

  for (const a of addons.filter((x) => !seen.has(x.task_id))) {
    lines.push({
      id: a.id,
      kind: 'addon',
      label: a.task_label ? `${a.task_label} — ${a.note}` : a.note,
      whenText: '',
      amount: Number(a.amount),
    })
  }

  return lines
}

/** עיגול לאגורות. ‏`toFixed` על מספר צף מחזיר מחרוזת; כאן נדרש מספר. */
function agorot(n: number): number {
  return Math.round(n * 100) / 100
}

/**
 * סכום ביניים, מע״מ וסה״כ.
 *
 * ‏`task_pricing.price` הוא מספר אחד לפני מע״מ — מנוע התמחור אינו יודע על
 * מע״מ דבר — ולכן המסמך הוא המקום היחיד שבו הוא מחושב. האחוז מגיע
 * מההגדרות ולא מקבוע בקוד: שיעור מע״מ הוא החלטה של המדינה, ושינוי שלו
 * אינו אמור לדרוש פריסה.
 */
export function quoteTotals(lines: QuoteLine[], vatPct: number): QuoteTotals {
  const subtotal = agorot(lines.reduce((sum, l) => sum + Number(l.amount || 0), 0))
  const vatAmount = agorot(subtotal * (Number(vatPct) || 0) / 100)
  return { subtotal, vatAmount, total: agorot(subtotal + vatAmount) }
}

/**
 * המשפט הקבוע של ההצעה.
 *
 * שם הלקוח מגיע כפרמטר ואינו כתוב כאן. זה אינו קישוט: הכלל החוזר ביותר
 * ברפו הוא "הדגל ולא השם" (0120, 0143, 0145), ומחרוזת "קיסר" בקוד הייתה
 * הופכת את הלקוח הבא שיקבל הצעות מחיר לשורת קוד במקום לשורה במסד.
 */
export function quoteFixedNote(documentNumber: string, customerName: string, sentOn: Date): string {
  const date = `${two(sentOn.getDate())}/${two(sentOn.getMonth() + 1)}/${sentOn.getFullYear()}`
  return `הצעת המחיר מתייחסת למפרט מס׳ ${documentNumber} כפי שנמסר ע״י חברת ${customerName} ונכון לתאריך ${date}`
}

/** "מסמך זה נוצר ע״י … בתאריך … בשעה …" */
export function quoteFooterText(footer: string, at: Date): string {
  const date = `${two(at.getDate())}/${two(at.getMonth() + 1)}/${at.getFullYear()}`
  const time = `${two(at.getHours())}:${two(at.getMinutes())}`
  return `${footer} בתאריך ${date} בשעה ${time}`
}

/**
 * מספר ישראלי בפורמט שוואטסאפ מבין: ‏972 ואז המספר בלי האפס המוביל.
 *
 * מחזיר null על כל מה שאינו מספר ישראלי תקין, ואז המסך מוריד את הנסיגה
 * ל-`wa.me` ומשאיר את השיתוף. ‏`wa.me` עם מספר שגוי פותח שיחה עם אדם אחר,
 * וזה גרוע מלא לפתוח שיחה בכלל.
 */
export function toWhatsAppNumber(phone: string | null | undefined): string | null {
  if (!phone) return null
  const digits = phone.replace(/[^\d+]/g, '')
  let local: string
  if (digits.startsWith('+972')) local = digits.slice(4)
  else if (digits.startsWith('972')) local = digits.slice(3)
  else if (digits.startsWith('00972')) local = digits.slice(5)
  else if (digits.startsWith('0')) local = digits.slice(1)
  else return null

  local = local.replace(/\D/g, '')
  // קווי (‎02–04, 08, 09) הוא שמונה ספרות אחרי האפס; סלולרי (‎05x) ומספרים
  // ארציים (‎07x) הם תשע. קידומת 1 היא שירות ואינה מקבלת וואטסאפ, וכל דבר
  // אחר אינו מספר טלפון ישראלי.
  if (!/^[2-9]\d{7,8}$/.test(local)) return null
  return `972${local}`
}

/** ההודעה שנפתחת בוואטסאפ לצד הקובץ. */
export function quoteWhatsAppText(documentNumber: string, companyName: string): string {
  return `שלום, מצורפת הצעת מחיר מס׳ ${documentNumber} מאת ${companyName}.`
}

/** שם הקובץ כפי שהלקוח יראה אותו. */
export function quoteFileName(documentNumber: string): string {
  return `הצעת מחיר ${documentNumber}.pdf`.replace(/[\\/:*?"<>|]/g, '-')
}

/** הנתיב בדלי. התיקייה הראשונה היא החוזה שהפוליסה קוראת (0169). */
export function quoteStoragePath(eventId: string, uuid: string): string {
  return `${eventId}/${uuid}.pdf`
}
