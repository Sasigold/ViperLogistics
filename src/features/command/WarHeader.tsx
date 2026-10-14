import type { ReactNode } from 'react'
import { cx } from '../../components/ui'
import type { MissionsBoard, MissionsStats } from '../../types/domain'
import { DEFCON, defconLine, fmtDebt, levelOf } from './warRoom'
import type { Defcon } from './warRoom'

/**
 * הכותרת של משימות הניהול: מד האיום (5 עד 1), שעון החוב שרץ, המשפט של הרמה,
 * ושורת המדדים — פתוחות, באיחור, בזמן, רצף ו-XP עם טבעת הדרגה.
 */
export function WarHeader({
  board,
  stats,
  debt,
  scope,
}: {
  board: MissionsBoard
  stats: MissionsStats | undefined
  /** החוב החי בשניות */
  debt: number
  scope: string
}) {
  const level = board.defcon as Defcon
  const look = DEFCON[level]
  const alarm = level <= 2
  const open = board.missions.filter((m) => m.status === 'open').length
  const onTimePct = stats && stats.done_30 > 0 ? Math.round((100 * stats.on_time_30) / stats.done_30) : null
  const lvl = levelOf(stats?.xp_total ?? 0)

  return (
    <section
      className={cx(
        'relative overflow-hidden rounded-2xl border p-4 sm:p-5',
        alarm ? 'border-error-border bg-[color-mix(in_srgb,var(--vl-error)_7%,var(--vl-surface))]' : 'border-line bg-surface',
        level === 5 && 'wr-aurora',
      )}
    >
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        {/* מד האיום */}
        <div className="min-w-0 sm:flex-1">
          <p className="type-overline" style={{ color: look.color }}>
            DEFCON {level} · {look.name}
          </p>
          <div className="mt-2 flex gap-1" role="meter" aria-valuemin={1} aria-valuemax={5} aria-valuenow={level} aria-label="רמת האיום">
            {[5, 4, 3, 2, 1].map((n) => (
              <span
                key={n}
                className={cx('h-2.5 flex-1 rounded-full transition-colors duration-500', n >= level ? '' : 'bg-inset')}
                style={n >= level ? { background: DEFCON[n as Defcon].color } : undefined}
              />
            ))}
          </div>
          <p className={cx('mt-3 type-title', alarm ? 'text-error-text' : 'text-ink')}>
            {defconLine(level, board.overdue + open)}
          </p>
          <p className="mt-0.5 type-caption text-ink-tertiary">{scope}</p>
        </div>

        {/* שעון החוב */}
        <div className="sm:text-end">
          <p className="type-overline">{board.overdue > 0 ? 'סך האיחור' : 'חוב'}</p>
          {board.overdue > 0 ? (
            <p className="wr-debt mt-1 font-mono text-3xl font-black text-error sm:text-4xl" aria-live="off">
              {fmtDebt(debt)}
            </p>
          ) : (
            <p className="mt-1 font-mono text-3xl font-black text-success sm:text-4xl">00:00:00</p>
          )}
          <p className="type-caption text-ink-tertiary">
            {board.overdue > 0
              ? `${board.overdue} ${board.overdue === 1 ? 'משימה' : 'משימות'} באיחור — כל אחת מוסיפה שנייה בכל שנייה`
              : 'אפס חוב'}
          </p>
        </div>
      </div>

      {alarm && (
        <div className="wr-ticker mt-4 rounded-lg bg-error py-1.5 type-caption font-bold text-white" aria-hidden>
          <span>
            ⛔ {board.overdue} משימות באיחור · החוב: {fmtDebt(debt)} · {look.lines.join(' · ')} · סגור אחת עכשיו ⛔
          </span>
        </div>
      )}

      {/* המדדים */}
      <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-5">
        <Kpi label="פתוחות" value={open} />
        <Kpi label="באיחור" value={board.overdue} tone={board.overdue ? 'error' : 'success'} />
        <Kpi
          label="בזמן · 30 יום"
          value={onTimePct === null ? '—' : `${onTimePct}%`}
          tone={onTimePct === null ? undefined : onTimePct >= 90 ? 'success' : onTimePct >= 60 ? 'warning' : 'error'}
        />
        <Kpi
          label="רצף ימים נקיים"
          value={
            <span className="inline-flex items-center gap-1">
              <span className={cx(stats?.streak ? 'wr-flame' : 'opacity-30 grayscale')} aria-hidden>
                🔥
              </span>
              {stats?.streak ?? 0}
            </span>
          }
          hint={stats ? `שיא: ${stats.best_streak}` : undefined}
        />
        <div className="col-span-2 flex items-center gap-3 rounded-xl border border-line-subtle bg-subtle px-3 py-2 sm:col-span-1">
          <LevelRing progress={lvl.progress} index={lvl.index} />
          <div className="min-w-0">
            <p className="type-caption text-ink-tertiary">{lvl.title}</p>
            <p className="tabular text-lg font-extrabold text-ink">{(stats?.xp_total ?? 0).toLocaleString('he-IL')} XP</p>
            {lvl.next && (
              <p className="type-caption text-ink-tertiary">
                עוד {(lvl.next.xp - (stats?.xp_total ?? 0)).toLocaleString('he-IL')} ל{lvl.next.title}
              </p>
            )}
          </div>
        </div>
      </div>
    </section>
  )
}

function Kpi({
  label,
  value,
  tone,
  hint,
}: {
  label: string
  value: ReactNode
  tone?: 'success' | 'warning' | 'error'
  hint?: string
}) {
  return (
    <div className="rounded-xl border border-line-subtle bg-subtle px-3 py-2">
      <p className="type-caption text-ink-tertiary">{label}</p>
      <p
        className={cx(
          'tabular text-2xl font-extrabold',
          tone === 'success' && 'text-success-text',
          tone === 'warning' && 'text-warning-text',
          tone === 'error' && 'text-error-text',
          !tone && 'text-ink',
        )}
      >
        {value}
      </p>
      {hint && <p className="type-caption text-ink-tertiary">{hint}</p>}
    </div>
  )
}

/** טבעת ההתקדמות לדרגה הבאה, עם מספר הדרגה באמצע */
export function LevelRing({ progress, index, size = 48 }: { progress: number; index: number; size?: number }) {
  const r = size / 2 - 4
  const c = 2 * Math.PI * r
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="shrink-0 -rotate-90" aria-hidden>
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--vl-inset)" strokeWidth={5} />
      <circle
        cx={size / 2}
        cy={size / 2}
        r={r}
        fill="none"
        stroke="var(--vl-primary)"
        strokeWidth={5}
        strokeLinecap="round"
        strokeDasharray={c}
        strokeDashoffset={c * (1 - progress)}
        style={{ transition: 'stroke-dashoffset 900ms var(--vl-ease-out)' }}
      />
      <text
        x="50%"
        y="50%"
        dominantBaseline="central"
        textAnchor="middle"
        className="rotate-90 fill-[var(--vl-text)] text-sm font-black"
        style={{ transformOrigin: 'center' }}
      >
        {index + 1}
      </text>
    </svg>
  )
}
