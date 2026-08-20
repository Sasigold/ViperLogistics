/**
 * צי הרכב — הלוגיקה שאינה נוגעת ברשת ולא ב-DOM.
 *
 * כל מה שכאן נבדק ב-vehicles.test.ts, ובאותה רוח של specs.ts: הכללים חייבים
 * לשקף את מה שהמסד והדלי אוכפים ב-0088 — אותה רשימת MIME, אותו גבול גודל,
 * ואותו חישוב תוקף שה-view `vehicle_document_status` עושה בשרת. הבדיקה כאן
 * אינה אבטחה; היא נימוס, וגם מה שמאפשר להציג צבע בלי הלוך-חזור נוסף.
 */
import type {
  Vehicle,
  VehicleCategory,
  VehicleDocumentState,
  VehicleFuelType,
  VehicleGearbox,
  VehicleOwnership,
  VehicleStatus,
} from '../../types/domain'

/** 25MB — אותו ערך שנרשם על הדלי vehicle-docs ב-0088 §8. */
export const VEHICLE_DOC_MAX_BYTES = 25 * 1024 * 1024

export const VEHICLE_DOC_MIME_TYPES = [
  'application/pdf',
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
] as const

export const VEHICLE_DOC_ACCEPT = '.pdf,.jpg,.jpeg,.png,.webp,.heic,.heif,application/pdf,image/*'

/* ===== תוויות ============================================================= */

export const VEHICLE_STATUS_LABELS: Record<VehicleStatus, string> = {
  active: 'פעיל',
  in_garage: 'במוסך',
  inactive: 'מושבת',
  sold: 'נמכר',
}

/** הצבעים של `StatusPill`, באותה משפחה שבה שאר המסכים משתמשים. */
export const VEHICLE_STATUS_COLORS: Record<VehicleStatus, string> = {
  active: '#22c55e',
  in_garage: '#f59e0b',
  inactive: '#8a93a5',
  sold: '#64748b',
}

export const VEHICLE_CATEGORY_LABELS: Record<VehicleCategory, string> = {
  truck: 'משאית',
  van: 'מסחרי',
  car: 'רכב פרטי',
  trailer: 'נגרר',
  forklift: 'מלגזה',
  other: 'אחר',
}

export const VEHICLE_OWNERSHIP_LABELS: Record<VehicleOwnership, string> = {
  owned: 'בבעלות',
  leasing: 'ליסינג',
  rental: 'שכירות',
}

export const VEHICLE_FUEL_LABELS: Record<VehicleFuelType, string> = {
  diesel: 'סולר',
  gasoline: 'בנזין',
  electric: 'חשמלי',
  hybrid: 'היברידי',
  lpg: 'גז',
}

export const VEHICLE_GEARBOX_LABELS: Record<VehicleGearbox, string> = {
  manual: 'ידני',
  automatic: 'אוטומטי',
}

/** דרגות הרישיון של תקנות התעבורה, בסדר שבו נהג מכיר אותן. */
export const LICENSE_CLASSES = ['A', 'A1', 'A2', 'B', 'C1', 'C', 'C+E', 'D1', 'D2', 'D3', 'D', '1'] as const

/* ===== מספר רישוי ========================================================= */

/**
 * הספרות בלבד. '12-345-67' ו-'1234567' הם אותו רכב, וזו ההשוואה שמונעת
 * כפילות כשמישהו מקליד את המקפים אחרת.
 */
export function normalizePlate(raw: string | null | undefined): string {
  return (raw ?? '').replace(/[^0-9]/g, '')
}

/**
 * התצוגה הישראלית: 7 ספרות הן 12-345-67, ו-8 הן 123-45-678. כל אורך אחר
 * מוצג כפי שהוקלד — מספר של נגרר או של רכב מיובא אינו חייב להיכנס לתבנית,
 * ולעוות אותו גרוע מלא לעצב אותו.
 */
export function formatPlate(raw: string | null | undefined): string {
  const digits = normalizePlate(raw)
  if (digits.length === 7) return `${digits.slice(0, 2)}-${digits.slice(2, 5)}-${digits.slice(5)}`
  if (digits.length === 8) return `${digits.slice(0, 3)}-${digits.slice(3, 5)}-${digits.slice(5)}`
  return (raw ?? '').trim()
}

/* ===== תוקף =============================================================== */

/**
 * אותו חישוב בדיוק שה-view עושה בשרת (0088 §4). הוא חוזר לכאן כי המסך צריך
 * לצבוע גם שורה שנערכה זה עתה ועוד לא נקראה מחדש; ההסכמה בין השניים נבדקת
 * בחבילת ה-SQL, לא כאן.
 *
 * `today` הוא פרמטר ולא `new Date()` פנימי — אחרת הבדיקה תלויה ביום שבו היא רצה.
 */
export function docState(
  expiresAt: string | null | undefined,
  alertDays: number,
  today: Date = new Date(),
): VehicleDocumentState {
  if (!expiresAt) return 'no_expiry'
  const left = daysUntil(expiresAt, today)
  if (left < 0) return 'expired'
  if (left <= alertDays) return 'expiring'
  return 'valid'
}

/**
 * ימים שלמים מהיום ועד התאריך. שלילי = עבר.
 *
 * שני הצדדים מנורמלים ל-UTC של חצות המקומית לפני החיסור, אחרת מעבר שעון קיץ
 * בתוך הטווח מזיז את התוצאה בשעה ומעגל ליום שלם.
 */
export function daysUntil(date: string, today: Date = new Date()): number {
  const target = new Date(`${date}T00:00:00`)
  if (Number.isNaN(target.getTime())) return 0
  const targetUtc = Date.UTC(target.getFullYear(), target.getMonth(), target.getDate())
  const baseUtc = Date.UTC(today.getFullYear(), today.getMonth(), today.getDate())
  return Math.round((targetUtc - baseUtc) / 86_400_000)
}

export const DOC_STATE_LABELS: Record<VehicleDocumentState, string> = {
  valid: 'בתוקף',
  expiring: 'פג בקרוב',
  expired: 'פג',
  no_expiry: 'ללא תוקף',
}

export const DOC_STATE_COLORS: Record<VehicleDocumentState, string> = {
  valid: '#22c55e',
  expiring: '#f59e0b',
  expired: '#ef4444',
  no_expiry: '#8a93a5',
}

/** 'פג בעוד 12 ימים' / 'פג לפני 3 ימים' / 'פג היום'. */
export function expiryLabel(expiresAt: string | null | undefined, today: Date = new Date()): string {
  if (!expiresAt) return 'ללא תאריך פקיעה'
  const left = daysUntil(expiresAt, today)
  if (left === 0) return 'פג היום'
  if (left === 1) return 'פג מחר'
  if (left === -1) return 'פג אתמול'
  return left > 0 ? `פג בעוד ${left} ימים` : `פג לפני ${-left} ימים`
}

/**
 * המצב החמור ביותר מבין המסמכים של רכב — זה מה שהעמודה ברשימה מציגה.
 * 'no_expiry' אינו מדורג: מסמך בלי תוקף אינו אומר דבר על כשירות הרכב.
 */
export function worstDocState(states: VehicleDocumentState[]): VehicleDocumentState {
  if (states.includes('expired')) return 'expired'
  if (states.includes('expiring')) return 'expiring'
  if (states.includes('valid')) return 'valid'
  return 'no_expiry'
}

/* ===== קבצים ============================================================== */

/** null = הקובץ תקין. אחרת — המשפט שיוצג למשתמש. */
export function validateDocFile(file: { name: string; type: string; size: number }): string | null {
  if (file.size === 0) return 'הקובץ ריק'
  if (file.size > VEHICLE_DOC_MAX_BYTES) {
    return `הקובץ גדול מ-${Math.round(VEHICLE_DOC_MAX_BYTES / 1024 / 1024)}MB (${formatBytes(file.size)})`
  }
  const mime = file.type.toLowerCase()
  if (mime && (VEHICLE_DOC_MIME_TYPES as readonly string[]).includes(mime)) return null
  const ext = file.name.split('.').pop()?.toLowerCase() ?? ''
  if (['pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'].includes(ext)) return null
  return 'אפשר להעלות PDF או תמונה בלבד'
}

/**
 * הנתיב בדלי. התיקייה הראשונה היא מזהה הרכב — זה החוזה שפוליסת ה-Storage
 * קוראת ממנו (0088 §8), ולכן הוא נבנה כאן ולא נלקח מהמשתמש.
 */
export function docStoragePath(vehicleId: string, fileName: string, uuid: string): string {
  const ext = fileName.includes('.') ? fileName.split('.').pop()!.toLowerCase().replace(/[^a-z0-9]/g, '') : ''
  return ext ? `${vehicleId}/${uuid}.${ext}` : `${vehicleId}/${uuid}`
}

export function formatBytes(bytes: number | null): string {
  if (bytes == null || bytes <= 0) return ''
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`
}

/* ===== תצוגה ============================================================== */

/** 'מרצדס אקטרוס 2019' — מה שיש, בלי רווחים כפולים כשחסר חלק. */
export function vehicleModelLine(v: Pick<Vehicle, 'make' | 'model' | 'model_year'>): string {
  return [v.make, v.model, v.model_year].filter(Boolean).join(' ')
}

/** תאריך פקיעה מוצע לפי הסוג, למילוי אוטומטי בטופס. */
export function suggestExpiry(issuedAt: string, validMonths: number | null): string {
  if (!validMonths || !issuedAt) return ''
  const d = new Date(`${issuedAt}T00:00:00`)
  if (Number.isNaN(d.getTime())) return ''
  const day = d.getDate()
  d.setMonth(d.getMonth() + validMonths)
  // 31 בינואר + 12 חודשים חייב להישאר 31 בינואר; חודש קצר היה גולש קדימה.
  if (d.getDate() !== day) d.setDate(0)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
}
