import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import FullCalendar from '@fullcalendar/react'
import dayGridPlugin from '@fullcalendar/daygrid'
import listPlugin from '@fullcalendar/list'
import heLocale from '@fullcalendar/core/locales/he'
import type { EventContentArg } from '@fullcalendar/core'
import { Card, PageHeader, Skeleton } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useIsMobile } from '../../lib/useMediaQuery'
import { RequirePermission } from '../auth/guards'
import { PERM } from '../../lib/permissions'
import { chipPaint } from '../calendar/eventColors'
import type { EventRow } from '../../types/domain'

/**
 * A read-only calendar. The staff CalendarPage is not reused: it carries saved
 * filters, a duplicate action and drag-to-reschedule that writes to events
 * directly — a write path 0010 closed for clients, so those interactions would
 * now fail rather than silently work.
 */
export default function ClientCalendarPage() {
  const navigate = useNavigate()
  const isMobile = useIsMobile()
  const [range, setRange] = useState<{ from: string; to: string } | null>(null)

  const { data: events = [], isLoading } = useQuery({
    queryKey: ['client', 'calendar', range?.from, range?.to],
    enabled: !!range,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('events')
        .select('*, statuses(name, color)')
        .is('deleted_at', null)
        .gte('event_date', range!.from)
        .lte('event_date', range!.to)
      if (error) throw error
      return data as EventRow[]
    },
  })

  const fcEvents = useMemo(
    () =>
      events.map((e) => ({
        id: e.id,
        title: e.end_client_name || e.event_number || 'אירוע',
        start: e.event_date,
        allDay: true,
        extendedProps: { color: e.statuses?.color, location: e.location_text },
      })),
    [events],
  )

  return (
    <RequirePermission perm={PERM.CALENDAR_VIEW}>
      <div className="space-y-4">
        <PageHeader title="לוח שנה" subtitle={isLoading ? 'טוען...' : `${events.length} אירועים בטווח המוצג`} />
        <Card padded>
          {!range && isLoading && <Skeleton className="h-96 w-full" />}
          <FullCalendar
            plugins={[dayGridPlugin, listPlugin]}
            initialView={isMobile ? 'listMonth' : 'dayGridMonth'}
            locale={heLocale}
            direction="rtl"
            height="auto"
            editable={false}
            selectable={false}
            headerToolbar={{ start: 'prev,next today', center: 'title', end: 'dayGridMonth,listMonth' }}
            events={fcEvents}
            datesSet={(arg) =>
              setRange({ from: arg.startStr.slice(0, 10), to: arg.endStr.slice(0, 10) })
            }
            eventClick={(arg) => navigate(`/client/events/${arg.event.id}`)}
            eventContent={(arg: EventContentArg) => {
              const paint = chipPaint(arg.event.extendedProps.color as string | undefined)
              return (
                <div
                  className="flex w-full items-center gap-1 overflow-hidden rounded px-1.5 py-0.5 type-caption"
                  style={{ background: paint.background, color: paint.color }}
                >
                  <span className="truncate">{arg.event.title}</span>
                </div>
              )
            }}
          />
        </Card>
      </div>
    </RequirePermission>
  )
}
