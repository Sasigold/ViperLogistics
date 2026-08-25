/**
 * טופס האירוע — המיפוי מהנתונים לשדות, בלי React ובלי רשת.
 *
 * כל שדה כאן הוא מחרוזת גם כשהעמודה במסד היא מספר: `<input type="number">`
 * מחזיר מחרוזת, ושדה שרוקן הוא `''` ולא `null`. ההמרה חזרה קורית ב-RPC, ולכן
 * הטופס אינו מנחש טיפוסים בדרך פנימה.
 *
 * המיפוי יושב בקובץ נפרד ולא בתוך האפקטים שקוראים לו, כי הוא החלק היחיד
 * בהזרעת הטופס שאפשר לבדוק: הבדיקות כאן רצות ב-node בלי DOM
 * (`vitest.config.ts`), ולכן מחזור החיים של המודאל עצמו נבדק ידנית ומה
 * שנשאר — מה נכנס לכל שדה — נבדק ב-eventForm.test.ts.
 */
import { toFormValues } from './CustomFieldInput'
import type { CustomFormValue } from './CustomFieldInput'
import type { EventAutoTask, EventRow } from '../../types/domain'

export type EventForm = {
  customer_id: string
  end_client_name: string
  event_number: string
  event_date: string
  location_text: string
  location_provider: string
  location_place_id: string
  location_lat: number | null
  location_lng: number | null
  location_notes: string
  volume_m: string
  truck_count: string
  contact_name: string
  contact_phone: string
  notes: string
  status_id: string
  no_parking: boolean
  porterage: boolean
  supplier_pickup: boolean
  supplier_ids: string[]
  setup_date: string
  setup_time: string
  setup_worker_count: string
  setup_hours_count: string
  setup_price: string
  setup_execution_method: string
  teardown_date: string
  teardown_time: string
  teardown_worker_count: string
  teardown_hours_count: string
  teardown_price: string
  teardown_execution_method: string
  /** values of the customer's custom fields, keyed by field_key */
  custom: Record<string, CustomFormValue>
  /** category income amounts (0068), keyed by income_categories.id */
  income: Record<string, string>
}

export const emptyEventForm: EventForm = {
  customer_id: '', end_client_name: '', event_number: '', event_date: '', location_text: '',
  location_provider: '', location_place_id: '', location_lat: null, location_lng: null,
  location_notes: '', volume_m: '', truck_count: '', contact_name: '', contact_phone: '',
  notes: '', status_id: '', no_parking: false, porterage: false, supplier_pickup: false, supplier_ids: [],
  setup_date: '', setup_time: '', setup_worker_count: '', setup_hours_count: '', setup_execution_method: '',
  setup_price: '',
  teardown_date: '', teardown_time: '', teardown_worker_count: '', teardown_hours_count: '', teardown_execution_method: '',
  teardown_price: '',
  custom: {},
  income: {},
}

/** The two auto-created tasks the section step edits. */
export const SECTIONS = [
  { code: 'setup' as const, title: 'הקמה' },
  { code: 'teardown' as const, title: 'פירוק' },
]

/** Field keys of one section — same names in form_fields, in the form and in the RPC payload. */
export const sectionFields = (code: 'setup' | 'teardown') =>
  [
    `${code}_date`,
    `${code}_time`,
    `${code}_worker_count`,
    `${code}_hours_count`,
    `${code}_execution_method`,
    `${code}_price`,
  ] as const

/**
 * האירוע כפי שהוא נכנס לטופס.
 *
 * מחזיר טופס *שלם* ולא patch, במכוון: כל פתיחה מתחילה מ-`emptyEventForm`,
 * ולכן ערך שנשאר מאירוע קודם אינו יכול לשרוד בשדה שהאירוע הזה השאיר ריק.
 *
 * שני שדות התאריך של הקמה ופירוק מוקדמים מתאריך האירוע — הם אינם על האירוע
 * כלל אלא על המשימות, וזה placeholder עד ש-`sectionValuesFromTasks` מגיע.
 */
export function eventFormValues(
  event: EventRow,
  contact?: { contact_name: string | null; contact_phone: string | null } | null,
  supplierIds?: string[],
): EventForm {
  return {
    ...emptyEventForm,
    customer_id: event.customer_id,
    end_client_name: event.end_client_name ?? '',
    event_number: event.event_number ?? '',
    event_date: event.event_date,
    location_text: event.location_text ?? '',
    location_provider: event.location_provider ?? '',
    location_place_id: event.location_place_id ?? '',
    location_lat: event.location_lat,
    location_lng: event.location_lng,
    location_notes: event.location_notes ?? '',
    volume_m: event.volume_m != null ? String(event.volume_m) : '',
    truck_count: event.truck_count != null ? String(event.truck_count) : '',
    contact_name: contact?.contact_name ?? '',
    contact_phone: contact?.contact_phone ?? '',
    notes: event.notes ?? '',
    status_id: event.status_id ?? '',
    no_parking: event.no_parking,
    porterage: event.porterage,
    supplier_pickup: event.supplier_pickup,
    supplier_ids: supplierIds ?? [],
    custom: toFormValues(event.custom_fields),
    setup_date: event.event_date,
    teardown_date: event.event_date,
  }
}

/**
 * ערכי ההקמה והפירוק, שיושבים על המשימות שהטריגר יצר ולא על האירוע.
 *
 * משימה שאינה קיימת נותנת שישה שדות ריקים ולא מפתחות נעדרים: מפתח נעדר היה
 * משאיר בטופס את מה שכבר היה בו, וזה בדיוק סוג התקלה שהמנגנון הזה נועד למנוע.
 *
 * ‏`price` יכול להיות null גם למשימה שיש לה מחיר — ‏RLS על `task_pricing`
 * מרוקנת אותו למי שאין לו `pricing.view` (ההנמקה ב-lib/queries.ts). השדה
 * נחסם בטופס, לא בשאילתה.
 */
export function sectionValuesFromTasks(tasks: EventAutoTask[]): Partial<EventForm> {
  const patch: Partial<EventForm> = {}
  for (const { code } of SECTIONS) {
    const t = tasks.find((x) => x.task_types.code === code)
    patch[`${code}_date`] = t?.task_date ?? ''
    patch[`${code}_time`] = t?.onsite_start_time?.slice(0, 5) ?? ''
    patch[`${code}_worker_count`] = t?.worker_count ? String(t.worker_count) : ''
    patch[`${code}_hours_count`] = t?.hours_count != null ? String(t.hours_count) : ''
    patch[`${code}_execution_method`] = t?.execution_method_id ?? ''
    patch[`${code}_price`] = t?.price != null ? String(t.price) : ''
  }
  return patch
}

/** סכומי ההכנסה של האירוע (0068), כמחרוזות של הטופס. */
export function incomeValuesFromRows(rows: { category_id: string; amount: number }[]): Record<string, string> {
  const income: Record<string, string> = {}
  for (const r of rows) income[r.category_id] = String(r.amount)
  return income
}

/**
 * הטיוטה של אירוע חדש, כפי שהיא חוזרת מ-localStorage.
 *
 * טיוטה שנכתבה בגרסה ישנה של הטופס, או כתיבה שנקטעה, אינה סיבה למסך שגיאה:
 * ה-JSON.parse רץ בתוך אפקט, ולכן זריקה ממנו הגיעה עד ל-ErrorBoundary ורוקנה
 * את העמוד. טיוטה שאי אפשר לקרוא נזרקת, והטופס נפתח ריק.
 */
export function draftFormValues(raw: string | null): EventForm {
  if (!raw) return emptyEventForm
  try {
    return { ...emptyEventForm, ...(JSON.parse(raw) as Partial<EventForm>) }
  } catch {
    return emptyEventForm
  }
}
