import { useMemo, useState } from 'react'
import { useMutation } from '@tanstack/react-query'
import {
  Banknote,
  Briefcase,
  CalendarCheck,
  ChevronLeft,
  ChevronRight,
  Clock,
  Download,
  ICON,
  LayoutGrid,
  List,
  MapPin,
  Plus,
  PlusCircle,
  STROKE,
  SlidersHorizontal,
  Wallet,
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
import { fmtDate, fmtMoney, fmtTime, toISODate } from '../../lib/dates'
import { addMonths, eachDayOfInterval, endOfMonth, format, startOfMonth, subMonths } from 'date-fns'
import { useAttendanceInvalidate, useAttendanceReport, useContractorStaff } from './attendanceQueries'
import { AttendanceEntryDrawer } from './AttendanceEntryDrawer'
import {
  STATUS_LABELS,
  STATUS_TONES,
  WORK_SITE_LABELS,
  flagLabel,
  fmtDuration,
  needsAttention,
  visibleFlags,
} from './shiftFormat'
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

function fmtDurationHHMM(hours: number | null | undefined, padHour = true): string {
  if (hours == null || isNaN(hours) || hours <= 0) return '00:00'
  const totalMins = Math.round(hours * 60)
  const h = Math.floor(totalMins / 60)
  const m = totalMins % 60
  const hh = padHour ? String(h).padStart(2, '0') : String(h)
  const mm = String(m).padStart(2, '0')
  return `${hh}:${mm}`
}

type ShiftStatus = 'completed' | 'pending' | 'rejected' | 'absence' | 'rest'

/**
 * טונים לנקודת הסטטוס ולתג שלידה. אחד לכל מצב, במקום אחד, כדי שהכרטיס
 * והתג לא יוכלו לצבוע את אותה שורה בשני צבעים.
 */
const SHIFT_STATUS: Record<ShiftStatus, { label: string | null; dot: string; pill: string }> = {
  completed: {
    label: 'הושלם',
    dot: 'bg-success',
    pill: 'border-success-border bg-success-subtle text-success-text',
  },
  pending: {
    label: 'ממתין',
    dot: 'bg-warning',
    pill: 'border-warning-border bg-warning-subtle text-warning-text',
  },
  rejected: {
    label: 'נדחה',
    dot: 'bg-error',
    pill: 'border-error-border bg-error-subtle text-error-text',
  },
  absence: {
    label: 'היעדרות',
    dot: 'bg-error',
    pill: 'border-error-border bg-error-subtle text-error-text',
  },
  rest: { label: null, dot: 'bg-line-strong', pill: '' },
}

/**
 * שורה ברשימת הכרטיסים: או משמרת אחת, או יום שאין בו משמרת בכלל. `row` הוא
 * מה שמבדיל ביניהם — יש רשומה לפתוח, או שאין.
 */
interface ShiftRowView {
  key: string
  formattedDate: string
  hebrewDayLetter: string
  /** "משמרת 2" — רק ביום שיש בו יותר מאחת */
  shiftLabel: string | null
  employeeName: string | null
  shiftTime: string
  location: string | null
  hoursText: string
  overtimeText: string | null
  /** הבונוס על המשמרת, או null כשאין או כשאין הרשאה לראות סכומים */
  bonus: number | null
  status: ShiftStatus
  row: AttendanceReportRow | null
  hours: number
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

  const todayISO = useMemo(() => toISODate(new Date()), [])

  /**
   * דוח של אדם אחד: או שהמשתמש רואה רק את עצמו, או שהוא סינן לעובד יחיד,
   * או שבפועל חזר עובד אחד בלבד. זו ההבחנה שקובעת גם את ימי ההיעדרות
   * וגם את הקיבוץ למטה.
   */
  const singleEmployee = useMemo(
    () => new Set(rows.map((r) => r.profile_id)).size <= 1 && (!showEmployeeFilter || profileIds.length <= 1),
    [rows, showEmployeeFilter, profileIds],
  )

  const toShiftView = (r: AttendanceReportRow, sameDayCount: number, day: Date): ShiftRowView => {
    const clockIn = new Date(r.clock_in_at)
    const clockOut = r.clock_out_at ? new Date(r.clock_out_at) : null
    const overtime = r.pay?.overtime_hours ?? 0
    return {
      key: r.id,
      formattedDate: format(day, 'dd.MM.yy'),
      hebrewDayLetter: HEBREW_DAY_LETTERS[day.getDay()],
      shiftLabel: sameDayCount > 1 ? `משמרת ${r.seq}` : null,
      employeeName: r.full_name,
      shiftTime: `${fmtTime(clockIn.toTimeString())} - ${clockOut ? fmtTime(clockOut.toTimeString()) : '…'}`,
      location: r.work_site
        ? WORK_SITE_LABELS[r.work_site]
        : r.contractor_id
        ? 'מחסן ראשי'
        : 'מרכז לוגיסטי',
      hoursText: fmtDurationHHMM(r.actual_hours, true),
      overtimeText: overtime > 0 ? `${fmtDurationHHMM(overtime, true)} נוספות` : null,
      bonus: r.pay?.bonus ? r.pay.bonus : null,
      status: r.status === 'approved' ? 'completed' : r.status,
      row: r,
      hours: r.actual_hours ?? 0,
    }
  }

  /**
   * שורה אחת לכל משמרת, לא לכל יום.
   *
   * יום עם שתי משמרות — יציאה לשטח בבוקר וחזרה למחסן בערב, או שתי משימות
   * שהפער ביניהן גדול מ-merge_gap_minutes — הוא מקרה רגיל ולא חריג, וכל
   * משמרת היא רשומה משלה: שעות משלה, סטטוס משלו ואישור נפרד.
   *
   * ימים בלי משמרת ממשיכים לתפוס שורה **רק בדוח של אדם אחד**. בדוח של כל
   * הצוות "היעדרות" בלי שם היא שורה שאי אפשר לענות עליה — של מי ההיעדרות?
   * — ובחודש מלא היא הייתה מציפה את המשמרות עצמן.
   */
  const shiftRows = useMemo<ShiftRowView[]>(() => {
    const start = startOfMonth(monthDate)
    const end = endOfMonth(monthDate)

    return eachDayOfInterval({ start, end }).flatMap<ShiftRowView>((day) => {
      const dateStr = toISODate(day)
      const dayOfWeek = day.getDay()

      const dayRows = rows
        .filter((r) => r.work_date === dateStr)
        .sort((a, b) => a.seq - b.seq || a.clock_in_at.localeCompare(b.clock_in_at))

      if (dayRows.length > 0) return dayRows.map((r) => toShiftView(r, dayRows.length, day))
      if (!singleEmployee) return []

      // יום חול שעבר ואין בו החתמה. שבת אינה יום עבודה, ולכן היא "מנוחה".
      const isPastOrToday = dateStr <= todayISO
      const isWorkDay = dayOfWeek !== 6
      return [
        {
          key: dateStr,
          formattedDate: format(day, 'dd.MM.yy'),
          hebrewDayLetter: HEBREW_DAY_LETTERS[dayOfWeek],
          shiftLabel: null,
          employeeName: null,
          shiftTime: '-',
          location: null,
          hoursText: '-',
          overtimeText: null,
          bonus: null,
          status: isPastOrToday && isWorkDay ? 'absence' : 'rest',
          row: null,
          hours: 0,
        },
      ]
    })
  }, [monthDate, rows, todayISO, singleEmployee])

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
      if (!r) continue
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

  const regularHours = useMemo(() => Math.max(0, totalWorkHours - overtimeHours), [totalWorkHours, overtimeHours])

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
          showOvertime={showOvertime}
          clickable={!!d.row && canOpenRow}
          onOpen={() => d.row && canOpenRow && setSelected(d.row)}
        />
      ))}
    </div>
  )

  return (
    <div className="mx-auto max-w-5xl space-y-5 pb-12">
      {!embedded && (
        <PageHeader
          title="דוח נוכחות"
          subtitle={canSeeAll ? 'שעות, שעות נוספות ושכר לכל העובדים' : 'השעות שלי'}
          actions={
            <div className="flex items-center gap-2">
              <Button
                variant="ghost"
                size="sm"
                onClick={() => void runExport()}
                loading={exporting}
                disabled={!data || rows.length === 0}
              >
                <Download size={ICON.sm} strokeWidth={STROKE} />
                ייצוא לאקסל
              </Button>
              {canAdd && (
                <Button variant="primary" size="sm" onClick={() => setAdding(true)}>
                  <Plus size={ICON.sm} strokeWidth={STROKE} />
                  הזנה ידנית
                </Button>
              )}
            </div>
          }
        />
      )}

      {/* סרגל אחד: החודש, התצוגה והסינון. קודם הם ישבו בשני מקומות רחוקים
          זה מזה — כדור מרחף במרכז הדף ומחליף תצוגה ליד כותרת הרשימה. */}
      <Card className="flex flex-wrap items-center justify-between gap-3 p-3">
        <div className="flex items-center gap-1">
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
          <SegmentedControl
            value={viewMode}
            onChange={setViewMode}
            items={[
              { key: 'cards', label: 'כרטיסים', icon: <LayoutGrid size={ICON.sm} strokeWidth={STROKE} /> },
              { key: 'table', label: 'טבלה', icon: <List size={ICON.sm} strokeWidth={STROKE} /> },
            ]}
          />
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

      {/* סיכום החודש. אריח מופיע רק כשיש לו מה לומר: שעות נוספות למי שהן
          חלות עליו, בונוסים למי שניתנו, וסכומים למי שרשאי לראות אותם. */}
      <div
        className={cx(
          'grid gap-3',
          'grid-cols-2',
          'sm:grid-cols-3',
          (showOvertime ? 1 : 0) + (showMoney && showBonus ? 1 : 0) + (showMoney ? 1 : 0) >= 2
            ? 'lg:grid-cols-6'
            : 'lg:grid-cols-4',
        )}
      >
        <StatCard
          icon={<Clock size={ICON.xl} strokeWidth={STROKE} />}
          label='סה"כ שעות'
          value={fmtDurationHHMM(totalWorkHours)}
        />
        <StatCard
          icon={<CalendarCheck size={ICON.xl} strokeWidth={STROKE} />}
          label="שעות רגילות"
          value={fmtDurationHHMM(regularHours)}
        />
        {showOvertime && (
          <StatCard
            icon={<PlusCircle size={ICON.xl} strokeWidth={STROKE} />}
            label="שעות נוספות"
            value={fmtDurationHHMM(overtimeHours)}
            tone="#f59e0b"
          />
        )}
        <StatCard
          icon={<Briefcase size={ICON.xl} strokeWidth={STROKE} />}
          label="ימי עבודה"
          value={workDaysCount}
        />
        {showMoney && showBonus && (
          <StatCard
            icon={<Banknote size={ICON.xl} strokeWidth={STROKE} />}
            label="בונוסים"
            value={fmtMoney(totals?.bonus ?? 0)}
            hint="כלול בסך לתשלום"
            tone="#1fa189"
          />
        )}
        {showMoney && (
          <StatCard
            icon={<Wallet size={ICON.xl} strokeWidth={STROKE} />}
            label='סה"כ לתשלום'
            value={fmtMoney(totals?.total ?? 0)}
            hint="מאושר בלבד"
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

      <div className="flex items-center justify-between gap-3 pt-1">
        <h3 className="type-heading">{singleEmployee ? 'פירוט לפי יום' : 'פירוט לפי עובד'}</h3>
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
      </div>

      {/* תצוגת הכרטיסים לא הציגה עד כה טעינה, שגיאה או ריק — רק הטבלה ידעה
          לעשות את זה, ולכן חודש בלי נתונים נראה כמו דף שנשבר. */}
      {isLoading ? (
        <SkeletonList rows={6} />
      ) : error ? (
        <ErrorState error={error} onRetry={() => void refetch()} />
      ) : viewMode === 'table' ? (
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
          title="אין רשומות נוכחות בחודש הזה"
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

      <AttendanceEntryDrawer row={selected} onClose={() => setSelected(null)} />
      {adding && <ManualEntryModal onClose={() => setAdding(false)} />}
    </div>
  )
}

/**
 * שורת משמרת אחת.
 *
 * הפריסה משתנה ברוחב במקום להתכווץ: במסך צר התאריך והסטטוס יושבים בשורה
 * אחת והשעות מתחתיה, ובמסך רחב הכול בשורה. קודם זו הייתה רשת של 12 עמודות
 * בכל הרוחבים, ובטלפון היא נמעכה.
 */
function ShiftCard({
  view: d,
  showName,
  showOvertime,
  clickable,
  onOpen,
}: {
  view: ShiftRowView
  showName: boolean
  showOvertime: boolean
  clickable: boolean
  onOpen: () => void
}) {
  const tone = SHIFT_STATUS[d.status]
  const isRest = d.status === 'rest'

  return (
    <div
      role={clickable ? 'button' : undefined}
      tabIndex={clickable ? 0 : undefined}
      onClick={clickable ? onOpen : undefined}
      onKeyDown={clickable ? (e) => (e.key === 'Enter' || e.key === ' ') && (e.preventDefault(), onOpen()) : undefined}
      className={cx(
        'surface flex flex-wrap items-center gap-x-4 gap-y-2 px-4 py-3 transition-colors',
        isRest && 'bg-subtle/40',
        clickable && 'cursor-pointer hover:border-line-strong hover:bg-subtle/60 focus-visible:outline-none focus-visible:focus-ring',
      )}
    >
      {/* תאריך + יום */}
      <div className="flex min-w-32 items-center gap-2.5">
        <span className={cx('size-2.5 shrink-0 rounded-full', tone.dot)} aria-hidden />
        <span className="min-w-0">
          <span className="block type-body font-semibold tabular" dir="ltr">
            {d.formattedDate}
          </span>
          <span className="block type-caption text-ink-tertiary">
            יום {d.hebrewDayLetter}
            {d.shiftLabel && ` · ${d.shiftLabel}`}
          </span>
        </span>
      </div>

      {/* שעון ומיקום */}
      <div className="min-w-40 flex-1">
        {showName && d.employeeName && (
          <p className="truncate type-caption font-semibold text-ink-tertiary">{d.employeeName}</p>
        )}
        <p className="type-body font-medium tabular" dir="ltr">
          {d.shiftTime}
        </p>
        {d.location && (
          <p className="flex items-center gap-1 type-caption text-ink-tertiary">
            <MapPin size={ICON.xs} strokeWidth={STROKE} />
            {d.location}
          </p>
        )}
      </div>

      {/* שעות */}
      <div className="min-w-20 text-end">
        <p className="type-title tabular">{d.hoursText}</p>
        {showOvertime && d.overtimeText && (
          <p className="type-caption text-warning-text">{d.overtimeText}</p>
        )}
      </div>

      {/* בונוס וסטטוס */}
      <div className="flex min-w-24 items-center justify-end gap-2">
        {d.bonus != null && (
          <span
            className="inline-flex items-center gap-1 rounded-lg border border-accent-200 bg-accent-50 px-2 py-0.5 type-caption font-bold text-accent-700 dark:border-accent-800 dark:bg-accent-950/50 dark:text-accent-300"
            title={d.row?.bonus_note ?? 'בונוס למשמרת'}
          >
            <Banknote size={ICON.xs} strokeWidth={STROKE} />
            {fmtMoney(d.bonus)}
          </span>
        )}
        {tone.label ? (
          <span className={cx('inline-flex items-center rounded-lg border px-2.5 py-1 type-caption font-bold', tone.pill)}>
            {tone.label}
          </span>
        ) : (
          <span className="type-caption text-ink-tertiary">—</span>
        )}
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
