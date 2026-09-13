import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Bar, BarChart, Cell, ReferenceLine, Tooltip, XAxis, YAxis } from 'recharts'
import { addMonths, endOfMonth, isSameMonth, startOfMonth } from 'date-fns'
import {
  Badge,
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
import { RequirePermission } from '../auth/guards'
import { MonthStepper } from '../dashboard/MonthStepper'
import { ChartFrame } from '../dashboard/parts/ChartFrame'
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
  LoadTask,
} from '../../types/domain'

/**
 * מפת העומסים (0173).
 *
 * חודש של תאים, ותא אחד נפתח לעשרים וארבע שעות. שתי התצוגות עונות על שתי
 * שאלות שונות: **"מתי אני עמוס"** — שהיא שאלה על החודש, ונענית בצבע — ו-
 * **"באיזו שעה, ובגלל מה"**, שהיא שאלה על היום ונענית בעמודות ובשמות.
 *
 * המידה בשתיהן זהה, וזה מה שמאפשר להשוות ביניהן: **המרבי מבין הממדים** מול
 * התקרה (‏`loadScale.ts`), ולצדו שם הצוואר. עומס אינו ממוצע — יום שאין בו
 * ראש צוות שלישי הוא יום סגור גם כשמחצית העובדים יושבים בבית.
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

  const from = toISODate(startOfMonth(month))
  const to = toISODate(endOfMonth(month))

  const map = useQuery({
    queryKey: ['load_heatmap', from, to],
    queryFn: async (): Promise<LoadHeatmapResult> => {
      const { data, error } = await supabase.rpc('load_heatmap', { p_from: from, p_to: to })
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
    /* היום הנבחר עובר איתו: מפה של אוגוסט מתחת לפילוח של יולי היא שני
       מסכים שמראים שני דברים ומתיימרים להיות אחד. ה-1 בחודש, אלא אם זה
       החודש הנוכחי — ואז היום. */
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
        <SummaryTiles summary={summary} capacity={capacity} />
        <MonthHeatmap
          month={month}
          days={days}
          capacity={capacity}
          selected={selected}
          onSelect={setSelected}
        />
        {selected && <DayPanel date={selected} />}
      </>
    )
  }

  return (
    <div className="space-y-4">
      <PageHeader
        title="מפת עומסים"
        subtitle="כמה רץ באותו רגע, מול מה שאפשר להפעיל — לפי היום הצפוף ולפי השעה שבתוכו"
        actions={
          <MonthStepper
            month={month}
            onStep={stepMonth}
            onToday={() => {
              setMonth(startOfMonth(new Date()))
              setSelected(toISODate(new Date()))
            }}
            atToday={isSameMonth(month, new Date())}
          />
        }
      />
      {body()}
    </div>
  )
}

/* ===== הסיכום החודשי ====================================================== */

function SummaryTiles({
  summary,
  capacity,
}: {
  summary: ReturnType<typeof monthSummary>
  capacity: LoadCapacity | undefined
}) {
  const busiest = summary.busiest
  const topDim = LOAD_DIMENSIONS.find((d) => d.key === summary.topBottleneck)

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
        hint={`${summary.activeDays} ימים עם עבודה · ${summary.totalTasks} משימות`}
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
        hint={
          summary.untimed > 0
            ? `${summary.delegated} משימות הואצלו · ${summary.untimed} ללא שעה`
            : `${summary.delegated} משימות הואצלו לקבלנים`
        }
      />
      {capacity && <CapacityNote capacity={capacity} />}
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
function CapacityNote({ capacity }: { capacity: LoadCapacity }) {
  const derived = LOAD_DIMENSIONS.filter((d) => capacity.source?.[d.capacityKey] === 'derived')
  return (
    <div className="sm:col-span-2 lg:col-span-4">
      <Card padded className="flex flex-wrap items-center gap-x-4 gap-y-2">
        <span className="type-caption font-semibold text-ink-tertiary">הקיבולת שמולה נמדד העומס:</span>
        {LOAD_DIMENSIONS.map((d) => (
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
            ‏"נגזר" = נספר מהמאגר הפעיל. אפשר לקבוע מספר מדויק בהגדרות המערכת.
          </span>
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
                {day.tasks} משימות · {day.worker_need} עובדים · {day.peak_trucks} משאיות בשיא
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

const HOUR_MEASURES = [
  { key: 'pct', label: 'עומס %' },
  { key: 'workers', label: 'עובדים' },
  { key: 'tasks', label: 'משימות' },
  { key: 'trucks', label: 'משאיות' },
  { key: 'leads', label: 'ראשי צוות' },
] as const

type HourMeasure = (typeof HOUR_MEASURES)[number]['key']

function DayPanel({ date }: { date: string }) {
  const [measure, setMeasure] = useState<HourMeasure>('pct')

  const { data, isLoading, error } = useQuery({
    queryKey: ['load_day', date],
    queryFn: async (): Promise<LoadDayResult> => {
      const { data, error } = await supabase.rpc('load_day', { p_date: date })
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
        <DayTasksCard date={date} tasks={tasks} loading={isLoading} denied={data?.meta?.denied} />
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
          <p className="type-caption tabular text-ink-secondary">
            {h.tasks} משימות · {h.workers} עובדים · {h.trucks} משאיות · {h.leads} ראשי צוות
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
}: {
  date: string
  tasks: LoadTask[]
  loading: boolean
  denied?: boolean
}) {
  const time = (iso: string) =>
    new Date(iso).toLocaleTimeString('he-IL', {
      hour: '2-digit',
      minute: '2-digit',
      timeZone: 'Asia/Jerusalem',
    })

  return (
    <Card className="h-full">
      <CardHeader
        title="מה רץ ביום הזה"
        subtitle={`${tasks.length} משימות נוגעות ב-${fmtDate(date)}`}
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
                    <span className="shrink-0 type-caption font-bold tabular" dir="ltr">
                      {time(t.start)}–{time(t.end)}
                    </span>
                    <span className="min-w-0 truncate type-body font-medium">{t.label ?? '—'}</span>
                  </div>
                  <div className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-0.5 type-caption text-ink-tertiary">
                    <span className="inline-flex items-center gap-1">
                      <Users size={ICON.xs} strokeWidth={STROKE} aria-hidden />
                      <span className="tabular">
                        {t.staffed}/{t.worker_need}
                      </span>
                    </span>
                    {t.trucks > 0 && (
                      <span className="inline-flex items-center gap-1">
                        <Truck size={ICON.xs} strokeWidth={STROKE} aria-hidden />
                        <span className="tabular">{t.trucks}</span>
                      </span>
                    )}
                    {t.needs_lead && (
                      <span className="inline-flex items-center gap-1">
                        <Crown size={ICON.xs} strokeWidth={STROKE} aria-hidden />
                        ראש צוות
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
