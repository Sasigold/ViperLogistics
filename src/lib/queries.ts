import { useQuery } from '@tanstack/react-query'
import { supabase } from './supabase'
import type {
  Contractor,
  ContractorWorker,
  Customer,
  ExecutionMethod,
  FormField,
  Profile,
  Status,
  Supplier,
  TaskType,
  Truck,
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
