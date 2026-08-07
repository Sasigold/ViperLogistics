import { useMemo, useState } from 'react'
import { useMutation } from '@tanstack/react-query'
import { AlertTriangle, Banknote, Clock, ICON, Plus, STROKE, Timer, Users } from '../../components/ui/icons'
import {
  Badge,
  Button,
  Card,
  Checkbox,
  DataTable,
  Field,
  Input,
  Modal,
  MultiSelect,
  PageHeader,
  Select,
  StatCard,
  cx,
  useToast,
} from '../../components/ui'
import type { Column } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { useContractors, useStaff } from '../../lib/queries'
import { fmtDate, fmtMoney, fmtTime } from '../../lib/dates'
import { toISODate } from '../../lib/dates'
import { startOfMonth } from 'date-fns'
import { useAttendanceInvalidate, useAttendanceReport } from './attendanceQueries'
import { AttendanceEntryDrawer } from './AttendanceEntryDrawer'
import {
  STATUS_LABELS,
  STATUS_TONES,
  WORK_SITE_LABELS,
  fmtDuration,
  flagLabel,
  needsAttention,
} from './shiftFormat'
import type { AttendanceReportRow, AttendanceStatus } from '../../types/domain'

export default function AttendanceReportPage() {
  return (
    <RequirePermission perm={PERM.ATTENDANCE_VIEW_OWN}>
      <AttendanceReport />
    </RequirePermission>
  )
}

/**
 * מסך אחד לשלושת הקהלים של הדוח.
 *
 * הראייה נחתכת בשרת ולא כאן: attendance_report מחזיר לעובד את שלו, לקבלן את
 * הסגל שלו ולמנהל את כולם. הרכיב רק מציג פילטרים שיש בהם טעם למי שפתח אותו,
 * ולכן אותו קוד משרת גם את /attendance וגם את לשונית הפורטל.
 */
export function AttendanceReport({
  embedded,
  contractorId,
}: {
  embedded?: boolean
  contractorId?: string | null
} = {}) {
  const has = useAuth((s) => s.has)
  const canSeeAll = has(PERM.ATTENDANCE_VIEW_ALL)
  const canEdit = has(PERM.ATTENDANCE_EDIT_ENTRY)
  const canAdd = has(PERM.ATTENDANCE_MANUAL_ENTRY)
  const canApprove = has(PERM.ATTENDANCE_APPROVE_ENTRY)

  const [from, setFrom] = useState(() => toISODate(startOfMonth(new Date())))
  const [to, setTo] = useState(() => toISODate(new Date()))
  const [profileIds, setProfileIds] = useState<string[]>([])
  const [contractor, setContractor] = useState<string>('')
  const [onlyFlagged, setOnlyFlagged] = useState(false)
  const [status, setStatus] = useState<AttendanceStatus | ''>('')
  const [selected, setSelected] = useState<AttendanceReportRow | null>(null)
  const [adding, setAdding] = useState(false)

  const { data: staff = [] } = useStaff()
  const { data: contractors = [] } = useContractors()

  const { data, isLoading, error, refetch } = useAttendanceReport({
    from,
    to,
    profileIds,
    contractorId: contractorId ?? (contractor || null),
    onlyFlagged,
    status: status ? [status] : null,
  })

  const rows = data?.rows ?? []
  const totals = data?.totals
  const showMoney = !!data?.can_see_pay

  const columns = useMemo<Column<AttendanceReportRow>[]>(() => {
    const base: Column<AttendanceReportRow>[] = [
      {
        key: 'date',
        header: 'תאריך',
        sticky: true,
        fixed: true,
        sortValue: (r) => r.work_date,
        render: (r) => (
          <div className="min-w-24">
            <p className="type-body">{fmtDate(r.work_date)}</p>
            {r.seq > 1 && <p className="type-caption text-ink-tertiary">משמרת {r.seq}</p>}
          </div>
        ),
      },
      {
        key: 'name',
        header: 'עובד',
        sortValue: (r) => r.full_name,
        render: (r) => <span className="truncate">{r.full_name}</span>,
      },
      {
        key: 'planned',
        header: 'מתוכנן',
        align: 'center',
        render: (r) => (
          <span className="tabular-nums text-ink-tertiary" dir="ltr">
            {r.shift_start ? `${fmtTime(new Date(r.shift_start).toTimeString())}` : '—'}
          </span>
        ),
      },
      {
        key: 'in_out',
        header: 'כניסה / יציאה',
        align: 'center',
        render: (r) => (
          <span className="tabular-nums" dir="ltr">
            {fmtTime(new Date(r.clock_in_at).toTimeString())}
            {' – '}
            {r.clock_out_at ? fmtTime(new Date(r.clock_out_at).toTimeString()) : '…'}
          </span>
        ),
      },
      {
        key: 'actual',
        header: 'בפועל',
        align: 'center',
        sortValue: (r) => r.actual_hours ?? 0,
        render: (r) => <span className="tabular-nums">{fmtDuration(r.actual_hours)}</span>,
      },
      {
        key: 'paid',
        header: 'לתשלום',
        align: 'center',
        sortValue: (r) => r.pay?.paid_hours ?? 0,
        // שורה שאינה מאושרת מוצגת חיוורת: הסכום הוא מה שישולם *אם* יאושר,
        // והוא אינו נכנס לסיכומים למעלה.
        render: (r) => (
          <span
            className={cx(
              'tabular-nums font-semibold',
              r.status !== 'approved' && 'text-ink-tertiary',
            )}
          >
            {fmtDuration(r.pay?.paid_hours)}
          </span>
        ),
      },
      {
        key: 'overtime',
        header: 'ש״נ',
        align: 'center',
        sortValue: (r) => r.pay?.overtime_hours ?? 0,
        render: (r) =>
          r.pay?.overtime_hours ? (
            <Badge tone="warning">{fmtDuration(r.pay.overtime_hours)}</Badge>
          ) : (
            <span className="text-ink-tertiary">—</span>
          ),
      },
      {
        key: 'site',
        header: 'שטח/מחסן',
        align: 'center',
        render: (r) =>
          r.work_site ? (
            <Badge tone={r.work_site === 'warehouse' ? 'info' : 'neutral'}>
              {WORK_SITE_LABELS[r.work_site]}
            </Badge>
          ) : null,
      },
      {
        key: 'flags',
        header: 'הערות',
        render: (r) => (
          <div className="flex flex-wrap gap-1">
            {/* מאושר אינו מקבל תג: זה המצב הרגיל, ותג על כל שורה היה מסתיר
                את השתיים שדורשות מבט. */}
            {r.status !== 'approved' && (
              <Badge tone={STATUS_TONES[r.status]}>{STATUS_LABELS[r.status]}</Badge>
            )}
            {r.source === 'manual' && <Badge tone="warning">ידני</Badge>}
            {r.flags.map((f) => (
              <Badge key={f} tone={needsAttention([f]) ? 'error' : 'neutral'}>
                {flagLabel(f)}
              </Badge>
            ))}
          </div>
        ),
      },
    ]
    // עמודת הכסף מתווספת רק כשהשרת בכלל שלח סכומים — אחרת היא הייתה
    // טור של מקפים שמרמז שאין שכר, במקום שאין הרשאה.
    if (showMoney) {
      base.push({
        key: 'total',
        header: 'שכר',
        align: 'end',
        sortValue: (r) => r.pay?.total ?? 0,
        render: (r) => (
          <span
            className={cx(
              'tabular-nums font-semibold',
              r.status !== 'approved' && 'text-ink-tertiary',
            )}
          >
            {fmtMoney(r.pay?.total)}
          </span>
        ),
      })
    }
    return base
  }, [showMoney])

  const flaggedCount = rows.filter((r) => needsAttention(r.flags)).length

  return (
    <div className="space-y-4">
      {!embedded && (
        <PageHeader
          title="דוח נוכחות"
          subtitle={canSeeAll ? 'שעות, שעות נוספות ושכר לכל העובדים' : 'השעות שלי'}
          actions={
            canAdd && (
              <Button variant="primary" size="sm" onClick={() => setAdding(true)}>
                <Plus size={ICON.sm} strokeWidth={STROKE} />
                הזנה ידנית
              </Button>
            )
          }
        />
      )}

      <Card className="flex flex-wrap items-end gap-3 p-4">
        <Field label="מתאריך" className="w-40">
          <Input type="date" dir="ltr" value={from} onChange={(e) => setFrom(e.target.value)} />
        </Field>
        <Field label="עד תאריך" className="w-40">
          <Input type="date" dir="ltr" value={to} onChange={(e) => setTo(e.target.value)} />
        </Field>
        {canSeeAll && (
          <>
            <Field label="עובדים" className="min-w-52 flex-1">
              <MultiSelect
                options={staff.map((p) => ({ id: p.id, label: p.full_name }))}
                values={profileIds}
                onToggle={(id) =>
                  setProfileIds((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]))
                }
                placeholder="כל העובדים"
              />
            </Field>
            {!contractorId && (
              <Field label="קבלן" className="w-48">
                <Select value={contractor} onChange={(e) => setContractor(e.target.value)}>
                  <option value="">כל הקבלנים</option>
                  {contractors.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name}
                    </option>
                  ))}
                </Select>
              </Field>
            )}
          </>
        )}
        <Field label="סטטוס" className="w-40">
          <Select value={status} onChange={(e) => setStatus(e.target.value as AttendanceStatus | '')}>
            <option value="">הכול</option>
            <option value="pending">ממתין לאישור</option>
            <option value="approved">מאושר</option>
            <option value="rejected">נדחה</option>
          </Select>
        </Field>
        <Checkbox
          checked={onlyFlagged}
          onChange={setOnlyFlagged}
          label="רק רשומות עם חריגה"
        />
      </Card>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard
          icon={<Users size={ICON.lg} strokeWidth={STROKE} />}
          label="משמרות"
          value={totals?.entries ?? 0}
          hint={totals?.pending ? `${totals.pending} ממתינות לאישור` : undefined}
        />
        {/* השעות והשכר סופרים מאושרות בלבד — מה שממתין לאישור אינו נכנס
            לכאן עד שיוכרע. */}
        <StatCard
          icon={<Clock size={ICON.lg} strokeWidth={STROKE} />}
          label="שעות מאושרות"
          value={fmtDuration(totals?.actual_hours)}
          hint={`${fmtDuration(totals?.paid_hours)} לתשלום`}
        />
        <StatCard
          icon={<Timer size={ICON.lg} strokeWidth={STROKE} />}
          label="שעות נוספות"
          value={fmtDuration(totals?.overtime_hours)}
          tone="#f59e0b"
        />
        {showMoney ? (
          <StatCard
            icon={<Banknote size={ICON.lg} strokeWidth={STROKE} />}
            label="שכר לתשלום"
            value={fmtMoney(totals?.total)}
            tone="#22c55e"
          />
        ) : (
          <StatCard
            icon={<AlertTriangle size={ICON.lg} strokeWidth={STROKE} />}
            label="חריגות"
            value={flaggedCount}
            tone="#ef4444"
            invertDelta
          />
        )}
      </div>

      <DataTable
        rows={rows}
        columns={columns}
        getRowId={(r) => r.id}
        loading={isLoading}
        error={error ? (error as Error).message : undefined}
        onRetry={() => void refetch()}
        empty="לא נמצאו רשומות נוכחות בטווח הזה"
        onRowClick={canEdit || canApprove ? (r) => setSelected(r) : undefined}
        storageKey="attendance-report"
        pageSize={50}
      />

      <AttendanceEntryDrawer row={selected} onClose={() => setSelected(null)} />
      {adding && <ManualEntryModal onClose={() => setAdding(false)} />}
    </div>
  )
}

/** הנתיב הידני: פטור מבדיקת המיקום, ומסומן ככזה ברשומה. */
function ManualEntryModal({ onClose }: { onClose: () => void }) {
  const toast = useToast()
  const invalidate = useAttendanceInvalidate()
  const { data: staff = [] } = useStaff()
  const [form, setForm] = useState({ profileId: '', clockIn: '', clockOut: '', note: '' })

  const save = useMutation({
    mutationFn: async () => {
      if (!form.profileId) throw new Error('יש לבחור עובד')
      if (!form.clockIn) throw new Error('חובה להזין שעת כניסה')
      const { error } = await supabase.rpc('attendance_record_entry', {
        p_profile_id: form.profileId,
        p_clock_in: new Date(form.clockIn).toISOString(),
        p_clock_out: form.clockOut ? new Date(form.clockOut).toISOString() : null,
        p_note: form.note || null,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('הנוכחות נרשמה')
      invalidate()
      onClose()
    },
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <Modal
      open
      onClose={onClose}
      size="sm"
      title="הזנת נוכחות ידנית"
      footer={
        <>
          <Button onClick={onClose}>ביטול</Button>
          <Button variant="primary" loading={save.isPending} onClick={() => save.mutate()}>
            שמירה
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <Field label="עובד" required>
          <Select
            data-autofocus
            value={form.profileId}
            onChange={(e) => setForm((f) => ({ ...f, profileId: e.target.value }))}
          >
            <option value="">בחירת עובד…</option>
            {staff.map((p) => (
              <option key={p.id} value={p.id}>
                {p.full_name}
              </option>
            ))}
          </Select>
        </Field>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="שעת כניסה" required>
            <Input
              type="datetime-local"
              dir="ltr"
              value={form.clockIn}
              onChange={(e) => setForm((f) => ({ ...f, clockIn: e.target.value }))}
            />
          </Field>
          <Field label="שעת יציאה">
            <Input
              type="datetime-local"
              dir="ltr"
              value={form.clockOut}
              onChange={(e) => setForm((f) => ({ ...f, clockOut: e.target.value }))}
            />
          </Field>
        </div>
        <Field label="סיבה" hint="נשמר כהערת מנהל על הרשומה">
          <Input value={form.note} onChange={(e) => setForm((f) => ({ ...f, note: e.target.value }))} />
        </Field>
      </div>
    </Modal>
  )
}
