import { useQuery } from '@tanstack/react-query'
import { Link, useNavigate } from 'react-router'
import { addDays } from 'date-fns'
import {
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  SkeletonCard,
  SkeletonList,
  StatCard,
  StatusPill,
  fmtHoursShort,
  fmtMoney,
  fmtRelative,
} from '../../../components/ui'
import { Bell, CalendarClock, Clock, ICON, STROKE, Wallet } from '../../../components/ui/icons'
import { fmtDate, fmtTime, toISODate } from '../../../lib/dates'
import { supabase } from '../../../lib/supabase'
import { useAuth } from '../../../state/auth'
import { useMyClockStatus, useMyShifts } from '../../attendance/attendanceQueries'
import { useDashboard } from '../dashboardContext'
import type { WidgetProps } from '../dashboardTypes'
import type { AttendanceReport, Notification, WorkBoardRow } from '../../../types/domain'

/**
 * The personal group.
 *
 * Everything here reuses a hook that already exists for the screen it came
 * from — the clock's status, the shift list, the notification feed. A widget
 * that re-queried the same thing its own way would be a second answer to a
 * question the product has already answered once.
 */

/* ===== my next shifts ===================================================== */

export function MyNextShiftWidget(_props: WidgetProps) {
  const { today } = useDashboard()
  const to = toISODate(addDays(new Date(today), 14))
  const { data = [], isLoading } = useMyShifts(today, to)
  const next = data.slice(0, 4)

  return (
    <Card>
      <CardHeader
        title="המשמרות הקרובות שלי"
        icon={<CalendarClock size={ICON.md} strokeWidth={STROKE} />}
        actions={
          <Link to="/my/schedule" className="rounded px-1.5 py-1 type-caption text-primary-text hover:bg-hover">
            הכל
          </Link>
        }
      />
      <CardBody padded={false}>
        {isLoading ? (
          <div className="p-4">
            <SkeletonList rows={3} />
          </div>
        ) : next.length === 0 ? (
          <EmptyState compact art="check" title="אין משמרות בשבועיים הקרובים" />
        ) : (
          <ul>
            {next.map((s) => (
              <li
                key={`${s.work_date}-${s.seq}`}
                className="flex items-center gap-2.5 border-b border-line-subtle px-4 py-2.5 last:border-0"
              >
                <span
                  className="h-8 w-1 shrink-0 rounded-full"
                  style={{ background: s.customer_color ?? 'var(--vl-border-strong)' }}
                  aria-hidden
                />
                <span className="min-w-0 flex-1">
                  <span className="block truncate type-body font-medium">{s.label ?? 'משמרת'}</span>
                  <span className="block type-caption tabular text-ink-tertiary">{fmtDate(s.work_date)}</span>
                </span>
                <span className="shrink-0 type-caption tabular font-semibold" dir="ltr">
                  {fmtTime(s.shift_start?.slice(11, 16))}
                </span>
              </li>
            ))}
          </ul>
        )}
      </CardBody>
    </Card>
  )
}

/* ===== the clock ==========================================================
   Read-only on purpose. Clocking in has real rules behind it — a location
   gate, a "may I start early" gate — and the screen that owns them is
   /my/attendance. A second button here would be a second place those rules
   could drift out of. */

export function MyClockWidget(_props: WidgetProps) {
  const navigate = useNavigate()
  const { data, isLoading } = useMyClockStatus()
  if (isLoading && !data) return <SkeletonCard lines={0} />

  const open = data?.open_entry ?? null
  return (
    <StatCard
      icon={<Clock size={ICON.xl} strokeWidth={STROKE} />}
      label={open ? 'במשמרת מאז' : 'שעון נוכחות'}
      value={open ? fmtTime(String(open.clock_in_at).slice(11, 16)) : 'לא בעבודה'}
      tone={open ? '#22c55e' : '#64748b'}
      hint={open ? 'ליציאה — מסך השעון' : 'להחתמה — מסך השעון'}
      onClick={() => navigate('/my/attendance')}
    />
  )
}

/* ===== my hours and my pay ================================================
   Both read `attendance_report` with no filters: the server already narrows
   it to the caller's own rows, and the money is masked there too. Asking for
   "everyone" and being handed "me" is the same call the report screen makes.  */

function useMyReport(from: string, to: string) {
  const has = useAuth((s) => s.has)
  return useQuery({
    queryKey: ['attendance', 'report', 'me', from, to],
    enabled: has('attendance.view_own'),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('attendance_report', { p_from: from, p_to: to })
      if (error) throw error
      return data as AttendanceReport
    },
  })
}

export function MyHoursWidget(_props: WidgetProps) {
  const { range } = useDashboard()
  const me = useAuth((s) => s.me)
  const { data, isLoading } = useMyReport(range.from, range.to)
  if (isLoading && !data) return <SkeletonCard lines={0} />

  const mine = (data?.rows ?? []).filter((r) => r.profile_id === me?.profile.id && r.status === 'approved')
  const hours = mine.reduce((s, r) => s + Number(r.actual_hours ?? 0), 0)

  return (
    <StatCard
      icon={<Clock size={ICON.xl} strokeWidth={STROKE} />}
      label="השעות שלי בטווח"
      value={fmtHoursShort(hours)}
      tone="#0ea5e9"
      hint={`${mine.length} משמרות מאושרות`}
    />
  )
}

export function MyPayWidget(_props: WidgetProps) {
  const { range } = useDashboard()
  const me = useAuth((s) => s.me)
  const { data, isLoading } = useMyReport(range.from, range.to)
  if (isLoading && !data) return <SkeletonCard lines={0} />

  const mine = (data?.rows ?? []).filter((r) => r.profile_id === me?.profile.id && r.status === 'approved')
  // the server omits `total` from the row when the reader may not see money,
  // so an absent value here means "not for you" rather than zero
  const anyPay = mine.some((r) => r.pay?.total != null)
  if (!anyPay && mine.length > 0) return null
  const total = mine.reduce((s, r) => s + Number(r.pay?.total ?? 0), 0)

  return (
    <StatCard
      icon={<Wallet size={ICON.xl} strokeWidth={STROKE} />}
      label="השכר שלי בטווח"
      value={fmtMoney(total)}
      tone="#1fa189"
      hint="משמרות מאושרות בלבד"
    />
  )
}

/* ===== my tasks =========================================================== */

export function MyTasksWidget(_props: WidgetProps) {
  const { today, openTask } = useDashboard()
  const me = useAuth((s) => s.me)
  const { data = [], isLoading } = useQuery({
    queryKey: ['dashboard', 'my-tasks', today, me?.profile.id],
    enabled: !!me,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('work_board_view')
        .select('*')
        .gte('task_date', today)
        .order('task_date')
        .order('onsite_start_time', { nullsFirst: false })
        .limit(40)
      if (error) throw error
      return data as WorkBoardRow[]
    },
  })

  /* The view already carries the staffing, so one `.some()` answers this
     without a second query. Note the arrays are null — not empty — for a
     reader without `board.view_staffing`: the names are withheld server-side,
     and this widget correctly shows nothing rather than guessing. */
  const myId = me?.profile.id
  const mine = data
    .filter(
      (t) =>
        (t.workers ?? []).some((w) => w.profile_id === myId) ||
        (t.drivers ?? []).some((d) => d.profile_id === myId) ||
        t.team_lead_id === myId,
    )
    .slice(0, 8)

  return (
    <Card>
      <CardHeader title="המשימות שלי" subtitle="מהיום והלאה" icon={<Clock size={ICON.md} strokeWidth={STROKE} />} />
      <CardBody padded={false}>
        {isLoading ? (
          <div className="p-4">
            <SkeletonList rows={3} />
          </div>
        ) : mine.length === 0 ? (
          <EmptyState compact art="check" title="אין משימות ששובצת אליהן" />
        ) : (
          <ul>
            {mine.map((t) => (
              <li key={t.id}>
                <button
                  onClick={() => openTask?.(t.id)}
                  disabled={!openTask}
                  className="flex w-full items-center gap-2.5 border-b border-line-subtle px-4 py-2.5 text-start transition-colors last:border-0 hover:bg-hover disabled:cursor-default disabled:hover:bg-transparent"
                >
                  <span className="min-w-0 flex-1">
                    <span className="block truncate type-body font-medium">
                      {t.end_client_name || t.title || t.customer_name || t.task_type_name}
                    </span>
                    <span className="block type-caption tabular text-ink-tertiary">{fmtDate(t.task_date)}</span>
                  </span>
                  <StatusPill color={t.status_color} className="shrink-0">
                    {t.status_name}
                  </StatusPill>
                </button>
              </li>
            ))}
          </ul>
        )}
      </CardBody>
    </Card>
  )
}

/* ===== notifications ====================================================== */

export function MyNotificationsWidget(_props: WidgetProps) {
  const me = useAuth((s) => s.me)
  const { data = [], isLoading } = useQuery({
    queryKey: ['notifications', 'recent'],
    enabled: !!me,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('notifications')
        .select('*')
        .eq('muted', false)
        .order('created_at', { ascending: false })
        .limit(30)
      if (error) throw error
      return data as Notification[]
    },
  })

  const unread = data.filter((n) => !n.read_at).length
  const recent = data.slice(0, 5)

  return (
    <Card>
      <CardHeader
        title="ההתראות שלי"
        subtitle={unread > 0 ? `${unread} שלא נקראו` : 'הכול נקרא'}
        icon={<Bell size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody padded={false}>
        {isLoading ? (
          <div className="p-4">
            <SkeletonList rows={3} />
          </div>
        ) : recent.length === 0 ? (
          <EmptyState compact art="check" title="אין התראות" />
        ) : (
          <ul>
            {recent.map((n) => (
              <li
                key={n.id}
                className="flex items-start gap-2.5 border-b border-line-subtle px-4 py-2.5 last:border-0"
              >
                {!n.read_at && <span className="mt-1.5 size-2 shrink-0 rounded-full bg-primary" aria-hidden />}
                <span className="min-w-0 flex-1">
                  <span className="block truncate type-body">{n.title}</span>
                  <span className="block type-caption text-ink-tertiary">{fmtRelative(n.created_at)}</span>
                </span>
              </li>
            ))}
          </ul>
        )}
      </CardBody>
    </Card>
  )
}
