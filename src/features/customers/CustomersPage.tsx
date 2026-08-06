import { useState } from 'react'
import { Link } from 'react-router'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Building2, ICON, Mail, Phone, Plus, STROKE, User } from '../../components/ui/icons'
import {
  Badge,
  Button,
  Card,
  Checkbox,
  EmptyState,
  Field,
  Input,
  Modal,
  PageHeader,
  SearchInput,
  SkeletonCard,
  StatusPill,
  Tooltip,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { useCustomers } from '../../lib/queries'
import { RequirePermission } from '../auth/guards'

export default function CustomersPage() {
  const { can } = useAuth()
  const { data: customers = [], isLoading } = useCustomers()
  const [createOpen, setCreateOpen] = useState(false)
  const [q, setQ] = useState('')

  const needle = q.trim().toLowerCase()
  const filtered = customers.filter(
    (c) =>
      !needle ||
      c.name.toLowerCase().includes(needle) ||
      (c.contact_name ?? '').toLowerCase().includes(needle) ||
      (c.contact_phone ?? '').includes(needle),
  )

  return (
    <RequirePermission resource="customers">
      <div className="space-y-4">
        <PageHeader
          title="לקוחות"
          subtitle={isLoading ? 'טוען...' : `${customers.length} לקוחות · ${customers.filter((c) => c.is_active).length} פעילים`}
          actions={
            can('customers', 'create') && (
              <Button size="sm" variant="primary" onClick={() => setCreateOpen(true)}>
                <Plus size={ICON.sm} strokeWidth={STROKE} />
                לקוח חדש
              </Button>
            )
          }
        >
          <SearchInput
            className="max-w-xs"
            inputSize="sm"
            placeholder="חיפוש לפי שם, איש קשר או טלפון..."
            value={q}
            onChange={(e) => setQ(e.target.value)}
            onClear={() => setQ('')}
            aria-label="חיפוש לקוח"
          />
        </PageHeader>

        {isLoading ? (
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
            {Array.from({ length: 8 }).map((_, i) => (
              <SkeletonCard key={i} lines={1} />
            ))}
          </div>
        ) : filtered.length === 0 ? (
          <Card>
            <EmptyState
              art="people"
              title={needle ? 'אין לקוחות תואמים' : 'עדיין אין לקוחות'}
              description={
                needle
                  ? 'נסה מונח חיפוש אחר'
                  : 'לקוח חדש מקבל אוטומטית קונפיגורציית שדות טופס ואופני ביצוע לפי ברירת המחדל'
              }
              action={
                needle ? (
                  <Button size="sm" onClick={() => setQ('')}>
                    ניקוי חיפוש
                  </Button>
                ) : (
                  can('customers', 'create') && (
                    <Button size="sm" variant="primary" onClick={() => setCreateOpen(true)}>
                      <Plus size={ICON.sm} />
                      לקוח חדש
                    </Button>
                  )
                )
              }
            />
          </Card>
        ) : (
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
            {filtered.map((c) => (
              <Card key={c.id} as="article" interactive className="group relative">
                {/* the customer colour is the card's identity, not decoration */}
                <span aria-hidden className="absolute inset-x-0 top-0 h-1" style={{ background: c.color }} />
                <Link to={`/customers/${c.id}`} className="block p-4 pt-5 focus-visible:outline-none focus-visible:focus-ring">
                  <div className="flex items-start gap-2.5">
                    <span
                      className="flex size-9 shrink-0 items-center justify-center rounded-xl"
                      style={{ background: `color-mix(in srgb, ${c.color} 14%, transparent)`, color: c.color }}
                      aria-hidden
                    >
                      <Building2 size={ICON.lg} strokeWidth={STROKE} />
                    </span>
                    <div className="min-w-0 flex-1">
                      <h2 className="truncate type-title">{c.name}</h2>
                      <p className="mt-0.5 truncate type-caption text-ink-tertiary">
                        {c.contact_name || 'ללא איש קשר'}
                      </p>
                    </div>
                    {!c.is_active && <StatusPill color="#8a93a5">לא פעיל</StatusPill>}
                  </div>

                  <div className="mt-3 flex flex-wrap items-center gap-1.5">
                    {c.can_create_events && (
                      <Badge tone="success" dot>
                        יוצר אירועים
                      </Badge>
                    )}
                    {c.contact_phone && (
                      <Tooltip content={c.contact_phone}>
                        <span className="inline-flex items-center gap-1 rounded-full bg-subtle px-2 py-0.5 type-caption tabular text-ink-secondary" dir="ltr">
                          <Phone size={10} />
                          {c.contact_phone}
                        </span>
                      </Tooltip>
                    )}
                    {c.contact_email && (
                      <Tooltip content={c.contact_email}>
                        <span className="inline-flex max-w-40 items-center gap-1 rounded-full bg-subtle px-2 py-0.5 type-caption text-ink-secondary">
                          <Mail size={10} className="shrink-0" />
                          <span className="truncate" dir="ltr">
                            {c.contact_email}
                          </span>
                        </span>
                      </Tooltip>
                    )}
                  </div>
                </Link>
              </Card>
            ))}
          </div>
        )}

        <CreateCustomerModal open={createOpen} onClose={() => setCreateOpen(false)} />
      </div>
    </RequirePermission>
  )
}

const PRESET_COLORS = ['#3563f0', '#8b5cf6', '#ec4899', '#ef4444', '#f59e0b', '#16a34a', '#1fa189', '#0ea5e9']

function CreateCustomerModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const qc = useQueryClient()
  const toast = useToast()
  const [form, setForm] = useState({
    name: '',
    color: '#3563f0',
    contact_name: '',
    contact_phone: '',
    contact_email: '',
    can_create_events: false,
  })
  const [touched, setTouched] = useState(false)

  const nameError = touched && !form.name.trim() ? 'חובה להזין שם לקוח' : undefined

  const save = useMutation({
    mutationFn: async () => {
      if (!form.name.trim()) throw new Error('חובה להזין שם לקוח')
      const { error } = await supabase.from('customers').insert(form)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('הלקוח נוצר', { description: 'אופני ביצוע ושדות טופס נזרעו אוטומטית' })
      void qc.invalidateQueries({ queryKey: ['customers'] })
      setForm({ name: '', color: '#3563f0', contact_name: '', contact_phone: '', contact_email: '', can_create_events: false })
      setTouched(false)
      onClose()
    },
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="לקוח חדש"
      description="שדות הטופס ואופני הביצוע ייווצרו אוטומטית לפי ברירת המחדל"
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
        <Field label="שם הלקוח" required error={nameError}>
          <Input
            data-autofocus
            value={form.name}
            onBlur={() => setTouched(true)}
            onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))}
          />
        </Field>

        <Field label="צבע בלוח השנה" hint="הצבע מזהה את הלקוח בכל המסכים">
          <div className="flex flex-wrap items-center gap-1.5">
            {PRESET_COLORS.map((c) => (
              <button
                key={c}
                type="button"
                aria-label={`בחירת צבע ${c}`}
                aria-pressed={form.color === c}
                onClick={() => setForm((f) => ({ ...f, color: c }))}
                className="size-7 rounded-lg transition-transform hover:scale-110 focus-visible:outline-none focus-visible:focus-ring"
                style={{
                  background: c,
                  boxShadow: form.color === c ? `0 0 0 2px var(--vl-surface), 0 0 0 4px ${c}` : undefined,
                }}
              />
            ))}
            <input
              type="color"
              aria-label="צבע מותאם אישית"
              value={form.color}
              onChange={(e) => setForm((f) => ({ ...f, color: e.target.value }))}
              className="size-7 cursor-pointer rounded-lg border border-line bg-transparent p-0.5"
            />
          </div>
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
              value={form.contact_phone}
              onChange={(e) => setForm((f) => ({ ...f, contact_phone: e.target.value }))}
            />
          </Field>
        </div>

        <Field label="אימייל">
          <Input
            dir="ltr"
            type="email"
            leading={<Mail size={ICON.sm} />}
            value={form.contact_email}
            onChange={(e) => setForm((f) => ({ ...f, contact_email: e.target.value }))}
          />
        </Field>

        <div className="rounded-lg border border-line-subtle bg-subtle/50 p-3">
          <Checkbox
            label="רשאי ליצור אירועים בעצמו"
            description="משתמשי הלקוח יוכלו להזין אירועים ישירות במערכת"
            checked={form.can_create_events}
            onChange={(v) => setForm((f) => ({ ...f, can_create_events: v }))}
          />
        </div>
      </div>
    </Modal>
  )
}
