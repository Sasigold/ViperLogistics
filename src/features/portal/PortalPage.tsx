import { useMemo, useState } from 'react'
import { Navigate, useNavigate, useSearchParams } from 'react-router'
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { addMonths, endOfMonth, isSameMonth, startOfMonth, subMonths } from 'date-fns'
import {
  Banknote,
  Briefcase,
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  CircleCheck,
  Download,
  ICON,
  MapPin,
  STROKE,
  Wallet,
} from '../../components/ui/icons'
import {
  Button,
  Card,
  DataTable,
  EmptyState,
  ErrorState,
  Field,
  IconButton,
  Input,
  PageHeader,
  ProgressBar,
  SkeletonCard,
  StatCard,
  StatusPill,
  Tooltip,
  useToast,
} from '../../components/ui'
import type { Column } from '../../components/ui'
import { fmtDate, fmtMoney, fmtMonth, toISODate } from '../../lib/dates'
import { shortAddress } from '../../lib/address'
import { supabase } from '../../lib/supabase'
import { errorMessage } from '../../lib/errors'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import type { PortalTaskRow } from '../../types/domain'
import { paidAmountOf, penaltyOf, summarize, taskLabel } from './portalTasks'

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

      {/* הפירוט שמתחת למספרים: על מה בדיוק הם. הכרטיסים עונים "כמה", והשורות
          עונות "על מה" — וזו השאלה שבאה מיד אחרי הראשונה. */}
      {contractorId && (
        <ContractorTaskList
          range={range}
          canSeeMoney={canSeeMoney}
          statsCount={stats?.tasks_count ?? null}
        />
      )}
    </div>
  )
}

/**
 * סיכום המשימות של הקבלן — שורה לכל משימה, עם המחיר שלה (0172).
 *
 * לקריאה בלבד. אותן שורות בדיוק נמצאות בכרטיס הקבלן שבמשרד
 * (`/contractors/:id`, לשונית "משימות ותשלומים"), ושם הן גם נערכות: המחיר
 * וסימון התשלום הם הכרעה של המשרד, ומסך שהיה מאפשר לקבלן לגעת בהם היה
 * מפתח שכתוב "לצפייה" ומתנהג כמו "לעריכה".
 */
function ContractorTaskList({
  range,
  canSeeMoney,
  statsCount,
}: {
  range: { from: string | null; to: string | null }
  canSeeMoney: boolean
  /** מונה המשימות של `contractor_dashboard` — הוא שאומר אם הרשימה נקטעה */
  statsCount: number | null
}) {
  const toast = useToast()
  const navigate = useNavigate()
  const { has } = useAuth()
  const canOpenTask = has(PERM.BOARD_VIEW)

  const { data: rows = [], isLoading, error, refetch } = useQuery({
    queryKey: ['portal', 'tasks', range.from, range.to],
    placeholderData: keepPreviousData,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('contractor_tasks', {
        p_from: range.from,
        p_to: range.to,
      })
      if (error) throw error
      return (data as PortalTaskRow[]) ?? []
    },
  })

  const totals = useMemo(() => summarize(rows), [rows])
  /* התקרה של ה-RPC היא 500 שורות. כשהמונה של הכרטיס גדול ממה שחזר, הרשימה
     אומרת את זה בעצמה — טבלה שנקטעה בשקט היא טבלה שמשקרת בסיכום שלה. */
  const truncated = statsCount != null && statsCount > rows.length

  const columns = useMemo<Column<PortalTaskRow>[]>(() => {
    const cols: Column<PortalTaskRow>[] = [
      {
        key: 'date',
        header: 'תאריך',
        width: 110,
        fixed: true,
        sortValue: (r) => r.task_date,
        render: (r) => <span className="tabular">{fmtDate(r.task_date)}</span>,
      },
      {
        /* תאריך האירוע אינו תאריך המשימה: הקמה ופירוק של אותו אירוע יושבים
           על שני ימים, והתשלום נקרא מול האירוע. שניהם מוצגים. */
        key: 'event_date',
        header: 'תאריך אירוע',
        width: 110,
        sortValue: (r) => r.event_date,
        render: (r) =>
          r.event_date ? (
            <span className="tabular">{fmtDate(r.event_date)}</span>
          ) : (
            <span className="text-ink-tertiary">—</span>
          ),
      },
      {
        key: 'task',
        header: 'משימה',
        width: 180,
        sortValue: (r) => taskLabel(r),
        render: (r) => <span className="font-medium">{taskLabel(r)}</span>,
      },
      {
        key: 'customer',
        header: 'לקוח',
        width: 150,
        sortValue: (r) => r.customer_name,
        render: (r) => r.customer_name ?? <span className="text-ink-tertiary">—</span>,
      },
      {
        key: 'end_client',
        header: 'לקוח סופי',
        width: 160,
        sortValue: (r) => r.end_client_name,
        render: (r) =>
          r.end_client_name ? (
            <span className="block truncate">{r.end_client_name}</span>
          ) : (
            <span className="text-ink-tertiary">—</span>
          ),
      },
      {
        key: 'location',
        header: 'מיקום',
        width: 200,
        sortValue: (r) => r.location_text,
        render: (r) =>
          r.location_text ? (
            <Tooltip content={r.location_text}>
              <span className="block truncate">{shortAddress(r.location_text)}</span>
            </Tooltip>
          ) : (
            <span className="text-ink-tertiary">—</span>
          ),
      },
      {
        key: 'status',
        header: 'סטטוס',
        width: 130,
        sortValue: (r) => r.status_name,
        render: (r) => <StatusPill color={r.status_color}>{r.status_name}</StatusPill>,
      },
    ]

    if (!canSeeMoney) return cols

    return cols.concat([
      {
        key: 'price',
        header: 'מחיר',
        width: 130,
        align: 'end',
        sortValue: (r) => r.price ?? -1,
        render: (r) => {
          if (r.price == null) return <span className="text-ink-tertiary">—</span>
          const penalty = penaltyOf(r)
          return (
            <div className="flex flex-col items-end">
              <span className="font-semibold tabular">{fmtMoney(r.price)}</span>
              {/* הקנס אינו מוסתר בתוך המחיר: זו השאלה הראשונה שקבלן שואל על
                  שורה שנראית לו נמוכה מדי (0093). */}
              {penalty > 0 && (
                <span className="type-caption text-warning-text tabular">
                  אחרי קנס {fmtMoney(penalty)}
                </span>
              )}
            </div>
          )
        },
      },
      {
        key: 'paid',
        header: 'תשלום',
        width: 160,
        sortValue: (r) => (r.paid_at ? 1 : 0),
        render: (r) => <PaidPill row={r} />,
      },
    ])
  }, [canSeeMoney])

  return (
    <DataTable
      rows={rows}
      columns={columns}
      getRowId={(r) => r.task_id}
      loading={isLoading}
      error={error}
      onRetry={() => void refetch()}
      storageKey="portal-tasks"
      pageSize={20}
      defaultSort={{ key: 'date', dir: 'desc' }}
      /* אותה דלת שההתראות משתמשות בה (0071 §4): המשימה נפתחת בלו״ז, שם היא
         גם ניתנת לשיבוץ. בלי המפתח ללו״ז השורה נשארת שורה. */
      onRowClick={canOpenTask ? (r) => void navigate(`/board?task=${r.task_id}`) : undefined}
      mobileCard={(r) => (
        <div className="space-y-1.5">
          <div className="flex items-center gap-2">
            <span className="type-caption font-semibold tabular">{fmtDate(r.task_date)}</span>
            <StatusPill color={r.status_color} className="ms-auto shrink-0">
              {r.status_name}
            </StatusPill>
          </div>
          <p className="truncate type-body font-semibold">{taskLabel(r)}</p>
          {r.event_date && <p className="type-caption text-ink-tertiary">אירוע: {fmtDate(r.event_date)}</p>}
          {(r.customer_name || r.end_client_name) && (
            <p className="truncate type-caption text-ink-tertiary">
              {[r.customer_name, r.end_client_name].filter(Boolean).join(' · ')}
            </p>
          )}
          {r.location_text && (
            <p className="flex items-center gap-1 truncate type-caption text-ink-tertiary">
              <MapPin size={ICON.sm} strokeWidth={STROKE} className="shrink-0" />
              {shortAddress(r.location_text)}
            </p>
          )}
          {canSeeMoney && (
            <div className="flex items-center gap-2">
              <span className="type-body font-semibold tabular">
                {r.price == null ? '—' : fmtMoney(r.price)}
              </span>
              <PaidPill row={r} />
            </div>
          )}
        </div>
      )}
      toolbar={
        <div className="flex grow flex-wrap items-center gap-x-3 gap-y-1">
          <p className="type-title">המשימות שלי</p>
          {/* הסיכום הוא של השורות שברשימה, ולכן הוא יושב עליה ולא בכרטיסים:
              שם הוא של כל הטווח, וכשהרשימה נקטעה השניים אינם אותו מספר. */}
          <p className="type-caption text-ink-tertiary">
            {totals.tasks} משימות · {totals.completed} בוצעו
            {canSeeMoney && ` · צפוי ${fmtMoney(totals.expected)} · שולם ${fmtMoney(totals.paid)} · יתרה ${fmtMoney(totals.unpaid)}`}
            {canSeeMoney && totals.unpriced > 0 && ` · ${totals.unpriced} ללא מחיר`}
          </p>
          {truncated && (
            <p className="type-caption text-warning-text">
              מוצגות {rows.length} מתוך {statsCount} — צמצמו את הטווח כדי לראות את השאר
            </p>
          )}
          <Button
            size="sm"
            variant="outlined"
            className="ms-auto"
            disabled={rows.length === 0}
            onClick={() => {
              void (async () => {
                try {
                  const { exportPortalTasks } = await import('./exportPortalTasks')
                  await exportPortalTasks(rows, { from: range.from ?? '', to: range.to ?? '' })
                } catch (e) {
                  toast.error(errorMessage(e))
                }
              })()
            }}
          >
            <Download size={ICON.sm} strokeWidth={STROKE} />
            ייצוא
          </Button>
        </div>
      }
      empty={
        <EmptyState
          art="table"
          title="אין משימות בתקופה הזאת"
          description="משימות שיואצלו אליך יופיעו כאן, עם המחיר של כל אחת ומצב התשלום שלה"
        />
      }
    />
  )
}

/** מצב התשלום של השורה. תווית ולא כפתור: הסימון הוא של המשרד. */
function PaidPill({ row }: { row: PortalTaskRow }) {
  const amount = paidAmountOf(row)
  if (!row.paid_at)
    return (
      <span className="rounded-full bg-warning-subtle px-2.5 py-1 type-caption font-semibold text-warning-text">
        ממתין לתשלום
      </span>
    )
  return (
    <span className="rounded-full bg-success-subtle px-2.5 py-1 type-caption font-semibold text-success-text">
      שולם · {fmtDate(row.paid_at)}
      {/* הסכום נכתב רק כשהוא שונה מהמחיר: המשרד יכול לשלם אחרת מהצפוי, וזה
          בדיוק המקרה שבו הקבלן צריך לראות את ההפרש. */}
      {amount != null && row.price != null && amount !== row.price && ` · ${fmtMoney(amount)}`}
    </span>
  )
}
