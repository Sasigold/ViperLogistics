import { useEffect, useState } from 'react'
import { useParams } from 'react-router'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Trash2 } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { Badge, Button, Field, Input, Spinner, useConfirm, useToast, cx } from '../../components/ui'
import { useContractorWorkers } from '../../lib/queries'
import { fmtDate, fmtMoney } from '../../lib/dates'
import { RequirePermission } from '../auth/guards'
import type { Contractor, ContractorWorker } from '../../types/domain'

interface ContractorTaskRow {
  task_id: string
  price: number
  paid_at: string | null
  paid_amount: number | null
  tasks: {
    id: string
    task_date: string
    title: string | null
    task_types: { name: string } | null
    customers: { name: string } | null
    statuses: { name: string; color: string; is_terminal: boolean } | null
  }
}

export default function ContractorDetailPage() {
  const { id } = useParams<{ id: string }>()
  const [tab, setTab] = useState<'details' | 'workers' | 'tasks'>('details')

  const { data: contractor, isLoading } = useQuery({
    queryKey: ['contractors', 'one', id],
    queryFn: async () => {
      const { data, error } = await supabase.from('contractors').select('*').eq('id', id).single()
      if (error) throw error
      return data as Contractor
    },
  })

  if (isLoading || !contractor) return <Spinner full />

  return (
    <RequirePermission resource="contractors">
      <div className="space-y-4">
        <h1 className="text-xl font-bold">{contractor.name}</h1>
        <div className="flex gap-1 border-b border-[var(--border)]">
          {([['details', 'פרטים'], ['workers', 'עובדי הקבלן'], ['tasks', 'משימות ותשלומים']] as const).map(([k, label]) => (
            <button
              key={k}
              onClick={() => setTab(k)}
              className={cx(
                'border-b-2 px-4 py-2 text-sm font-medium',
                tab === k ? 'border-brand-600 text-brand-600 dark:text-brand-300' : 'border-transparent text-[var(--muted)] hover:text-[var(--text)]',
              )}
            >
              {label}
            </button>
          ))}
        </div>
        {tab === 'details' && <DetailsTab contractor={contractor} />}
        {tab === 'workers' && <WorkersTab contractorId={contractor.id} />}
        {tab === 'tasks' && <TasksTab contractorId={contractor.id} />}
      </div>
    </RequirePermission>
  )
}

function DetailsTab({ contractor }: { contractor: Contractor }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { can } = useAuth()
  const canEdit = can('contractors', 'edit')
  const [form, setForm] = useState(contractor)
  useEffect(() => setForm(contractor), [contractor])

  const save = useMutation({
    mutationFn: async () => {
      const { error } = await supabase
        .from('contractors')
        .update({
          name: form.name,
          contact_name: form.contact_name,
          phone: form.phone,
          email: form.email,
          notes: form.notes,
          default_task_price: form.default_task_price,
          is_active: form.is_active,
        })
        .eq('id', contractor.id)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('הקבלן עודכן')
      void qc.invalidateQueries({ queryKey: ['contractors'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <div className="surface max-w-2xl space-y-3 p-4">
      <div className="grid grid-cols-2 gap-3">
        <Field label="שם" required>
          <Input value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} disabled={!canEdit} />
        </Field>
        <Field label="איש קשר">
          <Input value={form.contact_name ?? ''} onChange={(e) => setForm((f) => ({ ...f, contact_name: e.target.value }))} disabled={!canEdit} />
        </Field>
        <Field label="טלפון">
          <Input dir="ltr" value={form.phone ?? ''} onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))} disabled={!canEdit} />
        </Field>
        <Field label="מחיר ברירת מחדל למשימה (₪)">
          <Input
            type="number"
            min="0"
            value={form.default_task_price ?? ''}
            onChange={(e) => setForm((f) => ({ ...f, default_task_price: e.target.value === '' ? null : Number(e.target.value) }))}
            disabled={!canEdit}
          />
        </Field>
      </div>
      {canEdit && (
        <div className="flex justify-end">
          <Button variant="primary" loading={save.isPending} onClick={() => save.mutate()}>שמירה</Button>
        </div>
      )}
    </div>
  )
}

export function WorkersTab({ contractorId, canManage = true }: { contractorId: string; canManage?: boolean }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const { data: workers = [] } = useContractorWorkers(contractorId)
  const [form, setForm] = useState({ full_name: '', phone: '', id_number: '' })

  const add = useMutation({
    mutationFn: async () => {
      if (!form.full_name.trim()) throw new Error('חובה להזין שם עובד')
      const { error } = await supabase.from('contractor_workers').insert({ contractor_id: contractorId, ...form })
      if (error) throw error
    },
    onSuccess: () => {
      setForm({ full_name: '', phone: '', id_number: '' })
      void qc.invalidateQueries({ queryKey: ['contractor_workers'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const remove = async (w: ContractorWorker) => {
    if (!(await confirm(`להסיר את ${w.full_name} מהסגל?`))) return
    const { error } = await supabase.from('contractor_workers').update({ deleted_at: new Date().toISOString() }).eq('id', w.id)
    if (error) toast.error(error.message)
    else void qc.invalidateQueries({ queryKey: ['contractor_workers'] })
  }

  return (
    <div className="surface max-w-2xl space-y-3 p-4">
      {dialog}
      {canManage && (
        <div className="flex flex-wrap items-end gap-2">
          <Field label="שם מלא"><Input value={form.full_name} onChange={(e) => setForm((f) => ({ ...f, full_name: e.target.value }))} /></Field>
          <Field label="טלפון"><Input dir="ltr" value={form.phone} onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))} /></Field>
          <Field label="ת.ז."><Input dir="ltr" value={form.id_number} onChange={(e) => setForm((f) => ({ ...f, id_number: e.target.value }))} /></Field>
          <Button variant="primary" loading={add.isPending} onClick={() => add.mutate()}>הוספה</Button>
        </div>
      )}
      <div className="divide-y divide-[var(--border)]">
        {workers.length === 0 && <p className="py-3 text-sm text-[var(--muted)]">אין עובדים בסגל</p>}
        {workers.map((w) => (
          <div key={w.id} className="flex items-center justify-between py-2">
            <div>
              <p className="text-sm font-medium">{w.full_name}</p>
              <p className="text-xs text-[var(--muted)]">{[w.phone, w.id_number].filter(Boolean).join(' · ')}</p>
            </div>
            {canManage && (
              <button onClick={() => void remove(w)} className="text-[var(--muted)] hover:text-red-500">
                <Trash2 size={14} />
              </button>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}

function TasksTab({ contractorId }: { contractorId: string }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { can } = useAuth()
  const canEdit = can('contractors', 'edit')
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')

  const { data: rows = [], isLoading } = useQuery({
    queryKey: ['contractor_terms', contractorId, from, to],
    queryFn: async () => {
      let q = supabase
        .from('task_contractor_terms')
        .select('task_id, price, paid_at, paid_amount, tasks!inner(id, task_date, title, deleted_at, task_types(name), customers(name), statuses(name, color, is_terminal))')
        .eq('contractor_id', contractorId)
        .is('tasks.deleted_at', null)
      if (from) q = q.gte('tasks.task_date', from)
      if (to) q = q.lte('tasks.task_date', to)
      const { data, error } = await q
      if (error) throw error
      return (data as unknown as ContractorTaskRow[]).sort((a, b) => b.tasks.task_date.localeCompare(a.tasks.task_date))
    },
  })

  const setPaid = useMutation({
    mutationFn: async ({ taskId, paid }: { taskId: string; paid: boolean }) => {
      const row = rows.find((r) => r.task_id === taskId)
      const { error } = await supabase
        .from('task_contractor_terms')
        .update(paid ? { paid_at: new Date().toISOString(), paid_amount: row?.price ?? 0 } : { paid_at: null, paid_amount: null })
        .eq('task_id', taskId)
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['contractor_terms'] }),
    onError: (e) => toast.error((e as Error).message),
  })

  const updatePrice = useMutation({
    mutationFn: async ({ taskId, price }: { taskId: string; price: number }) => {
      const { error } = await supabase.from('task_contractor_terms').update({ price }).eq('task_id', taskId)
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['contractor_terms'] }),
    onError: (e) => toast.error((e as Error).message),
  })

  const expected = rows.reduce((s, r) => s + Number(r.price), 0)
  const paid = rows.filter((r) => r.paid_at).reduce((s, r) => s + Number(r.paid_amount ?? r.price), 0)

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-end gap-2">
        <Field label="מתאריך"><Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
        <Field label="עד תאריך"><Input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
        <div className="ms-auto flex gap-3 text-sm">
          <span>סה"כ צפוי: <b>{fmtMoney(expected)}</b></span>
          <span>שולם: <b className="text-emerald-600">{fmtMoney(paid)}</b></span>
          <span>יתרה: <b className="text-amber-600">{fmtMoney(expected - paid)}</b></span>
        </div>
      </div>
      <div className="surface overflow-x-auto">
        {isLoading ? (
          <Spinner full />
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-[var(--border)] text-xs text-[var(--muted)]">
                <th className="px-3 py-2 text-start">תאריך</th>
                <th className="px-3 py-2 text-start">משימה</th>
                <th className="px-3 py-2 text-start">לקוח</th>
                <th className="px-3 py-2 text-start">סטטוס</th>
                <th className="px-3 py-2 text-start">מחיר (₪)</th>
                <th className="px-3 py-2 text-start">תשלום</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.task_id} className="border-b border-[var(--border)] last:border-0">
                  <td className="px-3 py-2 whitespace-nowrap">{fmtDate(r.tasks.task_date)}</td>
                  <td className="px-3 py-2">{r.tasks.title || r.tasks.task_types?.name}</td>
                  <td className="px-3 py-2">{r.tasks.customers?.name}</td>
                  <td className="px-3 py-2">
                    {r.tasks.statuses && <Badge color={r.tasks.statuses.color}>{r.tasks.statuses.name}</Badge>}
                  </td>
                  <td className="px-3 py-2">
                    <Input
                      type="number"
                      min="0"
                      className="w-24"
                      defaultValue={r.price}
                      disabled={!canEdit}
                      onBlur={(e) => {
                        const v = Number(e.target.value) || 0
                        if (v !== Number(r.price)) updatePrice.mutate({ taskId: r.task_id, price: v })
                      }}
                    />
                  </td>
                  <td className="px-3 py-2">
                    <button
                      disabled={!canEdit}
                      onClick={() => setPaid.mutate({ taskId: r.task_id, paid: !r.paid_at })}
                      className={cx(
                        'rounded-full px-2.5 py-1 text-xs font-medium',
                        r.paid_at ? 'bg-emerald-500/15 text-emerald-600' : 'bg-amber-500/15 text-amber-600',
                      )}
                    >
                      {r.paid_at ? `שולם ${fmtDate(r.paid_at)}` : 'ממתין לתשלום'}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
