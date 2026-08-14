import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip as RTooltip } from 'recharts'
import {
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  ProgressBar,
  Skeleton,
  SkeletonCard,
  Tooltip,
  fmtMoney,
} from '../../../components/ui'
import {
  Armchair,
  Banknote,
  HandCoins,
  ICON,
  Info,
  Receipt,
  STROKE,
  Truck,
  Wallet,
  XCircle,
} from '../../../components/ui/icons'
import { ChartTooltip } from '../parts/ChartTooltip'
import { useSection } from '../dashboardContext'
import type { WidgetProps } from '../dashboardTypes'
import { sectionKpi } from './financeWidgets'

/* ===== shapes the server sends (0069) ===================================== */

interface IncomeByCategory {
  rows: { id: string; name: string; family: 'furniture' | 'logistics'; color: string; total: number }[]
  furniture_total: number
  logistics_total: number
  total: number
}

interface Receivables {
  owed: number
  paid: number
  unpaid: number
  receipts_count: number
  by_customer: { name: string; color: string; owed: number; paid: number; unpaid: number }[] | null
}

interface ClientShare {
  total: number
  rows: { name: string; color: string; total: number }[] | null
}

interface PayrollEmployer {
  base: number
  pct: number
  total: number
  unrated_shifts: number
}

interface ProfitSummary {
  revenue: number
  payroll: number
  employer_pct: number
  payroll_with_employer: number
  contractor: number
  profit: number
  pct: number | null
  unrated_shifts: number
}

/* ===== KPI tiles ========================================================== */

export const FurnitureIncomeWidget = sectionKpi<IncomeByCategory>({
  section: 'income.by_category',
  label: 'הכנסות מריהוט',
  icon: Armchair,
  tone: '#8b5cf6',
  delta: true,
  select: (v) => Number(v.furniture_total),
  format: (v) => fmtMoney(v),
  hint: () => 'ריהוט ישן וחדש שהוזנו על אירועים',
})

export const LogisticsIncomeWidget = sectionKpi<IncomeByCategory>({
  section: 'income.by_category',
  label: 'הכנסות מלוגיסטיקה',
  icon: Truck,
  tone: '#14b8a6',
  delta: true,
  select: (v) => Number(v.logistics_total),
  format: (v) => fmtMoney(v),
  hint: () => 'לוגיסטיקה והובלות שהוזנו על אירועים',
})

export const PayrollEmployerWidget = sectionKpi<PayrollEmployer>({
  section: 'cost.payroll_employer',
  label: 'משכורות עם עלות מעביד',
  icon: Wallet,
  tone: '#8b5cf6',
  delta: true,
  select: (v) => Number(v.total),
  format: (v) => fmtMoney(v),
  hint: (v) => `בסיס ${fmtMoney(Number(v.base))} · עלות מעביד ${Number(v.pct)}%`,
})

export const ViperOwedWidget = sectionKpi<Receivables>({
  section: 'finance.receivables',
  label: 'סה״כ תשלום לוויפר',
  icon: Banknote,
  tone: '#a855f7',
  delta: true,
  select: (v) => Number(v.owed),
  format: (v) => fmtMoney(v),
  hint: () => 'כל ההכנסות בטווח — מה שהלקוחות חייבים',
})

export const ViperPaidWidget = sectionKpi<Receivables>({
  section: 'finance.receivables',
  label: 'סה״כ שולם',
  icon: Receipt,
  tone: '#22c55e',
  delta: true,
  select: (v) => Number(v.paid),
  format: (v) => fmtMoney(v),
  hint: (v) => (v.receipts_count > 0 ? `${v.receipts_count} תקבולים בטווח` : 'לא נרשמו תקבולים בטווח'),
})

export const ViperUnpaidWidget = sectionKpi<Receivables>({
  section: 'finance.receivables',
  label: 'לא שולם',
  icon: XCircle,
  tone: '#ef4444',
  invertDelta: true,
  delta: true,
  select: (v) => Number(v.unpaid),
  format: (v) => fmtMoney(v),
  hint: () => 'החוב בטווח פחות התקבולים שנרשמו',
})

export const ClientShareWidget = sectionKpi<ClientShare>({
  section: 'finance.client_share',
  label: 'הכנסות ללקוח',
  icon: HandCoins,
  tone: '#16a34a',
  delta: true,
  select: (v) => Number(v.total),
  format: (v) => fmtMoney(v),
  // ה-snapshot: החישוב לפי האחוז שנשמר על כל אירוע בעת ההזנה, לא האחוז של היום
  hint: (v) =>
    v.rows?.length
      ? v.rows.map((r) => `${r.name} ${fmtMoney(Number(r.total))}`).join(' · ')
      : 'חלק הלקוח לפי האחוזים שנשמרו על האירועים',
})

/* ===== income mix — the legacy pie ========================================
   Category×customer slices plus task pricing as "צוות <לקוח>". Same pairing
   as StatusBreakdownWidget: the donut answers "what shape", the bars answer
   "how much, exactly".                                                      */

export function IncomeMixWidget({ height }: WidgetProps) {
  const { data, isLoading } = useSection<{ label: string; color: string; total: number }[]>('income.mix')
  if (data === null) return null

  const rows = data ?? []
  const total = rows.reduce((s, r) => s + Number(r.total), 0)

  return (
    <Card>
      <CardHeader title="פילוח הכנסות" subtitle={total ? fmtMoney(total) : undefined} />
      <CardBody>
        {isLoading && !data ? (
          <Skeleton className="w-full" style={{ height }} />
        ) : rows.length === 0 ? (
          <EmptyState compact art="table" title="אין הכנסות בטווח" />
        ) : (
          <>
            <div className="relative">
              <ResponsiveContainer width="100%" height={180}>
                <PieChart>
                  <Pie
                    data={rows}
                    dataKey="total"
                    nameKey="label"
                    innerRadius={58}
                    outerRadius={82}
                    paddingAngle={2}
                    stroke="none"
                  >
                    {rows.map((r, i) => (
                      <Cell key={i} fill={r.color} />
                    ))}
                  </Pie>
                  <RTooltip content={<ChartTooltip />} />
                </PieChart>
              </ResponsiveContainer>
              <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
                <span className="type-title tabular leading-none">{fmtMoney(total)}</span>
                <span className="type-caption text-ink-tertiary">סה״כ הכנסות</span>
              </div>
            </div>
            <div className="mt-4 space-y-2.5">
              {rows.map((r) => (
                <ProgressBar
                  key={r.label}
                  value={Number(r.total)}
                  max={total}
                  color={r.color}
                  label={
                    <span className="flex items-center gap-1.5">
                      <span className="size-2 rounded-full" style={{ background: r.color }} />
                      {r.label}
                    </span>
                  }
                  hint={`${fmtMoney(Number(r.total))} · ${total > 0 ? Math.round((Number(r.total) / total) * 100) : 0}%`}
                />
              ))}
            </div>
          </>
        )}
      </CardBody>
    </Card>
  )
}

/* ===== profit summary — the legacy bottom line ============================
   Revenue (tasks + category income), minus payroll grossed up by the global
   employer-cost percent, minus contractor cost. Same disclosure posture as
   GrossMarginWidget: the number carries its own limits on the card.         */

const PROFIT_NOTE =
  'רווח לפני הוצאות = תמחור משימות + הכנסות קטגוריה שהוזנו על אירועים. ' +
  'עלות השכר היא משמרות מאושרות בלבד, מוכפלת באחוז עלות המעביד שבהגדרות. ' +
  'אינו כולל תקורה, רכב, ביטוח ומע״מ. ההכנסה מיוחסת לתאריך המשימה/האירוע.'

export function ProfitSummaryWidget(_props: WidgetProps) {
  const { data, prev, isLoading } = useSection<ProfitSummary>('finance.profit_summary')
  if (isLoading && data === undefined) return <SkeletonCard lines={3} />
  if (data === null || data === undefined) return null

  const profit = Number(data.profit)
  const before = prev ? Number(prev.profit) : null
  const lines = [
    { label: 'רווח לפני הוצאות', value: Number(data.revenue), tone: 'text-success-text' },
    {
      label: `עלות שכר (כולל מעביד ${Number(data.employer_pct)}%)`,
      value: -Number(data.payroll_with_employer),
      tone: 'text-ink-secondary',
    },
    { label: 'עלות קבלנים ומובילים', value: -Number(data.contractor), tone: 'text-ink-secondary' },
  ]

  return (
    <Card>
      <CardHeader
        title="רווח"
        subtitle="במתכונת המערכת הישנה"
        actions={
          <Tooltip content={<span className="block max-w-xs">{PROFIT_NOTE}</span>}>
            <span className="text-ink-tertiary" aria-label="מה נכלל בחישוב">
              <Info size={ICON.md} strokeWidth={STROKE} />
            </span>
          </Tooltip>
        }
      />
      <CardBody>
        <div className="flex items-baseline gap-2">
          <span className="type-display tabular leading-none">{fmtMoney(profit)}</span>
          {data.pct !== null && (
            <span className="type-body tabular text-ink-tertiary">{Number(data.pct).toFixed(1)}%</span>
          )}
        </div>
        {before !== null && (
          <p className="mt-1 type-caption text-ink-tertiary">מול {fmtMoney(before)} בתקופה הקודמת</p>
        )}

        <ul className="mt-4 space-y-1.5">
          {lines.map((l) => (
            <li key={l.label} className="flex items-center justify-between type-body">
              <span className="text-ink-secondary">{l.label}</span>
              <span className={`tabular ${l.tone}`}>{fmtMoney(l.value)}</span>
            </li>
          ))}
        </ul>

        {data.unrated_shifts > 0 && (
          <p className="mt-3 rounded-md bg-warning-subtle px-2 py-1.5 type-caption text-warning-text">
            {data.unrated_shifts} משמרות ללא תעריף אינן נספרות בעלות השכר
          </p>
        )}
      </CardBody>
    </Card>
  )
}
