import { useEffect, useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Boxes,
  Building2,
  Calculator,
  ClipboardList,
  Eye,
  EyeOff,
  ICON,
  Mail,
  Package,
  Pencil,
  Percent,
  Phone,
  Plus,
  STROKE,
  Shield,
  SlidersHorizontal,
  Star,
  Trash2,
  Truck,
  User,
} from '../../components/ui/icons'
import {
  Badge,
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
  SkeletonTable,
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
  useBoardFields,
  useCustomerBoardConfig,
  useCustomerExecutionMethods,
  useCustomerTrucks,
  useCustomerFormConfig,
  useExecutionMethods,
  useFormFields,
  useSuppliers,
  useTaskTypeMethods,
  useTaskTypes,
  useTrucks,
} from '../../lib/queries'
import { usePageTitle } from '../../app/breadcrumbs'
import PricingTab from './PricingTab'
import IncomeSplitTab from './IncomeSplitTab'
import { useWarehouses } from '../attendance/attendanceQueries'
import { RequirePermission } from '../auth/guards'
import type {
  BoardFieldState,
  Customer,
  CustomFieldType,
  FieldState,
  Supplier,
} from '../../types/domain'
import { errorMessage } from '../../lib/errors'

const TABS = [
  { key: 'details', label: 'פרטים', icon: <Building2 size={ICON.sm} />, perm: PERM.CUSTOMERS_VIEW },
  { key: 'fields', label: 'שדות טופס', icon: <SlidersHorizontal size={ICON.sm} />, perm: PERM.CUSTOMERS_VIEW },
  /* ‏0109: הלשונית היחידה שאינה נגזרת ממפתח אלא ממנהל המערכת. `adminOnly`
     ולא מפתח במרשם — מפתח אפשר להעניק, ו"רק מנהל מערכת" נאמר כדי שלא. */
  { key: 'board', label: 'שדות הלו״ז', icon: <ClipboardList size={ICON.sm} />, perm: PERM.CUSTOMERS_VIEW, adminOnly: true },
  { key: 'methods', label: 'אופני ביצוע', icon: <Boxes size={ICON.sm} />, perm: PERM.CUSTOMERS_VIEW },
  /* ‏0116: אינה adminOnly כמו "שדות הלו״ז" — זו החלטה תפעולית על קטלוג, לא
     גבול הרשאות, ולכן יש לה מפתח: אותו `settings.trucks` שפותח את הקטלוג
     הגלובלי במסך ההגדרות. */
  { key: 'trucks', label: 'משאיות', icon: <Truck size={ICON.sm} />, perm: PERM.SETTINGS_TRUCKS },
  { key: 'suppliers', label: 'ספקים', icon: <Package size={ICON.sm} />, perm: PERM.CUSTOMERS_VIEW },
  { key: 'pricing', label: 'תמחור', icon: <Calculator size={ICON.sm} />, perm: PERM.PRICING_MANAGE_RULES },
  { key: 'income', label: 'חלוקת הכנסות', icon: <Percent size={ICON.sm} />, perm: PERM.FINANCE_MANAGE_SPLITS },
] as const

export default function CustomerDetailPage() {
  const { id } = useParams<{ id: string }>()
  const [tab, setTab] = useState<(typeof TABS)[number]['key']>('details')
  const { has } = useAuth()
  const isAdmin = !!useAuth((st) => st.me)?.profile.is_admin
  const visibleTabs = TABS.filter((t) => has(t.perm) && (!('adminOnly' in t) || isAdmin))

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
        {tab === 'board' && <BoardFieldsTab customerId={customer.id} />}
        {tab === 'methods' && <MethodsTab customerId={customer.id} />}
        {tab === 'trucks' && <CustomerTrucksTab customerId={customer.id} />}
        {tab === 'suppliers' && <SuppliersTab customerId={customer.id} />}
        {tab === 'pricing' && <PricingTab customer={customer} />}
        {tab === 'income' && <IncomeSplitTab customerId={customer.id} />}
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
    if (error) return toast.error(errorMessage(error))
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

/**
 * שדות הלו״ז של לקוח אחד (0109).
 *
 * שלוש מדרגות ולא שתיים, וזו כל ההבחנה שהמסך הזה קיים בשבילה: **מוסתר** —
 * השדה אינו מצויר אצלו כלל; **נראה** — הוא קורא ואינו נוגע; **עריכה** — הוא
 * גם משנה. עד כאן התשובה נגזרה מהמפתחות של התפקיד, כלומר הייתה זהה לכל
 * הלקוחות; מעכשיו היא נשאלת פר-לקוח, ומי שעונה עליה הוא מנהל המערכת.
 *
 * ההכרעה נאכפת בשרת ולא כאן: `app.enforce_customer_board_edit` דוחה כתיבה
 * לשדה שאינו `editable`, ולכן שינוי כאן משנה גם את מה שהמסך מצייר וגם את מה
 * שהשרת מקבל — ואי אפשר להם להיפרד.
 */
const BOARD_STATES = [
  { key: 'hidden' as const, label: 'מוסתר', icon: <EyeOff size={12} /> },
  { key: 'visible' as const, label: 'נראה', icon: <Eye size={12} /> },
  { key: 'editable' as const, label: 'עריכה', icon: <Pencil size={12} /> },
]

function BoardFieldsTab({ customerId }: { customerId: string }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { data: fields = [], isLoading } = useBoardFields()
  const { data: config = [] } = useCustomerBoardConfig(customerId)
  const stateOf = (key: string): BoardFieldState =>
    config.find((c) => c.field_key === key)?.state ?? 'visible'

  const update = useMutation({
    mutationFn: async ({ key, state }: { key: string; state: BoardFieldState }) => {
      const { error } = await supabase
        .from('customer_board_fields')
        .upsert({ customer_id: customerId, field_key: key, state })
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['customer_board_fields', customerId] }),
    onError: (e) => toast.error(errorMessage(e)),
  })

  const setAll = useMutation({
    mutationFn: async (state: BoardFieldState) => {
      const { error } = await supabase.from('customer_board_fields').upsert(
        fields.map((f) => ({ customer_id: customerId, field_key: f.field_key, state })),
      )
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['customer_board_fields', customerId] }),
    onError: (e) => toast.error(errorMessage(e)),
  })

  const counts = fields.reduce(
    (acc, f) => {
      acc[stateOf(f.field_key)]++
      return acc
    },
    { hidden: 0, visible: 0, editable: 0 } as Record<BoardFieldState, number>,
  )

  if (isLoading) return <SkeletonTable rows={6} cols={2} />

  return (
    <Card>
      <CardHeader
        title="שדות הלו״ז"
        subtitle="מה הלקוח הזה רואה בלוח העבודה, ומה הוא גם רשאי לשנות"
        icon={<ClipboardList size={ICON.md} strokeWidth={STROKE} />}
        actions={
          <span className="flex flex-wrap items-center gap-1.5">
            <Badge>{counts.visible} נראים</Badge>
            <Badge tone="primary">{counts.editable} לעריכה</Badge>
            {counts.hidden > 0 && <Badge tone="neutral">{counts.hidden} מוסתרים</Badge>}
          </span>
        }
      />
      <CardBody className="p-0">
        <p className="border-b border-line-subtle px-4 py-2.5 type-caption text-ink-secondary">
          שדה ב״עריכה״ נפתח ללקוח גם בשרת. שים לב ששדות שמזיזים כסף — משך, כמות
          עובדים ואופן ביצוע — מריצים מחדש את חישוב המחיר, ולכן מי שרשאי לשנות
          אותם משנה גם את מה שהוא ישלם.
        </p>
        <ul>
          {fields.map((f) => (
            <li
              key={f.field_key}
              className="flex items-center gap-3 border-b border-line-subtle px-4 py-2.5 last:border-0"
            >
              <span className="min-w-0 flex-1">
                <span className="block truncate type-body font-medium">{f.label_he}</span>
                {/* שדה בלי עמודה אינו נכתב מהלוח כלל — "עריכה" עליו היא הבטחה
                    שאין מי שיקיים, ולכן הוא מוצע כמוסתר/נראה בלבד */}
                {!f.column_name && (
                  <span className="type-caption text-ink-tertiary">לקריאה בלבד בלוח</span>
                )}
              </span>
              <SegmentedControl
                items={f.column_name ? BOARD_STATES : BOARD_STATES.filter((x) => x.key !== 'editable')}
                value={stateOf(f.field_key)}
                onChange={(state) => update.mutate({ key: f.field_key, state })}
              />
            </li>
          ))}
        </ul>
        <div className="flex flex-wrap items-center gap-2 px-4 py-3">
          <span className="type-caption text-ink-tertiary">החלה על הכול:</span>
          <Button size="sm" loading={setAll.isPending} onClick={() => setAll.mutate('hidden')}>
            הכול מוסתר
          </Button>
          <Button size="sm" loading={setAll.isPending} onClick={() => setAll.mutate('visible')}>
            הכול נראה
          </Button>
        </div>
      </CardBody>
    </Card>
  )
}

const FIELD_STATES = [
  { key: 'visible' as const, label: 'מוצג', icon: <Eye size={12} /> },
  { key: 'hidden' as const, label: 'מוסתר', icon: <EyeOff size={12} /> },
  { key: 'required' as const, label: 'חובה', icon: <span className="text-error">*</span> },
]

/** The shapes a custom field can take, in the order the picker offers them. */
const CUSTOM_FIELD_TYPES: { key: CustomFieldType; label: string }[] = [
  { key: 'text', label: 'טקסט' },
  { key: 'textarea', label: 'טקסט ארוך' },
  { key: 'number', label: 'מספר' },
  { key: 'date', label: 'תאריך' },
  { key: 'time', label: 'שעה' },
  { key: 'select', label: 'בחירה מרשימה' },
  { key: 'checkbox', label: 'כן / לא' },
]

const typeLabel = (t: CustomFieldType) => CUSTOM_FIELD_TYPES.find((x) => x.key === t)?.label ?? t

function FieldsTab({ customerId }: { customerId: string }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { has } = useAuth()
  const { confirm, dialog } = useConfirm()
  const canEdit = has(PERM.CUSTOMERS_MANAGE_FORM_FIELDS)
  const { data: fields = [], isLoading } = useFormFields(customerId)
  const { data: config = [] } = useCustomerFormConfig(customerId)
  const stateOf = (key: string): FieldState => config.find((c) => c.field_key === key)?.state ?? 'visible'

  const systemFields = fields.filter((f) => f.customer_id === null)
  const customFields = fields.filter((f) => f.customer_id !== null)

  const [newLabel, setNewLabel] = useState('')
  const [newType, setNewType] = useState<CustomFieldType>('text')
  const [newOptions, setNewOptions] = useState('')

  const invalidate = () => {
    void qc.invalidateQueries({ queryKey: ['form_fields'] })
    void qc.invalidateQueries({ queryKey: ['customer_form_fields', customerId] })
  }

  const update = useMutation({
    mutationFn: async ({ key, state }: { key: string; state: FieldState }) => {
      const { error } = await supabase.from('customer_form_fields').upsert({ customer_id: customerId, field_key: key, state })
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['customer_form_fields', customerId] }),
    onError: (e) => toast.error(errorMessage(e)),
  })

  /* The key is minted server-side: one chosen here could collide with a real
     column name ('notes', 'event_date') and be read twice out of the payload. */
  const create = useMutation({
    mutationFn: async () => {
      const options = newOptions
        .split('\n')
        .map((o) => o.trim())
        .filter(Boolean)
      const { error } = await supabase.rpc('create_custom_form_field', {
        p_customer_id: customerId,
        p_label: newLabel.trim(),
        p_type: newType,
        p_options: options,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('השדה נוסף')
      setNewLabel('')
      setNewOptions('')
      setNewType('text')
      invalidate()
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const remove = useMutation({
    mutationFn: async (key: string) => {
      const { error } = await supabase.rpc('delete_custom_form_field', { p_field_key: key })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('השדה נמחק')
      invalidate()
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const askRemove = async (key: string, label: string) => {
    if (
      !(await confirm('השדה יירד מהטופס. ערכים שכבר נשמרו באירועים קיימים נשמרים ואינם מוצגים עוד.', {
        title: `מחיקת השדה "${label}"`,
        confirmLabel: 'מחיקה',
      }))
    )
      return
    remove.mutate(key)
  }

  const counts = fields.reduce(
    (acc, f) => {
      acc[stateOf(f.field_key)]++
      return acc
    },
    { visible: 0, hidden: 0, required: 0 } as Record<FieldState, number>,
  )

  const stateRow = (f: (typeof fields)[number], locked: boolean, extra?: React.ReactNode) => (
    <li key={f.field_key} className="flex items-center gap-3 border-b border-line-subtle px-4 py-2.5 last:border-0">
      <span className="min-w-0 flex-1">
        <span className="block truncate type-body font-medium">{f.label_he}</span>
        {locked && <span className="type-caption text-ink-tertiary">שדה חובה קבוע</span>}
        {f.customer_id !== null && (
          <span className="type-caption text-ink-tertiary">
            {typeLabel(f.field_type)}
            {f.field_type === 'select' && f.options.length > 0 ? ` · ${f.options.join(' / ')}` : ''}
          </span>
        )}
      </span>
      <SegmentedControl
        items={FIELD_STATES}
        value={locked ? 'required' : stateOf(f.field_key)}
        onChange={(state) => !locked && canEdit && update.mutate({ key: f.field_key, state })}
        className={!canEdit || locked ? 'pointer-events-none opacity-55' : undefined}
      />
      {extra}
    </li>
  )

  return (
    <div className="max-w-2xl space-y-5">
      {dialog}

      <Card>
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
            <ul>{systemFields.map((f) => stateRow(f, f.field_key === 'event_date'))}</ul>
          )}
        </CardBody>
      </Card>

      {/* ── the customer's own fields ─────────────────────────────────────
          A field defined here is a row in form_fields carrying this
          customer's id, so it flows through the very same visible/hidden/
          required config as everything in the card above.                */}
      <Card>
        <CardHeader
          title="שדות מותאמים אישית"
          subtitle="שדות שנוספו ללקוח זה בלבד — הם אינם מופיעים אצל לקוחות אחרים"
          icon={<Plus size={ICON.md} strokeWidth={STROKE} />}
        />
        <CardBody padded={false}>
          {customFields.length > 0 ? (
            <ul>
              {customFields.map((f) =>
                stateRow(
                  f,
                  false,
                  canEdit ? (
                    <IconButton
                      label={`מחיקת ${f.label_he}`}
                      variant="danger"
                      size="sm"
                      onClick={() => void askRemove(f.field_key, f.label_he)}
                    >
                      <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                    </IconButton>
                  ) : undefined,
                ),
              )}
            </ul>
          ) : (
            <p className="border-b border-line-subtle px-4 py-3 type-caption text-ink-tertiary">
              אין עדיין שדות מותאמים אישית ללקוח זה.
            </p>
          )}

          {canEdit && (
            <div className="space-y-3 p-4">
              <div className="grid gap-3 sm:grid-cols-2">
                <Field label="שם השדה" required>
                  <Input value={newLabel} onChange={(e) => setNewLabel(e.target.value)} placeholder="לדוגמה: מספר הזמנת רכש" />
                </Field>
                <Field label="סוג השדה">
                  <Select value={newType} onChange={(e) => setNewType(e.target.value as CustomFieldType)}>
                    {CUSTOM_FIELD_TYPES.map((t) => (
                      <option key={t.key} value={t.key}>
                        {t.label}
                      </option>
                    ))}
                  </Select>
                </Field>
              </div>
              {newType === 'select' && (
                <Field label="ערכי הרשימה" hint="ערך בכל שורה">
                  <Textarea rows={3} value={newOptions} onChange={(e) => setNewOptions(e.target.value)} />
                </Field>
              )}
              <Button
                size="sm"
                variant="primary"
                loading={create.isPending}
                disabled={!newLabel.trim() || (newType === 'select' && !newOptions.trim())}
                onClick={() => create.mutate()}
              >
                <Plus size={ICON.sm} strokeWidth={STROKE} />
                הוספת שדה
              </Button>
            </div>
          )}
        </CardBody>
      </Card>
    </div>
  )
}

/* ===== execution methods ================================================== */

function MethodsTab({ customerId }: { customerId: string }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { has } = useAuth()
  const canEdit = has(PERM.CUSTOMERS_MANAGE_FORM_FIELDS)
  const { data: methods = [] } = useExecutionMethods()
  const { data: enabledRows = [] } = useCustomerExecutionMethods(customerId)
  const enabled = useMemo(() => enabledRows.map((r) => r.execution_method_id), [enabledRows])
  const defaultId = enabledRows.find((r) => r.is_default)?.execution_method_id ?? null
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

  /**
   * ברירת המחדל (0111). שתי כתיבות ולא אחת: האינדקס מתיר שורת `is_default`
   * אחת ללקוח, ולכן הקודמת חייבת לרדת לפני שהחדשה עולה — באותה טרנזקציה זה
   * היה נופל על האינדקס.
   */
  const setDefault = useMutation({
    mutationFn: async (methodId: string | null) => {
      const clear = await supabase
        .from('customer_execution_methods')
        .update({ is_default: false })
        .eq('customer_id', customerId)
        .eq('is_default', true)
      if (clear.error) throw clear.error
      if (!methodId) return
      const { error } = await supabase
        .from('customer_execution_methods')
        .update({ is_default: true })
        .eq('customer_id', customerId)
        .eq('execution_method_id', methodId)
      if (error) throw error
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
              הכוכב מסמן את ברירת המחדל: כל משימה חדשה של הלקוח נולדת איתה, גם
              כשהיא נוצרת ממקום שאין בו בורר.
            </p>
            {groups.map((g) => (
              <div key={g.label} className="space-y-2">
                <p className="type-overline">
                  {g.label} · {g.items.filter((m) => enabled.includes(m.id)).length}/{g.items.length}
                </p>
                <div className="grid gap-2 sm:grid-cols-2">
                  {g.items.map((m) => (
                    <div
                      key={m.id}
                      className="flex items-center gap-2 rounded-lg border border-line-subtle p-2.5 transition-colors hover:bg-hover"
                    >
                      <label className="min-w-0 flex-1 cursor-pointer">
                        <Checkbox
                          label={m.name}
                          checked={enabled.includes(m.id)}
                          onChange={(v) => toggle.mutate({ methodId: m.id, on: v })}
                          disabled={!canEdit}
                        />
                      </label>
                      {/* ברירת המחדל מוצעת רק על אופן שכבר הותר — היא חייבת
                          להיות אחד מהם, וזה מה שהאינדקס בשרת מבטיח (0111). */}
                      {enabled.includes(m.id) && (
                        <IconButton
                          label={defaultId === m.id ? `${m.name} — ברירת המחדל` : `הגדרת ${m.name} כברירת מחדל`}
                          size="sm"
                          bare
                          disabled={!canEdit || setDefault.isPending}
                          onClick={() => setDefault.mutate(defaultId === m.id ? null : m.id)}
                        >
                          <Star
                            size={ICON.sm}
                            strokeWidth={STROKE}
                            className={defaultId === m.id ? 'fill-warning text-warning' : 'text-ink-tertiary'}
                          />
                        </IconButton>
                      )}
                    </div>
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

/* ===== המשאיות של הלקוח (0116) ============================================ */

/**
 * אילו משאיות מהקטלוג הגלובלי זמינות ללקוח הזה בלו״ז.
 *
 * **ריק אינו "אין משאיות" אלא "אין הגבלה"**, וזו ההכרעה שמאפשרת לתכונה
 * לעלות בלי לגעת באף לקוח קיים. הכותרת אומרת זאת במפורש, כי מסך שמראה אפס
 * מסומנים ולא מסביר נקרא כמסך שאוסר הכול.
 *
 * האכיפה אינה כאן: `app.enforce_customer_trucks` דוחה שיבוץ של משאית שאינה
 * ברשימה גם כשהוא מגיע בלי לעבור במסך.
 */
function CustomerTrucksTab({ customerId }: { customerId: string }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { has } = useAuth()
  const canEdit = has(PERM.SETTINGS_TRUCKS)
  const { data: trucks = [] } = useTrucks()
  const { data: rows = [] } = useCustomerTrucks()

  const mine = useMemo(
    () => new Set(rows.filter((r) => r.customer_id === customerId).map((r) => r.truck_id)),
    [rows, customerId],
  )
  const active = useMemo(() => trucks.filter((t) => t.is_active || mine.has(t.id)), [trucks, mine])

  const toggle = useMutation({
    mutationFn: async ({ truckId, on }: { truckId: string; on: boolean }) => {
      if (on) {
        const { error } = await supabase
          .from('customer_trucks')
          .insert({ customer_id: customerId, truck_id: truckId })
        if (error) throw error
      } else {
        const { error } = await supabase
          .from('customer_trucks')
          .delete()
          .eq('customer_id', customerId)
          .eq('truck_id', truckId)
        if (error) throw error
      }
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['customer_trucks'] }),
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <Card className="max-w-2xl">
      <CardHeader
        title="המשאיות של הלקוח"
        subtitle={mine.size === 0 ? 'לא הוגדרה רשימה — כל המשאיות זמינות' : `${mine.size} מתוך ${active.length}`}
        icon={<Truck size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody className="space-y-4">
        {active.length === 0 ? (
          <EmptyState
            compact
            art="box"
            title="לא הוגדרו משאיות"
            description="ניתן להגדיר אותן במסך ההגדרות"
          />
        ) : (
          <>
            <p className="type-caption text-ink-secondary">
              מה שמסומן כאן הוא מה שהלקוח יראה בבורר המשאיות בלו״ז. כל עוד לא
              סומנה אף משאית — הרשימה שלו היא הקטלוג כולו, ולא רשימה ריקה.
            </p>
            <div className="grid gap-2 sm:grid-cols-2">
              {active.map((t) => (
                <label
                  key={t.id}
                  className="flex min-w-0 cursor-pointer items-center gap-2 rounded-lg border border-line-subtle p-2.5 transition-colors hover:bg-hover"
                >
                  <Checkbox
                    label={t.plate_number ? `${t.name} · ${t.plate_number}` : t.name}
                    checked={mine.has(t.id)}
                    onChange={(v) => toggle.mutate({ truckId: t.id, on: v })}
                    disabled={!canEdit}
                  />
                </label>
              ))}
            </div>
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
    if (error) toast.error(errorMessage(error))
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
              <Input type="tel" autoComplete="tel" inputSize="sm" dir="ltr" value={form.phone} onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))} />
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
