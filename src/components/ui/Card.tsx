import { useState } from 'react'
import type { ReactNode } from 'react'
import { ChevronDown, TrendingDown, TrendingUp } from 'lucide-react'
import { Button, cx } from './primitives'

/* ===== Card ===============================================================
   One container for every panel in the product: same radius, same border,
   same header rhythm, same optional hover lift.                           */

export function Card({
  children,
  className,
  padded,
  interactive,
  as: As = 'div',
  ...rest
}: {
  children: ReactNode
  className?: string
  /** apply the standard 16px inner padding directly on the card */
  padded?: boolean
  /** hover elevation — for cards that are links or buttons */
  interactive?: boolean
  as?: 'div' | 'section' | 'article'
} & React.HTMLAttributes<HTMLElement>) {
  return (
    <As
      className={cx(
        'surface overflow-hidden',
        padded && 'p-4',
        interactive &&
          'transition-[box-shadow,border-color,transform] duration-200 ease-[cubic-bezier(.4,0,.2,1)] hover:-translate-y-px hover:border-line-strong hover:shadow-md',
        className,
      )}
      {...rest}
    >
      {children}
    </As>
  )
}

export function CardHeader({
  title,
  subtitle,
  actions,
  icon,
  className,
  compact,
}: {
  title: ReactNode
  subtitle?: ReactNode
  actions?: ReactNode
  icon?: ReactNode
  className?: string
  compact?: boolean
}) {
  return (
    <div
      className={cx(
        'flex items-start gap-3 border-b border-line-subtle',
        compact ? 'px-3 py-2.5' : 'px-4 py-3',
        className,
      )}
    >
      {icon && (
        <span className="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-lg bg-subtle text-ink-secondary">
          {icon}
        </span>
      )}
      <div className="min-w-0 flex-1">
        <h2 className="truncate type-title">{title}</h2>
        {subtitle && <p className="mt-0.5 truncate type-caption text-ink-tertiary">{subtitle}</p>}
      </div>
      {actions && <div className="flex shrink-0 flex-wrap items-center gap-1.5">{actions}</div>}
    </div>
  )
}

export function CardBody({ children, className, padded = true }: { children: ReactNode; className?: string; padded?: boolean }) {
  return <div className={cx(padded && 'p-4', className)}>{children}</div>
}

export function CardFooter({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div className={cx('flex flex-wrap items-center gap-2 border-t border-line-subtle bg-subtle/50 px-4 py-3', className)}>
      {children}
    </div>
  )
}

/* ===== CollapsibleCard ====================================================
   Used to group long forms into sections that can be folded away.         */

export function CollapsibleCard({
  title,
  subtitle,
  icon,
  actions,
  defaultOpen = true,
  children,
  className,
}: {
  title: ReactNode
  subtitle?: ReactNode
  icon?: ReactNode
  actions?: ReactNode
  defaultOpen?: boolean
  children: ReactNode
  className?: string
}) {
  const [open, setOpen] = useState(defaultOpen)
  return (
    <Card className={className}>
      <div className="flex items-center gap-3 px-4 py-3">
        <button
          type="button"
          onClick={() => setOpen((v) => !v)}
          aria-expanded={open}
          className="flex min-w-0 flex-1 items-center gap-3 text-start"
        >
          <ChevronDown
            size={16}
            aria-hidden
            className={cx('shrink-0 text-ink-tertiary transition-transform duration-200', !open && '-rotate-90 rtl:rotate-90')}
          />
          {icon && <span className="shrink-0 text-ink-secondary">{icon}</span>}
          <span className="min-w-0">
            <span className="block truncate type-title">{title}</span>
            {subtitle && <span className="block truncate type-caption text-ink-tertiary">{subtitle}</span>}
          </span>
        </button>
        {actions && <div className="flex shrink-0 items-center gap-1.5">{actions}</div>}
      </div>
      {open && <div className="border-t border-line-subtle p-4">{children}</div>}
    </Card>
  )
}

/* ===== StatCard ===========================================================
   A KPI tile: icon, label, value, and an optional delta against the
   previous period.                                                        */

export function StatCard({
  icon,
  label,
  value,
  tone = '#3563f0',
  hint,
  delta,
  /** true when a rising number is bad (e.g. overdue tasks) */
  invertDelta,
  onClick,
  className,
}: {
  icon?: ReactNode
  label: ReactNode
  value: ReactNode
  tone?: string
  hint?: ReactNode
  delta?: number | null
  invertDelta?: boolean
  onClick?: () => void
  className?: string
}) {
  const showDelta = delta != null && Number.isFinite(delta) && delta !== 0
  const up = (delta ?? 0) > 0
  const good = invertDelta ? !up : up

  const inner = (
    <>
      <div className="flex items-start gap-3">
        {icon && (
          <span
            className="flex size-10 shrink-0 items-center justify-center rounded-xl"
            style={{ background: `color-mix(in srgb, ${tone} 12%, transparent)`, color: tone }}
            aria-hidden
          >
            {icon}
          </span>
        )}
        <div className="min-w-0 flex-1">
          <p className="truncate type-caption font-medium text-ink-tertiary">{label}</p>
          <p className="mt-0.5 type-display tabular leading-8">{value}</p>
        </div>
      </div>
      {(showDelta || hint) && (
        <div className="mt-2.5 flex items-center gap-2">
          {showDelta && (
            <span
              className={cx(
                'inline-flex items-center gap-0.5 rounded-full px-1.5 py-0.5 type-caption font-semibold tabular',
                good ? 'bg-success-subtle text-success-text' : 'bg-error-subtle text-error-text',
              )}
            >
              {up ? <TrendingUp size={11} aria-hidden /> : <TrendingDown size={11} aria-hidden />}
              {up ? '+' : ''}
              {delta}
            </span>
          )}
          {hint && <span className="min-w-0 truncate type-caption text-ink-tertiary">{hint}</span>}
        </div>
      )}
    </>
  )

  if (onClick)
    return (
      <button
        type="button"
        onClick={onClick}
        className={cx(
          'surface p-4 text-start transition-[box-shadow,border-color,transform] duration-200',
          'hover:-translate-y-px hover:border-line-strong hover:shadow-md focus-visible:outline-none focus-visible:focus-ring',
          className,
        )}
      >
        {inner}
      </button>
    )

  return <div className={cx('surface p-4', className)}>{inner}</div>
}

/* ===== PageHeader =========================================================
   Consistent title block for every screen.                                */

export function PageHeader({
  title,
  subtitle,
  actions,
  children,
  className,
}: {
  title: ReactNode
  subtitle?: ReactNode
  actions?: ReactNode
  /** filter bar or tabs rendered under the title */
  children?: ReactNode
  className?: string
}) {
  return (
    <div className={cx('space-y-3', className)}>
      <div className="flex flex-wrap items-start justify-between gap-x-3 gap-y-2">
        <div className="min-w-0 flex-1">
          <h1 className="type-heading">{title}</h1>
          {subtitle && <p className="mt-0.5 type-caption text-ink-tertiary">{subtitle}</p>}
        </div>
        {/* below `sm` the actions take their own full-width row rather than
            being squeezed next to a wrapping title */}
        {actions && <div className="flex w-full shrink-0 flex-wrap items-center gap-2 sm:w-auto">{actions}</div>}
      </div>
      {children}
    </div>
  )
}

/* ===== FilterBar ==========================================================
   The recurring "row of filters over a table" pattern.                    */

export function FilterBar({
  children,
  onReset,
  className,
}: {
  children: ReactNode
  onReset?: () => void
  className?: string
}) {
  return (
    <div className={cx('surface flex flex-wrap items-center gap-2 p-2.5', className)}>
      {children}
      {onReset && (
        <button
          type="button"
          onClick={onReset}
          className="ms-auto rounded-md px-2.5 py-1.5 type-button text-ink-tertiary transition-colors hover:bg-hover hover:text-ink"
        >
          ניקוי סינון
        </button>
      )}
    </div>
  )
}

/* ===== StickySaveBar ======================================================
   Footer for an edit surface: quiet until something actually changed. Lived
   inside the contractor detail screen and was imported out of it by the
   customer screens, which made Customers depend on Contractors for a
   primitive that belongs to neither.                                      */

export function StickySaveBar({
  dirty,
  saving,
  onSave,
  onReset,
}: {
  dirty: boolean
  saving?: boolean
  onSave: () => void
  onReset?: () => void
}) {
  return (
    <div
      className={cx(
        'sticky bottom-0 flex items-center gap-2 border-t border-line-subtle px-4 py-3 transition-colors',
        dirty ? 'bg-warning-subtle' : 'bg-subtle/50',
      )}
    >
      <span className="type-caption text-ink-tertiary">{dirty ? 'יש שינויים שלא נשמרו' : 'הכול שמור'}</span>
      <div className="ms-auto flex gap-2">
        {dirty && onReset && (
          <Button size="sm" variant="ghost" onClick={onReset}>
            ביטול שינויים
          </Button>
        )}
        <Button size="sm" variant="primary" loading={saving} disabled={!dirty} onClick={onSave}>
          שמירה
        </Button>
      </div>
    </div>
  )
}
