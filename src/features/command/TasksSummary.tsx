import { AlertCircle, CalendarClock, CheckCheck, ICON, ListChecks, Percent, STROKE } from '../../components/ui/icons'
import { StatCard } from '../../components/ui'
import type { Mission, MissionsStats } from '../../types/domain'
import { fmtSpan, laneOf, oldestOverdueSeconds, onTimePct } from './warRoom'

/**
 * שורת המדדים של משימות הניהול (0232): פתוחות, באיחור (והוותיקה שבהן),
 * להיום, עמידה ביעדים ב-30 יום, והושלמו ב-7 הימים האחרונים. הכול נגזר מהלוח
 * (`missions_board`) ומהסטטיסטיקה (`missions_stats`) שהשרת מחזיר.
 */
export function TasksSummary({
  missions,
  stats,
  nowMs,
}: {
  missions: readonly Mission[]
  stats: MissionsStats | undefined
  nowMs: number
}) {
  const open = missions.filter((m) => m.status === 'open')
  const overdue = open.filter((m) => laneOf(m, nowMs) === 'overdue').length
  const today = open.filter((m) => laneOf(m, nowMs) === 'today').length
  const oldest = oldestOverdueSeconds(missions, nowMs)
  const pct = stats ? onTimePct(stats.done_30, stats.on_time_30) : null
  const doneWeek = stats ? stats.daily.slice(-7).reduce((s, d) => s + d.done, 0) : null

  const icon = (I: typeof ListChecks) => <I size={ICON.lg} strokeWidth={STROKE} />

  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
      <StatCard icon={icon(ListChecks)} label="פתוחות" value={open.length} tone="#3563f0" />
      <StatCard
        icon={icon(AlertCircle)}
        label="באיחור"
        value={overdue}
        tone={overdue ? '#dc2626' : '#16a34a'}
        hint={oldest !== null ? `הוותיקה: ${fmtSpan(oldest)}` : 'אין משימות באיחור'}
      />
      <StatCard icon={icon(CalendarClock)} label="להיום" value={today} tone="#f59e0b" />
      <StatCard
        icon={icon(Percent)}
        label="עמידה ביעדים · 30 יום"
        value={pct === null ? '—' : `${pct}%`}
        tone="#16a34a"
        hint={stats?.done_30 ? `${stats.on_time_30} מתוך ${stats.done_30} הושלמו בזמן` : 'עוד לא הושלמו משימות'}
      />
      <StatCard icon={icon(CheckCheck)} label="הושלמו · 7 ימים" value={doneWeek ?? '—'} tone="#0891b2" />
    </div>
  )
}
