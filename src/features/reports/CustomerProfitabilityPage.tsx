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
import { buildProfitabilityExport } from './profitability'
import type { DateRange } from '../dashboard/dashboardRange'
import type { ProfitMeta, ProfitResult, ProfitRow } from './profitability'

/**
 * רווחיות לקוחות: P&L פר לקוח — הכנסות, עלות קבלנים, שכר משויך, רווח גולמי.
 *
 * המסך כולו הוא `customer_profitability` אחת (0059): כל מספר, כולל החיסור
 * והאחוז שבכל שורה, חושב בשרת. מה שהמסך מוסיף הוא סדר, צבע — וגילוי נאות:
 * הקצאת השכר ללקוח היא משוערת, והרווח אינו כולל תקורה. שניהם נאמרים על
 * המסך ונוסעים בקובץ המיוצא.
 */

export default function CustomerProfitabilityPage() {
  return (
    <RequirePermission perm={PERM.REPORTS_VIEW}>
      <ProfitabilityScreen />
    </RequirePermission>
  )
}

function ProfitabilityScreen() {
  const has = useAuth((s) => s.has)
  const toast = useToast()
  const canExport = has(PERM.REPORTS_EXPORT)
  const [range, setRange] = useState<DateRange>(defaultRange)

  const { data, isLoading, error } = useQuery({
    queryKey: ['customer_profitability', range.from, range.to],
    queryFn: async (): Promise<ProfitResult> => {
      const { data, error } = await supabase.rpc('customer_profitability', {
        p_from: range.from,
        p_to: range.to,
      })
      if (error) throw error
      return data as ProfitResult
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
        await writeDashboardExport(buildProfitabilityExport(range, data)),
        `רווחיות-לקוחות-${range.from}-${range.to}.xlsx`,
      )
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  const exportCsv = () => {
    if (!data) return
    const plan = buildProfitabilityExport(range, data)
    const detail = plan.sheets.find((s) => s.title === 'רווחיות לפי לקוח')
    if (detail) downloadBlob(csvBlob(detail), `רווחיות-לקוחות-${range.from}-${range.to}.csv`)
  }

  const body = () => {
    if (error) return <EmptyState art="alert" title="שגיאה בטעינת הדוח" description={errorMessage(error)} />
    if (isLoading || !data) return <Skeleton className="h-72 w-full" />
    if (data.rows === null) {
      return (
        <EmptyState
          art="table"
          title="הנתון אינו זמין בהרשאות שלך"
          description="רווח גולמי דורש את מפתחות ההכנסות, עלות הקבלנים ועלות השכר יחד, והיקף נתונים מלא"
        />
      )
    }
    if (data.rows.length === 0) {
      return <EmptyState art="box" title="אין משימות ללקוחות בטווח שנבחר" />
    }
    return (
      <>
        <SummaryTiles data={data} />
        <ProfitTable rows={data.rows} meta={data.meta} />
      </>
    )
  }

  return (
    <div className="space-y-4">
      {/* כותרת מודפסת בלבד — הקובץ מסביר את עצמו גם בלי המסך */}
      <div className="hidden print:block">
        <h1 className="type-heading">רווחיות לקוחות</h1>
        <p className="type-caption">
          {fmtDate(range.from)} – {fmtDate(range.to)}
        </p>
      </div>

      <div className="print:hidden">
        <PageHeader
          title="רווחיות לקוחות"
          subtitle={`${fmtDate(range.from)} – ${fmtDate(range.to)} · הכנסות מול עלות קבלנים ושכר משויך, ללא תקורה`}
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

function SummaryTiles({ data }: { data: ProfitResult }) {
  const s = data.summary
  if (!s) return null
  return (
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
      <StatCard icon={<Banknote size={ICON.xl} strokeWidth={STROKE} />} label="הכנסות" value={fmtMoney(s.revenue)} />
      <StatCard
        icon={<HardHat size={ICON.xl} strokeWidth={STROKE} />}
        label="עלות קבלנים"
        value={fmtMoney(s.contractor)}
        tone="#f59e0b"
      />
      <StatCard
        icon={<Wallet size={ICON.xl} strokeWidth={STROKE} />}
        label="עלות שכר"
        value={s.payroll === null ? '—' : fmtMoney(s.payroll)}
        tone="#8b5cf6"
      />
      <StatCard
        icon={s.pct === null ? <TrendingUp size={ICON.xl} strokeWidth={STROKE} /> : <Percent size={ICON.xl} strokeWidth={STROKE} />}
        label="רווח גולמי"
        value={fmtMoney(s.gross)}
        tone={s.gross >= 0 ? '#1fa189' : '#ef4444'}
        hint={s.pct === null ? 'ללא תקורה' : `${s.pct}% מההכנסות · ללא תקורה`}
      />
    </div>
  )
}

function ProfitTable({ rows, meta }: { rows: ProfitRow[]; meta: ProfitMeta }) {
  return (
    <div className="surface print-panel overflow-hidden">
      <DataTable<ProfitRow>
        rows={rows}
        getRowId={(r) => r.name}
        pageSize={0}
        zebra
        defaultSort={{ key: 'revenue', dir: 'desc' }}
        columns={[
          {
            key: 'name',
            header: 'לקוח',
            fixed: true,
            sticky: true,
            render: (r) => (
              <span className="flex items-center gap-2 font-medium">
                {r.color && <span aria-hidden className="size-2.5 shrink-0 rounded-full" style={{ background: r.color }} />}
                {r.name}
              </span>
            ),
            sortValue: (r) => r.name,
          },
          {
            key: 'revenue',
            header: 'הכנסות',
            align: 'end',
            render: (r) => <span className="tabular">{fmtMoney(r.revenue)}</span>,
            sortValue: (r) => r.revenue,
          },
          {
            key: 'contractor',
            header: 'עלות קבלנים',
            align: 'end',
            render: (r) => <span className="tabular">{fmtMoney(r.contractor)}</span>,
            sortValue: (r) => r.contractor,
          },
          {
            key: 'payroll',
            header: 'שכר משויך (משוער)',
            align: 'end',
            render: (r) => <span className="tabular">{fmtMoney(r.payroll)}</span>,
            sortValue: (r) => r.payroll,
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
        ]}
      />
      <ProfitDisclosures meta={meta} />
    </div>
  )
}

/** אותם גילויים שהקובץ המיוצא נושא, על המסך — בסדר הזה */
function ProfitDisclosures({ meta }: { meta: ProfitMeta }) {
  const lines: string[] = []
  if (meta.estimated) {
    lines.push('שיוך השכר ללקוח משוער — עלות המשמרת מחולקת בין המשימות לפי שעות')
    if (meta.unallocated != null && Number(meta.unallocated) > 0) {
      lines.push(`${fmtMoney(Number(meta.unallocated))} שכר אינו משויך ללקוח`)
    }
  }
  if (meta.unrated_shifts != null && Number(meta.unrated_shifts) > 0) {
    lines.push(`${meta.unrated_shifts} משמרות ללא תעריף אינן נספרות`)
  }
  if (meta.truncated) lines.push('מוצגות השורות המובילות בלבד')
  if (meta.excludes_overhead) lines.push('אינו כולל תקורה')
  if (meta.scope_note) lines.push(meta.scope_note)
  if (lines.length === 0) return null
  return <p className="border-t border-line-subtle px-4 py-2.5 type-caption text-ink-tertiary">{lines.join(' · ')}</p>
}
