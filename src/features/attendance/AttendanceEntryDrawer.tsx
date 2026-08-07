import { useEffect, useState } from 'react'
import { useMutation } from '@tanstack/react-query'
import { ICON, MapPin, STROKE, Trash2 } from '../../components/ui/icons'
import {
  Badge,
  Button,
  Drawer,
  Field,
  Input,
  Textarea,
  useConfirm,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { fmtDateTime, fmtMoney } from '../../lib/dates'
import { useAttendanceInvalidate } from './attendanceQueries'
import { WORK_SITE_LABELS, fmtDistance, fmtDuration, flagLabel } from './shiftFormat'
import type { AttendanceReportRow } from '../../types/domain'

/** timestamptz -> הערך ש-<input type="datetime-local"> מצפה לו, בשעון המקומי. */
function toLocalInput(iso: string | null | undefined): string {
  if (!iso) return ''
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

export function AttendanceEntryDrawer({
  row,
  onClose,
}: {
  row: AttendanceReportRow | null
  onClose: () => void
}) {
  const toast = useToast()
  const has = useAuth((s) => s.has)
  const { confirm, dialog } = useConfirm()
  const invalidate = useAttendanceInvalidate()
  const canEdit = has(PERM.ATTENDANCE_EDIT_ENTRY)
  const canDelete = has(PERM.ATTENDANCE_DELETE)

  const [form, setForm] = useState({ clockIn: '', clockOut: '', note: '' })

  useEffect(() => {
    if (!row) return
    setForm({
      clockIn: toLocalInput(row.clock_in_at),
      clockOut: toLocalInput(row.clock_out_at),
      note: row.manager_note ?? '',
    })
  }, [row])

  const save = useMutation({
    mutationFn: async () => {
      if (!row) return
      if (!form.clockIn) throw new Error('חובה להזין שעת כניסה')
      const { error } = await supabase.rpc('attendance_save_entry', {
        p_id: row.id,
        p_clock_in: new Date(form.clockIn).toISOString(),
        p_clock_out: form.clockOut ? new Date(form.clockOut).toISOString() : null,
        p_manager_note: form.note || null,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('הרשומה עודכנה')
      invalidate()
      onClose()
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const remove = useMutation({
    mutationFn: async () => {
      if (!row) return
      const { error } = await supabase.rpc('attendance_delete_entry', { p_id: row.id, p_restore: false })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('הרשומה נמחקה')
      invalidate()
      onClose()
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const pay = row?.pay
  const corrected = !!row && (!!row.raw_clock_in_at || !!row.raw_clock_out_at)

  return (
    <>
      <Drawer
        open={!!row}
        onClose={onClose}
        title={row?.full_name ?? ''}
        description={row ? `${row.work_date} · משמרת ${row.seq}` : undefined}
        footer={
          canEdit && (
            <>
              {canDelete && (
                <Button
                  variant="ghost"
                  onClick={async () => {
                    if (await confirm('למחוק את רשומת הנוכחות?', { tone: 'danger' })) remove.mutate()
                  }}
                >
                  <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                  מחיקה
                </Button>
              )}
              <Button onClick={onClose}>ביטול</Button>
              <Button variant="primary" loading={save.isPending} onClick={() => save.mutate()}>
                שמירה
              </Button>
            </>
          )
        }
      >
        {row && (
          <div className="space-y-4">
            <div className="flex flex-wrap gap-1.5">
              <Badge tone={row.source === 'manual' ? 'warning' : 'neutral'}>
                {row.source === 'manual' ? 'הוזן ידנית' : 'שעון'}
              </Badge>
              {row.work_site && <Badge tone="info">{WORK_SITE_LABELS[row.work_site]}</Badge>}
              {row.flags.map((f) => (
                <Badge key={f} tone="warning">
                  {flagLabel(f)}
                </Badge>
              ))}
            </div>

            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="שעת כניסה" required>
                <Input
                  type="datetime-local"
                  dir="ltr"
                  value={form.clockIn}
                  disabled={!canEdit}
                  onChange={(e) => setForm((f) => ({ ...f, clockIn: e.target.value }))}
                />
              </Field>
              <Field label="שעת יציאה" hint="ריק = משמרת פתוחה">
                <Input
                  type="datetime-local"
                  dir="ltr"
                  value={form.clockOut}
                  disabled={!canEdit}
                  onChange={(e) => setForm((f) => ({ ...f, clockOut: e.target.value }))}
                />
              </Field>
            </div>

            {/* המדידה המקורית נשמרת בנפרד, כך שתיקון של מנהל אינו מוחק את
                מה שהשעון ראה בפועל. */}
            {corrected && (
              <div className="rounded-lg border border-line-subtle bg-subtle/50 p-3 type-caption text-ink-secondary">
                <p className="type-overline mb-1">כפי שנמדד בשעון</p>
                <p dir="ltr">
                  {fmtDateTime(row.raw_clock_in_at)} — {fmtDateTime(row.raw_clock_out_at) || '…'}
                </p>
                {row.edited_at && <p className="mt-1">תוקן ב-{fmtDateTime(row.edited_at)}</p>}
              </div>
            )}

            <div className="grid gap-3 sm:grid-cols-3">
              <Stat label="מתוכנן" value={`${fmtDuration(row.planned_hours)} ש׳`} />
              <Stat label="בפועל" value={`${fmtDuration(row.actual_hours)} ש׳`} />
              <Stat label="לתשלום" value={`${fmtDuration(pay?.paid_hours)} ש׳`} />
            </div>

            {(row.in_distance_m != null || row.out_distance_m != null) && (
              <p className="flex flex-wrap items-center gap-3 type-caption text-ink-tertiary">
                <MapPin size={ICON.sm} strokeWidth={STROKE} />
                {row.in_distance_m != null && <span>כניסה: {fmtDistance(row.in_distance_m)} מהאתר</span>}
                {row.out_distance_m != null && <span>יציאה: {fmtDistance(row.out_distance_m)} מהאתר</span>}
              </p>
            )}

            {/* lines מושמט לחלוטין למי שאינו רשאי לראות כסף — הוא לא מגיע
                מהשרת מלכתחילה, ולכן אין כאן מה להסתיר בצד הלקוח. */}
            {pay?.lines && pay.lines.length > 0 && (
              <div className="rounded-lg border border-line-subtle">
                <p className="border-b border-line-subtle bg-subtle/50 px-3 py-2 type-overline">פירוט השכר</p>
                <ul className="divide-y divide-line-subtle">
                  {pay.lines.map((l) => (
                    <li key={l.key} className="flex items-center gap-2 px-3 py-2 type-body">
                      <span className="flex-1 truncate">{l.label}</span>
                      <span className="tabular-nums text-ink-tertiary">
                        {fmtDuration(l.hours)} × {l.rate}
                      </span>
                      <span className="w-20 text-end tabular-nums font-semibold">{fmtMoney(l.amount)}</span>
                    </li>
                  ))}
                  <li className="flex items-center gap-2 bg-subtle/50 px-3 py-2 type-body font-semibold">
                    <span className="flex-1">סך הכול</span>
                    <span className="tabular-nums">{fmtMoney(pay.total)}</span>
                  </li>
                </ul>
              </div>
            )}

            {row.employee_note && (
              <Field label="הערת העובד">
                <p className="rounded-lg border border-line-subtle bg-subtle/50 px-3 py-2 type-body">
                  {row.employee_note}
                </p>
              </Field>
            )}

            <Field label="הערת מנהל">
              <Textarea
                rows={2}
                value={form.note}
                disabled={!canEdit}
                onChange={(e) => setForm((f) => ({ ...f, note: e.target.value }))}
              />
            </Field>
          </div>
        )}
      </Drawer>
      {dialog}
    </>
  )
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border border-line-subtle bg-subtle/40 px-3 py-2">
      <p className="type-overline text-ink-tertiary">{label}</p>
      <p className="type-title tabular-nums">{value}</p>
    </div>
  )
}
