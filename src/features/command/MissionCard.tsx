import { memo } from 'react'
import {
  AlarmClock,
  Check,
  ICON,
  MoreVertical,
  Pencil,
  Crosshair,
  RotateCcw,
  STROKE,
  Trash2,
} from '../../components/ui/icons'
import { Avatar, IconButton, MenuItem, MenuSeparator, Popover, cx } from '../../components/ui'
import type { Mission } from '../../types/domain'
import { PRIORITIES, RECURRENCE_LABELS, countdown } from './warRoom'

export interface MissionActions {
  onComplete: (m: Mission, el: HTMLElement) => void
  onReopen: (m: Mission) => void
  onSnooze: (m: Mission, minutes: number) => void
  onEdit: (m: Mission) => void
  onRemove: (m: Mission) => void
  onFocus: (m: Mission) => void
  onToggleStep: (stepId: string) => void
}

const SNOOZES = [
  { minutes: 60, label: 'שעה' },
  { minutes: 24 * 60, label: 'יום' },
  { minutes: 7 * 24 * 60, label: 'שבוע' },
]

/**
 * כרטיס משימה: כמה זמן נשאר עד היעד (או כמה עבר ממנו), עדיפות, חזרה, צעדים
 * ואחראי. משימה שעברה את היעד מסומנת במסגרת אדומה.
 */
export const MissionCard = memo(function MissionCard({
  mission: m,
  nowMs,
  showOwner,
  highlight,
  actions,
}: {
  mission: Mission
  nowMs: number
  showOwner: boolean
  highlight?: boolean
  actions: MissionActions
}) {
  const done = m.status === 'done'
  const cd = countdown(m.due_at, nowMs)
  const prio = PRIORITIES.find((p) => p.value === m.priority)!
  const stepsDone = m.steps.filter((s) => s.done).length

  return (
    <article
      id={`mission-${m.id}`}
      className={cx(
        'group relative rounded-xl border bg-surface p-3 transition-shadow',
        done
          ? 'border-line-subtle opacity-75'
          : cd.overdue
            ? 'border-error-border bg-[color-mix(in_srgb,var(--vl-error)_4%,var(--vl-surface))] shadow-xs hover:shadow-md'
            : 'border-line shadow-xs hover:shadow-md',
        highlight && 'ring-2 ring-primary',
      )}
    >
      <span
        aria-hidden
        className="absolute inset-y-2 start-0 w-1 rounded-full"
        style={{ background: done ? 'var(--vl-success)' : prio.color }}
      />
      <div className="flex items-start gap-2 ps-1.5">
        <button
          type="button"
          onClick={(e) => (done ? actions.onReopen(m) : actions.onComplete(m, e.currentTarget))}
          aria-label={done ? 'החזרה לפתוחות' : 'סימון כבוצעה'}
          className={cx(
            'mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-full border-2 transition-all',
            'focus-visible:outline-none focus-visible:focus-ring',
            done
              ? 'border-success bg-success text-white'
              : 'border-line-strong text-transparent hover:scale-110 hover:border-success hover:bg-success-subtle hover:text-success',
          )}
        >
          <Check size={ICON.sm} strokeWidth={3} />
        </button>

        <div className="min-w-0 flex-1">
          <button
            type="button"
            onClick={() => actions.onEdit(m)}
            className={cx(
              'block w-full text-start type-body font-semibold text-ink hover:text-primary-text',
              done && 'line-through decoration-ink-tertiary',
            )}
          >
            {m.title}
          </button>

          <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 type-caption">
            {done ? (
              <span className="font-semibold text-success-text">
                הושלמה{m.done_at ? ` · ${new Date(m.done_at).toLocaleDateString('he-IL', { day: 'numeric', month: 'numeric' })}` : ''}
              </span>
            ) : (
              <span
                className={cx(
                  'tabular font-bold',
                  cd.overdue ? 'text-error-text' : cd.soon ? 'text-warning-text' : 'text-ink-secondary',
                )}
              >
                {cd.text}
              </span>
            )}
            <span className="font-semibold" style={{ color: prio.color }}>
              P{m.priority}
            </span>
            {m.recurrence !== 'none' && <span className="text-ink-tertiary">↻ {RECURRENCE_LABELS[m.recurrence]}</span>}
            {m.postpone_count > 0 && (
              <span className="text-warning-text" title="כמה פעמים היעד נדחה">
                {m.postpone_count === 1 ? 'נדחתה פעם אחת' : `נדחתה ${m.postpone_count} פעמים`}
              </span>
            )}
          </div>

          {m.steps.length > 0 && (
            <div className="mt-2 space-y-1">
              <div className="h-1.5 overflow-hidden rounded-full bg-inset">
                <div
                  className="h-full rounded-full bg-success transition-all duration-500"
                  style={{ width: `${(100 * stepsDone) / m.steps.length}%` }}
                />
              </div>
              {!done && (
                <ul className="space-y-0.5">
                  {m.steps.map((s) => (
                    <li key={s.id}>
                      <label className="flex cursor-pointer items-center gap-1.5 type-caption text-ink-secondary">
                        <input
                          type="checkbox"
                          checked={s.done}
                          onChange={() => actions.onToggleStep(s.id)}
                          className="size-3.5 accent-[var(--vl-success)]"
                        />
                        <span className={cx(s.done && 'line-through text-ink-tertiary')}>{s.title}</span>
                      </label>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          )}
        </div>

        <div className="flex shrink-0 flex-col items-center gap-1">
          {showOwner && <Avatar name={m.owner_name} size="sm" />}
          <Popover
            trigger={(aria) => (
              <IconButton label="פעולות" size="sm" onClick={aria.toggle} aria-expanded={aria['aria-expanded']} aria-haspopup="menu">
                <MoreVertical size={ICON.sm} strokeWidth={STROKE} />
              </IconButton>
            )}
          >
            {(close) => {
              const run = (fn: () => void) => () => {
                close()
                fn()
              }
              return (
                <>
                  {!done && (
                    <>
                      <MenuItem icon={<Crosshair size={ICON.sm} />} onClick={run(() => actions.onFocus(m))}>
                        מצב פוקוס
                      </MenuItem>
                      {SNOOZES.map((s) => (
                        <MenuItem
                          key={s.minutes}
                          icon={<AlarmClock size={ICON.sm} />}
                          onClick={run(() => actions.onSnooze(m, s.minutes))}
                        >
                          לדחות ב{s.label}
                        </MenuItem>
                      ))}
                      <MenuSeparator />
                    </>
                  )}
                  {done && (
                    <MenuItem icon={<RotateCcw size={ICON.sm} />} onClick={run(() => actions.onReopen(m))}>
                      החזרה לפתוחות
                    </MenuItem>
                  )}
                  <MenuItem icon={<Pencil size={ICON.sm} />} onClick={run(() => actions.onEdit(m))}>
                    עריכה
                  </MenuItem>
                  <MenuItem icon={<Trash2 size={ICON.sm} />} danger onClick={run(() => actions.onRemove(m))}>
                    הסרה
                  </MenuItem>
                </>
              )
            }}
          </Popover>
        </div>
      </div>
    </article>
  )
})
