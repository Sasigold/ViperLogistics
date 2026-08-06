import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Trash2 } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { Button, Checkbox, Field, Input, Select, Spinner, Textarea, useConfirm, useToast, cx } from '../../components/ui'
import { useCustomerExecutionMethods, useCustomerFormConfig, useExecutionMethods, useFormFields, useSuppliers } from '../../lib/queries'
import { RequirePermission } from '../auth/guards'
import type { Customer, FieldState, Supplier } from '../../types/domain'

const tabs = [
  { key: 'details', label: 'פרטים' },
  { key: 'fields', label: 'שדות טופס' },
  { key: 'methods', label: 'אופני ביצוע' },
  { key: 'suppliers', label: 'ספקים' },
] as const

export default function CustomerDetailPage() {
  const { id } = useParams<{ id: string }>()
  const [tab, setTab] = useState<(typeof tabs)[number]['key']>('details')

  const { data: customer, isLoading } = useQuery({
    queryKey: ['customers', 'one', id],
    queryFn: async () => {
      const { data, error } = await supabase.from('customers').select('*').eq('id', id).single()
      if (error) throw error
      return data as Customer
    },
  })

  if (isLoading || !customer) return <Spinner full />

  return (
    <RequirePermission resource="customers">
      <div className="space-y-4">
        <div className="flex items-center gap-3">
          <span className="size-4 rounded-full" style={{ background: customer.color }} />
          <h1 className="text-xl font-bold">{customer.name}</h1>
        </div>
        <div className="flex gap-1 border-b border-[var(--border)]">
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
        {tab === 'details' && <DetailsTab customer={customer} />}
        {tab === 'fields' && <FieldsTab customerId={customer.id} />}
        {tab === 'methods' && <MethodsTab customerId={customer.id} />}
        {tab === 'suppliers' && <SuppliersTab customerId={customer.id} />}
      </div>
    </RequirePermission>
  )
}

function DetailsTab({ customer }: { customer: Customer }) {
  const qc = useQueryClient()
  const toast = useToast()
  const navigate = useNavigate()
  const { can } = useAuth()
  const { confirm, dialog } = useConfirm()
  const [form, setForm] = useState(customer)
  useEffect(() => setForm(customer), [customer])
  const canEdit = can('customers', 'edit')

  const save = useMutation({
    mutationFn: async () => {
      const { error } = await supabase
        .from('customers')
        .update({
          name: form.name,
          color: form.color,
          can_create_events: form.can_create_events,
          contact_name: form.contact_name,
          contact_phone: form.contact_phone,
          contact_email: form.contact_email,
          notes: form.notes,
          is_active: form.is_active,
        })
        .eq('id', customer.id)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('הלקוח עודכן')
      void qc.invalidateQueries({ queryKey: ['customers'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const remove = async () => {
    if (!(await confirm('למחוק את הלקוח? האירועים והמשימות שלו יוסתרו.'))) return
    const { error } = await supabase.rpc('soft_delete', { p_table: 'customers', p_id: customer.id })
    if (error) return toast.error(error.message)
    toast.success('הלקוח נמחק')
    void qc.invalidateQueries({ queryKey: ['customers'] })
    navigate('/customers')
  }

  return (
    <div className="surface max-w-2xl space-y-3 p-4">
      {dialog}
      <div className="grid grid-cols-2 gap-3">
        <Field label="שם" required>
          <Input value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} disabled={!canEdit} />
        </Field>
        <Field label="צבע">
          <input type="color" value={form.color} onChange={(e) => setForm((f) => ({ ...f, color: e.target.value }))} disabled={!canEdit} className="h-9 w-16 cursor-pointer rounded border border-[var(--border)] bg-transparent" />
        </Field>
        <Field label="איש קשר">
          <Input value={form.contact_name ?? ''} onChange={(e) => setForm((f) => ({ ...f, contact_name: e.target.value }))} disabled={!canEdit} />
        </Field>
        <Field label="טלפון">
          <Input dir="ltr" value={form.contact_phone ?? ''} onChange={(e) => setForm((f) => ({ ...f, contact_phone: e.target.value }))} disabled={!canEdit} />
        </Field>
        <Field label="אימייל">
          <Input dir="ltr" value={form.contact_email ?? ''} onChange={(e) => setForm((f) => ({ ...f, contact_email: e.target.value }))} disabled={!canEdit} />
        </Field>
      </div>
      <Field label="הערות">
        <Textarea value={form.notes ?? ''} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} disabled={!canEdit} />
      </Field>
      <div className="flex gap-4">
        <Checkbox label="רשאי ליצור אירועים" checked={form.can_create_events} onChange={(v) => setForm((f) => ({ ...f, can_create_events: v }))} disabled={!canEdit} />
        <Checkbox label="פעיל" checked={form.is_active} onChange={(v) => setForm((f) => ({ ...f, is_active: v }))} disabled={!canEdit} />
      </div>
      <div className="flex justify-between pt-2">
        {can('customers', 'delete') ? (
          <Button variant="danger" onClick={() => void remove()}><Trash2 size={14} /> מחיקה</Button>
        ) : <span />}
        {canEdit && <Button variant="primary" loading={save.isPending} onClick={() => save.mutate()}>שמירה</Button>}
      </div>
    </div>
  )
}

function FieldsTab({ customerId }: { customerId: string }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { can } = useAuth()
  const canEdit = can('customers', 'edit') || can('settings', 'edit')
  const { data: fields = [] } = useFormFields()
  const { data: config = [] } = useCustomerFormConfig(customerId)
  const stateOf = (key: string): FieldState => config.find((c) => c.field_key === key)?.state ?? 'visible'

  const update = useMutation({
    mutationFn: async ({ key, state }: { key: string; state: FieldState }) => {
      const { error } = await supabase
        .from('customer_form_fields')
        .upsert({ customer_id: customerId, field_key: key, state })
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['customer_form_fields', customerId] }),
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <div className="surface max-w-2xl p-4">
      <p className="mb-3 text-sm text-[var(--muted)]">
        קביעה אילו שדות יוצגו ללקוח בטופס יצירת אירוע, אילו יוסתרו ואילו יהיו חובה.
      </p>
      <div className="divide-y divide-[var(--border)]">
        {fields.map((f) => (
          <div key={f.field_key} className="flex items-center justify-between py-2.5">
            <span className="text-sm font-medium">{f.label_he}</span>
            <Select
              className="w-32"
              value={stateOf(f.field_key)}
              disabled={!canEdit || f.field_key === 'event_date'}
              onChange={(e) => update.mutate({ key: f.field_key, state: e.target.value as FieldState })}
            >
              <option value="visible">מוצג</option>
              <option value="hidden">מוסתר</option>
              <option value="required">חובה</option>
            </Select>
          </div>
        ))}
      </div>
    </div>
  )
}

function MethodsTab({ customerId }: { customerId: string }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { can } = useAuth()
  const canEdit = can('customers', 'edit') || can('settings', 'edit')
  const { data: methods = [] } = useExecutionMethods()
  const { data: enabled = [] } = useCustomerExecutionMethods(customerId)

  const toggle = useMutation({
    mutationFn: async ({ methodId, on }: { methodId: string; on: boolean }) => {
      if (on) {
        const { error } = await supabase.from('customer_execution_methods').insert({ customer_id: customerId, execution_method_id: methodId })
        if (error) throw error
      } else {
        const { error } = await supabase.from('customer_execution_methods').delete().eq('customer_id', customerId).eq('execution_method_id', methodId)
        if (error) throw error
      }
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['customer_execution_methods', customerId] }),
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <div className="surface max-w-2xl p-4">
      <p className="mb-3 text-sm text-[var(--muted)]">אילו אופני ביצוע זמינים ללקוח זה.</p>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
        {methods.map((m) => (
          <Checkbox
            key={m.id}
            label={m.name}
            checked={enabled.includes(m.id)}
            onChange={(v) => toggle.mutate({ methodId: m.id, on: v })}
            disabled={!canEdit}
          />
        ))}
      </div>
    </div>
  )
}

function SuppliersTab({ customerId }: { customerId: string }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { can } = useAuth()
  const canEdit = can('customers', 'edit') || can('settings', 'edit')
  const { data: suppliers = [] } = useSuppliers(customerId)
  const [form, setForm] = useState({ name: '', phone: '', address: '' })
  const { confirm, dialog } = useConfirm()

  const add = useMutation({
    mutationFn: async () => {
      if (!form.name.trim()) throw new Error('חובה להזין שם ספק')
      const { error } = await supabase.from('suppliers').insert({ customer_id: customerId, ...form })
      if (error) throw error
    },
    onSuccess: () => {
      setForm({ name: '', phone: '', address: '' })
      void qc.invalidateQueries({ queryKey: ['suppliers', 'byCustomer', customerId] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const remove = async (s: Supplier) => {
    if (!(await confirm(`למחוק את הספק "${s.name}"?`))) return
    const { error } = await supabase.rpc('soft_delete', { p_table: 'suppliers', p_id: s.id })
    if (error) toast.error(error.message)
    else void qc.invalidateQueries({ queryKey: ['suppliers', 'byCustomer', customerId] })
  }

  return (
    <div className="surface max-w-2xl space-y-3 p-4">
      {dialog}
      <p className="text-sm text-[var(--muted)]">רשימת הספקים של הלקוח עבור "איסוף מספקים".</p>
      {canEdit && (
        <div className="flex flex-wrap items-end gap-2">
          <Field label="שם ספק"><Input value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} /></Field>
          <Field label="טלפון"><Input dir="ltr" value={form.phone} onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))} /></Field>
          <Field label="כתובת"><Input value={form.address} onChange={(e) => setForm((f) => ({ ...f, address: e.target.value }))} /></Field>
          <Button variant="primary" loading={add.isPending} onClick={() => add.mutate()}>הוספה</Button>
        </div>
      )}
      <div className="divide-y divide-[var(--border)]">
        {suppliers.length === 0 && <p className="py-3 text-sm text-[var(--muted)]">אין ספקים</p>}
        {suppliers.map((s) => (
          <div key={s.id} className="flex items-center justify-between py-2">
            <div>
              <p className="text-sm font-medium">{s.name}</p>
              <p className="text-xs text-[var(--muted)]">{[s.phone, s.address].filter(Boolean).join(' · ')}</p>
            </div>
            {canEdit && (
              <button onClick={() => void remove(s)} className="text-[var(--muted)] hover:text-red-500">
                <Trash2 size={14} />
              </button>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}
