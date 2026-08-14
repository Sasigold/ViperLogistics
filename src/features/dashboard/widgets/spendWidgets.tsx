import { Bar, BarChart, Tooltip as RTooltip, XAxis, YAxis } from 'recharts'
import { Card, CardBody, CardHeader, EmptyState, ProgressBar, Skeleton, fmtMoney } from '../../../components/ui'
import { HandCoins } from '../../../components/ui/icons'
import { fmtDate } from '../../../lib/dates'
import { ChartTooltip } from '../parts/ChartTooltip'
import { ChartFrame } from '../parts/ChartFrame'
import { useSection } from '../dashboardContext'
import type { WidgetProps } from '../dashboardTypes'
import { sectionKpi } from './financeWidgets'

/**
 * מה שהלקוח רואה בכספים — ורק הוא.
 *
 * ‏`task_pricing.price` הוא מספר אחד ששני צדדים קוראים הפוך: לנו הוא הכנסה,
 * ללקוח הוא מה ששילם. עד 0074 הלקוח קיבל את הצד שלנו — כרטיס בשם "הכנסות
 * בטווח" שהראה לו את החשבון של עצמו — פשוט מפני ש-`pricing.revenue` נגזר
 * מ-`pricing.view`, שהוא כן צריך. הכרטיסים כאן הם אותו נתון בשם הנכון.
 *
 * שלושתם קוראים סקשן אחד (`spend.summary`), ולכן שלושה כרטיסים על המסך הם
 * שאילתה אחת בשרת; ושלושתם נעלמים יחד כשהסקשן מחזיר `null`, כלומר לכל מי
 * שאינו לקוח.
 */

const AXIS = { tick: { fontSize: 11, fill: 'var(--vl-text-tertiary)' }, axisLine: false, tickLine: false } as const

interface Spend {
  total: number
  tasks: number
  by_event: { id: string; event_date: string; label: string; total: number }[]
  by_bucket: { bucket: string; total: number }[]
}

export const CustomerSpendWidget = sectionKpi<Spend>({
  section: 'spend.summary',
  label: 'הוצאה על אירועים',
  icon: HandCoins,
  tone: '#f59e0b',
  delta: true,
  // הוצאה שעולה אינה בשורה טובה, ולכן החץ הפוך משל כרטיס הכנסה
  invertDelta: true,
  select: (v) => Number(v.total),
  format: (v) => fmtMoney(v),
  hint: (v) => (v.tasks > 0 ? `${v.tasks} משימות מתומחרות בטווח` : 'אין משימות מתומחרות בטווח'),
})

/** על מה הלך הכסף. לרוב הלקוחות זו השאלה האמיתית, לא הסכום. */
export function SpendByEventWidget({ height }: WidgetProps) {
  const { data, isLoading } = useSection<Spend>('spend.summary')
  if (data === null) return null

  const rows = data?.by_event ?? []
  const max = rows.reduce((m, r) => Math.max(m, Number(r.total)), 0)

  return (
    <Card>
      <CardHeader title="הוצאה לפי אירוע" subtitle={data ? fmtMoney(Number(data.total)) : undefined} />
      <CardBody>
        {isLoading && !data ? (
          <Skeleton className="w-full" style={{ height }} />
        ) : rows.length === 0 ? (
          <EmptyState compact art="table" title="אין הוצאות בטווח" />
        ) : (
          <div className="space-y-2.5">
            {rows.map((r) => (
              <ProgressBar
                key={r.id}
                value={Number(r.total)}
                max={max}
                color="#f59e0b"
                label={r.label}
                hint={`${fmtDate(r.event_date)} · ${fmtMoney(Number(r.total))}`}
              />
            ))}
          </div>
        )}
      </CardBody>
    </Card>
  )
}

export function SpendTrendWidget({ height }: WidgetProps) {
  const { data, isLoading } = useSection<Spend>('spend.summary')
  if (data === null) return null

  const rows = data?.by_bucket ?? []
  return (
    <ChartFrame title="מגמת הוצאה" loading={isLoading && !data} empty={!rows.length} height={height}>
      <BarChart data={rows} margin={{ top: 8, right: 8, bottom: 4, left: -12 }}>
        <XAxis dataKey="bucket" {...AXIS} tickFormatter={(v: string) => fmtDate(v)} />
        <YAxis {...AXIS} width={64} tickFormatter={(v: number) => String(Math.round(v / 1000)) + 'k'} />
        <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip />} />
        <Bar dataKey="total" name="הוצאה" fill="#f59e0b" radius={[6, 6, 0, 0]} maxBarSize={40} />
      </BarChart>
    </ChartFrame>
  )
}
