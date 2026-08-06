import { useState } from 'react'
import { Link } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import { Plus, FileSpreadsheet } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { Badge, Button, EmptyState, Input, Select, Spinner } from '../../components/ui'
import { useCustomers } from '../../lib/queries'
import { fmtDate } from '../../lib/dates'
import { EventFormModal } from './EventFormModal'
import { ExcelDialog } from '../importExport/ExcelDialog'
import { RequirePermission } from '../auth/guards'
import type { EventRow } from '../../types/domain'

export default function EventsPage() {
  const { can } = useAuth()
  const [q, setQ] = useState('')
  const [customer, setCustomer] = useState('')
  const [createOpen, setCreateOpen] = useState(false)
  const [excelOpen, setExcelOpen] = useState(false)
  const { data: customers = [] } = useCustomers()

  const { data: events = [], isLoading } = useQuery({
    queryKey: ['events', 'list', q, customer],
    queryFn: async () => {
      let query = supabase
        .from('events')
        .select('*, customers(name, color), statuses(name, color)')
        .is('deleted_at', null)
        .order('event_date', { ascending: false })
        .limit(200)
      if (customer) query = query.eq('customer_id', customer)
      if (q.trim()) query = query.or(`end_client_name.ilike.%${q}%,event_number.ilike.%${q}%,location_text.ilike.%${q}%`)
      const { data, error } = await query
      if (error) throw error
      return data as EventRow[]
    },
  })

  return (
    <RequirePermission resource="events">
      <div className="space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-xl font-bold">אירועים</h1>
          <div className="ms-auto flex gap-2">
            <Button onClick={() => setExcelOpen(true)}>
              <FileSpreadsheet size={14} /> ייבוא / ייצוא
            </Button>
            {can('events', 'create') && (
              <Button variant="primary" onClick={() => setCreateOpen(true)}>
                <Plus size={14} /> אירוע חדש
              </Button>
            )}
          </div>
        </div>

        <div className="surface flex flex-wrap gap-2 p-2.5">
          <Input className="w-56" placeholder="חיפוש לפי שם, מספר, מיקום..." value={q} onChange={(e) => setQ(e.target.value)} />
          <Select className="w-44" value={customer} onChange={(e) => setCustomer(e.target.value)}>
            <option value="">כל הלקוחות</option>
            {customers.map((c) => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </Select>
        </div>

        <div className="surface overflow-x-auto">
          {isLoading ? (
            <Spinner full />
          ) : events.length === 0 ? (
            <EmptyState text="אין אירועים" />
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[var(--border)] text-start text-xs text-[var(--muted)]">
                  <th className="px-3 py-2 text-start">תאריך</th>
                  <th className="px-3 py-2 text-start">לקוח</th>
                  <th className="px-3 py-2 text-start">לקוח האירוע</th>
                  <th className="px-3 py-2 text-start">מס' אירוע</th>
                  <th className="px-3 py-2 text-start">מיקום</th>
                  <th className="px-3 py-2 text-start">נפח</th>
                  <th className="px-3 py-2 text-start">משאיות</th>
                  <th className="px-3 py-2 text-start">סטטוס</th>
                </tr>
              </thead>
              <tbody>
                {events.map((e) => (
                  <tr key={e.id} className="border-b border-[var(--border)] last:border-0 hover:bg-[var(--bg)]">
                    <td className="px-3 py-2 whitespace-nowrap">
                      <Link to={`/events/${e.id}`} className="font-medium text-brand-600 hover:underline dark:text-brand-300">
                        {fmtDate(e.event_date)}
                      </Link>
                    </td>
                    <td className="px-3 py-2">
                      <span className="inline-flex items-center gap-1.5">
                        <span className="size-2.5 rounded-full" style={{ background: e.customers?.color }} />
                        {e.customers?.name}
                      </span>
                    </td>
                    <td className="px-3 py-2">{e.end_client_name}</td>
                    <td className="px-3 py-2">{e.event_number}</td>
                    <td className="max-w-56 truncate px-3 py-2">{e.location_text}</td>
                    <td className="px-3 py-2">{e.volume_m ?? ''}</td>
                    <td className="px-3 py-2">{e.truck_count ?? ''}</td>
                    <td className="px-3 py-2">
                      {e.statuses && <Badge color={e.statuses.color}>{e.statuses.name}</Badge>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        <EventFormModal open={createOpen} onClose={() => setCreateOpen(false)} />
        <ExcelDialog open={excelOpen} onClose={() => setExcelOpen(false)} />
      </div>
    </RequirePermission>
  )
}
