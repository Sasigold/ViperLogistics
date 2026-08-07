import { useEffect, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Banknote,
  Briefcase,
  Clock,
  HardHat,
  ICON,
  MapPin,
  RefreshCw,
  STROKE,
  Trash2,
  Truck,
  Users,
} from '../../components/ui/icons'
import {
  AvatarGroup,
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  Drawer,
  Field,
  Input,
  MultiSelect,
  SegmentedControl,
  Select,
  Skeleton,
  Textarea,
  cx,
  useConfirm,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import {
  useAllowedExecutionMethods,
  useContractors,
  useStaff,
  useStatuses,
  useTaskTypes,
  useTrucks,
} from '../../lib/queries'
import { Breakdown } from '../customers/PricingTab'
import { useWarehouses } from '../attendance/attendanceQueries'
import type { PriceBreakdown, StaffRole, TaskPricing, TaskRow, WorkSite } from '../../types/domain'
import { errorMessage } from '../../lib/errors'

interface Assignment {
  id?: string
  profile_id: string
  role: StaffRole
  truck_id: string | null
  /** מהיכן הוא מתחיל — קובע את שעת ההתחלה של המשמרת שלו */
  work_site: WorkSite
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
  const has = useAuth((s) => s.has)
  /**
   * One gate per thing that can change, matching the keys the column trigger
   * enforces. On a new task the create permission stands in for all of them —
   * the field trigger only judges updates.
   */
  const isNew = !taskId
  const canCreate = has(PERM.TASKS_CREATE)
  const gate = (perm: string) => (isNew ? canCreate : has(perm))
  const canEdit = isNew ? canCreate : has(PERM.TASKS_EDIT)
  const canReschedule = gate(PERM.TASKS_RESCHEDULE)
  const canChangeStatus = gate(PERM.TASKS_CHANGE_STATUS)
  const canChangeType = gate(PERM.TASKS_CHANGE_TYPE)
  const canChangeWorkerCount = gate(PERM.TASKS_CHANGE_WORKER_COUNT)
  const canChangeMethod = gate(PERM.TASKS_CHANGE_EXECUTION_METHOD)
  const canChangeTruck = gate(PERM.TASKS_CHANGE_TRUCK)
  const canChangeLocation = gate(PERM.TASKS_CHANGE_LOCATION)
  const canEditNotes = gate(PERM.TASKS_EDIT_NOTES)
  const canDelegate = gate(PERM.TASKS_DELEGATE)
  const canViewPricing = has(PERM.CONTRACTORS_VIEW_PRICING)
  const canEditPricing = has(PERM.CONTRACTORS_EDIT_PRICING)
  // מחיר הלקוח ומחיר הקבלן הם שני דברים שונים עם שני מפתחות שונים: מי
  // שמנהל תשלומים לקבלנים לא בהכרח אמור לראות כמה גובים.
  const canViewCustomerPrice = has(PERM.PRICING_VIEW)
  const canEditCustomerPrice = has(PERM.PRICING_EDIT)
  const canAssign: Record<StaffRole, boolean> = {
    worker: has(PERM.TASKS_ASSIGN_WORKER),
    driver: has(PERM.TASKS_ASSIGN_DRIVER),
    team_lead: has(PERM.TASKS_ASSIGN_TEAM_LEAD),
  }
  const canAssignAny = canAssign.worker || canAssign.driver || canAssign.team_lead

  const { data: taskTypes = [] } = useTaskTypes()
  const { data: statuses = [] } = useStatuses('task')
  const { data: trucks = [] } = useTrucks()
  const { data: contractors = [] } = useContractors()
  const { data: staff = [] } = useStaff()
  const { data: warehouses = [] } = useWarehouses()

  const { data: existing, isLoading } = useQuery({
    queryKey: ['tasks', 'one', taskId],
    enabled: open && !!taskId,
    queryFn: async () => {
      // task_pricing חסומה ב-RLS למי שאין לו pricing.view, ומחזירה אז פשוט
      // כלום — ולכן היא נשלפת כאן בלי תנאי והכרטיס הוא שמגודר.
      const [t, a, terms, pricing] = await Promise.all([
        supabase.from('tasks').select('*').eq('id', taskId).single(),
        supabase.from('task_assignments').select('*').eq('task_id', taskId),
        supabase.from('task_contractor_terms').select('*').eq('task_id', taskId).maybeSingle(),
        supabase.from('task_pricing').select('*').eq('task_id', taskId).maybeSingle(),
      ])
      if (t.error) throw t.error
      return {
        task: t.data as TaskRow,
        assignments: (a.data ?? []) as Assignment[],
        terms: terms.data as { price: number; paid_at: string | null } | null,
        pricing: (pricing.data as TaskPricing) ?? null,
      }
    },
  })

  const [form, setForm] = useState<Partial<TaskRow>>({})
  const [assignments, setAssignments] = useState<Assignment[]>([])
  const [price, setPrice] = useState<string>('')
  const [customerPrice, setCustomerPrice] = useState<string>('')
  const [touched, setTouched] = useState(false)

  useEffect(() => {
    if (!open) return
    setTouched(false)
    if (taskId && existing) {
      setForm(existing.task)
      setAssignments(existing.assignments)
      setPrice(existing.terms?.price != null ? String(existing.terms.price) : '')
      setCustomerPrice(existing.pricing?.price != null ? String(existing.pricing.price) : '')
    } else if (!taskId) {
      setForm({ task_date: new Date().toISOString().slice(0, 10), worker_count: 0, ...initial })
      setAssignments([])
      setPrice('')
      setCustomerPrice('')
    }
  }, [open, taskId, existing, initial])

  const allowedMethods = useAllowedExecutionMethods(form.task_type_id, form.customer_id)

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
        warehouse_id: form.warehouse_id || null,
        ...(canEditCustomerPrice
          ? { travel_hours: form.travel_hours ?? null, requires_team_lead: form.requires_team_lead ?? null }
          : {}),
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
      const { data: current } = await supabase.from('task_assignments').select('id, profile_id, role, truck_id, work_site').eq('task_id', id)
      const key = (a: { profile_id: string; role: string; truck_id: string | null; work_site?: string | null }) =>
        `${a.profile_id}:${a.role}:${a.truck_id ?? ''}:${a.work_site ?? 'field'}`
      const wanted = assignments.map(key)
      const existingKeys = (current ?? []).map(key)
      const toDelete = (current ?? []).filter((a) => !wanted.includes(key(a)))
      const toInsert = assignments.filter((a) => !existingKeys.includes(key(a)))
      if (toDelete.length) {
        const { error } = await supabase
          .from('task_assignments')
          .delete()
          .in('id', toDelete.map((a) => a.id))
        if (error) throw error
      }
      if (toInsert.length) {
        const { error } = await supabase
          .from('task_assignments')
          .insert(
            toInsert.map((a) => ({
              task_id: id,
              profile_id: a.profile_id,
              role: a.role,
              truck_id: a.truck_id,
              work_site: a.work_site,
            })),
          )
        if (error) throw error
      }
      // contractor price
      if (base.contractor_id && price !== '') {
        const { error } = await supabase.from('task_contractor_terms').update({ price: Number(price) }).eq('task_id', id)
        if (error) throw error
      }
      // מחיר ללקוח. נכתב רק כשהוא באמת השתנה, כי כל כתיבה נועלת את המחיר
      // מפני חישוב מחדש — שמירה של המגירה בלי שנגעו בשדה לא אמורה לנעול.
      const before = existing?.pricing?.price
      if (canEditCustomerPrice && customerPrice !== '' && Number(customerPrice) !== before) {
        const { error } = await supabase
          .from('task_pricing')
          .upsert({ task_id: id, price: Number(customerPrice) }, { onConflict: 'task_id' })
        if (error) throw error
      }
    },
    onSuccess: () => {
      toast.success('המשימה נשמרה')
      void qc.invalidateQueries({ queryKey: ['tasks'] })
      void qc.invalidateQueries({ queryKey: ['workboard'] })
      void qc.invalidateQueries({ queryKey: ['calendar'] })
      void qc.invalidateQueries({ queryKey: ['dashboard'] })
      void qc.invalidateQueries({ queryKey: ['task_pricing'] })
      onClose()
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  // מנקה את הנעילה הידנית ומחשב מהמחשבון של הלקוח.
  const recalcPrice = useMutation({
    mutationFn: async () => {
      if (!taskId) return null
      const { data, error } = await supabase.rpc('recalculate_task_price', { p_task_id: taskId })
      if (error) throw error
      return data as PriceBreakdown
    },
    onSuccess: (r) => {
      if (r) setCustomerPrice(String(r.total))
      toast.success('המחיר חושב מחדש')
      void qc.invalidateQueries({ queryKey: ['tasks', 'one', taskId] })
      void qc.invalidateQueries({ queryKey: ['workboard'] })
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const remove = async () => {
    if (!taskId) return
    if (
      !(await confirm('למחוק את המשימה? ניתן לשחזר מסל המיחזור בהגדרות.', {
        title: 'מחיקת משימה',
        confirmLabel: 'מחיקה',
      }))
    )
      return
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
        return [
          ...prev.filter((a) => a.role !== 'team_lead'),
          { profile_id: profileId, role, truck_id: null, work_site: 'field' as WorkSite },
        ]
      }
      return [...prev, { profile_id: profileId, role, truck_id: null, work_site: 'field' as WorkSite }]
    })
  }

  const staffOptions = (role: StaffRole) =>
    staff.filter((p) => (p.staff_roles ?? []).some((r) => r.role === role)).map((p) => ({ id: p.id, label: p.full_name }))

  const nameOf = (id: string) => staff.find((p) => p.id === id)?.full_name ?? ''
  const selectedType = taskTypes.find((t) => t.id === form.task_type_id)

  const typeError = touched && !form.task_type_id ? 'חובה לבחור סוג משימה' : undefined
  const dateError = touched && !form.task_date ? 'חובה לבחור תאריך' : undefined

  /* staffing progress — the single number a dispatcher checks most often */
  const assignedCount = byRole('worker').length + byRole('driver').length
  const needed = form.worker_count ?? 0
  const understaffed = needed > 0 && assignedCount < needed

  return (
    <Drawer
      open={open}
      onClose={onClose}
      /* the drawer is already read-only without the keys — the title should say
         so rather than promise an edit the footer will not offer */
      title={
        taskId
          ? `${canEdit || canAssignAny ? 'עריכת משימה' : 'פרטי משימה'}${selectedType ? ` — ${selectedType.name}` : ''}`
          : 'משימה חדשה'
      }
      description={taskId ? undefined : 'משימה שאינה משויכת לאירוע — למשל סידור מחסן או טיפול ברכב'}
      footer={
        <>
          {taskId && has(PERM.TASKS_DELETE) ? (
            <Button variant="danger" onClick={() => void remove()}>
              <Trash2 size={ICON.sm} strokeWidth={STROKE} />
              מחיקה
            </Button>
          ) : (
            <span />
          )}
          <div className="ms-auto flex gap-2">
            <Button onClick={onClose}>ביטול</Button>
            {(canEdit || canAssignAny) && (
              <Button
                variant="primary"
                loading={save.isPending}
                onClick={() => {
                  setTouched(true)
                  save.mutate()
                }}
              >
                שמירה
              </Button>
            )}
          </div>
        </>
      }
    >
      {dialog}
      {taskId && isLoading ? (
        <div className="space-y-4">
          <Skeleton className="h-20 w-full" />
          <Skeleton className="h-40 w-full" />
          <Skeleton className="h-32 w-full" />
        </div>
      ) : (
        <div className="space-y-4">
          {/* ── what ─────────────────────────────────────────────────────── */}
          <Card>
            <CardHeader title="מהות המשימה" icon={<Briefcase size={ICON.md} strokeWidth={STROKE} />} />
            <CardBody className="space-y-4">
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label="סוג משימה" required error={typeError}>
                  <Select
                    data-autofocus
                    value={form.task_type_id ?? ''}
                    onChange={(e) => set({ task_type_id: e.target.value })}
                    disabled={!canChangeType}
                  >
                    <option value="">בחירה...</option>
                    {taskTypes
                      .filter((t) => t.is_active)
                      .map((t) => (
                        <option key={t.id} value={t.id}>
                          {t.name}
                        </option>
                      ))}
                  </Select>
                </Field>
                <Field label="סטטוס">
                  <Select value={form.status_id ?? ''} onChange={(e) => set({ status_id: e.target.value })} disabled={!canChangeStatus}>
                    <option value="">ברירת מחדל</option>
                    {statuses.map((s) => (
                      <option key={s.id} value={s.id}>
                        {s.name}
                      </option>
                    ))}
                  </Select>
                </Field>
              </div>

              {!form.event_id && (
                <>
                  <Field label="כותרת" hint="משימה שאינה משויכת לאירוע">
                    <Input
                      value={form.title ?? ''}
                      onChange={(e) => set({ title: e.target.value })}
                      placeholder="למשל: סידור מחסן, טיפול במשאית..."
                      disabled={!canEdit}
                    />
                  </Field>
                  <Field label="מיקום">
                    <Input
                      leading={<MapPin size={ICON.sm} strokeWidth={STROKE} />}
                      value={form.location_text ?? ''}
                      onChange={(e) => set({ location_text: e.target.value })}
                      disabled={!canChangeLocation}
                    />
                  </Field>
                </>
              )}
            </CardBody>
          </Card>

          {/* ── when ─────────────────────────────────────────────────────── */}
          <Card>
            <CardHeader title="תזמון" icon={<Clock size={ICON.md} strokeWidth={STROKE} />} />
            <CardBody>
              <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                <Field label="תאריך" required error={dateError}>
                  <Input type="date" value={form.task_date ?? ''} onChange={(e) => set({ task_date: e.target.value })} disabled={!canReschedule} />
                </Field>
                <Field label="תחילה במחסן">
                  <Input
                    type="time"
                    value={form.warehouse_start_time?.slice(0, 5) ?? ''}
                    onChange={(e) => set({ warehouse_start_time: e.target.value || null })}
                    disabled={!canReschedule}
                  />
                </Field>
                <Field label="תחילה בשטח">
                  <Input
                    type="time"
                    value={form.onsite_start_time?.slice(0, 5) ?? ''}
                    onChange={(e) => set({ onsite_start_time: e.target.value || null })}
                    disabled={!canReschedule}
                  />
                </Field>
                <Field label="כמות שעות">
                  <Input
                    type="number"
                    step="0.5"
                    min="0"
                    value={form.hours_count ?? ''}
                    onChange={(e) => set({ hours_count: e.target.value === '' ? null : Number(e.target.value) })}
                    disabled={!canReschedule}
                  />
                </Field>
              </div>
            </CardBody>
          </Card>

          {/* ── resources ────────────────────────────────────────────────── */}
          <Card>
            <CardHeader title="משאבים" icon={<Truck size={ICON.md} strokeWidth={STROKE} />} />
            <CardBody>
              <div className="grid gap-4 sm:grid-cols-2">
                <Field
                  label="כמות עובדים נדרשת"
                  hint={understaffed ? undefined : 'מספר האנשים שהמשימה דורשת'}
                  error={understaffed ? `שובצו ${assignedCount} מתוך ${needed}` : undefined}
                >
                  <Input
                    type="number"
                    min="0"
                    value={form.worker_count ?? 0}
                    onChange={(e) => set({ worker_count: Number(e.target.value) || 0 })}
                    disabled={!canChangeWorkerCount}
                  />
                </Field>
                <Field label="אופן ביצוע" hint="הרשימה מסוננת לפי סוג המשימה והלקוח">
                  <Select
                    value={form.execution_method_id ?? ''}
                    onChange={(e) => set({ execution_method_id: e.target.value || null })}
                    disabled={!canChangeMethod}
                  >
                    <option value="">בחירה...</option>
                    {allowedMethods.map((m) => (
                      <option key={m.id} value={m.id}>
                        {m.name}
                      </option>
                    ))}
                  </Select>
                </Field>
                <Field label="משאית (מרשימה)">
                  <Select value={form.truck_id ?? ''} onChange={(e) => set({ truck_id: e.target.value || null })} disabled={!canChangeTruck}>
                    <option value="">—</option>
                    {trucks
                      .filter((t) => t.is_active)
                      .map((t) => (
                        <option key={t.id} value={t.id}>
                          {t.name}
                        </option>
                      ))}
                  </Select>
                </Field>
                <Field label="משאית (מלל חופשי)">
                  <Input
                    value={form.truck_free_text ?? ''}
                    onChange={(e) => set({ truck_free_text: e.target.value })}
                    disabled={!canChangeTruck}
                  />
                </Field>
              </div>
            </CardBody>
          </Card>

          {/* ── team ─────────────────────────────────────────────────────── */}
          <Card>
            <CardHeader
              title="שיבוץ צוות"
              subtitle={needed > 0 ? `${assignedCount} מתוך ${needed} שובצו` : `${assignedCount} משובצים`}
              icon={<Users size={ICON.md} strokeWidth={STROKE} />}
              actions={
                assignedCount > 0 && (
                  <AvatarGroup
                    names={[...byRole('worker'), ...byRole('driver')].map((a) => nameOf(a.profile_id)).filter(Boolean)}
                    max={5}
                    size="sm"
                  />
                )
              }
            />
            <CardBody className="space-y-4">
              {understaffed && (
                <p className="rounded-lg border border-warning-border bg-warning-subtle px-3 py-2 type-caption text-warning-text">
                  חסרים {needed - assignedCount} אנשים ביחס לכמות שהוגדרה
                </p>
              )}
              <Field label="ראש צוות">
                <MultiSelect
                  options={staffOptions('team_lead')}
                  values={byRole('team_lead').map((a) => a.profile_id)}
                  onToggle={(id) => canAssign.team_lead && toggleAssignment('team_lead', id)}
                  placeholder="בחירת ראש צוות..."
                  disabled={!canAssign.team_lead}
                />
              </Field>
              <Field label="עובדים">
                <MultiSelect
                  options={staffOptions('worker')}
                  values={byRole('worker').map((a) => a.profile_id)}
                  onToggle={(id) => canAssign.worker && toggleAssignment('worker', id)}
                  placeholder="בחירת עובדים..."
                  disabled={!canAssign.worker}
                />
              </Field>
              <Field label="נהגים">
                <MultiSelect
                  options={staffOptions('driver')}
                  values={byRole('driver').map((a) => a.profile_id)}
                  onToggle={(id) => canAssign.driver && toggleAssignment('driver', id)}
                  placeholder="בחירת נהגים..."
                  disabled={!canAssign.driver}
                />
              </Field>

              {/*
                שטח או מחסן, פר-משובץ. השדה קובע את שעת ההתחלה של המשמרת
                שלו: מי שיוצא מהמחסן מתחיל ב"תחילה במחסן" ומי שמגיע לאתר
                ב"תחילה בשטח". בלי שעת מחסן על המשימה אין להבחנה משמעות,
                ולכן הפאנל מוסתר.
              */}
              {form.warehouse_start_time && (
                <Field
                  label="מחסן יציאה"
                  hint="דריסה למשימה הזו בלבד. ריק = המחסן של הלקוח"
                >
                  <Select
                    value={form.warehouse_id ?? ''}
                    onChange={(e) => set({ warehouse_id: e.target.value || null })}
                    disabled={!canChangeLocation}
                  >
                    <option value="">המחסן של הלקוח</option>
                    {warehouses
                      .filter((w) => w.is_active || w.id === form.warehouse_id)
                      .map((w) => (
                        <option key={w.id} value={w.id}>
                          {w.name}
                        </option>
                      ))}
                  </Select>
                </Field>
              )}

              {form.warehouse_start_time && assignments.length > 0 && (
                <div className="space-y-2 rounded-lg border border-line-subtle bg-subtle/50 p-3">
                  <p className="type-overline">נקודת התחלה</p>
                  {assignments.map((a) => (
                    <div key={`${a.profile_id}:${a.role}`} className="flex items-center gap-2">
                      <span className="w-32 shrink-0 truncate type-body">{nameOf(a.profile_id)}</span>
                      <SegmentedControl
                        items={[
                          { key: 'field' as WorkSite, label: 'שטח' },
                          { key: 'warehouse' as WorkSite, label: 'מחסן' },
                        ]}
                        value={a.work_site}
                        onChange={(work_site) =>
                          canAssign[a.role] &&
                          setAssignments((prev) => prev.map((x) => (x === a ? { ...x, work_site } : x)))
                        }
                      />
                    </div>
                  ))}
                </div>
              )}

              {byRole('driver').length > 0 && (
                <div className="space-y-2 rounded-lg border border-line-subtle bg-subtle/50 p-3">
                  <p className="type-overline">שיוך נהג ↔ משאית</p>
                  {byRole('driver').map((a) => (
                    <div key={a.profile_id} className="flex items-center gap-2">
                      <span className="w-32 shrink-0 truncate type-body">{nameOf(a.profile_id)}</span>
                      <Select
                        selectSize="sm"
                        aria-label={`משאית עבור ${nameOf(a.profile_id)}`}
                        value={a.truck_id ?? ''}
                        onChange={(e) =>
                          setAssignments((prev) => prev.map((x) => (x === a ? { ...x, truck_id: e.target.value || null } : x)))
                        }
                        disabled={!has(PERM.TASKS_ASSIGN_TRUCK)}
                      >
                        <option value="">ללא משאית</option>
                        {trucks
                          .filter((t) => t.is_active)
                          .map((t) => (
                            <option key={t.id} value={t.id}>
                              {t.name}
                            </option>
                          ))}
                      </Select>
                    </div>
                  ))}
                </div>
              )}
            </CardBody>
          </Card>

          {/* ── customer price ───────────────────────────────────────────── */}
          {canViewCustomerPrice && !isNew && (
            <Card>
              <CardHeader
                title="מחיר ללקוח"
                subtitle="מה שהלקוח משלם — נפרד לגמרי ממה שמשולם לקבלן"
                icon={<Banknote size={ICON.md} strokeWidth={STROKE} />}
                actions={
                  existing?.pricing ? (
                    existing.pricing.is_manual ? (
                      <Badge tone="warning">ידני</Badge>
                    ) : (
                      <Badge tone="neutral">חושב אוטומטית</Badge>
                    )
                  ) : null
                }
              />
              <CardBody className="space-y-4">
                <div className="grid gap-4 sm:grid-cols-2">
                  <Field
                    label="מחיר (₪)"
                    hint={
                      canEditCustomerPrice
                        ? 'שינוי ידני נועל את המחיר — חישוב אוטומטי לא ידרוס אותו'
                        : undefined
                    }
                  >
                    <Input
                      type="number"
                      min="0"
                      step="any"
                      dir="ltr"
                      value={customerPrice}
                      onChange={(e) => setCustomerPrice(e.target.value)}
                      disabled={!canEditCustomerPrice}
                    />
                  </Field>
                  {canEditCustomerPrice && (
                    <div className="flex items-end">
                      <Button variant="ghost" loading={recalcPrice.isPending} onClick={() => recalcPrice.mutate()}>
                        <RefreshCw size={ICON.sm} />
                        חשב מחדש מהמחשבון
                      </Button>
                    </div>
                  )}
                </div>

                {/* דריסות נקודתיות: קיימות כדי שאירוע חריג לא יאלץ לשנות את
                    המחשבון של כל הלקוח. ריק = לפי ההגדרה. */}
                <div className="grid gap-4 sm:grid-cols-2">
                  <Field label="זמן נסיעה (ש׳)" hint="ריק = לפי אזור הנסיעה של מיקום האירוע">
                    <Input
                      type="number"
                      min="0"
                      step="0.25"
                      dir="ltr"
                      value={form.travel_hours ?? ''}
                      onChange={(e) => set({ travel_hours: e.target.value === '' ? null : Number(e.target.value) })}
                      disabled={!canEditCustomerPrice}
                    />
                  </Field>
                  <Field label="נדרש ראש צוות" hint="ריק = לפי הקבוע במחשבון">
                    <Select
                      value={form.requires_team_lead === null || form.requires_team_lead === undefined ? '' : String(form.requires_team_lead)}
                      onChange={(e) =>
                        set({ requires_team_lead: e.target.value === '' ? null : e.target.value === 'true' })
                      }
                      disabled={!canEditCustomerPrice}
                    >
                      <option value="">לפי המחשבון</option>
                      <option value="true">כן</option>
                      <option value="false">לא</option>
                    </Select>
                  </Field>
                </div>

                {existing?.pricing?.breakdown && (
                  <details className="rounded-xl border border-line-subtle bg-subtle/30 p-3">
                    <summary className="cursor-pointer type-body font-medium">פירוט החישוב</summary>
                    <div className="mt-3">
                      <Breakdown breakdown={existing.pricing.breakdown} />
                    </div>
                  </details>
                )}
              </CardBody>
            </Card>
          )}

          {/* ── delegation ───────────────────────────────────────────────── */}
          {has(PERM.CONTRACTORS_VIEW) && (
            <Card className={cx(form.contractor_id && 'border-warning-border')}>
              <CardHeader
                title="האצלה לקבלן"
                subtitle="קבלן רואה את המשימה בפורטל שלו ומשבץ אליה את עובדיו"
                icon={<HardHat size={ICON.md} strokeWidth={STROKE} />}
              />
              <CardBody>
                <div className="grid gap-4 sm:grid-cols-2">
                  <Field label="קבלן">
                    <Select
                      value={form.contractor_id ?? ''}
                      onChange={(e) => set({ contractor_id: e.target.value || null })}
                      disabled={!canDelegate}
                    >
                      <option value="">ללא קבלן</option>
                      {contractors
                        .filter((c) => c.is_active)
                        .map((c) => (
                          <option key={c.id} value={c.id}>
                            {c.name}
                          </option>
                        ))}
                    </Select>
                  </Field>
                  {form.contractor_id && canViewPricing && (
                    <Field label="מחיר לקבלן (₪)">
                      <Input
                        type="number"
                        min="0"
                        value={price}
                        onChange={(e) => setPrice(e.target.value)}
                        disabled={!canEditPricing}
                      />
                    </Field>
                  )}
                </div>
              </CardBody>
            </Card>
          )}

          <Field label="הערות">
            <Textarea autoGrow value={form.notes ?? ''} onChange={(e) => set({ notes: e.target.value })} disabled={!canEditNotes} />
          </Field>
        </div>
      )}
    </Drawer>
  )
}
