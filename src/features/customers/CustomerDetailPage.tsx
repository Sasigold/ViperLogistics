import { useEffect, useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Boxes,
  Building2,
  Calculator,
  Eye,
  EyeOff,
  ICON,
  Mail,
  Package,
  Phone,
  Plus,
  STROKE,
  Shield,
  SlidersHorizontal,
  Trash2,
  User,
} from '../../components/ui/icons'
import {
  Button,
  Card,
  CardBody,
  CardHeader,
  Checkbox,
  EmptyState,
  Field,
  IconButton,
  Input,
  PageHeader,
  SegmentedControl,
  Select,
  Skeleton,
  ErrorState,
  StatusPill,
  Switch,
  Tabs,
  Textarea,
  useConfirm,
  useToast,
  StickySaveBar,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import {
  useCustomerExecutionMethods,
  useCustomerFormConfig,
  useExecutionMethods,
  useFormFields,
  useSuppliers,
  useTaskTypeMethods,
  useTaskTypes,
} from '../../lib/queries'
import { usePageTitle } from '../../app/breadcrumbs'
import PricingTab from './PricingTab'
import { useWarehouses } from '../attendance/attendanceQueries'
import { RequirePermission } from '../auth/guards'
import type { Customer, FieldState, Supplier } from '../../types/domain'
import { errorMessage } from '../../lib/errors'

const TABS = [
  { key: 'details', label: 'פרטים', icon: <Building2 size={ICON.sm} />, perm: PERM.CUSTOMERS_VIEW },
  { key: 'fields', label: 'שדות טופס', icon: <SlidersHorizontal size={ICON.sm} />, perm: PERM.CUSTOMERS_VIEW },
  { key: 'methods', label: 'אופני ביצוע', icon: <Boxes size={ICON.sm} />, perm: PERM.CUSTOMERS_VIEW },
  { key: 'suppliers', label: 'ספקים', icon: <Package size={ICON.sm} />, perm: PERM.CUSTOMERS_VIEW },
  { key: 'pricing', label: 'תמחור', icon: <Calculator size={ICON.sm} />, perm: PERM.PRICING_MANAGE_RULES },
] as const

export default function CustomerDetailPage() {
  const { id } = useParams<{ id: string }>()
  const [tab, setTab] = useState<(typeof TABS)[number]['key']>('details')
  const { has } = useAuth()
  const visibleTabs = TABS.filter((t) => has(t.perm))

  const { data: customer, isLoading, error, refetch } = useQuery({
    queryKey: ['customers', 'one', id],
    queryFn: async () => {
      const { data, error } = await supabase.from('customers').select('*').eq('id', id).single()
      if (error) throw error
      return data as Customer
    },
  })

  usePageTitle(customer?.name ?? null)

  if (isLoading || !customer) {
    // שאילתה שנכשלה משאירה isLoading=false ו-customer=undefined, ולכן בלי
    // הענף הזה המסך היה נשאר שלד לנצח — נראה כמו טעינה ולא ככישלון.
    if (error) return <ErrorState error={error} onRetry={() => void refetch()} />
    return (
      <div className="space-y-4">
        <Skeleton className="h-8 w-56" />
        <Skeleton className="h-10 w-full max-w-md" />
        <Skeleton className="h-72 w-full max-w-2xl" />
      </div>
    )
  }

  return (
    <RequirePermission perm={PERM.CUSTOMERS_VIEW}>
      <div className="space-y-4">
        <PageHeader
          title={
            <span className="flex flex-wrap items-center gap-2.5">
              <span
                className="flex size-9 shrink-0 items-center justify-center rounded-xl"
                style={{ background: `color-mix(in srgb, ${customer.color} 14%, transparent)`, color: customer.color }}
                aria-hidden
              >
                <Building2 size={ICON.lg} strokeWidth={STROKE} />
              </span>
              {customer.name}
              {!customer.is_active && <StatusPill color="#8a93a5">לא פעיל</StatusPill>}
              {customer.can_create_events && <StatusPill color="#16a34a">יוצר אירועים</StatusPill>}
            </span>
          }
          subtitle={[customer.contact_name, customer.contact_phone].filter(Boolean).join(' · ') || 'ללא פרטי קשר'}
        >
          <Tabs items={visibleTabs} value={tab} onChange={setTab} />
        </PageHeader>

        {tab === 'details' && <DetailsTab customer={customer} />}
        {tab === 'fields' && <FieldsTab customerId={customer.id} />}
        {tab === 'methods' && <MethodsTab customerId={customer.id} />}
        {tab === 'suppliers' && <SuppliersTab customerId={customer.id} />}
        {tab === 'pricing' && <PricingTab customer={customer} />}
      </div>
    </RequirePermission>
  )
}

/* ===== details ============================================================ */

const PRESET_COLORS = ['#3563f0', '#8b5cf6', '#ec4899', '#ef4444', '#f59e0b', '#16a34a', '#1fa189', '#0ea5e9']

function DetailsTab({ customer }: { customer: Customer }) {
  const qc = useQueryClient()
  const toast = useToast()
  const navigate = useNavigate()
  const { has } = useAuth()
  const { confirm, dialog } = useConfirm()
  const [form, setForm] = useState(customer)
  useEffect(() => setForm(customer), [customer])
  const canEdit = has(PERM.CUSTOMERS_EDIT)
  const { data: warehouses = [] } = useWarehouses()

  const dirty = useMemo(
    () =>
      (['name', 'color', 'can_create_events', 'contact_name', 'contact_phone', 'contact_email', 'notes', 'is_active', 'warehouse_id'] as const).some(
        (k) => form[k] !== customer[k],
      ),
    [form, customer],
  )

  const save = useMutation({
    mutationFn: async () => {
      if (!form.name.trim()) throw new Error('חובה להזין שם לקוח')
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
          warehouse_id: form.warehouse_id,
        })
        .eq('id', customer.id)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('הלקוח עודכן')
      void qc.invalidateQueries({ queryKey: ['customers'] })
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const remove = async () => {
    if (
      !(await confirm('למחוק את הלקוח? האירועים והמשימות שלו יוסתרו.', {
        title: 'מחיקת לקוח',
        confirmLabel: 'מחיקה',
      }))
    )
      return
    const { error } = await supabase.rpc('soft_delete', { p_table: 'customers', p_id: customer.id })
    if (error) return toast.error(error.message)
    toast.success('הלקוח נמחק')
    void qc.invalidateQueries({ queryKey: ['customers'] })
    navigate('/customers')
  }

  return (
    <div className="max-w-2xl space-y-4">
      {dialog}
      <Card>
        <CardHeader title="פרטי הלקוח" icon={<Building2 size={ICON.md} strokeWidth={STROKE} />} />
        <CardBody className="space-y-4">
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="שם" required error={!form.name.trim() ? 'חובה להזין שם לקוח' : undefined}>
              <Input value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} disabled={!canEdit} />
            </Field>
            <Field label="איש קשר">
              <Input
                leading={<User size={ICON.sm} />}
                value={form.contact_name ?? ''}
                onChange={(e) => setForm((f) => ({ ...f, contact_name: e.target.value }))}
                disabled={!canEdit}
              />
            </Field>
            <Field label="טלפון">
              <Input
                dir="ltr"
                leading={<Phone size={ICON.sm} />}
                value={form.contact_phone ?? ''}
                onChange={(e) => setForm((f) => ({ ...f, contact_phone: e.target.value }))}
                disabled={!canEdit}
              />
            </Field>
            <Field label="אימייל">
              <Input
                dir="ltr"
                type="email"
                leading={<Mail size={ICON.sm} />}
                value={form.contact_email ?? ''}
                onChange={(e) => setForm((f) => ({ ...f, contact_email: e.target.value }))}
                disabled={!canEdit}
              />
            </Field>
          </div>

          <Field label="צבע מזהה" hint="מופיע בלוח השנה, בלוח העבודה ובדשבורד">
            <div className="flex flex-wrap items-center gap-1.5">
              {PRESET_COLORS.map((c) => (
                <button
                  key={c}
                  type="button"
                  disabled={!canEdit}
                  aria-label={`בחירת צבע ${c}`}
                  aria-pressed={form.color === c}
                  onClick={() => setForm((f) => ({ ...f, color: c }))}
                  className="size-7 rounded-lg transition-transform hover:scale-110 disabled:pointer-events-none focus-visible:outline-none focus-visible:focus-ring"
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
                disabled={!canEdit}
                onChange={(e) => setForm((f) => ({ ...f, color: e.target.value }))}
                className="size-7 cursor-pointer rounded-lg border border-line bg-transparent p-0.5"
              />
            </div>
          </Field>

          {/* המחסן של הלקוח הוא נקודת הייחוס שמולה נמדדת החתמת עובד
              שמתחיל את המשמרת במחסן, בכל המשימות של הלקוח הזה. */}
          <Field
            label="מחסן"
            hint="ממנו יוצאים למשימות של הלקוח, ומולו נמדדת החתמת מי שמתחיל במחסן"
          >
            <Select
              value={form.warehouse_id ?? ''}
              onChange={(e) => setForm((f) => ({ ...f, warehouse_id: e.target.value || null }))}
              disabled={!canEdit}
            >
              <option value="">ללא מחסן</option>
              {warehouses
                .filter((w) => w.is_active || w.id === form.warehouse_id)
                .map((w) => (
                  <option key={w.id} value={w.id}>
                    {w.name}
                  </option>
                ))}
            </Select>
          </Field>

          <Field label="הערות">
            <Textarea
              autoGrow
              value={form.notes ?? ''}
              onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))}
              disabled={!canEdit}
            />
          </Field>

          <div className="space-y-3 rounded-lg border border-line-subtle bg-subtle/50 p-3">
            <Switch
              checked={form.can_create_events}
              onChange={(v) => setForm((f) => ({ ...f, can_create_events: v }))}
              disabled={!canEdit}
              label="רשאי ליצור אירועים"
              description="משתמשי הלקוח יוכלו להזין אירועים ישירות"
            />
            <Switch
              checked={form.is_active}
              onChange={(v) => setForm((f) => ({ ...f, is_active: v }))}
              disabled={!canEdit}
              label="לקוח פעיל"
              description="לקוח לא פעיל לא יופיע ברשימות בחירה"
            />
          </div>
        </CardBody>
        {canEdit && (
          <StickySaveBar dirty={dirty} saving={save.isPending} onSave={() => save.mutate()} onReset={() => setForm(customer)} />
        )}
      </Card>

      {has(PERM.CUSTOMERS_DELETE) && (
        <Card className="border-error-border">
          <CardHeader
            title="אזור מסוכן"
            subtitle="מחיקה רכה — ניתן לשחזר מסל המיחזור בהגדרות"
            icon={<Shield size={ICON.md} strokeWidth={STROKE} />}
          />
          <CardBody>
            <Button variant="danger" size="sm" onClick={() => void remove()}>
              <Trash2 size={ICON.sm} strokeWidth={STROKE} />
              מחיקת הלקוח
            </Button>
          </CardBody>
        </Card>
      )}
    </div>
  )
}

/* ===== form field configuration =========================================== */

const FIELD_STATES = [
  { key: 'visible' as const, label: 'מוצג', icon: <Eye size={12} /> },
  { key: 'hidden' as const, label: 'מוסתר', icon: <EyeOff size={12} /> },
  { key: 'required' as const, label: 'חובה', icon: <span className="text-error">*</span> },
]

function FieldsTab({ customerId }: { customerId: string }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { has } = useAuth()
  const canEdit = has(PERM.CUSTOMERS_MANAGE_FORM_FIELDS)
  const { data: fields = [], isLoading } = useFormFields()
  const { data: config = [] } = useCustomerFormConfig(customerId)
  const stateOf = (key: string): FieldState => config.find((c) => c.field_key === key)?.state ?? 'visible'

  const update = useMutation({
    mutationFn: async ({ key, state }: { key: string; state: FieldState }) => {
      const { error } = await supabase.from('customer_form_fields').upsert({ customer_id: customerId, field_key: key, state })
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['customer_form_fields', customerId] }),
    onError: (e) => toast.error(errorMessage(e)),
  })

  const counts = fields.reduce(
    (acc, f) => {
      acc[stateOf(f.field_key)]++
      return acc
    },
    { visible: 0, hidden: 0, required: 0 } as Record<FieldState, number>,
  )

  return (
    <Card className="max-w-2xl">
      <CardHeader
        title="שדות טופס יצירת אירוע"
        subtitle={`${counts.visible} מוצגים · ${counts.required} חובה · ${counts.hidden} מוסתרים`}
        icon={<SlidersHorizontal size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody padded={false}>
        <p className="border-b border-line-subtle bg-subtle/40 px-4 py-2.5 type-caption text-ink-secondary">
          ההגדרה חלה על הטופס שרואים משתמשי הלקוח. אנשי הצוות רואים תמיד את כל השדות.
        </p>
        {isLoading ? (
          <div className="p-4">
            <Skeleton className="h-40 w-full" />
          </div>
        ) : (
          <ul>
            {fields.map((f) => {
              const locked = f.field_key === 'event_date'
              return (
                <li key={f.field_key} className="flex items-center gap-3 border-b border-line-subtle px-4 py-2.5 last:border-0">
                  <span className="min-w-0 flex-1">
                    <span className="block truncate type-body font-medium">{f.label_he}</span>
                    {locked && <span className="type-caption text-ink-tertiary">שדה חובה קבוע</span>}
                  </span>
                  <SegmentedControl
                    items={FIELD_STATES}
                    value={locked ? 'required' : stateOf(f.field_key)}
                    onChange={(state) => !locked && canEdit && update.mutate({ key: f.field_key, state })}
                    className={!canEdit || locked ? 'pointer-events-none opacity-55' : undefined}
                  />
                </li>
              )
            })}
          </ul>
        )}
      </CardBody>
    </Card>
  )
}

/* ===== execution methods ================================================== */

function MethodsTab({ customerId }: { customerId: string }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { has } = useAuth()
  const canEdit = has(PERM.CUSTOMERS_MANAGE_FORM_FIELDS)
  const { data: methods = [] } = useExecutionMethods()
  const { data: enabled = [] } = useCustomerExecutionMethods(customerId)
  const { data: taskTypes = [] } = useTaskTypes()
  const { data: typeMethods = [] } = useTaskTypeMethods()

  /* Grouped by task type so it is obvious which section of the event form each
     method feeds. A method mapped to both types appears in both groups — there
     is one customer_execution_methods row per method, so the state is shared. */
  const groups = useMemo(() => {
    const idsFor = (code: string) => {
      const t = taskTypes.find((x) => x.code === code)
      return new Set(t ? typeMethods.filter((m) => m.task_type_id === t.id).map((m) => m.execution_method_id) : [])
    }
    const setupIds = idsFor('setup')
    const teardownIds = idsFor('teardown')
    return [
      { label: 'הקמה', items: methods.filter((m) => setupIds.has(m.id)) },
      { label: 'פירוק', items: methods.filter((m) => teardownIds.has(m.id)) },
      { label: 'סוגי משימות אחרים', items: methods.filter((m) => !setupIds.has(m.id) && !teardownIds.has(m.id)) },
    ].filter((g) => g.items.length > 0)
  }, [methods, taskTypes, typeMethods])

  const toggle = useMutation({
    mutationFn: async ({ methodId, on }: { methodId: string; on: boolean }) => {
      if (on) {
        const { error } = await supabase
          .from('customer_execution_methods')
          .insert({ customer_id: customerId, execution_method_id: methodId })
        if (error) throw error
      } else {
        const { error } = await supabase
          .from('customer_execution_methods')
          .delete()
          .eq('customer_id', customerId)
          .eq('execution_method_id', methodId)
        if (error) throw error
      }
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['customer_execution_methods', customerId] }),
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <Card className="max-w-2xl">
      <CardHeader
        title="אופני ביצוע זמינים"
        subtitle={`${enabled.length} מתוך ${methods.length} מופעלים`}
        icon={<Boxes size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody className="space-y-5">
        {methods.length === 0 ? (
          <EmptyState compact art="box" title="לא הוגדרו אופני ביצוע" description="ניתן להגדיר אותם במסך ההגדרות" />
        ) : (
          <>
            <p className="type-caption text-ink-secondary">
              אופן ביצוע המשותף לשני הסעיפים מופיע בשניהם — כיבויו משפיע על שניהם.
            </p>
            {groups.map((g) => (
              <div key={g.label} className="space-y-2">
                <p className="type-overline">
                  {g.label} · {g.items.filter((m) => enabled.includes(m.id)).length}/{g.items.length}
                </p>
                <div className="grid gap-2 sm:grid-cols-2">
                  {g.items.map((m) => (
                    <label
                      key={m.id}
                      className="flex cursor-pointer items-center gap-2 rounded-lg border border-line-subtle p-2.5 transition-colors hover:bg-hover"
                    >
                      <Checkbox
                        label={m.name}
                        checked={enabled.includes(m.id)}
                        onChange={(v) => toggle.mutate({ methodId: m.id, on: v })}
                        disabled={!canEdit}
                      />
                    </label>
                  ))}
                </div>
              </div>
            ))}
          </>
        )}
      </CardBody>
    </Card>
  )
}

/* ===== suppliers ========================================================== */

function SuppliersTab({ customerId }: { customerId: string }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { has } = useAuth()
  const canEdit = has(PERM.CUSTOMERS_MANAGE_FORM_FIELDS)
  const { data: suppliers = [], isLoading } = useSuppliers(customerId)
  const [form, setForm] = useState({ name: '', phone: '', address: '' })
  const { confirm, dialog } = useConfirm()

  const add = useMutation({
    mutationFn: async () => {
      if (!form.name.trim()) throw new Error('חובה להזין שם ספק')
      const { error } = await supabase.from('suppliers').insert({ customer_id: customerId, ...form })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('הספק נוסף')
      setForm({ name: '', phone: '', address: '' })
      void qc.invalidateQueries({ queryKey: ['suppliers', 'byCustomer', customerId] })
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const remove = async (s: Supplier) => {
    if (!(await confirm(`למחוק את הספק "${s.name}"?`, { title: 'מחיקת ספק', confirmLabel: 'מחיקה' }))) return
    const { error } = await supabase.rpc('soft_delete', { p_table: 'suppliers', p_id: s.id })
    if (error) toast.error(error.message)
    else {
      toast.success('הספק נמחק')
      void qc.invalidateQueries({ queryKey: ['suppliers', 'byCustomer', customerId] })
    }
  }

  return (
    <Card className="max-w-2xl">
      {dialog}
      <CardHeader
        title="ספקים"
        subtitle={`${suppliers.length} ספקים · משמשים לתוספת "איסוף מספקים"`}
        icon={<Package size={ICON.md} strokeWidth={STROKE} />}
      />
      {canEdit && (
        <div className="border-b border-line-subtle bg-subtle/40 p-4">
          <form
            className="flex flex-wrap items-end gap-2"
            onSubmit={(e) => {
              e.preventDefault()
              add.mutate()
            }}
          >
            <Field label="שם ספק" className="min-w-36 flex-1">
              <Input inputSize="sm" value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} />
            </Field>
            <Field label="טלפון" className="w-32">
              <Input inputSize="sm" dir="ltr" value={form.phone} onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))} />
            </Field>
            <Field label="כתובת" className="min-w-36 flex-1">
              <Input inputSize="sm" value={form.address} onChange={(e) => setForm((f) => ({ ...f, address: e.target.value }))} />
            </Field>
            <Button type="submit" size="sm" variant="primary" loading={add.isPending} disabled={!form.name.trim()}>
              <Plus size={ICON.sm} strokeWidth={STROKE} />
              הוספה
            </Button>
          </form>
        </div>
      )}
      <CardBody padded={false}>
        {isLoading ? (
          <div className="p-4">
            <Skeleton className="h-24 w-full" />
          </div>
        ) : suppliers.length === 0 ? (
          <EmptyState
            compact
            art="box"
            title="אין ספקים"
            description={canEdit ? 'הוסף ספקים כדי לאפשר בחירה בטופס האירוע' : undefined}
          />
        ) : (
          <ul>
            {suppliers.map((s) => (
              <li key={s.id} className="flex items-center gap-3 border-b border-line-subtle px-4 py-2.5 last:border-0 hover:bg-hover">
                <span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-subtle text-ink-tertiary" aria-hidden>
                  <Package size={ICON.sm} strokeWidth={STROKE} />
                </span>
                <div className="min-w-0 flex-1">
                  <p className="truncate type-body font-medium">{s.name}</p>
                  <p className="truncate type-caption text-ink-tertiary">
                    {[s.phone, s.address].filter(Boolean).join(' · ') || '—'}
                  </p>
                </div>
                {canEdit && (
                  <IconButton label={`מחיקת ${s.name}`} size="sm" className="hover:text-error" onClick={() => void remove(s)}>
                    <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                  </IconButton>
                )}
              </li>
            ))}
          </ul>
        )}
      </CardBody>
    </Card>
  )
}
