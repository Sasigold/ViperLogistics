import { useCallback, useEffect, useMemo, useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Check, Clock, ICON, MapPin, Package, PartyPopper, Phone, STROKE, User } from '../../components/ui/icons'
import {
  Button,
  Card,
  CardBody,
  CardHeader,
  Checkbox,
  Field,
  Input,
  Modal,
  MultiSelect,
  Select,
  Textarea,
  cx,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import {
  useAllowedExecutionMethods,
  useEffectiveFormConfig,
  useCustomers,
  useEventAutoTasks,
  useExecutionMethods,
  useStatuses,
  useSuppliers,
  useTaskTypes,
} from '../../lib/queries'
import { AddressAutocomplete } from './AddressAutocomplete'
import type { EventRow, ExecutionMethod } from '../../types/domain'

type EventForm = {
  customer_id: string
  end_client_name: string
  event_number: string
  event_date: string
  location_text: string
  location_provider: string
  location_place_id: string
  location_lat: number | null
  location_lng: number | null
  location_notes: string
  volume_m: string
  truck_count: string
  contact_name: string
  contact_phone: string
  notes: string
  status_id: string
  no_parking: boolean
  porterage: boolean
  supplier_pickup: boolean
  supplier_ids: string[]
  setup_date: string
  setup_time: string
  setup_worker_count: string
  setup_hours_count: string
  setup_execution_method: string
  teardown_date: string
  teardown_time: string
  teardown_worker_count: string
  teardown_hours_count: string
  teardown_execution_method: string
}

const empty: EventForm = {
  customer_id: '', end_client_name: '', event_number: '', event_date: '', location_text: '',
  location_provider: '', location_place_id: '', location_lat: null, location_lng: null,
  location_notes: '', volume_m: '', truck_count: '', contact_name: '', contact_phone: '',
  notes: '', status_id: '', no_parking: false, porterage: false, supplier_pickup: false, supplier_ids: [],
  setup_date: '', setup_time: '', setup_worker_count: '', setup_hours_count: '', setup_execution_method: '',
  teardown_date: '', teardown_time: '', teardown_worker_count: '', teardown_hours_count: '', teardown_execution_method: '',
}

const DRAFT_KEY = 'vl-event-draft'

/** The two auto-created tasks the last wizard step edits. */
const SECTIONS = [
  { code: 'setup' as const, title: 'הקמה' },
  { code: 'teardown' as const, title: 'פירוק' },
]

/** The five per-section fields, with the labels reused from the task drawer. */
const SECTION_LABELS = [
  ['date', 'תאריך'],
  ['time', 'שעה'],
  ['worker_count', 'כמות עובדים'],
  ['hours_count', 'כמות שעות'],
  ['execution_method', 'אופן ביצוע'],
] as const

/** Field keys of one section — same names in form_fields, in the form and in the RPC payload. */
const sectionFields = (code: 'setup' | 'teardown') =>
  [`${code}_date`, `${code}_time`, `${code}_worker_count`, `${code}_hours_count`, `${code}_execution_method`] as const

/** The contact pair is one permission, not two — see the event_contacts policy. */
const CONTACT_KEYS = ['contact_name', 'contact_phone']

/**
 * A form field can sit on several columns, and the two registries name them
 * differently: `form_fields` is form-shaped, `field_registry` column-shaped.
 * Keys absent here map to themselves; the setup/teardown keys have no registry
 * entry and are governed by the form config alone.
 */
const FIELD_COLUMNS: Record<string, string[]> = {
  location: ['location_text'],
  addons: ['no_parking', 'porterage', 'supplier_pickup'],
}
const columnsOf = (key: string) => FIELD_COLUMNS[key] ?? [key]

/** One configurable field can own several payload keys. */
const PAYLOAD_KEYS: Record<string, string[]> = {
  location: ['location_text', 'location_provider', 'location_place_id', 'location_lat', 'location_lng'],
  addons: ['no_parking', 'porterage', 'supplier_pickup', 'supplier_ids'],
  contact_name: ['contact_name'],
  contact_phone: ['contact_phone'],
}

/** Which configurable field keys belong to which step. */
const STEPS = [
  { key: 'basics', label: 'פרטי האירוע', icon: PartyPopper, fields: ['end_client_name', 'event_number', 'event_date'] },
  { key: 'location', label: 'מיקום ואיש קשר', icon: MapPin, fields: ['location', 'location_notes', 'contact_name', 'contact_phone'] },
  { key: 'logistics', label: 'לוגיסטיקה ותוספות', icon: Package, fields: ['volume_m', 'truck_count', 'addons', 'notes'] },
  { key: 'sections', label: 'הקמה ופירוק', icon: Clock, fields: [...sectionFields('setup'), ...sectionFields('teardown')] },
] as const

export function EventFormModal({
  open,
  onClose,
  event,
  contact,
  supplierIds,
}: {
  open: boolean
  onClose: () => void
  /** when set — edit mode */
  event?: EventRow | null
  contact?: { contact_name: string | null; contact_phone: string | null } | null
  supplierIds?: string[]
}) {
  const qc = useQueryClient()
  const toast = useToast()
  const { me, has, canViewField, canEditField } = useAuth()
  const isCustomer = me?.profile.user_kind === 'customer_user'
  const [form, setForm] = useState<EventForm>(empty)
  const [step, setStep] = useState(0)
  const [touched, setTouched] = useState(false)

  const { data: customers = [] } = useCustomers()
  const { data: statuses = [] } = useStatuses('event')
  const effectiveCustomerId = isCustomer ? me?.profile.customer_id : form.customer_id || null
  const config = useEffectiveFormConfig(effectiveCustomerId)
  const { data: suppliers = [] } = useSuppliers(effectiveCustomerId)

  const { data: taskTypes = [] } = useTaskTypes()
  const { data: allMethods = [] } = useExecutionMethods()
  const typeIdOf = (code: string) => taskTypes.find((t) => t.code === code && t.is_active)?.id ?? null
  const setupTypeId = typeIdOf('setup')
  const teardownTypeId = typeIdOf('teardown')
  const setupMethods = useAllowedExecutionMethods(setupTypeId, effectiveCustomerId)
  const teardownMethods = useAllowedExecutionMethods(teardownTypeId, effectiveCustomerId)
  const { data: autoTasks } = useEventAutoTasks(open && event ? event.id : null)

  useEffect(() => {
    if (!open) return
    setStep(0)
    setTouched(false)
    if (event) {
      setForm({
        ...empty,
        customer_id: event.customer_id,
        end_client_name: event.end_client_name ?? '',
        event_number: event.event_number ?? '',
        event_date: event.event_date,
        location_text: event.location_text ?? '',
        location_provider: event.location_provider ?? '',
        location_place_id: event.location_place_id ?? '',
        location_lat: event.location_lat,
        location_lng: event.location_lng,
        location_notes: event.location_notes ?? '',
        volume_m: event.volume_m != null ? String(event.volume_m) : '',
        truck_count: event.truck_count != null ? String(event.truck_count) : '',
        contact_name: contact?.contact_name ?? '',
        contact_phone: contact?.contact_phone ?? '',
        notes: event.notes ?? '',
        status_id: event.status_id ?? '',
        no_parking: event.no_parking,
        porterage: event.porterage,
        supplier_pickup: event.supplier_pickup,
        supplier_ids: supplierIds ?? [],
        // placeholders until the two auto tasks load below
        setup_date: event.event_date,
        teardown_date: event.event_date,
      })
    } else {
      const draft = localStorage.getItem(DRAFT_KEY)
      setForm(draft ? { ...empty, ...(JSON.parse(draft) as Partial<EventForm>) } : empty)
    }
  }, [open, event, contact, supplierIds])

  /** Edit mode: the section values live on the auto-created tasks, not on the event. */
  useEffect(() => {
    if (!open || !event || !autoTasks) return
    const patch: Partial<EventForm> = {}
    for (const { code } of SECTIONS) {
      const t = autoTasks.find((x) => x.task_types.code === code)
      patch[`${code}_date`] = t?.task_date ?? ''
      patch[`${code}_time`] = t?.onsite_start_time?.slice(0, 5) ?? ''
      patch[`${code}_worker_count`] = t?.worker_count ? String(t.worker_count) : ''
      patch[`${code}_hours_count`] = t?.hours_count != null ? String(t.hours_count) : ''
      patch[`${code}_execution_method`] = t?.execution_method_id ?? ''
    }
    setForm((f) => ({ ...f, ...patch }))
  }, [open, event, autoTasks])

  // auto-save draft for new events
  useEffect(() => {
    if (!open || event) return
    const t = setTimeout(() => localStorage.setItem(DRAFT_KEY, JSON.stringify(form)), 600)
    return () => clearTimeout(t)
  }, [form, open, event])

  const fieldState = useMemo(() => {
    const map = new Map(config.map((c) => [c.field_key, c.state]))
    return (key: string): 'visible' | 'hidden' | 'required' => map.get(key) ?? 'visible'
  }, [config])

  /**
   * customers see their configured form; staff see everything but keep required
   * markers. On top of that, a per-field data rule can hide or freeze any field
   * for one user: the config says what the form has, the permission says what
   * this person gets.
   */
  const show = useCallback(
    (key: string) => {
      if (CONTACT_KEYS.includes(key) && !has(PERM.EVENTS_VIEW_CONTACTS)) return false
      if (!columnsOf(key).every((c) => canViewField('event', c))) return false
      if (!isCustomer) return true
      return fieldState(key) !== 'hidden'
    },
    [has, canViewField, isCustomer, fieldState],
  )
  /** A field nobody can see is never a missing required field. */
  const req = useCallback((key: string) => show(key) && fieldState(key) === 'required', [show, fieldState])
  /** Visible but not editable — rendered read-only rather than dropped. */
  const ro = useCallback(
    (key: string) => {
      if (CONTACT_KEYS.includes(key)) return !has(PERM.EVENTS_MANAGE_CONTACTS)
      return !columnsOf(key).every((c) => canEditField('event', c))
    },
    [has, canEditField],
  )

  const set = (patch: Partial<EventForm>) => setForm((f) => ({ ...f, ...patch }))

  /** Steps with no visible field are dropped entirely rather than shown empty. */
  const steps = useMemo(() => STEPS.filter((s) => s.fields.some((f) => show(f))), [show])

  /** A step is incomplete when a field the customer marked "required" is empty. */
  const missingIn = (stepKey: string): string[] => {
    const s = steps.find((x) => x.key === stepKey)
    if (!s) return []
    const out: string[] = []
    if (stepKey === 'basics') {
      if (!isCustomer && !form.customer_id) out.push('לקוח במערכת')
      if (!form.event_date) out.push('תאריך אירוע')
      if (req('end_client_name') && !form.end_client_name.trim()) out.push('שם לקוח האירוע')
      if (req('event_number') && !form.event_number.trim()) out.push('מספר אירוע')
    }
    if (stepKey === 'location') {
      if (req('location') && !form.location_text.trim()) out.push('מיקום')
      if (req('location_notes') && !form.location_notes.trim()) out.push('הערות למיקום')
      if (req('contact_name') && !form.contact_name.trim()) out.push('איש קשר')
      if (req('contact_phone') && !form.contact_phone.trim()) out.push('טלפון איש קשר')
    }
    if (stepKey === 'logistics') {
      if (req('volume_m') && !form.volume_m) out.push('נפח במטר')
      if (req('truck_count') && !form.truck_count) out.push('כמות משאיות')
      if (req('notes') && !form.notes.trim()) out.push('הערות')
    }
    if (stepKey === 'sections') {
      for (const { code, title } of SECTIONS) {
        if (!typeIdOf(code)) continue
        for (const [key, label] of SECTION_LABELS) {
          const k = `${code}_${key}` as keyof EventForm
          if (show(k) && req(k) && !String(form[k] ?? '').trim()) out.push(`${title} — ${label}`)
        }
      }
    }
    return out
  }

  const stepMissing = steps.map((s) => missingIn(s.key))
  const allMissing = stepMissing.flat()
  const isLast = step === steps.length - 1

  const save = useMutation({
    mutationFn: async () => {
      const payload: Record<string, unknown> = {
        customer_id: form.customer_id || undefined,
        end_client_name: form.end_client_name,
        event_number: form.event_number,
        event_date: form.event_date,
        location_text: form.location_text,
        location_provider: form.location_provider,
        location_place_id: form.location_place_id,
        location_lat: form.location_lat,
        location_lng: form.location_lng,
        location_notes: form.location_notes,
        volume_m: form.volume_m,
        truck_count: form.truck_count,
        notes: form.notes,
        status_id: form.status_id || undefined,
        no_parking: form.no_parking,
        porterage: form.porterage,
        supplier_pickup: form.supplier_pickup,
        supplier_ids: form.supplier_pickup ? form.supplier_ids : [],
      }
      payload.contact_name = form.contact_name
      payload.contact_phone = form.contact_phone

      // Drop anything this user may not see or change. The RPC does the same
      // for clients; this covers staff, whose per-customer config the server
      // does not apply to them, and stops a read-only field being sent back.
      for (const key of Object.keys(PAYLOAD_KEYS)) {
        if (show(key) && !ro(key)) continue
        for (const k of PAYLOAD_KEYS[key]) delete payload[k]
      }
      for (const key of ['end_client_name', 'event_number', 'location_notes', 'volume_m', 'truck_count', 'notes']) {
        if (!show(key) || ro(key)) delete payload[key]
      }
      // hidden sections are never sent, so the RPC leaves their tasks alone
      for (const { code } of SECTIONS) {
        if (!typeIdOf(code)) continue
        for (const key of sectionFields(code)) {
          if (!show(key) || ro(key)) continue
          // task_date is NOT NULL — omitting an empty date keeps the current one
          if (key.endsWith('_date') && !form[key]) continue
          payload[key] = form[key]
        }
      }
      if (event) {
        const { error } = await supabase.rpc('update_event', { p_event_id: event.id, payload })
        if (error) throw error
        return event.id
      }
      const { data, error } = await supabase.rpc('create_event', { payload })
      if (error) throw error
      return data as string
    },
    onSuccess: () => {
      toast.success(event ? 'האירוע עודכן' : 'האירוע נוצר', {
        description: event ? undefined : 'משימות הקמה ופירוק נוצרו אוטומטית',
      })
      localStorage.removeItem(DRAFT_KEY)
      void qc.invalidateQueries({ queryKey: ['events'] })
      void qc.invalidateQueries({ queryKey: ['tasks'] })
      void qc.invalidateQueries({ queryKey: ['calendar'] })
      void qc.invalidateQueries({ queryKey: ['workboard'] })
      void qc.invalidateQueries({ queryKey: ['dashboard'] })
      onClose()
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const submit = () => {
    setTouched(true)
    if (allMissing.length > 0) {
      const firstBad = stepMissing.findIndex((m) => m.length > 0)
      setStep(firstBad)
      toast.warning('חסרים שדות חובה', { description: allMissing.join(', ') })
      return
    }
    save.mutate()
  }

  const current = steps[step]
  const err = (key: string, value: string) => (touched && req(key) && !value.trim() ? 'שדה חובה' : undefined)

  return (
    <Modal
      open={open}
      onClose={onClose}
      wide
      title={event ? 'עריכת אירוע' : 'אירוע חדש'}
      description={event ? undefined : 'הטופס נשמר אוטומטית כטיוטה עד לשליחה'}
      footer={
        <>
          {step > 0 && (
            <Button onClick={() => setStep((s) => s - 1)}>הקודם</Button>
          )}
          <Button className="ms-auto" onClick={onClose}>
            ביטול
          </Button>
          {!isLast && (
            <Button
              variant="secondary"
              onClick={() => {
                setTouched(true)
                if (stepMissing[step].length > 0) {
                  toast.warning('חסרים שדות חובה בשלב זה', { description: stepMissing[step].join(', ') })
                  return
                }
                setStep((s) => s + 1)
              }}
            >
              הבא
            </Button>
          )}
          <Button variant="primary" loading={save.isPending} onClick={submit}>
            {event ? 'שמירה' : 'יצירת אירוע'}
          </Button>
        </>
      }
    >
      {/* ── stepper ────────────────────────────────────────────────────────
          Each step reports its own completeness so a required field two
          steps back is visible without hunting for it.                    */}
      {steps.length > 1 && (
        <ol className="mb-5 flex items-center gap-1">
          {steps.map((s, i) => {
            const Icon = s.icon
            const missing = stepMissing[i].length > 0
            const done = i < step && !missing
            const active = i === step
            return (
              <li key={s.key} className="flex min-w-0 flex-1 items-center gap-1">
                <button
                  type="button"
                  onClick={() => setStep(i)}
                  aria-current={active ? 'step' : undefined}
                  className={cx(
                    'flex min-w-0 flex-1 items-center gap-2 rounded-lg px-2.5 py-2 text-start transition-colors',
                    'focus-visible:outline-none focus-visible:focus-ring',
                    active ? 'bg-selected' : 'hover:bg-hover',
                  )}
                >
                  <span
                    className={cx(
                      'flex size-7 shrink-0 items-center justify-center rounded-full transition-colors',
                      done
                        ? 'bg-success text-white'
                        : touched && missing
                          ? 'bg-error text-white'
                          : active
                            ? 'bg-primary text-on-primary'
                            : 'bg-subtle text-ink-tertiary',
                    )}
                  >
                    {done ? <Check size={ICON.sm} strokeWidth={3} /> : <Icon size={ICON.sm} strokeWidth={STROKE} />}
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className={cx('block truncate type-caption font-semibold', active ? 'text-ink' : 'text-ink-tertiary')}>
                      {s.label}
                    </span>
                    {touched && missing && (
                      <span className="block truncate type-caption text-error-text">{stepMissing[i].length} שדות חסרים</span>
                    )}
                  </span>
                </button>
                {i < steps.length - 1 && <span className="h-px w-4 shrink-0 bg-line" aria-hidden />}
              </li>
            )
          })}
        </ol>
      )}

      {/* ── step 1: basics ─────────────────────────────────────────────── */}
      {current?.key === 'basics' && (
        <div className="grid animate-fade-in gap-4 sm:grid-cols-2">
          {!isCustomer && (
            <Field label="לקוח במערכת" required error={touched && !form.customer_id ? 'שדה חובה' : undefined}>
              <Select
                data-autofocus
                value={form.customer_id}
                onChange={(e) => set({ customer_id: e.target.value, supplier_ids: [] })}
                disabled={!!event}
              >
                <option value="">בחירת לקוח...</option>
                {customers.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </Select>
            </Field>
          )}
          {show('end_client_name') && (
            <Field
              label="שם לקוח האירוע"
              required={req('end_client_name')}
              error={err('end_client_name', form.end_client_name)}
            >
              <Input value={form.end_client_name} onChange={(e) => set({ end_client_name: e.target.value })} disabled={ro('end_client_name')} />
            </Field>
          )}
          {show('event_number') && (
            <Field label="מספר אירוע" required={req('event_number')} error={err('event_number', form.event_number)}>
              <Input value={form.event_number} onChange={(e) => set({ event_number: e.target.value })} disabled={ro('event_number')} />
            </Field>
          )}
          {show('event_date') && (
            <Field label="תאריך אירוע" required error={touched && !form.event_date ? 'שדה חובה' : undefined}>
              {/* section dates follow the event date until the user moves one of them */}
              <Input
                type="date"
                value={form.event_date}
                onChange={(e) =>
                  setForm((f) => {
                    const d = e.target.value
                    const carry = (v: string) => (!v || v === f.event_date ? d : v)
                    return {
                      ...f,
                      event_date: d,
                      setup_date: carry(f.setup_date),
                      teardown_date: carry(f.teardown_date),
                    }
                  })
                }
              />
            </Field>
          )}
          {!isCustomer && (
            <Field label="סטטוס">
              <Select value={form.status_id} onChange={(e) => set({ status_id: e.target.value })}>
                <option value="">ברירת מחדל</option>
                {statuses.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                  </option>
                ))}
              </Select>
            </Field>
          )}
        </div>
      )}

      {/* ── step 2: location & contact ─────────────────────────────────── */}
      {current?.key === 'location' && (
        <div className="animate-fade-in space-y-4">
          {show('location') && (
            <Field label="מיקום" required={req('location')} error={err('location', form.location_text)} hint="בחירה מהרשימה שומרת גם קואורדינטות">
              <AddressAutocomplete
                value={form.location_text}
                onChange={(text) => set({ location_text: text, location_place_id: '', location_provider: '' })}
                onPick={(s) =>
                  set({
                    location_text: s.label,
                    location_place_id: s.place_id,
                    location_provider: s.provider,
                    location_lat: s.lat,
                    location_lng: s.lng,
                  })
                }
              />
            </Field>
          )}
          {show('location_notes') && (
            <Field label="הערות למיקום" required={req('location_notes')} error={err('location_notes', form.location_notes)}>
              <Input
                value={form.location_notes}
                onChange={(e) => set({ location_notes: e.target.value })}
                disabled={ro('location_notes')}
                placeholder="למשל: כניסה מהחניון האחורי"
              />
            </Field>
          )}
          {(show('contact_name') || show('contact_phone')) && (
            <div className="grid gap-4 sm:grid-cols-2">
              {show('contact_name') && (
                <Field label="איש קשר" required={req('contact_name')} error={err('contact_name', form.contact_name)}>
                  <Input
                    leading={<User size={ICON.sm} strokeWidth={STROKE} />}
                    value={form.contact_name}
                    onChange={(e) => set({ contact_name: e.target.value })}
                    disabled={ro('contact_name')}
                  />
                </Field>
              )}
              {show('contact_phone') && (
                <Field label="טלפון איש קשר" required={req('contact_phone')} error={err('contact_phone', form.contact_phone)}>
                  <Input
                    dir="ltr"
                    leading={<Phone size={ICON.sm} strokeWidth={STROKE} />}
                    value={form.contact_phone}
                    onChange={(e) => set({ contact_phone: e.target.value })}
                    disabled={!has(PERM.EVENTS_MANAGE_CONTACTS)}
                  />
                </Field>
              )}
            </div>
          )}
        </div>
      )}

      {/* ── step 3: logistics & add-ons ────────────────────────────────── */}
      {current?.key === 'logistics' && (
        <div className="animate-fade-in space-y-4">
          <div className="grid gap-4 sm:grid-cols-2">
            {show('volume_m') && (
              <Field label="נפח במטר" required={req('volume_m')} error={err('volume_m', form.volume_m)}>
                <Input type="number" step="0.1" min="0" value={form.volume_m} onChange={(e) => set({ volume_m: e.target.value })} disabled={ro('volume_m')} />
              </Field>
            )}
            {show('truck_count') && (
              <Field label="כמות משאיות" required={req('truck_count')} error={err('truck_count', form.truck_count)}>
                <Input type="number" min="0" value={form.truck_count} onChange={(e) => set({ truck_count: e.target.value })} disabled={ro('truck_count')} />
              </Field>
            )}
          </div>

          {show('addons') && (
            <div className="space-y-3 rounded-lg border border-line-subtle bg-subtle/50 p-3">
              <p className="type-overline">תוספות</p>
              <div className="grid gap-2 sm:grid-cols-3">
                <Checkbox label="אין חניה" checked={form.no_parking} onChange={(v) => set({ no_parking: v })} disabled={ro('addons')} />
                <Checkbox label="סבלות" checked={form.porterage} onChange={(v) => set({ porterage: v })} disabled={ro('addons')} />
                <Checkbox label="איסוף מספקים" checked={form.supplier_pickup} onChange={(v) => set({ supplier_pickup: v })} disabled={ro('addons')} />
              </div>
              {form.supplier_pickup && (
                <Field label="ספקים לאיסוף">
                  <MultiSelect
                    options={suppliers.map((s) => ({ id: s.id, label: s.name }))}
                    values={form.supplier_ids}
                    onToggle={(id) =>
                      set({
                        supplier_ids: form.supplier_ids.includes(id)
                          ? form.supplier_ids.filter((x) => x !== id)
                          : [...form.supplier_ids, id],
                      })
                    }
                    placeholder={suppliers.length ? 'בחירת ספקים...' : 'אין ספקים מוגדרים ללקוח זה'}
                  />
                </Field>
              )}
            </div>
          )}

          {show('notes') && (
            <Field label="הערות" required={req('notes')} error={err('notes', form.notes)}>
              <Textarea autoGrow value={form.notes} onChange={(e) => set({ notes: e.target.value })} disabled={ro('notes')} />
            </Field>
          )}
        </div>
      )}

      {/* ── step 4: setup & teardown ───────────────────────────────────────
          These two write straight onto the tasks the event trigger creates,
          so they are editable here instead of only in the task drawer.    */}
      {current?.key === 'sections' && (
        <div className="animate-fade-in grid gap-4 lg:grid-cols-2">
          {SECTIONS.map(({ code, title }) =>
            typeIdOf(code) ? (
              <TaskSection
                key={code}
                code={code}
                title={title}
                form={form}
                set={set}
                show={show}
                req={req}
                err={err}
                ro={ro}
                methods={code === 'setup' ? setupMethods : teardownMethods}
                allMethods={allMethods}
              />
            ) : null,
          )}
        </div>
      )}
    </Modal>
  )
}

/** One הקמה/פירוק block — the five fields that land on the auto-created task. */
function TaskSection({
  code,
  title,
  form,
  set,
  show,
  req,
  err,
  ro,
  methods,
  allMethods,
}: {
  code: 'setup' | 'teardown'
  title: string
  form: EventForm
  set: (patch: Partial<EventForm>) => void
  show: (key: string) => boolean
  req: (key: string) => boolean
  err: (key: string, value: string) => string | undefined
  ro: (key: string) => boolean
  methods: ExecutionMethod[]
  allMethods: ExecutionMethod[]
}) {
  const dateKey = `${code}_date` as const
  const timeKey = `${code}_time` as const
  const workersKey = `${code}_worker_count` as const
  const hoursKey = `${code}_hours_count` as const
  const methodKey = `${code}_execution_method` as const

  if (!sectionFields(code).some(show)) return null

  /** A method disabled for the customer after the fact would otherwise vanish silently. */
  const picked = form[methodKey]
  const orphan = picked && !methods.some((m) => m.id === picked) ? allMethods.find((m) => m.id === picked) : null

  return (
    <Card>
      <CardHeader title={title} icon={<Clock size={ICON.md} strokeWidth={STROKE} />} />
      <CardBody className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2">
          {show(dateKey) && (
            <Field label="תאריך" required={req(dateKey)} error={err(dateKey, form[dateKey])}>
              <Input type="date" value={form[dateKey]} onChange={(e) => set({ [dateKey]: e.target.value })} disabled={ro(dateKey)} />
            </Field>
          )}
          {show(timeKey) && (
            <Field label="שעה" required={req(timeKey)} error={err(timeKey, form[timeKey])} hint="שעת תחילה בשטח">
              <Input type="time" value={form[timeKey]} onChange={(e) => set({ [timeKey]: e.target.value })} disabled={ro(timeKey)} />
            </Field>
          )}
          {show(workersKey) && (
            <Field label="כמות עובדים" required={req(workersKey)} error={err(workersKey, form[workersKey])}>
              <Input
                type="number"
                min="0"
                value={form[workersKey]}
                onChange={(e) => set({ [workersKey]: e.target.value })}
                disabled={ro(workersKey)}
              />
            </Field>
          )}
          {show(hoursKey) && (
            <Field label="כמות שעות" required={req(hoursKey)} error={err(hoursKey, form[hoursKey])}>
              <Input
                type="number"
                step="0.5"
                min="0"
                value={form[hoursKey]}
                onChange={(e) => set({ [hoursKey]: e.target.value })}
                disabled={ro(hoursKey)}
              />
            </Field>
          )}
        </div>
        {show(methodKey) && (
          <Field
            label="אופן ביצוע"
            required={req(methodKey)}
            error={err(methodKey, form[methodKey])}
            hint={methods.length ? undefined : 'לא הוגדרו אופני ביצוע זמינים ללקוח זה'}
          >
            <Select value={form[methodKey]} onChange={(e) => set({ [methodKey]: e.target.value })} disabled={ro(methodKey)}>
              <option value="">בחירה...</option>
              {methods.map((m) => (
                <option key={m.id} value={m.id}>
                  {m.name}
                </option>
              ))}
              {orphan && (
                <option value={orphan.id} disabled>
                  {orphan.name} (אינו זמין יותר)
                </option>
              )}
            </Select>
          </Field>
        )}
      </CardBody>
    </Card>
  )
}
