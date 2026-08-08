import type { ReactNode } from 'react'
import { Link } from 'react-router'
import {
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  SkeletonList,
  StatusPill,
  fmtRelative,
} from '../../../components/ui'
import { fmtDate, fmtTime } from '../../../lib/dates'
import type { WorkBoardRow } from '../../../types/domain'

/** A compact list of tasks: colour bar, label, type, time or "updated", status. */
export function TaskListCard({
  title,
  subtitle,
  icon,
  tasks,
  loading,
  showDate,
  showUpdated,
  emptyTitle,
  emptyDescription,
  onOpen,
}: {
  title: ReactNode
  subtitle?: ReactNode
  icon?: ReactNode
  tasks: WorkBoardRow[]
  loading?: boolean
  showDate?: boolean
  showUpdated?: boolean
  emptyTitle: string
  emptyDescription?: string
  onOpen: (id: string) => void
}) {
  return (
    <Card>
      <CardHeader
        title={title}
        subtitle={subtitle}
        icon={icon}
        actions={
          <Link to="/board" className="rounded px-1.5 py-1 type-caption text-primary-text transition-colors hover:bg-hover">
            הכל
          </Link>
        }
      />
      <CardBody padded={false}>
        {loading ? (
          <div className="p-4">
            <SkeletonList rows={4} />
          </div>
        ) : tasks.length === 0 ? (
          <EmptyState compact art="check" title={emptyTitle} description={emptyDescription} />
        ) : (
          <ul>
            {tasks.map((t) => {
              const label = t.end_client_name || t.title || t.customer_name || t.task_type_name
              const time = fmtTime(t.onsite_start_time)
              return (
                <li key={t.id}>
                  <button
                    onClick={() => onOpen(t.id)}
                    className="flex w-full items-center gap-2.5 border-b border-line-subtle px-4 py-2.5 text-start transition-colors last:border-0 hover:bg-hover"
                  >
                    <span
                      className="h-8 w-1 shrink-0 rounded-full"
                      style={{ background: t.customer_color ?? 'var(--vl-border-strong)' }}
                      aria-hidden
                    />
                    <span className="min-w-0 flex-1">
                      <span className="flex items-center gap-1.5">
                        <span className="truncate type-body font-medium">{label}</span>
                      </span>
                      <span className="flex items-center gap-1.5 type-caption text-ink-tertiary">
                        <span className="truncate">{t.task_type_name}</span>
                        {showDate && <span className="tabular">· {fmtDate(t.task_date)}</span>}
                        {time && !showUpdated && (
                          <span className="tabular" dir="ltr">
                            · {time}
                          </span>
                        )}
                        {showUpdated && <span>· {fmtRelative(t.updated_at)}</span>}
                      </span>
                    </span>
                    <StatusPill color={t.status_color} className="shrink-0">
                      {t.status_name}
                    </StatusPill>
                  </button>
                </li>
              )
            })}
          </ul>
        )}
      </CardBody>
    </Card>
  )
}
