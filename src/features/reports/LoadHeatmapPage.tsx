import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Bar, BarChart, Cell, ReferenceLine, Tooltip, XAxis, YAxis } from 'recharts'
import { addMonths, endOfMonth, isSameMonth, startOfMonth } from 'date-fns'
import {
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  PageHeader,
  SegmentedControl,
  Skeleton,
  StatCard,
  Tooltip as UiTooltip,
} from '../../components/ui'
import {
  Activity,
  AlertTriangle,
  Clock,
  Crown,
  Flame,
  HardHat,
  ICON,
  MapPin,
  STROKE,
  Settings,
  Truck,
  UserPlus,
  Users,
  Warehouse,
} from '../../components/ui/icons'
import { fmtDate, fmtDateLong, fmtWeekdayShort, toISODate } from '../../lib/dates'
import { shortAddress } from '../../lib/address'
import { errorMessage } from '../../lib/errors'
import { PERM } from '../../lib/permissions'
import { supabase } from '../../lib/supabase'
import { useContractors } from '../../lib/queries'
import { RequirePermission } from '../auth/guards'
import { MonthStepper } from '../dashboard/MonthStepper'
import { ChartFrame } from '../dashboard/parts/ChartFrame'
import { CapacitySettingsDialog } from './CapacitySettingsDialog'
import {
  LOAD_BANDS,
  LOAD_DIMENSIONS,
  busiestHour,
  dayCounts,
  hourCounts,
  hourExtent,
  hourLabel,
  loadMark,
  loadPaint,
  loadScore,
  monthGrid,
  monthSummary,
} from './loadScale'
import type {
  LoadCapacity,
  LoadDay,
  LoadDayResult,
  LoadHeatmapResult,
  LoadHour,
  LoadScope,
  LoadTask,
} from '../../types/domain'

/**
 * מפת העומסים (0173).
 *
 * חודש של תאים, ותא אחד נפתח לעשרים וארבע שעות. שתי התצוגות עונות על שתי
 * שאלות שונות: **"מתי אני עמוס"** — שהיא שאלה על החודש, ונענית בצבע — ו-
 * **"באיזו שעה, ובגלל מה"**, שהיא שאלה על היום ונענית בעמודות ובשמות.
 *
 * כל מספר כאן מגיע מהשרת; המסך מחשב **אחוזים בלבד**, מול התקרה שהשרת שלח
 * באותה תשובה. כך "היום העמוס" בכרטיס ו"התא הכהה" ברשת אינם יכולים
 * להיפרד — הם אותו חישוב על אותם נתונים.
 */

export default function LoadHeatmapPage() {
  return (
    <RequirePermission perm={PERM.REPORTS_LOAD}>
      <LoadHeatmapScreen />
    </RequirePermission>
  )
}

function LoadHeatmapScreen() {
  const [month, setMonth] = useState(() => startOfMonth(new Date()))
  const [selected, setSelected] = useState<string | null>(() => toISODate(new Date()))
  const [scope, setScope] = useState<LoadScope>('internal')
  const [selectedContractorId, setSelectedContractorId] = useState<string | null>(null)
  const [settingsOpen, setSettingsOpen] = useState(false)

  const { data: contractors = [] } = useContractors()
  const activeContractors = useMemo(() => contractors.filter((c) => c.is_active), [contractors])
  const currentContractor = useMemo(
    () => activeContractors.find((c) => c.id === selectedContractorId),
    [activeContractors, selectedContractorId],
  )

  const from = toISODate(startOfMonth(month))
  const to = toISODate(endOfMonth(month))

  const contractorIdParam = scope === 'contractor' ? selectedContractorId : null

  const map = useQuery({
    queryKey: ['load_heatmap', from, to, scope, contractorIdParam],
    queryFn: async (): Promise<LoadHeatmapResult> => {
      const { data, error } = await supabase.rpc('load_heatmap', {
        p_from: from,
        p_to: to,
        p_scope: scope,
        p_contractor_id: contractorIdParam,
      })
      if (error) throw error
      return data as LoadHeatmapResult
    },
  })

  const capacity = map.data?.meta?.capacity
  const days = map.data?.days ?? null
  const summary = useMemo(() => monthSummary(days ?? [], capacity), [days, capacity])

  const stepMonth = (delta: number) => {
    const next = startOfMonth(addMonths(month, delta))
    setMonth(next)
    setSelected(toISODate(isSameMonth(next, new Date()) ? new Date() : next))
  }

  const body = () => {
    if (map.error)
      return <EmptyState art="alert" title="שגיאה בטעינת מפת העומסים" description={errorMessage(map.error)} />
    if (map.isLoading) return <Skeleton className="h-96 w-full" />
    if (!days)
      return (
        <EmptyState
          art="table"
          title="הנתון אינו זמין בהרשאות שלך"
          description="מפת עומסים נמדדת מול הקיבולת של כל העסק, ולכן היא דורשת היקף נתונים מלא על המשימות"
        />
      )
    return (
      <>
        <SummaryTiles
          summary={summary}
          capacity={capacity}
          scope={scope}
          contractorName={currentContractor?.name}
          onOpenSettings={() => setSettingsOpen(true)}
        />
        <MonthHeatmap
          month={month}
          days={days}
          capacity={capacity}
          selected={selected}
          onSelect={setSelected}
        />
        {selected && (
          <DayPanel
            date={selected}
            scope={scope}
            contractorId={contractorIdParam}
            contractorName={currentContractor?.name}
          />
        )}
      </>
    )
  }

  return (
    <div className="space-y-4">
      <PageHeader
        title="מפת עומסים"
        subtitle={
          scope === 'contractor'
            ? `עומס מחושב עבור קבלן: ${currentContractor?.name || 'בחר קבלן'} — מול העובדים והמשימות שלו`
            : scope === 'internal'
              ? 'עומס מחושב עבור הצוות הפנימי בלבד (משימות קבלן אינן מעמיסות על הצוות)'
              : 'כמה רץ באותו רגע, מול מה שאפשר להפעיל — לפי היום הצפוף ולפי השעה שבתוכו'
        }
        actions={
          <div className="flex items-center gap-2">
            <Button
              variant="outlined"
              size="sm"
              onClick={() => setSettingsOpen(true)}
              className="gap-1.5"
            >
              <Settings size={ICON.xs} />
              הגדרת קיבולת
            </Button>
            <MonthStepper
              month={month}
              onStep={stepMonth}
              onToday={() => {
                setMonth(startOfMonth(new Date()))
                setSelected(toISODate(new Date()))
              }}
              atToday={isSameMonth(month, new Date())}
            />
          </div>
        }
      />

      {/* בורר בסיס החישוב */}
      <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-line bg-surface p-2.5 shadow-sm">
        <div className="flex flex-wrap items-center gap-3">
          <span className="type-caption font-semibold text-ink-secondary ms-1">חישוב עומסים לפי:</span>
          <SegmentedControl
            items={[
              { key: 'internal', label: '🏢 צוות פנימי בלבד' },
              { key: 'contractor', label: '🤝 קבלן ספציפי' },
              { key: 'all', label: '🌐 כללי (הכל יחד)' },
            ]}
            value={scope}
            onChange={(val) => {
              const newScope = val as LoadScope
              setScope(newScope)
              if (newScope === 'contractor' && !selectedContractorId && activeContractors[0]) {
                setSelectedContractorId(activeContractors[0].id)
              }
            }}
          />

          {scope === 'contractor' && (
            <div className="flex items-center gap-2">
              <span className="type-caption text-ink-tertiary">קבלן:</span>
              <select
                aria-label="בחר קבלן לבדיקת עומס"
                value={selectedContractorId ?? ''}
                onChange={(e) => setSelectedContractorId(e.target.value || null)}
                className="h-8 rounded-lg border border-line bg-surface px-2.5 type-caption font-semibold text-ink focus:outline-none focus:ring-2 focus:ring-primary/20"
              >
                {activeContractors.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>
            </div>
          )}
        </div>

        <div className="type-caption text-ink-tertiary">
          {scope === 'internal' && 'משימות שהועברו לקבלנים אינן נספרות כעומס פנימי'}
          {scope === 'contractor' && currentContractor && `מציג משימות ועומס של ${currentContractor.name}`}
          {scope === 'all' && 'משקלל את כל המשימות בכלל המערכת'}
        </div>
      </div>

      {body()}

      <CapacitySettingsDialog
        open={settingsOpen}
        onClose={() => setSettingsOpen(false)}
      />
    </div>
  )
}

/* ===== הסיכום החודשי ====================================================== */

function SummaryTiles({
  summary,
  capacity,
  scope,
  contractorName,
  onOpenSettings,
}: {
  summary: ReturnType<typeof monthSummary>
  capacity: LoadCapacity | undefined
  scope: LoadScope
  contractorName?: string
  onOpenSettings?: () => void
}) {
  const busiest = summary.busiest
  const topDim = LOAD_DIMENSIONS.find((d) => d.key === summary.topBottleneck)

  const gapHint =
    scope === 'contractor'
      ? `${summary.totalTasks} משימות לקבלן בחודש`
      : summary.untimed > 0
        ? `${summary.delegated} משימות הואצלו · ${summary.untimed} ללא שעה`
        : `${summary.delegated} משימות הואצלו לקבלנים`

  return (
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
      <StatCard
        icon={<Flame size={ICON.xl} strokeWidth={STROKE} />}
        label="היום העמוס בחודש"
        value={busiest ? `${busiest.score.pct}%` : '—'}
        tone="#ef4444"
        hint={
          busiest
            ? `${fmtDate(busiest.day.day)}${
                busiest.day.peak_hour != null ? ` · בשיא ב-${hourLabel(busiest.day.peak_hour)}` : ''
              }`
            : 'אין עבודה מתוזמנת בחודש'
        }
      />
      <StatCard
        icon={<Activity size={ICON.xl} strokeWidth={STROKE} />}
        label="עומס ממוצע ביום פעיל"
        value={`${summary.avgPeakPct}%`}
        hint={`${summary.activeDays} ימים עם עבודה · ${summary.totalTasks} משימות${
          summary.untimed > 0 ? ` (${summary.untimed} ללא שעה)` : ''
        }`}
      />
      <StatCard
        icon={<AlertTriangle size={ICON.xl} strokeWidth={STROKE} />}
        label="ימים מעל הקיבולת"
        value={summary.overDays}
        tone="#f59e0b"
        hint={topDim ? `הצוואר הנפוץ: ${topDim.bottleneckLabel}` : 'אף יום לא עבר את התקרה'}
      />
      <StatCard
        icon={<UserPlus size={ICON.xl} strokeWidth={STROKE} />}
        label="תקנים שטרם אוישו"
        value={summary.gap}
        tone="#8b5cf6"
        hint={gapHint}
      />
      <StaffingNote summary={summary} />
      {capacity && (
        <CapacityNote
          capacity={capacity}
          scope={scope}
          contractorName={contractorName}
          onOpenSettings={onOpenSettings}
        />
      )}
    </div>
  )
}

/**
 * שובץ מתוך נדרש.
 *
 * העומס עצמו נמדד מול ה**דרישה** — היא מה שהחודש מחייב, והיא אינה יורדת
 * כשמישהו משבץ. אבל "‏12 ראשי צוות נדרשים" בלי לומר כמה מהם כבר יש הוא
 * מספר שאי אפשר לדעת ממנו מה נשאר לעשות, ולכן שני המספרים יושבים יחד —
 * ומה שחסר נאמר במפורש ולא מושאר לחיסור.
 */
function StaffingNote({ summary }: { summary: ReturnType<typeof monthSummary> }) {
  const rows = [
    { key: 'workers', label: 'עובדים', icon: Users, need: summary.need.workers, got: summary.staffed.workers },
    { key: 'leads', label: 'ראשי צוות', icon: Crown, need: summary.need.leads, got: summary.staffed.leads },
    { key: 'trucks', label: 'משאיות', icon: Truck, need: summary.need.trucks, got: summary.staffed.trucks },
  ]
  if (rows.every((r) => r.need === 0)) return null

  return (
    <div className="sm:col-span-2 lg:col-span-4">
      <Card padded className="flex flex-wrap items-center gap-x-5 gap-y-2">
        <span className="type-caption font-semibold text-ink-tertiary">
          נדרש החודש, ומה ששובץ מתוכו:
        </span>
        {rows.map((r) => {
          const missing = Math.max(r.need - r.got, 0)
          return (
            <span key={r.key} className="inline-flex items-center gap-1.5 type-caption text-ink-secondary">
              <r.icon size={ICON.xs} strokeWidth={STROKE} aria-hidden />
              {r.label}
              <span className="font-bold tabular text-ink" dir="ltr">
                {r.got}/{r.need}
              </span>
              {missing > 0 && <Badge tone="warning">חסרים {missing}</Badge>}
            </span>
          )
        })}
      </Card>
    </div>
  )
}

/**
 * מאין בא המכנה.
 *
 * בלי השורה הזו האחוזים נראים סמכותיים יותר ממה שהם: תקרה שנגזרה מהמאגר
 * היא ניחוש מושכל, ותקרה שהמשרד נקב בה היא הכרעה. שתיהן לגיטימיות, ואסור
 * שייראו אותו דבר.
 */
function CapacityNote({
  capacity,
  scope,
  contractorName,
  onOpenSettings,
}: {
  capacity: LoadCapacity
  scope: LoadScope
  contractorName?: string
  onOpenSettings?: () => void
}) {
  const derived = LOAD_DIMENSIONS.filter((d) => capacity.source?.[d.capacityKey] === 'derived')
  const scopeLabel =
    scope === 'internal'
      ? 'צוות פנימי בלבד'
      : scope === 'contractor'
        ? `קבלן: ${contractorName || 'קבלן'}`
        : 'כללי (פנימי + קבלנים)'

  const dimensionsToShow =
    scope === 'contractor'
      ? LOAD_DIMENSIONS.filter((d) => (capacity[d.capacityKey] ?? 0) > 0 || d.key === 'workers')
      : LOAD_DIMENSIONS

  return (
    <div className="sm:col-span-2 lg:col-span-4">
      <Card padded className="flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
        <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
          <span className="type-caption font-semibold text-ink-tertiary">
            הקיבולת שמולה נמדד העומס ({scopeLabel}):
          </span>
          {dimensionsToShow.map((d) => (
            <span key={d.key} className="inline-flex items-center gap-1.5 type-caption text-ink-secondary">
              <span className="font-bold tabular text-ink">{capacity[d.capacityKey]}</span>
              {d.label}
              {capacity.source?.[d.capacityKey] === 'derived' && (
                <Badge tone="neutral">נגזר</Badge>
              )}
            </span>
          ))}
          {derived.length > 0 && (
            <span className="type-caption text-ink-tertiary">
              ‏"נגזר" = נספר מהמאגר הפעיל. אפשר להגדיר מספר מדויק ב"הגדרת קיבולת".
            </span>
          )}
        </div>

        {onOpenSettings && (
          <Button variant="outlined" size="sm" onClick={onOpenSettings} className="gap-1.5 ms-auto">
            <Settings size={ICON.xs} />
            הגדרת קיבולת
          </Button>
        )}
      </Card>
    </div>
  )
}

/* ===== המפה החודשית ======================================================= */

const WEEKDAYS = ['א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ש']

function MonthHeatmap({
  month,
  days,
  capacity,
  selected,
  onSelect,
}: {
  month: Date
  days: LoadDay[]
  capacity: LoadCapacity | undefined
  selected: string | null
  onSelect: (day: string) => void
}) {
  const weeks = useMemo(() => monthGrid(month, days), [month, days])
  const today = toISODate(new Date())

  return (
    <Card>
      <CardHeader
        title="החודש"
        subtitle="הצבע הוא הפסגה של היום — כמה רץ באותו רגע, מול הקיבולת. לחיצה פותחת את הפילוח השעתי"
        icon={<Flame size={ICON.lg} strokeWidth={STROKE} />}
        actions={<BandLegend />}
      />
      <CardBody>
        <div className="grid grid-cols-7 gap-1 sm:gap-1.5">
          {WEEKDAYS.map((w) => (
            <div key={w} className="pb-1 text-center type-caption font-semibold text-ink-tertiary">
              {w}
            </div>
          ))}
          {weeks.flatMap((week, wi) =>
            week.map((d, di) =>
              d === null ? (
                <div key={`${wi}-${di}`} aria-hidden />
              ) : (
                <HeatCell
                  key={d.day}
                  day={d}
                  capacity={capacity}
                  isToday={d.day === today}
                  isSelected={d.day === selected}
                  onSelect={onSelect}
                />
              ),
            ),
          )}
        </div>
      </CardBody>
    </Card>
  )
}

function BandLegend() {
  return (
    <div className="flex flex-wrap items-center gap-x-2.5 gap-y-1">
      {LOAD_BANDS.map((b) => {
        /* הדגימה נלקחת בתוך המדרגה ולא בגבול שלה, אחרת "תקין" ו"עמוס"
           מצוירים באותו צבע במקרא שאמור להבדיל ביניהם. */
        const sample = b.max === Infinity ? 120 : b.max === 0 ? 0 : b.max - 1
        const paint = loadPaint(sample)
        return (
          <span key={b.key} className="inline-flex items-center gap-1 type-caption text-ink-tertiary">
            <span
              aria-hidden
              className="size-3 rounded-sm border"
              style={{ background: paint.background, borderColor: paint.border }}
            />
            {b.label}
          </span>
        )
      })}
    </div>
  )
}

function HeatCell({
  day,
  capacity,
  isToday,
  isSelected,
  onSelect,
}: {
  day: LoadDay
  capacity: LoadCapacity | undefined
  isToday: boolean
  isSelected: boolean
  onSelect: (day: string) => void
}) {
  const score = loadScore(dayCounts(day), capacity)
  const paint = loadPaint(score.pct)
  const dim = LOAD_DIMENSIONS.find((d) => d.key === score.bottleneck)
  const dayNum = Number(day.day.slice(8, 10))
  const quiet = day.tasks === 0 && day.untimed === 0

  return (
    <UiTooltip
      content={
        <span className="block space-y-0.5 text-start">
          <span className="block font-bold">
            {fmtWeekdayShort(day.day)} · {fmtDate(day.day)}
          </span>
          {quiet ? (
            <span className="block opacity-80">אין משימות</span>
          ) : (
            <>
              <span className="block opacity-90">
                עומס {score.pct}%{dim && ` — ${dim.bottleneckLabel}`}
              </span>
              <span className="block tabular opacity-80">
                {day.tasks} משימות{day.untimed > 0 && ` (${day.untimed} ללא שעה)`}
              </span>
              {/* בכל שורה: מה ששובץ מתוך מה שנדרש. המכנה הוא הדרישה, והוא
                  מה שהאחוז נמדד מולו. */}
              <span className="block tabular opacity-80" dir="ltr">
                {day.staffed}/{day.worker_need} עובדים · {day.lead_staffed}/{day.lead_need} ראשי צוות ·{' '}
                {day.truck_assigned}/{day.truck_need} משאיות
              </span>
              {day.peak_hour != null && (
                <span className="block tabular opacity-80">השיא ב-{hourLabel(day.peak_hour)}</span>
              )}
              {day.gap > 0 && <span className="block opacity-80">{day.gap} תקנים לא מאוישים</span>}
              {day.untimed > 0 && <span className="block opacity-70">{day.untimed} ללא שעה</span>}
            </>
          )}
        </span>
      }
    >
      <button
        type="button"
        onClick={() => onSelect(day.day)}
        aria-pressed={isSelected}
        aria-label={`${fmtDate(day.day)} — עומס ${score.pct}%`}
        className="relative flex aspect-square min-h-14 w-full flex-col items-center justify-center gap-0.5 rounded-lg border transition-[filter,box-shadow] hover:brightness-110 focus-visible:outline-none focus-visible:focus-ring"
        style={{
          background: paint.background,
          borderColor: isSelected ? 'var(--color-ink)' : paint.border,
          boxShadow: isSelected ? '0 0 0 2px var(--color-ink)' : undefined,
          color: paint.color,
        }}
      >
        <span className={`type-caption tabular ${isToday ? 'font-black underline' : 'font-semibold'}`}>
          {dayNum}
        </span>
        {!quiet && <span className="type-caption tabular font-bold leading-none">{score.pct}%</span>}
        {/* מעל הקיבולת נושא גם סימן ולא רק גוון — צבע לבדו אינו מידע למי
            שאינו מבחין בו, והתא הזה הוא בדיוק התא שאסור לפספס. */}
        {score.pct > 100 && (
          <AlertTriangle
            size={ICON.xs}
            strokeWidth={2.25}
            aria-hidden
            className="absolute end-1 top-1"
          />
        )}
        {day.gap > 0 && score.pct <= 100 && (
          <span
            aria-hidden
            className="absolute end-1 top-1 size-1.5 rounded-full"
            style={{ background: 'currentColor', opacity: 0.65 }}
          />
        )}
      </button>
    </UiTooltip>
  )
}

/* ===== היום ============================================================== */

/**
 * המדדים שאפשר לצייר על ציר השעות.
 *
 * מדד אחד בכל פעם, ולא כמה יחד: לעובדים, למשאיות ולמשימות יש סדרי גודל
 * שונים לגמרי, וציר משותף היה מוחץ את שניים מהם לקו שטוח. "עומס" הוא
 * ברירת המחדל מפני שהוא הנרמול שלהם — הוא היחיד שאפשר להשוות בו שעה של
 * אתמול לשעה של היום.
 */
const AXIS = { tick: { fontSize: 11, fill: 'var(--vl-text-tertiary)' }, axisLine: false, tickLine: false } as const

/* כל המדדים הם **דרישה** ולא איוש (0181), ולכן הכותרות אומרות זאת: עמודה
   שנקראת "משאיות" ומודדת את מה שנדרש היא בדיוק אי-ההבנה שהמסך הזה נועד
   לסלק. מה ששובץ נאמר בטולטיפ, לצד הדרישה. */
const HOUR_MEASURES = [
  { key: 'pct', label: 'עומס %' },
  { key: 'workers', label: 'עובדים נדרשים' },
  { key: 'tasks', label: 'משימות' },
  { key: 'trucks', label: 'משאיות נדרשות' },
  { key: 'leads', label: 'ראשי צוות נדרשים' },
] as const

type HourMeasure = (typeof HOUR_MEASURES)[number]['key']

function DayPanel({
  date,
  scope,
  contractorId,
  contractorName,
}: {
  date: string
  scope: LoadScope
  contractorId: string | null
  contractorName?: string
}) {
  const [measure, setMeasure] = useState<HourMeasure>('pct')

  const { data, isLoading, error } = useQuery({
    queryKey: ['load_day', date, scope, contractorId],
    queryFn: async (): Promise<LoadDayResult> => {
      const { data, error } = await supabase.rpc('load_day', {
        p_date: date,
        p_scope: scope,
        p_contractor_id: contractorId,
      })
      if (error) throw error
      return data as LoadDayResult
    },
  })

  const capacity = data?.meta?.capacity
  const hours = data?.hours ?? null
  const tasks = data?.tasks ?? []
  const peak = useMemo(() => busiestHour(hours ?? [], capacity), [hours, capacity])

  const extent = useMemo(() => hourExtent(hours ?? []), [hours])
  const rows = useMemo(
    () =>
      (hours ?? [])
        .filter((h) => h.hour >= extent.from && h.hour <= extent.to)
        .map((h) => ({
          hour: h.hour,
          name: hourLabel(h.hour),
          pct: loadScore(hourCounts(h), capacity).pct,
          workers: h.workers,
          tasks: h.tasks,
          trucks: h.trucks,
          leads: h.leads,
          raw: h,
        })),
    [hours, extent, capacity],
  )

  /* קו הייחוס אומר "מכאן זה מעבר ליכולת". הוא קיים רק כשיש קו כזה: במדד
     ‏"משימות" אין תקרה מוגדרת, וקו שרירותי היה ממציא גבול שאיש לא קבע. */
  const reference =
    measure === 'pct'
      ? 100
      : measure === 'workers'
        ? capacity?.workers
        : measure === 'trucks'
          ? capacity?.trucks
          : measure === 'leads'
            ? capacity?.team_leads
            : undefined

  const subtitle = peak
    ? `השעה העמוסה: ${hourLabel(peak.hour.hour)} — ${peak.score.pct}%${
        peak.score.bottleneck
          ? ` (${LOAD_DIMENSIONS.find((d) => d.key === peak.score.bottleneck)?.bottleneckLabel})`
          : ''
      }`
    : 'אין משימות מתוזמנות ביום הזה'

  if (error)
    return <EmptyState art="alert" title="שגיאה בטעינת היום" description={errorMessage(error)} />

  return (
    <div className="grid gap-4 lg:grid-cols-5">
      <div className="space-y-2 lg:col-span-3">
        {/* הבורר בשורה משלו ולא בכותרת הכרטיס: חמישה מקטעים לצד כותרת
            ותת-כותרת דוחפים את הכרטיס מעבר לרוחב של טלפון. ‏`overflow-x-auto`
            הוא הרשת מתחת — במסך צר במיוחד הוא נגלל במקום לגלוש. */}
        <div className="-mx-1 overflow-x-auto px-1 pb-0.5">
          <SegmentedControl
            items={HOUR_MEASURES.map((m) => ({ key: m.key, label: m.label }))}
            value={measure}
            onChange={setMeasure}
          />
        </div>
        <ChartFrame
          title={fmtDateLong(date)}
          subtitle={subtitle}
          height={280}
          loading={isLoading}
          empty={!isLoading && (hours === null || rows.length === 0)}
          emptyTitle={hours === null ? 'הנתון אינו זמין בהרשאות שלך' : 'אין שעות עם עבודה ביום הזה'}
        >
          <BarChart data={rows} margin={{ top: 8, right: 4, left: -18, bottom: 0 }}>
            <XAxis dataKey="name" {...AXIS} interval="preserveStartEnd" minTickGap={12} />
            <YAxis {...AXIS} allowDecimals={false} width={44} />
            <Tooltip
              cursor={{ fill: 'var(--color-hover)' }}
              content={<HourTooltip capacity={capacity} />}
            />
            {reference != null && reference > 0 && (
              <ReferenceLine
                y={reference}
                stroke="var(--color-error)"
                strokeDasharray="4 4"
                label={{
                  value: measure === 'pct' ? 'הקיבולת' : `הקיבולת (${reference})`,
                  position: 'insideTopRight',
                  fill: 'var(--color-error-text)',
                  fontSize: 11,
                }}
              />
            )}
            <Bar dataKey={measure} radius={[4, 4, 0, 0]} isAnimationActive={false}>
              {rows.map((r) => {
                /* הצבע הוא תמיד של **העומס**, גם כשהעמודה מודדת עובדים:
                   כך שעה אדומה נשארת אדומה בכל מדד, והבורר משנה את הגובה
                   ולא את המשמעות. */
                const mark = loadMark(r.pct)
                return <Cell key={r.hour} fill={mark.fill} fillOpacity={mark.opacity} />
              })}
            </Bar>
          </BarChart>
        </ChartFrame>
      </div>

      <div className="lg:col-span-2">
        <DayTasksCard
          date={date}
          tasks={tasks}
          loading={isLoading}
          denied={data?.meta?.denied}
          scope={scope}
          contractorName={contractorName}
        />
      </div>
    </div>
  )
}

function HourTooltip({
  active,
  payload,
  capacity,
}: {
  active?: boolean
  payload?: { payload?: { name: string; raw: LoadHour; pct: number } }[]
  capacity?: LoadCapacity
}) {
  const row = payload?.[0]?.payload
  if (!active || !row) return null
  const h = row.raw
  const score = loadScore(hourCounts(h), capacity)
  const dim = LOAD_DIMENSIONS.find((d) => d.key === score.bottleneck)
  return (
    <div className="rounded-lg border border-line bg-raised px-2.5 py-1.5 shadow-lg">
      <p className="type-caption font-semibold text-ink">{row.name}</p>
      {h.tasks === 0 ? (
        <p className="type-caption text-ink-secondary">אין עבודה</p>
      ) : (
        <>
          <p className="type-caption tabular text-ink-secondary">
            עומס <span className="font-bold text-ink">{score.pct}%</span>
            {dim && <span className="text-ink-tertiary"> · {dim.bottleneckLabel}</span>}
          </p>
          <p className="type-caption tabular text-ink-secondary">{h.tasks} משימות במקביל</p>
          {/* נדרש, ולצדו מה שכבר שובץ — באותו רגע. */}
          <p className="type-caption tabular text-ink-secondary" dir="ltr">
            {h.staffed}/{h.workers} עובדים · {h.leads_staffed}/{h.leads} ראשי צוות ·{' '}
            {h.trucks_assigned}/{h.trucks} משאיות
          </p>
          {h.gap > 0 && <p className="type-caption text-warning-text">{h.gap} תקנים לא מאוישים</p>}
          {h.sites > 1 && (
            <p className="type-caption text-ink-tertiary">{h.sites} אתרים במקביל</p>
          )}
          {h.warehouses > 1 && (
            <p className="type-caption text-ink-tertiary">{h.warehouses} מחסנים משלחים</p>
          )}
        </>
      )}
    </div>
  )
}

/**
 * מה שרץ ביום, ולא רק כמה.
 *
 * ‏"14:00 הוא הכי עמוס" הוא מספר שמיד אחריו באה השאלה "בגלל מה", והתשובה
 * חייבת להיות באותו מסך. הרשימה נושאת גם משימה שמתוארכת ליום אחר ונוגעת
 * ביום הזה — יציאה למחסן שנסוגה מהבוקר שאחריו, ומשימה של אתמול שנמשכת
 * אחרי חצות.
 */
function DayTasksCard({
  date,
  tasks,
  loading,
  denied,
  scope,
  contractorName,
}: {
  date: string
  tasks: LoadTask[]
  loading: boolean
  denied?: boolean
  scope?: LoadScope
  contractorName?: string
}) {
  const time = (iso: string) =>
    new Date(iso).toLocaleTimeString('he-IL', {
      hour: '2-digit',
      minute: '2-digit',
      timeZone: 'Asia/Jerusalem',
    })

  const untimed = tasks.filter((t) => !t.timed).length
  const tail = untimed > 0 ? ` · ${untimed} ללא שעה` : ''
  const subtitle =
    scope === 'contractor'
      ? `${tasks.length} משימות עבור ${contractorName || 'הקבלן'} ב-${fmtDate(date)}${tail}`
      : scope === 'internal'
        ? `${tasks.length} משימות בצוות הפנימי ב-${fmtDate(date)}${tail}`
        : `${tasks.length} משימות נוגעות ב-${fmtDate(date)}${tail}`

  return (
    <Card className="h-full">
      <CardHeader
        title="מה רץ ביום הזה"
        subtitle={subtitle}
        icon={<Clock size={ICON.lg} strokeWidth={STROKE} />}
      />
      <CardBody className="max-h-[19rem] overflow-y-auto p-3">
        {loading ? (
          <Skeleton className="h-56 w-full" />
        ) : denied || tasks.length === 0 ? (
          <EmptyState compact art="check" title="אין משימות מתוזמנות" description="יום פנוי" />
        ) : (
          <ul className="space-y-1.5">
            {tasks.map((t) => (
              <li
                key={t.task_id}
                className="flex items-start gap-2 rounded-lg border border-line-subtle p-2"
              >
                <span
                  aria-hidden
                  className="mt-0.5 h-9 w-1 shrink-0 rounded-full"
                  style={{ background: t.color ?? '#64748b' }}
                />
                <div className="min-w-0 flex-1">
                  <div className="flex items-baseline gap-1.5">
                    {/* משימה בלי שעה אינה על ציר השעות, אבל היא כן עבודה של
                        היום — ולכן היא ברשימה, ואומרת בפירוש מה חסר לה. */}
                    {t.timed && t.start && t.end ? (
                      <span className="shrink-0 type-caption font-bold tabular" dir="ltr">
                        {time(t.start)}–{time(t.end)}
                      </span>
                    ) : (
                      <Badge tone="neutral">ללא שעה</Badge>
                    )}
                    <span className="min-w-0 truncate type-body font-medium">{t.label ?? '—'}</span>
                  </div>
                  <div className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-0.5 type-caption text-ink-tertiary">
                    <span className="inline-flex items-center gap-1">
                      <Users size={ICON.xs} strokeWidth={STROKE} aria-hidden />
                      <span className="tabular">
                        {t.staffed}/{t.worker_need}
                      </span>
                    </span>
                    {(t.truck_need > 0 || t.trucks > 0) && (
                      <span className="inline-flex items-center gap-1">
                        <Truck size={ICON.xs} strokeWidth={STROKE} aria-hidden />
                        <span className="tabular" dir="ltr">
                          {t.trucks}/{t.truck_need}
                        </span>
                      </span>
                    )}
                    {t.needs_lead && (
                      <span
                        className={`inline-flex items-center gap-1 ${
                          t.lead_staffed > 0 ? '' : 'text-warning-text'
                        }`}
                      >
                        <Crown size={ICON.xs} strokeWidth={STROKE} aria-hidden />
                        {t.lead_staffed > 0 ? 'ראש צוות שובץ' : 'חסר ראש צוות'}
                      </span>
                    )}
                    {t.delegated && (
                      <span className="inline-flex items-center gap-1">
                        <HardHat size={ICON.xs} strokeWidth={STROKE} aria-hidden />
                        קבלן
                      </span>
                    )}
                    {t.site && (
                      <span className="inline-flex min-w-0 items-center gap-1">
                        <MapPin size={ICON.xs} strokeWidth={STROKE} aria-hidden />
                        <span className="truncate">{shortAddress(t.site)}</span>
                      </span>
                    )}
                    {/* משימה שמתוארכת ליום אחר ונוגעת בזה — היציאה למחסן
                        שנסוגה לערב שלפני, או משימה שנמשכה אחרי חצות. */}
                    {t.task_date !== date && (
                      <span className="inline-flex items-center gap-1 text-ink-tertiary">
                        <Warehouse size={ICON.xs} strokeWidth={STROKE} aria-hidden />
                        משימה של {fmtDate(t.task_date)}
                      </span>
                    )}
                  </div>
                </div>
                {t.staffed < t.worker_need && (
                  <Badge tone="warning">חסרים {t.worker_need - t.staffed}</Badge>
                )}
              </li>
            ))}
          </ul>
        )}
      </CardBody>
    </Card>
  )
}
