import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { CalendarDays, Clock, ICON, MapPin, STROKE } from '../../components/ui/icons'
import {
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  Field,
  FilterBar,
  Input,
  PageHeader,
  SkeletonList,
  StatusPill,
  Tooltip,
  cx,
  relativeDayLabel,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { fmtDate, fmtTime } from '../../lib/dates'
import { RequirePermission } from '../auth/guards'
import { PERM } from '../../lib/permissions'
import type { WorkBoardRow } from '../../types/domain'

/**
 * work_board_view is security_invoker, so the rows are already the client's.
 * The staff board is not reused: it renders contractor delegation, contractor
 * pricing and internal worker assignments. Those columns come back RLS-nulled
 * for a client, which is safe but reads as a broken screen — and the board's
 * inline editors would fail on save, since tasks_update excludes customer_user.
 */
export default function ClientTasksPage() {
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')

  const { data: tasks = [], isLoading } = useQuery({
    queryKey: ['client', 'tasks', from, to],
    queryFn: async () => {
      let q = supabase.from('work_board_view').select('*').order('task_date', { ascending: false }).limit(500)
      if (from) q = q.gte('task_date', from)
      if (to) q = q.lte('task_date', to)
      const { data, error } = await q
      if (error) throw error
      return data as WorkBoardRow[]
    },
  })

  return (
    <RequirePermission perm={PERM.TASKS_VIEW}>
      <div className="space-y-4">
        <PageHeader title="המשימות שלי" subtitle={isLoading ? 'טוען...' : `${tasks.length} משימות`}>
          <FilterBar
            onReset={
              from || to
                ? () => {
                    setFrom('')
                    setTo('')
                  }
                : undefined
            }
          >
            <Field label="מתאריך" className="w-40">
              <Input type="date" inputSize="sm" value={from} onChange={(e) => setFrom(e.target.value)} />
            </Field>
            <Field label="עד תאריך" className="w-40">
              <Input type="date" inputSize="sm" value={to} onChange={(e) => setTo(e.target.value)} />
            </Field>
          </FilterBar>
        </PageHeader>

        {isLoading ? (
          <SkeletonList rows={4} />
        ) : tasks.length === 0 ? (
          <Card>
            <EmptyState
              art="calendar"
              title="אין משימות בטווח"
              description="משימות ההקמה, הפירוק וההובלות של האירועים שלך יופיעו כאן"
            />
          </Card>
        ) : (
          <div className="space-y-3">
            {tasks.map((t) => (
              <ClientTaskCard key={t.id} task={t} />
            ))}
          </div>
        )}
      </div>
    </RequirePermission>
  )
}

function ClientTaskCard({ task }: { task: WorkBoardRow }) {
  const dayLabel = relativeDayLabel(task.task_date)
  return (
    <Card>
      <CardHeader
        title={
          <span className="flex flex-wrap items-center gap-2">
            {task.title || task.task_type_name}
            <StatusPill color={task.status_color}>{task.status_name}</StatusPill>
          </span>
        }
        subtitle={
          <span className="flex flex-wrap items-center gap-x-2">
            <span className="tabular">{fmtDate(task.task_date)}</span>
            {dayLabel && <span className="font-semibold text-primary-text">· {dayLabel}</span>}
            {task.end_client_name && <span>· {task.end_client_name}</span>}
          </span>
        }
      />
      <CardBody>
        <dl className="grid grid-cols-2 gap-3 sm:grid-cols-3">
          <Fact icon={<MapPin size={ICON.sm} strokeWidth={STROKE} />} label="מיקום" value={task.location_text || '—'} />
          <Fact
            icon={<Clock size={ICON.sm} strokeWidth={STROKE} />}
            label="שעה בשטח"
            value={fmtTime(task.onsite_start_time) || '—'}
            ltr
          />
          <Fact
            icon={<CalendarDays size={ICON.sm} strokeWidth={STROKE} />}
            label="אופן ביצוע"
            value={task.execution_method_name || '—'}
          />
        </dl>
      </CardBody>
    </Card>
  )
}

function Fact({
  icon,
  label,
  value,
  ltr,
}: {
  icon: React.ReactNode
  label: string
  value: string
  ltr?: boolean
}) {
  return (
    <div className="min-w-0">
      <dt className="flex items-center gap-1 type-caption text-ink-tertiary">
        <span className="shrink-0" aria-hidden>
          {icon}
        </span>
        {label}
      </dt>
      <Tooltip content={value.length > 24 ? value : ''}>
        <dd className={cx('mt-0.5 truncate type-body font-medium', ltr && 'tabular')} dir={ltr ? 'ltr' : undefined}>
          {value}
        </dd>
      </Tooltip>
    </div>
  )
}
