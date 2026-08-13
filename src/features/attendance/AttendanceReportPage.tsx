import { useEffect, useMemo, useRef, useState } from 'react'
import type { ComponentType, ReactNode } from 'react'
import { useSearchParams } from 'react-router'
import { useMutation } from '@tanstack/react-query'
import {
  AlertCircle,
  Banknote,
  CalendarCheck,
  CalendarDays,
  Check,
  ChevronLeft,
  ChevronRight,
  Clock,
  Download,
  History,
  ICON,
  LayoutGrid,
  List,
  MapPin,
  PieChart,
  Plus,
  PlusCircle,
  STROKE,
  SlidersHorizontal,
  Timer,
  Wallet,
  XCircle,
} from '../../components/ui/icons'
import {
  Badge,
  Button,
  Card,
  Checkbox,
  DataTable,
  EmptyState,
  ErrorState,
  Field,
  IconButton,
  Input,
  Modal,
  MultiSelect,
  PageHeader,
  Select,
  SegmentedControl,
  SkeletonList,
  cx,
  useToast,
} from '../../components/ui'
import type { Column } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { useContractors, useStaff } from '../../lib/queries'
import { useIsPhone } from '../../lib/useMediaQuery'
import { fmtDate, fmtMoney, fmtTime, toISODate } from '../../lib/dates'
import { addMonths, endOfMonth, format, parseISO, startOfMonth, subMonths } from 'date-fns'
import { useAttendanceInvalidate, useAttendanceReport, useContractorStaff } from './attendanceQueries'
import { AttendanceEntryDrawer } from './AttendanceEntryDrawer'
import {
  STATUS_LABELS,
  STATUS_TONES,
  WORK_SITE_LABELS,
  flagLabel,
  fmtDuration,
  needsAttention,
  shiftShortfall,
  shiftTone,
  visibleFlags,
} from './shiftFormat'
import type { ShiftTone } from './shiftFormat'
import type { AttendanceReportRow, AttendanceStatus } from '../../types/domain'
import { errorMessage } from '../../lib/errors'

const HEBREW_MONTH_NAMES = [
  'ינואר',
  'פברואר',
  'מרץ',
  'אפריל',
  'מאי',
  'יוני',
  'יולי',
  'אוגוסט',
  'ספטמבר',
  'אוקטובר',
  'נובמבר',
  'דצמבר',
]

const HEBREW_DAY_LETTERS: Record<number, string> = {
  0: "א'",
  1: "ב'",
  2: "ג'",
  3: "ד'",
  4: "ה'",
  5: "ו'",
  6: "ש'",
}

/** '9:00'. השעה אינה מרופדת באפס — '0:00' ולא '00:00'. */
function fmtDurationHHMM(hours: number | null | undefined): string {
  if (hours == null || isNaN(hours) || hours <= 0) return '0:00'
  const totalMins = Math.round(hours * 60)
  return `${Math.floor(totalMins / 60)}:${String(totalMins % 60).padStart(2, '0')}`
}

interface ToneStyle {
  label: string
  Icon: ComponentType<{ size?: number; strokeWidth?: number }>
  /** הריבוע המסומל בקצה השורה */
  box: string
  /** התווית שמתחתיו, ושורת ההפרש כשהיא באותו טון */
  text: string
}

/**
 * טון אחד לכל מצב, במקום אחד, כדי שהסמל, התווית ושורת ההפרש לא יוכלו
 * לצבוע את אותה משמרת בשלושה צבעים.
 */
const SHIFT_TONE: Record<ShiftTone, ToneStyle> = {
  present: {
    label: 'נוכח',
    Icon: Check,
    box: 'border-success-border bg-success-subtle text-success',
    text: 'text-success-text',
  },
  overtime: {
    label: 'שעות נוספות',
    Icon: Clock,
    box: 'border-violet-200 bg-violet-50 text-violet-600 dark:border-violet-900 dark:bg-violet-950/60 dark:text-violet-300',
    text: 'text-violet-700 dark:text-violet-300',
  },
  short: {
    label: 'חסר',
    Icon: AlertCircle,
    box: 'border-error-border bg-error-subtle text-error',
    text: 'text-error-text',
  },
  pending: {
    label: 'ממתין',
    Icon: History,
    box: 'border-warning-border bg-warning-subtle text-warning',
    text: 'text-warning-text',
  },
  rejected: {
    label: 'נדחה',
    Icon: XCircle,
    box: 'border-error-border bg-error-subtle text-error',
    text: 'text-error-text',
  },
  open: {
    label: 'במשמרת',
    Icon: Timer,
    box: 'border-primary-border bg-primary-subtle text-primary',
    text: 'text-primary-text',
  },
}

/** שורה ברשימת הכרטיסים. תמיד משמרת שהייתה — אין שורות ליום ריק. */
interface ShiftRowView {
  key: string
  /** '23/05' */
  formattedDate: string
  hebrewDayLetter: string
  /** "משמרת 2" — רק ביום שיש בו יותר מאחת לאותו עובד */
  shiftLabel: string | null
  employeeName: string | null
  clockIn: string
  /** null במשמרת שעדיין פתוחה */
  clockOut: string | null
  /** אימות המיקום בהחתמה, לנקודה שליד שעת הכניסה */
  locationVerified: boolean
  location: string | null
  hoursText: string
  /** השורה שמתחת לסה"כ: הנוספות, החוסר, או מול מה נמדדה המשמרת */
  deltaText: string | null
  deltaTone: 'overtime' | 'short' | 'muted'
  /** הבונוס על המשמרת, או null כשאין או כשאין הרשאה לראות סכומים */
  bonus: number | null
  tone: ShiftTone
  row: AttendanceReportRow
  hours: number
}

/**
 * משמרת אחת לתצוגה. הכל נגזר מהשורה עצמה ולא ממצב המסך, ולכן זה יושב מחוץ
 * לרכיב.
 */
function toShiftView(r: AttendanceReportRow, sameDayCount: number): ShiftRowView {
  const day = parseISO(r.work_date)
  const clockIn = new Date(r.clock_in_at)
  const clockOut = r.clock_out_at ? new Date(r.clock_out_at) : null
  const overtime = r.pay?.overtime_hours ?? 0
  const planned = r.planned_hours ?? 0
  const actual = r.actual_hours ?? 0
  // משמרת פתוחה לא "חסרה" — היא פשוט עוד לא נגמרה, והשעות שחסרות בה ימלאו
  // את עצמן כשהעובד יחתים יציאה. מולה מוצג המתוכנן בלבד.
  const shortfall = clockOut ? shiftShortfall(planned, actual) : 0

  return {
    key: r.id,
    formattedDate: format(day, 'dd/MM'),
    hebrewDayLetter: HEBREW_DAY_LETTERS[day.getDay()],
    shiftLabel: sameDayCount > 1 ? `משמרת ${r.seq}` : null,
    employeeName: r.full_name,
    clockIn: fmtTime(clockIn.toTimeString()),
    clockOut: clockOut ? fmtTime(clockOut.toTimeString()) : null,
    locationVerified: !needsAttention(r.flags),
    location: r.work_site
      ? WORK_SITE_LABELS[r.work_site]
      : r.contractor_id
      ? 'מחסן ראשי'
      : 'מרכז לוגיסטי',
    hoursText: fmtDurationHHMM(actual),
    // בלי המילה "נוספות": הסמל שבקצה השורה כבר אומר אותה, וברוחב של טלפון
    // עמודת השעות מחזיקה מספר אחד ולא משפט.
    deltaText:
      overtime > 0
        ? `+${fmtDurationHHMM(overtime)}`
        : shortfall > 0
        ? `חסר ${fmtDurationHHMM(shortfall)}`
        : planned > 0
        ? `מתוך ${fmtDurationHHMM(planned)}`
        : null,
    deltaTone: overtime > 0 ? 'overtime' : shortfall > 0 ? 'short' : 'muted',
    bonus: r.pay?.bonus ? r.pay.bonus : null,
    tone: shiftTone(r),
    row: r,
    hours: actual,
  }
}

/** סיכום של עובד אחד בתוך דוח שיש בו כמה. */
interface EmployeeGroup {
  profileId: string
  name: string
  hours: number
  overtime: number
  bonus: number
  total: number | null
  shifts: ShiftRowView[]
}

export default function AttendanceReportPage() {
  return (
    <RequirePermission perm={PERM.ATTENDANCE_VIEW_OWN}>
      <AttendanceReport />
    </RequirePermission>
  )
}

/**
 * דוח נוכחות עובדים.
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
  const canPortal = has(PERM.PORTAL_ATTENDANCE)
  // מנהל רואה את כל הצוות, קבלן רואה רק את הסגל שלו — שתי הרשימות מציגות
  // מסנן "עובד" זהה בעיצובו, כל אחת מהמאגר שמותר לה.
  const showEmployeeFilter = canSeeAll || canPortal
  const canEdit = has(PERM.ATTENDANCE_EDIT_ENTRY)
  const canAdd = has(PERM.ATTENDANCE_MANUAL_ENTRY)
  const canApprove = has(PERM.ATTENDANCE_APPROVE_ENTRY)
  const canBonus = has(PERM.ATTENDANCE_MANAGE_BONUS)
  const canOpenRow = canEdit || canApprove || canBonus

  const toast = useToast()

  const [monthDate, setMonthDate] = useState(() => startOfMonth(new Date()))
  const [showFilters, setShowFilters] = useState(false)
  const [viewMode, setViewMode] = useState<'cards' | 'table'>('cards')

  /**
   * הטבלה היא מסך של מחשב.
   *
   * ‏DataTable היא שתים-עשרה עמודות שנקראות זו לצד זו; בטלפון היא מתקפלת
   * לגלילה אופקית שאיש לא מוצא, והכרטיסים כבר אומרים את אותו דבר בפריסה
   * שנבנתה לרוחב הזה. לכן המתג לא מוצג בטלפון — וגם לא נאכף רק בהסתרה שלו:
   * מי שבחר "טבלה" במחשב וצמצם את החלון חוזר לכרטיסים.
   */
  const isPhone = useIsPhone()
  const effectiveView = isPhone ? 'cards' : viewMode

  const from = useMemo(() => toISODate(startOfMonth(monthDate)), [monthDate])
  const to = useMemo(() => toISODate(endOfMonth(monthDate)), [monthDate])

  const [profileIds, setProfileIds] = useState<string[]>([])
  const [contractor, setContractor] = useState<string>('')
  const [onlyFlagged, setOnlyFlagged] = useState(false)
  const [status, setStatus] = useState<AttendanceStatus | ''>('')
  const [selected, setSelected] = useState<AttendanceReportRow | null>(null)
  const [adding, setAdding] = useState(false)

  // עובד שרואה רק את עצמו לא מקבל מסנן עובדים ולא מסנן קבלנים, ולכן גם לא
  // משלם על שתי השאילתות שממלאות אותם — profiles ו-contractors היו חוזרים
  // אצלו כמעט ריקים ממילא, כי ה-RLS חוסם את הרוב.
  const { data: staff = [] } = useStaff(canSeeAll || canAdd)
  const { data: contractors = [] } = useContractors(canSeeAll)
  const { data: contractorStaff = [] } = useContractorStaff()
  const employeeOptions = useMemo(
    () =>
      canSeeAll
        ? staff.map((p) => ({ id: p.id, label: p.full_name }))
        : contractorStaff.map((p) => ({ id: p.id, label: p.full_name })),
    [canSeeAll, staff, contractorStaff],
  )

  const { data, isLoading, error, refetch } = useAttendanceReport({
    from,
    to,
    profileIds,
    contractorId: contractorId ?? (contractor || null),
    onlyFlagged,
    status: status ? [status] : null,
  })

  /**
   * הייצוא הוא הסיבה היחידה ש-ExcelJS ייטען, ולכן הוא נטען רק בלחיצה —
   * אותו דפוס של ExcelDialog. הנתונים הם בדיוק מה שהמסך כבר קיבל, כדי
   * שהקובץ יסכים עם המסך גם כשמסננים.
   */
  const [exporting, setExporting] = useState(false)
  const runExport = async () => {
    if (!data) return
    setExporting(true)
    try {
      const { exportAttendanceReport } = await import('./exportAttendance')
      await exportAttendanceReport(data, { from, to })
    } catch (e) {
      toast.error(errorMessage(e))
    } finally {
      setExporting(false)
    }
  }

  const rows = data?.rows ?? []
  const totals = data?.totals
  const showMoney = !!data?.can_see_pay

  /**
   * נחיתה מהתראת "דיווח נוכחות ממתין".
   *
   * ‏app.notification_link (0054) שולח את שני הפרמטרים יחד: ?date= קובע את
   * החודש, ובלעדיו הדוח היה נפתח על החודש הנוכחי ושורה מלפני חודשיים לא הייתה
   * בין הנטענות כלל. ?entry= פותח את המגירה — היא מקבלת שורה מלאה ולא מזהה,
   * ולכן זה קורה רק אחרי שהשורות חזרו מהשרת.
   *
   * המשובץ בפורטל הקבלן חולק את הרכיב הזה אך לא את ה-URL שלו, ולכן הוא מוחרג.
   */
  const [params] = useSearchParams()
  const entryParam = embedded ? null : params.get('entry')
  const dateParam = embedded ? null : params.get('date')
  const openedEntry = useRef<string | null>(null)

  useEffect(() => {
    if (dateParam) setMonthDate(startOfMonth(parseISO(dateParam)))
  }, [dateParam])

  useEffect(() => {
    if (!entryParam || openedEntry.current === entryParam) return
    const row = data?.rows.find((r) => r.id === entryParam)
    if (!row) return
    openedEntry.current = entryParam
    setSelected(row)
  }, [entryParam, data])

  /**
   * שעות נוספות הן הגדרה פר-עובד (worker_pay_settings.overtime_enabled), והשרת
   * מוסר אותה על כל שורה. למי שהיא כבויה אצלו אין "00:00 שעות נוספות" — פשוט
   * אין לו את המושג הזה, ולכן העמודה, האריח והשורה נעלמים ולא מתאפסים. בדוח
   * של כמה עובדים די בכך שהיא חלה על אחד מהם.
   *
   * `!== false` ולא `=== true`: מול שרת שטרם קיבל את 0032 השדה פשוט חסר,
   * ואז ההתנהגות היא זו שהייתה — להציג — ולא להעלים בשקט טור שיש בו נתונים.
   */
  const showOvertime = useMemo(() => rows.some((r) => r.overtime_enabled !== false), [rows])

  /**
   * אותו כלל בדיוק על הבונוסים: מי שלא נתן בונוס החודש אינו מקבל אריח
   * ועמודה שכתוב בהם ₪0. `pay.bonus` מגיע רק למי שרשאי לראות סכומים.
   */
  const showBonus = useMemo(() => rows.some((r) => (r.pay?.bonus ?? 0) > 0), [rows])

  const handlePrevMonth = () => setMonthDate((d) => subMonths(d, 1))
  const handleNextMonth = () => setMonthDate((d) => addMonths(d, 1))

  const monthName = HEBREW_MONTH_NAMES[monthDate.getMonth()]
  const yearStr = monthDate.getFullYear()
  const dateRangeStr = `${format(startOfMonth(monthDate), 'dd.MM.yyyy')} - ${format(endOfMonth(monthDate), 'dd.MM.yyyy')}`

  /**
   * דוח של אדם אחד: או שהמשתמש רואה רק את עצמו, או שהוא סינן לעובד יחיד,
   * או שבפועל חזר עובד אחד בלבד. זו ההבחנה שקובעת את הקיבוץ למטה.
   */
  const singleEmployee = useMemo(
    () => new Set(rows.map((r) => r.profile_id)).size <= 1 && (!showEmployeeFilter || profileIds.length <= 1),
    [rows, showEmployeeFilter, profileIds],
  )

  /**
   * שורה אחת לכל משמרת שהייתה — ותו לא.
   *
   * יום עם שתי משמרות — יציאה לשטח בבוקר וחזרה למחסן בערב, או שתי משימות
   * שהפער ביניהן גדול מ-merge_gap_minutes — הוא מקרה רגיל ולא חריג, וכל
   * משמרת היא רשומה משלה: שעות משלה, סטטוס משלו ואישור נפרד.
   *
   * ימים בלי החתמה אינם מקבלים שורה. הדוח הוא רשימת המשמרות ולא לוח שנה:
   * חודש שבו רוב השורות ריקות קובר בתוכו את מה שבאמת קרה, וממילא שורה כזו
   * לא ידעה להבחין בין חופשה, מחלה ויום שלא שובץ בו דבר. החוסר עצמו לא
   * נעלם — הוא נמדד מול המתוכנן, בשורת המשמרת ובאריח "שעות חסרות".
   *
   * הסדר מהחדש לישן: את החודש קוראים מהמשמרת האחרונה אחורה. בתוך יום אחד
   * הסדר נשאר כרונולוגי, כי שתי משמרות של אותו יום נקראות ברצף.
   */
  const shiftRows = useMemo<ShiftRowView[]>(() => {
    // הספירה היא לפי עובד ויום, ולא לפי יום בלבד: בדוח צוותי, שני עובדים
    // שעבדו באותו יום אינם "שתי משמרות" של אף אחד מהם.
    const perDay = new Map<string, number>()
    for (const r of rows) {
      const k = `${r.profile_id}|${r.work_date}`
      perDay.set(k, (perDay.get(k) ?? 0) + 1)
    }
    return [...rows]
      .sort(
        (a, b) =>
          b.work_date.localeCompare(a.work_date) || a.seq - b.seq || a.clock_in_at.localeCompare(b.clock_in_at),
      )
      .map((r) => toShiftView(r, perDay.get(`${r.profile_id}|${r.work_date}`) ?? 1))
  }, [rows])

  /**
   * קיבוץ לפי עובד, לדוח שיש בו יותר מאחד. זה מה שהופך את "הבונוס נספר
   * בסך הכולל לעובד" למשהו שרואים במסך ולא רק במספר החודשי הכללי: לכל
   * עובד יש כאן שורת סיכום משלו, ובה השעות, הבונוסים והסך שלו.
   *
   * הסיכומים סופרים מאושרות בלבד, בדיוק כמו הסיכומים שהשרת מחזיר — אחרת
   * סכום הקבוצות לא היה שווה לאריחים שמעליהן.
   */
  const employeeGroups = useMemo<EmployeeGroup[]>(() => {
    if (singleEmployee) return []
    const byId = new Map<string, EmployeeGroup>()
    for (const s of shiftRows) {
      const r = s.row
      let g = byId.get(r.profile_id)
      if (!g) {
        g = { profileId: r.profile_id, name: r.full_name, hours: 0, overtime: 0, bonus: 0, total: null, shifts: [] }
        byId.set(r.profile_id, g)
      }
      g.shifts.push(s)
      if (r.status !== 'approved') continue
      g.hours += r.actual_hours ?? 0
      g.overtime += r.pay?.overtime_hours ?? 0
      g.bonus += r.pay?.bonus ?? 0
      if (r.pay?.total != null) g.total = (g.total ?? 0) + r.pay.total
    }
    return [...byId.values()].sort((a, b) => a.name.localeCompare(b.name, 'he'))
  }, [shiftRows, singleEmployee])

  const totalWorkHours = useMemo(() => {
    if (totals?.actual_hours != null) return totals.actual_hours
    return shiftRows.reduce((acc, d) => acc + d.hours, 0)
  }, [totals, shiftRows])

  const overtimeHours = useMemo(() => {
    if (totals?.overtime_hours != null) return totals.overtime_hours
    return rows.reduce((acc, r) => acc + (r.pay?.overtime_hours ?? 0), 0)
  }, [totals, rows])

  /**
   * המתוכנן והחוסר מולו.
   *
   * מאושרות בלבד, בדיוק כמו ה-totals שהשרת מחזיר: אחרת "96:30 מתוך 104:00"
   * היה משווה שעות מאושרות לתכנון שכולל גם משמרות שטרם הוכרעו, ושני הצדדים
   * של אותו משפט היו נספרים לפי שני כללים.
   *
   * משמרת בלי planned_hours אינה נכנסת לאף אחד משני הסכומים — לא לתכנון ולא
   * לחוסר. לכן ייתכן שהעבודה בפועל תעלה על המתוכנן, וזה נכון: מי שהחתים בלי
   * שיבוץ עבד שעות שאיש לא תכנן.
   */
  const { plannedHours, missingHours } = useMemo(() => {
    let planned = 0
    let missing = 0
    for (const r of rows) {
      if (r.status !== 'approved') continue
      planned += r.planned_hours ?? 0
      // משמרת שעדיין פתוחה אינה נספרת כחוסר, בדיוק כמו בשורה שלה
      if (r.clock_out_at) missing += shiftShortfall(r.planned_hours, r.actual_hours)
    }
    return { plannedHours: planned, missingHours: missing }
  }, [rows])

  /** ימים, לא משמרות: יום עם שתי משמרות הוא עדיין יום עבודה אחד. */
  const workDaysCount = useMemo(
    () => new Set(rows.filter((r) => (r.actual_hours ?? 0) > 0).map((r) => r.work_date)).size,
    [rows],
  )

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
      // עמודת "עובד" קיימת רק כשיש יותר מעובד אחד בטבלה. בדוח של המשתמש
      // עצמו היא הייתה חוזרת על אותו שם בכל שורה.
      ...(showEmployeeFilter
        ? [
            {
              key: 'name',
              header: 'עובד',
              sortValue: (r: AttendanceReportRow) => r.full_name,
              render: (r: AttendanceReportRow) => <span className="truncate">{r.full_name}</span>,
            } satisfies Column<AttendanceReportRow>,
          ]
        : []),
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
        render: (r) => (
          <span className={cx('tabular-nums font-semibold', r.status !== 'approved' && 'text-ink-tertiary')}>
            {fmtDuration(r.pay?.paid_hours)}
          </span>
        ),
      },
      ...(showOvertime
        ? [
            {
              key: 'overtime',
              header: 'ש״נ',
              align: 'center',
              sortValue: (r: AttendanceReportRow) => r.pay?.overtime_hours ?? 0,
              render: (r: AttendanceReportRow) =>
                r.pay?.overtime_hours ? (
                  <Badge tone="warning">{fmtDuration(r.pay.overtime_hours)}</Badge>
                ) : (
                  <span className="text-ink-tertiary">—</span>
                ),
            } satisfies Column<AttendanceReportRow>,
          ]
        : []),
      {
        key: 'site',
        header: 'שטח/מחסן',
        align: 'center',
        render: (r) =>
          r.work_site ? <Badge tone={r.work_site === 'warehouse' ? 'info' : 'neutral'}>{WORK_SITE_LABELS[r.work_site]}</Badge> : null,
      },
      {
        key: 'flags',
        header: 'הערות',
        render: (r) => (
          // flex-nowrap ולא flex-wrap: התא הוא table-fixed עם 'truncate' משלו,
          // ולכן שורת תגים שעולה על רוחב העמודה נחתכת ולא יורדת שורה — עמודת
          // ההערות לא הייתה אמורה לקבוע את גובה כל השורה בטבלה.
          <div className="flex flex-nowrap items-center gap-1">
            <Badge tone={STATUS_TONES[r.status]}>{STATUS_LABELS[r.status]}</Badge>
            {r.source === 'manual' && <Badge tone="warning">ידני</Badge>}
            {visibleFlags(r.flags).map((f) => (
              <Badge key={f} tone={needsAttention([f]) ? 'error' : 'neutral'}>
                {flagLabel(f)}
              </Badge>
            ))}
          </div>
        ),
      },
    ]

    // עמודת הבונוס מופיעה רק כשיש בונוסים בכלל, ותמיד לפני "שכר" — שכבר
    // כולל אותה, כי הסך מגיע מחושב מהשרת.
    if (showMoney && showBonus) {
      base.push({
        key: 'bonus',
        header: 'בונוס',
        align: 'end',
        sortValue: (r) => r.pay?.bonus ?? 0,
        render: (r) =>
          r.pay?.bonus ? (
            <span
              className="tabular-nums font-semibold text-accent-700 dark:text-accent-300"
              title={r.bonus_note ?? undefined}
            >
              {fmtMoney(r.pay.bonus)}
            </span>
          ) : (
            <span className="text-ink-tertiary">—</span>
          ),
      })
    }

    if (showMoney) {
      base.push({
        key: 'total',
        header: 'שכר',
        align: 'end',
        sortValue: (r) => r.pay?.total ?? 0,
        render: (r) => (
          <span className={cx('tabular-nums font-semibold', r.status !== 'approved' && 'text-ink-tertiary')}>
            {fmtMoney(r.pay?.total)}
          </span>
        ),
      })
    }
    return base
  }, [showMoney, showBonus, showEmployeeFilter, showOvertime])

  const cardList = (list: ShiftRowView[]) => (
    <div className="space-y-2">
      {list.map((d) => (
        <ShiftCard
          key={d.key}
          view={d}
          showName={showEmployeeFilter && singleEmployee}
          clickable={canOpenRow}
          onOpen={() => canOpenRow && setSelected(d.row)}
        />
      ))}
    </div>
  )

  /**
   * כותרת הרשימה. "המשמרות שלי" רק כשהדוח באמת של הקורא — מנהל שסינן לעובד
   * אחד רואה את המשמרות של מישהו אחר.
   */
  const listTitle = !showEmployeeFilter ? 'המשמרות שלי' : singleEmployee ? 'המשמרות' : 'פירוט לפי עובד'

  const exportButton = (
    <Button
      variant="ghost"
      size="sm"
      onClick={() => void runExport()}
      loading={exporting}
      disabled={!data || rows.length === 0}
    >
      <Download size={ICON.sm} strokeWidth={STROKE} />
      ייצוא
    </Button>
  )

  return (
    <div className="mx-auto max-w-5xl space-y-5 pb-12">
      {!embedded && (
        <PageHeader
          title="דוח נוכחות"
          subtitle={canSeeAll ? 'שעות, שעות נוספות ושכר לכל העובדים' : 'השעות שלי'}
          actions={
            canAdd ? (
              <Button variant="primary" size="sm" onClick={() => setAdding(true)}>
                <Plus size={ICON.sm} strokeWidth={STROKE} />
                הזנה ידנית
              </Button>
            ) : undefined
          }
        />
      )}

      {/* סרגל אחד: החודש, התצוגה והסינון. קודם הם ישבו בשני מקומות רחוקים
          זה מזה — כדור מרחף במרכז הדף ומחליף תצוגה ליד כותרת הרשימה. */}
      <Card className="flex flex-wrap items-center justify-between gap-3 p-3">
        <div className="flex items-center gap-1">
          <span className="me-1 flex size-9 shrink-0 items-center justify-center rounded-xl bg-subtle text-ink-secondary" aria-hidden>
            <CalendarDays size={ICON.lg} strokeWidth={STROKE} />
          </span>
          <IconButton label="חודש קודם" variant="ghost" onClick={handlePrevMonth}>
            <ChevronRight size={ICON.lg} strokeWidth={STROKE} />
          </IconButton>
          <div className="min-w-36 text-center">
            <p className="type-title">
              {monthName} {yearStr}
            </p>
            <p className="type-caption text-ink-tertiary tabular" dir="ltr">
              {dateRangeStr}
            </p>
          </div>
          <IconButton label="חודש הבא" variant="ghost" onClick={handleNextMonth}>
            <ChevronLeft size={ICON.lg} strokeWidth={STROKE} />
          </IconButton>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          {!isPhone && (
            <SegmentedControl
              value={viewMode}
              onChange={setViewMode}
              items={[
                { key: 'cards', label: 'כרטיסים', icon: <LayoutGrid size={ICON.sm} strokeWidth={STROKE} /> },
                { key: 'table', label: 'טבלה', icon: <List size={ICON.sm} strokeWidth={STROKE} /> },
              ]}
            />
          )}
          <Button
            variant={showFilters ? 'primary' : 'outlined'}
            size="sm"
            onClick={() => setShowFilters(!showFilters)}
          >
            <SlidersHorizontal size={ICON.sm} strokeWidth={STROKE} />
            סינון
          </Button>
        </div>
      </Card>

      {/* סיכום החודש. הסדר הוא מהמוחשי למופשט — ימים, שעות, ואז החריגות
          משניהם. אריח מופיע רק כשיש לו מה לומר: שעות נוספות למי שהן חלות
          עליו, בונוסים למי שניתנו, וסכומים למי שרשאי לראות אותם. */}
      <div
        className={cx(
          'grid gap-3 grid-cols-2 sm:grid-cols-4',
          (showMoney && showBonus ? 1 : 0) + (showMoney ? 1 : 0) >= 1 && 'lg:grid-cols-6',
        )}
      >
        <SummaryTile
          icon={<CalendarCheck size={ICON.xl} strokeWidth={STROKE} />}
          label="ימי עבודה"
          value={workDaysCount}
          tone="#16a34a"
        />
        <SummaryTile
          icon={<Clock size={ICON.xl} strokeWidth={STROKE} />}
          label="שעות עבודה"
          value={fmtDurationHHMM(totalWorkHours)}
          hint={plannedHours > 0 ? `מתוך ${fmtDurationHHMM(plannedHours)}` : undefined}
          tone="#2e90fa"
        />
        {showOvertime && (
          <SummaryTile
            icon={<PlusCircle size={ICON.xl} strokeWidth={STROKE} />}
            label="שעות נוספות"
            value={fmtDurationHHMM(overtimeHours)}
            tone="#7c3aed"
          />
        )}
        <SummaryTile
          icon={<PieChart size={ICON.xl} strokeWidth={STROKE} />}
          label="שעות חסרות"
          value={fmtDurationHHMM(missingHours)}
          tone="#f59e0b"
        />
        {showMoney && showBonus && (
          <SummaryTile
            icon={<Banknote size={ICON.xl} strokeWidth={STROKE} />}
            label="בונוסים"
            value={fmtMoney(totals?.bonus ?? 0)}
            hint="כלול בסך לתשלום"
            tone="#1fa189"
          />
        )}
        {showMoney && (
          <SummaryTile
            icon={<Wallet size={ICON.xl} strokeWidth={STROKE} />}
            label='סה"כ לתשלום'
            value={fmtMoney(totals?.total ?? 0)}
            hint="מאושר בלבד"
            tone="#3563f0"
          />
        )}
      </div>

      {showFilters && (
        <Card className="flex flex-wrap items-end gap-3 p-4 animate-in fade-in duration-200">
          {showEmployeeFilter && (
            <Field label="עובדים" className="min-w-52 flex-1">
              <MultiSelect
                options={employeeOptions}
                values={profileIds}
                onToggle={(id) =>
                  setProfileIds((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]))
                }
                placeholder="כל העובדים"
              />
            </Field>
          )}
          {canSeeAll && !contractorId && (
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
          <Field label="סטטוס" className="w-40">
            <Select value={status} onChange={(e) => setStatus(e.target.value as AttendanceStatus | '')}>
              <option value="">הכול</option>
              <option value="pending">ממתין לאישור</option>
              <option value="approved">מאושר</option>
              <option value="rejected">נדחה</option>
            </Select>
          </Field>
          <Checkbox checked={onlyFlagged} onChange={setOnlyFlagged} label="רק רשומות עם חריגה" />
        </Card>
      )}

      {/* הייצוא יושב כאן ולא בכותרת הדף: הוא מייצא את הרשימה שמתחתיו, ובפורטל
          הקבלן — שבו הכותרת מוסתרת — הוא לא היה נגיש בכלל. */}
      <div className="flex flex-wrap items-center justify-between gap-3 pt-1">
        <h3 className="type-heading">{listTitle}</h3>
        <div className="flex items-center gap-2">
          {showEmployeeFilter && (
            <div className="w-52">
              <Select
                value={profileIds[0] || ''}
                onChange={(e) => setProfileIds(e.target.value ? [e.target.value] : [])}
              >
                <option value="">כל העובדים</option>
                {employeeOptions.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.label}
                  </option>
                ))}
              </Select>
            </div>
          )}
          {exportButton}
        </div>
      </div>

      {/* תצוגת הכרטיסים לא הציגה עד כה טעינה, שגיאה או ריק — רק הטבלה ידעה
          לעשות את זה, ולכן חודש בלי נתונים נראה כמו דף שנשבר. */}
      {isLoading ? (
        <SkeletonList rows={6} />
      ) : error ? (
        <ErrorState error={error} onRetry={() => void refetch()} />
      ) : effectiveView === 'table' ? (
        <DataTable
          rows={rows}
          columns={columns}
          getRowId={(r) => r.id}
          empty="לא נמצאו רשומות נוכחות בטווח הזה"
          onRowClick={canOpenRow ? (r) => setSelected(r) : undefined}
          storageKey="attendance-report"
          pageSize={50}
        />
      ) : shiftRows.length === 0 ? (
        <EmptyState
          art="calendar"
          title="אין משמרות בחודש הזה"
          description="אפשר לדפדף לחודש אחר, או לשחרר את הסינון."
        />
      ) : singleEmployee ? (
        cardList(shiftRows)
      ) : (
        <div className="space-y-5">
          {employeeGroups.map((g) => (
            <section key={g.profileId} className="space-y-2">
              {/* שורת הסיכום של העובד: כאן הבונוס הופך למספר שרואים ליד השם,
                  ולא רק לחלק מהסך החודשי של כל הצוות. */}
              <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 rounded-xl bg-subtle px-4 py-2.5">
                <p className="type-title">{g.name}</p>
                <p className="flex flex-wrap items-baseline gap-x-3 gap-y-1 type-caption text-ink-secondary">
                  <span className="tabular">{fmtDurationHHMM(g.hours)} שעות</span>
                  {showOvertime && g.overtime > 0 && (
                    <span className="tabular text-warning-text">{fmtDurationHHMM(g.overtime)} נוספות</span>
                  )}
                  {showMoney && g.bonus > 0 && (
                    <span className="tabular font-semibold text-accent-700 dark:text-accent-300">
                      בונוס {fmtMoney(g.bonus)}
                    </span>
                  )}
                  {showMoney && g.total != null && (
                    <span className="tabular type-body font-semibold text-ink">{fmtMoney(g.total)}</span>
                  )}
                </p>
              </div>
              {cardList(g.shifts)}
            </section>
          ))}
        </div>
      )}

      {/* שורת הסגירה של החודש. אותם מספרים שבאריחים למעלה, במשפט אחד —
          אחרי הגלילה דרך הרשימה, בלי לגלול חזרה. */}
      {!isLoading && !error && rows.length > 0 && (
        <Card className="flex items-center gap-3 p-4">
          <span className="flex size-10 shrink-0 items-center justify-center rounded-full bg-primary-subtle text-primary" aria-hidden>
            <PieChart size={ICON.xl} strokeWidth={STROKE} />
          </span>
          <div className="min-w-0">
            <p className="type-title">סיכום החודש</p>
            <p className="flex flex-wrap items-center gap-x-2 gap-y-0.5 type-caption text-ink-secondary">
              <span className="tabular">{workDaysCount} ימי עבודה</span>
              <span className="text-ink-tertiary" aria-hidden>|</span>
              <span className="tabular">{fmtDurationHHMM(totalWorkHours)} שעות עבודה</span>
              {showOvertime && overtimeHours > 0 && (
                <>
                  <span className="text-ink-tertiary" aria-hidden>|</span>
                  <span className="tabular text-violet-700 dark:text-violet-300">
                    {fmtDurationHHMM(overtimeHours)} שעות נוספות
                  </span>
                </>
              )}
              {missingHours > 0 && (
                <>
                  <span className="text-ink-tertiary" aria-hidden>|</span>
                  <span className="tabular text-error-text">{fmtDurationHHMM(missingHours)} שעות חסרות</span>
                </>
              )}
            </p>
          </div>
        </Card>
      )}

      <AttendanceEntryDrawer row={selected} onClose={() => setSelected(null)} />
      {adding && <ManualEntryModal onClose={() => setAdding(false)} />}
    </div>
  )
}

/**
 * אריח סיכום. גרסה מאונכת של StatCard: הסמל למעלה והמספר מתחתיו, כדי
 * ששורה של ארבעה תיקרא בטלפון בלי להתמעך לצדדים.
 */
function SummaryTile({
  icon,
  label,
  value,
  hint,
  tone,
}: {
  icon: ReactNode
  label: string
  value: ReactNode
  hint?: string
  tone: string
}) {
  return (
    <div className="surface flex flex-col items-center gap-1 px-2 py-4 text-center">
      <span
        className="mb-1 flex size-11 items-center justify-center rounded-full"
        style={{ background: `color-mix(in srgb, ${tone} 14%, transparent)`, color: tone }}
        aria-hidden
      >
        {icon}
      </span>
      <p className="type-caption font-medium text-ink-tertiary">{label}</p>
      <p className="type-display tabular leading-7">{value}</p>
      {hint && <p className="type-caption tabular text-ink-tertiary">{hint}</p>}
    </div>
  )
}

/**
 * תא בשורת המשמרת: כותרת קטנה מעל, הערך מתחתיה, וקו מפריד מהתא שלפניו.
 *
 * ‏`wide` נותן חלק גדול יותר מהרוחב לשתי העמודות שיש בהן שתי שורות —
 * הכניסה (שעה ומיקום) והסה"כ (שעות והפרש). בחלוקה שווה הן היו היחידות
 * שנחתכות, בזמן שעמודת היציאה מחזיקה מספר אחד ונשאר בה מקום.
 */
function ShiftCell({
  label,
  divided,
  wide,
  children,
}: {
  label: string
  divided?: boolean
  wide?: boolean
  children: ReactNode
}) {
  return (
    <div
      className={cx(
        'min-w-0 px-1 text-center sm:px-2',
        wide ? 'flex-[1.3]' : 'flex-1',
        divided && 'border-s border-line-subtle',
      )}
    >
      <p className="truncate type-caption leading-tight text-ink-tertiary">{label}</p>
      {children}
    </div>
  )
}

const DELTA_CLASS: Record<ShiftRowView['deltaTone'], string> = {
  overtime: 'text-violet-700 dark:text-violet-300',
  short: 'text-error-text',
  muted: 'text-ink-tertiary',
}

/**
 * שורת משמרת אחת: תאריך, כניסה, יציאה, סה"כ — ובקצה סמל שאומר במילה אחת
 * מה קרה בה.
 *
 * הפריסה משתנה ברוחב במקום להתכווץ: במסך צר שלוש עמודות השעות יורדות
 * לשורה משלהן מתחת לתאריך ולסמל, ובמסך רחב הכול בשורה אחת.
 */
function ShiftCard({
  view: d,
  showName,
  clickable,
  onOpen,
}: {
  view: ShiftRowView
  showName: boolean
  clickable: boolean
  onOpen: () => void
}) {
  const tone = SHIFT_TONE[d.tone]
  const { Icon } = tone

  return (
    <div
      role={clickable ? 'button' : undefined}
      tabIndex={clickable ? 0 : undefined}
      onClick={clickable ? onOpen : undefined}
      onKeyDown={clickable ? (e) => (e.key === 'Enter' || e.key === ' ') && (e.preventDefault(), onOpen()) : undefined}
      className={cx(
        'surface flex flex-wrap items-center gap-x-1 gap-y-2 px-2 py-3 transition-colors sm:gap-x-2 sm:px-3',
        clickable &&
          'cursor-pointer hover:border-line-strong hover:bg-subtle/60 focus-visible:outline-none focus-visible:focus-ring',
      )}
    >
      {showName && d.employeeName && (
        <p className="w-full truncate type-caption font-semibold text-ink-tertiary">{d.employeeName}</p>
      )}

      {/* פתיחת המשמרת */}
      <ChevronRight
        size={ICON.md}
        strokeWidth={STROKE}
        className={cx('shrink-0 text-ink-tertiary', !clickable && 'invisible')}
        aria-hidden
      />

      {/* תאריך ויום */}
      <div className="shrink-0">
        <p className="type-caption leading-tight text-ink-tertiary">יום {d.hebrewDayLetter}</p>
        <p className="type-body font-semibold tabular" dir="ltr">
          {d.formattedDate}
        </p>
        {d.shiftLabel && <p className="type-caption leading-tight text-ink-tertiary">{d.shiftLabel}</p>}
      </div>

      {/* השעות עצמן. שלוש העמודות נשארות בשורה אחת גם בטלפון — זה כל מה
          שיש בשורה, וירידת שורה שנייה הפכה כל משמרת לשני כרטיסים. */}
      <div className="flex min-w-0 flex-1 items-start">
        <ShiftCell label="כניסה" wide>
          {/* הנקודה מסמנת אם ההחתמה אומתה מול מיקום. ב-RTL היא נופלת לימין
              השעה, בדיוק כמו בעיצוב. */}
          <p className="flex items-center justify-center gap-1.5">
            <span
              className={cx('size-1.5 shrink-0 rounded-full', d.locationVerified ? 'bg-success' : 'bg-warning')}
              title={d.locationVerified ? 'מיקום אומת' : 'המיקום לא אומת'}
            />
            <span className="type-body font-semibold tabular text-success-text" dir="ltr">
              {d.clockIn}
            </span>
          </p>
          {d.location && (
            /* סמל הסיכה יורד בטלפון: הוא עולה 16px מעמודה שבה שם המחסן כבר
               נחתך בלעדיו, והמילה עצמה ברורה גם בלי הסמל שלידה. */
            <p className="flex items-center justify-center gap-1 type-caption text-ink-tertiary">
              <MapPin size={ICON.xs} strokeWidth={STROKE} className="hidden shrink-0 sm:block" />
              <span className="truncate">{d.location}</span>
            </p>
          )}
        </ShiftCell>

        <ShiftCell label="יציאה" divided>
          <p className="type-body font-semibold tabular" dir="ltr">
            {d.clockOut ?? '…'}
          </p>
        </ShiftCell>

        <ShiftCell label='סה"כ שעות' divided wide>
          <p className="type-title tabular" dir="ltr">
            {d.hoursText}
          </p>
          {d.deltaText && (
            <p className={cx('truncate type-caption tabular', DELTA_CLASS[d.deltaTone])}>{d.deltaText}</p>
          )}
        </ShiftCell>
      </div>

      {/* הבונוס יורד לשורה משלו בטלפון. בשורה הראשית הוא היה דוחק את שלוש
          עמודות השעות עד שהן נדרסות זו על זו. */}
      {d.bonus != null && (
        <p className="order-last w-full text-end sm:order-none sm:w-auto">
          <span
            className="inline-flex shrink-0 items-center gap-1 rounded-lg border border-accent-200 bg-accent-50 px-2 py-0.5 type-caption font-bold text-accent-700 dark:border-accent-800 dark:bg-accent-950/50 dark:text-accent-300"
            title={d.row.bonus_note ?? 'בונוס למשמרת'}
          >
            <Banknote size={ICON.xs} strokeWidth={STROKE} />
            {fmtMoney(d.bonus)}
          </span>
        </p>
      )}

      {/* מה קרה במשמרת */}
      <div className="flex w-13 shrink-0 flex-col items-center gap-1 sm:w-16">
        <span className={cx('flex size-8 items-center justify-center rounded-xl border sm:size-9', tone.box)} aria-hidden>
          <Icon size={ICON.lg} strokeWidth={STROKE} />
        </span>
        <span className={cx('type-caption text-center font-bold leading-tight', tone.text)}>{tone.label}</span>
      </div>
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
    onError: (e) => toast.error(errorMessage(e)),
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
