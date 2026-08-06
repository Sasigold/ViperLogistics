import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import {
  Button, Drawer, Field, Input, MultiSelect, Select, Textarea, Spinner, useToast, useConfirm,
} from '../../components/ui'
import {
  useContractors, useCustomerExecutionMethods, useExecutionMethods, useStatuses, useStaff,
  useTaskTypeMethods, useTaskTypes, useTrucks,
} from '../../lib/queries'
import type { StaffRole, TaskRow } from '../../types/domain'

interface Assignment {
  id?: string
  profile_id: string
  role: StaffRole
  truck_id: string | null
}

export interface TaskDrawerProps {
  open: boolean
  onClose: () => void
  taskId?: string | null
  /** initial values for a new task */
  initial?: Partial<TaskRow>
}

export function TaskDrawer({ open, onClose, taskId, initial }: TaskDrawerProps) {
  const qc = useQueryClient()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const can = useAuth((s) => s.can)
  const canEdit = can('tasks', 'edit') || (!taskId && can('tasks', 'create'))

  const { data: taskTypes = [] } = useTaskTypes()
  const { data: methods = [] } = useExecutionMethods()
  const { data: typeMethods = [] } = useTaskTypeMethods()
  const { data: statuses = [] } = useStatuses('task')
  const { data: trucks = [] } = useTrucks()
  const { data: contractors = [] } = useContractors()
  const { data: staff = [] } = useStaff()

  const { data: existing, isLoading } = useQuery({
    queryKey: ['tasks', 'one', taskId],
    enabled: open && !!taskId,
    queryFn: async () => {
      const [t, a, terms] = await Promise.all([
        supabase.from('tasks').select('*').eq('id', taskId).single(),
        supabase.from('task_assignments').select('*').eq('task_id', taskId),
        supabase.from('task_contractor_terms').select('*').eq('task_id', taskId).maybeSingle(),
      ])
      if (t.error) throw t.error
      return {
        task: t.data as TaskRow,
        assignments: (a.data ?? []) as Assignment[],
        terms: terms.data as { price: number; paid_at: string | null } | null,
      }
    },
  })

  const [form, setForm] = useState<Partial<TaskRow>>({})
  const [assignments, setAssignments] = useState<Assignment[]>([])
  const [price, setPrice] = useState<string>('')

  useEffect(() => {
    if (!open) return
    if (taskId && existing) {
      setForm(existing.task)
      setAssignments(existing.assignments)
      setPrice(existing.terms?.price != null ? String(existing.terms.price) : '')
    } else if (!taskId) {
      setForm({ task_date: new Date().toISOString().slice(0, 10), worker_count: 0, ...initial })
      setAssignments([])
      setPrice('')
    }
  }, [open, taskId, existing, initial])

  const customerMethodsQ = useCustomerExecutionMethods(form.customer_id)
  const allowedMethods = useMemo(() => {
    let list = methods.filter((m) => m.is_active)
    if (form.task_type_id) {
      const forType = typeMethods.filter((tm) => tm.task_type_id === form.task_type_id).map((tm) => tm.execution_method_id)
      if (forType.length) list = list.filter((m) => forType.includes(m.id))
    }
    if (form.customer_id && customerMethodsQ.data) {
      list = list.filter((m) => customerMethodsQ.data.includes(m.id))
    }
    return list
  }, [methods, typeMethods, form.task_type_id, form.customer_id, customerMethodsQ.data])

  const set = (patch: Partial<TaskRow>) => setForm((f) => ({ ...f, ...patch }))

  const save = useMutation({
    mutationFn: async () => {
      if (!form.task_type_id) throw new Error('חובה לבחור סוג משימה')
      if (!form.task_date) throw new Error('חובה לבחור תאריך')
      const base = {
        event_id: form.event_id ?? null,
        task_type_id: form.task_type_id,
        title: form.title || null,
        task_date: form.task_date,
        onsite_start_time: form.onsite_start_time || null,
        warehouse_start_time: form.warehouse_start_time || null,
        hours_count: form.hours_count ?? null,
        worker_count: form.worker_count ?? 0,
        execution_method_id: form.execution_method_id || null,
        truck_id: form.truck_id || null,
        truck_free_text: form.truck_free_text || null,
        notes: form.notes || null,
        status_id: form.status_id || statuses.find((s) => s.is_default)?.id,
        contractor_id: form.contractor_id || null,
        location_text: form.location_text || null,
      }
      let id = taskId
      if (taskId) {
        const { error } = await supabase.from('tasks').update(base).eq('id', taskId)
        if (error) throw error
      } else {
        const { data, error } = await supabase.from('tasks').insert(base).select('id').single()
        if (error) throw error
        id = data.id
      }
      // sync assignments (delete + reinsert is fine at this scale; audit keeps history)
      const { data: current } = await supabase.from('task_assignments').select('id, profile_id, role, truck_id').eq('task_id', id)
      const wanted = assignments.map((a) => `${a.profile_id}:${a.role}:${a.truck_id ?? ''}`)
      const existingKeys = (current ?? []).map((a) => `${a.profile_id}:${a.role}:${a.truck_id ?? ''}`)
      const toDelete = (current ?? []).filter((a) => !wanted.includes(`${a.profile_id}:${a.role}:${a.truck_id ?? ''}`))
      const toInsert = assignments.filter((a) => !existingKeys.includes(`${a.profile_id}:${a.role}:${a.truck_id ?? ''}`))
      if (toDelete.length) {
        const { error } = await supabase.from('task_assignments').delete().in('id', toDelete.map((a) => a.id))
        if (error) throw error
      }
      if (toInsert.length) {
        const { error } = await supabase.from('task_assignments').insert(
          toInsert.map((a) => ({ task_id: id, profile_id: a.profile_id, role: a.role, truck_id: a.truck_id })),
        )
        if (error) throw error
      }
      // contractor price
      if (base.contractor_id && price !== '') {
        const { error } = await supabase
          .from('task_contractor_terms')
          .update({ price: Number(price) })
          .eq('task_id', id)
        if (error) throw error
      }
    },
    onSuccess: () => {
      toast.success('המשימה נשמרה')
      void qc.invalidateQueries({ queryKey: ['tasks'] })
      void qc.invalidateQueries({ queryKey: ['workboard'] })
      void qc.invalidateQueries({ queryKey: ['calendar'] })
      onClose()
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const remove = async () => {
    if (!taskId) return
    if (!(await confirm('למחוק את המשימה? ניתן לשחזר מסל המיחזור בהגדרות.'))) return
    const { error } = await supabase.rpc('soft_delete', { p_table: 'tasks', p_id: taskId })
    if (error) toast.error(error.message)
    else {
      toast.success('המשימה נמחקה')
      void qc.invalidateQueries({ queryKey: ['tasks'] })
      void qc.invalidateQueries({ queryKey: ['workboard'] })
      void qc.invalidateQueries({ queryKey: ['calendar'] })
      onClose()
    }
  }

  const byRole = (role: StaffRole) => assignments.filter((a) => a.role === role)
  const toggleAssignment = (role: StaffRole, profileId: string) => {
    setAssignments((prev) => {
      const found = prev.find((a) => a.role === role && a.profile_id === profileId)
      if (found) return prev.filter((a) => a !== found)
      if (role === 'team_lead') {
        return [...prev.filter((a) => a.role !== 'team_lead'), { profile_id: profileId, role, truck_id: null }]
      }
      return [...prev, { profile_id: profileId, role, truck_id: null }]
    })
  }

  const staffOptions = (role: StaffRole) =>
    staff
      .filter((p) => (p.staff_roles ?? []).some((r) => r.role === role))
      .map((p) => ({ id: p.id, label: p.full_name }))

  const selectedType = taskTypes.find((t) => t.id === form.task_type_id)

  return (
    <Drawer open={open} onClose={onClose} title={taskId ? `עריכת משימה${selectedType ? ` — ${selectedType.name}` : ''}` : 'משימה חדשה'}>
      {dialog}
      {taskId && isLoading ? (
        <Spinner full />
      ) : (
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <Field label="סוג משימה" required>
              <Select value={form.task_type_id ?? ''} onChange={(e) => set({ task_type_id: e.target.value })} disabled={!canEdit}>
                <option value="">בחירה...</option>
                {taskTypes.filter((t) => t.is_active).map((t) => (
                  <option key={t.id} value={t.id}>{t.name}</option>
                ))}
              </Select>
            </Field>
            <Field label="סטטוס">
              <Select value={form.status_id ?? ''} onChange={(e) => set({ status_id: e.target.value })} disabled={!canEdit}>
                <option value="">ברירת מחדל</option>
                {statuses.map((s) => (
                  <option key={s.id} value={s.id}>{s.name}</option>
                ))}
              </Select>
            </Field>
          </div>

          {!form.event_id && (
            <Field label="כותרת (משימה שאינה משויכת לאירוע)">
              <Input value={form.title ?? ''} onChange={(e) => set({ title: e.target.value })} placeholder="למשל: סידור מחסן, טיפול במשאית..." disabled={!canEdit} />
            </Field>
          )}

          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <Field label="תאריך" required>
              <Input type="date" value={form.task_date ?? ''} onChange={(e) => set({ task_date: e.target.value })} disabled={!canEdit} />
            </Field>
            <Field label="תחילה במחסן">
              <Input type="time" value={form.warehouse_start_time?.slice(0, 5) ?? ''} onChange={(e) => set({ warehouse_start_time: e.target.value || null })} disabled={!canEdit} />
            </Field>
            <Field label="תחילה בשטח">
              <Input type="time" value={form.onsite_start_time?.slice(0, 5) ?? ''} onChange={(e) => set({ onsite_start_time: e.target.value || null })} disabled={!canEdit} />
            </Field>
            <Field label="כמות שעות">
              <Input type="number" step="0.5" min="0" value={form.hours_count ?? ''} onChange={(e) => set({ hours_count: e.target.value === '' ? null : Number(e.target.value) })} disabled={!canEdit} />
            </Field>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <Field label="כמות עובדים">
              <Input type="number" min="0" value={form.worker_count ?? 0} onChange={(e) => set({ worker_count: Number(e.target.value) || 0 })} disabled={!canEdit} />
            </Field>
            <Field label="אופן ביצוע">
              <Select value={form.execution_method_id ?? ''} onChange={(e) => set({ execution_method_id: e.target.value || null })} disabled={!canEdit}>
                <option value="">בחירה...</option>
                {allowedMethods.map((m) => (
                  <option key={m.id} value={m.id}>{m.name}</option>
                ))}
              </Select>
            </Field>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <Field label="משאית (מרשימה)">
              <Select value={form.truck_id ?? ''} onChange={(e) => set({ truck_id: e.target.value || null })} disabled={!canEdit}>
                <option value="">—</option>
                {trucks.filter((t) => t.is_active).map((t) => (
                  <option key={t.id} value={t.id}>{t.name}</option>
                ))}
              </Select>
            </Field>
            <Field label="משאית (מלל חופשי)">
              <Input value={form.truck_free_text ?? ''} onChange={(e) => set({ truck_free_text: e.target.value })} disabled={!canEdit} />
            </Field>
          </div>

          {!form.event_id && (
            <Field label="מיקום">
              <Input value={form.location_text ?? ''} onChange={(e) => set({ location_text: e.target.value })} disabled={!canEdit} />
            </Field>
          )}

          <Field label="הערות">
            <Textarea value={form.notes ?? ''} onChange={(e) => set({ notes: e.target.value })} disabled={!canEdit} />
          </Field>

          {/* assignments */}
          <div className="space-y-3 rounded-lg border border-[var(--border)] p-3">
            <h3 className="text-xs font-bold text-[var(--muted)]">שיבוץ צוות</h3>
            <Field label="ראש צוות">
              <MultiSelect
                options={staffOptions('team_lead')}
                values={byRole('team_lead').map((a) => a.profile_id)}
                onToggle={(id) => canEdit && toggleAssignment('team_lead', id)}
                placeholder="בחירת ראש צוות..."
              />
            </Field>
            <Field label="עובדים">
              <MultiSelect
                options={staffOptions('worker')}
                values={byRole('worker').map((a) => a.profile_id)}
                onToggle={(id) => canEdit && toggleAssignment('worker', id)}
                placeholder="בחירת עובדים..."
              />
            </Field>
            <Field label="נהגים">
              <MultiSelect
                options={staffOptions('driver')}
                values={byRole('driver').map((a) => a.profile_id)}
                onToggle={(id) => canEdit && toggleAssignment('driver', id)}
                placeholder="בחירת נהגים..."
              />
            </Field>
            {byRole('driver').length > 0 && (
              <div className="space-y-1.5">
                <p className="text-xs font-medium text-[var(--muted)]">שיוך נהג ↔ משאית</p>
                {byRole('driver').map((a) => (
                  <div key={a.profile_id} className="flex items-center gap-2 text-sm">
                    <span className="w-32 truncate">{staff.find((p) => p.id === a.profile_id)?.full_name}</span>
                    <Select
                      value={a.truck_id ?? ''}
                      onChange={(e) =>
                        setAssignments((prev) => prev.map((x) => (x === a ? { ...x, truck_id: e.target.value || null } : x)))
                      }
                      disabled={!canEdit}
                    >
                      <option value="">ללא משאית</option>
                      {trucks.filter((t) => t.is_active).map((t) => (
                        <option key={t.id} value={t.id}>{t.name}</option>
                      ))}
                    </Select>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* contractor delegation */}
          {can('contractors', 'view') && (
            <div className="space-y-3 rounded-lg border border-[var(--border)] p-3">
              <h3 className="text-xs font-bold text-[var(--muted)]">האצלה לקבלן</h3>
              <div className="grid grid-cols-2 gap-3">
                <Field label="קבלן">
                  <Select value={form.contractor_id ?? ''} onChange={(e) => set({ contractor_id: e.target.value || null })} disabled={!canEdit || !can('contractors', 'edit')}>
                    <option value="">ללא קבלן</option>
                    {contractors.filter((c) => c.is_active).map((c) => (
                      <option key={c.id} value={c.id}>{c.name}</option>
                    ))}
                  </Select>
                </Field>
                {form.contractor_id && (
                  <Field label="מחיר לקבלן (₪)">
                    <Input type="number" min="0" value={price} onChange={(e) => setPrice(e.target.value)} disabled={!can('contractors', 'edit')} />
                  </Field>
                )}
              </div>
            </div>
          )}

          <div className="flex justify-between gap-2 pt-2">
            {taskId && can('tasks', 'delete') ? (
              <Button variant="danger" onClick={() => void remove()}>מחיקה</Button>
            ) : <span />}
            <div className="flex gap-2">
              <Button onClick={onClose}>ביטול</Button>
              {canEdit && (
                <Button variant="primary" loading={save.isPending} onClick={() => save.mutate()}>
                  שמירה
                </Button>
              )}
            </div>
          </div>
        </div>
      )}
    </Drawer>
  )
}
