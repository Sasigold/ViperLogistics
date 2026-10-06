import { Bar, BarChart, Legend, Tooltip as RTooltip, XAxis, YAxis } from 'recharts'
import { parseISO } from 'date-fns'
import type { ReactNode } from 'react'
import { Card, CardBody, CardHeader, SkeletonCard, cx, fmtMoney } from '../../../components/ui'
import { CircleCheck, HandCoins, ICON, Percent, STROKE, XCircle } from '../../../components/ui/icons'
import { PERM } from '../../../lib/permissions'
import { useAuth } from '../../../state/auth'
import { fmtMonth } from '../../../lib/dates'
import { ChartFrame } from '../parts/ChartFrame'
import { ChartTooltip } from '../parts/ChartTooltip'
import { useDashboard, useSection } from '../dashboardContext'
import { useDrill } from '../useDrill'
import { useEventPaymentsDashboard } from '../dashboardQueries'
import type { WidgetProps } from '../dashboardTypes'
import type { EventPaymentsDashboard } from '../../../types/domain'

/**
 * תשלומי אירועים בדשבורד (0205): כמה שולם וכמה עוד לא, מהאירועים שבטווח.
 *
 * הכרטיסים שואלים בעצמם (`event_payments_dashboard`) ואינם סקשן של
 * `dashboard_sections` — ראו dashboardContext.tsx: מה שווידג׳ט יכול לשאול
 * בעצמו, הוא שואל. הטווח הוא תאריך **האירוע**: "מהאירועים של החודש, כמה עוד
 * לא שולם", גם אם התשלום יגיע בחודש אחר.
 *
 * ‏**אין כאן שם לקוח של תשלומי האירועים.** הכותרת נבנית ממה שהשרת מחזיר —
 * שמות הלקוחות שהדגל `event_payments_enabled` דלוק אצלם — כך שלקוח אחד נקרא
 * בשמו, ושניים נקראים "תשלומי אירועים". התוויות "הכנסות לשיא עיצובים" ו"עמלה
 * לקיסר" בכרטיס המאוחד הן החריג: הן מתארות את שני הסקשנים של 0174, שהשמות
 * כתובים בהם בשרת, ועברו לכאן כמו שהיו על האריחים.
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

/* ===== הכרטיס המאוחד ======================================================
   ארבעה מספרים שהיו ארבעה אריחים — הכנסות לשיא עיצובים, עוד לא שולם, שולם
   ועמלה לקיסר — בכרטיס אחד. כאריחים הם עמדו בגובה הטבעי שלהם ליד פאנל גבוה,
   והשאירו מתחתם שטח ריק; ככרטיס הוא פאנל רגיל שממלא את השורה שלו.

   כל חצי מגיע ממקור משלו ונעלם לבד כשאין הרשאה: ההכנסות והעמלה מהסקשנים של
   `dashboard_sections` (‏0174, `finance.income_view`), התשלומים מ-
   `event_payments_dashboard` (‏0205). רק כששניהם ריקים הכרטיס כולו נעלם.   */

interface ClientShare {
  total: number
  furniture_new_share?: number
  furniture_old_share?: number
}

interface KeisarCommission {
  total: number
  events_count: number
  tasks_total: number
}

const SHARE_TONE = '#3563f0'
const COMMISSION_TONE = '#ef4444'

interface Metric {
  key: string
  label: string
  value: number
  tone: string
  icon: ReactNode
  hint: ReactNode
  onClick?: () => void
}

function MetricCell({ m }: { m: Metric }) {
  const inner = (
    <>
      <div className="flex items-start justify-between gap-2">
        <p className="min-w-0 flex-1 type-caption font-medium leading-snug break-words text-ink-tertiary">{m.label}</p>
        <span
          className="flex size-7 shrink-0 items-center justify-center rounded-lg"
          style={{ background: `color-mix(in srgb, ${m.tone} 12%, transparent)`, color: m.tone }}
          aria-hidden
        >
          {m.icon}
        </span>
      </div>
      <p
        className="type-display tabular font-bold leading-tight tracking-tight break-words text-ink text-[clamp(1.15rem,2.2vw,1.65rem)]"
        title={fmtMoney(m.value)}
      >
        {fmtMoney(m.value)}
      </p>
      <div className="mt-auto border-t border-line-subtle/40 pt-1.5 type-caption leading-snug break-words text-ink-tertiary">
        {m.hint}
      </div>
    </>
  )
  /* עמודה עם `gap-2`, והרמז ב-`mt-auto`: בתא שנמתח לגובה השורה הרמז יורד
     לתחתית, ובתא בגובהו הטבעי נשאר בכל זאת מרווח מעל הקו שלו. */
  const cell = 'flex min-w-0 flex-col gap-2 bg-surface p-3 text-start'
  return m.onClick ? (
    <button
      type="button"
      onClick={m.onClick}
      className={cx(cell, 'transition-colors hover:bg-subtle focus-visible:outline-none focus-visible:focus-ring')}
    >
      {inner}
    </button>
  ) : (
    <div className={cell}>{inner}</div>
  )
}

export function ClientSummaryWidget(_props: WidgetProps) {
  const has = useAuth((s) => s.has)
  const { range } = useDashboard()
  const canPay = has(PERM.FINANCE_EVENT_PAYMENTS_VIEW)
  const pay = useEventPaymentsDashboard(range.from, range.to, canPay)
  const share = useSection<ClientShare>('finance.client_share')
  const commission = useSection<KeisarCommission>('finance.keisar_commission')
  const onPayments = usePaymentsDrill()

  const payData = canPay && !pay.error ? pay.data : null
  if ((share.isLoading && share.data === undefined) || (canPay && pay.isLoading && pay.data === undefined))
    return <SkeletonCard lines={3} />

  /* הסדר קובע את הזוגות בתצוגת שניים-על-שניים: הכנסות ועמלה בשורה אחת,
     עוד לא שולם ושולם בשורה שמתחתיה. */
  const metrics: Metric[] = []
  if (share.data) {
    const v = share.data
    metrics.push({
      key: 'share',
      label: 'הכנסות לשיא עיצובים',
      value: Number(v.total),
      tone: SHARE_TONE,
      icon: <HandCoins size={ICON.lg} strokeWidth={STROKE} />,
      hint:
        v.furniture_new_share != null && v.furniture_old_share != null ? (
          <span className="flex flex-col gap-0.5">
            <span>חדש (80%): {fmtMoney(Number(v.furniture_new_share))}</span>
            <span>ישן (30%): {fmtMoney(Number(v.furniture_old_share))}</span>
          </span>
        ) : (
          '80% מריהוט חדש ו-30% מריהוט ישן'
        ),
    })
  }
  if (commission.data) {
    const v = commission.data
    metrics.push({
      key: 'commission',
      label: 'עמלה לקיסר',
      value: Number(v.total),
      tone: COMMISSION_TONE,
      icon: <Percent size={ICON.lg} strokeWidth={STROKE} />,
      hint:
        v.events_count > 0 ? (
          <span className="flex flex-col gap-0.5">
            <span>10% מעל 2,000 ₪ לאירוע</span>
            <span>
              {v.events_count} אירועים ({fmtMoney(Number(v.tasks_total))})
            </span>
          </span>
        ) : (
          '10% מאירועים שסך משימותיהם מעל 2,000 ₪'
        ),
    })
  }
  if (payData) {
    metrics.push(
      {
        key: 'unpaid',
        label: 'עוד לא שולם',
        value: Number(payData.unpaid),
        tone: UNPAID,
        icon: <XCircle size={ICON.lg} strokeWidth={STROKE} />,
        hint:
          payData.events === 0
            ? 'אין אירועים בטווח'
            : payData.open_events === 0
              ? 'כל האירועים בטווח שולמו'
              : `${payData.open_events} אירועים עם יתרה פתוחה`,
        onClick: onPayments,
      },
      {
        key: 'paid',
        label: 'שולם',
        value: Number(payData.paid),
        tone: PAID,
        icon: <CircleCheck size={ICON.lg} strokeWidth={STROKE} />,
        hint:
          payData.events === 0
            ? 'אין אירועים בטווח'
            : `מתוך ${fmtMoney(Number(payData.due))} · ${payData.paid_events} מתוך ${payData.events} אירועים שולמו במלואם`,
        onClick: onPayments,
      },
    )
  }
  if (metrics.length === 0) return null

  return (
    <Card>
      <CardHeader
        compact
        icon={<HandCoins size={ICON.md} strokeWidth={STROKE} />}
        title={payData ? subject(payData) : 'הכנסות ועמלות'}
      />
      {/* בלי כותרת משנה, בכוונה: שתי שורות תאים וכותרת אחת נכנסות בתקרה של
          פאנל `lg` (‏`panelMaxHeight`) בלי פס גלילה.
          קווי ההפרדה הם הרקע שמבצבץ ב-`gap-px` בין התאים. `auto-rows-fr`
          מחלק את הגובה שהשורה נותנת לכרטיס שווה בשווה בין שורות התאים, כך
          שגם כרטיס שנמתח לגובה השכן שלו אינו משאיר שטח ריק בתחתית. ארבעה
          בשורה רק כשהכרטיס רחב מאוד (רוחב מלא) — אחרת שניים על שניים. */}
      <CardBody padded={false} className="@container">
        <div className="grid h-full auto-rows-fr grid-cols-2 gap-px bg-line-subtle @6xl:grid-cols-4">
          {metrics.map((m) => (
            <MetricCell key={m.key} m={m} />
          ))}
        </div>
      </CardBody>
    </Card>
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
