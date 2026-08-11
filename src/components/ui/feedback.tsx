import type { ReactNode } from 'react'
import { Loader2 } from 'lucide-react'
import { cx } from './primitives'
import { errorMessage } from '../../lib/errors'

/* ===== Spinner ============================================================ */

export function Spinner({ full, size = 24, className }: { full?: boolean; size?: number; className?: string }) {
  const el = <Loader2 className={cx('animate-spin text-primary', className)} size={size} aria-hidden />
  if (full)
    return (
      <div className="flex h-40 items-center justify-center" role="status" aria-label="טוען">
        {el}
      </div>
    )
  return el
}

/* ===== Skeleton ===========================================================
   Placeholders that match the shape of what's coming, so nothing reflows
   when the data lands.                                                     */

export function Skeleton({ className, style }: { className?: string; style?: React.CSSProperties }) {
  return <div className={cx('skeleton animate-shimmer', className)} style={style} aria-hidden />
}

export function SkeletonText({ lines = 3, className }: { lines?: number; className?: string }) {
  return (
    <div className={cx('space-y-2', className)} aria-hidden>
      {Array.from({ length: lines }).map((_, i) => (
        <Skeleton key={i} className={cx('h-3', i === lines - 1 ? 'w-2/3' : 'w-full')} />
      ))}
    </div>
  )
}

export function SkeletonCard({ className, lines = 2 }: { className?: string; lines?: number }) {
  return (
    <div className={cx('surface p-4', className)} aria-hidden>
      <div className="flex items-center gap-3">
        <Skeleton className="size-10 shrink-0 rounded-lg" />
        <div className="min-w-0 flex-1 space-y-2">
          <Skeleton className="h-3 w-24" />
          <Skeleton className="h-4 w-16" />
        </div>
      </div>
      {lines > 0 && <SkeletonText lines={lines} className="mt-4" />}
    </div>
  )
}

export function SkeletonTable({ rows = 8, cols = 5, className }: { rows?: number; cols?: number; className?: string }) {
  return (
    <div className={cx('w-full', className)} role="status" aria-label="טוען נתונים">
      <div className="flex gap-4 border-b border-line-subtle px-4 py-2.5">
        {Array.from({ length: cols }).map((_, i) => (
          <Skeleton key={i} className="h-3 flex-1" />
        ))}
      </div>
      {Array.from({ length: rows }).map((_, r) => (
        <div key={r} className="flex gap-4 border-b border-line-subtle px-4 py-3 last:border-0">
          {Array.from({ length: cols }).map((_, c) => (
            <Skeleton
              key={c}
              className="h-3 flex-1"
              // stagger the widths so it reads as data, not as a grid of bars
            />
          ))}
        </div>
      ))}
    </div>
  )
}

export function SkeletonList({ rows = 5, className }: { rows?: number; className?: string }) {
  return (
    <div className={cx('space-y-2', className)} aria-hidden>
      {Array.from({ length: rows }).map((_, i) => (
        <div key={i} className="flex items-center gap-3 rounded-lg border border-line-subtle p-3">
          <Skeleton className="size-8 shrink-0 rounded-full" />
          <div className="min-w-0 flex-1 space-y-2">
            <Skeleton className="h-3 w-1/3" />
            <Skeleton className="h-2.5 w-1/2" />
          </div>
          <Skeleton className="h-5 w-14 shrink-0 rounded-full" />
        </div>
      ))}
    </div>
  )
}

/* ===== Empty-state illustrations ==========================================
   Geometric line art built from the theme's own tokens — it reads as part of
   the product rather than as stock clipart, and it costs nothing to ship.  */

export type EmptyArt = 'box' | 'search' | 'calendar' | 'table' | 'people' | 'check' | 'alert'

function Illustration({ art }: { art: EmptyArt }) {
  const stroke = 'var(--vl-border-strong)'
  const fill = 'var(--vl-subtle)'
  const accent = 'var(--vl-primary)'
  return (
    <svg width="112" height="80" viewBox="0 0 112 80" fill="none" aria-hidden className="shrink-0">
      <ellipse cx="56" cy="70" rx="38" ry="5" fill={fill} />
      {art === 'box' && (
        <>
          <path d="M28 30 56 18l28 12v26L56 68 28 56V30Z" fill={fill} stroke={stroke} strokeWidth="1.5" strokeLinejoin="round" />
          <path d="M28 30l28 12 28-12M56 42v26" stroke={stroke} strokeWidth="1.5" strokeLinejoin="round" />
          <circle cx="84" cy="24" r="7" fill={accent} opacity=".16" />
        </>
      )}
      {art === 'search' && (
        <>
          <circle cx="50" cy="36" r="18" fill={fill} stroke={stroke} strokeWidth="1.5" />
          <path d="M63 49l12 12" stroke={stroke} strokeWidth="2.5" strokeLinecap="round" />
          <path d="M42 36h16M42 43h10" stroke={stroke} strokeWidth="1.5" strokeLinecap="round" />
          <circle cx="80" cy="22" r="6" fill={accent} opacity=".16" />
        </>
      )}
      {art === 'calendar' && (
        <>
          <rect x="30" y="20" width="52" height="44" rx="6" fill={fill} stroke={stroke} strokeWidth="1.5" />
          <path d="M30 32h52" stroke={stroke} strokeWidth="1.5" />
          <path d="M42 14v10M70 14v10" stroke={stroke} strokeWidth="2" strokeLinecap="round" />
          <rect x="40" y="40" width="10" height="8" rx="2" fill={accent} opacity=".22" />
          <rect x="56" y="40" width="10" height="8" rx="2" fill={stroke} opacity=".3" />
          <rect x="40" y="52" width="10" height="6" rx="2" fill={stroke} opacity=".2" />
        </>
      )}
      {art === 'table' && (
        <>
          <rect x="24" y="20" width="64" height="44" rx="6" fill={fill} stroke={stroke} strokeWidth="1.5" />
          <path d="M24 32h64M46 32v32M67 32v32" stroke={stroke} strokeWidth="1.5" />
          <rect x="30" y="38" width="10" height="4" rx="2" fill={accent} opacity=".25" />
          <rect x="52" y="38" width="10" height="4" rx="2" fill={stroke} opacity=".3" />
          <rect x="72" y="38" width="10" height="4" rx="2" fill={stroke} opacity=".3" />
        </>
      )}
      {art === 'people' && (
        <>
          <circle cx="44" cy="32" r="11" fill={fill} stroke={stroke} strokeWidth="1.5" />
          <path d="M26 62c0-9.4 8-17 18-17s18 7.6 18 17" fill={fill} stroke={stroke} strokeWidth="1.5" />
          <circle cx="72" cy="36" r="8" fill={fill} stroke={stroke} strokeWidth="1.5" />
          <path d="M60 62c0-7 5.4-13 12-13s12 6 12 13" fill={fill} stroke={stroke} strokeWidth="1.5" />
        </>
      )}
      {art === 'check' && (
        <>
          <circle cx="56" cy="40" r="22" fill={fill} stroke={stroke} strokeWidth="1.5" />
          <path d="M46 40l7 7 14-14" stroke="var(--vl-success)" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
        </>
      )}
      {art === 'alert' && (
        <>
          <path d="M56 18l24 42H32l24-42Z" fill={fill} stroke={stroke} strokeWidth="1.5" strokeLinejoin="round" />
          <path d="M56 34v12" stroke="var(--vl-warning)" strokeWidth="3" strokeLinecap="round" />
          <circle cx="56" cy="53" r="2" fill="var(--vl-warning)" />
        </>
      )}
    </svg>
  )
}

/* ===== EmptyState =========================================================
   `text` keeps the original one-liner call sites working; `title` +
   `description` + `action` produce the full treatment.                     */

export function EmptyState({
  text,
  title,
  description,
  art = 'box',
  action,
  compact,
  className,
}: {
  text?: string
  title?: string
  description?: ReactNode
  art?: EmptyArt
  action?: ReactNode
  compact?: boolean
  className?: string
}) {
  const heading = title ?? text ?? 'אין נתונים להצגה'
  return (
    <div
      className={cx(
        'flex flex-col items-center justify-center text-center',
        compact ? 'gap-2 px-4 py-8' : 'gap-3 px-6 py-14',
        className,
      )}
    >
      {!compact && <Illustration art={art} />}
      <div className="space-y-1">
        <p className="type-subtitle font-semibold text-ink">{heading}</p>
        {description && <p className="mx-auto max-w-sm type-caption text-ink-tertiary">{description}</p>}
      </div>
      {action && <div className="mt-1 flex flex-wrap items-center justify-center gap-2">{action}</div>}
    </div>
  )
}

/* ===== Inline states ====================================================== */

export function ErrorState({ error, onRetry }: { error: unknown; onRetry?: () => void }) {
  const msg = errorMessage(error)
  return (
    <EmptyState
      art="alert"
      title="לא הצלחנו לטעון את הנתונים"
      description={msg}
      action={
        onRetry && (
          <button
            onClick={onRetry}
            className="rounded-md border border-line bg-surface px-3 py-1.5 type-button hover:bg-subtle"
          >
            נסה שוב
          </button>
        )
      }
    />
  )
}
