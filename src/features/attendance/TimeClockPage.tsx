import { useEffect, useState } from 'react'
import { useMutation } from '@tanstack/react-query'
import { CalendarClock, Clock, ICON, LogOut, MapPin, STROKE, Timer } from '../../components/ui/icons'
import {
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  Skeleton,
  Textarea,
  cx,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { fmtTime } from '../../lib/dates'
import { useAttendanceInvalidate, useMyClockStatus } from './attendanceQueries'
import { GEO_MESSAGES, useGeolocation } from './useGeolocation'
import { WORK_SITE_LABELS, fmtDistance, fmtDuration, fmtShiftRange, flagLabel } from './shiftFormat'

/** מונה חי מרגע הכניסה. שנייה אחת היא הרזולוציה שאנשים מצפים לה משעון. */
function useElapsed(since: string | null | undefined) {
  const [now, setNow] = useState(() => Date.now())
  useEffect(() => {
    if (!since) return
    const t = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(t)
  }, [since])
  if (!since) return null
  const secs = Math.max(0, Math.floor((now - new Date(since).getTime()) / 1000))
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${pad(Math.floor(secs / 3600))}:${pad(Math.floor((secs % 3600) / 60))}:${pad(secs % 60)}`
}

export default function TimeClockPage() {
  return (
    <RequirePermission perm={PERM.ATTENDANCE_VIEW_OWN}>
      <TimeClock />
    </RequirePermission>
  )
}

function TimeClock() {
  const toast = useToast()
  const me = useAuth((s) => s.me)
  const has = useAuth((s) => s.has)
  const getPosition = useGeolocation()
  const invalidate = useAttendanceInvalidate()
  const { data: status, isLoading } = useMyClockStatus()
  const [note, setNote] = useState('')

  const open = status?.open_entry ?? null
  const shift = status?.shift ?? null
  const rules = status?.rules
  const needsLocation = !!rules?.requires_location
  const elapsed = useElapsed(open?.clock_in_at)

  /**
   * שתי ההחתמות חולקות מסלול אחד: קודם מיקום (אם נדרש), אחר כך ה-RPC.
   * הבדיקה כאן אינה ההגנה — השרת דוחה בכל מקרה — אלא מה שמונע נסיעה
   * מיותרת ומאפשר הודעה שמסבירה מה לעשות.
   */
  const punch = useMutation({
    mutationFn: async (kind: 'in' | 'out') => {
      let lat: number | null = null
      let lng: number | null = null
      let accuracy: number | null = null

      if (needsLocation) {
        const reading = await getPosition()
        if (reading.status !== 'ok') throw new Error(GEO_MESSAGES[reading.status])
        lat = reading.lat
        lng = reading.lng
        accuracy = reading.accuracy
      }

      const { data, error } = await supabase.rpc(
        kind === 'in' ? 'attendance_clock_in' : 'attendance_clock_out',
        { p_lat: lat, p_lng: lng, p_accuracy: accuracy, p_note: note || null },
      )
      if (error) throw error
      return data as { distance_m: number | null }
    },
    onSuccess: (data, kind) => {
      setNote('')
      invalidate()
      toast.success(
        kind === 'in' ? 'נרשמה כניסה למשמרת' : 'נרשמה יציאה מהמשמרת',
        data?.distance_m != null ? { description: `${fmtDistance(data.distance_m)} מנקודת הייחוס` } : undefined,
      )
    },
    onError: (e) => toast.error((e as Error).message),
  })

  if (isLoading) {
    return (
      <div className="mx-auto max-w-2xl space-y-4">
        <Skeleton className="h-32 w-full" />
        <Skeleton className="h-56 w-full" />
      </div>
    )
  }

  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <Card>
        <CardHeader
          title="שעון נוכחות"
          subtitle={me?.profile.full_name}
          icon={<Clock size={ICON.md} strokeWidth={STROKE} />}
          actions={
            open ? (
              <Badge tone="success">במשמרת</Badge>
            ) : (
              <Badge tone="neutral">מחוץ למשמרת</Badge>
            )
          }
        />
        <CardBody className="space-y-4">
          {/* המשמרת המתוכננת — מה שהשעון ייצמד אליו */}
          {shift ? (
            <div className="rounded-xl border border-line-subtle bg-subtle/50 p-4">
              <div className="flex flex-wrap items-center gap-2">
                <CalendarClock size={ICON.md} strokeWidth={STROKE} className="text-ink-tertiary" />
                <span className="type-title">{fmtShiftRange(shift.shift_start, shift.shift_end)}</span>
                <Badge tone={shift.work_site === 'warehouse' ? 'info' : 'neutral'}>
                  {WORK_SITE_LABELS[shift.work_site]}
                </Badge>
                {shift.planned_hours != null && (
                  <span className="type-caption text-ink-tertiary">
                    {fmtDuration(shift.planned_hours)} ש׳ מתוכננות
                  </span>
                )}
              </div>
              {shift.label && <p className="mt-1 type-body text-ink-secondary">{shift.label}</p>}
              {shift.task_ids.length > 1 && (
                <p className="mt-1 type-caption text-ink-tertiary">
                  {shift.task_ids.length} משימות אוחדו למשמרת אחת
                </p>
              )}
            </div>
          ) : (
            <div className="rounded-xl border border-warning-border bg-warning-subtle px-4 py-3 type-body text-warning-text">
              אין לך משמרת משובצת כרגע.
            </div>
          )}

          {open && (
            <div className="flex flex-col items-center gap-1 py-2">
              <span className="type-overline text-ink-tertiary">בעבודה מאז {fmtTime(new Date(open.clock_in_at).toTimeString())}</span>
              <span className="font-mono text-4xl tabular-nums" dir="ltr">
                {elapsed}
              </span>
            </div>
          )}

          {needsLocation && (
            <p className="flex items-center gap-1.5 type-caption text-ink-tertiary">
              <MapPin size={ICON.sm} strokeWidth={STROKE} />
              נדרש שיתוף מיקום כדי להחתים. ההחתמה תידחה מחוץ לטווח של{' '}
              {fmtDistance(rules?.location_radius_m)}.
            </p>
          )}

          <Textarea
            rows={2}
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="הערה (לא חובה)"
            aria-label="הערה להחתמה"
          />

          {has(PERM.ATTENDANCE_CLOCK) ? (
            <Button
              variant={open ? 'danger' : 'primary'}
              size="lg"
              className="w-full"
              loading={punch.isPending}
              onClick={() => punch.mutate(open ? 'out' : 'in')}
            >
              {open ? (
                <>
                  <LogOut size={ICON.lg} strokeWidth={STROKE} />
                  יציאה מהמשמרת
                </>
              ) : (
                <>
                  <Timer size={ICON.lg} strokeWidth={STROKE} />
                  כניסה למשמרת
                </>
              )}
            </Button>
          ) : (
            <p className="rounded-lg border border-line-subtle bg-subtle px-3 py-2 type-caption text-ink-tertiary">
              אין לך הרשאה להחתים שעון. פנה למנהל.
            </p>
          )}
        </CardBody>
      </Card>

      <Card>
        <CardHeader title="ההחתמות של היום" icon={<Clock size={ICON.md} strokeWidth={STROKE} />} />
        <CardBody>
          {(status?.today ?? []).length === 0 ? (
            <EmptyState compact art="calendar" title="עדיין לא הוחתם היום" />
          ) : (
            <ul className="divide-y divide-line-subtle">
              {(status?.today ?? []).map((e) => (
                <li key={e.id} className="flex flex-wrap items-center gap-2 py-2.5">
                  <span className="font-mono tabular-nums type-body" dir="ltr">
                    {fmtShiftRange(e.clock_in_at, e.clock_out_at) || '—'}
                  </span>
                  <span
                    className={cx(
                      'type-caption',
                      e.clock_out_at ? 'text-ink-secondary' : 'text-success-text',
                    )}
                  >
                    {e.clock_out_at ? `${fmtDuration(e.actual_hours)} ש׳` : 'פתוחה'}
                  </span>
                  {e.flags.map((f) => (
                    <Badge key={f} tone="warning">
                      {flagLabel(f)}
                    </Badge>
                  ))}
                </li>
              ))}
            </ul>
          )}
        </CardBody>
      </Card>
    </div>
  )
}
