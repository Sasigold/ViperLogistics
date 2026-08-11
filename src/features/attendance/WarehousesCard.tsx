import { useEffect, useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { ICON, MapPin, Pencil, Plus, STROKE, Trash2 } from '../../components/ui/icons'
import {
  Button,
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  Field,
  IconButton,
  Input,
  Modal,
  Skeleton,
  Switch,
  useConfirm,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useWarehouses } from './attendanceQueries'
import { LocationPicker } from './LocationPicker'
import type { Warehouse } from '../../types/domain'
import { errorMessage } from '../../lib/errors'

const BLANK = { name: '', address: '', lat: null as number | null, lng: null as number | null, radius_m: '' }

/**
 * המחסנים שמהם יוצאים למשימות.
 *
 * משמרת שמתחילה במחסן נמדדת מול המחסן שהמשימה נוקבת בו, ואם היא לא נקבה
 * באחד — מול הקרוב ביותר לעובד. לכן מחסן בלי קואורדינטות אינו שגיאה אלא
 * ויתור מודע על אימות המיקום עבורו, וזה מסומן ברשימה.
 */
export function WarehousesCard() {
  const qc = useQueryClient()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const { data: warehouses = [], isLoading } = useWarehouses()
  const [form, setForm] = useState(BLANK)
  const [editing, setEditing] = useState<Warehouse | null>(null)

  const invalidate = () => void qc.invalidateQueries({ queryKey: ['warehouses'] })
  const num = (v: string) => (v === '' ? null : Number(v))

  const add = useMutation({
    mutationFn: async () => {
      if (!form.name.trim()) throw new Error('חובה להזין שם מחסן')
      const { error } = await supabase.from('warehouses').insert({
        name: form.name.trim(),
        address: form.address || null,
        lat: form.lat,
        lng: form.lng,
        radius_m: num(form.radius_m),
        sort_order: warehouses.length,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('המחסן נוסף')
      setForm(BLANK)
      invalidate()
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const patch = useMutation({
    mutationFn: async ({ id, ...rest }: Partial<Warehouse> & { id: string }) => {
      const { error } = await supabase.from('warehouses').update(rest).eq('id', id)
      if (error) throw error
    },
    onSuccess: invalidate,
    onError: (e) => toast.error(errorMessage(e)),
  })

  const remove = async (w: Warehouse) => {
    if (!(await confirm(`למחוק את ${w.name}?`, { title: 'מחיקת מחסן', confirmLabel: 'מחיקה' }))) return
    const { error } = await supabase
      .from('warehouses')
      .update({ deleted_at: new Date().toISOString() })
      .eq('id', w.id)
    if (error) toast.error(errorMessage(error))
    else {
      toast.success('המחסן נמחק')
      invalidate()
    }
  }

  return (
    <Card>
      {dialog}
      <CardHeader
        title="מחסנים"
        subtitle="נקודות היציאה שמולן נמדדת החתמה של מי שמתחיל במחסן"
        icon={<MapPin size={ICON.md} strokeWidth={STROKE} />}
      />
      <div className="space-y-3 border-b border-line-subtle bg-subtle/40 p-4">
        <div className="grid gap-2 sm:grid-cols-2">
          <Field label="שם">
            <Input
              inputSize="sm"
              value={form.name}
              onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))}
            />
          </Field>
          <Field label="רדיוס מותר (מ׳)" hint="ריק = לפי ההגדרה הכללית">
            <Input
              inputSize="sm"
              dir="ltr"
              type="number"
              min={1}
              step={50}
              placeholder="כללי"
              value={form.radius_m}
              onChange={(e) => setForm((f) => ({ ...f, radius_m: e.target.value }))}
            />
          </Field>
        </div>

        {/* חיפוש כתובת ממלא את הקואורדינטות אוטומטית; אפשר גם ללחוץ על
            המפה או לגרור את הסמן — כל דרך מעדכנת את אותם lat/lng. */}
        <LocationPicker
          lat={form.lat}
          lng={form.lng}
          onChange={(lat, lng) => setForm((f) => ({ ...f, lat, lng }))}
          addressText={form.address}
          onAddressTextChange={(address) => setForm((f) => ({ ...f, address }))}
        />

        <div className="flex justify-end">
          <Button
            size="sm"
            variant="primary"
            loading={add.isPending}
            disabled={!form.name.trim()}
            onClick={() => add.mutate()}
          >
            <Plus size={ICON.sm} strokeWidth={STROKE} />
            הוספת מחסן
          </Button>
        </div>
      </div>
      <CardBody padded={false}>
        {isLoading ? (
          <div className="p-4">
            <Skeleton className="h-24 w-full" />
          </div>
        ) : warehouses.length === 0 ? (
          <EmptyState
            compact
            art="box"
            title="אין מחסנים מוגדרים"
            description="בלי מחסן, החתמה של מי שמתחיל במחסן תתקבל ותסומן כלא מאומתת"
          />
        ) : (
          <ul>
            {warehouses.map((w) => (
              <li
                key={w.id}
                className="flex flex-wrap items-center gap-3 border-b border-line-subtle px-4 py-2.5 last:border-0"
              >
                <div className="min-w-40 flex-1">
                  <p className="truncate type-body font-medium">{w.name}</p>
                  <p className="truncate type-caption text-ink-tertiary">
                    {w.lat != null && w.lng != null ? (
                      <span dir="ltr">
                        {w.lat.toFixed(4)}, {w.lng.toFixed(4)}
                        {w.radius_m ? ` · ${w.radius_m} מ׳` : ''}
                      </span>
                    ) : (
                      <span className="text-warning-text">ללא קואורדינטות — לא ניתן לאמת מיקום</span>
                    )}
                  </p>
                  {w.address && <p className="truncate type-caption text-ink-tertiary">{w.address}</p>}
                </div>
                <Switch
                  checked={w.is_active}
                  onChange={(v) => patch.mutate({ id: w.id, is_active: v })}
                  label="פעיל"
                />
                <IconButton label={`עריכת ${w.name}`} size="sm" onClick={() => setEditing(w)}>
                  <Pencil size={ICON.sm} strokeWidth={STROKE} />
                </IconButton>
                <IconButton label={`מחיקת ${w.name}`} size="sm" onClick={() => void remove(w)} className="hover:text-error">
                  <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                </IconButton>
              </li>
            ))}
          </ul>
        )}
      </CardBody>

      {editing && (
        <EditWarehouseModal
          warehouse={editing}
          onClose={() => setEditing(null)}
          onSave={(patchValue) =>
            patch.mutate(
              { id: editing.id, ...patchValue },
              { onSuccess: () => setEditing(null) },
            )
          }
          saving={patch.isPending}
        />
      )}
    </Card>
  )
}

function EditWarehouseModal({
  warehouse,
  onClose,
  onSave,
  saving,
}: {
  warehouse: Warehouse
  onClose: () => void
  onSave: (patch: Partial<Warehouse>) => void
  saving: boolean
}) {
  const [form, setForm] = useState({
    name: warehouse.name,
    address: warehouse.address ?? '',
    lat: warehouse.lat,
    lng: warehouse.lng,
    radius_m: warehouse.radius_m != null ? String(warehouse.radius_m) : '',
  })
  useEffect(() => {
    setForm({
      name: warehouse.name,
      address: warehouse.address ?? '',
      lat: warehouse.lat,
      lng: warehouse.lng,
      radius_m: warehouse.radius_m != null ? String(warehouse.radius_m) : '',
    })
  }, [warehouse])

  return (
    <Modal
      open
      onClose={onClose}
      size="md"
      title={`עריכת ${warehouse.name}`}
      footer={
        <>
          <Button onClick={onClose}>ביטול</Button>
          <Button
            variant="primary"
            loading={saving}
            disabled={!form.name.trim()}
            onClick={() =>
              onSave({
                name: form.name.trim(),
                address: form.address || null,
                lat: form.lat,
                lng: form.lng,
                radius_m: form.radius_m === '' ? null : Number(form.radius_m),
              })
            }
          >
            שמירה
          </Button>
        </>
      }
    >
      <div className="space-y-3">
        <div className="grid gap-2 sm:grid-cols-2">
          <Field label="שם">
            <Input value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} />
          </Field>
          <Field label="רדיוס מותר (מ׳)" hint="ריק = לפי ההגדרה הכללית">
            <Input
              dir="ltr"
              type="number"
              min={1}
              step={50}
              placeholder="כללי"
              value={form.radius_m}
              onChange={(e) => setForm((f) => ({ ...f, radius_m: e.target.value }))}
            />
          </Field>
        </div>
        <LocationPicker
          lat={form.lat}
          lng={form.lng}
          onChange={(lat, lng) => setForm((f) => ({ ...f, lat, lng }))}
          addressText={form.address}
          onAddressTextChange={(address) => setForm((f) => ({ ...f, address }))}
        />
      </div>
    </Modal>
  )
}
