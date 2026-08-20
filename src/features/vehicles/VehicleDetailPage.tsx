import { useEffect, useMemo, useState } from 'react'
import { useNavigate, useParams, useSearchParams } from 'react-router'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import {
  FileText,
  Fuel,
  ICON,
  STROKE,
  Shield,
  Trash2,
  Truck,
  User,
} from '../../components/ui/icons'
import {
  Button,
  Card,
  CardBody,
  CardHeader,
  ErrorState,
  Field,
  Input,
  PageHeader,
  Select,
  Skeleton,
  StatusPill,
  StickySaveBar,
  Tabs,
  Textarea,
  useConfirm,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { usePageTitle } from '../../app/breadcrumbs'
import { useTrucks, useVehicles } from '../../lib/queries'
import { errorMessage } from '../../lib/errors'
import type { Vehicle, VehicleCategory, VehicleFuelType, VehicleGearbox, VehicleOwnership, VehicleStatus } from '../../types/domain'
import { useCreateTruckForVehicle, useLinkTruck, useVehicle } from './vehicleQueries'
import { VehicleDocumentsTab } from './VehicleDocumentsTab'
import { VehicleDriversTab } from './VehicleDriversTab'
import { VehicleFuelCardTab } from './VehicleFuelCardTab'
import {
  LICENSE_CLASSES,
  VEHICLE_CATEGORY_LABELS,
  VEHICLE_FUEL_LABELS,
  VEHICLE_GEARBOX_LABELS,
  VEHICLE_OWNERSHIP_LABELS,
  VEHICLE_STATUS_COLORS,
  VEHICLE_STATUS_LABELS,
  formatPlate,
  vehicleModelLine,
} from './vehicles'

const TABS = [
  { key: 'details', label: 'פרטים', icon: <Truck size={ICON.sm} />, perm: PERM.FLEET_VIEW },
  { key: 'documents', label: 'מסמכים', icon: <FileText size={ICON.sm} />, perm: PERM.FLEET_DOCS_VIEW },
  { key: 'drivers', label: 'נהגים', icon: <User size={ICON.sm} />, perm: PERM.FLEET_VIEW },
  { key: 'fuel', label: 'כרטיס דלק', icon: <Fuel size={ICON.sm} />, perm: PERM.FLEET_VIEW_FUEL_CARD },
] as const

type TabKey = (typeof TABS)[number]['key']

export default function VehicleDetailPage() {
  const { id } = useParams<{ id: string }>()
  const { has } = useAuth()
  const visibleTabs = TABS.filter((t) => has(t.perm))

  /* הלשונית יושבת ב-query string ולא רק ב-state: הקישור שבפעמון מצביע על
     /vehicles/:id, וההתראה היא על מסמך — כך אפשר לשלוח ישר לטאב הנכון. */
  const [params, setParams] = useSearchParams()
  const requested = params.get('tab') as TabKey | null
  const tab: TabKey = visibleTabs.some((t) => t.key === requested) ? requested! : (visibleTabs[0]?.key ?? 'details')
  const setTab = (next: TabKey) => setParams((p) => {
    const q = new URLSearchParams(p)
    q.set('tab', next)
    return q
  }, { replace: true })

  const { data: vehicle, isLoading, error, refetch } = useVehicle(id)
  usePageTitle(vehicle ? `${vehicle.name} · ${formatPlate(vehicle.plate_number)}` : null)

  if (isLoading || !vehicle) {
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
    <RequirePermission perm={PERM.FLEET_VIEW}>
      <div className="space-y-4">
        <PageHeader
          title={
            <span className="flex flex-wrap items-center gap-2.5">
              <span
                className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-subtle text-ink-secondary"
                aria-hidden
              >
                <Truck size={ICON.lg} strokeWidth={STROKE} />
              </span>
              {vehicle.name}
              <StatusPill color={VEHICLE_STATUS_COLORS[vehicle.status]}>
                {VEHICLE_STATUS_LABELS[vehicle.status]}
              </StatusPill>
            </span>
          }
          subtitle={
            <span className="flex flex-wrap items-center gap-x-2 gap-y-1">
              <span className="tabular" dir="ltr">
                {formatPlate(vehicle.plate_number)}
              </span>
              {vehicleModelLine(vehicle) && <span>· {vehicleModelLine(vehicle)}</span>}
              {vehicle.current_driver_name && <span>· נהג קבוע: {vehicle.current_driver_name}</span>}
            </span>
          }
        >
          {visibleTabs.length > 1 && <Tabs items={visibleTabs} value={tab} onChange={setTab} />}
        </PageHeader>

        {tab === 'details' && <DetailsTab vehicle={vehicle} />}
        {tab === 'documents' && <VehicleDocumentsTab vehicle={vehicle} />}
        {tab === 'drivers' && <VehicleDriversTab vehicle={vehicle} />}
        {tab === 'fuel' && <VehicleFuelCardTab vehicle={vehicle} />}
      </div>
    </RequirePermission>
  )
}

/* ===== פרטים ============================================================== */

/** מה שנשמר מהטופס. `current_driver_id` אינו כאן — הוא נגזר (0088 §5). */
const EDITABLE = [
  'plate_number', 'name', 'category', 'status', 'make', 'model', 'model_year', 'vin', 'engine_number',
  'color', 'license_class', 'fuel_type', 'gearbox', 'seats', 'gross_weight_kg', 'payload_kg',
  'ownership', 'leasing_company', 'leasing_monthly_cost', 'leasing_end_date',
  'purchase_date', 'purchase_price', 'odometer_km', 'odometer_read_at', 'notes',
] as const

function DetailsTab({ vehicle }: { vehicle: Vehicle }) {
  const qc = useQueryClient()
  const toast = useToast()
  const navigate = useNavigate()
  const { has } = useAuth()
  const { confirm, dialog } = useConfirm()
  const canEdit = has(PERM.FLEET_EDIT)

  const [form, setForm] = useState(vehicle)
  useEffect(() => setForm(vehicle), [vehicle])

  const dirty = useMemo(() => EDITABLE.some((k) => form[k] !== vehicle[k]), [form, vehicle])

  const save = useMutation({
    mutationFn: async () => {
      if (!form.plate_number.trim()) throw new Error('חובה להזין מספר רישוי')
      if (!form.name.trim()) throw new Error('חובה להזין שם רכב')
      const row = Object.fromEntries(EDITABLE.map((k) => [k, form[k]]))
      const { error } = await supabase.from('vehicles').update(row).eq('id', vehicle.id)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('הרכב עודכן')
      void qc.invalidateQueries({ queryKey: ['vehicles'] })
      void qc.invalidateQueries({ queryKey: ['trucks'] })
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const remove = async () => {
    if (
      !(await confirm('למחוק את הרכב? המסמכים וההיסטוריה שלו יוסתרו איתו.', {
        title: 'מחיקת רכב',
        confirmLabel: 'מחיקה',
      }))
    )
      return
    const { error } = await supabase.rpc('soft_delete', { p_table: 'vehicles', p_id: vehicle.id })
    if (error) return toast.error(errorMessage(error))
    toast.success('הרכב נמחק')
    void qc.invalidateQueries({ queryKey: ['vehicles'] })
    navigate('/vehicles')
  }

  /** טקסט → מספר או null. שדה מספרי ריק אינו אפס. */
  const num = (v: string) => (v.trim() === '' ? null : Number(v))
  const str = (v: string) => (v.trim() === '' ? null : v)

  return (
    <div className="max-w-4xl space-y-4">
      {dialog}

      <Card>
        <CardHeader title="זיהוי" icon={<Truck size={ICON.md} strokeWidth={STROKE} />} />
        <CardBody className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <Field label="מספר רישוי" required>
            <Input
              dir="ltr"
              disabled={!canEdit}
              value={form.plate_number}
              onChange={(e) => setForm((f) => ({ ...f, plate_number: e.target.value }))}
            />
          </Field>
          <Field label="שם הרכב" required>
            <Input disabled={!canEdit} value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} />
          </Field>
          <Field label="סוג">
            <Select
              disabled={!canEdit}
              value={form.category}
              onChange={(e) => setForm((f) => ({ ...f, category: e.target.value as VehicleCategory }))}
            >
              {(Object.keys(VEHICLE_CATEGORY_LABELS) as VehicleCategory[]).map((c) => (
                <option key={c} value={c}>
                  {VEHICLE_CATEGORY_LABELS[c]}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="יצרן">
            <Input disabled={!canEdit} value={form.make ?? ''} onChange={(e) => setForm((f) => ({ ...f, make: str(e.target.value) }))} />
          </Field>
          <Field label="דגם">
            <Input disabled={!canEdit} value={form.model ?? ''} onChange={(e) => setForm((f) => ({ ...f, model: str(e.target.value) }))} />
          </Field>
          <Field label="שנת ייצור">
            <Input
              type="number"
              dir="ltr"
              disabled={!canEdit}
              value={form.model_year ?? ''}
              onChange={(e) => setForm((f) => ({ ...f, model_year: num(e.target.value) }))}
            />
          </Field>
          <Field label="מספר שלדה (VIN)">
            <Input dir="ltr" disabled={!canEdit} value={form.vin ?? ''} onChange={(e) => setForm((f) => ({ ...f, vin: str(e.target.value) }))} />
          </Field>
          <Field label="מספר מנוע">
            <Input
              dir="ltr"
              disabled={!canEdit}
              value={form.engine_number ?? ''}
              onChange={(e) => setForm((f) => ({ ...f, engine_number: str(e.target.value) }))}
            />
          </Field>
          <Field label="צבע">
            <Input disabled={!canEdit} value={form.color ?? ''} onChange={(e) => setForm((f) => ({ ...f, color: str(e.target.value) }))} />
          </Field>
        </CardBody>
      </Card>

      <Card>
        <CardHeader title="מפרט טכני" subtitle="מה שקובע מי רשאי לנהוג בו ומה מותר להעמיס" />
        <CardBody className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <Field label="דרגת רישיון נדרשת">
            <Select
              disabled={!canEdit}
              value={form.license_class ?? ''}
              onChange={(e) => setForm((f) => ({ ...f, license_class: str(e.target.value) }))}
            >
              <option value="">—</option>
              {LICENSE_CLASSES.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="סוג דלק">
            <Select
              disabled={!canEdit}
              value={form.fuel_type ?? ''}
              onChange={(e) => setForm((f) => ({ ...f, fuel_type: (e.target.value || null) as VehicleFuelType | null }))}
            >
              <option value="">—</option>
              {(Object.keys(VEHICLE_FUEL_LABELS) as VehicleFuelType[]).map((k) => (
                <option key={k} value={k}>
                  {VEHICLE_FUEL_LABELS[k]}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="תיבת הילוכים">
            <Select
              disabled={!canEdit}
              value={form.gearbox ?? ''}
              onChange={(e) => setForm((f) => ({ ...f, gearbox: (e.target.value || null) as VehicleGearbox | null }))}
            >
              <option value="">—</option>
              {(Object.keys(VEHICLE_GEARBOX_LABELS) as VehicleGearbox[]).map((k) => (
                <option key={k} value={k}>
                  {VEHICLE_GEARBOX_LABELS[k]}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="מספר מושבים">
            <Input
              type="number"
              dir="ltr"
              disabled={!canEdit}
              value={form.seats ?? ''}
              onChange={(e) => setForm((f) => ({ ...f, seats: num(e.target.value) }))}
            />
          </Field>
          <Field label="משקל כולל מותר (ק״ג)">
            <Input
              type="number"
              dir="ltr"
              disabled={!canEdit}
              value={form.gross_weight_kg ?? ''}
              onChange={(e) => setForm((f) => ({ ...f, gross_weight_kg: num(e.target.value) }))}
            />
          </Field>
          <Field label="כושר העמסה (ק״ג)">
            <Input
              type="number"
              dir="ltr"
              disabled={!canEdit}
              value={form.payload_kg ?? ''}
              onChange={(e) => setForm((f) => ({ ...f, payload_kg: num(e.target.value) }))}
            />
          </Field>
        </CardBody>
      </Card>

      <Card>
        <CardHeader title="בעלות ועלות" />
        <CardBody className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <Field label="סוג בעלות">
            <Select
              disabled={!canEdit}
              value={form.ownership}
              onChange={(e) => setForm((f) => ({ ...f, ownership: e.target.value as VehicleOwnership }))}
            >
              {(Object.keys(VEHICLE_OWNERSHIP_LABELS) as VehicleOwnership[]).map((k) => (
                <option key={k} value={k}>
                  {VEHICLE_OWNERSHIP_LABELS[k]}
                </option>
              ))}
            </Select>
          </Field>
          {form.ownership !== 'owned' && (
            <>
              <Field label="חברת הליסינג / ההשכרה">
                <Input
                  disabled={!canEdit}
                  value={form.leasing_company ?? ''}
                  onChange={(e) => setForm((f) => ({ ...f, leasing_company: str(e.target.value) }))}
                />
              </Field>
              <Field label="עלות חודשית (₪)">
                <Input
                  type="number"
                  step="any"
                  dir="ltr"
                  disabled={!canEdit}
                  value={form.leasing_monthly_cost ?? ''}
                  onChange={(e) => setForm((f) => ({ ...f, leasing_monthly_cost: num(e.target.value) }))}
                />
              </Field>
              <Field label="סוף החוזה">
                <Input
                  type="date"
                  disabled={!canEdit}
                  value={form.leasing_end_date ?? ''}
                  onChange={(e) => setForm((f) => ({ ...f, leasing_end_date: str(e.target.value) }))}
                />
              </Field>
            </>
          )}
          <Field label="תאריך רכישה">
            <Input
              type="date"
              disabled={!canEdit}
              value={form.purchase_date ?? ''}
              onChange={(e) => setForm((f) => ({ ...f, purchase_date: str(e.target.value) }))}
            />
          </Field>
          <Field label="מחיר רכישה (₪)">
            <Input
              type="number"
              step="any"
              dir="ltr"
              disabled={!canEdit}
              value={form.purchase_price ?? ''}
              onChange={(e) => setForm((f) => ({ ...f, purchase_price: num(e.target.value) }))}
            />
          </Field>
        </CardBody>
      </Card>

      <Card>
        <CardHeader title="מצב ותפעול" />
        <CardBody className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <Field label="סטטוס">
            <Select
              disabled={!canEdit}
              value={form.status}
              onChange={(e) => setForm((f) => ({ ...f, status: e.target.value as VehicleStatus }))}
            >
              {(Object.keys(VEHICLE_STATUS_LABELS) as VehicleStatus[]).map((k) => (
                <option key={k} value={k}>
                  {VEHICLE_STATUS_LABELS[k]}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="מד קילומטרים" hint="הקריאה האחרונה">
            <Input
              type="number"
              dir="ltr"
              disabled={!canEdit}
              value={form.odometer_km ?? ''}
              onChange={(e) => setForm((f) => ({ ...f, odometer_km: num(e.target.value) }))}
            />
          </Field>
          <Field label="תאריך הקריאה">
            <Input
              type="date"
              disabled={!canEdit}
              value={form.odometer_read_at ?? ''}
              onChange={(e) => setForm((f) => ({ ...f, odometer_read_at: str(e.target.value) }))}
            />
          </Field>
          <Field label="הערות" className="sm:col-span-2 lg:col-span-3">
            <Textarea
              autoGrow
              rows={2}
              disabled={!canEdit}
              value={form.notes ?? ''}
              onChange={(e) => setForm((f) => ({ ...f, notes: str(e.target.value) }))}
            />
          </Field>
        </CardBody>
        {canEdit && (
          <StickySaveBar dirty={dirty} saving={save.isPending} onSave={() => save.mutate()} onReset={() => setForm(vehicle)} />
        )}
      </Card>

      <TruckLinkCard vehicle={vehicle} canEdit={canEdit} />

      {has(PERM.FLEET_DELETE) && (
        <Card>
          <CardHeader
            title="אזור מסוכן"
            subtitle="מחיקה רכה — ניתן לשחזר מסל המיחזור בהגדרות"
            icon={<Shield size={ICON.md} strokeWidth={STROKE} />}
          />
          <CardBody>
            <Button variant="danger" size="sm" onClick={() => void remove()}>
              <Trash2 size={ICON.sm} strokeWidth={STROKE} />
              מחיקת הרכב
            </Button>
          </CardBody>
        </Card>
      )}
    </div>
  )
}

/* ===== הקישור לשיגור ====================================================== */

/**
 * הרכב הוא הנכס; המשאית היא השורה שמשבצים ממנה משימות. הקישור אופציונלי,
 * והרכב הוא מקור האמת — טריגר במסד דוחף ממנו את מספר הרישוי והשם אל המשאית
 * המקושרת (0088 §3), ולכן אין כאן שני ערכים שאפשר להעמיד בסתירה.
 */
function TruckLinkCard({ vehicle, canEdit }: { vehicle: Vehicle; canEdit: boolean }) {
  const toast = useToast()
  const { data: trucks = [] } = useTrucks()
  const { data: vehicles = [] } = useVehicles()
  const link = useLinkTruck(vehicle.id)
  const create = useCreateTruckForVehicle(vehicle.id)

  const truck = trucks.find((t) => t.id === vehicle.truck_id)
  const taken = useMemo(
    () => new Set(vehicles.filter((v) => v.id !== vehicle.id).map((v) => v.truck_id).filter(Boolean)),
    [vehicles, vehicle.id],
  )
  const options = trucks.filter((t) => !taken.has(t.id))

  const onLink = (truckId: string | null) =>
    link.mutate(truckId, {
      onSuccess: () => toast.success(truckId ? 'הרכב קושר למשאית' : 'הקישור הוסר'),
      onError: (e) => toast.error(errorMessage(e)),
    })

  const onCreate = () =>
    create.mutate(undefined, {
      onSuccess: () => toast.success('נוצרה משאית מהרכב'),
      onError: (e) => toast.error(errorMessage(e)),
    })

  return (
    <Card>
      <CardHeader
        title="שיבוץ למשימות"
        subtitle={
          truck
            ? `מקושר למשאית "${truck.name}" — מספר הרישוי שלה מתעדכן מהרכב`
            : 'הרכב אינו ברשימת השיבוץ, ולכן אי אפשר לשבץ אותו למשימה'
        }
        icon={<Truck size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody className="flex flex-wrap items-end gap-3">
        <Field label="משאית מקושרת" className="min-w-52 flex-1">
          <Select
            disabled={!canEdit || link.isPending}
            value={vehicle.truck_id ?? ''}
            onChange={(e) => onLink(e.target.value || null)}
          >
            <option value="">ללא קישור</option>
            {options.map((t) => (
              <option key={t.id} value={t.id}>
                {t.name}
                {t.plate_number ? ` · ${t.plate_number}` : ''}
              </option>
            ))}
          </Select>
        </Field>
        {canEdit && !vehicle.truck_id && (
          <Button loading={create.isPending} onClick={onCreate}>
            <Truck size={ICON.sm} strokeWidth={STROKE} />
            יצירת משאית מהרכב
          </Button>
        )}
      </CardBody>
    </Card>
  )
}
