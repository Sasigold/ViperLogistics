import { useMemo, useState } from 'react'
import { format } from 'date-fns'
import { ICON, STROKE, User, UserCheck, UserPlus } from '../../components/ui/icons'
import {
  Button,
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  Field,
  Input,
  Modal,
  Select,
  Skeleton,
  StatusPill,
  Textarea,
  useConfirm,
  useToast,
} from '../../components/ui'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { useStaff } from '../../lib/queries'
import { errorMessage } from '../../lib/errors'
import { fmtDate } from '../../lib/dates'
import type { Vehicle } from '../../types/domain'
import { useAssignDriver, useEndDriver, useVehicleDrivers } from './vehicleQueries'

/**
 * הנהג של הרכב — הצמדה פעילה אחת, ומאחוריה היסטוריה.
 *
 * ההיסטוריה אינה קישוט: כשמגיע דוח תנועה או נזק, השאלה היא מי נהג ברכב
 * בתאריך ההוא. עמודה אחת על הרכב הייתה מוחקת את התשובה בכל החלפה.
 */
export function VehicleDriversTab({ vehicle }: { vehicle: Vehicle }) {
  const { has } = useAuth()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const canManage = has(PERM.FLEET_DRIVERS_MANAGE)

  const { data: rows = [], isLoading } = useVehicleDrivers(vehicle.id)
  const end = useEndDriver(vehicle.id)
  const [assignOpen, setAssignOpen] = useState(false)

  const current = rows.find((r) => r.to_date === null)
  const history = rows.filter((r) => r.to_date !== null)

  return (
    <div className="max-w-3xl space-y-4">
      {dialog}

      <Card>
        <CardHeader
          title="הנהג הקבוע"
          icon={<UserCheck size={ICON.md} strokeWidth={STROKE} />}
          actions={
            canManage && (
              <Button variant="primary" size="sm" onClick={() => setAssignOpen(true)}>
                <UserPlus size={ICON.sm} strokeWidth={STROKE} />
                {current ? 'החלפת נהג' : 'הצמדת נהג'}
              </Button>
            )
          }
        />
        <CardBody>
          {isLoading ? (
            <Skeleton className="h-12 w-full" />
          ) : !current ? (
            <p className="type-body text-ink-tertiary">
              לרכב אין נהג קבוע. התראות על פקיעת מסמך יישלחו למנהלי הצי בלבד.
            </p>
          ) : (
            <div className="flex flex-wrap items-center gap-3">
              <span className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-subtle text-ink-secondary" aria-hidden>
                <User size={ICON.lg} strokeWidth={STROKE} />
              </span>
              <div className="min-w-0 flex-1">
                <p className="truncate type-body font-medium">{current.driver_name ?? '—'}</p>
                <p className="truncate type-caption text-ink-tertiary">
                  מוצמד מ-{fmtDate(current.from_date)}
                  {current.note ? ` · ${current.note}` : ''}
                </p>
              </div>
              <StatusPill color="#22c55e">פעיל</StatusPill>
              {canManage && (
                <Button
                  size="sm"
                  loading={end.isPending}
                  onClick={async () => {
                    if (!(await confirm(`לסיים את ההצמדה של ${current.driver_name ?? 'הנהג'}?`, {
                      title: 'סיום הצמדה',
                      confirmLabel: 'סיום',
                    })))
                      return
                    end.mutate(format(new Date(), 'yyyy-MM-dd'), {
                      onSuccess: () => toast.success('ההצמדה הסתיימה'),
                      onError: (e) => toast.error(errorMessage(e)),
                    })
                  }}
                >
                  סיום הצמדה
                </Button>
              )}
            </div>
          )}
        </CardBody>
      </Card>

      <Card>
        <CardHeader title="היסטוריית נהגים" subtitle="מי נהג ברכב, ומתי עד מתי" />
        <CardBody padded={false}>
          {history.length === 0 ? (
            <EmptyState compact art="people" title="אין היסטוריה" description="הצמדות שהסתיימו יופיעו כאן" />
          ) : (
            <ul>
              {history.map((r) => (
                <li key={r.id} className="flex items-center gap-3 border-b border-line-subtle px-4 py-2.5 last:border-0">
                  <span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-subtle text-ink-tertiary" aria-hidden>
                    <User size={ICON.sm} strokeWidth={STROKE} />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate type-body">{r.driver_name ?? '—'}</p>
                    <p className="truncate type-caption tabular text-ink-tertiary">
                      {fmtDate(r.from_date)} — {r.to_date ? fmtDate(r.to_date) : ''}
                      {r.note ? ` · ${r.note}` : ''}
                    </p>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </CardBody>
      </Card>

      <AssignDriverModal vehicle={vehicle} open={assignOpen} onClose={() => setAssignOpen(false)} hasCurrent={!!current} />
    </div>
  )
}

/* ===== הצמדה ============================================================== */

function AssignDriverModal({
  vehicle,
  open,
  onClose,
  hasCurrent,
}: {
  vehicle: Vehicle
  open: boolean
  onClose: () => void
  hasCurrent: boolean
}) {
  const toast = useToast()
  const { data: staff = [] } = useStaff(open)
  const assign = useAssignDriver(vehicle.id)

  const [form, setForm] = useState({ profileId: '', from: '', note: '' })
  const [openedFor, setOpenedFor] = useState(false)
  if (open !== openedFor) {
    setOpenedFor(open)
    if (open) setForm({ profileId: '', from: format(new Date(), 'yyyy-MM-dd'), note: '' })
  }

  /* נהגים קודם — הם הרוב המכריע של הבחירות — ואחריהם השאר. ראש צוות שנוהג
     במלגזה הוא מקרה אמיתי, ולכן הרשימה אינה מסוננת אלא ממוינת. */
  const options = useMemo(() => {
    const isDriver = (p: (typeof staff)[number]) => p.staff_roles?.some((r) => r.role === 'driver') ?? false
    return [...staff].sort((a, b) => {
      const d = Number(isDriver(b)) - Number(isDriver(a))
      return d !== 0 ? d : a.full_name.localeCompare(b.full_name, 'he')
    })
  }, [staff])

  const valid = form.profileId !== '' && form.from !== ''

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={hasCurrent ? 'החלפת נהג' : 'הצמדת נהג'}
      description={hasCurrent ? 'ההצמדה הקיימת תיסגר ביום שלפני, וההיסטוריה תישמר' : undefined}
      footer={
        <>
          <Button className="ms-auto" onClick={onClose}>
            ביטול
          </Button>
          <Button
            variant="primary"
            loading={assign.isPending}
            disabled={!valid}
            onClick={() =>
              assign.mutate(form, {
                onSuccess: () => {
                  toast.success('הנהג הוצמד לרכב')
                  onClose()
                },
                onError: (e) => toast.error(errorMessage(e)),
              })
            }
          >
            הצמדה
          </Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="נהג" required>
          <Select
            data-autofocus
            value={form.profileId}
            onChange={(e) => setForm((f) => ({ ...f, profileId: e.target.value }))}
          >
            <option value="">בחירת עובד...</option>
            {options.map((p) => (
              <option key={p.id} value={p.id}>
                {p.full_name}
                {p.staff_roles?.some((r) => r.role === 'driver') ? ' · נהג' : ''}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="מתאריך" required>
          <Input type="date" value={form.from} onChange={(e) => setForm((f) => ({ ...f, from: e.target.value }))} />
        </Field>
        <Field label="הערה" className="sm:col-span-2">
          <Textarea autoGrow rows={2} value={form.note} onChange={(e) => setForm((f) => ({ ...f, note: e.target.value }))} />
        </Field>
      </div>
    </Modal>
  )
}
