import { useState } from 'react'
import { Navigate, useSearchParams } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import { Banknote, Briefcase, CircleCheck, ICON, STROKE, Wallet } from '../../components/ui/icons'
import {
  Card,
  ErrorState,
  Field,
  Input,
  PageHeader,
  ProgressBar,
  SkeletonCard,
  StatCard,
} from '../../components/ui'
import { fmtMoney } from '../../lib/dates'
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
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')

  /* התראות משימה ישנות נושאות `/portal?task=…`: `app.notification_link` (0054)
     שומרת את הכתובת על השורה ולא מחשבת אותה בקריאה, ולכן שורות שכבר נכתבו
     ימשיכו להצביע לכאן גם אחרי ש-0071 §4 העביר את היעד ל-`/board`. במקום ליפול
     על סיכום כספי, הן ממשיכות ליעד החדש עם אותו פרמטר. */
  const [params] = useSearchParams()
  const taskParam = params.get('task')

  const { data: stats, isLoading, error: statsError, refetch: refetchStats } = useQuery({
    queryKey: ['portal', 'stats', from, to],
    enabled: !!contractorId && !taskParam,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('contractor_dashboard', { p_from: from || null, p_to: to || null })
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
      <PageHeader title="כספים ותשלומים" subtitle="מה הואצל אליי, מה כבר שולם ומה עוד פתוח" />

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

      {/* הטווח חל על הסיכום שלמעלה בלבד. הלו״ז ולוח השנה הם מסכים אחרים עם
          ניווט משלהם, ולכן אין כאן סיכון לשני סרגלי תאריכים שמכריעים על אותו
          דבר — אבל הכותרת ממשיכה לומר במפורש על מה הוא חל. */}
      <Card padded className="flex flex-wrap items-end gap-3">
        <p className="basis-full type-caption text-ink-tertiary">טווח לסיכום שלמעלה</p>
        <Field label="מתאריך" className="grow basis-36 sm:w-40 sm:grow-0 sm:basis-auto">
          <Input type="date" inputSize="sm" value={from} onChange={(e) => setFrom(e.target.value)} />
        </Field>
        <Field label="עד תאריך" className="grow basis-36 sm:w-40 sm:grow-0 sm:basis-auto">
          <Input type="date" inputSize="sm" value={to} onChange={(e) => setTo(e.target.value)} />
        </Field>
        {(from || to) && (
          <button
            onClick={() => {
              setFrom('')
              setTo('')
            }}
            className="mb-1.5 rounded-md px-2 py-1 type-caption text-ink-tertiary transition-colors hover:bg-hover hover:text-ink"
          >
            ניקוי
          </button>
        )}
      </Card>
    </div>
  )
}
