import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { LogOut, Moon, Sun, Users } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { Badge, Field, Input, MultiSelect, Spinner, EmptyState, useToast, cx } from '../../components/ui'
import { useContractorWorkers } from '../../lib/queries'
import { fmtDate, fmtMoney, fmtTime } from '../../lib/dates'
import { WorkersTab } from '../contractors/ContractorDetailPage'
import type { WorkBoardRow } from '../../types/domain'

interface PortalStats {
  tasks_count: number
  expected_total: number
  paid_total: number
  unpaid_total: number
  completed_count: number
  upcoming_count: number
}

export default function PortalPage() {
  const { me, theme, toggleTheme, signOut } = useAuth()
  const contractorId = me?.profile.contractor_id ?? null
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const [tab, setTab] = useState<'tasks' | 'workers'>('tasks')

  const { data: stats } = useQuery({
    queryKey: ['portal', 'stats', from, to],
    enabled: !!contractorId,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('contractor_dashboard', {
        p_from: from || null,
        p_to: to || null,
      })
      if (error) throw error
      return data as PortalStats
    },
  })

  if (!me) return <Spinner full />

  return (
    <div className="mx-auto max-w-5xl space-y-4 p-4">
      <header className="flex items-center gap-2">
        <div>
          <h1 className="text-xl font-bold">פורטל קבלן</h1>
          <p className="text-sm text-[var(--muted)]">שלום, {me.profile.full_name}</p>
        </div>
        <div className="ms-auto flex gap-1">
          <button onClick={toggleTheme} className="rounded-lg p-2 text-[var(--muted)] hover:bg-[var(--panel)]">
            {theme === 'light' ? <Moon size={16} /> : <Sun size={16} />}
          </button>
          <button onClick={() => void signOut()} className="rounded-lg p-2 text-[var(--muted)] hover:bg-[var(--panel)]" title="התנתקות">
            <LogOut size={16} />
          </button>
        </div>
      </header>

      <div className="flex flex-wrap items-end gap-2">
        <Field label="מתאריך"><Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
        <Field label="עד תאריך"><Input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
      </div>

      {stats && (
        <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
          {[
            ['משימות', String(stats.tasks_count)],
            ['סכום צפוי', fmtMoney(stats.expected_total)],
            ['שולם', fmtMoney(stats.paid_total)],
            ['יתרה', fmtMoney(stats.unpaid_total)],
            ['בוצעו', String(stats.completed_count)],
            ['עתידיות', String(stats.upcoming_count)],
          ].map(([label, value]) => (
            <div key={label} className="surface p-3">
              <p className="text-xs text-[var(--muted)]">{label}</p>
              <p className="text-lg font-bold">{value}</p>
            </div>
          ))}
        </div>
      )}

      <div className="flex gap-1 border-b border-[var(--border)]">
        {([['tasks', 'המשימות שלי'], ['workers', 'העובדים שלי']] as const).map(([k, label]) => (
          <button
            key={k}
            onClick={() => setTab(k)}
            className={cx(
              'flex items-center gap-1.5 border-b-2 px-4 py-2 text-sm font-medium',
              tab === k ? 'border-brand-600 text-brand-600 dark:text-brand-300' : 'border-transparent text-[var(--muted)]',
            )}
          >
            {k === 'workers' && <Users size={14} />}
            {label}
          </button>
        ))}
      </div>

      {tab === 'tasks' ? (
        <PortalTasks contractorId={contractorId!} from={from} to={to} />
      ) : (
        contractorId && <WorkersTab contractorId={contractorId} />
      )}
    </div>
  )
}

function PortalTasks({ contractorId, from, to }: { contractorId: string; from: string; to: string }) {
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

  if (isLoading) return <Spinner full />
  if (tasks.length === 0) return <EmptyState text="אין משימות" />

  return (
    <div className="space-y-3">
      {tasks.map((t) => {
        const term = terms.find((x) => x.task_id === t.id)
        return <PortalTaskCard key={t.id} task={t} term={term} contractorId={contractorId} />
      })}
    </div>
  )
}

function PortalTaskCard({
  task,
  term,
  contractorId,
}: {
  task: WorkBoardRow
  term?: { price: number; paid_at: string | null; paid_amount: number | null }
  contractorId: string
}) {
  const qc = useQueryClient()
  const toast = useToast()
  const { data: roster = [] } = useContractorWorkers(contractorId)
  const chosen = (task.contractor_worker_list ?? []).map((w) => w.id)

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
        return toast.error(error.message.includes('חריגה') ? error.message : 'לא ניתן להוסיף עובד — ייתכן שחרגת מכמות העובדים למשימה')
      }
    }
    void qc.invalidateQueries({ queryKey: ['portal', 'tasks'] })
  }

  return (
    <div className="surface p-4">
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-bold">{task.title || task.task_type_name}</span>
        <Badge color={task.status_color}>{task.status_name}</Badge>
        {term && (
          <Badge color={term.paid_at ? '#22c55e' : '#f59e0b'}>
            {term.paid_at ? `שולם ${fmtMoney(term.paid_amount ?? term.price)}` : `צפוי ${fmtMoney(term.price)}`}
          </Badge>
        )}
        <span className="ms-auto text-sm font-medium">{fmtDate(task.task_date)}</span>
      </div>
      {/* location/time/counts are read-only for contractors — enforced by RLS */}
      <div className="mt-2 grid grid-cols-2 gap-2 text-sm text-[var(--muted)] sm:grid-cols-4">
        <span>מיקום: <b className="text-[var(--text)]">{task.location_text || '—'}</b></span>
        <span>שעה: <b className="text-[var(--text)]" dir="ltr">{fmtTime(task.onsite_start_time) || '—'}</b></span>
        <span>כמות עובדים: <b className="text-[var(--text)]">{task.worker_count}</b></span>
        <span>לקוח: <b className="text-[var(--text)]">{task.customer_name || '—'}</b></span>
      </div>
      <div className="mt-3">
        <p className="mb-1 text-xs font-medium text-[var(--muted)]">
          העובדים שלי למשימה ({chosen.length}/{task.worker_count || '∞'})
        </p>
        <MultiSelect
          options={roster.map((w) => ({ id: w.id, label: w.full_name }))}
          values={chosen}
          onToggle={(id) => void toggleWorker(id)}
          placeholder="בחירת עובדים מהסגל שלך..."
        />
      </div>
    </div>
  )
}
