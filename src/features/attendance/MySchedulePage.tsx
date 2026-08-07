import { useMemo, useRef, useState } from 'react'
import FullCalendar from '@fullcalendar/react'
import timeGridPlugin from '@fullcalendar/timegrid'
import listPlugin from '@fullcalendar/list'
import heLocale from '@fullcalendar/core/locales/he'
import type { DatesSetArg, EventContentArg } from '@fullcalendar/core'
import { addDays, startOfWeek } from 'date-fns'
import { CalendarClock, Clock, ICON, MapPin, STROKE } from '../../components/ui/icons'
import { Badge, Button, Card, EmptyState, PageHeader, Skeleton, Tooltip } from '../../components/ui'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { toISODate } from '../../lib/dates'
import { useIsMobile } from '../../lib/useMediaQuery'
import { chipPaint } from '../../lib/colors'
import { useMyShifts } from './attendanceQueries'
import { WORK_SITE_LABELS, fmtDuration, fmtShiftRange } from './shiftFormat'
import type { PlannedShift } from '../../types/domain'

export default function MySchedulePage() {
  return (
    <RequirePermission perm={PERM.ATTENDANCE_VIEW_SCHEDULE}>
      <MySchedule />
    </RequirePermission>
  )
}

function MySchedule() {
  const isMobile = useIsMobile()
  const calRef = useRef<FullCalendar>(null)
  // טווח ההתחלה הוא השבוע הנוכחי, כמו לוח העבודה; datesSet מרחיב אותו
  // כשמדפדפים, כך שהשאילתה עוקבת אחרי מה שבאמת מוצג.
  const [range, setRange] = useState(() => {
    const from = startOfWeek(new Date(), { weekStartsOn: 0 })
    return { from: toISODate(from), to: toISODate(addDays(from, 6)) }
  })

  const { data: shifts = [], isLoading } = useMyShifts(range.from, range.to)

  const events = useMemo(
    () =>
      shifts.map((s) => ({
        id: `${s.work_date}-${s.seq}`,
        title: s.label ?? 'משמרת',
        start: s.shift_start,
        end: s.shift_end,
        backgroundColor: s.customer_color ?? '#3563f0',
        borderColor: s.customer_color ?? '#3563f0',
        extendedProps: { shift: s },
      })),
    [shifts],
  )

  const onDatesSet = (arg: DatesSetArg) => {
    const from = toISODate(arg.start)
    // הטווח שהתצוגה מבקשת נגמר בחצות של היום שאחרי האחרון שמוצג
    const to = toISODate(addDays(arg.end, -1))
    setRange((r) => (r.from === from && r.to === to ? r : { from, to }))
  }

  const total = shifts.reduce((sum, s) => sum + (s.planned_hours ?? 0), 0)

  return (
    <div className="space-y-4">
      <PageHeader
        title="לוח המשמרות שלי"
        subtitle="המשימות ששובצת אליהן, מקובצות למשמרות"
        actions={
          <Button size="sm" onClick={() => calRef.current?.getApi().today()}>
            היום
          </Button>
        }
      >
        <div className="flex flex-wrap items-center gap-2">
          <Badge tone="info">
            <CalendarClock size={ICON.sm} strokeWidth={STROKE} />
            {shifts.length} משמרות
          </Badge>
          <Badge tone="neutral">
            <Clock size={ICON.sm} strokeWidth={STROKE} />
            {fmtDuration(total)} ש׳
          </Badge>
        </div>
      </PageHeader>

      <Card className="p-2 sm:p-3">
        {isLoading ? (
          <Skeleton className="h-[32rem] w-full" />
        ) : (
          <FullCalendar
            ref={calRef}
            plugins={[timeGridPlugin, listPlugin]}
            initialView={isMobile ? 'listWeek' : 'timeGridWeek'}
            headerToolbar={{ start: 'prev,next', center: 'title', end: 'timeGridWeek,timeGridDay,listWeek' }}
            buttonText={{ week: 'שבוע', day: 'יום', list: 'סדר יום', today: 'היום' }}
            direction="rtl"
            locale={heLocale}
            height="auto"
            allDaySlot={false}
            nowIndicator
            // כל היממה מוצגת, 00:00–24:00: משמרת שמתחילה ב-22:00 ונמשכת 4
            // שעות ממשיכה בעמודת היום שאחריה כרגיל, ולא נחתכת.
            slotMinTime="00:00:00"
            slotMaxTime="24:00:00"
            // תצוגת 24 שעות מפורשת ("01:00", "23:00"), בלי AM/PM — גם אם
            // הלוקאל של הדפדפן משתמש בברירת מחדל אחרת.
            slotLabelFormat={{ hour: '2-digit', minute: '2-digit', hour12: false }}
            eventTimeFormat={{ hour: '2-digit', minute: '2-digit', hour12: false }}
            expandRows
            events={events}
            eventContent={renderShift}
            datesSet={onDatesSet}
            noEventsContent={() => <EmptyState compact art="calendar" title="אין משמרות בטווח הזה" />}
          />
        )}
      </Card>
    </div>
  )
}

function renderShift(arg: EventContentArg) {
  const shift = arg.event.extendedProps.shift as PlannedShift
  const paint = chipPaint(shift.customer_color ?? '#3563f0')
  return (
    <Tooltip
      content={`${fmtShiftRange(shift.shift_start, shift.shift_end)} · ${
        WORK_SITE_LABELS[shift.work_site]
      }${shift.task_ids.length > 1 ? ` · ${shift.task_ids.length} משימות` : ''}`}
    >
      <div
        className="flex h-full flex-col gap-0.5 overflow-hidden rounded-md px-1.5 py-1"
        style={{ background: paint.background, color: paint.color, borderColor: paint.borderColor }}
      >
        <span className="truncate type-caption font-semibold">{shift.label}</span>
        <span className="truncate type-caption opacity-90" dir="ltr">
          {fmtShiftRange(shift.shift_start, shift.shift_end)}
        </span>
        {shift.work_site === 'warehouse' && (
          <span className="flex items-center gap-1 truncate type-caption opacity-90">
            <MapPin size={ICON.xs} strokeWidth={STROKE} />
            מהמחסן
          </span>
        )}
      </div>
    </Tooltip>
  )
}
