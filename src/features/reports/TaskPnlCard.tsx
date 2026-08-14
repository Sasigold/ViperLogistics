import { useQuery } from '@tanstack/react-query'
import { Card, CardBody, CardHeader, Skeleton } from '../../components/ui'
import { ICON, Percent, STROKE } from '../../components/ui/icons'
import { fmtMoney } from '../../components/ui/format'
import { PERM } from '../../lib/permissions'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import type { TaskPnlResult, TaskPnlRow } from './taskPnl'

/**
 * רווחיות המשימה, בתוך המגירה — קריאה בלבד.
 *
 * הכרטיס יושב ליד "מחיר ללקוח" כי שם כבר עומדים כששואלים "כמה הרווחתי על
 * זו". הוא קורא ל-`task_pnl` (0070) על יום המשימה בלבד, ומצייר את `rows[0]`.
 *
 * שני מצבים שבהם הוא **פשוט לא מופיע**, במכוון ולא כשגיאה: קורא בלי צרור
 * הרווח (ה-RPC מחזיר `rows: null`), ומשימה שאין עליה שורה. כרטיס ריק או
 * כרטיס "אין לך הרשאה" הם רעש במגירה שכבר צפופה.
 */
export function TaskPnlCard({ taskId, taskDate }: { taskId: string; taskDate: string }) {
  const has = useAuth((s) => s.has)
  // שער מקדים בלקוח כדי לא לירות בקשה שהשרת ידחה ממילא. השרת הוא הסמכות.
  const enabled = has(PERM.DASHBOARD_MARGIN) && !!taskId && !!taskDate

  const { data, isLoading } = useQuery({
    queryKey: ['task_pnl', 'one', taskId, taskDate],
    enabled,
    queryFn: async (): Promise<TaskPnlResult> => {
      const { data, error } = await supabase.rpc('task_pnl', {
        p_from: taskDate,
        p_to: taskDate,
        p_task_id: taskId,
      })
      if (error) throw error
      return data as TaskPnlResult
    },
  })

  if (!enabled) return null
  if (isLoading) return <Skeleton className="h-32 w-full" />
  const row: TaskPnlRow | undefined = data?.rows?.[0]
  if (!row) return null

  return (
    <Card>
      <CardHeader
        title="רווחיות המשימה"
        subtitle="מה שחויב מול מה שעלה בפועל"
        icon={<Percent size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody className="space-y-3">
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <Figure label="הכנסה" value={row.unpriced ? '—' : fmtMoney(row.revenue)} hint="לפי התכנון" />
          <Figure label="עלות קבלן" value={fmtMoney(row.contractor_cost)} />
          <Figure
            label="שכר + נטל"
            value={fmtMoney(row.payroll_with_employer)}
            hint={row.no_attendance ? 'לא הוחתם' : `${row.actual_workers} עובדים · ${row.actual_hours} ש׳`}
          />
          <Figure
            label="רווח גולמי"
            value={fmtMoney(row.gross)}
            tone={row.gross >= 0 ? 'text-success-text' : 'text-error-text'}
            hint={row.pct === null ? undefined : `${row.pct}%`}
          />
        </div>

        {/* מתוכנן מול בפועל — זה מה שמסביר את השוליים בלי להמציא מחיר נגדי */}
        <p className="rounded-lg bg-subtle/40 px-3 py-2 type-caption text-ink-secondary">
          תוכננו <span className="tabular font-semibold">{row.planned_worker_hours}</span> שעות-עובד
          {row.planned_workers != null && row.planned_hours != null && (
            <> ({row.planned_workers} × {row.planned_hours})</>
          )}
          {row.no_attendance ? (
            <> · טרם הוחתמה נוכחות</>
          ) : (
            <>
              {' '}· הוחתמו <span className="tabular font-semibold">{row.actual_hours}</span>
              {row.hours_delta !== 0 && (
                <span className={row.hours_delta > 0 ? 'text-error-text' : undefined}>
                  {' '}({row.hours_delta > 0 ? '+' : ''}
                  {row.hours_delta})
                </span>
              )}
            </>
          )}
        </p>

        {row.unrated_shifts > 0 && (
          <p className="type-caption text-warning-text">
            {row.unrated_shifts} משמרות ללא תעריף אינן נספרות בעלות
          </p>
        )}
        <p className="type-caption text-ink-tertiary">
          שיוך השכר משוער — עלות משמרת מתחלקת בין משימותיה לפי שעות המשימה. אינו כולל תקורה.
        </p>
      </CardBody>
    </Card>
  )
}

function Figure({
  label,
  value,
  hint,
  tone,
}: {
  label: string
  value: string
  hint?: string
  tone?: string
}) {
  return (
    <div>
      <span className="block type-caption text-ink-tertiary">{label}</span>
      <span className={`block tabular type-body font-semibold ${tone ?? ''}`}>{value}</span>
      {hint && <span className="block type-caption text-ink-tertiary">{hint}</span>}
    </div>
  )
}
