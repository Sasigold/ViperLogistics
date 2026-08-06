import { useId, useLayoutEffect, useRef, useState } from 'react'
import type { ButtonHTMLAttributes, ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { Loader2 } from 'lucide-react'

export function cx(...parts: Array<string | false | null | undefined>) {
  return parts.filter(Boolean).join(' ')
}

/* ===== Button =============================================================
   Five variants x three sizes. Every variant carries the same focus, press
   and disabled treatment so the whole product responds identically.        */

export type BtnVariant = 'primary' | 'secondary' | 'outlined' | 'ghost' | 'danger'
export type BtnSize = 'sm' | 'md' | 'lg'

const BTN_BASE =
  'relative inline-flex select-none items-center justify-center gap-1.5 rounded-md border type-button whitespace-nowrap ' +
  'transition-[background-color,border-color,color,box-shadow,transform] duration-150 ease-[cubic-bezier(.4,0,.2,1)] ' +
  'active:scale-[.98] focus-visible:outline-none focus-visible:focus-ring ' +
  'disabled:pointer-events-none disabled:opacity-55 disabled:active:scale-100'

const BTN_VARIANTS: Record<BtnVariant, string> = {
  primary:
    'border-transparent bg-primary text-on-primary shadow-xs hover:bg-primary-hover active:bg-primary-hover',
  secondary:
    'border-line bg-surface text-ink shadow-xs hover:bg-subtle hover:border-line-strong active:bg-inset',
  outlined:
    'border-primary-border bg-transparent text-primary-text hover:bg-primary-subtle active:bg-primary-subtle',
  ghost: 'border-transparent bg-transparent text-ink-secondary hover:bg-hover hover:text-ink active:bg-hover',
  danger: 'border-transparent bg-error text-white shadow-xs hover:brightness-110 active:brightness-95',
}

const BTN_SIZES: Record<BtnSize, string> = {
  sm: 'h-8 px-2.5 text-[0.8125rem]',
  md: 'h-9 px-3',
  lg: 'h-10 px-4 text-[0.9375rem]',
}

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: BtnVariant
  size?: BtnSize
  loading?: boolean
  /** stretch to the container width */
  block?: boolean
}

export function Button({
  variant = 'secondary',
  size = 'md',
  loading,
  block,
  className,
  children,
  ...rest
}: ButtonProps) {
  return (
    <button
      className={cx(BTN_BASE, BTN_VARIANTS[variant], BTN_SIZES[size], block && 'w-full', className)}
      disabled={loading || rest.disabled}
      aria-busy={loading || undefined}
      {...rest}
    >
      {loading && <Loader2 size={14} className="animate-spin" aria-hidden />}
      {children}
    </button>
  )
}

/* ===== IconButton =========================================================
   Square, icon-only. `label` is mandatory — it becomes the accessible name
   and the tooltip, so an icon-only control is never unlabelled.            */

export interface IconButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'title'> {
  label: string
  variant?: BtnVariant
  size?: BtnSize
  loading?: boolean
  /** suppress the hover tooltip (when the parent renders its own) */
  bare?: boolean
}

const ICON_SIZES: Record<BtnSize, string> = { sm: 'size-8', md: 'size-9', lg: 'size-10' }

export function IconButton({
  label,
  variant = 'ghost',
  size = 'md',
  loading,
  bare,
  className,
  children,
  ...rest
}: IconButtonProps) {
  const btn = (
    <button
      aria-label={label}
      className={cx(BTN_BASE, BTN_VARIANTS[variant], ICON_SIZES[size], 'shrink-0 p-0', className)}
      disabled={loading || rest.disabled}
      {...rest}
    >
      {loading ? <Loader2 size={15} className="animate-spin" aria-hidden /> : children}
    </button>
  )
  return bare ? btn : <Tooltip content={label}>{btn}</Tooltip>
}

/* ===== Tooltip ============================================================
   Portalled so it escapes `overflow:hidden` table and board containers, and
   mounted only while open so idle rows cost nothing.                       */

type Placement = 'top' | 'bottom' | 'start' | 'end'

export function Tooltip({
  content,
  placement = 'top',
  delay = 250,
  children,
}: {
  content: ReactNode
  placement?: Placement
  delay?: number
  children: ReactNode
}) {
  const [open, setOpen] = useState(false)
  const [pos, setPos] = useState<{ top: number; left: number } | null>(null)
  const anchor = useRef<HTMLSpanElement>(null)
  const bubble = useRef<HTMLDivElement>(null)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const id = useId()

  const show = () => {
    if (timer.current) clearTimeout(timer.current)
    timer.current = setTimeout(() => setOpen(true), delay)
  }
  const hide = () => {
    if (timer.current) clearTimeout(timer.current)
    setOpen(false)
    setPos(null)
  }

  useLayoutEffect(() => {
    if (!open || !anchor.current || !bubble.current) return
    const a = anchor.current.getBoundingClientRect()
    const b = bubble.current.getBoundingClientRect()
    const gap = 8
    let top = a.top - b.height - gap
    let left = a.left + a.width / 2 - b.width / 2
    if (placement === 'bottom') top = a.bottom + gap
    if (placement === 'start' || placement === 'end') {
      top = a.top + a.height / 2 - b.height / 2
      left = placement === 'start' ? a.left - b.width - gap : a.right + gap
    }
    // keep the bubble inside the viewport
    left = Math.max(8, Math.min(left, window.innerWidth - b.width - 8))
    if (top < 8) top = a.bottom + gap
    if (top + b.height > window.innerHeight - 8) top = Math.max(8, a.top - b.height - gap)
    setPos({ top, left })
  }, [open, placement])

  if (!content) return <>{children}</>

  return (
    <>
      <span
        ref={anchor}
        className="contents"
        onPointerEnter={show}
        onPointerLeave={hide}
        onFocusCapture={() => setOpen(true)}
        onBlurCapture={hide}
        aria-describedby={open ? id : undefined}
      >
        {children}
      </span>
      {open &&
        createPortal(
          <div
            ref={bubble}
            id={id}
            role="tooltip"
            className="pointer-events-none fixed z-[100] max-w-xs animate-fade-in rounded-md bg-ink px-2 py-1 type-caption font-medium text-ink-inverse shadow-lg"
            style={{ top: pos?.top ?? -9999, left: pos?.left ?? -9999, visibility: pos ? 'visible' : 'hidden' }}
          >
            {content}
          </div>,
          document.body,
        )}
    </>
  )
}

/* ===== Badge ==============================================================
   `color` (an arbitrary hex from the DB — customer/status colours) keeps its
   original meaning. Dark mode lightens the text so DB colours picked against
   a white background stay readable on a dark surface.                       */

export type Tone = 'neutral' | 'primary' | 'success' | 'warning' | 'error' | 'info'

const TONES: Record<Tone, string> = {
  neutral: 'bg-subtle text-ink-secondary ring-line',
  primary: 'bg-primary-subtle text-primary-text ring-primary-border',
  success: 'bg-success-subtle text-success-text ring-success-border',
  warning: 'bg-warning-subtle text-warning-text ring-warning-border',
  error: 'bg-error-subtle text-error-text ring-error-border',
  info: 'bg-info-subtle text-info-text ring-info-border',
}

export function Badge({
  color,
  tone = 'neutral',
  dot,
  className,
  children,
}: {
  color?: string
  tone?: Tone
  dot?: boolean
  className?: string
  children: ReactNode
}) {
  const base =
    'inline-flex max-w-full items-center gap-1 rounded-full px-2 py-0.5 type-caption font-semibold ring-1 ring-inset'
  if (color) {
    return (
      <span
        className={cx(
          base,
          'text-[color-mix(in_srgb,var(--vl-badge),black_20%)] ring-[color-mix(in_srgb,var(--vl-badge),transparent_72%)]',
          'dark:text-[color-mix(in_srgb,var(--vl-badge),white_55%)]',
          className,
        )}
        style={
          {
            '--vl-badge': color,
            background: `color-mix(in srgb, ${color} 14%, transparent)`,
          } as React.CSSProperties
        }
      >
        {dot && <span className="size-1.5 shrink-0 rounded-full" style={{ background: color }} />}
        <span className="truncate">{children}</span>
      </span>
    )
  }
  return (
    <span className={cx(base, TONES[tone], className)}>
      {dot && <span className="size-1.5 shrink-0 rounded-full bg-current opacity-70" />}
      <span className="truncate">{children}</span>
    </span>
  )
}

/** A small square status chip — reads better than a pill inside dense grids. */
export function StatusPill({ color, children, className }: { color?: string | null; children: ReactNode; className?: string }) {
  return (
    <span
      className={cx(
        'inline-flex max-w-full items-center gap-1.5 rounded-md px-1.5 py-0.5 type-caption font-semibold',
        'text-[color-mix(in_srgb,var(--vl-pill),black_20%)] dark:text-[color-mix(in_srgb,var(--vl-pill),white_55%)]',
        className,
      )}
      style={
        {
          '--vl-pill': color ?? 'var(--vl-text-secondary)',
          background: `color-mix(in srgb, ${color ?? 'var(--vl-text-secondary)'} 14%, transparent)`,
        } as React.CSSProperties
      }
    >
      <span className="size-1.5 shrink-0 rounded-full" style={{ background: color ?? 'var(--vl-text-tertiary)' }} />
      <span className="truncate">{children}</span>
    </span>
  )
}

/* ===== Avatar =============================================================
   Initials with a colour derived from the name, so the same person is always
   the same colour without storing anything.                                */

const AVATAR_HUES = [214, 262, 340, 12, 32, 152, 188, 286]

function initials(name: string) {
  const parts = name.trim().split(/\s+/).filter(Boolean)
  if (parts.length === 0) return '?'
  if (parts.length === 1) return parts[0].slice(0, 2)
  return parts[0][0] + parts[parts.length - 1][0]
}

function hue(name: string) {
  let h = 0
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) >>> 0
  return AVATAR_HUES[h % AVATAR_HUES.length]
}

const AVATAR_SIZES = { xs: 'size-5 text-[9px]', sm: 'size-6 text-[10px]', md: 'size-8 text-[11px]', lg: 'size-10 text-sm' }

export function Avatar({
  name,
  size = 'sm',
  className,
  ring,
}: {
  name: string
  size?: keyof typeof AVATAR_SIZES
  className?: string
  ring?: boolean
}) {
  const h = hue(name || '?')
  return (
    <span
      className={cx(
        'inline-flex shrink-0 items-center justify-center rounded-full font-bold uppercase',
        AVATAR_SIZES[size],
        ring && 'ring-2 ring-surface',
        className,
      )}
      style={{ background: `hsl(${h} 72% 92%)`, color: `hsl(${h} 62% 32%)` }}
      title={name}
    >
      {initials(name || '?')}
    </span>
  )
}

export function AvatarGroup({
  names,
  max = 4,
  size = 'sm',
}: {
  names: string[]
  max?: number
  size?: keyof typeof AVATAR_SIZES
}) {
  if (names.length === 0) return null
  const shown = names.slice(0, max)
  const rest = names.length - shown.length
  return (
    <Tooltip content={names.join(' · ')}>
      <span className="inline-flex items-center -space-x-1.5 rtl:space-x-reverse">
        {shown.map((n, i) => (
          <Avatar key={`${n}-${i}`} name={n} size={size} ring />
        ))}
        {rest > 0 && (
          <span
            className={cx(
              'inline-flex shrink-0 items-center justify-center rounded-full bg-inset font-bold text-ink-secondary ring-2 ring-surface',
              AVATAR_SIZES[size],
            )}
          >
            +{rest}
          </span>
        )}
      </span>
    </Tooltip>
  )
}

/* ===== ProgressBar ======================================================== */

const PROGRESS_TONES: Record<Tone, string> = {
  neutral: 'bg-ink-tertiary',
  primary: 'bg-primary',
  success: 'bg-success',
  warning: 'bg-warning',
  error: 'bg-error',
  info: 'bg-info',
}

export function ProgressBar({
  value,
  max = 100,
  tone = 'primary',
  color,
  label,
  hint,
  className,
}: {
  value: number
  max?: number
  tone?: Tone
  /** overrides `tone` with an arbitrary colour (DB status colours) */
  color?: string
  label?: ReactNode
  hint?: ReactNode
  className?: string
}) {
  const pct = max > 0 ? Math.min(100, Math.max(0, (value / max) * 100)) : 0
  return (
    <div className={className}>
      {(label || hint) && (
        <div className="mb-1.5 flex items-center justify-between gap-2">
          {label && <span className="min-w-0 truncate type-caption font-medium text-ink-secondary">{label}</span>}
          {hint && <span className="shrink-0 type-caption tabular text-ink-tertiary">{hint}</span>}
        </div>
      )}
      <div
        className="h-1.5 w-full overflow-hidden rounded-full bg-inset"
        role="progressbar"
        aria-valuenow={Math.round(pct)}
        aria-valuemin={0}
        aria-valuemax={100}
      >
        <div
          className={cx('h-full rounded-full transition-[width] duration-500 ease-out', !color && PROGRESS_TONES[tone])}
          style={{ width: `${pct}%`, background: color }}
        />
      </div>
    </div>
  )
}

/* ===== Kbd ================================================================ */

export function Kbd({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <kbd
      dir="ltr"
      className={cx(
        'inline-flex h-5 min-w-5 items-center justify-center rounded border border-line bg-subtle px-1',
        'font-sans text-[10px] font-semibold text-ink-tertiary',
        className,
      )}
    >
      {children}
    </kbd>
  )
}

/* ===== Divider ============================================================ */

export function Divider({ className, vertical }: { className?: string; vertical?: boolean }) {
  return vertical ? (
    <span className={cx('inline-block h-4 w-px shrink-0 bg-line', className)} aria-hidden />
  ) : (
    <div className={cx('h-px w-full bg-line-subtle', className)} aria-hidden />
  )
}
