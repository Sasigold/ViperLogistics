import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { addDays, startOfMonth, endOfMonth } from 'date-fns'
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, PieChart, Pie, Cell, Legend } from 'recharts'
import { CalendarDays, ClipboardList, AlertTriangle, Users } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { toISODate } from '../../lib/dates'
import { Field, Input, Spinner } from '../../components/ui'
import { RequirePermission } from '../auth/guards'

interface Stats {
  events_count: number
  tasks_count: number
  tasks_today: number
  tasks_week: number
  tasks_overdue: number
  available_workers: number
  by_customer: { name: string; color: string; cnt: number }[]
  by_contractor: { name: string; cnt: number }[]
  by_worker: { name: string; cnt: number }[]
  by_status: { name: string; color: string; cnt: number }[]
}

function StatCard({ icon: Icon, label, value, tone }: { icon: typeof CalendarDays; label: string; value: number; tone?: string }) {
  return (
    <div className="surface flex items-center gap-3 p-4">
      <div className="flex size-10 items-center justify-center rounded-lg" style={{ background: `color-mix(in srgb, ${tone ?? '#3b6ef6'} 12%, transparent)`, color: tone ?? '#3b6ef6' }}>
        <Icon size={18} />
      </div>
      <div>
        <p className="text-xs text-[var(--muted)]">{label}</p>
        <p className="text-xl font-bold">{value}</p>
      </div>
    </div>
  )
}

export default function DashboardPage() {
  const [from, setFrom] = useState(toISODate(startOfMonth(new Date())))
  const [to, setTo] = useState(toISODate(endOfMonth(addDays(new Date(), 0))))

  const { data: stats, isLoading } = useQuery({
    queryKey: ['dashboard', from, to],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('dashboard_stats', { p_from: from, p_to: to })
      if (error) throw error
      return data as Stats
    },
  })

  return (
    <RequirePermission resource="dashboard">
      <div className="space-y-4">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <h1 className="text-xl font-bold">דשבורד</h1>
          <div className="flex items-end gap-2">
            <Field label="מתאריך">
              <Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
            </Field>
            <Field label="עד תאריך">
              <Input type="date" value={to} onChange={(e) => setTo(e.target.value)} />
            </Field>
          </div>
        </div>

        {isLoading || !stats ? (
          <Spinner full />
        ) : (
          <>
            <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
              <StatCard icon={CalendarDays} label="אירועים בטווח" value={stats.events_count} />
              <StatCard icon={ClipboardList} label="משימות בטווח" value={stats.tasks_count} />
              <StatCard icon={ClipboardList} label="משימות היום" value={stats.tasks_today} tone="#8b5cf6" />
              <StatCard icon={ClipboardList} label="משימות השבוע" value={stats.tasks_week} tone="#0ea5e9" />
              <StatCard icon={AlertTriangle} label="משימות באיחור" value={stats.tasks_overdue} tone="#ef4444" />
              <StatCard icon={Users} label="עובדים זמינים היום" value={stats.available_workers} tone="#22c55e" />
            </div>

            <div className="grid gap-3 lg:grid-cols-2">
              <div className="surface p-4">
                <h2 className="mb-3 text-sm font-bold">התפלגות משימות לפי לקוח</h2>
                {stats.by_customer.length === 0 ? (
                  <p className="text-sm text-[var(--muted)]">אין נתונים</p>
                ) : (
                  <ResponsiveContainer width="100%" height={260}>
                    <BarChart data={stats.by_customer}>
                      <XAxis dataKey="name" tick={{ fontSize: 11, fill: 'var(--muted)' }} />
                      <YAxis tick={{ fontSize: 11, fill: 'var(--muted)' }} allowDecimals={false} />
                      <Tooltip cursor={{ fill: 'var(--bg)' }} contentStyle={{ background: 'var(--panel)', border: '1px solid var(--border)', borderRadius: 8 }} />
                      <Bar dataKey="cnt" name="משימות" radius={[4, 4, 0, 0]}>
                        {stats.by_customer.map((c, i) => (
                          <Cell key={i} fill={c.color} />
                        ))}
                      </Bar>
                    </BarChart>
                  </ResponsiveContainer>
                )}
              </div>

              <div className="surface p-4">
                <h2 className="mb-3 text-sm font-bold">התפלגות לפי סטטוס</h2>
                {stats.by_status.length === 0 ? (
                  <p className="text-sm text-[var(--muted)]">אין נתונים</p>
                ) : (
                  <ResponsiveContainer width="100%" height={260}>
                    <PieChart>
                      <Pie data={stats.by_status} dataKey="cnt" nameKey="name" innerRadius={55} outerRadius={90} paddingAngle={2}>
                        {stats.by_status.map((s, i) => (
                          <Cell key={i} fill={s.color} />
                        ))}
                      </Pie>
                      <Legend formatter={(v) => <span style={{ color: 'var(--text)', fontSize: 12 }}>{v}</span>} />
                      <Tooltip contentStyle={{ background: 'var(--panel)', border: '1px solid var(--border)', borderRadius: 8 }} />
                    </PieChart>
                  </ResponsiveContainer>
                )}
              </div>

              <div className="surface p-4">
                <h2 className="mb-3 text-sm font-bold">עומס עובדים (שיבוצים בטווח)</h2>
                {stats.by_worker.length === 0 ? (
                  <p className="text-sm text-[var(--muted)]">אין נתונים</p>
                ) : (
                  <ResponsiveContainer width="100%" height={260}>
                    <BarChart data={stats.by_worker} layout="vertical">
                      <XAxis type="number" tick={{ fontSize: 11, fill: 'var(--muted)' }} allowDecimals={false} />
                      <YAxis type="category" dataKey="name" width={90} tick={{ fontSize: 11, fill: 'var(--muted)' }} />
                      <Tooltip cursor={{ fill: 'var(--bg)' }} contentStyle={{ background: 'var(--panel)', border: '1px solid var(--border)', borderRadius: 8 }} />
                      <Bar dataKey="cnt" name="שיבוצים" fill="#3b6ef6" radius={[0, 4, 4, 0]} />
                    </BarChart>
                  </ResponsiveContainer>
                )}
              </div>

              <div className="surface p-4">
                <h2 className="mb-3 text-sm font-bold">התפלגות קבלנים</h2>
                {stats.by_contractor.length === 0 ? (
                  <p className="text-sm text-[var(--muted)]">אין נתונים</p>
                ) : (
                  <ResponsiveContainer width="100%" height={260}>
                    <BarChart data={stats.by_contractor}>
                      <XAxis dataKey="name" tick={{ fontSize: 11, fill: 'var(--muted)' }} />
                      <YAxis tick={{ fontSize: 11, fill: 'var(--muted)' }} allowDecimals={false} />
                      <Tooltip cursor={{ fill: 'var(--bg)' }} contentStyle={{ background: 'var(--panel)', border: '1px solid var(--border)', borderRadius: 8 }} />
                      <Bar dataKey="cnt" name="משימות" fill="#f59e0b" radius={[4, 4, 0, 0]} />
                    </BarChart>
                  </ResponsiveContainer>
                )}
              </div>
            </div>
          </>
        )}
      </div>
    </RequirePermission>
  )
}
