import { useMemo, useState } from 'react'
import { format } from 'date-fns'
import {
  AlertTriangle,
  Eye,
  ICON,
  IdCard,
  Paperclip,
  Pencil,
  STROKE,
  User,
  UserCheck,
  UserPlus,
} from '../../components/ui/icons'
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
import type { DriverLicense } from '../../types/domain'
import {
  useAssignDriver,
  useDriverLicense,
  useDriverLicenseFileUrl,
  useEndDriver,
  useSaveDriverLicense,
  useVehicleDrivers,
} from './vehicleQueries'
import type { LicenseDraft } from './vehicleQueries'
import {
  DATE_MAX,
  DATE_MIN,
  DOC_STATE_COLORS,
  DOC_STATE_LABELS,
  VEHICLE_DOC_ACCEPT,
  docState,
  driverInsuranceIssues,
  expiryLabel,
  formatBytes,
  fullYearsSince,
  isSaneDate,
  previewKind,
  validateDocFile,
} from './vehicles'
import { FilePreviewModal } from './FilePreviewModal'

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

      {current && <DriverLicenseCard vehicle={vehicle} profileId={current.profile_id} driverName={current.driver_name} />}

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

/* ===== רישיון הנהיגה (0240) ============================================== */

/** ימי התראה לפני פקיעת הרישיון — אותו סדר גודל של מסמכי הרכב. */
const LICENSE_ALERT_DAYS = 30

/**
 * רישיון הנהג המוצמד: צילום, תוקף, גיל וותק — ומולם תנאי הביטוח של הרכב.
 * הרישיון שייך לנהג ולא לרכב, ולכן עריכה כאן מתעדכנת בכל רכב שהוא נוהג בו.
 */
function DriverLicenseCard({
  vehicle,
  profileId,
  driverName,
}: {
  vehicle: Vehicle
  profileId: string
  driverName: string | null
}) {
  const { has } = useAuth()
  const canView = has(PERM.FLEET_DOCS_VIEW)
  const canManage = has(PERM.FLEET_DRIVERS_MANAGE)
  const { data: license, isLoading } = useDriverLicense(profileId, canView)
  const { data: fileUrl } = useDriverLicenseFileUrl(canView ? license : null)
  const [editOpen, setEditOpen] = useState(false)
  const [previewOpen, setPreviewOpen] = useState(false)

  if (!canView) return null

  const issues = isLoading ? [] : driverInsuranceIssues(license, vehicle)
  const state = license ? docState(license.expires_at, LICENSE_ALERT_DAYS) : null
  const age = fullYearsSince(license?.birth_date)
  const years = fullYearsSince(license?.first_issued_at)
  const isImage = previewKind(license?.mime_type, license?.file_name) === 'image'

  return (
    <Card>
      <CardHeader
        title="רישיון נהיגה"
        subtitle={driverName ?? undefined}
        icon={<IdCard size={ICON.md} strokeWidth={STROKE} />}
        actions={
          canManage && (
            <Button size="sm" onClick={() => setEditOpen(true)}>
              <Pencil size={ICON.sm} strokeWidth={STROKE} />
              {license ? 'עדכון רישיון' : 'הוספת רישיון'}
            </Button>
          )
        }
      />
      <CardBody className="space-y-3">
        {isLoading ? (
          <Skeleton className="h-16 w-full" />
        ) : !license ? (
          <p className="type-body text-ink-tertiary">לא נרשם רישיון נהיגה לנהג הזה.</p>
        ) : (
          <div className="flex flex-wrap items-start gap-4">
            {fileUrl &&
              (isImage ? (
                <button type="button" className="shrink-0" onClick={() => setPreviewOpen(true)} aria-label="צפייה ברישיון">
                  <img
                    src={fileUrl}
                    alt={`רישיון הנהיגה של ${driverName ?? 'הנהג'}`}
                    className="h-28 w-44 rounded-lg border border-line-subtle object-cover"
                  />
                </button>
              ) : (
                <Button size="sm" onClick={() => setPreviewOpen(true)}>
                  <Eye size={ICON.sm} strokeWidth={STROKE} />
                  צפייה ברישיון
                </Button>
              ))}
            <dl className="grid min-w-0 flex-1 grid-cols-2 gap-x-4 gap-y-2 type-body sm:grid-cols-3">
              <div>
                <dt className="type-caption text-ink-tertiary">תוקף</dt>
                <dd className="flex flex-wrap items-center gap-1.5">
                  {license.expires_at ? fmtDate(license.expires_at) : '—'}
                  {state && <StatusPill color={DOC_STATE_COLORS[state]}>{DOC_STATE_LABELS[state]}</StatusPill>}
                </dd>
                {license.expires_at && <dd className="type-caption text-ink-tertiary">{expiryLabel(license.expires_at)}</dd>}
              </div>
              <div>
                <dt className="type-caption text-ink-tertiary">מספר רישיון</dt>
                <dd dir="ltr" className="text-start tabular">{license.license_number ?? '—'}</dd>
              </div>
              <div>
                <dt className="type-caption text-ink-tertiary">דרגות</dt>
                <dd dir="ltr" className="text-start">{license.license_classes ?? '—'}</dd>
              </div>
              <div>
                <dt className="type-caption text-ink-tertiary">גיל</dt>
                <dd>{age == null ? '—' : `${age}`}</dd>
              </div>
              <div>
                <dt className="type-caption text-ink-tertiary">ותק</dt>
                <dd>{years == null ? '—' : `${years} שנים (מ-${fmtDate(license.first_issued_at)})`}</dd>
              </div>
              {license.note && (
                <div className="col-span-2 sm:col-span-3">
                  <dt className="type-caption text-ink-tertiary">הערה</dt>
                  <dd>{license.note}</dd>
                </div>
              )}
            </dl>
          </div>
        )}

        {issues.length > 0 && (
          <div className="flex items-start gap-2 rounded-lg bg-warning/10 p-3 type-body text-warning">
            <AlertTriangle size={ICON.sm} strokeWidth={STROKE} className="mt-0.5 shrink-0" />
            <ul className="space-y-0.5">
              {issues.map((i) => (
                <li key={i}>{i}</li>
              ))}
            </ul>
          </div>
        )}
      </CardBody>

      <FilePreviewModal
        open={previewOpen}
        onClose={() => setPreviewOpen(false)}
        title={`רישיון נהיגה${driverName ? ` · ${driverName}` : ''}`}
        url={fileUrl}
        mimeType={license?.mime_type}
        fileName={license?.file_name}
      />

      {canManage && (
        <LicenseModal
          open={editOpen}
          onClose={() => setEditOpen(false)}
          profileId={profileId}
          driverName={driverName}
          license={license ?? null}
        />
      )}
    </Card>
  )
}

function LicenseModal({
  open,
  onClose,
  profileId,
  driverName,
  license,
}: {
  open: boolean
  onClose: () => void
  profileId: string
  driverName: string | null
  license: DriverLicense | null
}) {
  const toast = useToast()
  const save = useSaveDriverLicense(profileId)
  const [draft, setDraft] = useState<LicenseDraft>({
    license_number: '',
    license_classes: '',
    first_issued_at: '',
    expires_at: '',
    birth_date: '',
    note: '',
    file: null,
  })
  const [fileError, setFileError] = useState<string | null>(null)
  const [openedFor, setOpenedFor] = useState(false)
  if (open !== openedFor) {
    setOpenedFor(open)
    setFileError(null)
    if (open)
      setDraft({
        license_number: license?.license_number ?? '',
        license_classes: license?.license_classes ?? '',
        first_issued_at: license?.first_issued_at ?? '',
        expires_at: license?.expires_at ?? '',
        birth_date: license?.birth_date ?? '',
        note: license?.note ?? '',
        file: null,
      })
  }

  const badDate = [draft.first_issued_at, draft.expires_at, draft.birth_date].some((d) => !isSaneDate(d))
  const valid = !fileError && !badDate

  const pickFile = (file: File | null) => {
    if (!file) {
      setFileError(null)
      return setDraft((d) => ({ ...d, file: null }))
    }
    const err = validateDocFile(file)
    setFileError(err)
    setDraft((d) => ({ ...d, file: err ? null : file }))
  }

  const dateField = (key: 'first_issued_at' | 'expires_at' | 'birth_date', label: string, hint?: string) => (
    <Field label={label} hint={hint} error={isSaneDate(draft[key]) ? undefined : 'תאריך לא תקין — בדקו את השנה'}>
      <Input
        type="date"
        min={DATE_MIN}
        max={DATE_MAX}
        value={draft[key]}
        onChange={(e) => setDraft((d) => ({ ...d, [key]: e.target.value }))}
      />
    </Field>
  )

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={`רישיון נהיגה${driverName ? ` · ${driverName}` : ''}`}
      description="הרישיון שייך לנהג — הוא יוצג בכל רכב שהנהג מוצמד אליו"
      footer={
        <>
          <Button className="ms-auto" onClick={onClose}>
            ביטול
          </Button>
          <Button
            variant="primary"
            loading={save.isPending}
            disabled={!valid}
            onClick={() =>
              save.mutate(
                { draft, existing: license },
                {
                  onSuccess: () => {
                    toast.success('הרישיון נשמר')
                    onClose()
                  },
                  onError: (e) => toast.error(errorMessage(e)),
                },
              )
            }
          >
            שמירה
          </Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="מספר רישיון">
          <Input
            data-autofocus
            dir="ltr"
            value={draft.license_number}
            onChange={(e) => setDraft((d) => ({ ...d, license_number: e.target.value }))}
          />
        </Field>
        <Field label="דרגות" hint="למשל B, C1">
          <Input dir="ltr" value={draft.license_classes} onChange={(e) => setDraft((d) => ({ ...d, license_classes: e.target.value }))} />
        </Field>
        {dateField('expires_at', 'תוקף הרישיון')}
        {dateField('first_issued_at', 'הוצאת רישיון ראשון', 'ממנו נגזר הוותק')}
        {dateField('birth_date', 'תאריך לידה', 'ממנו נגזר הגיל')}
        <Field
          label="צילום הרישיון"
          error={fileError ?? undefined}
          hint={
            license?.file_name && !draft.file
              ? `כרגע: ${license.file_name}${license.size_bytes ? ` · ${formatBytes(license.size_bytes)}` : ''}`
              : 'תמונה או PDF, עד 25MB'
          }
        >
          <Input type="file" accept={VEHICLE_DOC_ACCEPT} onChange={(e) => pickFile(e.target.files?.[0] ?? null)} />
        </Field>
        {draft.file && (
          <p className="flex items-center gap-2 type-caption text-ink-tertiary sm:col-span-2">
            <Paperclip size={ICON.xs} strokeWidth={STROKE} />
            {draft.file.name} · {formatBytes(draft.file.size)}
          </p>
        )}
        <Field label="הערה" className="sm:col-span-2">
          <Textarea autoGrow rows={2} value={draft.note} onChange={(e) => setDraft((d) => ({ ...d, note: e.target.value }))} />
        </Field>
      </div>
    </Modal>
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
