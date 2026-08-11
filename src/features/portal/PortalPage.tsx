import { useEffect, useState } from 'react'
import { useSearchParams } from 'react-router'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Banknote,
  Briefcase,
  CalendarDays,
  CircleCheck,
  Clock,
  ICON,
  LogOut,
  MapPin,
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
  CardBody,
  CardHeader,
  EmptyState,
  Field,
  IconButton,
  Input,
  MultiSelect,
  ProgressBar,
  Skeleton,
  SkeletonCard,
  SkeletonList,
  StatCard,
  StatusPill,
  Tabs,
  Tooltip,
  cx,
  relativeDayLabel,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { useContractorWorkers } from '../../lib/queries'
import { HIGHLIGHT_CLASS, useDeepLinkHighlight } from '../../lib/deepLink'
import { fmtDate, fmtMoney, fmtTime } from '../../lib/dates'
import { WorkersTab } from '../contractors/ContractorDetailPage'
import { AttendanceReport } from '../attendance/AttendanceReportPage'
import type { WorkBoardRow } from '../../types/domain'

interface PortalStats {
  tasks_count: number
  /** null when the contractor lacks portal.view_financials — the RPC omits it */
  expected_total: number | null
  paid_total: number | null
  unpaid_total: number | null
  completed_count: number
  upcoming_count: number
}

const TABS = [
  { key: 'tasks' as const, label: 'המשימות שלי', icon: <Briefcase size={ICON.sm} />, perm: PERM.PORTAL_VIEW },
  { key: 'workers' as const, label: 'העובדים שלי', icon: <Users size={ICON.sm} />, perm: PERM.PORTAL_MANAGE_WORKERS },
  { key: 'attendance' as const, label: 'נוכחות', icon: <Clock size={ICON.sm} />, perm: PERM.PORTAL_ATTENDANCE },
]

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
  const [tab, setTab] = useState<'tasks' | 'workers' | 'attendance'>('tasks')

  /* התראת משימה של קבלן מובילה לכאן ולא ללוח העבודה — /board מגודר ב-board.view
     שהיא הרשאת staff, ולקבלן אין אותה. app.notification_link (0054) מפצל לפי
     user_kind, והפרמטר הוא מה שאומר איזו משימה מבין החמישים ברשימה. */
  const [params] = useSearchParams()
  const taskParam = params.get('task')
  useEffect(() => {
    if (taskParam) setTab('tasks')
  }, [taskParam])

  const { data: stats, isLoading } = useQuery({
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

        <Card padded className="flex flex-wrap items-end gap-3">
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

        {tab === 'tasks' ? (
          <PortalTasks
            contractorId={contractorId!}
            from={from}
            to={to}
            canAssign={canAssign}
            highlightId={taskParam}
          />
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

function PortalTasks({
  contractorId,
  from,
  to,
  canAssign,
  highlightId,
}: {
  contractorId: string
  from: string
  to: string
  canAssign: boolean
  /** המשימה שהגיעו אליה מהתראה — נגללת ומובזקת פעם אחת */
  highlightId?: string | null
}) {
  const { data: tasks = [], isLoading } = useQuery({
    queryKey: ['portal', 'tasks', from, to],
    queryFn: async () => {
      let q = supabase.from('work_board_view').select('*').order('task_date', { ascending: false }).limit(500)
      if (from) q = q.gte('task_date', from)
      if (to) q = q.lte('task_date', to)
      const { data, error } = await q
      if (error) throw error
      return data as WorkBoardRow[]
    },
  })

  const { data: terms = [] } = useQuery({
    queryKey: ['portal', 'terms'],
    queryFn: async () => {
      const { data, error } = await supabase.from('task_contractor_terms').select('task_id, price, paid_at, paid_amount')
      if (error) throw error
      return data as { task_id: string; price: number; paid_at: string | null; paid_amount: number | null }[]
    },
  })

  if (isLoading) return <SkeletonList rows={4} />
  if (tasks.length === 0)
    return (
      <Card>
        <EmptyState
          art="calendar"
          title="אין משימות בטווח"
          description="משימות שיואצלו אליך יופיעו כאן, ותוכל לשבץ אליהן את העובדים שלך"
        />
      </Card>
    )

  return (
    <div className="space-y-3">
      {tasks.map((t) => (
        <PortalTaskCard
          key={t.id}
          task={t}
          term={terms.find((x) => x.task_id === t.id)}
          contractorId={contractorId}
          canAssign={canAssign}
          highlighted={t.id === highlightId}
        />
      ))}
    </div>
  )
}

function PortalTaskCard({
  task,
  term,
  contractorId,
  canAssign,
  highlighted,
}: {
  task: WorkBoardRow
  term?: { price: number; paid_at: string | null; paid_amount: number | null }
  contractorId: string
  canAssign: boolean
  highlighted?: boolean
}) {
  const ref = useDeepLinkHighlight(highlighted ? task.id : null)
  const qc = useQueryClient()
  const toast = useToast()
  const { data: roster = [] } = useContractorWorkers(contractorId)
  const chosen = (task.contractor_worker_list ?? []).map((w) => w.id)
  const dayLabel = relativeDayLabel(task.task_date)
  const full = task.worker_count > 0 && chosen.length >= task.worker_count

  const toggleWorker = async (workerId: string) => {
    if (chosen.includes(workerId)) {
      const { error } = await supabase
        .from('task_contractor_workers')
        .delete()
        .eq('task_id', task.id)
        .eq('contractor_worker_id', workerId)
      if (error) return toast.error(error.message)
    } else {
      const { error } = await supabase
        .from('task_contractor_workers')
        .insert({ task_id: task.id, contractor_worker_id: workerId })
      if (error) {
        return toast.error(
          error.message.includes('חריגה') ? error.message : 'לא ניתן להוסיף עובד — ייתכן שחרגת מכמות העובדים למשימה',
        )
      }
    }
    void qc.invalidateQueries({ queryKey: ['portal', 'tasks'] })
  }

  return (
    /* ה-ref יושב על עטיפה ולא על Card: Card מפזר את ה-rest שלו על אלמנט DOM
       אבל אינו מצהיר על ref בטיפוסים, ותיקון ה-UI kit בשביל גלילה אחת הוא
       שינוי גדול מהצורך. */
    <div ref={ref as React.Ref<HTMLDivElement>} className={highlighted ? HIGHLIGHT_CLASS : undefined}>
    <Card>
      <CardHeader
        title={
          <span className="flex flex-wrap items-center gap-2">
            {task.title || task.task_type_name}
            <StatusPill color={task.status_color}>{task.status_name}</StatusPill>
            {term && (
              <StatusPill color={term.paid_at ? '#16a34a' : '#f59e0b'}>
                {term.paid_at ? `שולם ${fmtMoney(term.paid_amount ?? term.price)}` : `צפוי ${fmtMoney(term.price)}`}
              </StatusPill>
            )}
          </span>
        }
        subtitle={
          <span className="flex flex-wrap items-center gap-x-2">
            <span className="tabular">{fmtDate(task.task_date)}</span>
            {dayLabel && <span className="font-semibold text-primary-text">· {dayLabel}</span>}
            {task.customer_name && <span>· {task.customer_name}</span>}
          </span>
        }
      />
      <CardBody className="space-y-3">
        {/* location / time / counts are read-only for contractors — enforced by RLS */}
        <dl className="grid grid-cols-2 gap-3 sm:grid-cols-3">
          <PortalFact icon={<MapPin size={ICON.sm} strokeWidth={STROKE} />} label="מיקום" value={task.location_text || '—'} />
          <PortalFact
            icon={<Clock size={ICON.sm} strokeWidth={STROKE} />}
            label="שעה בשטח"
            value={fmtTime(task.onsite_start_time) || '—'}
            ltr
          />
          <PortalFact
            icon={<CalendarDays size={ICON.sm} strokeWidth={STROKE} />}
            label="כמות עובדים"
            value={String(task.worker_count || '—')}
          />
        </dl>

        <div>
          <div className="mb-1.5 flex items-center gap-2">
            <p className="type-caption font-semibold text-ink-secondary">העובדים שלי למשימה</p>
            <span
              className={cx(
                'rounded-full px-1.5 py-0.5 type-caption font-bold tabular',
                full ? 'bg-success-subtle text-success-text' : 'bg-warning-subtle text-warning-text',
              )}
            >
              {chosen.length}/{task.worker_count || '∞'}
            </span>
          </div>
          <MultiSelect
            options={roster.map((w) => ({ id: w.id, label: w.full_name }))}
            values={chosen}
            onToggle={(id) => void toggleWorker(id)}
            placeholder="בחירת עובדים מהסגל שלך..."
            disabled={!canAssign}
          />
        </div>
      </CardBody>
    </Card>
    </div>
  )
}

function PortalFact({ icon, label, value, ltr }: { icon: React.ReactNode; label: string; value: string; ltr?: boolean }) {
  return (
    <div className="min-w-0">
      <dt className="flex items-center gap-1 type-caption text-ink-tertiary">
        <span className="shrink-0" aria-hidden>
          {icon}
        </span>
        {label}
      </dt>
      <Tooltip content={value.length > 24 ? value : ''}>
        <dd className={cx('mt-0.5 truncate type-body font-medium', ltr && 'tabular')} dir={ltr ? 'ltr' : undefined}>
          {value}
        </dd>
      </Tooltip>
    </div>
  )
}
