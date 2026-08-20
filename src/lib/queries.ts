import { useMemo } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from './supabase'
import { useAuth } from '../state/auth'
import type {
  Contractor,
  ContractorWorker,
  Customer,
  CustomerIncomeSplit,
  CustomerPricingRule,
  IncomeCategory,
  EventAutoTask,
  PricingZone,
  TaskPricing,
  ExecutionMethod,
  FieldState,
  FormField,
  Profile,
  Status,
  Supplier,
  TaskType,
  Truck,
  UserFormField,
  Vehicle,
  VehicleDocumentKind,
} from '../types/domain'

async function fetchList<T>(table: string, order = 'name'): Promise<T[]> {
  const { data, error } = await supabase.from(table).select('*').is('deleted_at', null).order(order)
  if (error) throw error
  return data as T[]
}

export function useCustomers() {
  return useQuery({ queryKey: ['customers', 'list'], queryFn: () => fetchList<Customer>('customers') })
}

/** `enabled` הוא בשביל מסך שהרשימה בו היא מסנן אופציונלי ולא כל התוכן. */
export function useContractors(enabled = true) {
  return useQuery({
    queryKey: ['contractors', 'list'],
    enabled,
    queryFn: () => fetchList<Contractor>('contractors'),
  })
}

export function useTaskTypes() {
  return useQuery({ queryKey: ['task_types', 'list'], queryFn: () => fetchList<TaskType>('task_types', 'sort_order') })
}

export function useExecutionMethods() {
  return useQuery({ queryKey: ['execution_methods', 'list'], queryFn: () => fetchList<ExecutionMethod>('execution_methods', 'sort_order') })
}

export function useStatuses(entity?: 'task' | 'event') {
  const q = useQuery({ queryKey: ['statuses', 'list'], queryFn: () => fetchList<Status>('statuses', 'sort_order') })
  return { ...q, data: entity ? q.data?.filter((s) => s.entity === entity) : q.data }
}

export function useTrucks() {
  return useQuery({ queryKey: ['trucks', 'list'], queryFn: () => fetchList<Truck>('trucks') })
}

/**
 * צי הרכב (0089). `trucks` שמעליה היא רשימת השיגור; זו היא רשימת הנכסים.
 * הסדר לפי מספר רישוי ולא לפי שם — כך מחפשים רכב.
 */
export function useVehicles(enabled = true) {
  return useQuery({
    queryKey: ['vehicles', 'list'],
    enabled,
    queryFn: () => fetchList<Vehicle>('vehicles', 'plate_number'),
  })
}

/** קטלוג סוגי מסמכי הרכב. משותף לכרטיס הרכב ולטאב ההגדרות. */
export function useVehicleDocumentKinds() {
  return useQuery({
    queryKey: ['vehicle_document_kinds', 'list'],
    queryFn: () => fetchList<VehicleDocumentKind>('vehicle_document_kinds', 'sort_order'),
  })
}

/**
 * The event-form catalog: the fixed system fields, plus the custom fields one
 * customer defined. Without a customer only the system fields come back —
 * another company's custom fields are neither useful here nor readable, since
 * `form_fields_read` (0053) scopes them.
 */
export function useFormFields(customerId?: string | null) {
  return useQuery({
    queryKey: ['form_fields', 'list', customerId ?? 'system'],
    queryFn: async () => {
      let q = supabase.from('form_fields').select('*').is('deleted_at', null)
      q = customerId ? q.or(`customer_id.is.null,customer_id.eq.${customerId}`) : q.is('customer_id', null)
      const { data, error } = await q.order('sort_order')
      if (error) throw error
      return data as FormField[]
    },
  })
}

/** Only the fields this customer defined — what the form draws dynamically. */
export function useCustomFormFields(customerId?: string | null) {
  const q = useFormFields(customerId)
  const fields = q.data
  return {
    ...q,
    data: useMemo(() => (fields ?? []).filter((f) => f.customer_id !== null), [fields]),
  }
}

/**
 * Every customer's custom fields at once — the Excel workbook needs the whole
 * set, because one file may carry rows for several customers.
 */
export function useAllCustomFormFields(enabled = true) {
  return useQuery({
    queryKey: ['form_fields', 'custom', 'all'],
    enabled,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('form_fields')
        .select('*')
        .is('deleted_at', null)
        .not('customer_id', 'is', null)
        .order('sort_order')
      if (error) throw error
      return data as FormField[]
    },
  })
}

export function useStaff(enabled = true) {
  return useQuery({
    queryKey: ['profiles', 'staff'],
    enabled,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('profiles')
        .select('*, staff_roles(role)')
        .eq('user_kind', 'staff')
        .is('deleted_at', null)
        .eq('is_active', true)
        .order('full_name')
      if (error) throw error
      return data as Profile[]
    },
  })
}

export function useSuppliers(customerId?: string | null) {
  return useQuery({
    queryKey: ['suppliers', 'byCustomer', customerId],
    enabled: !!customerId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('suppliers')
        .select('*')
        .eq('customer_id', customerId)
        .is('deleted_at', null)
        .order('name')
      if (error) throw error
      return data as Supplier[]
    },
  })
}

/**
 * כל הספקים במערכת, עם הלקוח שכל אחד שייך אליו.
 *
 * useSuppliers מסננת ללקוח אחד כי כך עובד טופס האירוע. גיליון ההסבר של קובץ
 * הייבוא צריך את ההפך — קובץ אחד נושא אירועים של כמה לקוחות, וכל שם ספק בו
 * נבדק מול הלקוח של אותה שורה.
 */
export function useAllSuppliers(enabled = true) {
  return useQuery({
    queryKey: ['suppliers', 'all'],
    enabled,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('suppliers')
        .select('name, is_active, customers(name)')
        .is('deleted_at', null)
        .order('name')
      if (error) throw error
      return (data as unknown as { name: string; is_active: boolean; customers: { name: string } | null }[])
        .filter((s) => s.is_active)
        .map((s) => ({ name: s.name, customer: s.customers?.name ?? '' }))
    },
  })
}

export function useContractorWorkers(contractorId?: string | null) {
  return useQuery({
    queryKey: ['contractor_workers', 'byContractor', contractorId],
    enabled: !!contractorId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('contractor_workers')
        .select('*')
        .eq('contractor_id', contractorId)
        .is('deleted_at', null)
        .order('full_name')
      if (error) throw error
      return data as ContractorWorker[]
    },
  })
}

/**
 * מי מהקבלן ניתן לשיבוץ.
 *
 * ‏`useContractorWorkers` לעיל קורא את `contractor_workers` — הרוסטר הידני —
 * וזה מה שהזין את בורר השיבוץ עד 0071. הבעיה: חשבון עובד קבלן שהמשרד יצר
 * במסך העובדים נושא `contractor_id` בלי `contractor_worker_id`, ולכן אינו
 * יושב ברוסטר ומעולם לא הופיע בבורר. ה-RPC מאחד את שתי הרשימות; פריט בלי
 * `worker_id` הוא חשבון שעדיין אין לו שורת סגל, ו-`contractor_assign_worker`
 * יוצר לו אותה בשיבוץ.
 *
 * שני ההוקים אינם מתחרים: הרוסטר הוא מה שמנהלים במסך "העובדים שלי", והאיחוד
 * הוא מה שמשבצים ממנו.
 */
export interface AssignableContractorWorker {
  worker_id: string | null
  profile_id: string | null
  full_name: string
  phone: string | null
  has_login: boolean
}

export function useContractorAssignableWorkers(contractorId?: string | null) {
  return useQuery({
    queryKey: ['contractor_assignable', contractorId],
    enabled: !!contractorId,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('contractor_assignable_workers', {
        p_contractor_id: contractorId,
      })
      if (error) throw error
      return (data ?? []) as AssignableContractorWorker[]
    },
  })
}

/**
 * שיבוץ עובד קבלן למשימה, והסרתו.
 *
 * דרך RPC ולא בכתיבה ישירה ל-`task_contractor_workers`, כי שיבוץ של חשבון
 * שאין לו שורת סגל חייב ליצור אותה קודם — ושתי הכתיבות באותה טרנזקציה.
 *
 * `onSettled` ולא `onSuccess`: כשלון הרשאה מגיע אחרי שהמצב האופטימי כבר צויר,
 * ורענון בשני המקרים הוא מה שמחזיר את המסך למה שבשרת באמת יש.
 */
export function useContractorWorkerAssign() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (v: {
      taskId: string
      workerId?: string | null
      profileId?: string | null
      on: boolean
      workSite?: 'field' | 'warehouse'
    }) => {
      const { error } = await supabase.rpc('contractor_assign_worker', {
        p_task_id: v.taskId,
        p_worker_id: v.workerId ?? null,
        p_profile_id: v.profileId ?? null,
        p_on: v.on,
        p_work_site: v.workSite ?? 'field',
      })
      if (error) throw error
    },
    onSettled: () => {
      void qc.invalidateQueries({ queryKey: ['workboard'] })
      /* השיבוץ עשוי ליצור שורת סגל, ולכן גם שתי רשימות העובדים מתיישנות */
      void qc.invalidateQueries({ queryKey: ['contractor_assignable'] })
      void qc.invalidateQueries({ queryKey: ['contractor_workers'] })
    },
  })
}

/**
 * מחשבוני התמחור של לקוח, אחד לכל סוג משימה.
 *
 * customer_pricing_rules חסומה ב-RLS למי שאין לו pricing.manage_rules או
 * pricing.view, ולכן ההוק הזה יחזיר רשימה ריקה ולא ישבור — הקריאה גם ככה
 * נעשית רק ממסך שמגודר באותו מפתח.
 */
export function useCustomerPricingRules(customerId?: string | null) {
  return useQuery({
    queryKey: ['customer_pricing_rules', customerId],
    enabled: !!customerId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('customer_pricing_rules')
        .select('*')
        .eq('customer_id', customerId)
      if (error) throw error
      return data as CustomerPricingRule[]
    },
  })
}

/** null כשאין עדיין מחיר, או כשהמשתמש אינו רשאי לראות אותו. */
export function useTaskPricing(taskId?: string | null) {
  return useQuery({
    queryKey: ['task_pricing', taskId],
    enabled: !!taskId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('task_pricing')
        .select('*')
        .eq('task_id', taskId)
        .maybeSingle()
      if (error) throw error
      return (data as TaskPricing) ?? null
    },
  })
}

/** אזורי הנסיעה של לקוח מסוים, ואת הגלובליים שחלים על כולם. */
export function usePricingZones(customerId?: string | null) {
  return useQuery({
    queryKey: ['pricing_zones', customerId ?? 'global'],
    queryFn: async () => {
      let q = supabase.from('pricing_zones').select('*').is('deleted_at', null)
      q = customerId ? q.or(`customer_id.eq.${customerId},customer_id.is.null`) : q.is('customer_id', null)
      const { data, error } = await q.order('priority').order('name')
      if (error) throw error
      return data as PricingZone[]
    },
  })
}

export function useCustomerFormConfig(customerId?: string | null) {
  return useQuery({
    queryKey: ['customer_form_fields', customerId],
    enabled: !!customerId,
    queryFn: async () => {
      const { data, error } = await supabase.from('customer_form_fields').select('*').eq('customer_id', customerId)
      if (error) throw error
      return data as { customer_id: string; field_key: string; state: 'visible' | 'hidden' | 'required' }[]
    },
  })
}

/**
 * The event-form config that actually applies to the signed-in user.
 *
 * Staff see the plain per-customer config for whichever customer they picked.
 * A client's config is the company config intersected with their personal
 * overrides, which get_my_permissions already merged server-side — reading it
 * from there rather than joining in the browser keeps it right even though
 * customer_form_fields is world-readable while user_form_fields is not.
 */
export function useEffectiveFormConfig(customerId?: string | null) {
  const me = useAuth((s) => s.me)
  const isCustomer = me?.profile.user_kind === 'customer_user'
  const perCustomer = useCustomerFormConfig(isCustomer ? null : customerId)
  return useMemo(
    () =>
      isCustomer
        ? ((me?.form_config ?? []) as { field_key: string; state: FieldState }[])
        : (perCustomer.data ?? []).map((c) => ({ field_key: c.field_key, state: c.state })),
    [isCustomer, me?.form_config, perCustomer.data],
  )
}

export function useUserFormFields(profileId?: string | null) {
  return useQuery({
    queryKey: ['user_form_fields', profileId],
    enabled: !!profileId,
    queryFn: async () => {
      const { data, error } = await supabase.from('user_form_fields').select('*').eq('profile_id', profileId)
      if (error) throw error
      return data as UserFormField[]
    },
  })
}

/** Sub-users of one customer — the list a client admin manages. */
export function useCustomerUsers(customerId?: string | null) {
  return useQuery({
    queryKey: ['profiles', 'byCustomer', customerId],
    enabled: !!customerId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .eq('customer_id', customerId)
        .eq('user_kind', 'customer_user')
        .is('deleted_at', null)
        .order('full_name')
      if (error) throw error
      return data as Profile[]
    },
  })
}

export function useCustomerExecutionMethods(customerId?: string | null) {
  return useQuery({
    queryKey: ['customer_execution_methods', customerId],
    enabled: !!customerId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('customer_execution_methods')
        .select('execution_method_id')
        .eq('customer_id', customerId)
      if (error) throw error
      return (data as { execution_method_id: string }[]).map((r) => r.execution_method_id)
    },
  })
}

export function useTaskTypeMethods() {
  return useQuery({
    queryKey: ['task_type_execution_methods', 'all'],
    queryFn: async () => {
      const { data, error } = await supabase.from('task_type_execution_methods').select('*')
      if (error) throw error
      return data as { task_type_id: string; execution_method_id: string }[]
    },
  })
}

/** Active methods ∩ those allowed for the task type ∩ those enabled for the customer. */
export function useAllowedExecutionMethods(taskTypeId?: string | null, customerId?: string | null) {
  const { data: methods = [] } = useExecutionMethods()
  const { data: typeMethods = [] } = useTaskTypeMethods()
  const { data: customerMethods } = useCustomerExecutionMethods(customerId)
  return useMemo(() => {
    let list = methods.filter((m) => m.is_active)
    if (taskTypeId) {
      const forType = typeMethods.filter((tm) => tm.task_type_id === taskTypeId).map((tm) => tm.execution_method_id)
      if (forType.length) list = list.filter((m) => forType.includes(m.id))
    }
    if (customerId && customerMethods) list = list.filter((m) => customerMethods.includes(m.id))
    return list
  }, [methods, typeMethods, taskTypeId, customerId, customerMethods])
}

/** קטלוג קטגוריות ההכנסה (0068) — מסך ההגדרות, כרטיס הלקוח וטופס האירוע. */
export function useIncomeCategories() {
  return useQuery({
    queryKey: ['income_categories', 'list'],
    queryFn: () => fetchList<IncomeCategory>('income_categories', 'sort_order'),
  })
}

/**
 * חלוקת ההכנסות של לקוח: קיום שורה = הקטגוריה מופעלת, והיא שמדליקה את שדות
 * הסכומים בטופס האירוע. RLS מחזירה ריק למי שאינו רשאי — הטופס פשוט לא יציג
 * את הסטפ, בלי שגיאה.
 */
export function useCustomerIncomeSplits(customerId?: string | null) {
  return useQuery({
    queryKey: ['customer_income_splits', customerId],
    enabled: !!customerId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('customer_income_splits')
        .select('*')
        .eq('customer_id', customerId)
      if (error) throw error
      return data as CustomerIncomeSplit[]
    },
  })
}

/** הסכומים שכבר הוזנו על אירוע — הידרציה של טופס העריכה. */
export function useEventIncome(eventId?: string | null) {
  return useQuery({
    queryKey: ['event_income', eventId],
    enabled: !!eventId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('event_income')
        .select('category_id, amount, viper_share_pct')
        .eq('event_id', eventId)
      if (error) throw error
      return data as { category_id: string; amount: number; viper_share_pct: number }[]
    },
  })
}

/** The הקמה/פירוק tasks the event trigger created — used to prefill the event form. */
export function useEventAutoTasks(eventId?: string | null) {
  return useQuery({
    queryKey: ['tasks', 'autoByEvent', eventId],
    enabled: !!eventId,
    queryFn: async () => {
      // task_pricing מסוננת ב-RLS, ולכן היא פשוט חוזרת ריקה למי שאינו רשאי
      // לראות מחירים — השדה בטופס הוא שמגודר, לא השאילתה.
      const { data, error } = await supabase
        .from('tasks')
        .select(
          'id, task_date, onsite_start_time, hours_count, worker_count, execution_method_id,' +
            ' task_types!inner(code), task_pricing(price, is_manual)',
        )
        .eq('event_id', eventId)
        .is('deleted_at', null)
        .in('task_types.code', ['setup', 'teardown'])
      if (error) throw error
      // PostgREST מחזיר אובייקט ליחס 1:1 ומערך אחרת; שני המקרים מטופלים כאן
      // כדי שהטופס לא יישבר על שינוי בזיהוי היחס.
      return ((data ?? []) as unknown as Record<string, unknown>[]).map((row) => {
        const p = row.task_pricing
        const one = Array.isArray(p) ? p[0] : p
        return { ...row, price: (one as { price?: number } | null)?.price ?? null }
      }) as unknown as EventAutoTask[]
    },
  })
}
