import { useMemo } from 'react'
import { AvatarGroup, EmptyState, Tooltip } from '../../../components/ui'
import { fmtTime } from '../../../lib/dates'
import { shortAddress } from '../../../lib/address'
import { useIsPhone } from '../../../lib/useMediaQuery'
import type { WorkBoardRow } from '../../../types/domain'

/**
 * Today's tasks laid on an hour axis so overlaps and gaps are visible at a
 * glance. Everything is derived from onsite_start_time / hours_count — no new
 * data.
 */
export function DayTimeline({ tasks, onOpen }: { tasks: WorkBoardRow[]; onOpen: (id: string) => void }) {
  const timed = tasks.filter((t) => t.onsite_start_time)
  const untimed = tasks.filter((t) => !t.onsite_start_time)
  /* An hour axis needs horizontal room to mean anything: on a phone every bar
     collapses to a sliver and the ruler's labels collide. There the same tasks
     are simply listed in time order. */
  const isPhone = useIsPhone()

  const { startHour, endHour } = useMemo(() => {
    if (timed.length === 0) return { startHour: 6, endHour: 22 }
    let min = 24
    let max = 0
    for (const t of timed) {
      const s = Number(t.onsite_start_time!.slice(0, 2))
      const dur = t.hours_count ?? 2
      const e = t.onsite_end_time ? Number(t.onsite_end_time.slice(0, 2)) + 1 : s + Math.ceil(dur)
      min = Math.min(min, s)
      max = Math.max(max, e)
    }
    return { startHour: Math.max(0, min - 1), endHour: Math.min(24, Math.max(max + 1, min + 4)) }
  }, [timed])

  const span = Math.max(1, endHour - startHour)
  const pos = (time: string) => {
    const [h, m] = time.split(':').map(Number)
    return ((h + m / 60 - startHour) / span) * 100
  }

  if (tasks.length === 0)
    return <EmptyState compact art="check" title="אין משימות מתוזמנות היום" description="לוח נקי — אין מה לתאם" />

  const hours = Array.from({ length: span + 1 }, (_, i) => startHour + i)

  return (
    <div className="space-y-3">
      {timed.length > 0 && isPhone && (
        <ul className="space-y-1.5">
          {timed.map((t) => {
            const label = t.end_client_name || t.title || t.customer_name || t.task_type_name
            const team = [...(t.workers ?? []).map((w) => w.name), ...(t.drivers ?? []).map((d) => d.name)]
            return (
              <li key={t.id}>
                <button
                  onClick={() => onOpen(t.id)}
                  className="flex w-full items-center gap-2 rounded-lg p-2 text-start transition-colors hover:bg-hover"
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
        <div>
          {/* hour ruler */}
          <div className="relative mb-1.5 h-4">
            {hours.map((h) => (
              <span
                key={h}
                className="absolute -translate-x-1/2 type-caption tabular text-ink-tertiary rtl:translate-x-1/2"
                style={{ insetInlineStart: `${((h - startHour) / span) * 100}%` }}
              >
                {String(h).padStart(2, '0')}
              </span>
            ))}
          </div>

          <div className="max-h-64 space-y-1 overflow-y-auto pe-1">
            {timed.map((t) => {
              const start = pos(t.onsite_start_time!)
              const endTime = t.onsite_end_time
              const width = endTime
                ? Math.max(6, pos(endTime) - start)
                : Math.max(6, ((t.hours_count ?? 2) / span) * 100)
              const label = t.end_client_name || t.title || t.customer_name || t.task_type_name
              const team = [...(t.workers ?? []).map((w) => w.name), ...(t.drivers ?? []).map((d) => d.name)]
              return (
                <div key={t.id} className="relative h-8 rounded-md bg-subtle/50">
                  {/* hour gridlines */}
                  {hours.map((h) => (
                    <span
                      key={h}
                      aria-hidden
                      className="absolute inset-y-0 w-px bg-line-subtle"
                      style={{ insetInlineStart: `${((h - startHour) / span) * 100}%` }}
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
                      onClick={() => onOpen(t.id)}
                      className="absolute inset-y-0.5 flex items-center gap-1.5 overflow-hidden rounded px-1.5 text-start shadow-xs transition-[filter] hover:brightness-105 focus-visible:outline-none focus-visible:focus-ring"
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
      )}

      {untimed.length > 0 && (
        <div className="rounded-lg border border-dashed border-line p-2.5">
          <p className="mb-1.5 type-caption font-semibold text-ink-tertiary">ללא שעה ({untimed.length})</p>
          <div className="flex flex-wrap gap-1.5">
            {untimed.map((t) => (
              <button
                key={t.id}
                onClick={() => onOpen(t.id)}
                className="inline-flex items-center gap-1.5 rounded-full border border-line bg-surface px-2 py-0.5 type-caption transition-colors hover:bg-hover"
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
