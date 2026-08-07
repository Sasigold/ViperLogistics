import { useMemo, useState } from 'react'
import { useMutation } from '@tanstack/react-query'
import {
  Briefcase,
  CalendarCheck,
  ChevronDown,
  Download,
  ChevronLeft,
  ChevronRight,
  Clock,
  ICON,
  MapPin,
  Plus,
  PlusCircle,
  SlidersHorizontal,
  STROKE,
  LayoutGrid,
  List,
} from '../../components/ui/icons'
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

export default function AttendanceReportPage() {
  return (
    <RequirePermission perm={PERM.ATTENDANCE_VIEW_OWN}>
      <AttendanceReport />
    </RequirePermission>
  )
}

/**
 * דוח נוכחות עובדים - מעוצב מחדש לפי העיצוב המבוקש
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

  const toast = useToast()

  // Month navigation state
  const [monthDate, setMonthDate] = useState(() => startOfMonth(new Date()))
  const [showFilters, setShowFilters] = useState(false)
  const [viewMode, setViewMode] = useState<'cards' | 'table'>('cards')

  // Date range derived from month
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
    () => (canSeeAll ? staff.map((p) => ({ id: p.id, label: p.full_name })) : contractorStaff.map((p) => ({ id: p.id, label: p.full_name }))),
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

  const handlePrevMonth = () => setMonthDate((d) => subMonths(d, 1))
  const handleNextMonth = () => setMonthDate((d) => addMonths(d, 1))

  const monthName = HEBREW_MONTH_NAMES[monthDate.getMonth()]
  const yearStr = monthDate.getFullYear()
  const dateRangeStr = `${format(startOfMonth(monthDate), 'dd.MM.yyyy')} - ${format(endOfMonth(monthDate), 'dd.MM.yyyy')}`

  const todayISO = useMemo(() => toISODate(new Date()), [])

  /**
   * שורה אחת לכל משמרת, לא לכל יום.
   *
   * יום עם שתי משמרות — יציאה לשטח בבוקר וחזרה למחסן בערב, או שתי משימות
   * שהפער ביניהן גדול מ-merge_gap_minutes — הוא מקרה רגיל ולא חריג, וכל
   * משמרת היא רשומה משלה: שעות משלה, סטטוס משלו ואישור נפרד. כשהיום קופל
   * לשורה אחת נלקחו השעות של כולן והשעון והסטטוס של הראשונה בלבד, וגם
   * הקליק פתח תמיד את הראשונה.
   *
   * `seq` הוא המספור של השרת בתוך היום, ולכן גם סדר התצוגה וגם התווית.
   * ימים בלי משמרת ממשיכים לתפוס שורה, כדי שהחודש יישאר רציף.
   */
  const shiftRows = useMemo(() => {
    const start = startOfMonth(monthDate)
    const end = endOfMonth(monthDate)

    return eachDayOfInterval({ start, end }).flatMap((day) => {
      const dateStr = toISODate(day)
      const dayOfWeek = day.getDay()
      const formattedDate = format(day, 'dd.MM.yy')
      const hebrewDayLetter = HEBREW_DAY_LETTERS[dayOfWeek]
      const base = { formattedDate, hebrewDayLetter }

      const dayRows = rows
        .filter((r) => r.work_date === dateStr)
        .sort((a, b) => a.seq - b.seq || a.clock_in_at.localeCompare(b.clock_in_at))

      if (dayRows.length > 0) {
        return dayRows.map((r) => {
          const clockIn = new Date(r.clock_in_at)
          const clockOut = r.clock_out_at ? new Date(r.clock_out_at) : null
          const overtime = r.pay?.overtime_hours ?? 0
          return {
            ...base,
            key: r.id,
            shiftLabel: dayRows.length > 1 ? `משמרת ${r.seq}` : null,
            employeeName: r.full_name,
            shiftTime: `${fmtTime(clockIn.toTimeString())} - ${clockOut ? fmtTime(clockOut.toTimeString()) : '…'}`,
            location: r.work_site
              ? WORK_SITE_LABELS[r.work_site]
              : r.contractor_id
              ? 'מחסן ראשי'
              : 'מרכז לוגיסטי',
            hoursText: fmtDurationHHMM(r.actual_hours, true),
            overtimeText: overtime > 0 ? `${fmtDurationHHMM(overtime, true)} נוספות` : null,
            status: r.status === 'approved' ? 'completed' : r.status,
            row: r,
            hours: r.actual_hours ?? 0,
          }
        })
      }

      // יום חול שעבר ואין בו החתמה. שבת אינה יום עבודה, ולכן היא "מנוחה".
      const isPastOrToday = dateStr <= todayISO
      const isWorkDay = dayOfWeek !== 6
      return [
        {
          ...base,
          key: dateStr,
          shiftLabel: null,
          employeeName: null,
          shiftTime: '-',
          location: null,
          hoursText: '-',
          overtimeText: null,
          status: isPastOrToday && isWorkDay ? 'absence' : 'rest',
          row: null,
          hours: 0,
        },
      ]
    })
  }, [monthDate, rows, todayISO])

  // Calculated metrics
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

  // Data table columns for classic mode
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
          <div className="flex flex-wrap gap-1">
            {r.status !== 'approved' && <Badge tone={STATUS_TONES[r.status]}>{STATUS_LABELS[r.status]}</Badge>}
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
  }, [showMoney, showEmployeeFilter, showOvertime])

  return (
    <div className="space-y-6 max-w-5xl mx-auto pb-12">
      {/* Page Header */}
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

      {/* Month Navigation Control */}
      <div className="flex flex-col items-center justify-center my-2">
        <div className="flex items-center gap-3 bg-white dark:bg-slate-900 border border-slate-200/90 dark:border-slate-800 rounded-full px-5 py-2 shadow-xs hover:shadow-md transition-shadow">
          <button
            onClick={handlePrevMonth}
            className="w-8 h-8 rounded-full flex items-center justify-center text-slate-500 hover:text-blue-600 hover:bg-blue-50 dark:hover:bg-slate-800 transition-colors"
            title="חודש קודם"
          >
            <ChevronRight size={20} />
          </button>

          <div className="flex items-center gap-2 font-bold text-slate-900 dark:text-white text-lg">
            <span>
              {monthName} {yearStr}
            </span>
            <ChevronDown size={18} className="text-slate-400" />
          </div>

          <button
            onClick={handleNextMonth}
            className="w-8 h-8 rounded-full flex items-center justify-center text-slate-500 hover:text-blue-600 hover:bg-blue-50 dark:hover:bg-slate-800 transition-colors"
            title="חודש הבא"
          >
            <ChevronLeft size={20} />
          </button>
        </div>
        <span className="text-xs text-slate-400 font-medium mt-1.5 dir-ltr tracking-wide">{dateRangeStr}</span>
      </div>

      {/* סיכום החודש: מה שנמדד, בלי מה שנגזר ממנו */}
      <div className="bg-white dark:bg-slate-900 rounded-3xl border border-slate-200/80 dark:border-slate-800 p-6 md:p-8 shadow-xs">
        <div className={cx('grid gap-y-6 gap-x-4', showOvertime ? 'grid-cols-2 md:grid-cols-4' : 'grid-cols-3')}>
          <div className="flex flex-col items-center text-center">
            <div className="flex items-center justify-center gap-1.5 text-xs text-slate-500 dark:text-slate-400 font-semibold mb-1">
              <Clock size={15} className="text-blue-500" />
              <span>סה"כ שעות עבודה</span>
            </div>
            <span className="text-2xl font-black text-slate-900 dark:text-white tracking-tight tabular-nums">
              {fmtDurationHHMM(totalWorkHours)}
            </span>
          </div>

          <div className="flex flex-col items-center text-center">
            <div className="flex items-center justify-center gap-1.5 text-xs text-slate-500 dark:text-slate-400 font-semibold mb-1">
              <CalendarCheck size={15} className="text-blue-500" />
              <span>שעות רגילות</span>
            </div>
            <span className="text-2xl font-black text-slate-900 dark:text-white tracking-tight tabular-nums">
              {fmtDurationHHMM(regularHours)}
            </span>
          </div>

          {showOvertime && (
            <div className="flex flex-col items-center text-center">
              <div className="flex items-center justify-center gap-1.5 text-xs text-slate-500 dark:text-slate-400 font-semibold mb-1">
                <PlusCircle size={15} className="text-blue-500" />
                <span>שעות נוספות</span>
              </div>
              <span className="text-2xl font-black text-slate-900 dark:text-white tracking-tight tabular-nums">
                {fmtDurationHHMM(overtimeHours)}
              </span>
            </div>
          )}

          <div className="flex flex-col items-center text-center">
            <div className="flex items-center justify-center gap-1.5 text-xs text-slate-500 dark:text-slate-400 font-semibold mb-1">
              <Briefcase size={15} className="text-blue-500" />
              <span>ימי עבודה</span>
            </div>
            <span className="text-2xl font-black text-slate-900 dark:text-white tracking-tight tabular-nums">
              {workDaysCount}
            </span>
          </div>
        </div>
      </div>

      {/* Filter drawer / filter section */}
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

      {/* Daily Breakdown Section Header */}
      <div className="flex items-center justify-between pt-2">
        <h3 className="text-xl font-extrabold text-slate-900 dark:text-white">פירוט לפי יום</h3>

        <div className="flex items-center gap-2">
          {showEmployeeFilter && (
            <div className="w-48 hidden sm:block">
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

          <div className="flex border border-slate-200 dark:border-slate-800 rounded-full p-0.5 bg-slate-100 dark:bg-slate-800">
            <button
              onClick={() => setViewMode('cards')}
              className={cx(
                'px-3 py-1 text-xs font-semibold rounded-full transition-colors flex items-center gap-1',
                viewMode === 'cards'
                  ? 'bg-white dark:bg-slate-900 text-blue-600 dark:text-blue-400 shadow-xs'
                  : 'text-slate-500 hover:text-slate-900'
              )}
            >
              <LayoutGrid size={13} />
              <span>כרטיסים</span>
            </button>
            <button
              onClick={() => setViewMode('table')}
              className={cx(
                'px-3 py-1 text-xs font-semibold rounded-full transition-colors flex items-center gap-1',
                viewMode === 'table'
                  ? 'bg-white dark:bg-slate-900 text-blue-600 dark:text-blue-400 shadow-xs'
                  : 'text-slate-500 hover:text-slate-900'
              )}
            >
              <List size={13} />
              <span>טבלה</span>
            </button>
          </div>

          <Button
            variant={showFilters ? 'primary' : 'outlined'}
            size="sm"
            onClick={() => setShowFilters(!showFilters)}
            className="rounded-full px-4 gap-1.5"
          >
            <SlidersHorizontal size={14} />
            <span>סינון</span>
          </Button>
        </div>
      </div>

      {/* Main List / Table View */}
      {viewMode === 'cards' ? (
        <div className="space-y-2.5">
          {/* Table Header Labels */}
          <div className="grid grid-cols-12 gap-2 px-5 py-2 text-xs font-bold text-slate-500 dark:text-slate-400">
            <div className="col-span-3 sm:col-span-2 flex items-center gap-1">
              <span>תאריך</span>
              <ChevronDown size={14} className="text-slate-400" />
            </div>
            <div className="col-span-1 text-center">יום</div>
            <div className="col-span-4 sm:col-span-4 text-center">סוג משמרת</div>
            <div className="col-span-2 sm:col-span-3 text-center">שעות</div>
            <div className="col-span-2 sm:col-span-2 text-left">סטטוס</div>
          </div>

          {/* שורה למשמרת ולא ליום: יום עם כמה משמרות מופיע כמה פעמים, כל אחת
              עם השעות והסטטוס שלה, וקליק שפותח אותה ולא את הראשונה */}
          {shiftRows.map((d) => {
            const isCompleted = d.status === 'completed' || d.status === 'approved'
            const isAbsence = d.status === 'absence'
            const isPending = d.status === 'pending'
            const isRest = d.status === 'rest'

            return (
              <div
                key={d.key}
                onClick={() => d.row && (canEdit || canApprove) && setSelected(d.row)}
                className={cx(
                  'grid grid-cols-12 gap-2 items-center px-5 py-3.5 bg-white dark:bg-slate-900 border border-slate-200/70 dark:border-slate-800 rounded-2xl transition-all shadow-2xs hover:shadow-md',
                  d.row && (canEdit || canApprove) && 'cursor-pointer hover:border-blue-300 dark:hover:border-blue-700'
                )}
              >
                {/* Date Column */}
                <div className="col-span-3 sm:col-span-2 flex items-center gap-2">
                  <span
                    className={cx(
                      'w-2.5 h-2.5 rounded-full flex-shrink-0',
                      isCompleted && 'bg-emerald-500 shadow-xs shadow-emerald-500/50',
                      isAbsence && 'bg-rose-500 shadow-xs shadow-rose-500/50',
                      isPending && 'bg-amber-500 shadow-xs shadow-amber-500/50',
                      isRest && 'bg-slate-300 dark:bg-slate-700'
                    )}
                  />
                  <span className="min-w-0">
                    <span className="block font-bold text-slate-800 dark:text-slate-100 text-sm dir-ltr">
                      {d.formattedDate}
                    </span>
                    {d.shiftLabel && (
                      <span className="block text-[11px] font-semibold text-slate-400 dark:text-slate-500">
                        {d.shiftLabel}
                      </span>
                    )}
                  </span>
                  <ChevronLeft size={14} className="text-slate-400 hidden sm:block mr-auto" />
                </div>

                {/* Day Column */}
                <div className="col-span-1 text-center font-bold text-slate-700 dark:text-slate-300 text-sm">
                  {d.hebrewDayLetter}
                </div>

                {/* Shift Type Column */}
                <div className="col-span-4 sm:col-span-4 flex flex-col items-center justify-center text-center">
                  {/* בדוח של כמה עובדים אותו יום מופיע פעם לכל אחד, ובלי השם
                      אי אפשר לדעת של מי המשמרת */}
                  {showEmployeeFilter && d.employeeName && (
                    <span className="max-w-full truncate text-[11px] font-bold text-slate-500 dark:text-slate-400">
                      {d.employeeName}
                    </span>
                  )}
                  <span className="font-semibold text-slate-800 dark:text-slate-200 text-sm dir-ltr">
                    {d.shiftTime}
                  </span>
                  {d.location ? (
                    <div className="flex items-center justify-center gap-1 text-xs text-slate-500 dark:text-slate-400 mt-0.5 font-medium">
                      <MapPin size={11} className="text-slate-400" />
                      <span>{d.location}</span>
                    </div>
                  ) : (
                    <span className="text-slate-400 dark:text-slate-600 text-xs">-</span>
                  )}
                </div>

                {/* Hours Column */}
                <div className="col-span-2 sm:col-span-3 flex flex-col items-center justify-center text-center">
                  <span className="font-bold text-slate-900 dark:text-white text-sm tabular-nums">
                    {d.hoursText}
                  </span>
                  {showOvertime && d.overtimeText && (
                    <span className="text-[11px] font-semibold text-slate-400 dark:text-slate-400 mt-0.5">
                      {d.overtimeText}
                    </span>
                  )}
                </div>

                {/* Status Column */}
                <div className="col-span-2 sm:col-span-2 flex justify-end">
                  {isCompleted && (
                    <span className="inline-flex items-center px-3 py-1 rounded-xl text-xs font-extrabold bg-emerald-50 text-emerald-700 dark:bg-emerald-950/60 dark:text-emerald-300 border border-emerald-200/70 dark:border-emerald-800/50">
                      הושלם
                    </span>
                  )}
                  {isAbsence && (
                    <span className="inline-flex items-center px-3 py-1 rounded-xl text-xs font-extrabold bg-rose-50 text-rose-700 dark:bg-rose-950/60 dark:text-rose-300 border border-rose-200/70 dark:border-rose-800/50">
                      היעדרות
                    </span>
                  )}
                  {isPending && (
                    <span className="inline-flex items-center px-3 py-1 rounded-xl text-xs font-extrabold bg-amber-50 text-amber-700 dark:bg-amber-950/60 dark:text-amber-300 border border-amber-200/70 dark:border-amber-800/50">
                      ממתין
                    </span>
                  )}
                  {isRest && (
                    <span className="text-xs text-slate-400 dark:text-slate-600 font-medium px-2 py-1">
                      -
                    </span>
                  )}
                </div>
              </div>
            )
          })}
        </div>
      ) : (
        <DataTable
          rows={rows}
          columns={columns}
          getRowId={(r) => r.id}
          loading={isLoading}
          error={error ? errorMessage(error) : undefined}
          onRetry={() => void refetch()}
          empty="לא נמצאו רשומות נוכחות בטווח הזה"
          onRowClick={canEdit || canApprove ? (r) => setSelected(r) : undefined}
          storageKey="attendance-report"
          pageSize={50}
        />
      )}

      {/* Entry Drawer & Manual Modal */}
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
