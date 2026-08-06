import { format, parseISO } from 'date-fns'
import { he } from 'date-fns/locale'

export function fmtDate(d: string | Date | null | undefined): string {
  if (!d) return ''
  const date = typeof d === 'string' ? parseISO(d) : d
  return format(date, 'dd/MM/yyyy', { locale: he })
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
