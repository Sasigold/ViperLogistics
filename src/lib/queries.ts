import { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { supabase } from './supabase'
import { useAuth } from '../state/auth'
import type {
  Contractor,
  ContractorWorker,
  Customer,
  CustomerPricingRule,
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
} from '../types/domain'

async function fetchList<T>(table: string, order = 'name'): Promise<T[]> {
  const { data, error } = await supabase.from(table).select('*').is('deleted_at', null).order(order)
  if (error) throw error
  return data as T[]
}

export function useCustomers() {
  return useQuery({ queryKey: ['customers', 'list'], queryFn: () => fetchList<Customer>('customers') })
}

export function useContractors() {
  return useQuery({ queryKey: ['contractors', 'list'], queryFn: () => fetchList<Contractor>('contractors') })
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

export function useFormFields() {
  return useQuery({
    queryKey: ['form_fields', 'list'],
    queryFn: async () => {
      const { data, error } = await supabase.from('form_fields').select('*').order('sort_order')
      if (error) throw error
      return data as FormField[]
    },
  })
}

export function useStaff() {
  return useQuery({
    queryKey: ['profiles', 'staff'],
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

/** The הקמה/פירוק tasks the event trigger created — used to prefill the event form. */
export function useEventAutoTasks(eventId?: string | null) {
  return useQuery({
    queryKey: ['tasks', 'autoByEvent', eventId],
    enabled: !!eventId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('tasks')
        .select('id, task_date, onsite_start_time, hours_count, worker_count, execution_method_id, task_types!inner(code)')
        .eq('event_id', eventId)
        .is('deleted_at', null)
        .in('task_types.code', ['setup', 'teardown'])
      if (error) throw error
      return data as unknown as EventAutoTask[]
    },
  })
}
