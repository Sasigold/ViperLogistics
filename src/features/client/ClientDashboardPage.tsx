import { Link } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import { CalendarDays, CircleCheck, ClipboardList, ICON, PartyPopper, STROKE } from '../../components/ui/icons'
import {
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  SkeletonCard,
  StatCard,
  StatusPill,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { fmtDate } from '../../lib/dates'
import { RequirePermission } from '../auth/guards'
import { PERM } from '../../lib/permissions'
import type { CustomerDashboard } from '../../types/domain'

export default function ClientDashboardPage() {
  const { data: stats, isLoading } = useQuery({
    queryKey: ['client', 'dashboard'],
    queryFn: async () => {
      // SECURITY INVOKER on the RPC, so RLS scopes the numbers to this customer
      const { data, error } = await supabase.rpc('customer_dashboard', { p_from: null, p_to: null })
      if (error) throw error
      return data as CustomerDashboard
    },
  })

  return (
    <RequirePermission perm={PERM.DASHBOARD_VIEW}>
      {isLoading || !stats ? (
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <SkeletonCard key={i} lines={0} />
          ))}
        </div>
      ) : (
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <StatCard
              icon={<PartyPopper size={ICON.xl} strokeWidth={STROKE} />}
              label="אירועים"
              value={stats.events_count}
              hint={`${stats.events_done} הושלמו`}
            />
            <StatCard
              icon={<CalendarDays size={ICON.xl} strokeWidth={STROKE} />}
              label="אירועים קרובים"
              value={stats.events_upcoming}
            />
            <StatCard
              icon={<ClipboardList size={ICON.xl} strokeWidth={STROKE} />}
              label="משימות"
              value={stats.tasks_count}
            />
            <StatCard
              icon={<CircleCheck size={ICON.xl} strokeWidth={STROKE} />}
              label="משימות פתוחות"
              value={stats.tasks_open}
              tone="#f59e0b"
            />
          </div>

          <Card>
            <CardHeader title="האירועים הקרובים" icon={<CalendarDays size={ICON.md} strokeWidth={STROKE} />} />
            <CardBody padded={false}>
              {stats.next_events.length === 0 ? (
                <EmptyState art="calendar" title="אין אירועים קרובים" description="אירועים חדשים יופיעו כאן" />
              ) : (
                <ul>
                  {stats.next_events.map((e) => (
                    <li key={e.id} className="border-b border-line-subtle last:border-0">
                      <Link
                        to={`/client/events/${e.id}`}
                        className="flex items-center gap-3 px-4 py-2.5 transition-colors hover:bg-hover"
                      >
                        <span className="w-24 shrink-0 tabular type-body font-medium text-primary-text">
                          {fmtDate(e.event_date)}
                        </span>
                        <span className="min-w-0 flex-1 truncate">{e.end_client_name || 'ללא שם'}</span>
                        {e.event_number && <span className="shrink-0 tabular type-caption text-ink-tertiary">{e.event_number}</span>}
                      </Link>
                    </li>
                  ))}
                </ul>
              )}
            </CardBody>
          </Card>

          {stats.by_status.length > 0 && (
            <Card>
              <CardHeader title="משימות לפי סטטוס" icon={<ClipboardList size={ICON.md} strokeWidth={STROKE} />} />
              <CardBody className="flex flex-wrap gap-2">
                {stats.by_status.map((s) => (
                  <span key={s.name} className="flex items-center gap-1.5">
                    <StatusPill color={s.color}>{s.name}</StatusPill>
                    <span className="tabular type-caption text-ink-tertiary">{s.cnt}</span>
                  </span>
                ))}
              </CardBody>
            </Card>
          )}
        </div>
      )}
    </RequirePermission>
  )
}
