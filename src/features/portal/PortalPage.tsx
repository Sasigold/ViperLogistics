import { useMemo, useState } from 'react'
import { Navigate, useSearchParams } from 'react-router'
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { addMonths, endOfMonth, isSameMonth, startOfMonth, subMonths } from 'date-fns'
import {
  Banknote,
  Briefcase,
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  CircleCheck,
  ICON,
  STROKE,
  Wallet,
} from '../../components/ui/icons'
import {
  Button,
  Card,
  ErrorState,
  Field,
  IconButton,
  Input,
  PageHeader,
  ProgressBar,
  SkeletonCard,
  StatCard,
} from '../../components/ui'
import { fmtDate, fmtMoney, fmtMonth, toISODate } from '../../lib/dates'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'

interface PortalStats {
  tasks_count: number
  /** null when the contractor lacks portal.view_financials — the RPC omits it */
  expected_total: number | null
  paid_total: number | null
  unpaid_total: number | null
  completed_count: number
  upcoming_count: number
}

/**
 * הסיכום הכספי של הקבלן.
 *
 * עד 0071 המסך הזה היה shell שלם מחוץ ל-`AppLayout`, עם chrome משלו וארבע
 * לשוניות שהחזיקו את לוח השנה, הלו״ז, סגל העובדים והנוכחות של הקבלן. כל אחת
 * מהן היא עכשיו נתיב של ממש — `/calendar`, `/board`, `/my/staff`, `/attendance`
 * — ומה שנשאר כאן הוא מה שהמסך באמת היה: כמה משימות, כמה צפוי, כמה שולם וכמה
 * נותר. הכותרת, ההתנתקות ומחליף ערכת הנושא מגיעים מה-shell כמו לכל מסך אחר.
 */
export default function PortalPage() {
  return (
    <RequirePermission perm={PERM.PORTAL_VIEW}>
      <ContractorSummary />
    </RequirePermission>
  )
}

function ContractorSummary() {
  const { me, has } = useAuth()
  /**
   * The portal used to rely on RLS alone. RLS still decides, but the screen now
   * asks the same questions so a contractor without the financial key sees a
   * task count rather than four empty money tiles.
   */
  const canSeeMoney = has(PERM.PORTAL_VIEW_FINANCIALS)
  const contractorId = me?.profile.contractor_id ?? null

  /**
   * החודש הנוכחי, ובורר שמדפדף בין החודשים.
   *
   * המסך נפתח עד כה על **כל התקופה**, כי שני שדות התאריך התחילו ריקים. זו
   * תשובה נכונה לשאלה שאיש לא שאל: קבלן שנכנס לכאן שואל "מה יש לי החודש",
   * ולא "כמה עבדתי מאז ומעולם" — והמספר הכולל, שגדל בכל חודש שעובר, גם לא
   * ענה על הראשונה וגם לא היה ניתן להשוואה לחודש שעבר. החודש הנוכחי הוא
   * ברירת המחדל, והחיצים הם התנועה — אותה תבנית של דוח הנוכחות ושל רישום
   * התקבולים, כולל הכיוון: ימין הוא אחורה ב-RTL.
   *
   * **וכל התקופה לא אבדה.** יתרה פתוחה אינה נגמרת בסוף החודש, ולכן "טווח
   * מותאם" נשאר — ובו שני השדות בדיוק כפי שהיו, ששניהם ריקים בו פירושו
   * הכול. שינוי ברירת המחדל אינו אמור להסתיר חוב ישן ממי שבא לחפש אותו.
   */
  const [monthDate, setMonthDate] = useState(() => startOfMonth(new Date()))
  const [customRange, setCustomRange] = useState(false)
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')

  const month = useMemo(
    () => ({ from: toISODate(startOfMonth(monthDate)), to: toISODate(endOfMonth(monthDate)) }),
    [monthDate],
  )
  /* ‏`null` בשני הקצוות = בלי גבול, וזה מה שה-RPC מקבל מאז 0006. */
  const range = customRange ? { from: from || null, to: to || null } : month

  /* התראות משימה ישנות נושאות `/portal?task=…`: `app.notification_link` (0054)
     שומרת את הכתובת על השורה ולא מחשבת אותה בקריאה, ולכן שורות שכבר נכתבו
     ימשיכו להצביע לכאן גם אחרי ש-0071 §4 העביר את היעד ל-`/board`. במקום ליפול
     על סיכום כספי, הן ממשיכות ליעד החדש עם אותו פרמטר. */
  const [params] = useSearchParams()
  const taskParam = params.get('task')

  const { data: stats, isLoading, error: statsError, refetch: refetchStats } = useQuery({
    queryKey: ['portal', 'stats', range.from, range.to],
    enabled: !!contractorId && !taskParam,
    /* דפדוף בין חודשים אינו אמור להבהב: המספרים של החודש הקודם נשארים על
       המסך עד שאלה של החדש מגיעים. */
    placeholderData: keepPreviousData,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('contractor_dashboard', {
        p_from: range.from,
        p_to: range.to,
      })
      if (error) throw error
      return data as PortalStats
    },
  })

  if (taskParam) return <Navigate to={`/board?task=${taskParam}`} replace />

  const paidRatio =
    stats && stats.expected_total && stats.paid_total !== null
      ? (stats.paid_total / stats.expected_total) * 100
      : 0

  return (
    <div className="space-y-4">
      <PageHeader
        title="כספים ותשלומים"
        subtitle={
          customRange
            ? 'מה הואצל אליי, מה כבר שולם ומה עוד פתוח — בטווח שנבחר'
            : `מה הואצל אליי, מה כבר שולם ומה עוד פתוח — ${fmtMonth(monthDate)}`
        }
      />

      {/* בורר התקופה יושב *מעל* המספרים ולא מתחתיהם: הוא מה שקובע מה הם
          אומרים, ומי שקרא אותם קודם לא ידע שהוא קיים. */}
      <Card className="flex flex-wrap items-center justify-between gap-3 p-3">
        {customRange ? (
          <div className="flex flex-wrap items-end gap-3">
            <Field label="מתאריך" className="grow basis-36 sm:w-40 sm:grow-0 sm:basis-auto">
              <Input type="date" inputSize="sm" value={from} onChange={(e) => setFrom(e.target.value)} />
            </Field>
            <Field label="עד תאריך" className="grow basis-36 sm:w-40 sm:grow-0 sm:basis-auto">
              <Input type="date" inputSize="sm" value={to} onChange={(e) => setTo(e.target.value)} />
            </Field>
            <p className="mb-2 type-caption text-ink-tertiary">שדה ריק = בלי הגבלה</p>
          </div>
        ) : (
          <div className="flex items-center gap-1">
            <span
              className="me-1 flex size-9 shrink-0 items-center justify-center rounded-xl bg-subtle text-ink-secondary"
              aria-hidden
            >
              <CalendarDays size={ICON.lg} strokeWidth={STROKE} />
            </span>
            <IconButton
              label="חודש קודם"
              variant="ghost"
              onClick={() => setMonthDate((d) => subMonths(d, 1))}
            >
              <ChevronRight size={ICON.lg} strokeWidth={STROKE} />
            </IconButton>
            {/* הכותרת היא גם הדרך חזרה: לחיצה עליה מחזירה לחודש הנוכחי,
                כמו בבורר החודש של לו״ז העבודה. */}
            <button
              type="button"
              onClick={() => setMonthDate(startOfMonth(new Date()))}
              title="חזרה לחודש הנוכחי"
              className="min-w-36 rounded-lg px-2 py-0.5 text-center transition-colors hover:bg-hover"
            >
              <p className="type-title">{fmtMonth(monthDate)}</p>
              <p className="type-caption text-ink-tertiary tabular" dir="ltr">
                {fmtDate(month.from)} — {fmtDate(month.to)}
              </p>
            </button>
            <IconButton
              label="חודש הבא"
              variant="ghost"
              onClick={() => setMonthDate((d) => addMonths(d, 1))}
            >
              <ChevronLeft size={ICON.lg} strokeWidth={STROKE} />
            </IconButton>
            {!isSameMonth(monthDate, new Date()) && (
              <Button size="sm" onClick={() => setMonthDate(startOfMonth(new Date()))}>
                החודש
              </Button>
            )}
          </div>
        )}

        <Button
          size="sm"
          variant={customRange ? 'primary' : 'outlined'}
          onClick={() => {
            setCustomRange((v) => !v)
            if (customRange) {
              setFrom('')
              setTo('')
            }
          }}
        >
          {customRange ? 'חזרה לתצוגה חודשית' : 'טווח מותאם'}
        </Button>

        {/* אמירה מפורשת ולא הנחה: ארבעת הכרטיסים למטה — ובהם "יתרה" —
            מדברים על התקופה הזאת בלבד, ולא על הכול. */}
        <p className="basis-full type-caption text-ink-tertiary">
          כל המספרים למטה הם של התקופה שנבחרה כאן.
          {!customRange && ' ליתרה הכוללת — "טווח מותאם" בלי תאריכים.'}
        </p>
      </Card>

      {isLoading ? (
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <SkeletonCard key={i} lines={0} />
          ))}
        </div>
      ) : statsError != null ? (
        <ErrorState error={statsError} onRetry={() => void refetchStats()} />
      ) : (
        stats && (
          <>
            <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
              <StatCard
                icon={<Briefcase size={ICON.xl} strokeWidth={STROKE} />}
                label="משימות"
                value={stats.tasks_count}
                hint={`${stats.completed_count} בוצעו · ${stats.upcoming_count} עתידיות`}
              />
              {canSeeMoney && (
                <>
                  <StatCard
                    icon={<Wallet size={ICON.xl} strokeWidth={STROKE} />}
                    label="סכום צפוי"
                    value={fmtMoney(stats.expected_total ?? 0)}
                  />
                  <StatCard
                    icon={<CircleCheck size={ICON.xl} strokeWidth={STROKE} />}
                    label="שולם"
                    value={fmtMoney(stats.paid_total ?? 0)}
                    tone="#16a34a"
                  />
                  <StatCard
                    icon={<Banknote size={ICON.xl} strokeWidth={STROKE} />}
                    label="יתרה"
                    value={fmtMoney(stats.unpaid_total ?? 0)}
                    tone="#f59e0b"
                  />
                </>
              )}
            </div>

            {canSeeMoney && (stats.expected_total ?? 0) > 0 && (
              <Card padded>
                <ProgressBar
                  value={stats.paid_total ?? 0}
                  max={stats.expected_total ?? 0}
                  tone="success"
                  label="התקדמות תשלומים"
                  hint={`${Math.round(paidRatio)}% · ${fmtMoney(stats.paid_total ?? 0)} מתוך ${fmtMoney(stats.expected_total ?? 0)}`}
                />
              </Card>
            )}
          </>
        )
      )}
    </div>
  )
}
