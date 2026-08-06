import { useState } from 'react'
import { Link } from 'react-router'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Plus } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { Badge, Button, Field, Input, Modal, Spinner, EmptyState, useToast, Checkbox } from '../../components/ui'
import { useCustomers } from '../../lib/queries'
import { RequirePermission } from '../auth/guards'

export default function CustomersPage() {
  const { can } = useAuth()
  const { data: customers = [], isLoading } = useCustomers()
  const [createOpen, setCreateOpen] = useState(false)
  const [q, setQ] = useState('')

  const filtered = customers.filter((c) => c.name.includes(q))

  return (
    <RequirePermission resource="customers">
      <div className="space-y-3">
        <div className="flex items-center gap-2">
          <h1 className="text-xl font-bold">לקוחות</h1>
          <div className="ms-auto">
            {can('customers', 'create') && (
              <Button variant="primary" onClick={() => setCreateOpen(true)}>
                <Plus size={14} /> לקוח חדש
              </Button>
            )}
          </div>
        </div>
        <Input className="max-w-xs" placeholder="חיפוש לקוח..." value={q} onChange={(e) => setQ(e.target.value)} />
        {isLoading ? (
          <Spinner full />
        ) : filtered.length === 0 ? (
          <EmptyState text="אין לקוחות" />
        ) : (
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
            {filtered.map((c) => (
              <Link key={c.id} to={`/customers/${c.id}`} className="surface p-4 transition-shadow hover:shadow-md">
                <div className="flex items-center gap-2">
                  <span className="size-3 rounded-full" style={{ background: c.color }} />
                  <span className="font-bold">{c.name}</span>
                  {!c.is_active && <Badge>לא פעיל</Badge>}
                </div>
                <p className="mt-1 text-sm text-[var(--muted)]">{c.contact_name || '—'}</p>
                <div className="mt-2 flex gap-1">
                  {c.can_create_events && <Badge color="#22c55e">יוצר אירועים</Badge>}
                </div>
              </Link>
            ))}
          </div>
        )}
        <CreateCustomerModal open={createOpen} onClose={() => setCreateOpen(false)} />
      </div>
    </RequirePermission>
  )
}

function CreateCustomerModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const qc = useQueryClient()
  const toast = useToast()
  const [form, setForm] = useState({ name: '', color: '#3b82f6', contact_name: '', contact_phone: '', contact_email: '', can_create_events: false })

  const save = useMutation({
    mutationFn: async () => {
      if (!form.name.trim()) throw new Error('חובה להזין שם לקוח')
      const { error } = await supabase.from('customers').insert(form)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('הלקוח נוצר — אופני ביצוע ושדות טופס נזרעו אוטומטית')
      void qc.invalidateQueries({ queryKey: ['customers'] })
      setForm({ name: '', color: '#3b82f6', contact_name: '', contact_phone: '', contact_email: '', can_create_events: false })
      onClose()
    },
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <Modal open={open} onClose={onClose} title="לקוח חדש">
      <div className="space-y-3">
        <Field label="שם הלקוח" required>
          <Input value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} />
        </Field>
        <Field label="צבע בלוח השנה">
          <input type="color" value={form.color} onChange={(e) => setForm((f) => ({ ...f, color: e.target.value }))} className="h-9 w-16 cursor-pointer rounded border border-[var(--border)] bg-transparent" />
        </Field>
        <div className="grid grid-cols-2 gap-3">
          <Field label="איש קשר">
            <Input value={form.contact_name} onChange={(e) => setForm((f) => ({ ...f, contact_name: e.target.value }))} />
          </Field>
          <Field label="טלפון">
            <Input dir="ltr" value={form.contact_phone} onChange={(e) => setForm((f) => ({ ...f, contact_phone: e.target.value }))} />
          </Field>
        </div>
        <Field label="אימייל">
          <Input dir="ltr" type="email" value={form.contact_email} onChange={(e) => setForm((f) => ({ ...f, contact_email: e.target.value }))} />
        </Field>
        <Checkbox label="רשאי ליצור אירועים בעצמו" checked={form.can_create_events} onChange={(v) => setForm((f) => ({ ...f, can_create_events: v }))} />
        <div className="flex justify-end gap-2 pt-2">
          <Button onClick={onClose}>ביטול</Button>
          <Button variant="primary" loading={save.isPending} onClick={() => save.mutate()}>יצירה</Button>
        </div>
      </div>
    </Modal>
  )
}
