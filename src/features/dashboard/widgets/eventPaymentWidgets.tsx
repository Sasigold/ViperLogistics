import { Bar, BarChart, Legend, Tooltip as RTooltip, XAxis, YAxis } from 'recharts'
import { parseISO } from 'date-fns'
import { SkeletonCard, StatCard, fmtMoney } from '../../../components/ui'
import { HandCoins, ICON, STROKE, XCircle } from '../../../components/ui/icons'
import { fmtMonth } from '../../../lib/dates'
import { ChartFrame } from '../parts/ChartFrame'
import { ChartTooltip } from '../parts/ChartTooltip'
import { useDashboard } from '../dashboardContext'
import { useDrill } from '../useDrill'
import { useEventPaymentsDashboard } from '../dashboardQueries'
import type { WidgetProps } from '../dashboardTypes'
import type { EventPaymentsDashboard } from '../../../types/domain'

/**
 * תשלומי אירועים בדשבורד (0203): כמה שולם וכמה עוד לא, מהאירועים שבטווח.
 *
 * הכרטיסים שואלים בעצמם (`event_payments_dashboard`) ואינם סקשן של
 * `dashboard_sections` — ראו dashboardContext.tsx: מה שווידג׳ט יכול לשאול
 * בעצמו, הוא שואל. הטווח הוא תאריך **האירוע**: "מהאירועים של החודש, כמה עוד
 * לא שולם", גם אם התשלום יגיע בחודש אחר.
 *
 * ‏**אין כאן שם לקוח.** הכותרת נבנית ממה שהשרת מחזיר — שמות הלקוחות שהדגל
 * `event_payments_enabled` דלוק אצלם — כך שלקוח אחד נקרא בשמו, ושניים נקראים
 * "תשלומי אירועים".
 */

const AXIS = { tick: { fontSize: 11, fill: 'var(--vl-text-tertiary)' }, axisLine: false, tickLine: false } as const

/* צבעי הגרף נבדקו בבודק הפלטה (כולל עיוורון צבעים, בבהיר ובכהה): ירוק מול
   אדום נכשל בדאוטן, ולכן שולם = טורקיז ועוד לא = כתום. */
const PAID = '#1fa189'
const UNPAID = '#ea580c'

function subject(v: EventPaymentsDashboard): string {
  return v.customers.length === 1 ? v.customers[0] : 'תשלומי אירועים'
}

function useRangePayments() {
  const { range } = useDashboard()
  return useEventPaymentsDashboard(range.from, range.to)
}

/** לחיצה על כרטיס פותחת את מסך התשלומים — "אילו אירועים" היא השאלה הבאה. */
function usePaymentsDrill() {
  const drill = useDrill({ to: 'payments' })
  return drill && (() => drill({ to: 'payments' }))
}

export function EventPaymentsPaidWidget(_props: WidgetProps) {
  const { data, isLoading } = useRangePayments()
  const onClick = usePaymentsDrill()
  if (isLoading && data === undefined) return <SkeletonCard lines={0} />
  if (!data) return null
  return (
    <StatCard
      icon={<HandCoins size={ICON.xl} strokeWidth={STROKE} />}
      label={`${subject(data)} — שולם`}
      value={fmtMoney(Number(data.paid))}
      tone={PAID}
      onClick={onClick}
      hint={
        data.events === 0
          ? 'אין אירועים בטווח'
          : `מתוך ${fmtMoney(Number(data.due))} · ${data.paid_events} מתוך ${data.events} אירועים שולמו במלואם`
      }
    />
  )
}

export function EventPaymentsUnpaidWidget(_props: WidgetProps) {
  const { data, isLoading } = useRangePayments()
  const onClick = usePaymentsDrill()
  if (isLoading && data === undefined) return <SkeletonCard lines={0} />
  if (!data) return null
  return (
    <StatCard
      icon={<XCircle size={ICON.xl} strokeWidth={STROKE} />}
      label={`${subject(data)} — עוד לא שולם`}
      value={fmtMoney(Number(data.unpaid))}
      tone={UNPAID}
      onClick={onClick}
      hint={data.open_events === 0 ? 'כל האירועים בטווח שולמו' : `${data.open_events} אירועים עם יתרה פתוחה`}
    />
  )
}

/** חודש בחודשו: שנים-עשר החודשים שמסתיימים בסוף הטווח, שולם מול עוד לא. */
export function EventPaymentsMonthlyWidget({ height }: WidgetProps) {
  const { data, isLoading } = useRangePayments()
  if (data === null) return null

  const rows = (data?.months ?? []).map((m) => ({
    name: fmtMonth(parseISO(m.month)),
    paid: Number(m.paid),
    unpaid: Number(m.unpaid),
  }))

  return (
    <ChartFrame
      title={data ? `${subject(data)} — תשלומים לפי חודש` : 'תשלומים לפי חודש'}
      subtitle="לפי חודש האירוע · שנים-עשר החודשים האחרונים"
      loading={isLoading && !data}
      empty={!rows.length}
      emptyTitle="אין אירועים לגבייה"
      height={height}
    >
      <BarChart data={rows} margin={{ top: 8, right: 8, bottom: 4, left: -12 }}>
        <XAxis dataKey="name" {...AXIS} />
        <YAxis {...AXIS} width={64} tickFormatter={(v: number) => String(Math.round(v / 1000)) + 'k'} />
        <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip format={(v) => fmtMoney(v)} />} />
        <Legend wrapperStyle={{ fontSize: 11 }} />
        <Bar
          dataKey="paid"
          name="שולם"
          stackId="p"
          fill={PAID}
          stroke="var(--vl-surface)"
          strokeWidth={2}
          maxBarSize={28}
        />
        <Bar
          dataKey="unpaid"
          name="עוד לא שולם"
          stackId="p"
          fill={UNPAID}
          stroke="var(--vl-surface)"
          strokeWidth={2}
          radius={[4, 4, 0, 0]}
          maxBarSize={28}
        />
      </BarChart>
    </ChartFrame>
  )
}
