import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Plus, RotateCcw, Trash2 } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { Badge, Button, Checkbox, Field, Input, Select, Spinner, EmptyState, useConfirm, useToast, cx } from '../../components/ui'
import { useExecutionMethods, useStatuses, useTaskTypes, useTrucks } from '../../lib/queries'
import { fmtDateTime } from '../../lib/dates'
import { RequirePermission } from '../auth/guards'

const tabs = [
  { key: 'task_types', label: 'סוגי משימות' },
  { key: 'execution_methods', label: 'אופני ביצוע' },
  { key: 'statuses', label: 'סטטוסים' },
  { key: 'trucks', label: 'משאיות' },
  { key: 'recycle', label: 'סל מיחזור' },
  { key: 'audit', label: 'יומן פעילות' },
] as const

export default function SettingsPage() {
  const [tab, setTab] = useState<(typeof tabs)[number]['key']>('task_types')
  return (
    <RequirePermission resource="settings">
      <div className="space-y-4">
        <h1 className="text-xl font-bold">הגדרות</h1>
        <div className="flex flex-wrap gap-1 border-b border-[var(--border)]">
          {tabs.map((t) => (
            <button
              key={t.key}
              onClick={() => setTab(t.key)}
              className={cx(
                'border-b-2 px-4 py-2 text-sm font-medium',
                tab === t.key ? 'border-brand-600 text-brand-600 dark:text-brand-300' : 'border-transparent text-[var(--muted)] hover:text-[var(--text)]',
              )}
            >
              {t.label}
            </button>
          ))}
        </div>
        {tab === 'task_types' && <TaskTypesTab />}
        {tab === 'execution_methods' && <MethodsTab />}
        {tab === 'statuses' && <StatusesTab />}
        {tab === 'trucks' && <TrucksTab />}
        {tab === 'recycle' && <RecycleBinTab />}
        {tab === 'audit' && <AuditLogTab />}
      </div>
    </RequirePermission>
  )
}

function useSoftDelete(invalidate: string) {
  const qc = useQueryClient()
  const toast = useToast()
  return useMutation({
    mutationFn: async ({ table, id, restore }: { table: string; id: string; restore?: boolean }) => {
      const { error } = await supabase.rpc('soft_delete', { p_table: table, p_id: id, p_restore: restore ?? false })
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: [invalidate] }),
    onError: (e) => toast.error((e as Error).message),
  })
}

function TaskTypesTab() {
  const qc = useQueryClient()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const { data: types = [] } = useTaskTypes()
  const [name, setName] = useState('')
  const del = useSoftDelete('task_types')

  const add = useMutation({
    mutationFn: async () => {
      if (!name.trim()) throw new Error('חובה להזין שם')
      const { error } = await supabase.from('task_types').insert({ name, sort_order: types.length + 1 })
      if (error) throw error
    },
    onSuccess: () => {
      setName('')
      void qc.invalidateQueries({ queryKey: ['task_types'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <div className="surface max-w-2xl space-y-3 p-4">
      {dialog}
      <div className="flex items-end gap-2">
        <Field label="סוג משימה חדש"><Input value={name} onChange={(e) => setName(e.target.value)} /></Field>
        <Button variant="primary" onClick={() => add.mutate()}><Plus size={14} /> הוספה</Button>
      </div>
      <div className="divide-y divide-[var(--border)]">
        {types.map((t) => (
          <div key={t.id} className="flex items-center gap-2 py-2">
            <span className="text-sm font-medium">{t.name}</span>
            {t.is_system && <Badge color="#8b5cf6">מערכת</Badge>}
            {t.auto_create_on_event && <Badge color="#22c55e">נוצר אוטומטית</Badge>}
            {!t.is_system && (
              <button
                className="ms-auto text-[var(--muted)] hover:text-red-500"
                onClick={async () => {
                  if (await confirm(`למחוק את "${t.name}"?`)) del.mutate({ table: 'task_types', id: t.id })
                }}
              >
                <Trash2 size={14} />
              </button>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}

function MethodsTab() {
  const qc = useQueryClient()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const { data: methods = [] } = useExecutionMethods()
  const { data: types = [] } = useTaskTypes()
  const [name, setName] = useState('')
  const del = useSoftDelete('execution_methods')

  const { data: mapping = [] } = useQuery({
    queryKey: ['task_type_execution_methods', 'all'],
    queryFn: async () => {
      const { data, error } = await supabase.from('task_type_execution_methods').select('*')
      if (error) throw error
      return data as { task_type_id: string; execution_method_id: string }[]
    },
  })

  const add = useMutation({
    mutationFn: async () => {
      if (!name.trim()) throw new Error('חובה להזין שם')
      const { data, error } = await supabase.from('execution_methods').insert({ name, sort_order: methods.length + 1 }).select('id').single()
      if (error) throw error
      // new methods are available for all task types by default
      await supabase.from('task_type_execution_methods').insert(types.map((t) => ({ task_type_id: t.id, execution_method_id: data.id })))
    },
    onSuccess: () => {
      setName('')
      void qc.invalidateQueries({ queryKey: ['execution_methods'] })
      void qc.invalidateQueries({ queryKey: ['task_type_execution_methods'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const toggleMap = useMutation({
    mutationFn: async ({ typeId, methodId, on }: { typeId: string; methodId: string; on: boolean }) => {
      if (on) {
        const { error } = await supabase.from('task_type_execution_methods').insert({ task_type_id: typeId, execution_method_id: methodId })
        if (error) throw error
      } else {
        const { error } = await supabase.from('task_type_execution_methods').delete().eq('task_type_id', typeId).eq('execution_method_id', methodId)
        if (error) throw error
      }
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['task_type_execution_methods'] }),
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <div className="surface space-y-3 p-4">
      {dialog}
      <div className="flex max-w-md items-end gap-2">
        <Field label="אופן ביצוע חדש"><Input value={name} onChange={(e) => setName(e.target.value)} /></Field>
        <Button variant="primary" onClick={() => add.mutate()}><Plus size={14} /> הוספה</Button>
      </div>
      <p className="text-xs text-[var(--muted)]">סימון אילו אופני ביצוע זמינים לכל סוג משימה:</p>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-xs text-[var(--muted)]">
              <th className="px-2 py-1.5 text-start">אופן ביצוע</th>
              {types.map((t) => <th key={t.id} className="px-2 py-1.5 text-center">{t.name}</th>)}
              <th />
            </tr>
          </thead>
          <tbody>
            {methods.map((m) => (
              <tr key={m.id} className="border-t border-[var(--border)]">
                <td className="px-2 py-2 font-medium">{m.name}</td>
                {types.map((t) => {
                  const on = mapping.some((x) => x.task_type_id === t.id && x.execution_method_id === m.id)
                  return (
                    <td key={t.id} className="px-2 py-2 text-center">
                      <input
                        type="checkbox"
                        className="accent-brand-600"
                        checked={on}
                        onChange={(e) => toggleMap.mutate({ typeId: t.id, methodId: m.id, on: e.target.checked })}
                      />
                    </td>
                  )
                })}
                <td className="px-2 py-2">
                  <button
                    className="text-[var(--muted)] hover:text-red-500"
                    onClick={async () => {
                      if (await confirm(`למחוק את "${m.name}"?`)) del.mutate({ table: 'execution_methods', id: m.id })
                    }}
                  >
                    <Trash2 size={14} />
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}

function StatusesTab() {
  const qc = useQueryClient()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const { data: statuses = [] } = useStatuses()
  const [form, setForm] = useState({ name: '', entity: 'task', color: '#3b82f6', is_terminal: false })
  const del = useSoftDelete('statuses')

  const add = useMutation({
    mutationFn: async () => {
      if (!form.name.trim()) throw new Error('חובה להזין שם')
      const { error } = await supabase.from('statuses').insert({ ...form, sort_order: statuses.length + 1 })
      if (error) throw error
    },
    onSuccess: () => {
      setForm((f) => ({ ...f, name: '' }))
      void qc.invalidateQueries({ queryKey: ['statuses'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <div className="surface max-w-3xl space-y-3 p-4">
      {dialog}
      <div className="flex flex-wrap items-end gap-2">
        <Field label="סטטוס חדש"><Input value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} /></Field>
        <Field label="עבור">
          <Select value={form.entity} onChange={(e) => setForm((f) => ({ ...f, entity: e.target.value }))}>
            <option value="task">משימות</option>
            <option value="event">אירועים</option>
          </Select>
        </Field>
        <Field label="צבע">
          <input type="color" value={form.color} onChange={(e) => setForm((f) => ({ ...f, color: e.target.value }))} className="h-9 w-14 cursor-pointer rounded border border-[var(--border)] bg-transparent" />
        </Field>
        <Checkbox label="סטטוס סוגר (הושלם/בוטל)" checked={form.is_terminal} onChange={(v) => setForm((f) => ({ ...f, is_terminal: v }))} />
        <Button variant="primary" onClick={() => add.mutate()}><Plus size={14} /> הוספה</Button>
      </div>
      {(['task', 'event'] as const).map((entity) => (
        <div key={entity}>
          <h3 className="mb-1 text-xs font-bold text-[var(--muted)]">{entity === 'task' ? 'סטטוסי משימות' : 'סטטוסי אירועים'}</h3>
          <div className="flex flex-wrap gap-2">
            {statuses.filter((s) => s.entity === entity).map((s) => (
              <span key={s.id} className="inline-flex items-center gap-1.5 rounded-full border border-[var(--border)] px-2.5 py-1 text-sm">
                <span className="size-2.5 rounded-full" style={{ background: s.color }} />
                {s.name}
                {s.is_default && <Badge>ברירת מחדל</Badge>}
                {s.is_terminal && <Badge>סוגר</Badge>}
                {!s.is_default && (
                  <button
                    className="text-[var(--muted)] hover:text-red-500"
                    onClick={async () => {
                      if (await confirm(`למחוק את "${s.name}"?`)) del.mutate({ table: 'statuses', id: s.id })
                    }}
                  >
                    <Trash2 size={12} />
                  </button>
                )}
              </span>
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}

function TrucksTab() {
  const qc = useQueryClient()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const { data: trucks = [] } = useTrucks()
  const [form, setForm] = useState({ name: '', plate_number: '' })
  const del = useSoftDelete('trucks')

  const add = useMutation({
    mutationFn: async () => {
      if (!form.name.trim()) throw new Error('חובה להזין שם משאית')
      const { error } = await supabase.from('trucks').insert(form)
      if (error) throw error
    },
    onSuccess: () => {
      setForm({ name: '', plate_number: '' })
      void qc.invalidateQueries({ queryKey: ['trucks'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <div className="surface max-w-2xl space-y-3 p-4">
      {dialog}
      <div className="flex flex-wrap items-end gap-2">
        <Field label="שם משאית"><Input value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} /></Field>
        <Field label="מספר רישוי"><Input dir="ltr" value={form.plate_number} onChange={(e) => setForm((f) => ({ ...f, plate_number: e.target.value }))} /></Field>
        <Button variant="primary" onClick={() => add.mutate()}><Plus size={14} /> הוספה</Button>
      </div>
      <div className="divide-y divide-[var(--border)]">
        {trucks.length === 0 && <p className="py-3 text-sm text-[var(--muted)]">אין משאיות</p>}
        {trucks.map((t) => (
          <div key={t.id} className="flex items-center justify-between py-2">
            <div>
              <p className="text-sm font-medium">{t.name}</p>
              <p className="text-xs text-[var(--muted)]" dir="ltr">{t.plate_number}</p>
            </div>
            <button
              className="text-[var(--muted)] hover:text-red-500"
              onClick={async () => {
                if (await confirm(`למחוק את "${t.name}"?`)) del.mutate({ table: 'trucks', id: t.id })
              }}
            >
              <Trash2 size={14} />
            </button>
          </div>
        ))}
      </div>
    </div>
  )
}

function RecycleBinTab() {
  const { me } = useAuth()
  const qc = useQueryClient()
  const toast = useToast()
  const [table, setTable] = useState('events')

  const { data: rows = [], isLoading } = useQuery({
    queryKey: ['recycle', table],
    queryFn: async () => {
      const { data, error } = await supabase
        .from(table)
        .select('*')
        .not('deleted_at', 'is', null)
        .order('deleted_at', { ascending: false })
        .limit(100)
      if (error) throw error
      return data as Record<string, unknown>[]
    },
  })

  const restore = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('soft_delete', { p_table: table, p_id: id, p_restore: true })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('שוחזר בהצלחה')
      void qc.invalidateQueries({ queryKey: ['recycle'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  if (!me?.profile.is_admin) return <p className="text-sm text-[var(--muted)]">סל המיחזור זמין למנהלי מערכת בלבד.</p>

  const labelOf = (r: Record<string, unknown>) =>
    (r.name as string) || (r.end_client_name as string) || (r.full_name as string) || (r.title as string) || (r.id as string)

  return (
    <div className="surface max-w-2xl space-y-3 p-4">
      <Select className="max-w-52" value={table} onChange={(e) => setTable(e.target.value)}>
        <option value="events">אירועים</option>
        <option value="tasks">משימות</option>
        <option value="customers">לקוחות</option>
        <option value="contractors">קבלנים</option>
        <option value="profiles">משתמשים</option>
        <option value="suppliers">ספקים</option>
        <option value="trucks">משאיות</option>
        <option value="task_types">סוגי משימות</option>
        <option value="execution_methods">אופני ביצוע</option>
        <option value="statuses">סטטוסים</option>
      </Select>
      {isLoading ? (
        <Spinner full />
      ) : rows.length === 0 ? (
        <EmptyState text="סל המיחזור ריק" />
      ) : (
        <div className="divide-y divide-[var(--border)]">
          {rows.map((r) => (
            <div key={r.id as string} className="flex items-center justify-between py-2">
              <div>
                <p className="text-sm font-medium">{labelOf(r)}</p>
                <p className="text-xs text-[var(--muted)]">נמחק: {fmtDateTime(r.deleted_at as string)}</p>
              </div>
              <Button onClick={() => restore.mutate(r.id as string)}>
                <RotateCcw size={13} /> שחזור
              </Button>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

function AuditLogTab() {
  const { me } = useAuth()
  const { data: rows = [], isLoading } = useQuery({
    queryKey: ['audit', 'global'],
    enabled: !!me?.profile.is_admin,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('audit_log')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(200)
      if (error) throw error
      return data as {
        id: number
        action: 'INSERT' | 'UPDATE' | 'DELETE'
        table_name: string
        changed_cols: string[] | null
        created_at: string
      }[]
    },
  })

  if (!me?.profile.is_admin) return <p className="text-sm text-[var(--muted)]">יומן הפעילות זמין למנהלי מערכת בלבד.</p>
  if (isLoading) return <Spinner full />

  const colors = { INSERT: '#22c55e', UPDATE: '#3b82f6', DELETE: '#ef4444' }
  const labels = { INSERT: 'יצירה', UPDATE: 'עדכון', DELETE: 'מחיקה' }

  return (
    <div className="surface max-w-3xl overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-[var(--border)] text-xs text-[var(--muted)]">
            <th className="px-3 py-2 text-start">זמן</th>
            <th className="px-3 py-2 text-start">פעולה</th>
            <th className="px-3 py-2 text-start">טבלה</th>
            <th className="px-3 py-2 text-start">שדות שהשתנו</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.id} className="border-b border-[var(--border)] last:border-0">
              <td className="px-3 py-2 whitespace-nowrap text-xs">{fmtDateTime(r.created_at)}</td>
              <td className="px-3 py-2"><Badge color={colors[r.action]}>{labels[r.action]}</Badge></td>
              <td className="px-3 py-2 text-xs">{r.table_name}</td>
              <td className="max-w-64 truncate px-3 py-2 text-xs text-[var(--muted)]">
                {(r.changed_cols ?? []).filter((c) => !['updated_at', 'search_tsv'].includes(c)).join(', ')}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
