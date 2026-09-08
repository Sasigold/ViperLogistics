import { fmtMoney } from '../../../components/ui'
import { HandCoins } from '../../../components/ui/icons'
import { fmtDate } from '../../../lib/dates'
import { SeriesCard } from '../parts/SeriesCard'
import { TREND_FORMS, pickForm } from '../seriesOpts'
import type { SeriesRow } from '../seriesOpts'
import { useSection } from '../dashboardContext'
import { useDrill } from '../useDrill'
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

/** the progress-bar list is what this card always was, so it stays first */
export const SPEND_EVENT_FORMS = ['list', 'row', 'bar', 'donut', 'table'] as const

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
export function SpendByEventWidget({ height, opts }: WidgetProps) {
  const { data, isLoading } = useSection<Spend>('spend.summary')
  const go = useDrill({ to: 'event', id: '' })
  if (data === null) return null

  const rows: SeriesRow[] | undefined = data?.by_event.map((r) => ({
    key: r.id,
    label: r.label,
    value: Number(r.total),
    color: '#f59e0b',
    hint: `${fmtDate(r.event_date)} · ${fmtMoney(Number(r.total))}`,
  }))

  return (
    <SeriesCard
      title="הוצאה לפי אירוע"
      subtitle={data ? fmtMoney(Number(data.total)) : undefined}
      rows={rows}
      loading={isLoading && !data}
      form={pickForm(SPEND_EVENT_FORMS, opts)}
      height={height}
      opts={opts}
      seriesName="הוצאה"
      format={fmtMoney}
      fill="#f59e0b"
      emptyTitle="אין הוצאות בטווח"
      emptyDescription="אף משימה באירועים שלך לא תומחרה בטווח שנבחר"
      /* the row is an event and the event has a page — this is the click the
         card has been implying since it was written */
      onSelect={go && ((r) => go({ to: 'event', id: r.key }))}
    />
  )
}

export function SpendTrendWidget({ height, opts }: WidgetProps) {
  const { data, isLoading } = useSection<Spend>('spend.summary')
  /* The row key of a trend *is* a date, and the board opens on one. That makes
     every bucket on every trend card a link to the days behind it, for free. */
  const go = useDrill({ to: 'board' })
  if (data === null) return null

  const rows: SeriesRow[] | undefined = data?.by_bucket.map((r) => ({
    key: r.bucket,
    label: r.bucket,
    value: Number(r.total),
  }))

  return (
    <SeriesCard
      title="מגמת הוצאה"
      subtitle={data ? fmtMoney(Number(data.total)) : undefined}
      rows={rows}
      loading={isLoading && !data}
      form={pickForm(TREND_FORMS, opts)}
      height={height}
      opts={opts}
      seriesName="הוצאה"
      format={fmtMoney}
      fill="#f59e0b"
      timeAxis
      emptyTitle="אין הוצאות בטווח"
      emptyDescription="גרף מגמה נבנה מכמה תקופות — נסו טווח רחב יותר"
      onSelect={go && ((r) => go({ to: 'board', date: r.key }))}
    />
  )
}
