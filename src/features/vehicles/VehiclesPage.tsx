import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import {
  AlertTriangle,
  CircleCheck,
  ICON,
  Plus,
  RefreshCw,
  STROKE,
  Timer,
  Truck,
} from '../../components/ui/icons'
import {
  Button,
  Card,
  CardBody,
  DataTable,
  EmptyState,
  Field,
  Input,
  Modal,
  PageHeader,
  SearchInput,
  Select,
  StatCard,
  StatusPill,
  Textarea,
  useToast,
} from '../../components/ui'
import type { Column } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { useTrucks, useVehicles } from '../../lib/queries'
import { errorMessage } from '../../lib/errors'
import { fmtDate } from '../../lib/dates'
import type { Vehicle, VehicleCategory, VehicleDocumentState, VehicleStatus } from '../../types/domain'
import { useFleetExpirySummary, useFleetExpiringDocuments, useFleetSweep } from './vehicleQueries'
import {
  DOC_STATE_COLORS,
  DOC_STATE_LABELS,
  VEHICLE_CATEGORY_LABELS,
  VEHICLE_STATUS_COLORS,
  VEHICLE_STATUS_LABELS,
  formatPlate,
  normalizePlate,
  vehicleModelLine,
  worstDocState,
} from './vehicles'

/**
 * ניהול רכבים (0088): הרכב כנכס, ולא כערך ב-dropdown של שיבוץ.
 *
 * המונים שמעל הטבלה נשאלים מ-`fleet_expiry_summary` ואינם נספרים כאן, כדי
 * שהמסך והדשבורד לעולם לא יסתרו זה את זה — אותה עמדה של מסך התקבולים.
 */
export default function VehiclesPage() {
  const { has } = useAuth()
  const navigate = useNavigate()
  const toast = useToast()
  const canCreate = has(PERM.FLEET_CREATE)
  const canSweep = has(PERM.FLEET_EDIT)
  const canSeeDocs = has(PERM.FLEET_DOCS_VIEW)

  const [q, setQ] = useState('')
  const [status, setStatus] = useState<'' | VehicleStatus>('')
  const [createOpen, setCreateOpen] = useState(false)

  const { data: vehicles = [], isLoading } = useVehicles()
  const { data: summary } = useFleetExpirySummary()
  const { data: expiring = [] } = useFleetExpiringDocuments(canSeeDocs)
  const sweep = useFleetSweep()

  /* המצב החמור ביותר פר-רכב, מתוך שאילתה אחת על כל הצי. */
  const stateOf = useMemo(() => {
    const byVehicle = new Map<string, VehicleDocumentState[]>()
    for (const d of expiring) {
      const list = byVehicle.get(d.vehicle_id) ?? []
      list.push(d.status)
      byVehicle.set(d.vehicle_id, list)
    }
    return new Map([...byVehicle].map(([id, states]) => [id, worstDocState(states)]))
  }, [expiring])

  const nearestOf = useMemo(() => {
    const m = new Map<string, { name: string; date: string | null }>()
    // המסמכים מגיעים ממוינים לפי תאריך פקיעה, ולכן הראשון לכל רכב הוא הקרוב.
    for (const d of expiring) if (!m.has(d.vehicle_id)) m.set(d.vehicle_id, { name: d.kind_name, date: d.expires_at })
    return m
  }, [expiring])

  const rows = useMemo(() => {
    const needle = q.trim().toLowerCase()
    const digits = normalizePlate(q)
    return vehicles.filter((v) => {
      if (status && v.status !== status) return false
      if (!needle) return true
      if (digits && normalizePlate(v.plate_number).includes(digits)) return true
      return [v.name, v.make, v.model, v.current_driver_name, v.vin]
        .filter(Boolean)
        .some((s) => s!.toLowerCase().includes(needle))
    })
  }, [vehicles, q, status])

  const columns: Column<Vehicle>[] = [
    {
      key: 'plate_number',
      header: 'מספר רישוי',
      sticky: true,
      render: (v) => (
        <span className="tabular" dir="ltr">
          {formatPlate(v.plate_number)}
        </span>
      ),
      sortValue: (v) => normalizePlate(v.plate_number),
    },
    {
      key: 'name',
      header: 'רכב',
      render: (v) => (
        <span className="min-w-0">
          <span className="block truncate">{v.name}</span>
          <span className="block truncate type-caption text-ink-tertiary">{vehicleModelLine(v)}</span>
        </span>
      ),
      sortValue: (v) => v.name,
    },
    {
      key: 'category',
      header: 'סוג',
      render: (v) => VEHICLE_CATEGORY_LABELS[v.category] ?? v.category,
      sortValue: (v) => VEHICLE_CATEGORY_LABELS[v.category] ?? v.category,
    },
    {
      key: 'driver',
      header: 'נהג קבוע',
      render: (v) => <span className="truncate">{v.current_driver_name ?? '—'}</span>,
      sortValue: (v) => v.current_driver_name ?? '',
    },
    {
      key: 'status',
      header: 'סטטוס',
      render: (v) => <StatusPill color={VEHICLE_STATUS_COLORS[v.status]}>{VEHICLE_STATUS_LABELS[v.status]}</StatusPill>,
      sortValue: (v) => VEHICLE_STATUS_LABELS[v.status],
    },
    ...(canSeeDocs
      ? [
          {
            key: 'docs',
            header: 'תוקף',
            render: (v: Vehicle) => {
              const state = stateOf.get(v.id)
              if (!state) return <span className="type-caption text-ink-tertiary">תקין</span>
              const near = nearestOf.get(v.id)
              return (
                <span className="flex min-w-0 items-center gap-2">
                  <StatusPill color={DOC_STATE_COLORS[state]}>{DOC_STATE_LABELS[state]}</StatusPill>
                  {near && (
                    <span className="truncate type-caption text-ink-tertiary">
                      {near.name}
                      {near.date ? ` · ${fmtDate(near.date)}` : ''}
                    </span>
                  )}
                </span>
              )
            },
            sortValue: (v: Vehicle) => nearestOf.get(v.id)?.date ?? '',
          },
        ]
      : []),
    {
      key: 'odometer',
      header: 'ק״מ',
      align: 'end' as const,
      render: (v) => (
        <span className="tabular" dir="ltr">
          {v.odometer_km == null ? '—' : v.odometer_km.toLocaleString('he-IL')}
        </span>
      ),
      sortValue: (v) => v.odometer_km ?? -1,
    },
  ]

  return (
    <RequirePermission perm={PERM.FLEET_VIEW}>
      <div className="space-y-4">
        <PageHeader title="ניהול רכבים" subtitle="הצי של החברה — מסמכים, תוקף, נהגים וכרטיסי דלק">
          {canSweep && (
            <Button
              loading={sweep.isPending}
              onClick={() =>
                sweep.mutate(undefined, {
                  onSuccess: (r) =>
                    toast.success(
                      r.documents === 0 ? 'אין מסמכים חדשים שפגים' : `נשלחו התראות על ${r.documents} מסמכים`,
                    ),
                  onError: (e) => toast.error(errorMessage(e)),
                })
              }
            >
              <RefreshCw size={ICON.sm} strokeWidth={STROKE} />
              בדיקת תוקף
            </Button>
          )}
          {canCreate && (
            <Button variant="primary" onClick={() => setCreateOpen(true)}>
              <Plus size={ICON.sm} strokeWidth={STROKE} />
              רכב חדש
            </Button>
          )}
        </PageHeader>

        {summary && (
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard
              icon={<Truck size={ICON.xl} strokeWidth={STROKE} />}
              label="רכבים בצי"
              value={String(summary.vehicles)}
              tone="#3563f0"
            />
            <StatCard
              icon={<CircleCheck size={ICON.xl} strokeWidth={STROKE} />}
              label="מסמכים בתוקף"
              value={String(summary.valid)}
              tone="#22c55e"
            />
            <StatCard
              icon={<Timer size={ICON.xl} strokeWidth={STROKE} />}
              label="פגים בקרוב"
              value={String(summary.expiring)}
              tone="#f59e0b"
            />
            <StatCard
              icon={<AlertTriangle size={ICON.xl} strokeWidth={STROKE} />}
              label="פגי תוקף"
              value={String(summary.expired)}
              hint={summary.missing_required > 0 ? `${summary.missing_required} מסמכי חובה חסרים` : undefined}
              tone="#ef4444"
            />
          </div>
        )}

        <Card className="flex flex-wrap items-center gap-3 p-3">
          <SearchInput
            className="min-w-52 flex-1"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="מספר רישוי, שם, דגם או נהג..."
          />
          <Select
            className="w-40"
            value={status}
            onChange={(e) => setStatus(e.target.value as '' | VehicleStatus)}
            aria-label="סינון לפי סטטוס"
          >
            <option value="">כל הסטטוסים</option>
            {(Object.keys(VEHICLE_STATUS_LABELS) as VehicleStatus[]).map((s) => (
              <option key={s} value={s}>
                {VEHICLE_STATUS_LABELS[s]}
              </option>
            ))}
          </Select>
        </Card>

        <Card>
          <CardBody padded={false}>
            <DataTable
              rows={rows}
              columns={columns}
              getRowId={(v) => v.id}
              loading={isLoading}
              storageKey="vehicles"
              onRowClick={(v) => navigate(`/vehicles/${v.id}`)}
              empty={
                <EmptyState
                  compact
                  art="box"
                  title={vehicles.length === 0 ? 'אין רכבים' : 'אין רכב שמתאים לסינון'}
                  description={
                    vehicles.length === 0 && canCreate
                      ? 'הוסף רכב כדי לנהל את המסמכים, התוקף והנהג הקבוע שלו'
                      : undefined
                  }
                />
              }
            />
          </CardBody>
        </Card>

        <CreateVehicleModal open={createOpen} onClose={() => setCreateOpen(false)} />
      </div>
    </RequirePermission>
  )
}

/* ===== רכב חדש ============================================================ */

/**
 * רק מה שנדרש כדי לפתוח כרטיס: רישוי, שם, סוג, וקישור אופציונלי למשאית
 * קיימת. כל השאר נערך בכרטיס עצמו — טופס יצירה שמבקש שלושים שדות הוא טופס
 * שממלאים חצי ממנו.
 */
function CreateVehicleModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const qc = useQueryClient()
  const toast = useToast()
  const navigate = useNavigate()
  const { data: trucks = [] } = useTrucks()
  const { data: vehicles = [] } = useVehicles()

  const BLANK = { plate_number: '', name: '', category: 'truck' as VehicleCategory, truck_id: '', notes: '' }
  const [form, setForm] = useState(BLANK)

  const [openedFor, setOpenedFor] = useState(false)
  if (open !== openedFor) {
    setOpenedFor(open)
    if (open) setForm(BLANK)
  }

  /* משאית שכבר מקושרת לרכב אחר אינה בבורר: העמודה ייחודית, וההודעה של
     Postgres על הפרת אינדקס אינה משהו שמסך צריך להציג. */
  const takenTrucks = useMemo(() => new Set(vehicles.map((v) => v.truck_id).filter(Boolean)), [vehicles])
  const freeTrucks = trucks.filter((t) => !takenTrucks.has(t.id))

  const valid = form.plate_number.trim() !== '' && form.name.trim() !== ''

  const save = useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase
        .from('vehicles')
        .insert({
          plate_number: form.plate_number.trim(),
          name: form.name.trim(),
          category: form.category,
          truck_id: form.truck_id || null,
          notes: form.notes.trim() || null,
        })
        .select('id')
        .single()
      if (error) throw error
      return data.id as string
    },
    onSuccess: (id) => {
      toast.success('הרכב נוסף', { description: 'אפשר להוסיף לו מסמכים ונהג בכרטיס' })
      void qc.invalidateQueries({ queryKey: ['vehicles'] })
      void qc.invalidateQueries({ queryKey: ['fleet'] })
      onClose()
      navigate(`/vehicles/${id}`)
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="רכב חדש"
      description="הפרטים המלאים, המסמכים והנהג נוספים בכרטיס הרכב"
      footer={
        <>
          <Button className="ms-auto" onClick={onClose}>
            ביטול
          </Button>
          <Button variant="primary" loading={save.isPending} disabled={!valid} onClick={() => save.mutate()}>
            הוספה
          </Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="מספר רישוי" required>
          <Input
            data-autofocus
            dir="ltr"
            value={form.plate_number}
            onChange={(e) => setForm((f) => ({ ...f, plate_number: e.target.value }))}
          />
        </Field>
        <Field label="שם הרכב" required hint="איך קוראים לו בדיבור">
          <Input value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} />
        </Field>
        <Field label="סוג">
          <Select
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
        <Field label="משאית לשיבוץ" hint="הקישור לרשימה שממנה משבצים משימות">
          <Select value={form.truck_id} onChange={(e) => setForm((f) => ({ ...f, truck_id: e.target.value }))}>
            <option value="">ללא קישור</option>
            {freeTrucks.map((t) => (
              <option key={t.id} value={t.id}>
                {t.name}
                {t.plate_number ? ` · ${t.plate_number}` : ''}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="הערות" className="sm:col-span-2">
          <Textarea autoGrow rows={2} value={form.notes} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
        </Field>
      </div>
    </Modal>
  )
}
