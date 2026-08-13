import { useEffect, useState } from 'react'
import { useSearchParams } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import {
  Banknote,
  Briefcase,
  CalendarDays,
  CircleCheck,
  ClipboardList,
  Clock,
  ICON,
  LogOut,
  Moon,
  STROKE,
  Sun,
  Truck,
  Users,
  Wallet,
} from '../../components/ui/icons'
import {
  Avatar,
  Card,
  ErrorState,
  Field,
  IconButton,
  Input,
  ProgressBar,
  Skeleton,
  SkeletonCard,
  StatCard,
  Tabs,
} from '../../components/ui'
import { fmtMoney } from '../../lib/dates'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { WorkersTab } from '../contractors/ContractorDetailPage'
import { ContractorCalendar, ContractorSchedule } from '../contractors/ContractorWork'
import { AttendanceReport } from '../attendance/AttendanceReportPage'

interface PortalStats {
  tasks_count: number
  /** null when the contractor lacks portal.view_financials — the RPC omits it */
  expected_total: number | null
  paid_total: number | null
  unpaid_total: number | null
  completed_count: number
  upcoming_count: number
}

/* הלו״ז ולוח השנה רוכבים על portal.view, אותו מפתח שפותח את הפורטל עצמו:
   הם *התצוגה* של אותן משימות שהלשונית הראשונה כבר הראתה, ולא מידע נוסף.
   השיבוץ שבתוכם הוא מה שנשלט בנפרד, דרך portal.assign_workers. */
const TABS = [
  { key: 'schedule' as const, label: 'לו״ז עבודה', icon: <ClipboardList size={ICON.sm} />, perm: PERM.PORTAL_VIEW },
  { key: 'calendar' as const, label: 'לוח שנה', icon: <CalendarDays size={ICON.sm} />, perm: PERM.PORTAL_VIEW },
  { key: 'workers' as const, label: 'העובדים שלי', icon: <Users size={ICON.sm} />, perm: PERM.PORTAL_MANAGE_WORKERS },
  { key: 'attendance' as const, label: 'נוכחות', icon: <Clock size={ICON.sm} />, perm: PERM.PORTAL_ATTENDANCE },
]

type PortalTab = (typeof TABS)[number]['key']

export default function PortalPage() {
  const { me, theme, toggleTheme, signOut, has } = useAuth()
  /**
   * The portal used to rely on RLS alone. RLS still decides, but the screen now
   * asks the same questions so a contractor without the financial key sees a
   * task list rather than four empty money tiles.
   */
  const canSeeMoney = has(PERM.PORTAL_VIEW_FINANCIALS)
  const canAssign = has(PERM.PORTAL_ASSIGN_WORKERS)
  const visibleTabs = TABS.filter((t) => has(t.perm))
  const contractorId = me?.profile.contractor_id ?? null
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const [tab, setTab] = useState<PortalTab>('schedule')

  /* התראת משימה של קבלן מובילה לכאן ולא ללוח העבודה — /board מגודר ב-board.view
     שהיא הרשאת staff, ולקבלן אין אותה. app.notification_link (0054) מפצל לפי
     user_kind, והפרמטר הוא מה שאומר איזו משימה מבין החמישים ברשימה. */
  const [params] = useSearchParams()
  const taskParam = params.get('task')
  useEffect(() => {
    if (taskParam) setTab('schedule')
  }, [taskParam])

  /* הלו״ז נפתח על חודש, ולכן קישור למשימה חייב לדעת באיזה חודש היא יושבת —
     אחרת הוא היה נוחת על החודש הנוכחי ומדגיש שורה שאינה בו. שאילתה של שדה
     אחד, ורק כשהגיעו מקישור. */
  const { data: taskMonth } = useQuery({
    queryKey: ['portal', 'task_month', taskParam],
    enabled: !!taskParam,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('work_board_view')
        .select('task_date')
        .eq('id', taskParam)
        .maybeSingle()
      if (error) throw error
      return (data?.task_date as string | undefined) ?? null
    },
  })

  const { data: stats, isLoading, error: statsError, refetch: refetchStats } = useQuery({
    queryKey: ['portal', 'stats', from, to],
    enabled: !!contractorId,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('contractor_dashboard', { p_from: from || null, p_to: to || null })
      if (error) throw error
      return data as PortalStats
    },
  })

  if (!me)
    return (
      <div className="mx-auto max-w-5xl space-y-4 p-4">
        <Skeleton className="h-14 w-full" />
        <Skeleton className="h-32 w-full" />
      </div>
    )

  const paidRatio =
    stats && stats.expected_total && stats.paid_total !== null
      ? (stats.paid_total / stats.expected_total) * 100
      : 0

  return (
    <div className="min-h-full bg-canvas">
      {/* the portal lives outside AppLayout, so it carries its own chrome */}
      <header className="sticky top-0 z-30 border-b border-line bg-surface/85 backdrop-blur-md">
        <div className="mx-auto flex h-14 max-w-5xl items-center gap-2.5 px-4">
          <span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-primary text-on-primary" aria-hidden>
            <Truck size={ICON.md} strokeWidth={STROKE} />
          </span>
          <div className="min-w-0">
            <h1 className="truncate type-title leading-tight">פורטל קבלן</h1>
            <p className="truncate type-caption text-ink-tertiary">{me.profile.full_name}</p>
          </div>
          <div className="ms-auto flex items-center gap-0.5">
            <IconButton
              label={theme === 'light' ? 'מעבר למצב כהה' : 'מעבר למצב בהיר'}
              size="sm"
              onClick={toggleTheme}
            >
              {theme === 'light' ? <Moon size={ICON.md} strokeWidth={STROKE} /> : <Sun size={ICON.md} strokeWidth={STROKE} />}
            </IconButton>
            <IconButton label="התנתקות" size="sm" onClick={() => void signOut()}>
              <LogOut size={ICON.md} strokeWidth={STROKE} />
            </IconButton>
            <Avatar name={me.profile.full_name} size="md" className="ms-1" />
          </div>
        </div>
      </header>

      <div className="mx-auto max-w-5xl space-y-4 p-4">
        {/* ── financial summary ─────────────────────────────────────────── */}
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

        {/* הטווח הזה מסנן את הסיכום שלמעלה בלבד. ללו״ז וללוח השנה יש ניווט
            חודשי משלהם, ושני סרגלי תאריכים שמכריעים על אותו דבר היו שניים
            יותר מדי — ולכן הכותרת אומרת במפורש על מה הוא חל. */}
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

        {visibleTabs.length > 1 && <Tabs items={visibleTabs} value={tab} onChange={setTab} />}

        {tab === 'schedule' ? (
          contractorId && (
            <ContractorSchedule
              contractorId={contractorId}
              canAssign={canAssign}
              highlightId={taskParam}
              initialMonth={taskMonth}
            />
          )
        ) : tab === 'calendar' ? (
          contractorId && <ContractorCalendar contractorId={contractorId} canAssign={canAssign} />
        ) : tab === 'attendance' ? (
          /* אותו רכיב דוח של המנהל. התחימה לסגל של הקבלן נעשית בשרת, ולכן
             הפרופ כאן הוא נוחות ולא הגנה. */
          <AttendanceReport embedded contractorId={contractorId} />
        ) : (
          contractorId && <WorkersTab contractorId={contractorId} canManage={has(PERM.PORTAL_MANAGE_WORKERS)} />
        )}
      </div>
    </div>
  )
}
