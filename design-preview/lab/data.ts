// שכבת נתונים של ה-Lab: אותן טבלאות ואותם שדות שהאפליקציה קוראת, ללא שום כתיבה.
import { useQuery } from '@tanstack/react-query'
import { supabase } from '../../src/lib/supabase'
import type { WorkBoardRow } from '../../src/types/domain'

export interface LabEvent {
  id: string
  event_date: string
  end_client_name: string | null
  event_number: string | null
  location_text: string | null
  location_notes: string | null
  volume_m: number | null
  truck_count: number | null
  notes: string | null
  no_parking: boolean
  porterage: boolean
  supplier_pickup: boolean
  approved_at: string | null
  status_id: string | null
  customer_id: string
  customers: { name: string; color: string } | null
  statuses: { name: string; color: string; code: string } | null
}

export const useEvents = (from: string, to: string) =>
  useQuery({
    queryKey: ['lab', 'events', from, to],
    queryFn: async () => {
      const { data, error } = await supabase.from('events').select('*, customers(name, color), statuses(name, color, code)')
        .gte('event_date', from).lte('event_date', to).is('deleted_at', null)
      if (error) throw error
      return (data as unknown as LabEvent[]).sort((a, b) => a.event_date.localeCompare(b.event_date))
    },
  })

export const useTasks = (from: string, to: string) =>
  useQuery({
    queryKey: ['lab', 'tasks', from, to],
    queryFn: async () => {
      const { data, error } = await supabase.from('work_board_view').select('*').gte('task_date', from).lte('task_date', to)
      if (error) throw error
      return (data as unknown as WorkBoardRow[]).sort((a, b) => (a.onsite_start_time ?? '').localeCompare(b.onsite_start_time ?? ''))
    },
  })

export const useEvent = (id: string) =>
  useQuery({
    queryKey: ['lab', 'event', id],
    queryFn: async () => {
      const { data, error } = await supabase.from('events').select('*, customers(name, color), statuses(name, color, code)').eq('id', id).single()
      if (error) throw error
      return data as unknown as LabEvent
    },
  })

// ── נגזרות תצוגה (לא לוגיקה עסקית — רק סיכום של מה שכבר בשורה) ──
export const mins = (t: string | null | undefined) => (t ? +t.slice(0, 2) * 60 + +t.slice(3, 5) : null)
export const hm = (t: string | null | undefined) => (t ? t.slice(0, 5) : '—')

export interface TaskHealth {
  need: number
  have: number
  flags: { key: string; label: string; tone: 'warn' | 'bad' }[]
  ready: boolean
}
export function taskHealth(t: WorkBoardRow): TaskHealth {
  const have = (t.workers?.length ?? 0) + (t.drivers?.length ?? 0) + (t.team_lead_id ? 1 : 0) + (t.contractor_worker_list?.length ?? 0)
  const need = t.worker_count
  const flags: TaskHealth['flags'] = []
  if (t.requires_team_lead && !t.team_lead_id) flags.push({ key: 'lead', label: 'חסר ראש צוות', tone: 'bad' })
  if (have < need) flags.push({ key: 'crew', label: `חסרים ${need - have} עובדים`, tone: 'bad' })
  if (!t.truck_id) flags.push({ key: 'truck', label: 'ללא משאית', tone: 'warn' })
  if (t.status_code === 'draft') flags.push({ key: 'draft', label: 'טיוטה', tone: 'warn' })
  return { need, have, flags, ready: flags.length === 0 }
}

export const HE_DAYS = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת']
export const parse = (d: string) => new Date(d + 'T12:00:00')
export const iso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
export const addDays = (d: string, n: number) => { const x = parse(d); x.setDate(x.getDate() + n); return iso(x) }
export const weekStart = (d: string) => addDays(d, -parse(d).getDay())
export const dayLabel = (d: string) => `${HE_DAYS[parse(d).getDay()]} ${parse(d).getDate()}.${parse(d).getMonth() + 1}`
export const TODAY = iso(new Date())
export const money = (n: number | null | undefined) => (n == null ? '—' : `₪${Math.round(n).toLocaleString('he-IL')}`)
export const initials = (n: string) => n.split(' ').map((p) => p[0]).slice(0, 2).join('')

export const useContact = (id: string) =>
  useQuery({
    queryKey: ['lab', 'contact', id],
    queryFn: async () => {
      const { data } = await supabase.from('event_contacts').select('*').eq('event_id', id).maybeSingle()
      return data as { contact_name: string | null; contact_phone: string | null } | null
    },
  })
export const fmtDM = (d: string) => `${parse(d).getDate()}.${parse(d).getMonth() + 1}`
export const monthStart = (d: string) => d.slice(0, 8) + '01'
export const monthEnd = (d: string) => iso(new Date(+d.slice(0, 4), +d.slice(5, 7), 0, 12))
export const addMonths = (d: string, n: number) => iso(new Date(+d.slice(0, 4), +d.slice(5, 7) - 1 + n, 1, 12))
