import { useState } from 'react'
import { Link } from 'react-router'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { HardHat, ICON, Mail, Phone, Plus, STROKE, User, Wallet } from '../../components/ui/icons'
import {
  Avatar,
  Button,
  Card,
  EmptyState,
  Field,
  Input,
  Modal,
  PageHeader,
  SearchInput,
  SkeletonCard,
  StatusPill,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { useContractors } from '../../lib/queries'
import { fmtMoney } from '../../lib/dates'
import { RequirePermission } from '../auth/guards'
import { errorMessage } from '../../lib/errors'

export default function ContractorsPage() {
  const { has } = useAuth()
  const { data: contractors = [], isLoading } = useContractors()
  const [createOpen, setCreateOpen] = useState(false)
  const [q, setQ] = useState('')

  const needle = q.trim().toLowerCase()
  const filtered = contractors.filter(
    (c) =>
      !needle ||
      c.name.toLowerCase().includes(needle) ||
      (c.contact_name ?? '').toLowerCase().includes(needle) ||
      (c.phone ?? '').includes(needle),
  )

  return (
    <RequirePermission perm={PERM.CONTRACTORS_VIEW}>
      <div className="space-y-4">
        <PageHeader
          title="קבלנים"
          subtitle={isLoading ? 'טוען...' : `${contractors.length} קבלנים · ${contractors.filter((c) => c.is_active).length} פעילים`}
          actions={
            has(PERM.CONTRACTORS_CREATE) && (
              <Button size="sm" variant="primary" onClick={() => setCreateOpen(true)}>
                <Plus size={ICON.sm} strokeWidth={STROKE} />
                קבלן חדש
              </Button>
            )
          }
        >
          <SearchInput
            className="max-w-xs"
            inputSize="sm"
            placeholder="חיפוש קבלן..."
            value={q}
            onChange={(e) => setQ(e.target.value)}
            onClear={() => setQ('')}
            aria-label="חיפוש קבלן"
          />
        </PageHeader>

        {isLoading ? (
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {Array.from({ length: 6 }).map((_, i) => (
              <SkeletonCard key={i} lines={1} />
            ))}
          </div>
        ) : filtered.length === 0 ? (
          <Card>
            <EmptyState
              art="people"
              title={needle ? 'אין קבלנים תואמים' : 'עדיין אין קבלנים'}
              description={
                needle
                  ? 'נסה מונח חיפוש אחר'
                  : 'קבלן מקבל פורטל משלו שבו הוא משבץ את עובדיו למשימות שהואצלו אליו'
              }
              action={
                needle ? (
                  <Button size="sm" onClick={() => setQ('')}>
                    ניקוי חיפוש
                  </Button>
                ) : (
                  has(PERM.CONTRACTORS_CREATE) && (
                    <Button size="sm" variant="primary" onClick={() => setCreateOpen(true)}>
                      <Plus size={ICON.sm} />
                      קבלן חדש
                    </Button>
                  )
                )
              }
            />
          </Card>
        ) : (
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {filtered.map((c) => (
              <Card key={c.id} as="article" interactive>
                <Link to={`/contractors/${c.id}`} className="block p-4 focus-visible:outline-none focus-visible:focus-ring">
                  <div className="flex items-start gap-2.5">
                    <Avatar name={c.name} size="lg" />
                    <div className="min-w-0 flex-1">
                      <h2 className="truncate type-title">{c.name}</h2>
                      <p className="mt-0.5 truncate type-caption text-ink-tertiary">
                        {c.contact_name || 'ללא איש קשר'}
                      </p>
                    </div>
                    {!c.is_active && <StatusPill color="#8a93a5">לא פעיל</StatusPill>}
                  </div>

                  <div className="mt-3 flex flex-wrap items-center gap-1.5">
                    {c.phone && (
                      <span className="inline-flex items-center gap-1 rounded-full bg-subtle px-2 py-0.5 type-caption tabular text-ink-secondary" dir="ltr">
                        <Phone size={10} />
                        {c.phone}
                      </span>
                    )}
                    {c.default_task_price != null && (
                      <span className="inline-flex items-center gap-1 rounded-full bg-subtle px-2 py-0.5 type-caption tabular text-ink-secondary">
                        <Wallet size={10} />
                        {fmtMoney(c.default_task_price)} למשימה
                      </span>
                    )}
                  </div>
                </Link>
              </Card>
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
  const [touched, setTouched] = useState(false)

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
      setTouched(false)
      onClose()
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="קבלן חדש"
      description="לאחר היצירה ניתן להוסיף לו סגל עובדים ולהאציל אליו משימות"
      footer={
        <>
          <Button onClick={onClose}>ביטול</Button>
          <Button variant="primary" loading={save.isPending} onClick={() => save.mutate()}>
            יצירה
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <Field label="שם הקבלן" required error={touched && !form.name.trim() ? 'חובה להזין שם קבלן' : undefined}>
          <Input
            data-autofocus
            leading={<HardHat size={ICON.sm} strokeWidth={STROKE} />}
            value={form.name}
            onBlur={() => setTouched(true)}
            onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))}
          />
        </Field>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="איש קשר">
            <Input
              leading={<User size={ICON.sm} />}
              value={form.contact_name}
              onChange={(e) => setForm((f) => ({ ...f, contact_name: e.target.value }))}
            />
          </Field>
          <Field label="טלפון">
            <Input
              dir="ltr"
              leading={<Phone size={ICON.sm} />}
              value={form.phone}
              onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))}
            />
          </Field>
          <Field label="אימייל">
            <Input
              dir="ltr"
              type="email"
              leading={<Mail size={ICON.sm} />}
              value={form.email}
              onChange={(e) => setForm((f) => ({ ...f, email: e.target.value }))}
            />
          </Field>
          <Field label="מחיר ברירת מחדל" hint="בשקלים, למשימה">
            <Input
              type="number"
              min="0"
              value={form.default_task_price}
              onChange={(e) => setForm((f) => ({ ...f, default_task_price: e.target.value }))}
            />
          </Field>
        </div>
      </div>
    </Modal>
  )
}
