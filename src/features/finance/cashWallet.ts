/**
 * ארנק המזומנים (0206) — הלוגיקה הטהורה של המסך.
 *
 * היתרה, הסכומים והיתרה הרצה נספרים בשרת (`cash_wallet`). מה שכאן הוא איך
 * קוראים שורה, ואיזה טווח נשאל.
 */
import { format } from 'date-fns'
import type { CashWalletEntry, CashWalletSource } from '../../types/domain'
import { presetRange } from './eventPayments'
import type { RangePreset } from './eventPayments'

export const SOURCE_LABELS: Record<CashWalletSource, string> = {
  payment: 'תשלום במזומן',
  income: 'הכנסה ידנית',
  expense: 'הוצאה',
}

export const SOURCE_TONES: Record<CashWalletSource, 'success' | 'info' | 'error'> = {
  payment: 'success',
  income: 'info',
  expense: 'error',
}

/** שורה ידנית נמחקת מהארנק; מזומן שהתקבל על אירוע — רק מכרטיס האירוע. */
export function isManual(entry: Pick<CashWalletEntry, 'source'>): boolean {
  return entry.source !== 'payment'
}

/**
 * הכותרת של שורה: מה שהבעלים כתב, ובתשלום — על איזה אירוע הוא התקבל.
 * תשלום על אירוע שנמחק לצמיתות (event_id ריק) נשאר עם שם הלקוח.
 */
export function entryTitle(
  e: Pick<CashWalletEntry, 'source' | 'label' | 'event_name' | 'event_number' | 'customer_name'>,
): string {
  if (e.source !== 'payment') return e.label || SOURCE_LABELS[e.source]
  const event = [e.event_name, e.event_number && `#${e.event_number}`].filter(Boolean).join(' ')
  return event || e.customer_name || SOURCE_LABELS.payment
}

/** הטווחים של הארנק: אותם של מסך התשלומים, ועוד "הכול" — מהתנועה הראשונה. */
export type WalletPreset = RangePreset | 'all'

export const ALL_FROM = '2000-01-01'

export function walletRange(preset: WalletPreset, today: Date): { from: string; to: string } {
  if (preset === 'all') return { from: ALL_FROM, to: format(today, 'yyyy-MM-dd') }
  return presetRange(preset, today)
}

export function walletRangeError(from: string, to: string): string | null {
  if (!from || !to) return 'יש לבחור טווח תאריכים'
  if (to < from) return 'תאריך הסיום לפני תאריך ההתחלה'
  return null
}
