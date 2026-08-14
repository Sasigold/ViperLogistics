import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Button,
  DataTable,
  EmptyState,
  Input,
  MenuItem,
  PageHeader,
  Popover,
  Skeleton,
  StatCard,
  StatusPill,
  useToast,
} from '../../components/ui'
import {
  Banknote,
  ChevronDown,
  Download,
  FileSpreadsheet,
  HardHat,
  ICON,
  Percent,
  Printer,
  STROKE,
  Timer,
  TrendingUp,
  Wallet,
} from '../../components/ui/icons'
import { fmtDate } from '../../lib/dates'
import { errorMessage } from '../../lib/errors'
import { PERM } from '../../lib/permissions'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { RequirePermission } from '../auth/guards'
import { fmtMoney } from '../../components/ui/format'
import { RANGE_PRESETS, defaultRange } from '../dashboard/dashboardRange'
import { csvBlob } from './exportCsv'
import { downloadBlob } from './download'
import { buildTaskPnlExport, taskPnlLabel } from './taskPnl'
import type { DateRange } from '../dashboard/dashboardRange'
import type { TaskPnlMeta, TaskPnlResult, TaskPnlRow } from './taskPnl'

/**
 * רווחיות פר-משימה: כמה חויב על המשימה, וכמה היא עלתה בפועל.
 *
 * המסך כולו הוא `task_pnl` אחת (0070) — כל מספר, כולל החיסור, האחוז ונטל
 * המעביד, חושב בשרת. מה שהמסך מוסיף הוא סדר וגילוי נאות, ובראשו **הפער
 * שהמספרים לא יכולים להסתיר**: ההכנסה מתומחרת מהתכנון והעלות נמדדת מהבפועל.
 * לכן כל שורה נושאת גם מתוכנן-מול-בפועל בשעות, ולא רק כסף — זה מה שמסביר
 * למה השוליים זזו, בלי להמציא מחיר שמעולם לא הוצג ללקוח.
 *
 * הרווח הגרוע ביותר מגיע ראשון מהשרת, וזו ברירת המחדל של המיון: השאלה
 * ששאלו היא "איפה הפסדתי", לא "מי הכי גדול".
 */

export default function TaskPnlPage() {
  return (
    <RequirePermission perm={PERM.REPORTS_VIEW}>
      <TaskPnlScreen />
    </RequirePermission>
  )
}

function TaskPnlScreen() {
  const has = useAuth((s) => s.has)
  const toast = useToast()
  const canExport = has(PERM.REPORTS_EXPORT)
  const [range, setRange] = useState<DateRange>(defaultRange)

  const { data, isLoading, error } = useQuery({
    queryKey: ['task_pnl', range.from, range.to],
    queryFn: async (): Promise<TaskPnlResult> => {
      const { data, error } = await supabase.rpc('task_pnl', {
        p_from: range.from,
        p_to: range.to,
      })
      if (error) throw error
      return data as TaskPnlResult
    },
  })

  const setDates = (from: string, to: string) => {
    if (from && to && from <= to) setRange({ from, to })
  }

  const exportXlsx = async () => {
    if (!data) return
    try {
      const { writeDashboardExport } = await import('../dashboard/exportDashboard')
      downloadBlob(
        await writeDashboardExport(buildTaskPnlExport(range, data)),
        `רווחיות-משימות-${range.from}-${range.to}.xlsx`,
      )
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  const exportCsv = () => {
    if (!data) return
    const plan = buildTaskPnlExport(range, data)
    const detail = plan.sheets.find((s) => s.title === 'רווחיות לפי משימה')
    if (detail) downloadBlob(csvBlob(detail), `רווחיות-משימות-${range.from}-${range.to}.csv`)
  }

  const body = () => {
    if (error) return <EmptyState art="alert" title="שגיאה בטעינת הדוח" description={errorMessage(error)} />
    if (isLoading || !data) return <Skeleton className="h-72 w-full" />
    if (data.rows === null) {
      return (
        <EmptyState
          art="table"
          title="הנתון אינו זמין בהרשאות שלך"
          description="רווחיות פר-משימה דורשת את מפתחות ההכנסות, עלות הקבלנים ועלות השכר יחד, את הצפייה בכלל העובדים, והיקף נתונים מלא"
        />
      )
    }
    if (data.rows.length === 0) {
      return <EmptyState art="box" title="אין משימות בטווח שנבחר" />
    }
    return (
      <>
        <SummaryTiles data={data} />
        <TaskPnlTable rows={data.rows} meta={data.meta} />
      </>
    )
  }

  return (
    <div className="space-y-4">
      {/* כותרת מודפסת בלבד — הקובץ מסביר את עצמו גם בלי המסך */}
      <div className="hidden print:block">
        <h1 className="type-heading">רווחיות לפי משימה</h1>
        <p className="type-caption">
          {fmtDate(range.from)} – {fmtDate(range.to)}
        </p>
      </div>

      <div className="print:hidden">
        <PageHeader
          title="רווחיות לפי משימה"
          subtitle={`${fmtDate(range.from)} – ${fmtDate(range.to)} · מחיר שהוזמן מול עלות שהוחתמה, ללא תקורה`}
          actions={
            canExport && (
              <Popover
                trigger={(props) => (
                  <Button onClick={props.toggle} aria-expanded={props['aria-expanded']} aria-haspopup="menu" disabled={!data?.rows}>
                    <Download size={ICON.sm} strokeWidth={STROKE} />
                    ייצוא
                    <ChevronDown size={ICON.sm} strokeWidth={STROKE} />
                  </Button>
                )}
              >
                {(close) => (
                  <>
                    <MenuItem
                      icon={<FileSpreadsheet size={ICON.sm} strokeWidth={STROKE} />}
                      onClick={() => {
                        close()
                        void exportXlsx()
                      }}
                    >
                      Excel
                    </MenuItem>
                    <MenuItem
                      icon={<Download size={ICON.sm} strokeWidth={STROKE} />}
                      onClick={() => {
                        close()
                        exportCsv()
                      }}
                    >
                      CSV
                    </MenuItem>
                    <MenuItem
                      icon={<Printer size={ICON.sm} strokeWidth={STROKE} />}
                      onClick={() => {
                        close()
                        window.print()
                      }}
                    >
                      PDF / הדפסה
                    </MenuItem>
                  </>
                )}
              </Popover>
            )
          }
        >
          <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
            <div className="flex items-center gap-1.5">
              {RANGE_PRESETS.map((p) => (
                <Button
                  key={p.label}
                  size="sm"
                  variant="ghost"
                  onClick={() => {
                    const r = p.range()
                    setDates(r.from, r.to)
                  }}
                >
                  {p.label}
                </Button>
              ))}
            </div>
            <div className="flex items-center gap-1.5">
              <Input type="date" aria-label="מתאריך" value={range.from} onChange={(e) => setDates(e.target.value, range.to)} />
              <span className="text-ink-tertiary">–</span>
              <Input type="date" aria-label="עד תאריך" value={range.to} onChange={(e) => setDates(range.from, e.target.value)} />
            </div>
          </div>
        </PageHeader>
      </div>

      {body()}
    </div>
  )
}

function SummaryTiles({ data }: { data: TaskPnlResult }) {
  const s = data.summary
  if (!s) return null
  return (
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
      <StatCard
        icon={<Banknote size={ICON.xl} strokeWidth={STROKE} />}
        label="הכנסה"
        value={fmtMoney(s.revenue)}
        hint={`${s.tasks} משימות · לפי התכנון`}
      />
      <StatCard
        icon={<HardHat size={ICON.xl} strokeWidth={STROKE} />}
        label="עלות קבלנים"
        value={fmtMoney(s.contractor)}
        tone="#f59e0b"
      />
      <StatCard
        icon={<Wallet size={ICON.xl} strokeWidth={STROKE} />}
        label="שכר כולל נטל מעביד"
        value={fmtMoney(s.payroll_with_employer)}
        tone="#8b5cf6"
        hint={`${fmtMoney(s.payroll)} שכר + ${s.employer_pct}% נטל`}
      />
      <StatCard
        icon={s.pct === null ? <TrendingUp size={ICON.xl} strokeWidth={STROKE} /> : <Percent size={ICON.xl} strokeWidth={STROKE} />}
        label="רווח גולמי"
        value={fmtMoney(s.gross)}
        tone={s.gross >= 0 ? '#1fa189' : '#ef4444'}
        hint={s.pct === null ? 'ללא תקורה' : `${s.pct}% מההכנסה · ללא תקורה`}
      />
    </div>
  )
}

/** מתוכנן מול בפועל, בשעות-עובד. זה מה שמסביר את השוליים. */
function HoursCell({ r }: { r: TaskPnlRow }) {
  if (r.no_attendance) return <span className="type-caption text-ink-tertiary">לא הוחתם</span>
  const worse = r.hours_delta > 0
  return (
    <span className="tabular type-caption">
      {r.planned_worker_hours} → <span className="font-semibold">{r.actual_hours}</span>
      {r.hours_delta !== 0 && (
        <span className={worse ? 'text-error-text' : 'text-ink-tertiary'}>
          {' '}
          ({worse ? '+' : ''}
          {r.hours_delta})
        </span>
      )}
    </span>
  )
}

function TaskPnlTable({ rows, meta }: { rows: TaskPnlRow[]; meta: TaskPnlMeta }) {
  return (
    <div className="surface print-panel overflow-hidden">
      <DataTable<TaskPnlRow>
        rows={rows}
        getRowId={(r) => r.task_id}
        pageSize={25}
        zebra
        storageKey="task-pnl"
        defaultSort={{ key: 'gross', dir: 'asc' }}
        columns={[
          {
            key: 'task',
            header: 'משימה',
            fixed: true,
            sticky: true,
            render: (r) => (
              <span className="flex items-center gap-2">
                {r.customer_color && (
                  <span aria-hidden className="size-2.5 shrink-0 rounded-full" style={{ background: r.customer_color }} />
                )}
                <span className="min-w-0">
                  <span className="block truncate font-medium">{taskPnlLabel(r)}</span>
                  <span className="block truncate type-caption text-ink-tertiary">
                    {[r.customer_name, r.event_number].filter(Boolean).join(' · ') || r.task_type_name}
                  </span>
                </span>
              </span>
            ),
            sortValue: (r) => taskPnlLabel(r),
          },
          {
            key: 'task_date',
            header: 'תאריך',
            render: (r) => <span className="tabular type-caption">{fmtDate(r.task_date)}</span>,
            sortValue: (r) => r.task_date,
          },
          {
            key: 'status',
            header: 'סטטוס',
            render: (r) => (r.status_name ? <StatusPill color={r.status_color}>{r.status_name}</StatusPill> : null),
            sortValue: (r) => r.status_name,
          },
          {
            key: 'revenue',
            header: 'הכנסה',
            align: 'end',
            render: (r) =>
              r.unpriced ? (
                <span className="type-caption text-ink-tertiary">לא תומחר</span>
              ) : (
                <span className="tabular">{fmtMoney(r.revenue)}</span>
              ),
            sortValue: (r) => r.revenue,
          },
          {
            key: 'contractor_cost',
            header: 'עלות קבלן',
            align: 'end',
            render: (r) => <span className="tabular">{fmtMoney(r.contractor_cost)}</span>,
            sortValue: (r) => r.contractor_cost,
          },
          {
            key: 'payroll_with_employer',
            header: 'שכר + נטל',
            align: 'end',
            render: (r) => (
              <span className="tabular">
                {fmtMoney(r.payroll_with_employer)}
                {r.unrated_shifts > 0 && (
                  <span className="text-warning-text" title={`${r.unrated_shifts} משמרות ללא תעריף אינן נספרות`}>
                    {' '}
                    *
                  </span>
                )}
              </span>
            ),
            sortValue: (r) => r.payroll_with_employer,
          },
          {
            key: 'cost_total',
            header: 'עלות כוללת',
            align: 'end',
            render: (r) => <span className="tabular">{fmtMoney(r.cost_total)}</span>,
            sortValue: (r) => r.cost_total,
          },
          {
            key: 'gross',
            header: 'רווח גולמי',
            align: 'end',
            render: (r) => (
              <span className={`tabular font-semibold ${r.gross >= 0 ? 'text-success-text' : 'text-error-text'}`}>
                {fmtMoney(r.gross)}
              </span>
            ),
            sortValue: (r) => r.gross,
          },
          {
            key: 'pct',
            header: '% רווח',
            align: 'end',
            render: (r) =>
              r.pct === null ? (
                <span className="text-ink-tertiary">—</span>
              ) : (
                <span className={`tabular ${r.pct >= 0 ? 'text-success-text' : 'text-error-text'}`}>{r.pct}%</span>
              ),
            sortValue: (r) => r.pct,
          },
          {
            key: 'hours',
            header: 'שעות: תוכנן → בפועל',
            align: 'end',
            render: (r) => <HoursCell r={r} />,
            sortValue: (r) => r.hours_delta,
          },
        ]}
        mobileCard={(r) => (
          <div className="space-y-1.5">
            <div className="flex items-center gap-2">
              <span className="type-caption font-semibold tabular">{fmtDate(r.task_date)}</span>
              {r.status_name && (
                <StatusPill color={r.status_color} className="ms-auto shrink-0">
                  {r.status_name}
                </StatusPill>
              )}
            </div>
            <p className="truncate type-body font-semibold">{taskPnlLabel(r)}</p>
            {(r.customer_name || r.event_number) && (
              <p className="truncate type-caption text-ink-tertiary">
                {[r.customer_name, r.event_number].filter(Boolean).join(' · ')}
              </p>
            )}
            <div className="grid grid-cols-3 gap-2 border-t border-line-subtle pt-1.5">
              <span>
                <span className="block type-caption text-ink-tertiary">הכנסה</span>
                <span className="tabular type-caption">{r.unpriced ? '—' : fmtMoney(r.revenue)}</span>
              </span>
              <span>
                <span className="block type-caption text-ink-tertiary">עלות</span>
                <span className="tabular type-caption">{fmtMoney(r.cost_total)}</span>
              </span>
              <span>
                <span className="block type-caption text-ink-tertiary">רווח</span>
                <span className={`tabular type-caption font-semibold ${r.gross >= 0 ? 'text-success-text' : 'text-error-text'}`}>
                  {fmtMoney(r.gross)}
                  {r.pct !== null && ` · ${r.pct}%`}
                </span>
              </span>
            </div>
            <p className="flex items-center gap-1.5 type-caption text-ink-tertiary">
              <Timer size={ICON.xs} strokeWidth={STROKE} />
              <HoursCell r={r} />
            </p>
          </div>
        )}
      />
      <TaskPnlDisclosures meta={meta} />
    </div>
  )
}

/**
 * אותם גילויים שהקובץ המיוצא נושא, על המסך. הראשון הוא החשוב: שני בסיסי
 * המדידה. בלעדיו העמודה "רווח" נראית כמו מספר אחד, והיא חיסור בין שניים.
 */
function TaskPnlDisclosures({ meta }: { meta: TaskPnlMeta }) {
  const lines: string[] = []
  lines.push('ההכנסה היא המחיר שהוזמן, מחושב מהתכנון; העלות נמדדת מהשעות שהוחתמו בפועל')
  if (meta.estimated) {
    lines.push('שיוך השכר למשימה משוער — עלות המשמרת מחולקת בין משימותיה לפי שעות המשימה')
    if (meta.unallocated != null && Number(meta.unallocated) > 0) {
      lines.push(`${fmtMoney(Number(meta.unallocated))} שכר אינו משויך לאף משימה ואינו נספר כאן`)
    }
  }
  if (meta.unrated_shifts != null && Number(meta.unrated_shifts) > 0) {
    lines.push(`${meta.unrated_shifts} משמרות ללא תעריף אינן נספרות (מסומנות ב-*)`)
  }
  if (meta.tasks_no_attendance != null && Number(meta.tasks_no_attendance) > 0) {
    lines.push(`${meta.tasks_no_attendance} משימות ללא החתמה כלל`)
  }
  if (meta.unpriced_tasks != null && Number(meta.unpriced_tasks) > 0) {
    lines.push(`${meta.unpriced_tasks} משימות ללא תמחור`)
  }
  if (meta.truncated) lines.push('מוצגות השורות המובילות בלבד')
  if (meta.excludes_overhead) lines.push('אינו כולל תקורה')
  return <p className="border-t border-line-subtle px-4 py-2.5 type-caption text-ink-tertiary">{lines.join(' · ')}</p>
}
