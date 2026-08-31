import { useMemo } from 'react'
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { Card, EmptyState, PageHeader } from '../../components/ui'
import { fmtMonth } from '../../lib/dates'
import { supabase } from '../../lib/supabase'
import { DashboardProvider } from './dashboardContext'
import { defaultRange, previousRange } from './dashboardRange'
import type { DateRange } from './dashboardRange'
import type { DashboardSections, SectionMap } from './useDashboardData'
import {
  CustomerCommissionWidget,
  CustomerEventsCountWidget,
  CustomerEventsTotalWidget,
  CustomerMonthsWidget,
} from './widgets/customerMonthlyWidgets'

/**
 * דשבורד הלקוח — מסך אחד, קבוע, וכלום מלבד מה שהלקוח נשאל עליו.
 *
 * הצוות והקבלן ממשיכים ב-`DashboardPage` המשותף, המסונן בהרשאות. הלקוח, לעומת
 * זאת, מקבל מסך ייעודי: כמות אירועים לחודש, הסכום, והעמלה — ולא דבר מעבר. אין
 * כאן בורר טווח, ייצוא, התאמה אישית או עריכה, פשוט משום שאין מה שיצייר אותם.
 *
 * ‏**אין כאן שם לקוח.** ארקו וקיסר נבדלים אך ורק ב-`commission_pct` על שורתם
 * (0143): לקוח בלי עמלה רואה "סכום לתשלום לוייפר" ובלי כרטיס/עמודת עמלה, ולקוח
 * עמלה רואה "סכום כולל של האירועים" ואת העמלה. שלושת הכרטיסים והטבלה קוראים
 * **סקשן אחד** (`customer.monthly`), כלומר שאילתה אחת בשרת, וכולם מכריעים לבד
 * מהקונפיגורציה שחוזרת בו.
 */
async function fetchMonthly(range: DateRange): Promise<SectionMap> {
  const { data, error } = await supabase.rpc('dashboard_sections', {
    p_sections: ['customer.monthly'],
    p_from: range.from,
    p_to: range.to,
    p_opts: {},
  })
  if (error) throw error
  return (data ?? {}) as SectionMap
}

/* אותו סקשן, ואותו חוזה של `useSection`: הכרטיסים קוראים את החודש הנוכחי מול
   הקודם (לדלתא), הטבלה מתעלמת מהטווח וממילא מציגה שנים־עשר חודשים. מפתחות
   השאילתה תואמים ל-`useDashboardData`, כך ששתי טעינות של אותו חודש חולקות מטמון. */
function useCustomerMonthly(range: DateRange, prev: DateRange): DashboardSections {
  const rangeQ = useQuery({
    queryKey: ['dashboard', 'sections', 'range', range.from, range.to, 'customer.monthly', {}],
    placeholderData: keepPreviousData,
    queryFn: () => fetchMonthly(range),
  })
  const prevQ = useQuery({
    queryKey: ['dashboard', 'sections', 'range', prev.from, prev.to, 'customer.monthly', {}],
    staleTime: 5 * 60_000,
    queryFn: () => fetchMonthly(prev),
  })

  const rangeData = rangeQ.data
  const prevData = prevQ.data
  const isLoading = rangeQ.isLoading
  const error = rangeQ.error
  const refetchRange = rangeQ.refetch
  const refetchPrev = prevQ.refetch

  return useMemo<DashboardSections>(
    () => ({
      section: (key: string) => rangeData?.[key],
      prevSection: (key: string) => prevData?.[key],
      customResult: () => undefined,
      isLoading,
      error,
      refetch: () => {
        void refetchRange()
        void refetchPrev()
      },
    }),
    [rangeData, prevData, isLoading, error, refetchRange, refetchPrev],
  )
}

export default function CustomerDashboard() {
  const range = useMemo(() => defaultRange(), [])
  const prev = useMemo(() => previousRange(range), [range])
  const sections = useCustomerMonthly(range, prev)

  const ctx = useMemo(
    () => ({ range, prev, today: range.to, sections, openNewEvent: () => {} }),
    [range, prev, sections],
  )

  /* `null` = השרת מסרב לתת את הסקשן לקורא הזה — לקוח בלי `finance.customer_monthly`.
     בלי הגדר הזאת המסך היה כותרת מרחפת מעל כלום. `undefined` הוא טעינה, ואותו
     נטפל בו השלד של הכרטיסים עצמם. */
  const declined = sections.section('customer.monthly') === null

  return (
    <div className="space-y-4">
      <PageHeader title="דשבורד" subtitle={fmtMonth(new Date())} />

      {declined ? (
        <Card>
          <EmptyState
            art="alert"
            title="אין נתונים להצגה"
            description="לא נמצאו אירועים לחשבון שלך. פנה למנהל המערכת אם זו טעות."
          />
        </Card>
      ) : (
        <DashboardProvider value={ctx}>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
            <CustomerEventsCountWidget size="sm" height={0} opts={{}} />
            <CustomerEventsTotalWidget size="sm" height={0} opts={{}} />
            <CustomerCommissionWidget size="sm" height={0} opts={{}} />
          </div>
          <CustomerMonthsWidget size="md" height={0} opts={{}} />
        </DashboardProvider>
      )}
    </div>
  )
}
