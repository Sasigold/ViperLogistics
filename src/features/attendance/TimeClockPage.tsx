import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router'
import { useMutation } from '@tanstack/react-query'
import {
  AlertTriangle,
  CalendarClock,
  ChevronDown,
  ChevronUp,
  ICON,
  Loader2,
  Lock,
  MapPin,
  PencilLine,
  STROKE,
  Trash2,
} from '../../components/ui/icons'
import {
  Badge,
  Button,
  ErrorState,
  Field,
  IconButton,
  Input,
  Modal,
  Skeleton,
  Textarea,
  cx,
  useConfirm,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { fmtDate } from '../../lib/dates'
import { HIGHLIGHT_CLASS, useDeepLinkHighlight } from '../../lib/deepLink'
import { useHoldToConfirm } from '../../lib/useHoldToConfirm'
import {
  useAttendanceInvalidate,
  useCancelCorrection,
  useMyClockStatus,
  useRequestCorrection,
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
import {
  clockTime,
  dayLabel,
  fmtHM,
  headerDate,
  minutesBetween,
  overtimeState,
  ringArcs,
  shortDate,
} from './clockDisplay'
import type { AttendanceEntry, ClockStatus, PlannedShift } from '../../types/domain'
import { errorMessage } from '../../lib/errors'

/** שעון שמתקתק — לתצוגה בלבד; השרת חותם את ההחתמה עצמה ב-now() שלו */
function useNow(intervalMs: number) {
  const [now, setNow] = useState(() => Date.now())
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), intervalMs)
    return () => clearInterval(t)
  }, [intervalMs])
  return now
}

function siteOf(s: Pick<PlannedShift, 'work_site' | 'warehouse_name'>): string {
  return s.work_site === 'warehouse' && s.warehouse_name ? s.warehouse_name : WORK_SITE_LABELS[s.work_site]
}

type Tone = 'success' | 'warning' | 'neutral'

const PILL_TONE: Record<Tone, string> = {
  success: 'bg-success-subtle text-success-text',
  warning: 'bg-warning-subtle text-warning-text',
  neutral: 'bg-subtle text-ink-secondary',
}

const LOC_ICON_TONE: Record<Tone, string> = {
  success: 'text-success',
  warning: 'text-warning',
  neutral: 'text-ink-tertiary',
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
  /** הכשל של ההחתמה האחרונה — נשאר מתחת לכפתור עם "נסה שוב", ולא נעלם בטוסט */
  const [punchError, setPunchError] = useState<string | null>(null)
  const { data: status, isLoading, error: statusError, refetch: refetchStatus } = useMyClockStatus()
  const [note, setNote] = useState('')
  const [showNoteInput, setShowNoteInput] = useState(false)
  const [showLocInfo, setShowLocInfo] = useState(false)
  const [reporting, setReporting] = useState(false)
  /** ההחתמה שעליה נפתחה בקשת תיקון, או null כשהמודאל סגור (0165) */
  const [correcting, setCorrecting] = useState<AttendanceEntry | null>(null)

  const open = status?.open_entry ?? null
  const shift = status?.shift ?? null
  const rules = status?.rules
  /**
   * מה שהשרת יבקש, ולא מה שההגדרה אומרת.
   *
   * ‏`requires_location` הוא הכלל שנקבע לעובד; `location_required` הוא
   * התשובה למקרה הזה — הוא כבוי כשלמשמרת אין נקודת ייחוס כלל (מיקום שהוקלד
   * ידנית בלי קואורדינטות, 0159). לבקש GPS שם היה מעכב את ההחתמה, ולפעמים
   * מונע אותה לגמרי — מרתף בלי קליטה, הרשאת מיקום שנחסמה פעם — בשביל ערך
   * שהשרת ישליך ממילא.
   *
   * הנפילה חזרה ל-`requires_location` היא בשביל תשובה ישנה שנענתה מהמטמון
   * של ה-service worker: מוטב לבקש מיקום שלא היה נדרש מאשר לשלוח בלעדיו
   * ולהידחות.
   */
  const needsLocation = status?.location_required ?? !!rules?.requires_location
  const locationWaived = !!rules?.requires_location && !needsLocation
  const today = status?.today ?? []
  const reports = status?.reports ?? []
  const canSubmit =
    !!status?.can_submit && has(PERM.ATTENDANCE_SUBMIT_ENTRY) && rules?.self_entry?.enabled !== false
  /**
   * בקשת תיקון שעות (0165). השרת הוא שמכריע — `can_request_correction` נגזר
   * שם מהמפתח — והבדיקה בצד הלקוח היא רק כדי לא לצייר כפתור שייפול.
   */
  const canCorrect = !!status?.can_request_correction && has(PERM.ATTENDANCE_REQUEST_CORRECTION)
  const corrections = status?.corrections ?? []
  /**
   * השער של הכניסה (0168). השרת מכריע — אותה `app.clock_in_gate` שההחתמה
   * עצמה עוברת דרכה — והמסך רק מצייר לפיה. הנפילה ל"פתוח" היא בשביל תשובה
   * ישנה שנענתה מהמטמון של ה-service worker: מוטב כפתור שנלחץ ונדחה מאשר
   * כפתור שנעול בטעות ואינו מסביר דבר.
   */
  const clockBlock = status?.clock_in_block ?? null
  const blocked = !open && !!clockBlock && status?.can_clock_in === false
  const canClock = has(PERM.ATTENDANCE_CLOCK)

  const now = useNow(open || shift ? 1000 : 30_000)

  /* רשימת ההחתמות של היום. `today` מגיע מהשרת לפי `work_date`, ומשמרת
     שנפתחה אתמול בלילה ועדיין פתוחה אינה בתוכו — היא בדיוק זו שחסרה לה
     שעת סיום, ולכן היא חייבת להופיע. */
  const allToday = open ? [open, ...today.filter((t) => t.id !== open.id)] : today
  const historyEntries = [...allToday].sort(
    (a, b) => new Date(a.clock_in_at).getTime() - new Date(b.clock_in_at).getTime(),
  )
  const earliestIn = historyEntries[0]?.clock_in_at ?? null

  /* בזמן משמרת פתוחה: מה שכבר נסגר היום ועוד הזמן שרץ — ולא רק הקטע הפתוח */
  const closedHours = today
    .filter((e) => e.clock_out_at && e.id !== open?.id)
    .reduce((a, e) => a + (e.actual_hours ?? 0), 0)
  const workedMin = closedHours * 60 + (open ? Math.max(0, minutesBetween(open.clock_in_at, now)) : 0)

  /* החלון המתוכנן: בזמן משמרת פתוחה — מה שנצרב על הרשומה בכניסה; אם אין
     בה כזה, המשמרת של עכשיו רק כשהיא באמת מכסה את הרגע הזה. */
  const nowCovered = !!shift && now >= Date.parse(shift.shift_start) && now <= Date.parse(shift.shift_end)
  const plan = open
    ? open.shift_start && open.shift_end
      ? { start: open.shift_start, end: open.shift_end, hours: open.planned_hours }
      : shift && nowCovered
        ? { start: shift.shift_start, end: shift.shift_end, hours: shift.planned_hours }
        : null
    : shift
      ? { start: shift.shift_start, end: shift.shift_end, hours: shift.planned_hours }
      : null
  const plannedMin = plan ? (plan.hours != null ? plan.hours * 60 : minutesBetween(plan.start, plan.end)) : 0
  const shiftIsToday = !!shift && dayLabel(shift.shift_start, new Date(now)) === 'היום'
  const shiftUpcoming = !!shift && Date.parse(shift.shift_start) > now
  const startsInMin = shift && shiftUpcoming && shiftIsToday ? minutesBetween(now, shift.shift_start) : null

  const fullName = me?.profile?.full_name ?? ''
  const where = shift ? [shift.label, siteOf(shift)].filter(Boolean).join(' · ') : 'אין משמרת מתוכננת'

  const mode: 'in' | 'out' | 'locked' = open ? 'in' : blocked || !canClock ? 'locked' : 'out'

  /* ===== שבב המיקום — נגזר ממה שכבר ידוע, בלי לבקש GPS לפני ההחתמה ===== */
  let loc: { text: string; tone: Tone; info: string } | null = null
  if (open && open.clock_in_distance_m != null) {
    const d = open.clock_in_distance_m
    const inside = rules?.location_radius_m == null || d <= rules.location_radius_m
    loc = inside
      ? { text: `באתר · ${fmtDistance(d)}`, tone: 'success', info: `המיקום אומת בכניסה: ${fmtDistance(d)} מנקודת הייחוס` }
      : { text: 'מחוץ לאתר', tone: 'warning', info: `בכניסה נמדדו ${fmtDistance(d)} מנקודת הייחוס` }
  } else if (needsLocation) {
    loc = {
      text: `מיקום נדרש · ${fmtDistance(rules?.location_radius_m)}`,
      tone: 'neutral',
      info: `נדרש שיתוף מיקום להחתמה (${fmtDistance(rules?.location_radius_m)} מהאתר)`,
    }
  } else if (locationWaived) {
    /* אין נקודת ייחוס — ולכן ההסבר, ולא שקט. עובד שרגיל שהשעון מבקש
       ממנו מיקום צריך לדעת למה הפעם לא, ושהשעות עדיין קובעות. */
    loc = {
      text: 'ללא אימות מיקום',
      tone: 'neutral',
      info: 'לא הוגדרו קואורדינטות לאתר — אפשר להחתים מכל מקום, לפי שעות המשמרת',
    }
  }

  /* ===== הטבעת ===== */
  let ring: {
    label: string
    big: string | null
    sub: string
    pill: { text: string; tone: Tone } | null
    arcs: { base: number; over: number }
  }
  if (mode === 'in') {
    const ot = plan ? overtimeState(now, plan.end) : null
    ring = {
      label: 'במשמרת',
      big: fmtHM(workedMin),
      sub: plannedMin > 0 ? `שעות · מתוך ${fmtHM(plannedMin)}` : 'שעות היום',
      pill: ot
        ? {
            text: ot.kind === 'until' ? `שעה נוספת בעוד ${fmtHM(ot.minutes)}` : `שעות נוספות ${fmtHM(ot.minutes)}`,
            tone: 'warning',
          }
        : null,
      arcs: ringArcs(workedMin, plannedMin, ot?.kind === 'over' ? ot.minutes : 0),
    }
  } else if (mode === 'out') {
    ring = {
      label: 'מחוץ לעבודה',
      big: startsInMin != null ? fmtHM(Math.ceil(startsInMin)) : fmtHM(workedMin),
      sub: startsInMin != null ? 'עד תחילת המשמרת' : 'שעות היום',
      pill: shift
        ? shiftIsToday
          ? { text: `מתוכנן ${fmtShiftRange(shift.shift_start, shift.shift_end)}`, tone: 'neutral' }
          : { text: `הבאה: ${dayLabel(shift.shift_start, new Date(now))} ${clockTime(shift.shift_start)}`, tone: 'neutral' }
        : null,
      arcs: shiftIsToday ? ringArcs(workedMin, plannedMin) : { base: 0, over: 0 },
    }
  } else {
    /* ‏0168: הכפתור נעול, ולכן המסך חייב להגיד למה — ההודעה מגיעה מהשרת,
       ולכן היא בדיוק זו שההחתמה עצמה הייתה מחזירה אילו נלחצה. */
    ring = {
      label: 'נעול',
      big: null,
      sub: blocked && clockBlock ? clockBlock.message : 'אין הרשאה להחתים',
      pill:
        shift && shiftUpcoming
          ? {
              text: `הבאה: ${dayLabel(shift.shift_start, new Date(now))} ${clockTime(shift.shift_start)} · ${siteOf(shift)}`,
              tone: 'warning',
            }
          : null,
      arcs: { base: 0, over: 0 },
    }
  }

  /* ===== האריחים — רק מה שכבר נטען ===== */
  const tiles: { l: string; v: string }[] = []
  if (mode === 'in') {
    tiles.push({ l: 'כניסה', v: clockTime(earliestIn) })
    if (plan) tiles.push({ l: 'מתוכנן עד', v: clockTime(plan.end) })
  } else if (mode === 'out') {
    if (shift) {
      const suffix = shiftIsToday ? '' : ` · ${dayLabel(shift.shift_start, new Date(now))}`
      tiles.push({ l: `מתחילה${suffix}`, v: clockTime(shift.shift_start) })
      tiles.push({ l: 'מסתיימת', v: clockTime(shift.shift_end) })
    }
    if (startsInMin != null && workedMin > 0) tiles.push({ l: 'היום', v: fmtHM(workedMin) })
  } else {
    tiles.push({ l: 'היום', v: workedMin > 0 ? fmtHM(workedMin) : '—' })
    if (shift && shiftUpcoming) {
      const d = dayLabel(shift.shift_start, new Date(now))
      tiles.push({ l: d === 'היום' ? 'הבאה' : d, v: clockTime(shift.shift_start) })
    }
  }

  const punch = useMutation({
    mutationFn: async (kind: 'in' | 'out') => {
      let lat: number | null = null
      let lng: number | null = null
      let accuracy: number | null = null

      /**
       * הנקודה נדגמת בכל החתמה, גם כשאין מול מה לאמת אותה (0166): המנהל
       * צריך לדעת *מאיפה* הוחתם, ולא רק כמה רחוק מהאתר. מה שנשמר מ-0159 הוא
       * מי חוסם את מי — כשהמיקום נדרש, קריאה שנכשלה עוצרת את ההחתמה
       * ומסבירה למה; כשהוא אינו נדרש, הקריאה רכה וההחתמה נכנסת בלעדיה.
       */
      const reading = await getPosition({ soft: !needsLocation })
      if (reading.status === 'ok') {
        lat = reading.lat
        lng = reading.lng
        accuracy = reading.accuracy
      } else if (needsLocation) {
        throw new Error(GEO_MESSAGES[reading.status])
      }

      const { data, error } = await supabase.rpc(
        kind === 'in' ? 'attendance_clock_in' : 'attendance_clock_out',
        { p_lat: lat, p_lng: lng, p_accuracy: accuracy, p_note: note || null },
      )
      if (error) throw error
      return data as { distance_m: number | null }
    },
    onSuccess: async (data, kind) => {
      setNote('')
      setShowNoteInput(false)
      setPunchError(null)
      invalidate()
      /* הכפתור נשאר בטעינה עד שהסטטוס החדש חזר — אחרת הוא עוד אומר "כניסה"
         לרגע, ולחיצה שנייה נדחית בשרת ב"כבר נרשמה כניסה" */
      await refetchStatus()
      if (typeof navigator !== 'undefined' && 'vibrate' in navigator) navigator.vibrate?.(40)
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
        setPunchError('אין חיבור לרשת — ההחתמה לא נקלטה. כשהקליטה תחזור אפשר להחתים שוב.')
        return
      }
      setPunchError(errorMessage(e))
    },
  })

  /**
   * ההחזקה היא האישור: יציאה מסיימת את המשמרת וביטול שלה הוא בקשת תיקון
   * לאישור מנהל, ולכן לחיצה קצרה לא עושה דבר — במקום דיאלוג "בטוח?".
   */
  const doPunch = () => {
    setPunchError(null)
    punch.mutate(open ? 'out' : 'in')
  }
  const buttonDisabled = punch.isPending || !canClock || blocked
  const hold = useHoldToConfirm({ onConfirm: doPunch, disabled: buttonDisabled })

  if (isLoading) {
    return (
      <div className="mx-auto max-w-md space-y-4 px-4 py-6">
        <Skeleton className="h-12 w-full rounded-2xl" />
        <Skeleton className="mx-auto h-64 w-64 rounded-full" />
        <Skeleton className="h-16 w-full rounded-2xl" />
        <Skeleton className="h-[62px] w-full rounded-[20px]" />
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

  const buttonText =
    mode === 'in' ? 'החזיקו ליציאה' : mode === 'out' ? 'החזיקו לכניסה' : canClock ? 'אין משמרת פעילה' : 'אין הרשאה להחתים'
  const hint =
    mode === 'in'
      ? 'החזקה של שנייה מונעת יציאה בטעות'
      : mode === 'out'
        ? 'החזקה של שנייה מונעת החתמה בטעות'
        : canSubmit
          ? 'עבדת ולא הוחתם? "שכחתי להחתים" למטה'
          : null

  return (
    <div className="mx-auto flex min-h-full max-w-md flex-col gap-4 px-4 pt-4 text-ink">
      {/* ===== כותרת: מי, מתי, איפה ===== */}
      <header className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h1 className="truncate text-xl font-bold">{fullName || 'השעון שלי'}</h1>
          <p className="line-clamp-2 text-[13px] text-ink-tertiary">
            {headerDate(new Date(now))} · {where}
          </p>
        </div>
        {loc && (
          <button
            type="button"
            onClick={() => setShowLocInfo((v) => !v)}
            aria-expanded={showLocInfo}
            title={loc.info}
            className="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-line px-2.5 py-1.5 text-xs text-ink-secondary transition-colors hover:bg-hover"
          >
            <MapPin size={13} strokeWidth={2.2} className={LOC_ICON_TONE[loc.tone]} aria-hidden />
            {loc.text}
          </button>
        )}
      </header>
      {loc && showLocInfo && (
        <p className="-mt-2 rounded-xl bg-subtle px-3 py-2 text-xs text-ink-secondary">{loc.info}</p>
      )}

      {/* ===== הטבעת ===== */}
      <ClockRing arcs={ring.arcs} dashedTrack={mode === 'locked'}>
        <div className="text-[13px] tracking-wide text-ink-tertiary">{ring.label}</div>
        {ring.big != null ? (
          <div className="text-[58px] leading-none font-extrabold tabular-nums" dir="ltr">
            {ring.big}
          </div>
        ) : (
          <Lock size={54} strokeWidth={1.6} className="text-ink-tertiary" aria-hidden />
        )}
        <div className="max-w-[190px] text-center text-[13px] text-ink-tertiary tabular-nums">{ring.sub}</div>
        {ring.pill && (
          <span
            className={cx(
              'mt-2 max-w-[200px] rounded-full px-2.5 py-1 text-center text-xs font-semibold tabular-nums',
              PILL_TONE[ring.pill.tone],
            )}
          >
            {ring.pill.text}
          </span>
        )}
      </ClockRing>

      {/* ===== אריחים ===== */}
      {tiles.length > 0 && (
        <div className={cx('grid gap-2', tiles.length === 3 ? 'grid-cols-3' : tiles.length === 2 ? 'grid-cols-2' : 'grid-cols-1')}>
          {tiles.map((s) => (
            <div
              key={s.l}
              className="flex flex-col items-center gap-0.5 rounded-2xl border border-line-subtle bg-surface px-2 py-2.5"
            >
              <div className="text-xs text-ink-tertiary">{s.l}</div>
              <div className="text-[17px] font-bold tabular-nums">{s.v}</div>
            </div>
          ))}
        </div>
      )}

      {/* ===== הכפתור: החזקה של שנייה ===== */}
      <div className="flex flex-col gap-2">
        <button
          type="button"
          disabled={buttonDisabled}
          aria-label={
            mode === 'in'
              ? 'יציאה מהמשמרת — החזיקו את הכפתור לחוץ כשנייה כדי לאשר'
              : mode === 'out'
                ? 'כניסה למשמרת — החזיקו את הכפתור לחוץ כשנייה כדי לאשר'
                : buttonText
          }
          aria-describedby={hint ? 'clock-hold-hint' : undefined}
          aria-busy={punch.isPending || undefined}
          {...hold.bind}
          className={cx(
            'relative isolate flex h-[62px] w-full touch-manipulation items-center justify-center overflow-hidden rounded-[20px] text-lg font-extrabold select-none [-webkit-touch-callout:none]',
            'transition-transform duration-150 focus-visible:ring-4 focus-visible:ring-[var(--vl-focus-ring)] focus-visible:outline-none',
            mode === 'in' && 'bg-ink text-ink-inverse',
            mode === 'out' && 'bg-success text-ink-inverse',
            mode === 'locked' && 'cursor-not-allowed bg-subtle text-ink-tertiary',
            mode !== 'locked' && !punch.isPending && 'cursor-pointer',
            hold.holding && 'scale-[0.985]',
            punch.isPending && 'cursor-wait',
          )}
        >
          {/* המילוי — מתקדם לאורך זמן ההחזקה ונעלם מיד בשחרור */}
          {mode !== 'locked' && (
            <span
              aria-hidden
              className={cx(
                'absolute inset-y-0 start-0 -z-10',
                mode === 'in' ? 'bg-error/35' : 'bg-ink-inverse/25',
              )}
              style={{
                width: hold.holding ? '100%' : '0%',
                transition: hold.holding ? `width ${hold.duration}ms linear` : 'width 150ms ease-out',
              }}
            />
          )}
          <span className="flex items-center gap-2.5">
            {punch.isPending ? (
              <Loader2 size={20} className="animate-spin" aria-hidden />
            ) : mode === 'in' ? (
              <span aria-hidden className="size-3 rounded-[3px] bg-error" />
            ) : mode === 'out' ? (
              <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
                <path d="M17 5v14L6 12z" />
              </svg>
            ) : null}
            {buttonText}
          </span>
        </button>
        {hint && (
          <div id="clock-hold-hint" className="text-center text-xs text-ink-tertiary">
            {hint}
          </div>
        )}

        {punchError && !punch.isPending && (
          <div
            role="alert"
            className="flex items-start gap-2 rounded-2xl border border-error-border bg-error-subtle px-3 py-2.5 text-sm text-error-text"
          >
            <AlertTriangle size={ICON.sm} strokeWidth={STROKE} className="mt-0.5 shrink-0" />
            <span className="flex-1 font-semibold">{punchError}</span>
            {/* ההחזקה כבר נעשתה; הניסיון החוזר הוא אותה החלטה */}
            <Button size="sm" variant="primary" onClick={doPunch}>
              נסה שוב
            </Button>
          </div>
        )}
      </div>

      {/* ===== "היום" — גיליון תחתון ===== */}
      <section className="mt-auto -mx-4 flex flex-col gap-2.5 rounded-t-3xl border border-b-0 border-line-subtle bg-surface px-5 pt-2.5 pb-5">
        <div aria-hidden className="h-1 w-10 self-center rounded-full bg-line" />
        <div className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1">
          <h2 className="text-[15px] font-bold">היום</h2>
          <div className="flex items-center gap-3.5 text-[13px]">
            <button
              type="button"
              onClick={() => setShowNoteInput((v) => !v)}
              aria-expanded={showNoteInput}
              className="text-primary-text hover:underline"
            >
              הערה{note && !showNoteInput ? ' •' : ''}
            </button>
            {/* דיווח משמרת שלא הוחתמה — מקום אחד במסך, באותם תנאים כמו קודם */}
            {canSubmit && !open && (
              <button type="button" onClick={() => setReporting(true)} className="text-primary-text hover:underline">
                שכחתי להחתים
              </button>
            )}
            {/* החודש כולו — שעות, ש״נ, היעדרויות ושכר — נמצא בדוח */}
            <Link to="/attendance" className="text-primary-text hover:underline">
              הדוח שלי
            </Link>
          </div>
        </div>

        {showNoteInput ? (
          <div className="flex items-center gap-2">
            <Input
              inputSize="sm"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="הערה להחתמה..."
              autoFocus
              className="flex-1"
            />
            <Button size="sm" variant="ghost" onClick={() => setShowNoteInput(false)}>
              סגור
            </Button>
          </div>
        ) : (
          note && <p className="truncate text-xs text-ink-tertiary">הערה להחתמה: {note}</p>
        )}

        {historyEntries.length === 0 ? (
          <p className="text-sm text-ink-tertiary">טרם הוחתם היום</p>
        ) : (
          <ul className="flex flex-col">
            {historyEntries.map((e) => (
              <PunchRows
                key={e.id}
                entry={e}
                radius={rules?.location_radius_m ?? null}
                canCorrect={canCorrect}
                onCorrect={() => setCorrecting(e)}
                now={now}
              />
            ))}
          </ul>
        )}

        {(reports.length > 0 || corrections.length > 0) && (
          <PendingItems reports={reports} corrections={corrections} />
        )}
      </section>

      {/* מודאל דיווח ידני */}
      {reporting && <SelfReportModal status={status} onClose={() => setReporting(false)} />}
      {/* ומודאל בקשת התיקון, על ההחתמה שנבחרה */}
      {correcting && <CorrectionModal entry={correcting} onClose={() => setCorrecting(null)} />}
    </div>
  )
}

/** טבעת ההתקדמות: מסלול, קשת בצבע ההצלחה, והחלק שאחרי הסוף המתוכנן בענבר */
function ClockRing({
  arcs,
  dashedTrack,
  children,
}: {
  arcs: { base: number; over: number }
  dashedTrack?: boolean
  children: React.ReactNode
}) {
  const r = 116
  const c = 2 * Math.PI * r
  const dash = (f: number) => `${(c * f).toFixed(1)} ${c.toFixed(1)}`
  return (
    <div className="relative size-[264px] shrink-0 self-center">
      {/* scaleX(-1) rotate(-90deg): מתחיל למעלה ומתקדם עם כיוון הקריאה (RTL) */}
      <svg
        width="264"
        height="264"
        viewBox="0 0 264 264"
        aria-hidden
        className="absolute inset-0"
        style={{ transform: 'scaleX(-1) rotate(-90deg)' }}
      >
        <circle
          cx="132"
          cy="132"
          r={r}
          fill="none"
          strokeWidth="14"
          className="stroke-line"
          strokeDasharray={dashedTrack ? '3 10' : undefined}
        />
        {arcs.base > 0 && (
          <circle
            cx="132"
            cy="132"
            r={r}
            fill="none"
            strokeWidth="14"
            strokeLinecap="round"
            className="stroke-success transition-[stroke-dasharray] duration-500"
            strokeDasharray={dash(arcs.base)}
          />
        )}
        {arcs.over > 0 && (
          <circle
            cx="132"
            cy="132"
            r={r}
            fill="none"
            strokeWidth="14"
            className="stroke-warning"
            strokeDasharray={dash(arcs.over)}
            strokeDashoffset={(-c * arcs.base).toFixed(1)}
          />
        )}
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center gap-1">{children}</div>
    </div>
  )
}

/**
 * ההחתמות של משמרת אחת כשורות: כניסה, ואז יציאה או "משמרת פתוחה".
 * העיפרון יושב על שורת הכניסה — בקשת התיקון היא על הרשומה כולה (0165).
 */
function PunchRows({
  entry: e,
  radius,
  canCorrect,
  onCorrect,
  now,
}: {
  entry: AttendanceEntry
  radius: number | null
  canCorrect: boolean
  onCorrect: () => void
  now: number
}) {
  /* משמרת שנפתחה אתמול בלילה נושאת את התאריך שלה */
  const stamp = (iso: string) => {
    const t = clockTime(iso)
    return dayLabel(iso, new Date(now)) === 'היום' ? t : `${t} (${shortDate(iso)})`
  }
  const where = (d: number | null, place: string | null) =>
    d != null ? (radius == null || d <= radius ? 'מיקום אומת' : `${fmtDistance(d)} מהאתר`) : (place ?? '')

  const row = (
    key: string,
    dot: 'filled' | 'muted' | 'hollow',
    label: React.ReactNode,
    sub: string,
    value: string,
    action?: React.ReactNode,
  ) => (
    <li key={key} className="flex min-h-9 items-center gap-2.5 py-0.5 text-sm">
      <span
        aria-hidden
        className={cx(
          'size-[9px] shrink-0 rounded-full border-2',
          dot === 'filled' && 'border-success bg-success',
          dot === 'muted' && 'border-ink-tertiary bg-ink-tertiary',
          dot === 'hollow' && 'border-success bg-transparent',
        )}
      />
      <span className="min-w-0 flex-1">
        {label} {sub && <span className="text-xs text-ink-tertiary">{sub}</span>}
      </span>
      <span className="font-semibold tabular-nums" dir="ltr">
        {value}
      </span>
      <span className="flex w-8 shrink-0 justify-center">{action}</span>
    </li>
  )

  return (
    <>
      {row(
        `${e.id}-in`,
        'filled',
        <>
          כניסה
          {e.flags.map((f) => (
            <Badge key={f} tone="warning" className="ms-1.5">
              {flagLabel(f)}
            </Badge>
          ))}
        </>,
        where(e.clock_in_distance_m, e.clock_in_place),
        stamp(e.clock_in_at),
        /* ‏0165: תיקון השעה מתחיל כאן, על ההחתמה עצמה. משמרת שכבר יש עליה
           בקשה פתוחה מציגה אותה במקום הכפתור, כדי שלא תישלח פעמיים. */
        e.req_at ? null : canCorrect ? (
          <IconButton label="בקשת תיקון שעות" size="sm" onClick={onCorrect}>
            <PencilLine size={ICON.sm} strokeWidth={STROKE} />
          </IconButton>
        ) : null,
      )}
      {e.req_at && (
        <li className="ps-5 pb-1">
          <Badge tone="warning">בקשת תיקון נשלחה</Badge>
        </li>
      )}
      {e.clock_out_at
        ? row(
            `${e.id}-out`,
            'muted',
            'יציאה',
            [`${fmtDuration(e.actual_hours)} ש׳`, where(e.clock_out_distance_m, e.clock_out_place)]
              .filter(Boolean)
              .join(' · '),
            stamp(e.clock_out_at),
          )
        : row(`${e.id}-open`, 'hollow', 'משמרת פתוחה', '', '—')}
    </>
  )
}

/**
 * מה שממתין להכרעה: דיווחים ידניים (ממתינים או נדחו) ובקשות תיקון שעות.
 * שורה ענברית אחת לכל פריט, ונפתחת במקום לפרטים ולביטול.
 *
 * בקשת תיקון אינה "דיווח": המשמרת עצמה קיימת ונספרת, ומה שממתין הוא רק
 * השינוי בשעות שלה — ולכן הנוסח שונה.
 */
function PendingItems({ reports, corrections }: { reports: AttendanceEntry[]; corrections: AttendanceEntry[] }) {
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const invalidate = useAttendanceInvalidate()
  const cancel = useCancelCorrection()
  /* התראת "הדיווח שלך אושר/נדחה" מובילה לכאן עם ?entry=. אין מגירה לפתוח
     במסך הזה, ולכן הסימון הוא פתיחת השורה, גלילה והבזק. */
  const [params] = useSearchParams()
  const entryParam = params.get('entry')
  const highlightRef = useDeepLinkHighlight(entryParam, reports.length > 0)
  const [expanded, setExpanded] = useState<string | null>(() => (entryParam ? `r:${entryParam}` : null))

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

  const items = [
    ...reports.map((e) => ({ key: `r:${e.id}`, kind: 'report' as const, e })),
    ...corrections.map((e) => ({ key: `c:${e.id}`, kind: 'correction' as const, e })),
  ]

  return (
    <>
      <ul className="flex flex-col gap-1.5">
        {items.map(({ key, kind, e }) => {
          const isOpen = expanded === key
          const rejected = kind === 'report' && e.status === 'rejected'
          const summary =
            kind === 'correction'
              ? `בקשת תיקון ל־${shortDate(e.work_date)} ממתינה לאישור`
              : `דיווח משמרת ל־${shortDate(e.work_date)} ${e.status === 'pending' ? 'ממתין לאישור' : STATUS_LABELS[e.status]}`
          const highlighted = kind === 'report' && e.id === entryParam
          return (
            <li
              key={key}
              ref={highlighted ? (highlightRef as React.Ref<HTMLLIElement>) : undefined}
              className={cx(
                'rounded-xl text-[13px]',
                rejected ? 'bg-error-subtle text-error-text' : 'bg-warning-subtle text-warning-text',
                highlighted && HIGHLIGHT_CLASS,
              )}
            >
              <button
                type="button"
                onClick={() => setExpanded(isOpen ? null : key)}
                aria-expanded={isOpen}
                className="flex w-full items-center gap-2 px-3 py-2 text-start"
              >
                <span
                  aria-hidden
                  className={cx(
                    'inline-flex size-5 shrink-0 items-center justify-center rounded-full text-ink-inverse',
                    rejected ? 'bg-error' : 'bg-warning',
                  )}
                >
                  {kind === 'correction' ? <PencilLine size={11} strokeWidth={2.4} /> : <CalendarClock size={11} strokeWidth={2.4} />}
                </span>
                <span className="flex-1">{summary}</span>
                {isOpen ? <ChevronUp size={14} aria-hidden /> : <ChevronDown size={14} aria-hidden />}
              </button>
              {isOpen && (
                <div className="flex flex-wrap items-center gap-2 border-t border-current/10 px-3 py-2 text-xs text-ink-secondary">
                  <span className="font-medium">{fmtDate(e.work_date)}</span>
                  {kind === 'report' ? (
                    <>
                      <span className="font-mono tabular-nums" dir="ltr">
                        {fmtShiftRange(e.clock_in_at, e.clock_out_at)}
                      </span>
                      <span>{fmtDuration(e.actual_hours)} ש׳</span>
                      <Badge tone={STATUS_TONES[e.status]}>{STATUS_LABELS[e.status]}</Badge>
                      {e.status === 'rejected' && e.manager_note && (
                        <span className="text-ink-tertiary">{e.manager_note}</span>
                      )}
                    </>
                  ) : (
                    <>
                      {/* מה שביקשתי, מול מה שרשום */}
                      <span className="font-mono text-ink-tertiary tabular-nums line-through" dir="ltr">
                        {fmtShiftRange(e.clock_in_at, e.clock_out_at) || '—'}
                      </span>
                      <span className="font-mono font-semibold text-ink tabular-nums" dir="ltr">
                        {fmtShiftRange(e.req_clock_in_at, e.req_clock_out_at ?? e.clock_out_at) || '—'}
                      </span>
                      {e.req_note && <span className="text-ink-tertiary">{e.req_note}</span>}
                    </>
                  )}
                  <span className="flex-1" />
                  {kind === 'report' && e.status === 'pending' && (
                    <IconButton
                      label="ביטול הדיווח"
                      size="sm"
                      disabled={withdraw.isPending}
                      onClick={async () => {
                        if (await confirm('לבטל את הדיווח?', { tone: 'danger' })) withdraw.mutate(e.id)
                      }}
                    >
                      <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                    </IconButton>
                  )}
                  {kind === 'correction' && (
                    <IconButton
                      label="ביטול הבקשה"
                      size="sm"
                      disabled={cancel.isPending}
                      onClick={async () => {
                        if (await confirm('לבטל את בקשת התיקון?', { tone: 'danger' })) {
                          cancel.mutate(e.id, {
                            onSuccess: () => toast.success('הבקשה בוטלה'),
                            onError: (err) => toast.error(errorMessage(err)),
                          })
                        }
                      }}
                    >
                      <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                    </IconButton>
                  )}
                </div>
              )}
            </li>
          )
        })}
      </ul>
      {dialog}
    </>
  )
}

/**
 * בקשת תיקון על החתמה קיימת.
 *
 * שני מקרים באותו טופס: שעה שהוחתמה בזמן הלא נכון, ומשמרת שאין לה שעת סיום
 * כלל. השני הוא הסיבה ששדה הסיום אינו חובה כאן — להבדיל מדיווח משמרת שלא
 * הוחתמה, שם הוא חובה כי הוא מתאר משמרת שהסתיימה. השארתו ריק על משמרת
 * פתוחה משאירה אותה פתוחה, וזה מה שההסבר מתחתיו אומר.
 */
function CorrectionModal({ entry, onClose }: { entry: AttendanceEntry; onClose: () => void }) {
  const toast = useToast()
  const request = useRequestCorrection()
  const isOpenShift = !entry.clock_out_at

  const [form, setForm] = useState(() => ({
    clockIn: toLocalInput(entry.clock_in_at),
    clockOut: toLocalInput(entry.clock_out_at),
    note: '',
  }))

  const save = () => {
    if (!form.clockIn) {
      toast.error('חובה להזין שעת כניסה')
      return
    }
    if (!form.note.trim()) {
      toast.error('חובה לכתוב למה השעה צריכה להשתנות')
      return
    }
    request.mutate(
      { id: entry.id, clockIn: form.clockIn, clockOut: form.clockOut || null, note: form.note },
      {
        onSuccess: () => {
          toast.success('הבקשה נשלחה לאישור', {
            description: 'השעות ישתנו רק אחרי שמנהל יאשר',
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
      title="בקשת תיקון שעות"
      footer={
        <>
          <Button onClick={onClose}>ביטול</Button>
          <Button variant="primary" loading={request.isPending} onClick={save}>
            שליחה לאישור
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <p className="rounded-lg border border-line-subtle bg-subtle/50 px-3 py-2 type-caption text-ink-secondary">
          השעות הרשומות אינן משתנות עד שמנהל יאשר, ובקשה שתידחה פשוט תימחק — המשמרת תישאר כפי שהיא.
        </p>
        <div className="rounded-lg border border-line-subtle px-3 py-2 type-caption text-ink-secondary">
          <span className="type-overline">רשום כרגע</span>
          <p className="mt-0.5 tabular-nums text-ink" dir="ltr">
            {fmtShiftRange(entry.clock_in_at, entry.clock_out_at) || '—'}
          </p>
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="כניסה" required>
            <Input
              data-autofocus
              type="datetime-local"
              dir="ltr"
              value={form.clockIn}
              onChange={(e) => setForm((f) => ({ ...f, clockIn: e.target.value }))}
            />
          </Field>
          <Field
            label="יציאה"
            hint={isOpenShift ? 'המשמרת פתוחה — כאן משלימים לה סוף' : 'ריק = משאיר את שעת היציאה כפי שהיא'}
          >
            <Input
              type="datetime-local"
              dir="ltr"
              value={form.clockOut}
              onChange={(e) => setForm((f) => ({ ...f, clockOut: e.target.value }))}
            />
          </Field>
        </div>
        <Field label="סיבה" required hint="זה מה שהמנהל יראה כשיכריע">
          <Textarea
            rows={2}
            value={form.note}
            placeholder="למשל: יצאתי מהמחסן ב-06:40 והחתמתי רק כשהגעתי לרכב"
            onChange={(e) => setForm((f) => ({ ...f, note: e.target.value }))}
          />
        </Field>
      </div>
    </Modal>
  )
}

function toLocalInput(iso: string | null | undefined): string {
  if (!iso) return ''
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
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
