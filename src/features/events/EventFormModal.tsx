import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { Button, Checkbox, Field, Input, Modal, MultiSelect, Select, Textarea, useToast } from '../../components/ui'
import { useCustomerFormConfig, useCustomers, useStatuses, useSuppliers } from '../../lib/queries'
import { AddressAutocomplete } from './AddressAutocomplete'
import type { EventRow } from '../../types/domain'

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
}

const empty: EventForm = {
  customer_id: '', end_client_name: '', event_number: '', event_date: '', location_text: '',
  location_provider: '', location_place_id: '', location_lat: null, location_lng: null,
  location_notes: '', volume_m: '', truck_count: '', contact_name: '', contact_phone: '',
  notes: '', status_id: '', no_parking: false, porterage: false, supplier_pickup: false, supplier_ids: [],
}

const DRAFT_KEY = 'vl-event-draft'

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
  const { me, canViewField, canEditField } = useAuth()
  const isCustomer = me?.profile.user_kind === 'customer_user'
  const [form, setForm] = useState<EventForm>(empty)

  const { data: customers = [] } = useCustomers()
  const { data: statuses = [] } = useStatuses('event')
  const effectiveCustomerId = isCustomer ? me?.profile.customer_id : form.customer_id || null
  const { data: config = [] } = useCustomerFormConfig(effectiveCustomerId)
  const { data: suppliers = [] } = useSuppliers(effectiveCustomerId)

  useEffect(() => {
    if (!open) return
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
      })
    } else {
      const draft = localStorage.getItem(DRAFT_KEY)
      setForm(draft ? { ...empty, ...(JSON.parse(draft) as Partial<EventForm>) } : empty)
    }
  }, [open, event, contact, supplierIds])

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

  /** customers see their configured form; staff see everything but keep required markers */
  const show = (key: string) => {
    if (key === 'contact_phone' && !canViewField('event', 'contact_phone')) return false
    if (!isCustomer) return true
    return fieldState(key) !== 'hidden'
  }
  const req = (key: string) => fieldState(key) === 'required'

  const set = (patch: Partial<EventForm>) => setForm((f) => ({ ...f, ...patch }))

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
      if (canEditField('event', 'contact_phone')) {
        payload.contact_name = form.contact_name
        payload.contact_phone = form.contact_phone
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
      toast.success(event ? 'האירוע עודכן' : 'האירוע נוצר עם משימות הקמה ופירוק')
      localStorage.removeItem(DRAFT_KEY)
      void qc.invalidateQueries({ queryKey: ['events'] })
      void qc.invalidateQueries({ queryKey: ['calendar'] })
      void qc.invalidateQueries({ queryKey: ['workboard'] })
      onClose()
    },
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <Modal open={open} onClose={onClose} title={event ? 'עריכת אירוע' : 'אירוע חדש'} wide>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        {!isCustomer && (
          <Field label="לקוח במערכת" required>
            <Select value={form.customer_id} onChange={(e) => set({ customer_id: e.target.value, supplier_ids: [] })} disabled={!!event}>
              <option value="">בחירת לקוח...</option>
              {customers.map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </Select>
          </Field>
        )}
        {show('end_client_name') && (
          <Field label="שם לקוח האירוע" required={req('end_client_name')}>
            <Input value={form.end_client_name} onChange={(e) => set({ end_client_name: e.target.value })} />
          </Field>
        )}
        {show('event_number') && (
          <Field label="מספר אירוע" required={req('event_number')}>
            <Input value={form.event_number} onChange={(e) => set({ event_number: e.target.value })} />
          </Field>
        )}
        {show('event_date') && (
          <Field label="תאריך אירוע" required>
            <Input type="date" value={form.event_date} onChange={(e) => set({ event_date: e.target.value })} />
          </Field>
        )}
        {show('location') && (
          <Field label="מיקום" required={req('location')}>
            <AddressAutocomplete
              value={form.location_text}
              onChange={(text) => set({ location_text: text, location_place_id: '', location_provider: '' })}
              onPick={(s) => set({ location_text: s.label, location_place_id: s.place_id, location_provider: s.provider, location_lat: s.lat, location_lng: s.lng })}
            />
          </Field>
        )}
        {show('location_notes') && (
          <Field label="הערות למיקום" required={req('location_notes')}>
            <Input value={form.location_notes} onChange={(e) => set({ location_notes: e.target.value })} />
          </Field>
        )}
        {show('volume_m') && (
          <Field label="נפח במטר" required={req('volume_m')}>
            <Input type="number" step="0.1" min="0" value={form.volume_m} onChange={(e) => set({ volume_m: e.target.value })} />
          </Field>
        )}
        {show('truck_count') && (
          <Field label="כמות משאיות" required={req('truck_count')}>
            <Input type="number" min="0" value={form.truck_count} onChange={(e) => set({ truck_count: e.target.value })} />
          </Field>
        )}
        {show('contact_name') && (
          <Field label="איש קשר" required={req('contact_name')}>
            <Input value={form.contact_name} onChange={(e) => set({ contact_name: e.target.value })} disabled={!canEditField('event', 'contact_phone')} />
          </Field>
        )}
        {show('contact_phone') && (
          <Field label="טלפון איש קשר" required={req('contact_phone')}>
            <Input dir="ltr" value={form.contact_phone} onChange={(e) => set({ contact_phone: e.target.value })} disabled={!canEditField('event', 'contact_phone')} />
          </Field>
        )}
        {!isCustomer && (
          <Field label="סטטוס">
            <Select value={form.status_id} onChange={(e) => set({ status_id: e.target.value })}>
              <option value="">ברירת מחדל</option>
              {statuses.map((s) => (
                <option key={s.id} value={s.id}>{s.name}</option>
              ))}
            </Select>
          </Field>
        )}
      </div>

      {show('notes') && (
        <div className="mt-3">
          <Field label="הערות" required={req('notes')}>
            <Textarea value={form.notes} onChange={(e) => set({ notes: e.target.value })} />
          </Field>
        </div>
      )}

      {show('addons') && (
        <div className="mt-3 space-y-2 rounded-lg border border-[var(--border)] p-3">
          <h3 className="text-xs font-bold text-[var(--muted)]">תוספות</h3>
          <div className="flex flex-wrap gap-4">
            <Checkbox label="אין חניה" checked={form.no_parking} onChange={(v) => set({ no_parking: v })} />
            <Checkbox label="סבלות" checked={form.porterage} onChange={(v) => set({ porterage: v })} />
            <Checkbox label="איסוף מספקים" checked={form.supplier_pickup} onChange={(v) => set({ supplier_pickup: v })} />
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

      <div className="mt-4 flex justify-end gap-2">
        <Button onClick={onClose}>ביטול</Button>
        <Button variant="primary" loading={save.isPending} onClick={() => save.mutate()}>
          {event ? 'שמירה' : 'יצירת אירוע'}
        </Button>
      </div>
    </Modal>
  )
}
