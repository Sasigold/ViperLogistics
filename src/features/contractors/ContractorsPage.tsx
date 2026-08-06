import { useState } from 'react'
import { Link } from 'react-router'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Plus } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { Badge, Button, Field, Input, Modal, Spinner, EmptyState, useToast } from '../../components/ui'
import { useContractors } from '../../lib/queries'
import { RequirePermission } from '../auth/guards'

export default function ContractorsPage() {
  const { can } = useAuth()
  const { data: contractors = [], isLoading } = useContractors()
  const [createOpen, setCreateOpen] = useState(false)

  return (
    <RequirePermission resource="contractors">
      <div className="space-y-3">
        <div className="flex items-center gap-2">
          <h1 className="text-xl font-bold">קבלנים</h1>
          <div className="ms-auto">
            {can('contractors', 'create') && (
              <Button variant="primary" onClick={() => setCreateOpen(true)}>
                <Plus size={14} /> קבלן חדש
              </Button>
            )}
          </div>
        </div>
        {isLoading ? (
          <Spinner full />
        ) : contractors.length === 0 ? (
          <EmptyState text="אין קבלנים" />
        ) : (
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {contractors.map((c) => (
              <Link key={c.id} to={`/contractors/${c.id}`} className="surface p-4 transition-shadow hover:shadow-md">
                <div className="flex items-center gap-2">
                  <span className="font-bold">{c.name}</span>
                  {!c.is_active && <Badge>לא פעיל</Badge>}
                </div>
                <p className="mt-1 text-sm text-[var(--muted)]">{[c.contact_name, c.phone].filter(Boolean).join(' · ') || '—'}</p>
                {c.default_task_price != null && (
                  <p className="mt-1 text-xs text-[var(--muted)]">מחיר ברירת מחדל: ₪{c.default_task_price}</p>
                )}
              </Link>
            ))}
          </div>
        )}
        <CreateContractorModal open={createOpen} onClose={() => setCreateOpen(false)} />
      </div>
    </RequirePermission>
  )
}

function CreateContractorModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const qc = useQueryClient()
  const toast = useToast()
  const [form, setForm] = useState({ name: '', contact_name: '', phone: '', email: '', default_task_price: '' })

  const save = useMutation({
    mutationFn: async () => {
      if (!form.name.trim()) throw new Error('חובה להזין שם קבלן')
      const { error } = await supabase.from('contractors').insert({
        ...form,
        default_task_price: form.default_task_price === '' ? null : Number(form.default_task_price),
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('הקבלן נוצר')
      void qc.invalidateQueries({ queryKey: ['contractors'] })
      setForm({ name: '', contact_name: '', phone: '', email: '', default_task_price: '' })
      onClose()
    },
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <Modal open={open} onClose={onClose} title="קבלן חדש">
      <div className="space-y-3">
        <Field label="שם" required>
          <Input value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} />
        </Field>
        <div className="grid grid-cols-2 gap-3">
          <Field label="איש קשר">
            <Input value={form.contact_name} onChange={(e) => setForm((f) => ({ ...f, contact_name: e.target.value }))} />
          </Field>
          <Field label="טלפון">
            <Input dir="ltr" value={form.phone} onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))} />
          </Field>
          <Field label="אימייל">
            <Input dir="ltr" type="email" value={form.email} onChange={(e) => setForm((f) => ({ ...f, email: e.target.value }))} />
          </Field>
          <Field label="מחיר ברירת מחדל למשימה (₪)">
            <Input type="number" min="0" value={form.default_task_price} onChange={(e) => setForm((f) => ({ ...f, default_task_price: e.target.value }))} />
          </Field>
        </div>
        <div className="flex justify-end gap-2 pt-2">
          <Button onClick={onClose}>ביטול</Button>
          <Button variant="primary" loading={save.isPending} onClick={() => save.mutate()}>יצירה</Button>
        </div>
      </div>
    </Modal>
  )
}
