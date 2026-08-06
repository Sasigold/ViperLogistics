import { useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'react-router'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useVirtualizer } from '@tanstack/react-virtual'
import { addDays, startOfWeek } from 'date-fns'
import { Plus, Pencil } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { Button, Field, Input, Modal, Select, Spinner, EmptyState, useToast, cx } from '../../components/ui'
import { useContractors, useCustomers, useExecutionMethods, useStatuses, useTaskTypes, useTrucks } from '../../lib/queries'
import { toISODate, fmtDate, fmtHours, fmtTime } from '../../lib/dates'
import { TaskDrawer } from '../tasks/TaskDrawer'
import { RequirePermission } from '../auth/guards'
import type { WorkBoardRow } from '../../types/domain'

/** inline cell that writes a single column with optimistic-concurrency on updated_at */
function useInlineUpdate() {
  const qc = useQueryClient()
  const toast = useToast()
  return useMutation({
    mutationFn: async ({ row, patch }: { row: WorkBoardRow; patch: Record<string, unknown> }) => {
      const { data, error } = await supabase
        .from('tasks')
        .update(patch)
        .eq('id', row.id)
        .eq('updated_at', row.updated_at)
        .select('id')
      if (error) throw error
      if (!data || data.length === 0) throw new Error('המשימה עודכנה על ידי משתמש אחר — הנתונים רועננו')
    },
    onSettled: () => void qc.invalidateQueries({ queryKey: ['workboard'] }),
    onError: (e) => toast.error((e as Error).message),
  })
}

export default function WorkBoardPage() {
  const { can } = useAuth()
  const canEdit = can('tasks', 'edit')
  const [params] = useSearchParams()
  const weekStart = startOfWeek(new Date(), { weekStartsOn: 0 })
  const [from, setFrom] = useState(params.get('date') || toISODate(weekStart))
  const [to, setTo] = useState(params.get('date') || toISODate(addDays(weekStart, 6)))
  const [filters, setFilters] = useState({ customer: '', status: '', type: '', contractor: '', q: '' })
  const [drawer, setDrawer] = useState<{ open: boolean; taskId: string | null }>({
    open: !!params.get('task'),
    taskId: params.get('task'),
  })
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [bulkOpen, setBulkOpen] = useState(false)

  const { data: customers = [] } = useCustomers()
  const { data: statuses = [] } = useStatuses('task')
  const { data: taskTypes = [] } = useTaskTypes()
  const { data: contractors = [] } = useContractors()
  const { data: methods = [] } = useExecutionMethods()
  const { data: trucks = [] } = useTrucks()
  const inline = useInlineUpdate()

  const { data: rows = [], isLoading } = useQuery({
    queryKey: ['workboard', 'range', from, to, filters],
    queryFn: async () => {
      let q = supabase
        .from('work_board_view')
        .select('*')
        .gte('task_date', from)
        .lte('task_date', to)
        .order('task_date')
        .order('onsite_start_time', { nullsFirst: false })
        .limit(2000)
      if (filters.customer) q = q.eq('customer_id', filters.customer)
      if (filters.status) q = q.eq('status_id', filters.status)
      if (filters.type) q = q.eq('task_type_id', filters.type)
      if (filters.contractor) q = q.eq('contractor_id', filters.contractor)
      if (filters.q.trim())
        q = q.or(
          `title.ilike.%${filters.q}%,end_client_name.ilike.%${filters.q}%,event_number.ilike.%${filters.q}%,location_text.ilike.%${filters.q}%,customer_name.ilike.%${filters.q}%`,
        )
      const { data, error } = await q
      if (error) throw error
      return data as WorkBoardRow[]
    },
  })

  const parentRef = useRef<HTMLDivElement>(null)
  const virtualizer = useVirtualizer({
    count: rows.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 44,
    overscan: 12,
  })

  const allSelected = rows.length > 0 && selected.size === rows.length
  const toggleAll = () => setSelected(allSelected ? new Set() : new Set(rows.map((r) => r.id)))
  const toggleOne = (id: string) =>
    setSelected((s) => {
      const n = new Set(s)
      if (n.has(id)) n.delete(id)
      else n.add(id)
      return n
    })

  const cols = useMemo(
    () => [
      { key: 'sel', label: '', w: 'w-8' },
      { key: 'customer', label: 'לקוח', w: 'w-32' },
      { key: 'end_client', label: 'לקוח האירוע', w: 'w-32' },
      { key: 'event_number', label: "מס' אירוע", w: 'w-20' },
      { key: 'location', label: 'מיקום', w: 'w-40' },
      { key: 'type', label: 'סוג משימה', w: 'w-24' },
      { key: 'date', label: 'תאריך', w: 'w-24' },
      { key: 'warehouse', label: 'התחלה במחסן', w: 'w-24' },
      { key: 'onsite', label: 'התחלה בשטח', w: 'w-24' },
      { key: 'end', label: 'סיום בשטח', w: 'w-20' },
      { key: 'duration', label: 'משך', w: 'w-16' },
      { key: 'workers_count', label: 'עובדים', w: 'w-16' },
      { key: 'trucks_count', label: 'משאיות', w: 'w-16' },
      { key: 'volume', label: 'נפח', w: 'w-14' },
      { key: 'truck', label: 'משאית', w: 'w-32' },
      { key: 'method', label: 'אופן ביצוע', w: 'w-32' },
      { key: 'lead', label: 'ראש צוות', w: 'w-28' },
      { key: 'team', label: 'עובדים ונהגים', w: 'w-44' },
      { key: 'contractor', label: 'קבלן', w: 'w-28' },
      { key: 'status', label: 'סטטוס', w: 'w-28' },
      { key: 'notes', label: 'הערות', w: 'w-40' },
      { key: 'edit', label: '', w: 'w-10' },
    ],
    [],
  )

  return (
    <RequirePermission resource="tasks">
      <div className="flex h-full flex-col gap-3">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-xl font-bold">לוח עבודה</h1>
          <span className="text-sm text-[var(--muted)]">{rows.length} משימות</span>
          <div className="ms-auto flex flex-wrap gap-2">
            {selected.size > 0 && canEdit && (
              <Button onClick={() => setBulkOpen(true)}>
                <Pencil size={14} /> עריכה מרובה ({selected.size})
              </Button>
            )}
            {can('tasks', 'create') && (
              <Button variant="primary" onClick={() => setDrawer({ open: true, taskId: null })}>
                <Plus size={14} /> משימה חדשה
              </Button>
            )}
          </div>
        </div>

        <div className="surface flex flex-wrap items-center gap-2 p-2.5">
          <Input type="date" className="w-36" value={from} onChange={(e) => setFrom(e.target.value)} />
          <span className="text-xs text-[var(--muted)]">עד</span>
          <Input type="date" className="w-36" value={to} onChange={(e) => setTo(e.target.value)} />
          <Input className="w-44" placeholder="חיפוש..." value={filters.q} onChange={(e) => setFilters((f) => ({ ...f, q: e.target.value }))} />
          <Select className="w-36" value={filters.customer} onChange={(e) => setFilters((f) => ({ ...f, customer: e.target.value }))}>
            <option value="">כל הלקוחות</option>
            {customers.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </Select>
          <Select className="w-32" value={filters.type} onChange={(e) => setFilters((f) => ({ ...f, type: e.target.value }))}>
            <option value="">כל הסוגים</option>
            {taskTypes.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
          </Select>
          <Select className="w-32" value={filters.status} onChange={(e) => setFilters((f) => ({ ...f, status: e.target.value }))}>
            <option value="">כל הסטטוסים</option>
            {statuses.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </Select>
          <Select className="w-32" value={filters.contractor} onChange={(e) => setFilters((f) => ({ ...f, contractor: e.target.value }))}>
            <option value="">כל הקבלנים</option>
            {contractors.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </Select>
        </div>

        <div className="surface min-h-0 flex-1 overflow-hidden">
          {isLoading ? (
            <Spinner full />
          ) : rows.length === 0 ? (
            <EmptyState text="אין משימות בטווח שנבחר" />
          ) : (
            <div ref={parentRef} className="h-full overflow-auto">
              <div className="min-w-[2100px]">
                <div className="sticky top-0 z-10 flex border-b border-[var(--border)] bg-[var(--panel)] text-xs font-semibold text-[var(--muted)]">
                  {cols.map((c) => (
                    <div key={c.key} className={cx('shrink-0 px-2 py-2', c.w)}>
                      {c.key === 'sel' ? (
                        <input type="checkbox" className="accent-brand-600" checked={allSelected} onChange={toggleAll} />
                      ) : (
                        c.label
                      )}
                    </div>
                  ))}
                </div>
                <div style={{ height: virtualizer.getTotalSize(), position: 'relative' }}>
                  {virtualizer.getVirtualItems().map((vi) => {
                    const r = rows[vi.index]
                    return (
                      <div
                        key={r.id}
                        className="absolute inset-x-0 flex items-center border-b border-[var(--border)] text-sm hover:bg-[var(--bg)]"
                        style={{ top: 0, transform: `translateY(${vi.start}px)`, height: vi.size }}
                      >
                        <div className="w-8 shrink-0 px-2">
                          <input type="checkbox" className="accent-brand-600" checked={selected.has(r.id)} onChange={() => toggleOne(r.id)} />
                        </div>
                        <div className="w-32 shrink-0 truncate px-2">
                          {r.customer_name && (
                            <span className="inline-flex items-center gap-1.5">
                              <span className="size-2 shrink-0 rounded-full" style={{ background: r.customer_color ?? '#64748b' }} />
                              <span className="truncate">{r.customer_name}</span>
                            </span>
                          )}
                        </div>
                        <div className="w-32 shrink-0 truncate px-2">{r.end_client_name ?? r.title}</div>
                        <div className="w-20 shrink-0 truncate px-2">{r.event_number}</div>
                        <div className="w-40 shrink-0 truncate px-2" title={r.location_text ?? ''}>{r.location_text}</div>
                        <div className="w-24 shrink-0 truncate px-2 font-medium">{r.task_type_name}</div>
                        <div className="w-24 shrink-0 whitespace-nowrap px-2">{fmtDate(r.task_date)}</div>
                        <div className="w-24 shrink-0 px-1">
                          <input
                            type="time"
                            defaultValue={fmtTime(r.warehouse_start_time)}
                            disabled={!canEdit}
                            onBlur={(e) => {
                              const v = e.target.value || null
                              if ((v ?? '') !== fmtTime(r.warehouse_start_time)) inline.mutate({ row: r, patch: { warehouse_start_time: v } })
                            }}
                            className="w-full rounded border border-transparent bg-transparent px-1 py-0.5 text-sm hover:border-[var(--border)] focus:border-brand-500 focus:outline-none"
                          />
                        </div>
                        <div className="w-24 shrink-0 px-1">
                          <input
                            type="time"
                            defaultValue={fmtTime(r.onsite_start_time)}
                            disabled={!canEdit}
                            onBlur={(e) => {
                              const v = e.target.value || null
                              if ((v ?? '') !== fmtTime(r.onsite_start_time)) inline.mutate({ row: r, patch: { onsite_start_time: v } })
                            }}
                            className="w-full rounded border border-transparent bg-transparent px-1 py-0.5 text-sm hover:border-[var(--border)] focus:border-brand-500 focus:outline-none"
                          />
                        </div>
                        <div className="w-20 shrink-0 px-2" dir="ltr">{fmtTime(r.onsite_end_time)}</div>
                        <div className="w-16 shrink-0 px-1">
                          <input
                            type="number"
                            step="0.5"
                            min="0"
                            defaultValue={r.hours_count ?? ''}
                            disabled={!canEdit}
                            title={fmtHours(r.hours_count)}
                            onBlur={(e) => {
                              const v = e.target.value === '' ? null : Number(e.target.value)
                              if (v !== r.hours_count) inline.mutate({ row: r, patch: { hours_count: v } })
                            }}
                            className="w-full rounded border border-transparent bg-transparent px-1 py-0.5 text-sm hover:border-[var(--border)] focus:border-brand-500 focus:outline-none"
                          />
                        </div>
                        <div className="w-16 shrink-0 px-1">
                          <input
                            type="number"
                            min="0"
                            defaultValue={r.worker_count}
                            disabled={!canEdit}
                            onBlur={(e) => {
                              const v = Number(e.target.value) || 0
                              if (v !== r.worker_count) inline.mutate({ row: r, patch: { worker_count: v } })
                            }}
                            className="w-full rounded border border-transparent bg-transparent px-1 py-0.5 text-sm hover:border-[var(--border)] focus:border-brand-500 focus:outline-none"
                          />
                        </div>
                        <div className="w-16 shrink-0 px-2">{r.event_truck_count ?? ''}</div>
                        <div className="w-14 shrink-0 px-2">{r.volume_m ?? ''}</div>
                        <div className="w-32 shrink-0 px-1">
                          <select
                            value={r.truck_id ?? ''}
                            disabled={!canEdit}
                            onChange={(e) => inline.mutate({ row: r, patch: { truck_id: e.target.value || null } })}
                            className="w-full truncate rounded border border-transparent bg-transparent px-1 py-0.5 text-sm hover:border-[var(--border)] focus:border-brand-500 focus:outline-none"
                          >
                            <option value="">{r.truck_free_text || '—'}</option>
                            {trucks.filter((t) => t.is_active).map((t) => (
                              <option key={t.id} value={t.id}>{t.name}</option>
                            ))}
                          </select>
                        </div>
                        <div className="w-32 shrink-0 px-1">
                          <select
                            value={r.execution_method_id ?? ''}
                            disabled={!canEdit}
                            onChange={(e) => inline.mutate({ row: r, patch: { execution_method_id: e.target.value || null } })}
                            className="w-full truncate rounded border border-transparent bg-transparent px-1 py-0.5 text-sm hover:border-[var(--border)] focus:border-brand-500 focus:outline-none"
                          >
                            <option value="">—</option>
                            {methods.filter((m) => m.is_active).map((m) => (
                              <option key={m.id} value={m.id}>{m.name}</option>
                            ))}
                          </select>
                        </div>
                        <div className="w-28 shrink-0 truncate px-2">{r.team_lead_name}</div>
                        <div className="w-44 shrink-0 truncate px-2 text-xs" title={[...(r.workers ?? []).map((w) => w.name), ...(r.drivers ?? []).map((d) => `${d.name}${d.truck_name ? ` (${d.truck_name})` : ''}`)].join(', ')}>
                          {(r.workers ?? []).map((w) => w.name).join(', ')}
                          {(r.drivers ?? []).length > 0 && (
                            <span className="text-[var(--muted)]">
                              {(r.workers ?? []).length > 0 && ' · '}
                              🚚 {(r.drivers ?? []).map((d) => `${d.name}${d.truck_name ? ` (${d.truck_name})` : ''}`).join(', ')}
                            </span>
                          )}
                          {(r.contractor_worker_list ?? []).length > 0 && (
                            <span className="text-amber-600 dark:text-amber-400">
                              {' '}👷 {(r.contractor_worker_list ?? []).map((w) => w.name).join(', ')}
                            </span>
                          )}
                        </div>
                        <div className="w-28 shrink-0 truncate px-2">{r.contractor_name}</div>
                        <div className="w-28 shrink-0 px-1">
                          <select
                            value={r.status_id}
                            disabled={!canEdit}
                            onChange={(e) => inline.mutate({ row: r, patch: { status_id: e.target.value } })}
                            className="w-full truncate rounded border px-1 py-0.5 text-xs font-medium focus:outline-none"
                            style={{
                              background: `color-mix(in srgb, ${r.status_color} 14%, transparent)`,
                              color: r.status_color,
                              borderColor: 'transparent',
                            }}
                          >
                            {statuses.map((s) => (
                              <option key={s.id} value={s.id} style={{ color: 'var(--text)', background: 'var(--panel)' }}>
                                {s.name}
                              </option>
                            ))}
                          </select>
                        </div>
                        <div className="w-40 shrink-0 px-1">
                          <input
                            defaultValue={r.notes ?? ''}
                            disabled={!canEdit}
                            onBlur={(e) => {
                              const v = e.target.value || null
                              if (v !== r.notes) inline.mutate({ row: r, patch: { notes: v } })
                            }}
                            className="w-full rounded border border-transparent bg-transparent px-1 py-0.5 text-sm hover:border-[var(--border)] focus:border-brand-500 focus:outline-none"
                          />
                        </div>
                        <div className="w-10 shrink-0 px-1">
                          <button
                            onClick={() => setDrawer({ open: true, taskId: r.id })}
                            className="rounded p-1 text-[var(--muted)] hover:bg-[var(--border)] hover:text-[var(--text)]"
                            title="פתיחת משימה"
                          >
                            <Pencil size={13} />
                          </button>
                        </div>
                      </div>
                    )
                  })}
                </div>
              </div>
            </div>
          )}
        </div>

        <TaskDrawer open={drawer.open} onClose={() => setDrawer({ open: false, taskId: null })} taskId={drawer.taskId} />
        <BulkEditModal
          open={bulkOpen}
          onClose={() => setBulkOpen(false)}
          taskIds={[...selected]}
          onDone={() => {
            setSelected(new Set())
            setBulkOpen(false)
          }}
        />
      </div>
    </RequirePermission>
  )
}

function BulkEditModal({ open, onClose, taskIds, onDone }: { open: boolean; onClose: () => void; taskIds: string[]; onDone: () => void }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { data: statuses = [] } = useStatuses('task')
  const { data: contractors = [] } = useContractors()
  const { data: methods = [] } = useExecutionMethods()
  const [patch, setPatch] = useState<Record<string, string>>({})

  const apply = useMutation({
    mutationFn: async () => {
      const clean: Record<string, string> = {}
      for (const [k, v] of Object.entries(patch)) if (v !== '__skip__') clean[k] = v
      if (Object.keys(clean).length === 0) throw new Error('לא נבחרו שדות לעדכון')
      const { data, error } = await supabase.rpc('bulk_update_tasks', { p_task_ids: taskIds, p_patch: clean })
      if (error) throw error
      return data as number
    },
    onSuccess: (count) => {
      toast.success(`${count} משימות עודכנו`)
      void qc.invalidateQueries({ queryKey: ['workboard'] })
      void qc.invalidateQueries({ queryKey: ['calendar'] })
      setPatch({})
      onDone()
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const setIf = (key: string, value: string) => setPatch((p) => ({ ...p, [key]: value }))

  return (
    <Modal open={open} onClose={onClose} title={`עריכה מרובה — ${taskIds.length} משימות`}>
      <div className="space-y-3">
        <Field label="סטטוס">
          <Select value={patch.status_id ?? '__skip__'} onChange={(e) => setIf('status_id', e.target.value)}>
            <option value="__skip__">ללא שינוי</option>
            {statuses.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </Select>
        </Field>
        <Field label="תאריך">
          <Input type="date" value={patch.task_date ?? ''} onChange={(e) => setIf('task_date', e.target.value || '__skip__')} />
        </Field>
        <Field label="אופן ביצוע">
          <Select value={patch.execution_method_id ?? '__skip__'} onChange={(e) => setIf('execution_method_id', e.target.value)}>
            <option value="__skip__">ללא שינוי</option>
            {methods.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}
          </Select>
        </Field>
        <Field label="קבלן">
          <Select value={patch.contractor_id ?? '__skip__'} onChange={(e) => setIf('contractor_id', e.target.value)}>
            <option value="__skip__">ללא שינוי</option>
            <option value="">הסרת קבלן</option>
            {contractors.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </Select>
        </Field>
        <Field label="שעת התחלה במחסן">
          <Input type="time" value={patch.warehouse_start_time ?? ''} onChange={(e) => setIf('warehouse_start_time', e.target.value || '__skip__')} />
        </Field>
        <div className="flex justify-end gap-2 pt-2">
          <Button onClick={onClose}>ביטול</Button>
          <Button variant="primary" loading={apply.isPending} onClick={() => apply.mutate()}>עדכון</Button>
        </div>
      </div>
    </Modal>
  )
}
