import { useRef } from 'react'
import type { ReactNode } from 'react'
import { cx } from './primitives'

export interface TabItem<K extends string = string> {
  key: K
  label: ReactNode
  icon?: ReactNode
  /** count or status shown after the label */
  badge?: ReactNode
  disabled?: boolean
}

/**
 * Underlined tab strip with roving-focus keyboard navigation.
 * Panels stay with the caller — every screen already renders
 * `{tab === 'x' && <XTab />}`.
 */
export function Tabs<K extends string>({
  items,
  value,
  onChange,
  className,
  size = 'md',
}: {
  items: readonly TabItem<K>[]
  value: K
  onChange: (key: K) => void
  className?: string
  size?: 'sm' | 'md'
}) {
  const ref = useRef<HTMLDivElement>(null)

  const move = (dir: 1 | -1) => {
    const enabled = items.filter((i) => !i.disabled)
    const idx = enabled.findIndex((i) => i.key === value)
    const next = enabled[(idx + dir + enabled.length) % enabled.length]
    if (!next) return
    onChange(next.key)
    ref.current?.querySelector<HTMLElement>(`[data-tab="${next.key}"]`)?.focus()
  }

  return (
    <div
      ref={ref}
      role="tablist"
      className={cx('flex flex-wrap items-center gap-1 border-b border-line', className)}
      onKeyDown={(e) => {
        // in RTL the visual "next" tab is the one to the left
        if (e.key === 'ArrowLeft') {
          e.preventDefault()
          move(1)
        } else if (e.key === 'ArrowRight') {
          e.preventDefault()
          move(-1)
        }
      }}
    >
      {items.map((t) => {
        const active = t.key === value
        return (
          <button
            key={t.key}
            data-tab={t.key}
            role="tab"
            type="button"
            aria-selected={active}
            tabIndex={active ? 0 : -1}
            disabled={t.disabled}
            onClick={() => onChange(t.key)}
            className={cx(
              'relative -mb-px inline-flex items-center gap-1.5 border-b-2 type-button transition-colors duration-150',
              'focus-visible:outline-none focus-visible:bg-hover focus-visible:rounded-t-md',
              size === 'sm' ? 'px-3 py-1.5' : 'px-4 py-2.5',
              'disabled:pointer-events-none disabled:opacity-45',
              active
                ? 'border-primary text-primary-text'
                : 'border-transparent text-ink-tertiary hover:border-line-strong hover:text-ink',
            )}
          >
            {t.icon && <span className="shrink-0">{t.icon}</span>}
            {t.label}
            {t.badge != null && (
              <span
                className={cx(
                  'ms-0.5 inline-flex h-4 min-w-4 items-center justify-center rounded-full px-1 type-caption font-bold tabular',
                  active ? 'bg-primary-subtle text-primary-text' : 'bg-subtle text-ink-tertiary',
                )}
              >
                {t.badge}
              </span>
            )}
          </button>
        )
      })}
    </div>
  )
}

/**
 * Compact segmented control — for switching a view mode inside a toolbar
 * rather than switching whole pages.
 */
export function SegmentedControl<K extends string>({
  items,
  value,
  onChange,
  className,
}: {
  items: readonly { key: K; label: ReactNode; icon?: ReactNode }[]
  value: K
  onChange: (key: K) => void
  className?: string
}) {
  return (
    <div className={cx('inline-flex shrink-0 items-center gap-0.5 rounded-lg bg-subtle p-0.5', className)} role="group">
      {items.map((it) => {
        const active = it.key === value
        return (
          <button
            key={it.key}
            type="button"
            aria-pressed={active}
            onClick={() => onChange(it.key)}
            className={cx(
              'inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 type-caption font-semibold transition-all duration-150',
              'focus-visible:outline-none focus-visible:focus-ring',
              active ? 'bg-surface text-ink shadow-xs' : 'text-ink-tertiary hover:text-ink',
            )}
          >
            {it.icon}
            {it.label}
          </button>
        )
      })}
    </div>
  )
}
