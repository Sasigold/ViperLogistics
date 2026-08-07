import { useMemo, useRef, useState } from 'react'
import FullCalendar from '@fullcalendar/react'
import timeGridPlugin from '@fullcalendar/timegrid'
import heLocale from '@fullcalendar/core/locales/he'
import type { DatesSetArg, EventContentArg } from '@fullcalendar/core'
import { addDays, startOfWeek } from 'date-fns'
import { CalendarClock, Clock, ICON, STROKE } from '../../components/ui/icons'
import { Badge, Button, Card, EmptyState, PageHeader, Skeleton } from '../../components/ui'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { toISODate } from '../../lib/dates'
import { useIsPhone } from '../../lib/useMediaQuery'
import { useMyShifts } from './attendanceQueries'
import { fmtDuration } from './shiftFormat'
import { ShiftChip } from './ShiftChip'
import { ShiftDetailDrawer } from './ShiftDetailDrawer'
import type { PlannedShift } from '../../types/domain'

export default function MySchedulePage() {
  return (
    <RequirePermission perm={PERM.ATTENDANCE_VIEW_SCHEDULE}>
      <MySchedule />
    </RequirePermission>
  )
}

function MySchedule() {
  const isPhone = useIsPhone()
  const calRef = useRef<FullCalendar>(null)
  const [selected, setSelected] = useState<PlannedShift | null>(null)
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
        backgroundColor: 'transparent',
        borderColor: 'transparent',
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

      <Card className="vl-shiftcal p-2 sm:p-3">
        {isLoading ? (
          <Skeleton className="h-[32rem] w-full" />
        ) : (
          // שבוע, ותו לא: אין מתג תצוגות ואין תצוגת יום. במסך צר הלוח נגלל
          // אופקית (ראו .vl-shiftcal ב-index.css) במקום לרסק שבע עמודות.
          <div className="overflow-x-auto">
            <FullCalendar
              ref={calRef}
              plugins={[timeGridPlugin]}
              initialView="timeGridWeek"
              headerToolbar={{ start: 'prev,next', center: 'title', end: '' }}
              buttonText={{ today: 'היום' }}
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
              eventClick={(info) => setSelected(info.event.extendedProps.shift as PlannedShift)}
              datesSet={onDatesSet}
              noEventsContent={() => <EmptyState compact art="calendar" title="אין משמרות בטווח הזה" />}
            />
          </div>
        )}
      </Card>

      <p className="px-1 type-caption text-ink-tertiary">
        {isPhone ? 'הקישו על משמרת כדי לראות ממה היא מורכבת' : 'לחיצה על משמרת פותחת את המשימות שמרכיבות אותה'}
      </p>

      <ShiftDetailDrawer shift={selected} onClose={() => setSelected(null)} />
    </div>
  )
}

function renderShift(arg: EventContentArg) {
  const shift = arg.event.extendedProps.shift as PlannedShift
  return <ShiftChip shift={shift} className="h-full" />
}
