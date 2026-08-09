import { useCallback, useMemo, useRef, useState } from 'react'
import type { PointerEvent as ReactPointerEvent } from 'react'
import FullCalendar from '@fullcalendar/react'
import timeGridPlugin from '@fullcalendar/timegrid'
import heLocale from '@fullcalendar/core/locales/he'
import type { DatesSetArg, DayHeaderContentArg, EventContentArg } from '@fullcalendar/core'
import { addDays, startOfWeek } from 'date-fns'
import { Card, Spinner } from '../../components/ui'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { toISODate } from '../../lib/dates'
import { useMyShifts } from './attendanceQueries'
import { ShiftChip } from './ShiftChip'
import { ShiftDetailDrawer } from './ShiftDetailDrawer'
import type { PlannedShift } from '../../types/domain'

/** מעבר לשבוע אחר מתחיל רק אחרי גרירה של רוחב כזה — פחות מזה זו נגיעה */
const SWIPE_MIN = 56
/** משך ההחלקה החוצה, בזהה ל-duration שב-CSS למטה */
const SLIDE_MS = 200

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

  const { dx, sliding, swipeHandlers, surfaceRef } = useWeekSwipe(calRef)

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
        <div
          ref={surfaceRef}
          className="h-full min-h-0 flex-1 touch-pan-y select-none overflow-hidden"
          {...swipeHandlers}
        >
          <div
            className="h-full"
            style={{
              transform: `translate3d(${dx}px, 0, 0)`,
              transition: sliding ? `transform ${SLIDE_MS}ms ease-out` : 'none',
            }}
          >
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

/* ===== גרירה בין שבועות ====================================================
   גרירה ימינה מביאה את השבוע הבא, שמאלה את הקודם. הלוח נגרר עם האצבע, ואם
   הגרירה עברה את הסף הוא ממשיך החוצה ומוחלף — אחרת הוא חוזר למקומו.

   האצבע נחטפת רק אחרי שהתנועה הוכרזה אופקית, כך שנגיעה על משמרת נשארת
   נגיעה ופותחת את המגירה.                                                  */
function useWeekSwipe(calRef: React.RefObject<FullCalendar | null>) {
  const surfaceRef = useRef<HTMLDivElement>(null)
  const [dx, setDx] = useState(0)
  const [sliding, setSliding] = useState(false)
  const drag = useRef<{ id: number; x: number; y: number; axis: 'unknown' | 'x' | 'y' } | null>(null)

  const finish = useCallback(
    (moved: number) => {
      const width = surfaceRef.current?.clientWidth ?? 0
      if (Math.abs(moved) < SWIPE_MIN) {
        setSliding(true)
        setDx(0)
        window.setTimeout(() => setSliding(false), SLIDE_MS)
        return
      }
      const dir = moved > 0 ? 1 : -1
      setSliding(true)
      setDx(dir * (width || Math.abs(moved)))
      window.setTimeout(() => {
        const api = calRef.current?.getApi()
        if (dir > 0) api?.next()
        else api?.prev()
        setSliding(false)
        setDx(0)
      }, SLIDE_MS)
    },
    [calRef],
  )

  const onPointerDown = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (sliding || drag.current || (e.pointerType === 'mouse' && e.button !== 0)) return
    drag.current = { id: e.pointerId, x: e.clientX, y: e.clientY, axis: 'unknown' }
  }

  const onPointerMove = (e: ReactPointerEvent<HTMLDivElement>) => {
    const d = drag.current
    if (!d || d.id !== e.pointerId) return
    const moved = e.clientX - d.x
    const vertical = e.clientY - d.y
    if (d.axis === 'unknown') {
      if (Math.abs(moved) < 10 && Math.abs(vertical) < 10) return
      d.axis = Math.abs(moved) > Math.abs(vertical) ? 'x' : 'y'
      if (d.axis === 'x') e.currentTarget.setPointerCapture(e.pointerId)
    }
    if (d.axis !== 'x') return
    setDx(moved)
  }

  const end = (e: ReactPointerEvent<HTMLDivElement>) => {
    const d = drag.current
    if (!d || d.id !== e.pointerId) return
    drag.current = null
    if (e.currentTarget.hasPointerCapture?.(e.pointerId)) e.currentTarget.releasePointerCapture(e.pointerId)
    if (d.axis === 'x') finish(e.clientX - d.x)
  }

  return {
    dx,
    sliding,
    surfaceRef,
    swipeHandlers: {
      onPointerDown,
      onPointerMove,
      onPointerUp: end,
      onPointerCancel: end,
    },
  }
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
