/**
 * לוח המשמרות של הצוות.
 *
 * שני טווחים בלבד — שבוע ושלושה ימים — ושתי דרכים לצייר אותם: טבלת שיבוץ
 * (מי עובד מתי) וציר זמן לפי שעה (מי חופף למי). הטווח והלייאאוט נשמרים
 * מקומית, כי מנהל שנכנס ללוח פעמיים ביום לא אמור לבחור מחדש בכל פעם.
 *
 * המסנן של העובדים הוא היחיד שיורד לשרת: הוא מצמצם את הגזירה עצמה, שהיא
 * החלק היקר. השאר מסננים את מה שכבר הגיע, כמו בלוח השנה.
 */
import { useEffect, useMemo, useRef, useState } from 'react'
import { addDays, parseISO } from 'date-fns'
import {
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  Clock,
  Filter,
  ICON,
  LayoutGrid,
  STROKE,
  User,
  Users,
  X,
} from '../../components/ui/icons'
import {
  Badge,
  Button,
  EmptyState,
  Input,
  Modal,
  MultiSelect,
  PageHeader,
  SegmentedControl,
  Select,
  Skeleton,
  cx,
} from '../../components/ui'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { useContractors, useCustomers } from '../../lib/queries'
import { toISODate } from '../../lib/dates'
import { useIsMobile, useIsPhone } from '../../lib/useMediaQuery'
import { useShiftRoster, useTeamShifts } from './attendanceQueries'
import { fmtDuration } from './shiftFormat'
import { ShiftRosterGrid } from './ShiftRosterGrid'
import { ShiftTimeline } from './ShiftTimeline'
import { ShiftDetailDrawer } from './ShiftDetailDrawer'
import {
  BOARD_FILTER_LABELS,
  BOARD_LAYOUTS,
  BOARD_MODES,
  STAFF_ONLY,
  TIMELINE_GROUPINGS,
  activeBoardFilters,
  applyBoardFilters,
  boardDays,
  boardRange,
  boardStep,
  emptyBoardFilters,
  indexShifts,
  rangeTotals,
} from './shiftBoard'
import type {
  BoardFilters,
  BoardLayout,
  BoardMode,
  ShiftGroupMember,
  TimelineGrouping,
} from './shiftBoard'
import type { PlannedShift, WorkSite } from '../../types/domain'

const PREFS_KEY = 'vl-shiftboard-prefs'

interface Prefs {
  mode?: BoardMode
  layout?: BoardLayout
  grouping?: TimelineGrouping
}

function loadPrefs(): Prefs {
  try {
    return JSON.parse(localStorage.getItem(PREFS_KEY) ?? '{}') as Prefs
  } catch {
    return {}
  }
}

export default function ShiftBoardPage() {
  return (
    <RequirePermission perm={PERM.ATTENDANCE_VIEW_ALL}>
      <ShiftBoard />
    </RequirePermission>
  )
}

function ShiftBoard() {
  const isMobile = useIsMobile()
  const isPhone = useIsPhone()
  const prefs = useRef(loadPrefs())

  const [mode, setMode] = useState<BoardMode>(prefs.current.mode ?? 'week')
  const [layout, setLayout] = useState<BoardLayout>(prefs.current.layout ?? 'roster')
  const [grouping, setGrouping] = useState<TimelineGrouping>(prefs.current.grouping ?? 'grouped')
  const [anchor, setAnchor] = useState(() => new Date())
  const [filters, setFilters] = useState<BoardFilters>(emptyBoardFilters)
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [selected, setSelected] = useState<{
    shift: PlannedShift
    name: string
    team?: ShiftGroupMember[]
  } | null>(null)

  useEffect(() => {
    localStorage.setItem(PREFS_KEY, JSON.stringify({ mode, layout, grouping }))
  }, [mode, layout, grouping])

  const { from, to } = useMemo(() => boardRange(anchor, mode), [anchor, mode])
  const days = useMemo(() => boardDays(from, to), [from, to])

  const { data: roster = [], isLoading: rosterLoading } = useShiftRoster(from, to)
  const { data: shifts = [], isFetching } = useTeamShifts(from, to, filters.employees)
  const { data: customers = [] } = useCustomers()
  const { data: contractors = [] } = useContractors()

  const view = useMemo(() => applyBoardFilters(roster, shifts, filters), [roster, shifts, filters])
  const byCell = useMemo(() => indexShifts(view.shifts), [view.shifts])
  const totals = useMemo(() => rangeTotals(view.shifts), [view.shifts])
  const totalHours = view.shifts.reduce((sum, s) => sum + (s.planned_hours ?? 0), 0)

  const active = activeBoardFilters(filters)
  const step = boardStep(mode)
  const move = (dir: -1 | 1) => setAnchor((a) => addDays(a, dir * step))

  const filterValueLabel = (k: keyof BoardFilters): string => {
    if (k === 'q') return filters.q
    if (k === 'employees') return `${filters.employees.length} נבחרו`
    if (k === 'customer') return customers.find((c) => c.id === filters.customer)?.name ?? filters.customer
    if (k === 'site') return filters.site === 'warehouse' ? 'מחסן' : 'שטח'
    return filters.contractor === STAFF_ONLY
      ? 'עובדי החברה'
      : (contractors.find((c) => c.id === filters.contractor)?.name ?? filters.contractor)
  }

  const clearFilter = (k: keyof BoardFilters) =>
    setFilters((f) => ({ ...f, [k]: k === 'employees' ? [] : '' }))

  const filterControls = (
    <>
      <Input
        placeholder="חיפוש עובד..."
        inputSize="sm"
        value={filters.q}
        onChange={(e) => setFilters((f) => ({ ...f, q: e.target.value }))}
        aria-label="חיפוש עובד"
      />
      <MultiSelect
        options={roster.map((r) => ({ id: r.id, label: r.full_name }))}
        values={filters.employees}
        onToggle={(id) =>
          setFilters((f) => ({
            ...f,
            employees: f.employees.includes(id)
              ? f.employees.filter((x) => x !== id)
              : [...f.employees, id],
          }))
        }
        placeholder="כל העובדים"
      />
      <Select
        selectSize="sm"
        value={filters.customer}
        onChange={(e) => setFilters((f) => ({ ...f, customer: e.target.value }))}
        aria-label="לקוח"
      >
        <option value="">כל הלקוחות</option>
        {customers.map((c) => (
          <option key={c.id} value={c.id}>
            {c.name}
          </option>
        ))}
      </Select>
      <Select
        selectSize="sm"
        value={filters.site}
        onChange={(e) => setFilters((f) => ({ ...f, site: e.target.value as '' | WorkSite }))}
        aria-label="אתר עבודה"
      >
        <option value="">שטח ומחסן</option>
        <option value="field">שטח</option>
        <option value="warehouse">מחסן</option>
      </Select>
      <Select
        selectSize="sm"
        value={filters.contractor}
        onChange={(e) => setFilters((f) => ({ ...f, contractor: e.target.value }))}
        aria-label="קבלן"
      >
        <option value="">כולם</option>
        <option value={STAFF_ONLY}>עובדי החברה</option>
        {contractors.map((c) => (
          <option key={c.id} value={c.id}>
            {c.name}
          </option>
        ))}
      </Select>
    </>
  )

  const switches = (
    <>
      <SegmentedControl
        items={BOARD_MODES.map((m) => ({ key: m.key, label: m.label }))}
        value={mode}
        onChange={setMode}
        block={isPhone}
      />
      <SegmentedControl
        items={BOARD_LAYOUTS.map((l) => ({
          key: l.key,
          label: l.label,
          icon:
            l.key === 'roster' ? (
              <LayoutGrid size={ICON.sm} strokeWidth={STROKE} />
            ) : (
              <Clock size={ICON.sm} strokeWidth={STROKE} />
            ),
        }))}
        value={layout}
        onChange={setLayout}
        block={isPhone}
      />
      {/* הקיבוץ נוגע רק לציר השעות — בטבלת השיבוץ ממילא יש שורה לעובד */}
      {layout === 'timeline' && (
        <SegmentedControl
          items={TIMELINE_GROUPINGS.map((g) => ({
            key: g.key,
            label: g.label,
            icon:
              g.key === 'grouped' ? (
                <Users size={ICON.sm} strokeWidth={STROKE} />
              ) : (
                <User size={ICON.sm} strokeWidth={STROKE} />
              ),
          }))}
          value={grouping}
          onChange={setGrouping}
          block={isPhone}
        />
      )}
    </>
  )

  return (
    <div className="space-y-4">
      <PageHeader
        title="לוח משמרות צוות"
        subtitle={`${view.rows.length} עובדים · ${view.shifts.length} משמרות · ${fmtDuration(totalHours)} ש׳`}
        actions={
          <>
            <Button size="sm" onClick={() => move(-1)} aria-label="הקודם">
              <ChevronRight size={ICON.sm} strokeWidth={STROKE} />
            </Button>
            <Button size="sm" onClick={() => setAnchor(new Date())}>
              היום
            </Button>
            <Button size="sm" onClick={() => move(1)} aria-label="הבא">
              <ChevronLeft size={ICON.sm} strokeWidth={STROKE} />
            </Button>
            {!isPhone && switches}
            <Button
              size="sm"
              variant={active.length > 0 ? 'outlined' : 'secondary'}
              onClick={() => setFiltersOpen((v) => !v)}
              aria-expanded={filtersOpen}
            >
              <Filter size={ICON.sm} strokeWidth={STROKE} />
              סינון
              {active.length > 0 && (
                <span className="inline-flex size-4 items-center justify-center rounded-full bg-primary type-caption font-bold tabular text-on-primary">
                  {active.length}
                </span>
              )}
            </Button>
          </>
        }
      >
        <div className="flex flex-wrap items-center gap-2">
          <Badge tone="info">
            <CalendarDays size={ICON.sm} strokeWidth={STROKE} />
            <span dir="ltr" className="tabular">
              {toISODate(parseISO(from))} – {toISODate(parseISO(to))}
            </span>
          </Badge>
        </div>

        {/* בטלפון המתגים יורדים לשורה משלהם ותופסים את כל הרוחב, במקום
            להידחס לתוך שורת הפעולות */}
        {isPhone && <div className="grid gap-2">{switches}</div>}

        {active.length > 0 && (
          <div className="scroll-row gap-1.5 sm:flex-wrap">
            {active.map((k) => (
              <span
                key={k}
                className="scroll-row-item inline-flex items-center gap-1 rounded-full border border-primary-border bg-primary-subtle py-0.5 pe-1 ps-2 type-caption font-medium text-primary-text"
              >
                <span className="opacity-70">{BOARD_FILTER_LABELS[k]}:</span>
                <span className="max-w-40 truncate">{filterValueLabel(k)}</span>
                <button
                  onClick={() => clearFilter(k)}
                  aria-label={`הסרת סינון ${BOARD_FILTER_LABELS[k]}`}
                  className="rounded-full p-0.5 opacity-60 transition-opacity hover:opacity-100"
                >
                  <X size={11} />
                </button>
              </span>
            ))}
            <button
              onClick={() => setFilters(emptyBoardFilters)}
              className="scroll-row-item rounded-md px-2 py-0.5 type-caption text-ink-tertiary transition-colors hover:bg-hover hover:text-ink"
            >
              ניקוי הכל
            </button>
          </div>
        )}

        {filtersOpen && !isMobile && (
          <div className="surface grid animate-slide-up gap-2 p-3 sm:grid-cols-2 lg:grid-cols-3">
            {filterControls}
          </div>
        )}
      </PageHeader>

      {/* במובייל הפאנל הופך לדיאלוג, כדי שהוא לא ידחוף את הלוח מהמסך */}
      <Modal
        open={filtersOpen && isMobile}
        onClose={() => setFiltersOpen(false)}
        title="סינון משמרות"
        description={`${view.shifts.length} משמרות מוצגות`}
        footer={
          <>
            <Button onClick={() => setFilters(emptyBoardFilters)} disabled={active.length === 0}>
              ניקוי
            </Button>
            <Button variant="primary" onClick={() => setFiltersOpen(false)}>
              הצגה
            </Button>
          </>
        }
      >
        <div className="grid gap-3">{filterControls}</div>
      </Modal>

      <div className="relative">
        <div
          aria-hidden
          className={cx(
            'pointer-events-none absolute inset-x-0 top-0 z-40 h-0.5 bg-primary transition-opacity duration-200',
            isFetching ? 'animate-shimmer opacity-100' : 'opacity-0',
          )}
        />
        {rosterLoading ? (
          <Skeleton className="h-[32rem] w-full" />
        ) : view.rows.length === 0 && view.empty.length === 0 ? (
          <EmptyState art="calendar" title="אין עובדים להצגה" description="נסו לשנות את הסינון או את הטווח" />
        ) : layout === 'roster' ? (
          <div
            style={{ '--vl-shift-fs': isPhone ? '0.6875rem' : isMobile ? '0.75rem' : '0.8125rem' } as React.CSSProperties}
          >
            <ShiftRosterGrid
              rows={view.rows}
              empty={view.empty}
              days={days}
              byCell={byCell}
              totals={totals}
              narrow={isMobile}
              onOpen={(shift, name) => setSelected({ shift, name })}
            />
          </div>
        ) : (
          <ShiftTimeline
            shifts={view.shifts}
            roster={roster}
            from={from}
            to={to}
            grouping={grouping}
            onOpen={(g) =>
              setSelected({
                // הנציג הוא מי שמתחיל ראשון, ולכן המגירה מציגה את החלון המלא
                shift: g.lead,
                name: g.members.length === 1 ? g.members[0].name : `${g.members.length} עובדים`,
                team: g.members.length > 1 ? g.members : undefined,
              })
            }
          />
        )}
      </div>

      <ShiftDetailDrawer
        shift={selected?.shift ?? null}
        employeeName={selected?.name}
        team={selected?.team}
        onClose={() => setSelected(null)}
      />
    </div>
  )
}
