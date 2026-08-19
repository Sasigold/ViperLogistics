import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router'
import { useMutation } from '@tanstack/react-query'
import { endOfMonth, format, startOfMonth } from 'date-fns'
import {
  Banknote,
  Calendar,
  CalendarClock,
  Clock,
  FileText,
  ICON,
  LogIn,
  LogOut,
  MapPin,
  MessageSquarePlus,
  Plus,
  STROKE,
  Trash2,
  ChevronDown,
  ChevronUp,
  Loader2,
} from '../../components/ui/icons'
import {
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  ErrorState,
  Field,
  IconButton,
  Input,
  Modal,
  Skeleton,
  Textarea,
  cx,
  fmtMoney,
  useConfirm,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { fmtDate, toISODate } from '../../lib/dates'
import { HIGHLIGHT_CLASS, useDeepLinkHighlight } from '../../lib/deepLink'
import {
  useAttendanceInvalidate,
  useAttendanceReport,
  useMyClockStatus,
  useSubmitAttendanceEntry,
} from './attendanceQueries'
import { GEO_MESSAGES, useGeolocation } from './useGeolocation'
import {
  STATUS_LABELS,
  STATUS_TONES,
  WORK_SITE_LABELS,
  fmtDistance,
  fmtDuration,
  fmtShiftRange,
  flagLabel,
} from './shiftFormat'
import type { AttendanceEntry, ClockStatus } from '../../types/domain'
import { errorMessage } from '../../lib/errors'

/** מונה חי מרגע הכניסה */
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

function formatClockTime(iso: string | null | undefined): string {
  if (!iso) return '--:--'
  try {
    const d = new Date(iso)
    if (isNaN(d.getTime())) return '--:--'
    return d.toLocaleTimeString('he-IL', { hour: '2-digit', minute: '2-digit', hour12: false })
  } catch {
    return '--:--'
  }
}

function formatClockDate(iso: string | null | undefined): string {
  if (!iso) return format(new Date(), 'dd.MM.yyyy')
  try {
    const d = new Date(iso)
    if (isNaN(d.getTime())) return format(new Date(), 'dd.MM.yyyy')
    return format(d, 'dd.MM.yyyy')
  } catch {
    return format(new Date(), 'dd.MM.yyyy')
  }
}

function getGreeting() {
  const hour = new Date().getHours()
  if (hour >= 5 && hour < 12) return 'בוקר טוב'
  if (hour >= 12 && hour < 17) return 'צהריים טובים'
  if (hour >= 17 && hour < 21) return 'ערב טוב'
  return 'לילה טוב'
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
  const { data: status, isLoading, error: statusError, refetch: refetchStatus } = useMyClockStatus()
  const [note, setNote] = useState('')
  const [showNoteInput, setShowNoteInput] = useState(false)
  const [showHistory, setShowHistory] = useState(false)
  const [reporting, setReporting] = useState(false)

  const open = status?.open_entry ?? null
  const shift = status?.shift ?? null
  const rules = status?.rules
  const needsLocation = !!rules?.requires_location
  const elapsed = useElapsed(open?.clock_in_at)
  const today = status?.today ?? []
  const reports = status?.reports ?? []
  const canSubmit =
    !!status?.can_submit && has(PERM.ATTENDANCE_SUBMIT_ENTRY) && rules?.self_entry?.enabled !== false

  // חישוב נתוני תצוגה עפ"י ההחתמות
  const lastEntry = open ?? (today.length > 0 ? today[0] : null)
  const lastClockInTime = lastEntry?.clock_in_at ? formatClockTime(lastEntry.clock_in_at) : '--:--'
  const lastClockInDate = lastEntry?.clock_in_at
    ? formatClockDate(lastEntry.clock_in_at)
    : formatClockDate(new Date().toISOString())

  const allToday = open ? [open, ...today.filter((t) => t.id !== open.id)] : today
  const earliestTodayEntry =
    allToday.length > 0
      ? [...allToday].sort(
          (a, b) => new Date(a.clock_in_at).getTime() - new Date(b.clock_in_at).getTime(),
        )[0]
      : null
  const todayClockInTime = earliestTodayEntry ? formatClockTime(earliestTodayEntry.clock_in_at) : '--:--'

  const completedToday = today.filter((e) => e.clock_out_at)
  const latestTodayExit =
    completedToday.length > 0
      ? [...completedToday].sort(
          (a, b) => new Date(b.clock_out_at!).getTime() - new Date(a.clock_out_at!).getTime(),
        )[0]
      : null
  const todayClockOutTime = latestTodayExit?.clock_out_at
    ? formatClockTime(latestTodayExit.clock_out_at)
    : '--:--'

  const totalCompletedHours = completedToday.reduce((acc, curr) => acc + (curr.actual_hours ?? 0), 0)
  const todayWorkDuration = open
    ? elapsed
      ? elapsed.slice(0, 5)
      : '00:00'
    : totalCompletedHours > 0
      ? fmtDuration(totalCompletedHours)
      : '--:--'

  const firstName = me?.profile?.full_name?.split(' ')[0] ?? null

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
      setShowNoteInput(false)
      invalidate()
      toast.success(
        kind === 'in' ? 'נרשמה כניסה למשמרת' : 'נרשמה יציאה מהמשמרת',
        data?.distance_m != null ? { description: `${fmtDistance(data.distance_m)} מנקודת הייחוס` } : undefined,
      )
    },
    onError: (e) => {
      // בלי קליטה ההחתמה פשוט לא קרתה — אין תור והשליחה לא תחזור מעצמה,
      // כי השרת חותם now() ושידור מאוחר היה רושם שעה שגויה. הנתיב הנכון
      // הוא דיווח משמרת שלא הוחתמה, לאישור מנהל.
      if (typeof navigator !== 'undefined' && navigator.onLine === false) {
        toast.error('אין חיבור לרשת — ההחתמה לא נקלטה', {
          description: 'כשהקליטה תחזור אפשר להחתים שוב, או להשתמש ב"דיווח משמרת שלא הוחתמה".',
        })
        return
      }
      toast.error(errorMessage(e))
    },
  })

  if (isLoading) {
    return (
      <div className="mx-auto max-w-md space-y-4 py-8">
        <Skeleton className="h-16 w-3/4 mx-auto rounded-2xl" />
        <Skeleton className="h-28 w-full rounded-3xl" />
        <Skeleton className="h-72 w-72 mx-auto rounded-full" />
        <Skeleton className="h-36 w-full rounded-3xl" />
      </div>
    )
  }

  if (statusError != null && !status) {
    return (
      <div className="mx-auto max-w-md py-8">
        <ErrorState error={statusError} onRetry={() => void refetchStatus()} />
      </div>
    )
  }

  return (
    <div className="mx-auto max-w-md space-y-5 py-4 px-2 sm:px-4 text-ink">
      {/* כותרת ברכה עליונה */}
      <div className="text-center space-y-1">
        <h1 className="text-2xl font-black text-ink tracking-tight flex items-center justify-center gap-1.5">
          {getGreeting()}{firstName ? `, ${firstName}` : ''} <span className="inline-block animate-bounce">👋</span>
        </h1>
        <p className="text-sm font-medium text-ink-secondary">
          אנחנו שמחים לראות אותך!
        </p>
      </div>

      {/* כרטיס סטטוס עליון */}
      <div className="bg-surface rounded-3xl p-4 sm:p-5 shadow-sm border border-line-subtle grid grid-cols-2 divide-x divide-x-reverse divide-line-subtle items-center">
        {/* כניסה אחרונה (ימין ב-RTL) */}
        <div className="flex flex-col items-center justify-center text-center px-2">
          <span className="text-xs text-ink-tertiary font-medium mb-1">כניסה אחרונה</span>
          <span className="text-2xl font-black text-ink tracking-tight tabular-nums" dir="ltr">
            {lastClockInTime}
          </span>
          <span className="text-xs text-ink-tertiary font-medium mt-1">
            {lastClockInDate} היום
          </span>
        </div>

        {/* סטטוס נוכחי (שמאל ב-RTL) */}
        <div className="flex flex-col items-center justify-center text-center px-2">
          <div className="flex items-center gap-1.5 mb-1.5">
            <span className={`w-2 h-2 rounded-full ${open ? 'bg-success-subtle0 animate-pulse' : 'bg-ink-tertiary'}`} />
            <span className="text-xs text-ink-tertiary font-medium">סטטוס נוכחי</span>
          </div>
          <span className={`text-lg font-bold ${open ? 'text-success-text' : 'text-ink-secondary'}`}>
            {open ? 'נוכח בעבודה' : 'מחוץ לעבודה'}
          </span>
        </div>
      </div>

      {/* כפתור שעון עגול מרכזי */}
      <div className="flex flex-col items-center justify-center my-3 relative">
        {/* טבעת חיצונית זוהרת */}
        <div
          className={`w-72 h-72 rounded-full border flex items-center justify-center p-3 transition-all duration-300 shadow-xs ${
            open ? 'border-error-border/70 bg-error-subtle/20' : 'border-success-border/70 bg-success-subtle/20'
          }`}
        >
          {/* טבעת פנימית אמצעית */}
          <div
            className={`w-64 h-64 rounded-full border flex items-center justify-center p-2 ${
              open ? 'border-error-border/40' : 'border-success-border/40'
            }`}
          >
            {/* כפתור מעגלי ראשי */}
            <button
              type="button"
              disabled={punch.isPending || !has(PERM.ATTENDANCE_CLOCK)}
              onClick={() => punch.mutate(open ? 'out' : 'in')}
              className={`w-56 h-56 rounded-full transition-all duration-200 active:scale-95 flex flex-col items-center justify-center text-white cursor-pointer select-none shadow-xl ${
                open ? 'bg-error hover:brightness-110' : 'bg-success hover:brightness-110'
              } ${punch.isPending ? 'opacity-85 cursor-wait' : ''}`}
            >
              {punch.isPending ? (
                <Loader2 className="w-12 h-12 text-white animate-spin mb-2" />
              ) : open ? (
                <LogOut className="w-12 h-12 stroke-[2.2] text-white mb-2" />
              ) : (
                <LogIn className="w-12 h-12 stroke-[2.2] text-white mb-2" />
              )}
              <span className="text-3xl font-black text-white tracking-wide mb-0.5">
                {open ? 'יציאה' : 'כניסה'}
              </span>
              <span className="text-xs font-medium text-white/80">
                {open ? 'לחץ לסיום יום העבודה' : 'לחץ לתחילת יום העבודה'}
              </span>
            </button>
          </div>
        </div>

        {/* פיל תג תחתון מתחת לכפתור */}
        <div className="mt-4 inline-flex items-center gap-2 bg-surface px-5 py-2 rounded-full border border-line shadow-xs">
          <span className={`w-2.5 h-2.5 rounded-full ${open ? 'bg-success-subtle0 animate-pulse' : 'bg-ink-tertiary'}`} />
          <span className={`text-sm font-bold ${open ? 'text-success-text' : 'text-ink-secondary'}`}>
            {open ? 'נמצא בעבודה' : 'מחוץ לעבודה'}
          </span>
        </div>
      </div>

      {/* כרטיס סיכום היום */}
      <div className="bg-surface rounded-3xl p-5 shadow-sm border border-line-subtle space-y-4">
        {/* כותרת כרטיס */}
        <div className="flex items-center justify-start gap-2">
          <div className="w-8 h-8 rounded-xl bg-primary-subtle text-primary-text flex items-center justify-center shrink-0">
            <Calendar className="w-4 h-4" />
          </div>
          <h2 className="text-base font-bold text-ink">סיכום היום</h2>
        </div>

        {/* 3 עמודות */}
        <div className="grid grid-cols-3 divide-x divide-x-reverse divide-line-subtle text-center items-center pt-1">
          {/* שעת כניסה */}
          <div className="flex flex-col items-center justify-center px-1">
            <span className="text-xs text-ink-tertiary font-medium mb-2">שעת כניסה</span>
            <div className="flex items-center justify-center gap-1.5">
              <span className="text-base sm:text-lg font-bold text-success-text tabular-nums" dir="ltr">
                {todayClockInTime}
              </span>
              <div className="w-6 h-6 rounded-md bg-success-subtle text-success-text flex items-center justify-center shrink-0">
                <LogIn className="w-3.5 h-3.5" />
              </div>
            </div>
          </div>

          {/* משך עבודה */}
          <div className="flex flex-col items-center justify-center px-1">
            <span className="text-xs text-ink-tertiary font-medium mb-2">משך עבודה</span>
            <span className="text-base sm:text-lg font-bold text-ink tabular-nums" dir="ltr">
              {todayWorkDuration}
            </span>
          </div>

          {/* שעת יציאה */}
          <div className="flex flex-col items-center justify-center px-1">
            <span className="text-xs text-ink-tertiary font-medium mb-2">שעת יציאה</span>
            <div className="flex items-center justify-center gap-1.5">
              <div className="w-6 h-6 rounded-md bg-error-subtle text-error-text flex items-center justify-center shrink-0">
                <LogOut className="w-3.5 h-3.5" />
              </div>
              <span className="text-base sm:text-lg font-bold text-ink-tertiary tabular-nums" dir="ltr">
                {todayClockOutTime}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* מידע משלימה ותכונות עזר (הערה, מיקום, דיווח ידני, משמרת) */}
      <div className="space-y-3 pt-1">
        {/* דרישת מיקום במידה וקיים */}
        {needsLocation && (
          <div className="flex items-center justify-center gap-1.5 text-xs text-ink-secondary bg-subtle py-2 px-3 rounded-xl border border-line-subtle text-center">
            <MapPin size={ICON.sm} strokeWidth={STROKE} className="text-ink-tertiary shrink-0" />
            <span>
              נדרש שיתוף מיקום להחתמה ({fmtDistance(rules?.location_radius_m)} מהאתר)
            </span>
          </div>
        )}

        {/* משמרת מתוכננת במידה וקיימת */}
        {shift && (
          <div className="rounded-2xl border border-line-subtle bg-subtle/70 p-3.5 text-xs text-ink-secondary">
            <div className="flex items-center justify-between gap-2">
              <div className="flex items-center gap-2 font-medium">
                <CalendarClock size={ICON.md} strokeWidth={STROKE} className="text-ink-tertiary" />
                <span>משמרת מתוכננת: {fmtShiftRange(shift.shift_start, shift.shift_end)}</span>
              </div>
              <Badge tone={shift.work_site === 'warehouse' ? 'info' : 'neutral'}>
                {shift.work_site === 'warehouse' && shift.warehouse_name
                  ? shift.warehouse_name
                  : WORK_SITE_LABELS[shift.work_site]}
              </Badge>
            </div>
          </div>
        )}

        {/* הוספת הערה להחתמה */}
        <div className="text-center">
          {!showNoteInput ? (
            <button
              type="button"
              onClick={() => setShowNoteInput(true)}
              className="inline-flex items-center gap-1.5 text-xs font-semibold text-ink-secondary hover:text-ink transition-colors py-1"
            >
              <MessageSquarePlus size={14} />
              {note ? `הערה: ${note}` : 'הוסף הערה להחתמה (אופציונלי)'}
            </button>
          ) : (
            <div className="space-y-1.5 text-right">
              <Input
                inputSize="sm"
                value={note}
                onChange={(e) => setNote(e.target.value)}
                placeholder="הערה להחתמה..."
                autoFocus
              />
              <div className="flex justify-end gap-2">
                <Button size="sm" variant="ghost" onClick={() => setShowNoteInput(false)}>
                  סגור
                </Button>
              </div>
            </div>
          )}
        </div>

        {/* כפתור דיווח משמרת שלא הוחתמה */}
        {canSubmit && !open && (
          <Button
            variant="secondary"
            className="w-full justify-center rounded-2xl bg-surface border border-line text-ink-secondary hover:bg-hover text-xs py-2.5 font-semibold"
            onClick={() => setReporting(true)}
          >
            <Plus size={ICON.sm} strokeWidth={STROKE} />
            דיווח משמרת שלא הוחתמה
          </Button>
        )}

        {/* דיווחים ממתינים להסכמה במידה וקיימים */}
        {reports.length > 0 && <MyReportsCard reports={reports} />}

        <MyPayCard />

        {/* המסך הזה מראה את היום; החודש כולו — שעות, ש״נ והיעדרויות — נמצא
            בדוח, ומכאן הוא במרחק לחיצה גם כשהתפריט התחתון מלא. */}
        <Link
          to="/attendance"
          className="flex w-full items-center justify-center gap-1.5 rounded-2xl border border-line bg-surface py-2.5 text-xs font-semibold text-ink-secondary transition-colors hover:bg-hover"
        >
          <FileText size={ICON.sm} strokeWidth={STROKE} />
          דוח הנוכחות החודשי שלי
        </Link>

        {/* היסטוריית החתמות מתקפלת של היום */}
        <div className="border-t border-line-subtle pt-2 text-center">
          <button
            type="button"
            onClick={() => setShowHistory(!showHistory)}
            className="inline-flex items-center gap-1 text-xs text-ink-tertiary hover:text-ink-secondary transition-colors py-1"
          >
            <Clock size={13} />
            <span>ההחתמות של היום ({today.length})</span>
            {showHistory ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
          </button>

          {showHistory && (
            <div className="mt-2 text-right bg-surface rounded-2xl p-3 border border-line-subtle shadow-xs">
              {today.length === 0 ? (
                <p className="text-xs text-ink-tertiary text-center py-2">טרם הוחתם היום</p>
              ) : (
                <ul className="divide-y divide-line-subtle">
                  {today.map((e) => (
                    <li key={e.id} className="flex items-center justify-between py-2 text-xs">
                      <span className="font-mono tabular-nums text-ink-secondary" dir="ltr">
                        {fmtShiftRange(e.clock_in_at, e.clock_out_at) || '—'}
                      </span>
                      <span className={cx(e.clock_out_at ? 'text-ink-secondary' : 'text-success-text font-semibold')}>
                        {e.clock_out_at ? `${fmtDuration(e.actual_hours)} ש׳` : 'משמרת פתוחה'}
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
            </div>
          )}
        </div>
      </div>

      {/* מודאל דיווח ידני */}
      {reporting && <SelfReportModal status={status} onClose={() => setReporting(false)} />}
    </div>
  )
}

function MyReportsCard({ reports }: { reports: AttendanceEntry[] }) {
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const invalidate = useAttendanceInvalidate()
  /* התראת "הדיווח שלך אושר/נדחה" מובילה לכאן עם ?entry=. אין מגירה לפתוח
     במסך הזה — הרשימה היא כל מה שיש — ולכן הסימון הוא גלילה והבזק. */
  const [params] = useSearchParams()
  const entryParam = params.get('entry')
  const highlightRef = useDeepLinkHighlight(entryParam, reports.length > 0)

  const withdraw = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('attendance_delete_entry', { p_id: id, p_restore: false })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('הדיווח בוטל')
      invalidate()
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <>
      <Card className="rounded-2xl border-line-subtle">
        <CardHeader
          title="הדיווחים שלי"
          subtitle="משמרות שדיווחת ידנית"
          icon={<CalendarClock size={ICON.md} strokeWidth={STROKE} />}
        />
        <CardBody className="p-3">
          <ul className="divide-y divide-line-subtle">
            {reports.map((e) => (
              <li
                key={e.id}
                ref={e.id === entryParam ? (highlightRef as React.Ref<HTMLLIElement>) : undefined}
                className={cx(
                  'flex flex-wrap items-center gap-2 py-2 text-xs',
                  e.id === entryParam && HIGHLIGHT_CLASS,
                )}
              >
                <span className="text-ink-secondary font-medium">{fmtDate(e.work_date)}</span>
                <span className="font-mono tabular-nums text-ink-secondary" dir="ltr">
                  {fmtShiftRange(e.clock_in_at, e.clock_out_at)}
                </span>
                <span className="text-ink-secondary">{fmtDuration(e.actual_hours)} ש׳</span>
                <Badge tone={STATUS_TONES[e.status]}>{STATUS_LABELS[e.status]}</Badge>
                {e.status === 'rejected' && e.manager_note && (
                  <span className="text-ink-tertiary">{e.manager_note}</span>
                )}
                <span className="flex-1" />
                {e.status === 'pending' && (
                  <IconButton
                    label="ביטול הדיווח"
                    disabled={withdraw.isPending}
                    onClick={async () => {
                      if (await confirm('לבטל את הדיווח?', { tone: 'danger' })) withdraw.mutate(e.id)
                    }}
                  >
                    <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                  </IconButton>
                )}
              </li>
            ))}
          </ul>
        </CardBody>
      </Card>
      {dialog}
    </>
  )
}

function toLocalInput(iso: string | null | undefined): string {
  if (!iso) return ''
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

/**
 * השכר של החודש, בשעון עצמו.
 *
 * ‏`attendance_report` כבר מחזיר את הסכומים לשורות של הקורא עצמו כשהוא מחזיק
 * `attendance.view_own_pay` — ומשמיט אותם לגמרי כשלא. לכן אין כאן שאלת
 * הרשאה שנייה: אם `totals.total` חזר, מותר לו לראות אותו, וזו אותה הכרעה
 * בדיוק שהשרת עשה. מה שממתין לאישור אינו נספר בו, כמו בדוח.
 */
function MyPayCard() {
  const from = toISODate(startOfMonth(new Date()))
  const to = toISODate(endOfMonth(new Date()))
  const { data } = useAttendanceReport({ from, to })
  const totals = data?.totals
  if (!totals || totals.total == null) return null

  return (
    <Card>
      <CardHeader
        title="השכר שלי החודש"
        subtitle="שעות שאושרו בלבד"
        icon={<Banknote size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody>
        <div className="grid grid-cols-3 gap-2 text-center">
          <div>
            <div className="type-overline">שעות</div>
            <div className="type-subtitle tabular">{fmtDuration(totals.paid_hours ?? 0)} ש׳</div>
          </div>
          <div>
            <div className="type-overline">תוספות</div>
            <div className="type-subtitle tabular" dir="ltr">{fmtMoney(totals.bonus ?? 0)}</div>
          </div>
          <div>
            <div className="type-overline">לתשלום</div>
            <div className="type-subtitle tabular font-bold text-success-text" dir="ltr">
              {fmtMoney(totals.total)}
            </div>
          </div>
        </div>
      </CardBody>
    </Card>
  )
}

function SelfReportModal({ status, onClose }: { status?: ClockStatus; onClose: () => void }) {
  const toast = useToast()
  const submit = useSubmitAttendanceEntry()
  const shift = status?.shift ?? null
  const self = status?.rules?.self_entry

  const [form, setForm] = useState(() => ({
    clockIn: toLocalInput(shift?.shift_start),
    clockOut: toLocalInput(shift?.shift_end),
    note: '',
    inPlace: '',
    outPlace: '',
  }))

  const save = () => {
    if (!form.clockIn || !form.clockOut) {
      toast.error('חובה להזין שעת התחלה ושעת סיום')
      return
    }
    // השרת דוחה דיווח בלי מיקום; הבדיקה כאן היא כדי שההודעה תגיע לפני
    // הנסיעה הלוך-חזור, ולא במקומה.
    if (!form.inPlace.trim() || !form.outPlace.trim()) {
      toast.error('חובה לציין מיקום כניסה ומיקום יציאה')
      return
    }
    submit.mutate(
      {
        clockIn: form.clockIn,
        clockOut: form.clockOut,
        note: form.note,
        inPlace: form.inPlace,
        outPlace: form.outPlace,
      },
      {
        onSuccess: () => {
          toast.success('הדיווח נשלח לאישור', {
            description: 'השעות ייספרו אחרי שמנהל יאשר אותן',
          })
          onClose()
        },
        onError: (e) => toast.error(errorMessage(e)),
      },
    )
  }

  return (
    <Modal
      open
      onClose={onClose}
      size="sm"
      title="דיווח משמרת שלא הוחתמה"
      footer={
        <>
          <Button onClick={onClose}>ביטול</Button>
          <Button variant="primary" loading={submit.isPending} onClick={save}>
            שליחה לאישור
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <p className="rounded-lg border border-line-subtle bg-subtle/50 px-3 py-2 type-caption text-ink-secondary">
          הדיווח ממתין לאישור מנהל ואינו נספר בשעות ובשכר עד שיאושר.
          {self?.max_backdate_days != null && ` ניתן לדווח עד ${self.max_backdate_days} ימים אחורה.`}
        </p>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="התחלה" required>
            <Input
              data-autofocus
              type="datetime-local"
              dir="ltr"
              value={form.clockIn}
              onChange={(e) => setForm((f) => ({ ...f, clockIn: e.target.value }))}
            />
          </Field>
          <Field label="סיום" required hint="משמרת פתוחה מדווחים בשעון">
            <Input
              type="datetime-local"
              dir="ltr"
              value={form.clockOut}
              onChange={(e) => setForm((f) => ({ ...f, clockOut: e.target.value }))}
            />
          </Field>
        </div>
        {/* אין כאן GPS לאמת מולו, ולכן המיקום נכתב במילים — וזה מה שהמנהל
            מאשר לפיו. שני השדות חובה, בשרת ובמסך. */}
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="מיקום כניסה" required>
            <Input
              value={form.inPlace}
              placeholder="למשל: המחסן בראשון"
              onChange={(e) => setForm((f) => ({ ...f, inPlace: e.target.value }))}
            />
          </Field>
          <Field label="מיקום יציאה" required>
            <Input
              value={form.outPlace}
              placeholder="למשל: אולמי הגן"
              onChange={(e) => setForm((f) => ({ ...f, outPlace: e.target.value }))}
            />
          </Field>
        </div>
        <Field label="סיבה" hint="למה השעון לא הוחתם — זה מה שהמנהל יראה">
          <Textarea
            rows={2}
            value={form.note}
            onChange={(e) => setForm((f) => ({ ...f, note: e.target.value }))}
          />
        </Field>
      </div>
    </Modal>
  )
}
