import { useCallback, useMemo, useRef, useState } from 'react'
import FullCalendar from '@fullcalendar/react'
import timeGridPlugin from '@fullcalendar/timegrid'
import heLocale from '@fullcalendar/core/locales/he'
import type { DatesSetArg, DayHeaderContentArg, EventContentArg } from '@fullcalendar/core'
import { addDays, startOfWeek } from 'date-fns'
import { Card, ErrorState, Spinner } from '../../components/ui'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { toISODate } from '../../lib/dates'
import { useSwipeNav } from '../../lib/useSwipeNav'
import { useMyShifts } from './attendanceQueries'
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
  const calRef = useRef<FullCalendar>(null)
  const [selected, setSelected] = useState<PlannedShift | null>(null)
  // טווח ההתחלה הוא השבוע הנוכחי, כמו לוח העבודה; datesSet מרחיב אותו
  // כשמדפדפים, כך שהשאילתה עוקבת אחרי מה שבאמת מוצג.
  const [range, setRange] = useState(() => {
    const from = startOfWeek(new Date(), { weekStartsOn: 0 })
    return { from: toISODate(from), to: toISODate(addDays(from, 6)) }
  })

  const { data: shifts = [], isLoading, error, refetch } = useMyShifts(range.from, range.to)

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

  const { trackStyle, swipeHandlers, surfaceRef } = useSwipeNav({
    onNext: useCallback(() => calRef.current?.getApi().next(), []),
    onPrev: useCallback(() => calRef.current?.getApi().prev(), []),
  })

  return (
    // המסך כולו הוא הלוח: אין כותרת, אין סרגל ניווט משלו ואין גלילה — לא
    // אנכית ולא אופקית. מעבר בין שבועות נעשה בגרירה (ראו useWeekSwipe).
    <div className="flex h-full min-h-0 flex-col">
      <Card className="vl-shiftcal vl-myshifts relative flex min-h-0 flex-1 flex-col overflow-hidden p-1 sm:p-2">
        {isLoading && (
          <span className="pointer-events-none absolute end-2 top-2 z-10 opacity-70">
            <Spinner size={16} />
          </span>
        )}
        {error != null && shifts.length === 0 && (
          <div className="absolute inset-0 z-10 grid place-items-center bg-surface/90">
            <ErrorState error={error} onRetry={() => void refetch()} />
          </div>
        )}
        <div
          ref={surfaceRef}
          className="h-full min-h-0 flex-1 touch-pan-y select-none overflow-hidden"
          {...swipeHandlers}
        >
          <div className="h-full" style={trackStyle}>
            {/* שבוע, ותו לא: אין מתג תצוגות, אין סרגל כלים ואין תצוגת יום.
                expandRows + height="100%" מותחים את 24 השעות בדיוק לגובה
                הפנוי, כך שכל היממה נכנסת בלי גלילה.                        */}
            <FullCalendar
              ref={calRef}
              plugins={[timeGridPlugin]}
              initialView="timeGridWeek"
              headerToolbar={false}
              direction="rtl"
              locale={heLocale}
              height="100%"
              allDaySlot={false}
              nowIndicator
              // כל היממה מוצגת, 00:00–24:00: משמרת שמתחילה ב-22:00 ונמשכת 4
              // שעות ממשיכה בעמודת היום שאחריה כרגיל, ולא נחתכת.
              slotMinTime="00:00:00"
              slotMaxTime="24:00:00"
              // שורה לשעה, לא לחצי שעה: 24 שורות הן מה שנכנס לגובה מסך אחד.
              slotDuration="01:00:00"
              // תצוגת 24 שעות מפורשת ("01:00", "23:00"), בלי AM/PM — גם אם
              // הלוקאל של הדפדפן משתמש בברירת מחדל אחרת.
              slotLabelFormat={{ hour: '2-digit', minute: '2-digit', hour12: false }}
              eventTimeFormat={{ hour: '2-digit', minute: '2-digit', hour12: false }}
              dayHeaderContent={renderDayHeader}
              expandRows
              events={events}
              eventContent={renderShift}
              eventClick={(info) => setSelected(info.event.extendedProps.shift as PlannedShift)}
              datesSet={onDatesSet}
            />
          </div>
        </div>
      </Card>

      <ShiftDetailDrawer shift={selected} onClose={() => setSelected(null)} />
    </div>
  )
}

/** כותרת עמודה בשתי שורות — "א׳" מעל "9.8" — במקום שורה אחת שנחתכת */
function renderDayHeader(arg: DayHeaderContentArg) {
  const d = arg.date
  return (
    <span className="flex flex-col items-center leading-tight">
      <span className="font-semibold">{WEEKDAYS[d.getDay()]}</span>
      <span className="tabular opacity-70">{`${d.getDate()}.${d.getMonth() + 1}`}</span>
    </span>
  )
}

const WEEKDAYS = ['א׳', 'ב׳', 'ג׳', 'ד׳', 'ה׳', 'ו׳', 'ש׳']

function renderShift(arg: EventContentArg) {
  const shift = arg.event.extendedProps.shift as PlannedShift
  return <ShiftChip shift={shift} className="h-full" />
}
