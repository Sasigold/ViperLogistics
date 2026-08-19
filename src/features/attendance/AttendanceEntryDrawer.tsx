import { useEffect, useState } from 'react'
import { useMutation } from '@tanstack/react-query'
import { Check, ICON, MapPin, STROKE, Trash2, X } from '../../components/ui/icons'
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
import { useAttendanceInvalidate, useReviewAttendanceEntry, useSetShiftBonus } from './attendanceQueries'
import {
  STATUS_LABELS,
  STATUS_TONES,
  WORK_SITE_LABELS,
  fmtDistance,
  fmtDuration,
  fmtPayLineRate,
  flagLabel,
  visibleFlags,
} from './shiftFormat'
import type { AttendanceReportRow } from '../../types/domain'
import { errorMessage } from '../../lib/errors'

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
  const canApprove = has(PERM.ATTENDANCE_APPROVE_ENTRY)
  const canBonus = has(PERM.ATTENDANCE_MANAGE_BONUS)
  const isPending = row?.status === 'pending'
  const review = useReviewAttendanceEntry()
  const setBonus = useSetShiftBonus()

  /**
   * `pay.bonus` מגיע מהשרת רק למי שרשאי לראות סכומים — הוא מושמט מהאובייקט
   * יחד עם `total` ו-`lines`. לכן קיומו הוא התשובה לשאלה "מותר לו לראות
   * כסף", ואין כאן הכרעת הרשאה שנייה שיכולה לחלוק על זו של השרת.
   */
  const seesMoney = row?.pay?.bonus !== undefined

  const [form, setForm] = useState({
    clockIn: '', clockOut: '', note: '', bonus: '', bonusNote: '', inPlace: '', outPlace: '',
  })

  useEffect(() => {
    if (!row) return
    setForm({
      clockIn: toLocalInput(row.clock_in_at),
      clockOut: toLocalInput(row.clock_out_at),
      note: row.manager_note ?? '',
      bonus: row.pay?.bonus ? String(row.pay.bonus) : '',
      bonusNote: row.bonus_note ?? '',
      inPlace: row.clock_in_place ?? '',
      outPlace: row.clock_out_place ?? '',
    })
  }, [row])

  const bonusAmount = Number(form.bonus || 0)
  const bonusChanged =
    !!row && (bonusAmount !== (row.pay?.bonus ?? 0) || form.bonusNote !== (row.bonus_note ?? ''))

  const save = useMutation({
    mutationFn: async () => {
      if (!row) return
      if (canEdit) {
        if (!form.clockIn) throw new Error('חובה להזין שעת כניסה')
        const { error } = await supabase.rpc('attendance_save_entry', {
          p_id: row.id,
          p_clock_in: new Date(form.clockIn).toISOString(),
          p_clock_out: form.clockOut ? new Date(form.clockOut).toISOString() : null,
          p_manager_note: form.note || null,
          p_in_place: form.inPlace,
          p_out_place: form.outPlace,
        })
        if (error) throw error
      }
      // הבונוס נשמר בקריאה נפרדת, כי הוא נאכף במפתח אחר. היא נשלחת רק כשהוא
      // באמת השתנה — אחרת כל שמירת תיקון של רכז משמרות הייתה נדחית על
      // הרשאה שהוא לא צריך.
      if (canBonus && bonusChanged) {
        if (Number.isNaN(bonusAmount)) throw new Error('סכום הבונוס אינו מספר')
        await setBonus.mutateAsync({ id: row.id, bonus: bonusAmount, note: form.bonusNote })
      }
    },
    onSuccess: () => {
      toast.success('הרשומה עודכנה')
      invalidate()
      onClose()
    },
    onError: (e) => toast.error(errorMessage(e)),
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
    onError: (e) => toast.error(errorMessage(e)),
  })

  /**
   * ההכרעה על דיווח. הנימוק נלקח משדה "הערת מנהל" שכבר בטופס, ולא משדה
   * שני משלו: זה בדיוק אותו טקסט, והעובד רואה אותו כשהדיווח נדחה.
   */
  const decide = (approve: boolean) => {
    if (!row) return
    if (!approve && !form.note.trim()) {
      toast.error('דחייה מחייבת נימוק — כתוב אותו בהערת המנהל')
      return
    }
    review.mutate(
      { id: row.id, approve, note: form.note },
      {
        onSuccess: () => {
          toast.success(approve ? 'הדיווח אושר ונספר בשעות' : 'הדיווח נדחה')
          onClose()
        },
        onError: (e) => toast.error(errorMessage(e)),
      },
    )
  }

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
          // canBonus לבדו מספיק כדי להצדיק כפתור שמירה: חשב שכר שרשאי רק
          // לקבוע בונוס אינו מחזיק attendance.edit_entry.
          (canEdit || canBonus || (isPending && canApprove)) && (
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
              {/* כשיש הכרעה לקבל, היא הפעולה הראשית. "שמירת תיקון" נשארת
                  זמינה כדי לתקן שעה לפני האישור, אבל אינה מתחרה עליה. */}
              {isPending && canApprove ? (
                <>
                  {(canEdit || canBonus) && (
                    <Button loading={save.isPending} onClick={() => save.mutate()}>
                      שמירת תיקון
                    </Button>
                  )}
                  <Button variant="danger" loading={review.isPending} onClick={() => decide(false)}>
                    <X size={ICON.sm} strokeWidth={STROKE} />
                    דחייה
                  </Button>
                  <Button variant="primary" loading={review.isPending} onClick={() => decide(true)}>
                    <Check size={ICON.sm} strokeWidth={STROKE} />
                    אישור
                  </Button>
                </>
              ) : (
                <>
                  <Button onClick={onClose}>ביטול</Button>
                  <Button variant="primary" loading={save.isPending} onClick={() => save.mutate()}>
                    שמירה
                  </Button>
                </>
              )}
            </>
          )
        }
      >
        {row && (
          <div className="space-y-4">
            <div className="flex flex-nowrap items-center gap-1.5 overflow-hidden">
              <Badge tone={STATUS_TONES[row.status]}>{STATUS_LABELS[row.status]}</Badge>
              {row.source === 'manual' && <Badge tone="warning">ידני</Badge>}
              {row.work_site && <Badge tone="info">{WORK_SITE_LABELS[row.work_site]}</Badge>}
              {visibleFlags(row.flags).map((f) => (
                <Badge key={f} tone="warning">
                  {flagLabel(f)}
                </Badge>
              ))}
            </div>

            {row.status === 'pending' ? (
              <p className="rounded-lg border border-warning-border bg-warning-subtle px-3 py-2 type-body text-warning-text">
                הדיווח ממתין להכרעה. השעות אינן נספרות בסיכומים ובשכר עד שיאושר.
              </p>
            ) : (
              row.reviewed_at && (
                <p className="type-caption text-ink-tertiary">
                  {row.status === 'approved' ? 'אושר' : 'נדחה'} ב-{fmtDateTime(row.reviewed_at)}
                </p>
              )
            )}

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

            {/* המיקום במילים. הוא נכתב בדיווח ידני — שבו אין GPS לאמת מולו —
                ולכן הוא מוצג לכל מי שפותח את הרשומה ונערך בידי מי שמתקן
                אותה. בהחתמת שעון הוא ריק, ואז אין מה להראות. */}
            {(row.source === 'manual' || row.clock_in_place || row.clock_out_place) && (
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label="מיקום כניסה">
                  <Input
                    value={form.inPlace}
                    disabled={!canEdit}
                    placeholder="למשל: המחסן בראשון"
                    onChange={(e) => setForm((f) => ({ ...f, inPlace: e.target.value }))}
                  />
                </Field>
                <Field label="מיקום יציאה">
                  <Input
                    value={form.outPlace}
                    disabled={!canEdit}
                    placeholder="למשל: אולמי הגן"
                    onChange={(e) => setForm((f) => ({ ...f, outPlace: e.target.value }))}
                  />
                </Field>
              </div>
            )}

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

            {/* הבונוס יושב לפני פירוט השכר, כי הוא מה שמשנה אותו. הוא מוצג
                רק למי שרשאי לראות סכומים, ונעול לקריאה בלי מפתח הבונוס. */}
            {seesMoney && (canBonus || bonusAmount > 0) && (
              <div className="grid gap-4 sm:grid-cols-[10rem_1fr]">
                <Field label="בונוס למשמרת" hint="₪, מעבר לשעות">
                  <Input
                    type="number"
                    inputMode="decimal"
                    min={0}
                    step="10"
                    dir="ltr"
                    placeholder="0"
                    value={form.bonus}
                    disabled={!canBonus}
                    onChange={(e) => setForm((f) => ({ ...f, bonus: e.target.value }))}
                  />
                </Field>
                <Field label="סיבת הבונוס">
                  <Input
                    value={form.bonusNote}
                    disabled={!canBonus}
                    placeholder="למשל: משמרת לילה בהתראה קצרה"
                    onChange={(e) => setForm((f) => ({ ...f, bonusNote: e.target.value }))}
                  />
                </Field>
              </div>
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
                      {/* null לשורת הבונוס, שאינה מכפלה של שעות בתעריף */}
                      <span className="tabular-nums text-ink-tertiary">
                        {fmtPayLineRate(l.hours, l.rate)}
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
