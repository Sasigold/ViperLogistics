import { useMemo } from 'react'
import { AvatarGroup, EmptyState, Tooltip, cx } from '../../../components/ui'
import { fmtTime } from '../../../lib/dates'
import { shortAddress } from '../../../lib/address'
import { useIsPhone } from '../../../lib/useMediaQuery'
import { useCrewVisibility } from '../../tasks/crewVisibility'
import type { WorkBoardRow } from '../../../types/domain'

/**
 * Tasks laid on a 24-hour axis so overlaps and gaps are visible at a
 * glance. Everything is derived from onsite_start_time / hours_count — no new
 * data.
 */
/* `onOpen` הוא אופציונלי: כרטיס המשימה סגור למי שאינו מנהל מערכת (0108),
   ובלעדיו הצ׳יפ נשאר תצוגה ולא כפתור. */
export function DayTimeline({
  tasks,
  onOpen,
  isToday,
}: {
  tasks: WorkBoardRow[]
  onOpen?: (id: string) => void
  isToday?: boolean
}) {
  const timed = tasks.filter((t) => t.onsite_start_time)
  const untimed = tasks.filter((t) => !t.onsite_start_time)
  /* An hour axis needs horizontal room to mean anything: on a phone every bar
     collapses to a sliver and the ruler's labels collide. There the same tasks
     are simply listed in time order. */
  const isPhone = useIsPhone()
  /* אותה הכרעה של הלו״ז ושל דף האירוע: מי שהצוות נסגר לו בקונפיגורציה של
     הלקוח (0109) אינו רואה שמות גם כשהם ראשי תיבות על ציר הזמן. */
  const showCrew = useCrewVisibility().names

  const span = 24

  const pos = (time: string) => {
    const [h, m] = time.split(':').map(Number)
    return (((h || 0) + (m || 0) / 60) / span) * 100
  }

  const nowPos = useMemo(() => {
    const now = new Date()
    return ((now.getHours() + now.getMinutes() / 60) / span) * 100
  }, [span])

  if (tasks.length === 0)
    return <EmptyState compact art="check" title="אין משימות מתוזמנות ליום זה" description="לוח נקי — אין מה לתאם" />

  const hours = Array.from({ length: span + 1 }, (_, i) => i)

  return (
    <div className="space-y-3">
      {timed.length > 0 && isPhone && (
        <ul className="space-y-1.5">
          {timed.map((t) => {
            const label = t.end_client_name || t.title || t.customer_name || t.task_type_name
            const team = showCrew
              ? [...(t.workers ?? []).map((w) => w.name), ...(t.drivers ?? []).map((d) => d.name)]
              : []
            return (
              <li key={t.id}>
                <button
                  onClick={() => onOpen?.(t.id)}
                  disabled={!onOpen}
                  className="flex w-full items-center gap-2 rounded-lg p-2 text-start transition-colors hover:bg-hover disabled:cursor-default disabled:hover:bg-transparent"
                >
                  <span
                    aria-hidden
                    className="h-8 w-1 shrink-0 rounded-full"
                    style={{ background: t.customer_color ?? '#64748b' }}
                  />
                  <span className="shrink-0 type-caption font-bold tabular" dir="ltr">
                    {fmtTime(t.onsite_start_time)}
                    {t.onsite_end_time && `–${fmtTime(t.onsite_end_time)}`}
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate type-body font-medium">{label}</span>
                    <span className="block truncate type-caption text-ink-tertiary">{t.task_type_name}</span>
                  </span>
                  {team.length > 0 && <AvatarGroup names={team} max={2} size="xs" />}
                </button>
              </li>
            )
          })}
        </ul>
      )}

      {timed.length > 0 && !isPhone && (
        <div className="overflow-x-auto pb-1">
          <div className="min-w-[700px]">
            {/* hour ruler */}
            <div className="relative mb-2 h-4 select-none">
              {hours.map((h) => {
                if (h % 2 !== 0) return null
                return (
                  <span
                    key={h}
                    className="absolute -translate-x-1/2 type-caption tabular text-ink-tertiary rtl:translate-x-1/2"
                    style={{ insetInlineStart: `${(h / span) * 100}%` }}
                  >
                    {String(h).padStart(2, '0')}:00
                  </span>
                )
              })}
            </div>

            <div className="relative max-h-64 space-y-1 overflow-y-auto pe-1">
              {/* current time indicator if viewing today */}
              {isToday && (
                <div
                  aria-hidden
                  className="pointer-events-none absolute inset-y-0 z-20 w-px bg-red-500/80"
                  style={{ insetInlineStart: `${nowPos}%` }}
                  title="השעה כעת"
                >
                  <div className="size-1.5 -translate-x-1/2 rounded-full bg-red-500 rtl:translate-x-1/2" />
                </div>
              )}

              {timed.map((t) => {
                const start = pos(t.onsite_start_time!)
                const endTime = t.onsite_end_time
                const width = endTime
                  ? Math.max(3, pos(endTime) - start)
                  : Math.max(3, ((t.hours_count ?? 2) / span) * 100)
                const label = t.end_client_name || t.title || t.customer_name || t.task_type_name
                const team = showCrew
                  ? [...(t.workers ?? []).map((w) => w.name), ...(t.drivers ?? []).map((d) => d.name)]
                  : []
                return (
                  <div key={t.id} className="relative h-8 rounded-md bg-subtle/50">
                    {/* hour gridlines */}
                    {hours.map((h) => (
                      <span
                        key={h}
                        aria-hidden
                        className={cx(
                          'absolute inset-y-0 w-px',
                          h % 2 === 0 ? 'bg-line-subtle' : 'bg-line-subtle/30'
                        )}
                        style={{ insetInlineStart: `${(h / span) * 100}%` }}
                      />
                    ))}
                    <Tooltip
                      content={
                        <span className="block space-y-0.5">
                          <span className="block font-bold">{label}</span>
                          <span className="block opacity-80">{t.task_type_name}</span>
                          <span className="block tabular opacity-80">
                            {fmtTime(t.onsite_start_time)}
                            {endTime && ` – ${fmtTime(endTime)}`}
                          </span>
                          {t.location_text && (
                            <span className="block opacity-70">{shortAddress(t.location_text)}</span>
                          )}
                        </span>
                      }
                    >
                      <button
                        onClick={() => onOpen?.(t.id)}
                        disabled={!onOpen}
                        className="absolute inset-y-0.5 z-10 flex items-center gap-1.5 overflow-hidden rounded px-1.5 text-start shadow-xs transition-[filter] hover:brightness-105 focus-visible:outline-none focus-visible:focus-ring disabled:cursor-default disabled:hover:brightness-100"
                        style={{
                          insetInlineStart: `${Math.max(0, Math.min(start, 97))}%`,
                          width: `${Math.min(width, 100 - Math.max(0, Math.min(start, 97)))}%`,
                          background: `color-mix(in srgb, ${t.customer_color ?? '#64748b'} 18%, transparent)`,
                          borderInlineStart: `3px solid ${t.customer_color ?? '#64748b'}`,
                        }}
                      >
                        <span className="truncate type-caption font-semibold text-ink">{label}</span>
                        {team.length > 0 && <AvatarGroup names={team} max={2} size="xs" />}
                      </button>
                    </Tooltip>
                  </div>
                )
              })}
            </div>
          </div>
        </div>
      )}

      {untimed.length > 0 && (
        <div className="rounded-lg border border-dashed border-line p-2.5">
          <p className="mb-1.5 type-caption font-semibold text-ink-tertiary">ללא שעה ({untimed.length})</p>
          <div className="flex flex-wrap gap-1.5">
            {untimed.map((t) => (
              <button
                key={t.id}
                onClick={() => onOpen?.(t.id)}
                  disabled={!onOpen}
                className="inline-flex items-center gap-1.5 rounded-full border border-line bg-surface px-2 py-0.5 type-caption transition-colors hover:bg-hover disabled:cursor-default disabled:hover:bg-surface"
              >
                <span className="size-1.5 rounded-full" style={{ background: t.customer_color ?? '#64748b' }} />
                {t.end_client_name || t.title || t.task_type_name}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
