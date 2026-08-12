/**
 * המטא-דאטה של בונה המחשבון.
 *
 * `app.price_calc` במיגרציה 0017 היא המבצעת; הקובץ הזה רק מתאר לעורך *מה*
 * אפשר להרכיב — אילו סוגי רכיבים קיימים, אילו שדות כל סוג צריך, ואיך קוראים
 * להם בעברית. הוספת סוג רכיב למנוע היא ענף אחד ב-SQL וערך אחד כאן, ושום
 * מקום שלישי.
 *
 * שום חישוב לא נעשה בקובץ הזה במכוון. התצוגה המקדימה בבונה קוראת ל-RPC
 * preview_task_price ומקבלת את התוצאה מאותו מנוע שמתמחר בפועל, כדי שלא
 * ייווצרו שתי אמיתות שיכולות להיפרד זו מזו.
 */
import type {
  PricingAfterWorkers,
  PricingComponent,
  PricingConfig,
  PricingHourComponent,
  PricingModel,
} from '../../types/domain'

/* ===== המשתנים שהמנוע מכיר ================================================ */

export interface PricingVarDef {
  key: string
  label: string
  /** יחידת המדידה, לתצוגה ליד השדה */
  unit?: string
  kind: 'number' | 'boolean'
  /** מאיפה הערך מגיע בפועל — נכתב למשתמש כדי שידע מה הוא בוחר */
  source: string
}

export const PRICING_VARS: PricingVarDef[] = [
  { key: 'truck_count', label: 'כמות משאיות', kind: 'number', source: 'מהאירוע' },
  { key: 'worker_count', label: 'כמות עובדים', kind: 'number', source: 'מהמשימה' },
  { key: 'hours_count', label: 'שעות עבודה באירוע', unit: 'ש׳', kind: 'number', source: 'מהמשימה' },
  { key: 'travel_hours', label: 'זמן נסיעה (כיוון אחד)', unit: 'ש׳', kind: 'number', source: 'מאזור הגיאופנס' },
  { key: 'volume_m', label: 'נפח', unit: 'קוב', kind: 'number', source: 'מהאירוע' },
  { key: 'worker_hours', label: 'שעות × עובדים', kind: 'number', source: 'מחושב' },
  { key: 'zone_surcharge', label: 'תוספת האזור', unit: '₪', kind: 'number', source: 'מאזור הגיאופנס' },
  { key: 'dow', label: 'יום בשבוע (0=א׳)', kind: 'number', source: 'מתאריך המשימה' },
  { key: 'start_hour', label: 'שעת התחלה בשטח', kind: 'number', source: 'מהמשימה' },
  { key: 'no_parking', label: 'אין חניה', kind: 'boolean', source: 'מהאירוע' },
  { key: 'porterage', label: 'סבלות', kind: 'boolean', source: 'מהאירוע' },
  { key: 'supplier_pickup', label: 'איסוף מספקים', kind: 'boolean', source: 'מהאירוע' },
  { key: 'requires_team_lead', label: 'נדרש ראש צוות', kind: 'boolean', source: 'קבוע במחשבון' },
  { key: 'is_weekend', label: 'סוף שבוע', kind: 'boolean', source: 'מתאריך המשימה' },
  { key: 'has_truck', label: 'שובצה משאית', kind: 'boolean', source: 'מהמשימה' },
]

export const VAR_LABEL: Record<string, string> = Object.fromEntries(
  PRICING_VARS.map((v) => [v.key, v.label]),
)

export const NUMBER_VARS = PRICING_VARS.filter((v) => v.kind === 'number')
export const BOOLEAN_VARS = PRICING_VARS.filter((v) => v.kind === 'boolean')

/* ===== סוגי הרכיבים ======================================================= */

/** אילו שדות העורך צריך לצייר עבור כל סוג. */
export type FieldName =
  | 'hours'
  | 'input'
  | 'multiplier'
  | 'first'
  | 'each_additional'
  | 'amount'
  | 'rate'
  | 'included_units'
  | 'tiers'
  | 'amount_kind'
  | 'workers_basis'

export interface KindDef<K extends string> {
  kind: K
  label: string
  hint: string
  fields: FieldName[]
}

export const HOUR_KINDS: KindDef<PricingHourComponent['kind']>[] = [
  { kind: 'const', label: 'זמן קבוע', hint: 'מספר שעות קבוע, בלי תלות בנתוני האירוע', fields: ['hours'] },
  { kind: 'input', label: 'לפי נתון', hint: 'נתון מהאירוע או מהמשימה, עם מכפיל', fields: ['input', 'multiplier'] },
  {
    kind: 'stepped',
    label: 'מדורג לפי כמות',
    hint: 'הראשון בזמן אחד, כל נוסף בזמן אחר — כמו משאיות',
    fields: ['input', 'first', 'each_additional'],
  },
]

export const AFTER_KINDS: KindDef<PricingAfterWorkers['kind']>[] = [
  { kind: 'fixed', label: 'סכום קבוע', hint: 'מתווסף פעם אחת לסך הכול', fields: ['amount'] },
  { kind: 'per_worker', label: 'לכל עובד', hint: 'הסכום כפול כמות העובדים', fields: ['amount', 'workers_basis'] },
  { kind: 'percent', label: 'אחוז', hint: 'אחוז ממה שנצבר עד כאן', fields: ['amount'] },
  { kind: 'var', label: 'לפי נתון', hint: 'סכום שמגיע מהנתונים, כמו תוספת האזור', fields: ['input', 'multiplier'] },
]

export const COMPONENT_KINDS: KindDef<PricingComponent['kind']>[] = [
  { kind: 'fixed', label: 'סכום קבוע', hint: 'מחיר בסיס', fields: ['amount'] },
  {
    kind: 'per_unit',
    label: 'תעריף ליחידה',
    hint: 'מחיר לכל יחידה, עם אפשרות ליחידות כלולות בחינם',
    fields: ['input', 'rate', 'included_units'],
  },
  { kind: 'tiered', label: 'מדרגות', hint: 'מחיר לפי טווח — קבוע למדרגה או מדורג', fields: ['input', 'tiers'] },
  { kind: 'surcharge', label: 'תוספת מותנית', hint: 'סכום או אחוז שנוסף רק בתנאי', fields: ['amount', 'amount_kind'] },
  { kind: 'var', label: 'לפי נתון', hint: 'סכום שמגיע מהנתונים', fields: ['input', 'multiplier'] },
]

/**
 * שתי הצורות של תוספת עובדים. 'fixed' היא הוותיקה — מספר קבוע כשהתנאי
 * מתקיים. 'per_unit' סופרת לפי נתון, וזו התשובה ל"אין חניה ⇒ עובד לכל
 * משאית": המאמץ גדל עם כמות המשאיות ולא עם עצם היעדר החניה.
 */
export const WORKER_ADJUST_KINDS: KindDef<'fixed' | 'per_unit'>[] = [
  { kind: 'fixed', label: 'כמות קבועה', hint: 'מספר עובדים אחד, כשהתנאי מתקיים', fields: [] },
  {
    kind: 'per_unit',
    label: 'לפי כמות',
    hint: 'עובדים לכל יחידה — למשל עובד לכל משאית כשאין חניה',
    fields: ['input'],
  },
]

/** עיגול תוצאת per_unit, כי חצי עובד אינו אדם. */
export const ADJUST_ROUNDING_LABEL: Record<string, string> = {
  none: 'בלי עיגול',
  up: 'כלפי מעלה',
  down: 'כלפי מטה',
  nearest: 'לקרוב ביותר',
}

export const WORKERS_BASIS_LABEL: Record<string, string> = {
  base: 'העובדים שהוזמנו',
  effective: 'העובדים בפועל (כולל תוספות)',
}

export const ROUNDING_LABEL: Record<string, string> = {
  nearest: 'לקרוב ביותר',
  up: 'כלפי מעלה',
  down: 'כלפי מטה',
}

export const MODEL_LABEL: Record<PricingModel, string> = {
  worker_hours: 'שעות ועובדים',
  line_items: 'כרטיס תעריפים',
}

export const MODEL_HINT: Record<PricingModel, string> = {
  worker_hours:
    'סכום זמנים ⇒ שעות, כפול תעריף ⇒ מחיר לעובד, כפול כמות עובדים, ואז תוספות ומקדמים. זו הצורה של הקמה ופירוק.',
  line_items:
    'סכום שורות בלתי תלויות: בסיס, תעריף ליחידה, מדרגות ותוספות. מתאים ללקוח שמתמחר לפי קוב או לפי משאית.',
}

/* ===== עזרי עריכה ========================================================= */

/** מזהה יציב לשורה חדשה. המנוע לא נשען עליו — הוא נועד ל-key ולפירוט. */
export function newId(prefix: string): string {
  return `${prefix}_${Math.random().toString(36).slice(2, 8)}`
}

export function emptyConfig(model: PricingModel): PricingConfig {
  return model === 'worker_hours'
    ? {
        version: 1,
        model,
        hour_rate: 0,
        per_worker_fee: 0,
        // מחשבון חדש נולד עם רצפת 6 שעות; מחשבונים קיימים לא נוגעים —
        // normalizeConfig לא משלים את המפתח למי שנשמר בלעדיו.
        min_hours: 6,
        constants: {},
        hours: [],
        workers: { input: 'worker_count', adjustments: [] },
        after_workers: [],
        multipliers: [],
        min_price: null,
        max_price: null,
        rounding: { mode: 'nearest', to: 1 },
      }
    : {
        version: 1,
        model,
        components: [],
        multipliers: [],
        min_price: null,
        max_price: null,
        rounding: { mode: 'nearest', to: 1 },
      }
}

/**
 * ממלא חורים שנוצרו מהחלפת מודל או מקונפיג ישן, כדי שהעורך תמיד יקבל
 * מערכים ולא undefined. לא נוגע בערכים קיימים.
 */
export function normalizeConfig(config: Partial<PricingConfig> | null | undefined): PricingConfig {
  const model: PricingModel = config?.model === 'worker_hours' ? 'worker_hours' : 'line_items'
  const base = emptyConfig(model)
  return {
    ...base,
    ...config,
    model,
    version: config?.version ?? 1,
    constants: config?.constants ?? base.constants,
    hours: config?.hours ?? base.hours,
    workers: config?.workers ?? base.workers,
    after_workers: config?.after_workers ?? base.after_workers,
    components: config?.components ?? base.components,
    multipliers: config?.multipliers ?? [],
    rounding: config?.rounding ?? { mode: 'nearest', to: 1 },
  }
}

export function moveItem<T>(list: T[], from: number, to: number): T[] {
  if (to < 0 || to >= list.length) return list
  const next = list.slice()
  const [item] = next.splice(from, 1)
  next.splice(to, 0, item)
  return next
}

/**
 * הנתונים שהתצוגה המקדימה שולחת. אלה גם ברירות מחדל סבירות לאירוע טיפוסי,
 * כדי שהבונה יראה מספר אמיתי כבר בפתיחה ולא אפס.
 */
export const PREVIEW_DEFAULTS: Record<string, number | boolean> = {
  truck_count: 3,
  worker_count: 4,
  hours_count: 4,
  travel_hours: 0.5,
  volume_m: 40,
  zone_surcharge: 0,
  dow: 3,
  start_hour: 9,
  no_parking: false,
  porterage: false,
  supplier_pickup: false,
  requires_team_lead: false,
  is_weekend: false,
  has_truck: true,
}
