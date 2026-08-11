/**
 * ציר הזמן: כל המשמרות של כולם, זו לצד זו, לפי שעה.
 *
 * תוסף ה-resource של FullCalendar אינו מותקן (ואינו חינמי), ולכן "כולם זה
 * לצד זה" אינו שורה לעובד אלא עמודת יום אחת שבה פריסת החפיפה של FullCalendar
 * מסדרת את כולם. מה שהופך את זה לקריא הוא ששמות העובדים הם חלק מכל צ׳יפ —
 * בלעדיהם זה סתם קיר של צבעים.
 *
 * האירוע כאן אינו משמרת של אדם אלא *קבוצה* (ראו groupShifts): במצב 'grouped'
 * כל מי שעובד באותה משמרת נכנס לצ׳יפ אחד, ובמצב 'each' כל אחד מקבל קבוצה של
 * אחד. אותו מבנה בשני המצבים, ולכן גם הציור וגם הקליק הם ענף אחד.
 *
 * הניווט שייך לעמוד ולא ללוח: headerToolbar כבוי, והטווח מוזרק מבחוץ. אין
 * לחבר כאן datesSet בחזרה למצב של העמוד, אחרת שתי התצוגות יוכלו להראות
 * שבועות שונים.
 */
import { useEffect, useMemo, useRef } from 'react'
import FullCalendar from '@fullcalendar/react'
import timeGridPlugin from '@fullcalendar/timegrid'
import heLocale from '@fullcalendar/core/locales/he'
import type { EventContentArg } from '@fullcalendar/core'
import { parseISO } from 'date-fns'
import { EmptyState } from '../../components/ui'
import { ShiftGroupChip } from './ShiftGroupChip'
import { groupShifts } from './shiftBoard'
import type { ShiftGroup, TimelineGrouping } from './shiftBoard'
import type { PlannedShift, ShiftRosterEntry } from '../../types/domain'

const VIEW = 'timeGridBoard'

export function ShiftTimeline({
  shifts,
  roster,
  from,
  to,
  grouping,
  onOpen,
}: {
  shifts: PlannedShift[]
  roster: ShiftRosterEntry[]
  from: string
  to: string
  grouping: TimelineGrouping
  onOpen: (group: ShiftGroup) => void
}) {
  const calRef = useRef<FullCalendar>(null)
  const nameById = useMemo(() => new Map(roster.map((r) => [r.id, r.full_name])), [roster])
  const days = useMemo(() => {
    const diff = Math.round((parseISO(to).getTime() - parseISO(from).getTime()) / 86_400_000)
    return Math.max(1, diff + 1)
  }, [from, to])

  const groups = useMemo(
    () => groupShifts(shifts, nameById, grouping),
    [shifts, nameById, grouping],
  )

  const events = useMemo(
    () =>
      groups.map((g) => ({
        id: g.key,
        title: g.members.map((m) => m.name).join(', '),
        start: g.start,
        end: g.end,
        backgroundColor: 'transparent',
        borderColor: 'transparent',
        extendedProps: { group: g },
      })),
    [groups],
  )

  // הטווח נשלט מבחוץ. changeView עם תאריך פתיחה הוא הדרך היציבה להזיז view
  // בעל duration קבוע, במקום להסתמך על visibleRange שנקרא פעם אחת באתחול.
  useEffect(() => {
    calRef.current?.getApi().changeView(VIEW, from)
  }, [from, days])

  return (
    <div className="vl-shiftcal surface overflow-x-auto p-2 sm:p-3">
      <FullCalendar
        ref={calRef}
        plugins={[timeGridPlugin]}
        initialView={VIEW}
        views={{ [VIEW]: { type: 'timeGrid', duration: { days } } }}
        initialDate={from}
        headerToolbar={false}
        locale={heLocale}
        direction="rtl"
        height="auto"
        allDaySlot={false}
        nowIndicator
        // כל היממה, כדי שמשמרת שמתחילה ב-22:00 לא תיחתך
        slotMinTime="00:00:00"
        slotMaxTime="24:00:00"
        slotLabelFormat={{ hour: '2-digit', minute: '2-digit', hour12: false }}
        eventTimeFormat={{ hour: '2-digit', minute: '2-digit', hour12: false }}
        expandRows
        slotEventOverlap={false}
        events={events}
        eventContent={renderShift}
        eventClick={(info) => onOpen(info.event.extendedProps.group as ShiftGroup)}
        noEventsContent={() => <EmptyState compact art="calendar" title="אין משמרות בטווח הזה" />}
      />
    </div>
  )
}

function renderShift(arg: EventContentArg) {
  return <ShiftGroupChip group={arg.event.extendedProps.group as ShiftGroup} className="h-full" />
}
