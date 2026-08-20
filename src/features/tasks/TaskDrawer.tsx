import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Banknote,
  Briefcase,
  Clock,
  HardHat,
  ICON,
  MapPin,
  Paperclip,
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
  Switch,
  Textarea,
  cx,
  fmtMoney,
  useConfirm,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import {
  useAllowedExecutionMethods,
  useContractorAssignableWorkers,
  useContractorDelegate,
  useContractorWorkerAssign,
  useContractors,
  useStaff,
  useStatuses,
  useTaskTypes,
  useTrucks,
} from '../../lib/queries'
import { Breakdown } from '../customers/PricingTab'
import { EventSpecsModal } from '../events/EventSpecsModal'
import { useEventSpecs } from '../events/specQueries'
import { TaskPnlCard } from '../reports/TaskPnlCard'
import { useWarehouses } from '../attendance/attendanceQueries'
import type {
  AssignmentConflict,
  Contractor,
  PriceBreakdown,
  StaffRole,
  TaskContractorTerms,
  TaskPricing,
  TaskRow,
  WorkSite,
} from '../../types/domain'
import { fmtDate } from '../../lib/dates'
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

/** 'HH:MM' מתוך timestamptz, בשעון המקומי — ההתנגשות מוצגת בשעה שהיא קורית. */
const clockTime = (iso: string) =>
  new Date(iso).toLocaleTimeString('he-IL', { hour: '2-digit', minute: '2-digit', hour12: false })

export function TaskDrawer({ open, onClose, taskId, initial }: TaskDrawerProps) {
  const qc = useQueryClient()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const has = useAuth((s) => s.has)
  const me = useAuth((s) => s.me)
  /** הקבלן של המשתמש עצמו — מנהל קבלן משבץ את עובדיו דרך זה, לא דרך כרטיס ההאצלה. */
  const myContractorId = me?.profile.contractor_id ?? null
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
  // פרסום ("משובץ") הוא מפתח נפרד מ-tasks.change_status: מי שרשאי לשנות סטטוס
  // אך לא לפרסם (מנהל לקוח, למשל) לא יראה את האפשרות הזו בבורר.
  const canPublish = gate(PERM.TASKS_PUBLISH)
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
  /* לא נגזר מ-`canAssign`: הסגל של הקבלן אינו `task_assignments`, והמפתחות
     שמתירים לגעת בו הם אחרים לגמרי — של הקבלן, או של המשרד מול קבלנים. */
  const canAssignContractor = has(PERM.PORTAL_ASSIGN_WORKERS) || has(PERM.CONTRACTORS_ASSIGN_WORKERS)
  /* אי-התייצבות נקבעת ע״י מנהל/משרד (contractors.assign_workers), לא ע״י הקבלן. */
  const canMarkNoShow = has(PERM.CONTRACTORS_ASSIGN_WORKERS)
  const canViewSpecs = has(PERM.EVENTS_SPECS_VIEW)

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
      // ‏0096: למשימה יכולות להיות כמה שורות terms — אחת לכל קבלן — ולכן זו
      // רשימה, לא שורה יחידה; ועובדי הקבלן נשלפים עם ה-contractor_id שלהם כדי
      // לשייך כל אחד לכרטיס הקבלן שלו.
      const [t, a, terms, pricing, cw] = await Promise.all([
        supabase.from('tasks').select('*').eq('id', taskId).single(),
        supabase.from('task_assignments').select('*').eq('task_id', taskId),
        supabase.from('task_contractor_terms').select('*').eq('task_id', taskId),
        supabase.from('task_pricing').select('*').eq('task_id', taskId).maybeSingle(),
        supabase
          .from('task_contractor_workers')
          .select('contractor_worker_id, no_show, contractor_workers!inner(contractor_id)')
          .eq('task_id', taskId),
      ])
      if (t.error) throw t.error
      const cwRows = (cw.data ?? []) as unknown as {
        contractor_worker_id: string
        no_show: boolean
        contractor_workers: { contractor_id: string } | null
      }[]
      return {
        task: t.data as TaskRow,
        assignments: (a.data ?? []) as Assignment[],
        terms: (terms.data ?? []) as TaskContractorTerms[],
        pricing: (pricing.data as TaskPricing) ?? null,
        contractorWorkers: cwRows.map((r) => ({
          worker_id: r.contractor_worker_id,
          contractor_id: r.contractor_workers?.contractor_id ?? null,
          no_show: r.no_show,
        })),
      }
    },
  })

  const [form, setForm] = useState<Partial<TaskRow>>({})
  const [assignments, setAssignments] = useState<Assignment[]>([])
  const [customerPrice, setCustomerPrice] = useState<string>('')
  const [touched, setTouched] = useState(false)
  /* איזה קבלן נבחר בבורר ה"הוסף האצלה" לפני הלחיצה על הוספה. */
  const [addContractor, setAddContractor] = useState<string>('')

  const [specsOpen, setSpecsOpen] = useState(false)
  /**
   * המפרט של האירוע שהמשימה שייכת אליו.
   *
   * הרשימה נטענת עם המגירה ולא עם המודאל, כי המונה על הכפתור הוא מה שאומר אם
   * יש בכלל מה לפתוח — ובאותו מפתח שאילתה שהמודאל משתמש בו, כך שהפתיחה מיידית.
   * שם האירוע נשלף רק כשהמודאל נפתח: הוא כותרת, ולא סיבה לשאילתה נוספת בכל
   * פתיחה של משימה.
   */
  const specEventId = form.event_id ?? null
  const { data: specs = [] } = useEventSpecs(specEventId ?? '', open && !!specEventId && canViewSpecs)
  const { data: specEvent } = useQuery({
    queryKey: ['events', 'specHeader', specEventId],
    enabled: specsOpen && !!specEventId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('events')
        .select('end_client_name, event_date')
        .eq('id', specEventId!)
        .single()
      if (error) throw error
      return data as { end_client_name: string | null; event_date: string }
    },
  })

  /* ‏0096: שורת terms לכל קבלן שהואצל אליו המשימה. */
  const terms = existing?.terms ?? []
  /* שיבוץ עובדי הקבלן נכתב מיד ולא נשמר עם הטופס, ולכן הוא נקרא מהשאילתה
     ולא מוחזק ב-state: הרענון שאחרי הכתיבה הוא מה שמצייר את התוצאה. */
  const chosenContractorWorkers = existing?.contractorWorkers ?? []
  const delegate = useContractorDelegate()

  useEffect(() => {
    if (!open) return
    setTouched(false)
    setAddContractor('')
    if (taskId && existing) {
      setForm(existing.task)
      setAssignments(existing.assignments)
      setCustomerPrice(existing.pricing?.price != null ? String(existing.pricing.price) : '')
    } else if (!taskId) {
      setForm({ task_date: new Date().toISOString().slice(0, 10), worker_count: 0, ...initial })
      setAssignments([])
      setCustomerPrice('')
    }
  }, [open, taskId, existing, initial])

  /**
   * כפל-שיבוץ. הבדיקה יושבת ב-SQL (app.task_window / assignment_conflicts)
   * ולא כאן, כדי שהיומן, הלוח והמגירה יגיעו לאותה תשובה.
   *
   * המשובצים שנבחרו ועדיין לא נשמרו נשלחים כמועמדים, ולכן האזהרה מופיעה
   * בזמן השיבוץ ולא רק אחרי השמירה. היא אזהרה ולא חסימה: יש מקרים אמיתיים
   * שבהם אותו אדם באמת עושה את שתי המשימות, וההכרעה היא של מי שמשבץ.
   */
  const candidateIds = useMemo(
    () => [...new Set(assignments.map((a) => a.profile_id))].sort(),
    [assignments],
  )
  const { data: conflicts = [] } = useQuery({
    queryKey: ['tasks', 'conflicts', taskId, candidateIds],
    enabled: open && !!taskId,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('assignment_conflicts', {
        p_task_id: taskId,
        p_extra_profiles: candidateIds,
      })
      if (error) throw error
      return (data ?? []) as AssignmentConflict[]
    },
  })

  const allowedMethods = useAllowedExecutionMethods(form.task_type_id, form.customer_id)

  /* משימות שנשמרו לפני ריבוי המשאיות מגיעות עם truck_id בלבד */
  const truckIds = useMemo(
    () => form.truck_ids ?? (form.truck_id ? [form.truck_id] : []),
    [form.truck_ids, form.truck_id],
  )
  const firstTruckName = trucks.find((t) => t.id === truckIds[0])?.name ?? ''

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
        /* truck_id נגזר מהרשימה בטריגר (0035), ולכן נשלחת הרשימה בלבד —
           שליחת שניהם הייתה משאירה למסד שתי אמיתות לבחור ביניהן. */
        truck_ids: truckIds,
        truck_free_text: form.truck_free_text || null,
        notes: form.notes || null,
        status_id: form.status_id || statuses.find((s) => s.is_default)?.id,
        /* ‏contractor_id הוא כיום שיקוף של הקבלן הראשי, מתוחזק בטריגר על
           ‏task_contractor_terms (0096). ההאצלה נעשית ב-RPC ולא נכתבת כאן,
           ולכן העמודה אינה בעדכון — כדי לא לדרוס את השיקוף. */
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
      // תנאי הקבלן (נקודת התחלה, תעריף, כמות עובדים) וההאצלה עצמה נשמרים מיד
      // דרך כרטיס הקבלן וה-RPCים, ולא עם הטופס — כי משימה נושאת כמה קבלנים,
      // וכל אחד הוא ישות נפרדת עם שמירה משלה (0096).
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
      // יצירת משימה נרשמת ביומן של האירוע, ולכן היומן הפתוח מאחור מתיישן
      void qc.invalidateQueries({ queryKey: ['event_activity'] })
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
    if (error) toast.error(errorMessage(error))
    else {
      toast.success('המשימה נמחקה')
      void qc.invalidateQueries({ queryKey: ['tasks'] })
      void qc.invalidateQueries({ queryKey: ['workboard'] })
      void qc.invalidateQueries({ queryKey: ['calendar'] })
      void qc.invalidateQueries({ queryKey: ['event_activity'] })
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

  /* staffing progress — the single number a dispatcher checks most often.
     עובדי הקבלן נספרים כאן כמאיישים: משימה שהואצלה לקבלן והוא איישָׁ אותה
     אינה "חסרה", גם אם אין לה task_assignments משלה (0091). */
  const assignedCount =
    byRole('worker').length +
    byRole('driver').length +
    byRole('team_lead').length +
    chosenContractorWorkers.length
  const needed = form.worker_count ?? 0
  const understaffed = needed > 0 && assignedCount < needed

  /* הקבלנים שכבר הואצלו, והרשימה שנותרה לבחירה בבורר ההוספה. */
  const delegatedIds = new Set(terms.map((t) => t.contractor_id))
  const addableContractors = contractors.filter(
    (c) => c.is_active && !delegatedIds.has(c.id),
  )

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
      {specEventId && canViewSpecs && (
        <EventSpecsModal
          eventId={specEventId}
          eventTitle={specEvent?.end_client_name || (specEvent ? fmtDate(specEvent.event_date) : '')}
          open={specsOpen}
          onClose={() => setSpecsOpen(false)}
        />
      )}
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
            <CardHeader
              title="מהות המשימה"
              icon={<Briefcase size={ICON.md} strokeWidth={STROKE} />}
              /* המפרט של האירוע, מתוך המשימה. דף האירוע אינו נפתח לכולם —
                 מנהל קבלן ועובד קבלן מגיעים ללו״ז ולא ל-/events/:id — והמגירה
                 היא המקום היחיד שבו הם רואים משימה שיש לה אירוע. מ-0102
                 הצפייה במפרט נגזרת מהאירוע, ולכן מה שנשאר הוא לתת לה דלת. */
              actions={
                specEventId && canViewSpecs ? (
                  <Button size="sm" onClick={() => setSpecsOpen(true)}>
                    <Paperclip size={ICON.sm} strokeWidth={STROKE} />
                    מפרט
                    {specs.length > 0 && <Badge tone="primary">{specs.length}</Badge>}
                  </Button>
                ) : undefined
              }
            />
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
                    {statuses
                      // מסתירים את "משובץ" ממי שאינו רשאי לפרסם — אך משאירים אותו
                      // כשזה הסטטוס הנוכחי, כדי שמשימה שכבר פורסמה תוצג נכון.
                      .filter((s) => canPublish || s.code !== 'assigned' || s.id === form.status_id)
                      .map((s) => (
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
                {/* אירוע גדול יוצא ביותר ממשאית אחת. הראשונה ברשימה היא זו
                    שנשמרת גם ב-truck_id, ולפיה מחושבים המחיר והנוכחות. */}
                <Field label="משאיות" hint={truckIds.length > 1 ? `הראשונה: ${firstTruckName}` : undefined}>
                  <MultiSelect
                    options={trucks
                      .filter((t) => t.is_active || truckIds.includes(t.id))
                      .map((t) => ({ id: t.id, label: t.name }))}
                    values={truckIds}
                    onToggle={(id) =>
                      set({
                        truck_ids: truckIds.includes(id) ? truckIds.filter((x) => x !== id) : [...truckIds, id],
                      })
                    }
                    placeholder="בחירת משאיות..."
                    disabled={!canChangeTruck}
                  />
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
              {conflicts.length > 0 && (
                <div className="rounded-lg border border-error-border bg-error-subtle px-3 py-2 type-caption text-error-text">
                  <p className="font-semibold">שיבוץ כפול</p>
                  <ul className="mt-1 space-y-0.5">
                    {conflicts.map((c) => (
                      <li key={`${c.kind}:${c.subject_id}:${c.task_id}`}>
                        {c.subject_name} משובץ גם ל״{c.task_label}״
                        {c.customer_name ? ` (${c.customer_name})` : ''} ב-{fmtDate(c.task_date)},{' '}
                        {clockTime(c.starts_at)}–{clockTime(c.ends_at)}
                      </li>
                    ))}
                  </ul>
                </div>
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
                שטח או מחסן, פר-משובץ. השדה קובע שני דברים במשמרת של אותו
                אדם: מאיפה הוא מתחיל — "תחילה במחסן" למי שיוצא מהמחסן,
                "תחילה בשטח" לכל השאר — ומול מה נמדד המיקום בהחתמת הכניסה.
                הוא גם מה שקובע אם נספרת לו נסיעה חזרה למחסן בסוף המשמרת.

                עד כאן הפאנל הופיע רק כשהייתה למשימה שעת מחסן, ולכן במשימות
                של לקוח שאין לו שעה כזו פשוט לא היה איך לומר "האנשים האלה
                באים למחסן". אין סיבה לתלות: בלי שעת מחסן המשמרת מתחילה בשעת
                השטח, וזה בדיוק מה שהגזירה עושה (0023).
              */}
              {assignments.length > 0 && (
                <>
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
                    {/* המשמרת של מי שיוצא מהמחסן מתחילה בשעת המחסן — וכשאין
                        כזו, בשעת השטח. אמירה ולא חסימה: יש מקרים שבהם באמת
                        מתאספים במחסן בשעת השטח. */}
                    {!form.warehouse_start_time && assignments.some((a) => a.work_site === 'warehouse') && (
                      <p className="type-caption text-ink-tertiary">
                        אין למשימה "תחילה במחסן", ולכן המשמרת של מי שיוצא מהמחסן מתחילה בשעת השטח.
                      </p>
                    )}
                  </div>
                </>
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

          {/* ── task P&L ─────────────────────────────────────────────────── */}
          {/* אחרי מחיר הלקוח בכוונה: שם עומדים כששואלים "וכמה זה עלה לי". */}
          {!isNew && taskId && existing?.task && (
            <TaskPnlCard taskId={taskId} taskDate={existing.task.task_date} />
          )}

          {/* ── delegation to contractors (0096: several per task) ─────────
              ההאצלה אינה עוד בחירה יחידה: אפשר להאציל את המשימה לכמה קבלנים,
              כל אחד עם נקודת התחלה, תעריף, כמות עובדים וקנסות משלו. כל שורה
              היא ישות נפרדת שנשמרת מיד (הוספה/הסרה דרך RPC, שאר השדות בכתיבה
              ישירה ל-terms), ולא עם כפתור השמירה של הטופס. */}
          {taskId && has(PERM.CONTRACTORS_VIEW) && (
            <Card className={cx(terms.length > 0 && 'border-warning-border')}>
              <CardHeader
                title="האצלה לקבלנים"
                subtitle="כל קבלן רואה את המשימה בלוח שלו ומשבץ אליה את עובדיו — נשמר מיד"
                icon={<HardHat size={ICON.md} strokeWidth={STROKE} />}
              />
              <CardBody className="space-y-4">
                {terms.length === 0 && (
                  <p className="type-caption text-ink-tertiary">המשימה לא הואצלה לאף קבלן.</p>
                )}
                {terms.map((term) => {
                  const contractor = contractors.find((c) => c.id === term.contractor_id)
                  const mine = chosenContractorWorkers.filter(
                    (w) => w.contractor_id === term.contractor_id,
                  )
                  return (
                    <ContractorDelegationCard
                      key={term.contractor_id}
                      taskId={taskId}
                      term={term}
                      contractor={contractor}
                      assignedWorkerIds={mine.map((w) => w.worker_id)}
                      noShow={new Set(mine.filter((w) => w.no_show).map((w) => w.worker_id))}
                      canDelegate={canDelegate}
                      canEditPricing={canEditPricing}
                      canViewPricing={canViewPricing}
                      canAssignContractor={canAssignContractor}
                      canMarkNoShow={canMarkNoShow}
                      onRemove={() =>
                        delegate.mutate(
                          { taskId, contractorId: term.contractor_id, on: false },
                          { onError: (e) => toast.error(errorMessage(e)) },
                        )
                      }
                      removing={delegate.isPending}
                    />
                  )
                })}

                {canDelegate && addableContractors.length > 0 && (
                  <div className="flex items-end gap-2 border-t border-line-subtle pt-4">
                    <Field label="הוספת קבלן" className="flex-1">
                      <Select
                        value={addContractor}
                        onChange={(e) => setAddContractor(e.target.value)}
                      >
                        <option value="">בחירת קבלן...</option>
                        {addableContractors.map((c) => (
                          <option key={c.id} value={c.id}>
                            {c.name}
                          </option>
                        ))}
                      </Select>
                    </Field>
                    <Button
                      loading={delegate.isPending}
                      disabled={!addContractor}
                      onClick={() =>
                        delegate.mutate(
                          { taskId, contractorId: addContractor, on: true },
                          {
                            onSuccess: () => setAddContractor(''),
                            onError: (e) => toast.error(errorMessage(e)),
                          },
                        )
                      }
                    >
                      הוספה
                    </Button>
                  </div>
                )}
              </CardBody>
            </Card>
          )}

          {/* ── the contractor manager's own crew ─────────────────────────
              מנהל הקבלן אינו רואה את כרטיס ההאצלה שלמעלה (אין לו contractors.view),
              אך הוא כן משבץ את עובדיו — וזה המסך היחיד שבו הוא יכול, כי הכרטיס
              הנייד פותח את המגירה במקום לצייר את תא הצוות. שיבוץ נכתב מיד דרך
              RPC; המפתח הוא `portal.assign_workers`, לא `tasks.assign.worker`. */}
          {taskId && !has(PERM.CONTRACTORS_VIEW) && canAssignContractor && myContractorId && (
            <Card>
              <CardHeader
                title="עובדי הקבלן"
                subtitle="הסגל של הקבלן, ועובדים שנרשמו תחתיו — נשמר מיד"
                icon={<HardHat size={ICON.md} strokeWidth={STROKE} />}
              />
              <CardBody>
                <ContractorCrew
                  taskId={taskId}
                  contractorId={myContractorId}
                  contractorName={contractors.find((c) => c.id === myContractorId)?.name ?? null}
                  assignedWorkerIds={chosenContractorWorkers
                    .filter((w) => w.contractor_id === myContractorId)
                    .map((w) => w.worker_id)}
                  noShow={new Set()}
                  canMarkNoShow={false}
                />
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

/**
 * שיבוץ הסגל של קבלן אחד למשימה, וסימון אי-התייצבות (0096).
 *
 * נכתב מיד דרך RPC ולא נשמר עם הטופס — `task_contractor_workers` אינה עמודה של
 * המשימה. הקבלן נגזר מהעובד בשרת (`contractor_assign_worker`), ולכן די כאן ב-
 * ‏contractorId כדי להביא את הרוסטר הנכון ולתייג את העובדים.
 */
function ContractorCrew({
  taskId,
  contractorId,
  contractorName,
  assignedWorkerIds,
  noShow,
  canMarkNoShow,
}: {
  taskId: string
  contractorId: string
  contractorName: string | null
  assignedWorkerIds: string[]
  noShow: Set<string>
  canMarkNoShow: boolean
}) {
  const toast = useToast()
  const qc = useQueryClient()
  const { data: assignable = [] } = useContractorAssignableWorkers(contractorId)
  const contractorAssign = useContractorWorkerAssign()
  const assignedSet = new Set(assignedWorkerIds)
  const noShowMut = useMutation({
    mutationFn: async ({ workerId, on }: { workerId: string; on: boolean }) => {
      const { error } = await supabase.rpc('contractor_mark_no_show', {
        p_task_id: taskId,
        p_worker_id: workerId,
        p_on: on,
      })
      if (error) throw error
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['tasks', 'one', taskId] })
      void qc.invalidateQueries({ queryKey: ['workboard'] })
    },
    onError: (e) => toast.error(errorMessage(e)),
  })
  return (
    <>
      <MultiSelect
        options={assignable.map((w) => ({
          id: w.worker_id ? `w:${w.worker_id}` : `p:${w.profile_id}`,
          /* לאיזה קבלן העובד שייך, ולא "חשבון" (0094). */
          label: contractorName ? `${w.full_name} · ${contractorName}` : w.full_name,
        }))}
        values={assignable
          .filter((w) => w.worker_id && assignedSet.has(w.worker_id))
          .map((w) => `w:${w.worker_id}`)}
        onToggle={(id) => {
          const isProfile = id.startsWith('p:')
          const key = id.slice(2)
          contractorAssign.mutate(
            {
              taskId,
              workerId: isProfile ? null : key,
              profileId: isProfile ? key : null,
              on: !(!isProfile && assignedSet.has(key)),
            },
            { onError: (e) => toast.error(errorMessage(e)) },
          )
        }}
        placeholder="בחירת עובדים מהקבלן..."
      />
      {assignable.length === 0 && (
        <p className="mt-1 type-caption text-ink-tertiary">אין עדיין עובדים בסגל של הקבלן.</p>
      )}

      {/* סימון אי-התייצבות למנהל/משרד (0093). מפעיל את קנס אי-ההתייצבות. */}
      {canMarkNoShow && assignedWorkerIds.length > 0 && (
        <div className="mt-3 space-y-1.5 border-t border-line-subtle pt-3">
          <div className="type-overline">נוכחות עובדי הקבלן</div>
          {assignable
            .filter((w) => w.worker_id && assignedSet.has(w.worker_id))
            .map((w) => (
              <label key={w.worker_id} className="flex items-center justify-between gap-2 type-caption">
                <span className="truncate">{w.full_name}</span>
                <span className="inline-flex items-center gap-1.5 text-ink-secondary">
                  לא התייצב
                  <Switch
                    checked={noShow.has(w.worker_id!)}
                    onChange={(on) => noShowMut.mutate({ workerId: w.worker_id!, on })}
                  />
                </span>
              </label>
            ))}
        </div>
      )}
    </>
  )
}

/**
 * כרטיס האצלה של קבלן אחד במשימה (0096). משימה יכולה לשאת כמה כאלה. שדות
 * ה-terms (נקודת התחלה, כמות עובדים, תעריף/מחיר) נכתבים מיד ל-terms של אותו
 * קבלן; שורה ששולם עליה ננעלת לעריכה. שיבוץ עובדי הקבלן דרך `ContractorCrew`.
 */
function ContractorDelegationCard({
  taskId,
  term,
  contractor,
  assignedWorkerIds,
  noShow,
  canDelegate,
  canEditPricing,
  canViewPricing,
  canAssignContractor,
  canMarkNoShow,
  onRemove,
  removing,
}: {
  taskId: string
  term: TaskContractorTerms
  contractor: Contractor | undefined
  assignedWorkerIds: string[]
  noShow: Set<string>
  canDelegate: boolean
  canEditPricing: boolean
  canViewPricing: boolean
  canAssignContractor: boolean
  canMarkNoShow: boolean
  onRemove: () => void
  removing: boolean
}) {
  const toast = useToast()
  const qc = useQueryClient()
  const [workSite, setWorkSite] = useState<WorkSite>(term.work_site ?? 'field')
  const [count, setCount] = useState(
    term.contractor_worker_count != null ? String(term.contractor_worker_count) : '',
  )
  const [pricePerWorker, setPricePerWorker] = useState(
    term.price_per_worker != null ? String(term.price_per_worker) : '',
  )
  const [price, setPrice] = useState(term.price != null ? String(term.price) : '')

  /* השרת מחשב מחדש מחיר וקנסות אחרי כל שינוי — מסנכרנים את ה-state עם השורה
     שחזרה, כדי שהשדות הלא-נערכים ישקפו את התוצאה. */
  useEffect(() => {
    setWorkSite(term.work_site ?? 'field')
    setCount(term.contractor_worker_count != null ? String(term.contractor_worker_count) : '')
    setPricePerWorker(term.price_per_worker != null ? String(term.price_per_worker) : '')
    setPrice(term.price != null ? String(term.price) : '')
  }, [term.work_site, term.contractor_worker_count, term.price_per_worker, term.price])

  const patchTerms = useMutation({
    mutationFn: async (patch: Record<string, unknown>) => {
      const { error } = await supabase
        .from('task_contractor_terms')
        .update(patch)
        .eq('task_id', taskId)
        .eq('contractor_id', term.contractor_id)
      if (error) throw error
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['tasks', 'one', taskId] })
      void qc.invalidateQueries({ queryKey: ['workboard'] })
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const paid = term.paid_at != null
  const parts = term.price_parts
  const effectiveRate =
    pricePerWorker !== '' ? Number(pricePerWorker) : contractor?.price_per_worker ?? null
  const perWorkerPricing = effectiveRate != null

  return (
    <div
      className={cx(
        'space-y-4 rounded-xl border p-3',
        paid ? 'border-success-border bg-success-subtle/30' : 'border-line-subtle',
      )}
    >
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <span className="type-body font-semibold">{contractor?.name ?? 'קבלן'}</span>
          {paid && <Badge tone="success">שולם</Badge>}
        </div>
        {canDelegate && !paid && (
          <Button
            variant="ghost"
            size="sm"
            loading={removing}
            onClick={onRemove}
            aria-label={`הסרת ${contractor?.name ?? 'קבלן'}`}
          >
            <Trash2 size={ICON.sm} strokeWidth={STROKE} />
          </Button>
        )}
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        {/* נקודת ההתחלה שהמשרד קובע לקבלן. חלה אוטומטית על עובדיו (0091). */}
        <Field label="נקודת התחלה">
          <SegmentedControl
            value={workSite}
            onChange={(v) => {
              if (!canDelegate || paid) return
              setWorkSite(v as WorkSite)
              patchTerms.mutate({ work_site: v })
            }}
            items={[
              { key: 'field' as WorkSite, label: 'שטח' },
              { key: 'warehouse' as WorkSite, label: 'מחסן' },
            ]}
          />
        </Field>
        {/* כמה עובדים הקבלן צריך להביא — תקרת השיבוץ, בלתי תלויה בכמות המשימה. */}
        <Field label="עובדים להביא" hint="תקרת השיבוץ של הקבלן">
          <Input
            type="number"
            min="0"
            value={count}
            onChange={(e) => setCount(e.target.value)}
            onBlur={() => {
              if (!canDelegate || paid) return
              const next = count === '' ? null : Number(count)
              if (next !== (term.contractor_worker_count ?? null))
                patchTerms.mutate({ contractor_worker_count: next })
            }}
            disabled={!canDelegate || paid}
          />
        </Field>
      </div>

      {canViewPricing && (
        <div className="grid gap-4 sm:grid-cols-2">
          {/* התעריף-לעובד: ריק = ברירת המחדל של הקבלן. כשקיים, המחיר מחושב
              בשרת לפי מספר העובדים ששובצו בפועל (0091). */}
          <Field
            label="מחיר לעובד (₪)"
            hint={
              contractor?.price_per_worker != null
                ? `ריק = ברירת מחדל של הקבלן (${fmtMoney(contractor.price_per_worker)})`
                : 'ריק = תמחור לפי מחיר משימה קבוע'
            }
          >
            <Input
              type="number"
              min="0"
              value={pricePerWorker}
              placeholder={contractor?.price_per_worker?.toString() ?? ''}
              onChange={(e) => setPricePerWorker(e.target.value)}
              onBlur={() => {
                if (!canEditPricing || paid) return
                const next = pricePerWorker === '' ? null : Number(pricePerWorker)
                if (next !== (term.price_per_worker ?? null))
                  patchTerms.mutate({ price_per_worker: next })
              }}
              disabled={!canEditPricing || paid}
            />
          </Field>
          <Field
            label="מחיר לקבלן (₪)"
            hint={
              perWorkerPricing
                ? `מחושב: ${assignedWorkerIds.length} עובדים × ${fmtMoney(effectiveRate ?? 0)}`
                : undefined
            }
          >
            <Input
              type="number"
              min="0"
              value={perWorkerPricing ? String(term.price ?? 0) : price}
              onChange={(e) => setPrice(e.target.value)}
              onBlur={() => {
                if (!canEditPricing || paid || perWorkerPricing) return
                const next = price === '' ? null : Number(price)
                if (next !== (term.price ?? null)) patchTerms.mutate({ price: next })
              }}
              disabled={!canEditPricing || paid || perWorkerPricing}
            />
          </Field>
        </div>
      )}

      {/* פירוט תמחור וקנסות למנהל (0093/0094). */}
      {canViewPricing && parts && (
        <div className="space-y-1 rounded-xl border border-line-subtle bg-subtle/30 p-3 type-caption text-ink-secondary">
          <div className="type-body font-medium text-ink">פירוט תמחור וקנסות</div>
          <div className="flex justify-between">
            <span>בסיס{parts.transport ? ' (הובלה)' : ''}</span>
            <span dir="ltr" className="tabular">{fmtMoney(parts.base)}</span>
          </div>
          {parts.surcharge > 0 && (
            <div className="flex justify-between">
              <span>תוספת מחסן</span>
              <span dir="ltr" className="tabular">{fmtMoney(parts.surcharge)}</span>
            </div>
          )}
          {parts.late_count > 0 && (
            <div className="flex justify-between text-error-text">
              <span>קנס איחור ({parts.late_count})</span>
              <span dir="ltr" className="tabular">
                −{fmtMoney(parts.late_count * parts.late_penalty_each)}
              </span>
            </div>
          )}
          {parts.noshow_count > 0 && (
            <div className="flex justify-between text-error-text">
              <span>קנס אי-התייצבות ({parts.noshow_count})</span>
              <span dir="ltr" className="tabular">
                −{fmtMoney(parts.noshow_count * parts.noshow_penalty_each)}
              </span>
            </div>
          )}
          <div className="flex justify-between border-t border-line-subtle pt-1 type-body font-semibold text-ink">
            <span>סך לתשלום</span>
            <span dir="ltr" className="tabular">
              {fmtMoney(Math.max(0, parts.base + parts.surcharge - parts.penalty_total))}
            </span>
          </div>
        </div>
      )}

      {canAssignContractor && (
        <div className="border-t border-line-subtle pt-3">
          <div className="type-overline mb-2">עובדי הקבלן</div>
          <ContractorCrew
            taskId={taskId}
            contractorId={term.contractor_id}
            contractorName={contractor?.name ?? null}
            assignedWorkerIds={assignedWorkerIds}
            noShow={noShow}
            canMarkNoShow={canMarkNoShow}
          />
        </div>
      )}
    </div>
  )
}
