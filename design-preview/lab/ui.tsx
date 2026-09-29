import type { ReactNode } from 'react'
import { initials } from './data'

export const cx = (...a: (string | false | null | undefined)[]) => a.filter(Boolean).join(' ')

/** צבע → רקע רך + טקסט קריא, מחושב מהצבע עצמו */
export const tint = (hex: string, pct = 14) => `color-mix(in srgb, ${hex} ${pct}%, var(--vl-surface))`

export function Avatar({ name, color = 'var(--nova-a)', size = 26 }: { name: string; color?: string; size?: number }) {
  return (
    <span title={name} className="inline-flex shrink-0 items-center justify-center rounded-full font-bold text-white ring-2 ring-[var(--vl-surface)]"
      style={{ width: size, height: size, fontSize: size * 0.4, background: color }}>{initials(name)}</span>
  )
}
export function AvatarStack({ names, max = 4, size = 26 }: { names: string[]; max?: number; size?: number }) {
  const palette = ['#5b5bf0', '#0e8a7d', '#d0265c', '#a86a08', '#8a3fd4', '#0c7ba6']
  return (
    <span className="inline-flex items-center">
      {names.slice(0, max).map((n, i) => (
        <span key={n + i} style={{ marginInlineStart: i ? -8 : 0 }}><Avatar name={n} size={size} color={palette[(n.length + i) % palette.length]} /></span>
      ))}
      {names.length > max && <span className="ms-1 text-xs font-bold text-ink-tertiary">+{names.length - max}</span>}
    </span>
  )
}

export function Ring({ value, max, size = 44, stroke = 5, color = 'var(--nova-a)', children }: { value: number; max: number; size?: number; stroke?: number; color?: string; children?: ReactNode }) {
  const r = (size - stroke) / 2, c = 2 * Math.PI * r, p = max ? Math.min(1, value / max) : 0
  return (
    <span className="relative inline-flex items-center justify-center" style={{ width: size, height: size }}>
      <svg width={size} height={size} className="-rotate-90">
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--vl-border)" strokeWidth={stroke} />
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={color} strokeWidth={stroke} strokeLinecap="round" strokeDasharray={c} strokeDashoffset={c * (1 - p)} />
      </svg>
      <span className="absolute inset-0 flex items-center justify-center text-[11px] font-extrabold text-ink">{children}</span>
    </span>
  )
}

export function Chip({ tone = 'neutral', children, className }: { tone?: 'neutral' | 'good' | 'warn' | 'bad' | 'brand'; children: ReactNode; className?: string }) {
  const t = {
    neutral: 'bg-[var(--vl-subtle)] text-[var(--vl-text-secondary)]',
    good: 'bg-[var(--vl-success-subtle)] text-[var(--vl-success-text)]',
    warn: 'bg-[var(--vl-warning-subtle)] text-[var(--vl-warning-text)]',
    bad: 'bg-[var(--vl-error-subtle)] text-[var(--vl-error-text)]',
    brand: 'bg-[var(--vl-primary-subtle)] text-[var(--vl-primary-text)]',
  }[tone]
  return <span className={cx('lab-chip', t, className)}>{children}</span>
}

export function Seg<T extends string>({ value, onChange, options }: { value: T; onChange: (v: T) => void; options: { v: T; label: string }[] }) {
  return (
    <div className="inline-flex rounded-xl bg-[var(--vl-subtle)] p-[3px] shadow-[inset_0_0_0_1px_var(--vl-border-subtle)]">
      {options.map((o) => (
        <button key={o.v} onClick={() => onChange(o.v)}
          className={cx('rounded-[9px] px-3 py-1 text-[13px] font-semibold transition', value === o.v ? 'bg-[var(--vl-surface)] text-ink shadow-sm' : 'text-ink-tertiary hover:text-ink')}>{o.label}</button>
      ))}
    </div>
  )
}

/** טווח שעות בכיוון קבוע — בתוך טקסט עברי הוא אחרת מתהפך ("13:00–09:30") */
export const Rng = ({ a, b, className }: { a: string; b: string; className?: string }) => <bdi dir="ltr" className={cx('tabular-nums', className)}>{a}–{b}</bdi>
