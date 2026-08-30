import { Card, CardBody, CardHeader, DataTable, EmptyState, fmtMoney } from '../../../components/ui'
import type { Column } from '../../../components/ui'
import { HandCoins, Percent } from '../../../components/ui/icons'
import { fmtMonth } from '../../../lib/dates'
import { parseISO } from 'date-fns'
import { useSection } from '../dashboardContext'
import type { WidgetProps } from '../dashboardTypes'
import { sectionKpi } from './financeWidgets'

/**
 * מה שהלקוח שואל על עצמו — חודש בחודשו.
 *
 * ‏0074 נתן ללקוח את "כמה הוצאתי" לטווח שנבחר. שתי שאלות נשארו בלי מסך:
 * "כמה אירועים היו לי החודש וכמה אני חייב לוייפר", ו"כמה אירועים, מה הסכום
 * הכולל, וכמה עמלה מגיעה לי". שתיהן אותה שאלה עם קונפיגורציה אחרת, ולכן
 * שלושת הווידג׳טים כאן קוראים **סקשן אחד** (`customer.monthly`) — שלושה
 * כרטיסים על המסך הם שאילתה אחת בשרת, וכולם נעלמים יחד כשהסקשן מחזיר `null`,
 * כלומר לכל מי שאינו לקוח.
 *
 * ‏**אין כאן שם לקוח, ולא יהיה.** מה שמכריע הוא `commission_pct` על שורת
 * הלקוח (0143): ריק ⇒ אין עמלה, הכרטיס אינו מצויר והעמודה אינה קיימת. לקוח
 * עמלה נוסף בעתיד הוא שורה במסד, לא שינוי בקובץ הזה.
 *
 * ‏**והכרטיסים והטבלה עונים על שתי שאלות שונות בכוונה:** הכרטיסים קוראים את
 * הטווח שנבחר (שאצל הלקוח נעול על החודש הנוכחי, 0144), והטבלה מציגה חלון של
 * שנים־עשר חודשים שאינו נחתך בו — אחרת "לחודש" היה שורה אחת.
 */

interface MonthRow {
  month: string
  events: number
  total: number
  commission: number | null
}

interface Monthly {
  events: number
  total: number
  /** null ללקוח שאין לו עמלה — לא אפס. ראו הערת העמודה ב-0143 §1 */
  commission: number | null
  commission_pct: number | null
  commission_min: number
  months: MonthRow[]
}

export const CustomerEventsTotalWidget = sectionKpi<Monthly>({
  section: 'customer.monthly',
  /* אותו מספר, ושתי משמעויות: לקוח שמבצע בעצמו חייב אותו לוייפר, ולקוח שמביא
     עבודה ומקבל עליה עמלה רואה בו את המחזור שהביא. */
  label: (v) => (v.commission_pct === null ? 'סכום לתשלום לוייפר' : 'סכום כולל של האירועים'),
  icon: HandCoins,
  tone: '#f59e0b',
  delta: true,
  select: (v) => Number(v.total),
  format: (v) => fmtMoney(v),
  hint: (v) => (v.events > 0 ? `${v.events} אירועים בטווח` : 'אין אירועים בטווח'),
})

/* ‏`select` מחזיר null ללקוח בלי עמלה, ו-`sectionKpi` אינו מצייר דבר — אותו
   חוזה בדיוק של "null = לא בשבילך" שהסקשן עצמו מקיים כלפי מי שאינו לקוח. */
export const CustomerCommissionWidget = sectionKpi<Monthly>({
  section: 'customer.monthly',
  label: 'עמלה',
  icon: Percent,
  tone: '#22c55e',
  delta: true,
  select: (v) => (v.commission === null ? null : Number(v.commission)),
  format: (v) => fmtMoney(v),
  hint: (v) => `${v.commission_pct}% מכל אירוע מעל ${fmtMoney(Number(v.commission_min))}`,
})

/** הפירוט שהכרטיסים אינם יכולים לתת: מה היה בכל חודש, ולא רק בטווח. */
export function CustomerMonthsWidget({ height }: WidgetProps) {
  const { data, isLoading } = useSection<Monthly>('customer.monthly')
  if (data === null) return null

  const rows = data?.months ?? []
  /* אותה הכרעה של `showMoney` בטבלת הלקוחות המובילים: עמודה שאין בה נתון
     נעלמת, ואינה מוצגת כטור של מקפים. */
  const showCommission = data?.commission !== null && data?.commission !== undefined

  const columns: Column<MonthRow>[] = [
    {
      key: 'month',
      header: 'חודש',
      sticky: true,
      render: (r) => fmtMonth(parseISO(r.month)),
      sortValue: (r) => r.month,
    },
    {
      key: 'events',
      header: 'אירועים',
      align: 'end',
      render: (r) => r.events,
      sortValue: (r) => Number(r.events),
    },
    {
      key: 'total',
      header: 'סכום',
      align: 'end',
      render: (r) => fmtMoney(Number(r.total)),
      sortValue: (r) => Number(r.total),
    },
    ...(showCommission
      ? [
          {
            key: 'commission',
            header: 'עמלה',
            align: 'end' as const,
            render: (r: MonthRow) => fmtMoney(Number(r.commission ?? 0)),
            sortValue: (r: MonthRow) => Number(r.commission ?? 0),
          },
        ]
      : []),
  ]

  return (
    <Card>
      <CardHeader title="אירועים לפי חודש" subtitle="שנים־עשר החודשים האחרונים" />
      <CardBody padded={false}>
        <DataTable
          rows={rows}
          columns={columns}
          getRowId={(r) => r.month}
          loading={isLoading && !data}
          dense
          maxHeight={height ? `${height}px` : undefined}
          defaultSort={{ key: 'month', dir: 'desc' }}
          empty={<EmptyState compact art="table" title="אין אירועים להצגה" />}
        />
      </CardBody>
    </Card>
  )
}
