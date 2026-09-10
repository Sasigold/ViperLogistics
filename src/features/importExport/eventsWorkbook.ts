/**
 * הפורמט של קובץ האקסל של האירועים — בלי ExcelJS ובלי DOM.
 *
 * הקובץ הוא שני גיליונות: "אירועים" ו"משימות". גיליון המשימות מקושר לגיליון
 * האירועים דרך עמודת "מזהה שורה" (row_key) — מזהה חופשי שחי רק בתוך הקובץ
 * ואינו נשמר במסד. זו הדרך היחידה לתאר יותר ממשימה אחת לאירוע בלי לכפול את
 * שורת האירוע, ובלי להמציא מפתח טבעי (מספר אירוע אינו חובה, ושם לקוח אינו
 * ייחודי).
 *
 * שתי החלטות שחשוב לא לשבור:
 *
 * 1. **המיפוי הוא לפי טקסט הכותרת, לא לפי מיקום.** הגרסה הקודמת קראה את
 *    התאים לפי סדר קבוע, ולכן כל עמודה חדשה הייתה שוברת קבצים שכבר בידי
 *    המשתמשים. ההתאמה כאן היא מול הכותרת העברית *וגם* מול המפתח האנגלי, עם
 *    נפילה חזרה למיפוי מיקומי כשאף כותרת לא זוהתה — כך קובץ ישן בן גיליון
 *    אחד נקלט בדיוק כמו קודם.
 * 2. **בניית הגיליונות מופרדת מהכתיבה שלהם**, כמו ב-exportAttendance ו-
 *    exportDashboard, כדי שהחוזה יהיה ניתן לבדיקה בלי ExcelJS.
 */
import type { FormField } from '../../types/domain'

export interface SheetColumn {
  key: string
  header: string
  width: number
  /** נרמול הערך בקריאה. בעמודות הקבועות הוא נגזר מהמפתח, ובשדה מותאם — מהטיפוס */
  coerce?: CoerceKind
}

/**
 * טיפוסי הנרמול בקריאה.
 *
 * 'number' ו-'bool' נוספו יחד עם עמודות הכסף והתוספות, ושניהם קיימים מאותה
 * סיבה: התא נכתב בידי אדם, והשרת מקבל טקסט שהוא מיד יצטרך להמיר. '1,200 ₪'
 * ו'כן' הם ערכים לגיטימיים לגמרי בעיני מי שממלא את הקובץ, ובלי הנרמול כאן הם
 * חוזרים אליו כ-'invalid input syntax for type numeric'.
 */
export type CoerceKind = 'date' | 'time' | 'number' | 'bool'

export const EVENTS_SHEET = 'אירועים'
export const TASKS_SHEET = 'משימות'
export const GUIDE_SHEET = 'הסבר'

export const EVENT_COLUMNS: SheetColumn[] = [
  { key: 'row_key', header: 'מזהה שורה', width: 12 },
  { key: 'customer_name', header: 'שם לקוח במערכת', width: 20 },
  { key: 'end_client_name', header: 'שם לקוח האירוע', width: 20 },
  { key: 'event_number', header: 'מספר אירוע', width: 14 },
  { key: 'event_date', header: 'תאריך אירוע (YYYY-MM-DD)', width: 22 },
  { key: 'location_text', header: 'מיקום', width: 26 },
  { key: 'location_notes', header: 'הערות למיקום', width: 20 },
  { key: 'volume_m', header: 'נפח במטר', width: 12 },
  { key: 'truck_count', header: 'כמות משאיות', width: 13 },
  { key: 'no_parking', header: 'ללא חניה (כן/לא)', width: 16 },
  { key: 'porterage', header: 'סבלות (כן/לא)', width: 15 },
  { key: 'supplier_pickup', header: 'איסוף מספק (כן/לא)', width: 19 },
  { key: 'suppliers', header: 'ספקים (מופרדים בפסיק)', width: 26 },
  { key: 'contact_name', header: 'איש קשר', width: 18 },
  { key: 'contact_phone', header: 'טלפון איש קשר', width: 16 },
  { key: 'notes', header: 'הערות', width: 30 },
]

export const TASK_COLUMNS: SheetColumn[] = [
  { key: 'row_key', header: 'מזהה שורה (של האירוע)', width: 20 },
  { key: 'task_type', header: 'סוג משימה', width: 16 },
  { key: 'title', header: 'כותרת', width: 22 },
  { key: 'task_date', header: 'תאריך משימה (YYYY-MM-DD)', width: 22 },
  { key: 'warehouse_start_time', header: 'יציאה מהמחסן (HH:MM)', width: 20 },
  { key: 'onsite_start_time', header: 'תחילה בשטח (HH:MM)', width: 20 },
  { key: 'hours_count', header: 'כמות שעות', width: 12 },
  { key: 'worker_count', header: 'כמות עובדים', width: 13 },
  { key: 'execution_method', header: 'אופן ביצוע', width: 18 },
  { key: 'warehouse', header: 'מחסן יציאה', width: 18 },
  { key: 'truck_free_text', header: 'משאית', width: 16 },
  { key: 'location_text', header: 'מיקום המשימה', width: 26 },
  { key: 'travel_hours', header: 'זמן נסיעה בכיוון אחד (שעות)', width: 26 },
  { key: 'requires_team_lead', header: 'נדרש ראש צוות (כן/לא)', width: 21 },
  { key: 'price', header: 'מחיר ללקוח (₪)', width: 16 },
  { key: 'contractor', header: 'קבלן', width: 18 },
  { key: 'contractor_price', header: 'מחיר לקבלן (₪)', width: 16 },
  { key: 'notes', header: 'הערות', width: 30 },
]

/**
 * עמודות גיליון האירועים כולל שדות מותאמים אישית.
 *
 * הכותרת של שדה מותאם היא שמו, אבל שם אינו ייחודי: שני לקוחות יכולים להגדיר
 * "מספר הזמנה", ואפילו להתנגש בכותרת קבועה כמו "הערות". כותרת כפולה שוברת את
 * מיפוי הכותרות בייבוא, ולכן התנגשות מקבלת סיומת — שם הלקוח, ואם גם הוא חוזר,
 * מפתח השדה שהוא ייחודי מעצם הגדרתו.
 */
export function eventColumns(custom: FormField[], customerNames?: Map<string, string>): SheetColumn[] {
  const used = new Set(EVENT_COLUMNS.map((c) => c.header))
  const out = [...EVENT_COLUMNS]
  for (const f of custom) {
    let header = f.label_he
    if (used.has(header)) {
      const name = f.customer_id ? customerNames?.get(f.customer_id) : undefined
      header = name ? `${f.label_he} (${name})` : `${f.label_he} [${f.field_key}]`
    }
    if (used.has(header)) header = `${f.label_he} [${f.field_key}]`
    used.add(header)
    out.push({
      key: f.field_key,
      header,
      width: 18,
      coerce: CUSTOM_COERCE[f.field_type],
    })
  }
  return out
}

/**
 * נרמול של שדה מותאם נגזר מהטיפוס שלו.
 *
 * 'checkbox' הוא המקרה שהיה שבור עד כה: app.event_custom_patch ממירה את הערך
 * ב-`::boolean`, בעוד הייצוא כותב 'כן'/'לא' (formatCustomValue) — כלומר ייצוא
 * וייבוא חזרה של קובץ עם תיבת סימון נפלו על "ערך לא תקין בשדה". הנרמול ל-bool
 * סוגר את המעגל.
 */
const CUSTOM_COERCE: Record<string, CoerceKind | undefined> = {
  date: 'date',
  time: 'time',
  number: 'number',
  checkbox: 'bool',
}

/** עמודות הייצוא הישן, בלי מזהה השורה — קובץ שיצא כך חייב להמשיך להיקלט. */
const legacyColumns = (columns: SheetColumn[]) => columns.filter((c) => c.key !== 'row_key')

const DATE_KEYS = new Set(['event_date', 'task_date'])
const TIME_KEYS = new Set(['onsite_start_time', 'warehouse_start_time'])
const NUMBER_KEYS = new Set([
  'volume_m', 'truck_count', 'hours_count', 'worker_count',
  'travel_hours', 'price', 'contractor_price',
])
const BOOL_KEYS = new Set(['no_parking', 'porterage', 'supplier_pickup', 'requires_team_lead'])

/* מה שנקרא בתא כ"כן" וכ"לא". הייצוא וקובץ הדוגמה כותבים 'כן'/'לא' כי זה מה
   שאדם קורא, והשרת מקבל true/false — התרגום הוא כאן, בשכבה שמכירה את פורמט
   הקובץ. ‏'v' ו-'✓' נכנסו כי זה מה שאנשים מסמנים בעמודת כן/לא באקסל. */
const TRUE_CELLS = new Set(['כן', 'true', 't', 'yes', 'y', '1', 'v', '✓'])
const FALSE_CELLS = new Set(['לא', 'false', 'f', 'no', 'n', '0', '-'])

export type SheetRow = Record<string, string>
/** גיליון אחרי נרמול התאים: שורה 0 היא הכותרות. */
export type Matrix = string[][]

export interface SheetPlan {
  name: string
  columns: SheetColumn[]
  rows: SheetRow[]
  /** שורות טקסט חופשי שנכתבות מעל הטבלה */
  intro?: string[]
}

export interface ImportTaskPayload {
  [key: string]: string | undefined
  task_type: string
  title?: string
  task_date?: string
  warehouse_start_time?: string
  onsite_start_time?: string
  hours_count?: string
  worker_count?: string
  execution_method?: string
  warehouse?: string
  truck_free_text?: string
  location_text?: string
  travel_hours?: string
  requires_team_lead?: string
  price?: string
  contractor?: string
  contractor_price?: string
  notes?: string
}

export interface ImportEventPayload {
  customer_id: string
  tasks: ImportTaskPayload[]
  [key: string]: string | ImportTaskPayload[] | undefined
}

const pad2 = (n: number) => String(n).padStart(2, '0')

/**
 * תא של ExcelJS למחרוזת.
 *
 * ExcelJS מחזיר Date לכל תא שעוצב כתאריך *או* כשעה. תא שעה נשען על בסיס
 * התאריכים של אקסל (1899-12-30), ולכן שנה שקטנה מ-1900 היא הסימן שמדובר בשעה
 * ולא בתאריך. הכול נקרא ב-UTC: ExcelJS מפרש כך, וקריאה מקומית הייתה מזיזה
 * תאריך ביום שלם למי שיושב ממערב לגריניץ׳.
 */
export function normalizeCell(v: unknown): string {
  if (v == null) return ''
  if (v instanceof Date) {
    const hm = `${pad2(v.getUTCHours())}:${pad2(v.getUTCMinutes())}`
    if (v.getUTCFullYear() < 1900) return hm
    const ymd = `${v.getUTCFullYear()}-${pad2(v.getUTCMonth() + 1)}-${pad2(v.getUTCDate())}`
    return hm === '00:00' ? ymd : `${ymd} ${hm}`
  }
  if (typeof v === 'object') {
    const o = v as Record<string, unknown>
    if ('text' in o) return normalizeCell(o.text)
    if ('result' in o) return normalizeCell(o.result)
    if (Array.isArray(o.richText)) {
      return (o.richText as { text?: string }[]).map((p) => p.text ?? '').join('')
    }
    if ('hyperlink' in o) return String(o.hyperlink ?? '')
    return ''
  }
  return String(v).trim()
}

/** נרמול ערך לפי העמודה שאליה הוא שייך — תאריך, שעה, מספר, כן/לא, או טקסט. */
export function coerceValue(key: string, raw: string, kind?: CoerceKind): string {
  const s = raw.trim()
  if (!s) return ''
  if (kind === 'date' || (!kind && DATE_KEYS.has(key))) {
    const iso = s.match(/(\d{4})-(\d{1,2})-(\d{1,2})/)
    if (iso) return `${iso[1]}-${pad2(+iso[2])}-${pad2(+iso[3])}`
    const dmy = s.match(/^(\d{1,2})[./](\d{1,2})[./](\d{4})/)
    if (dmy) return `${dmy[3]}-${pad2(+dmy[2])}-${pad2(+dmy[1])}`
    return s
  }
  if (kind === 'time' || (!kind && TIME_KEYS.has(key))) {
    const t = s.match(/(\d{1,2}):(\d{2})/)
    return t ? `${pad2(+t[1])}:${t[2]}` : s
  }
  if (kind === 'number' || (!kind && NUMBER_KEYS.has(key))) {
    /* '1,200 ₪' ו-'₪1200.50' הם מה שיוצא מתא שעוצב כמטבע. מה שאינו מספר אחרי
       הניקוי חוזר כפי שהוא — השרת הוא שיאמר על *איזו* משימה מדובר. */
    const n = s.replace(/[₪$€,\s\u200e\u200f]/g, '')
    return /^-?\d+(\.\d+)?$/.test(n) ? n : s
  }
  if (kind === 'bool' || (!kind && BOOL_KEYS.has(key))) {
    const v = s.toLowerCase()
    if (TRUE_CELLS.has(v)) return 'true'
    if (FALSE_CELLS.has(v)) return 'false'
    return s
  }
  return s
}

const headerKey = (s: string) => s.trim().toLowerCase().replace(/\s+/g, ' ')

/**
 * שורת כותרות → מפתח לכל עמודה. `null` לעמודה שלא זוהתה.
 * מוחזר `null` לכל השורה כשאף כותרת לא זוהתה — אז הקורא נופל למיפוי מיקומי.
 */
export function mapHeaderRow(cells: string[], columns: SheetColumn[]): (string | null)[] | null {
  const byHeader = new Map<string, string>()
  for (const c of columns) {
    byHeader.set(headerKey(c.header), c.key)
    byHeader.set(headerKey(c.key), c.key)
    // "תאריך אירוע (YYYY-MM-DD)" נכתב לא פעם בלי ההערה שבסוגריים
    byHeader.set(headerKey(c.header.replace(/\s*\(.*\)\s*$/, '')), c.key)
  }
  const mapped = cells.map((c) => byHeader.get(headerKey(c)) ?? null)
  return mapped.some((m) => m !== null) ? mapped : null
}

/** מטריצת תאים מנורמלים → שורות לפי מפתח. שורה ריקה לגמרי מושמטת. */
export function parseSheet(matrix: Matrix, columns: SheetColumn[]): SheetRow[] {
  if (matrix.length < 2) return []
  const mapped = mapHeaderRow(matrix[0] ?? [], columns)
  const keys = mapped ?? columns.map((c) => c.key)
  const coerceOf = new Map(columns.filter((c) => c.coerce).map((c) => [c.key, c.coerce]))
  const out: SheetRow[] = []
  for (const cells of matrix.slice(1)) {
    const row: SheetRow = {}
    let any = false
    keys.forEach((key, i) => {
      if (!key) return
      const v = coerceValue(key, cells[i] ?? '', coerceOf.get(key))
      row[key] = v
      if (v !== '') any = true
    })
    if (any) out.push(row)
  }
  return out
}

/** גיליון אירועים, כולל נפילה לחוזה הישן שאין בו עמודת מזהה שורה. */
export function parseEventSheet(matrix: Matrix, columns: SheetColumn[] = EVENT_COLUMNS): SheetRow[] {
  const mapped = mapHeaderRow(matrix[0] ?? [], columns)
  return parseSheet(matrix, mapped ? columns : legacyColumns(columns))
}

export interface GroupedTasks {
  tasksByKey: Map<string, SheetRow[]>
  errors: string[]
}

/**
 * קישור שורות המשימות לשורות האירועים.
 *
 * כשגיליון האירועים מכיל שורה אחת בלבד, משימה בלי מזהה שורה משויכת אליה —
 * זה המקרה הנפוץ של "אירוע אחד עם כמה משימות", והדרישה למלא מזהה שם היא
 * טקס ריק. בכל מצב אחר מזהה חסר או לא מוכר הוא שגיאה, כי ניחוש כאן יוצר
 * משימות במקום הלא נכון.
 */
export function groupTasks(events: SheetRow[], tasks: SheetRow[]): GroupedTasks {
  const errors: string[] = []
  const tasksByKey = new Map<string, SheetRow[]>()
  const seen = new Set<string>()
  const dupes = new Set<string>()

  for (const e of events) {
    const k = (e.row_key ?? '').trim()
    if (!k) continue
    if (seen.has(k)) dupes.add(k)
    seen.add(k)
  }
  for (const k of dupes) errors.push(`מזהה שורה כפול בגיליון האירועים: ${k}`)

  const soleKey = events.length === 1 ? (events[0].row_key ?? '').trim() : null

  for (const t of tasks) {
    const raw = (t.row_key ?? '').trim()
    let k: string
    if (raw) {
      if (!seen.has(raw)) {
        errors.push(`משימה מפנה למזהה שורה שאינו קיים בגיליון האירועים: ${raw}`)
        continue
      }
      k = raw
    } else if (soleKey !== null) {
      k = soleKey
    } else {
      errors.push(`שורת משימה "${t.task_type || '—'}" בלי מזהה שורה`)
      continue
    }
    if (!t.task_type?.trim()) {
      errors.push(`שורת משימה במזהה ${k || '—'} בלי סוג משימה`)
      continue
    }
    const list = tasksByKey.get(k)
    if (list) list.push(t)
    else tasksByKey.set(k, [t])
  }

  return { tasksByKey, errors }
}

const TASK_PAYLOAD_KEYS = TASK_COLUMNS.map((c) => c.key).filter((k) => k !== 'row_key')
const EVENT_PAYLOAD_KEYS = EVENT_COLUMNS.map((c) => c.key).filter(
  (k) => k !== 'row_key' && k !== 'customer_name',
)

export interface BuiltPayload {
  payloads: ImportEventPayload[]
  /** שמות לקוח שהופיעו בקובץ ואין להם התאמה במערכת */
  unknownCustomers: string[]
  /** כמה משימות נכנסו ל-payloads — לתצוגה לפני השליחה */
  taskCount: number
}

/**
 * שורות הקובץ → מערך ה-payloads ל-bulk_import_events.
 * שם הלקוח נפתר כאן ולא בשרת, כי הרשימה כבר בזיכרון הדפדפן וההודעה על שם
 * שגוי צריכה להיאמר לפני שנשלחת שורה אחת.
 */
export function buildImportPayload(
  events: SheetRow[],
  tasksByKey: Map<string, SheetRow[]>,
  customers: { id: string; name: string }[],
  customFields: FormField[] = [],
): BuiltPayload {
  const byName = new Map(customers.map((c) => [c.name.trim().toLowerCase(), c.id]))
  /* שדה מותאם שייך ללקוח אחד. שורה של לקוח אחר עשויה לשאת ערך באותה עמודה —
     קובץ אחד מכיל כמה לקוחות — והוא נשמט, כי ה-RPC ממילא היה מתעלם ממנו. */
  const customByCustomer = new Map<string, string[]>()
  for (const f of customFields) {
    if (!f.customer_id) continue
    const list = customByCustomer.get(f.customer_id)
    if (list) list.push(f.field_key)
    else customByCustomer.set(f.customer_id, [f.field_key])
  }
  const unknown = new Set<string>()
  const payloads: ImportEventPayload[] = []
  let taskCount = 0

  for (const e of events) {
    const name = (e.customer_name ?? '').trim()
    const id = byName.get(name.toLowerCase())
    if (!id) {
      unknown.add(name || '(ריק)')
      continue
    }
    const tasks: ImportTaskPayload[] = (tasksByKey.get((e.row_key ?? '').trim()) ?? []).map((t) => {
      const task: ImportTaskPayload = { task_type: t.task_type.trim() }
      for (const k of TASK_PAYLOAD_KEYS) {
        const v = (t[k] ?? '').trim()
        if (v) task[k] = v
      }
      return task
    })
    taskCount += tasks.length

    const payload: ImportEventPayload = { customer_id: id, tasks }
    for (const k of EVENT_PAYLOAD_KEYS) {
      const v = (e[k] ?? '').trim()
      if (v) payload[k] = v
    }
    for (const k of customByCustomer.get(id) ?? []) {
      const v = (e[k] ?? '').trim()
      if (v) payload[k] = v
    }
    payloads.push(payload)
  }

  return { payloads, unknownCustomers: [...unknown], taskCount }
}

// ===== תבנית וקובץ דוגמה ====================================================

const emptySheet = (name: string, columns: SheetColumn[]): SheetPlan => ({ name, columns, rows: [] })

/** התבנית הריקה: כותרות בלבד, בשני הגיליונות. */
export function buildTemplatePlan(eventCols: SheetColumn[] = EVENT_COLUMNS): SheetPlan[] {
  return [emptySheet(EVENTS_SHEET, eventCols), emptySheet(TASKS_SHEET, TASK_COLUMNS)]
}


export interface SampleRefs {
  customers: string[]
  taskTypes: string[]
  executionMethods: string[]
  contractors?: string[]
  warehouses?: string[]
  /** הספק שייך ללקוח, ולכן הוא מוצג — וגם נבחר לשורת הדוגמה — יחד איתו */
  suppliers?: { customer: string; name: string }[]
  /**
   * מה שמותר למי שמוריד את הקובץ.
   *
   * שלוש עמודות בגיליון המשימות דורשות מפתח משלהן בשרת (pricing.edit,
   * tasks.delegate, contractors.edit_pricing). העמודות עצמן נשארות בקובץ תמיד
   * — הוא עשוי לעבור לעמית שכן מחזיק את המפתח — אבל *הערכים* בשורות הדוגמה
   * יורדים למי שאין לו, כדי שהקובץ שהוא הוריד ייקלט כפי שהוא ולא ייפול על
   * "אין לך הרשאה" בשורה הראשונה.
   */
  allow?: { price?: boolean; contractor?: boolean; contractorPrice?: boolean }
}

/** תאריך קבוע ולא "היום": קובץ דוגמה שמשתנה בכל הורדה קשה להסביר ולבדוק. */
const SAMPLE_DATE = '2026-03-15'
const SAMPLE_DATE_2 = '2026-03-16'

/**
 * קובץ הדוגמה: שני אירועים עם משימות, ועוד גיליון "הסבר" עם הערכים החוקיים
 * שנשלפו מהמערכת בזמן ההורדה.
 *
 * כלל אחד עובר על כל שורות הדוגמה: **תא מלא הוא תא שהייבוא יקבל**. לכן עמודת
 * "אופן ביצוע" נשארת ריקה — הערכים המותרים תלויים בלקוח ובסוג המשימה, וערך
 * שנראה תקין בקובץ אבל נפסל בייבוא מבלבל יותר משהוא מסביר — ולכן גם קבלן,
 * מחסן וספק נכתבים רק כשהמערכת החזירה שם אמיתי, ומחיר לקבלן רק כשיש קבלן.
 * הרשימות המלאות נמצאות בגיליון ההסבר.
 */
export function buildSamplePlan(refs: SampleRefs, eventCols: SheetColumn[] = EVENT_COLUMNS): SheetPlan[] {
  const customer = refs.customers[0] ?? 'שם הלקוח כפי שהוא מופיע במערכת'
  const customer2 = refs.customers[1] ?? customer
  const extraType =
    refs.taskTypes.find((t) => t !== 'הקמה' && t !== 'פירוק') ?? 'סידור'
  const allow = refs.allow ?? {}
  const warehouse = refs.warehouses?.[0] ?? ''
  const contractor = allow.contractor === false ? '' : (refs.contractors?.[0] ?? '')
  const contractorPrice = contractor && allow.contractorPrice !== false ? '900' : ''
  const price = (v: string) => (allow.price === false ? '' : v)
  const supplierOf = (name: string) =>
    refs.suppliers?.find((s) => s.customer === name)?.name ?? ''

  const events: SheetRow[] = [
    {
      row_key: '1',
      customer_name: customer,
      end_client_name: 'חתונה — משפחת לוי',
      event_number: '2026-101',
      event_date: SAMPLE_DATE,
      location_text: 'אולמי הגן, רחוב הרצל 12, ראשון לציון',
      location_notes: 'כניסת פריקה מהחניון האחורי',
      volume_m: '18',
      truck_count: '2',
      no_parking: 'כן',
      porterage: 'כן',
      supplier_pickup: 'לא',
      suppliers: supplierOf(customer),
      contact_name: 'דנה לוי',
      contact_phone: '050-1234567',
      notes: 'שורת דוגמה — אפשר למחוק אותה ולכתוב במקומה נתונים אמיתיים',
    },
    {
      row_key: '2',
      customer_name: customer2,
      end_client_name: 'כנס שנתי — חברת אלפא',
      event_number: '2026-102',
      event_date: SAMPLE_DATE_2,
      location_text: 'מרכז הכנסים, שדרות רוטשילד 45, תל אביב',
      location_notes: '',
      volume_m: '32',
      truck_count: '3',
      no_parking: 'לא',
      porterage: 'לא',
      supplier_pickup: 'כן',
      suppliers: supplierOf(customer2),
      contact_name: 'אורי כהן',
      contact_phone: '052-7654321',
      notes: '',
    },
  ]

  const tasks: SheetRow[] = [
    {
      row_key: '1',
      task_type: 'הקמה',
      title: '',
      task_date: SAMPLE_DATE,
      warehouse_start_time: '06:00',
      onsite_start_time: '08:00',
      hours_count: '4',
      worker_count: '5',
      execution_method: '',
      warehouse,
      truck_free_text: '',
      location_text: '',
      travel_hours: '1',
      requires_team_lead: 'כן',
      price: price('2400'),
      contractor: '',
      contractor_price: '',
      notes: 'הקמה ופירוק כבר נוצרות לכל אירוע — השורה כאן ממלאת אותן',
    },
    {
      row_key: '1',
      task_type: 'פירוק',
      title: '',
      task_date: SAMPLE_DATE,
      warehouse_start_time: '',
      onsite_start_time: '23:00',
      hours_count: '2',
      worker_count: '3',
      execution_method: '',
      warehouse: '',
      truck_free_text: '',
      location_text: '',
      travel_hours: '',
      requires_team_lead: 'לא',
      price: price('1100'),
      contractor: '',
      contractor_price: '',
      notes: '',
    },
    {
      row_key: '1',
      task_type: extraType,
      title: `${extraType} לפני האורחים`,
      task_date: SAMPLE_DATE,
      warehouse_start_time: '',
      onsite_start_time: '16:00',
      hours_count: '1.5',
      worker_count: '2',
      execution_method: '',
      warehouse: '',
      truck_free_text: '',
      location_text: '',
      travel_hours: '',
      requires_team_lead: '',
      price: price('600'),
      contractor,
      contractor_price: contractorPrice,
      notes: contractor
        ? 'משימה נוספת שהואצלה לקבלן — "מחיר לקבלן" הוא מה שמשלמים לו'
        : 'משימה נוספת — נוצרת מעבר להקמה ולפירוק',
    },
    {
      row_key: '2',
      task_type: 'הקמה',
      title: '',
      task_date: SAMPLE_DATE_2,
      warehouse_start_time: '05:30',
      onsite_start_time: '07:30',
      hours_count: '6',
      worker_count: '8',
      execution_method: '',
      warehouse,
      truck_free_text: 'רכב מלווה',
      location_text: '',
      travel_hours: '',
      requires_team_lead: '',
      price: price('5200'),
      contractor: '',
      contractor_price: '',
      notes: '',
    },
    {
      row_key: '2',
      task_type: 'פירוק',
      title: '',
      task_date: SAMPLE_DATE_2,
      warehouse_start_time: '',
      onsite_start_time: '21:00',
      hours_count: '3',
      worker_count: '6',
      execution_method: '',
      warehouse: '',
      truck_free_text: '',
      location_text: '',
      travel_hours: '',
      requires_team_lead: '',
      price: price('2600'),
      contractor: '',
      contractor_price: '',
      notes: '',
    },
  ]

  const guideRows: SheetRow[] = [
    ...refs.taskTypes.map((v) => ({ kind: 'סוג משימה', value: v })),
    ...refs.executionMethods.map((v) => ({ kind: 'אופן ביצוע', value: v })),
    ...refs.customers.map((v) => ({ kind: 'שם לקוח במערכת', value: v })),
    ...(refs.warehouses ?? []).map((v) => ({ kind: 'מחסן יציאה', value: v })),
    ...(refs.contractors ?? []).map((v) => ({ kind: 'קבלן', value: v })),
    ...(refs.suppliers ?? []).map((s) => ({ kind: `ספק של ${s.customer}`, value: s.name })),
  ]

  const guide: SheetPlan = {
    name: GUIDE_SHEET,
    intro: [
      'איך ממלאים את הקובץ',
      '',
      '1. בגיליון "אירועים" — שורה אחת לכל אירוע. עמודת "מזהה שורה" היא מספר או טקסט חופשי שאתם בוחרים; הוא משמש רק לקישור בתוך הקובץ ואינו נשמר במערכת.',
      '2. בגיליון "משימות" — שורה אחת לכל משימה, ובעמודת "מזהה שורה" רושמים את המזהה של האירוע שאליו היא שייכת. אפשר כמה שורות לאותו מזהה.',
      '3. "שם לקוח במערכת" חייב להיות זהה לשם הלקוח כפי שהוא רשום במערכת (הרשימה למטה). כך גם "סוג משימה", "אופן ביצוע", "מחסן יציאה", "קבלן" ו"ספקים".',
      '4. תאריכים בפורמט YYYY-MM-DD, שעות בפורמט HH:MM. תאריך משימה ריק יילקח מתאריך האירוע.',
      '5. עמודות כן/לא — התוספות של האירוע ו"נדרש ראש צוות" — מקבלות "כן" או "לא". תא ריק אינו "לא" אלא "לא נכתב", והמערכת תשאיר את ברירת המחדל.',
      '6. עמודת "ספקים" מקבלת שמות ספקים מופרדים בפסיק. הספק חייב להיות מוגדר אצל אותו לקוח — ספק של לקוח אחר ייפסל.',
      '7. עמודות הכסף: "מחיר ללקוח" הוא מה שגובים, ו"מחיר לקבלן" הוא מה שמשלמים לקבלן שהמשימה הואצלה אליו. מספרים בלבד (₪, פסיקים ורווחים מנוקים אוטומטית).',
      '   • מחיר שנכתב בקובץ נשמר כמחיר ידני ואינו נדרס בחישוב אוטומטי מאוחר יותר.',
      '   • "מחיר לקבלן" מחייב שגם עמודת "קבלן" מלאה באותה שורה.',
      '   • שלוש העמודות האלה דורשות הרשאה: מחיר ללקוח וזמן נסיעה — "עריכת מחיר ידנית"; קבלן — "האצלת משימה לקבלן"; מחיר לקבלן — "עריכת תמחור". בלי ההרשאה הקובץ כולו נדחה, ולא מיובא חלקית.',
      '8. לכל אירוע נוצרות אוטומטית משימת הקמה ומשימת פירוק. שורת "הקמה" או "פירוק" בגיליון המשימות ממלאת את המשימה הקיימת ואינה מייצרת כפילות.',
      '9. "אופן ביצוע" הוא אופציונלי, והערכים המותרים תלויים בלקוח ובסוג המשימה. אם ערך אינו מותר ללקוח — אותה שורה תדווח בשגיאה והאירוע לא ייווצר.',
      '10. שורה שנפסלה מתגלגלת כולה: האירוע והמשימות שלו אינם נוצרים, והשגיאה מדווחת עם מספר השורה. אפשר לתקן ולהעלות שוב את אותו קובץ.',
      '11. סטטוס אירוע וסטטוס משימה אינם מיובאים — הם נקבעים במערכת לפי מחזור החיים שלהם.',
      '12. אפשר להעלות גם קובץ בן גיליון אחד בלבד; אז ייווצרו האירועים בלי משימות מפורטות.',
      '',
      'ערכים חוקיים במערכת',
    ],
    columns: [
      { key: 'kind', header: 'קטגוריה', width: 22 },
      { key: 'value', header: 'ערך', width: 34 },
    ],
    rows: guideRows,
  }

  return [
    { name: EVENTS_SHEET, columns: eventCols, rows: events },
    { name: TASKS_SHEET, columns: TASK_COLUMNS, rows: tasks },
    guide,
  ]
}
