export type UserKind = 'staff' | 'customer_user' | 'contractor_user'
export type StaffRole = 'worker' | 'driver' | 'team_lead'
export type FieldState = 'visible' | 'hidden' | 'required'
export type PermissionAction = 'view' | 'create' | 'edit' | 'delete'

export interface Customer {
  id: string
  name: string
  color: string
  can_create_events: boolean
  contact_name: string | null
  contact_phone: string | null
  contact_email: string | null
  notes: string | null
  is_active: boolean
  deleted_at: string | null
}

export interface Contractor {
  id: string
  name: string
  contact_name: string | null
  phone: string | null
  email: string | null
  notes: string | null
  default_task_price: number | null
  is_active: boolean
  deleted_at: string | null
}

export interface ContractorWorker {
  id: string
  contractor_id: string
  full_name: string
  phone: string | null
  id_number: string | null
  user_id: string | null
  is_active: boolean
  deleted_at: string | null
}

export interface Profile {
  id: string
  user_id: string | null
  user_kind: UserKind
  is_admin: boolean
  full_name: string
  phone: string | null
  email: string | null
  customer_id: string | null
  contractor_id: string | null
  notes: string | null
  is_active: boolean
  deleted_at: string | null
  staff_roles?: { role: StaffRole }[]
}

export interface TaskType {
  id: string
  name: string
  code: string | null
  is_system: boolean
  auto_create_on_event: boolean
  sort_order: number
  is_active: boolean
  deleted_at: string | null
}

export interface ExecutionMethod {
  id: string
  name: string
  sort_order: number
  is_active: boolean
  deleted_at: string | null
}

export interface Status {
  id: string
  entity: 'task' | 'event'
  name: string
  color: string
  sort_order: number
  is_default: boolean
  is_terminal: boolean
  is_active: boolean
  deleted_at: string | null
}

export interface Truck {
  id: string
  name: string
  plate_number: string | null
  notes: string | null
  is_active: boolean
  deleted_at: string | null
}

export interface Supplier {
  id: string
  customer_id: string
  name: string
  phone: string | null
  address: string | null
  notes: string | null
  is_active: boolean
  deleted_at: string | null
}

export interface FormField {
  field_key: string
  label_he: string
  sort_order: number
}

export interface CustomerFormField {
  customer_id: string
  field_key: string
  state: FieldState
}

export interface EventRow {
  id: string
  customer_id: string
  end_client_name: string | null
  event_number: string | null
  event_date: string
  location_text: string | null
  location_provider: string | null
  location_place_id: string | null
  location_lat: number | null
  location_lng: number | null
  location_notes: string | null
  volume_m: number | null
  truck_count: number | null
  notes: string | null
  status_id: string | null
  no_parking: boolean
  porterage: boolean
  supplier_pickup: boolean
  created_by: string | null
  deleted_at: string | null
  customers?: { name: string; color: string }
  statuses?: { name: string; color: string } | null
}

export interface TaskRow {
  id: string
  event_id: string | null
  customer_id: string | null
  task_type_id: string
  title: string | null
  task_date: string
  onsite_start_time: string | null
  warehouse_start_time: string | null
  hours_count: number | null
  onsite_end_time: string | null
  worker_count: number
  execution_method_id: string | null
  truck_id: string | null
  truck_free_text: string | null
  notes: string | null
  status_id: string
  contractor_id: string | null
  location_text: string | null
  updated_at: string
  deleted_at: string | null
}

/** The auto-created הקמה/פירוק task, as read back into the event form. */
export interface EventAutoTask {
  id: string
  task_date: string
  onsite_start_time: string | null
  hours_count: number | null
  worker_count: number
  execution_method_id: string | null
  task_types: { code: 'setup' | 'teardown' }
}

export interface AssignmentPerson {
  profile_id: string
  name: string
  truck_id?: string | null
  truck_name?: string | null
}

export interface WorkBoardRow {
  id: string
  event_id: string | null
  customer_id: string | null
  customer_name: string | null
  customer_color: string | null
  end_client_name: string | null
  event_number: string | null
  location_text: string | null
  volume_m: number | null
  event_truck_count: number | null
  task_type_id: string
  task_type_name: string
  task_type_code: string | null
  title: string | null
  task_date: string
  warehouse_start_time: string | null
  onsite_start_time: string | null
  onsite_end_time: string | null
  hours_count: number | null
  worker_count: number
  execution_method_id: string | null
  execution_method_name: string | null
  truck_id: string | null
  truck_name: string | null
  truck_free_text: string | null
  notes: string | null
  status_id: string
  status_name: string
  status_color: string
  status_is_terminal: boolean
  contractor_id: string | null
  contractor_name: string | null
  updated_at: string
  team_lead_id: string | null
  team_lead_name: string | null
  workers: AssignmentPerson[] | null
  drivers: AssignmentPerson[] | null
  contractor_worker_list: { id: string; name: string }[] | null
}

export interface FieldPermission {
  entity: string
  field_key: string
  can_view: boolean
  can_edit: boolean
}

export interface MyPermissions {
  profile: {
    id: string
    full_name: string
    user_kind: UserKind
    is_admin: boolean
    customer_id: string | null
    contractor_id: string | null
    phone: string | null
    email: string | null
  }
  roles: StaffRole[]
  customer: { id: string; name: string; color: string; can_create_events: boolean } | null
  permissions: Record<string, Partial<Record<PermissionAction, boolean>>>
  field_permissions: FieldPermission[]
}

export interface Notification {
  id: string
  recipient_id: string
  type: string
  title: string
  body: string | null
  entity_type: string | null
  entity_id: string | null
  read_at: string | null
  created_at: string
}

export interface SavedFilter {
  id: string
  profile_id: string
  screen: string
  name: string
  filters: Record<string, unknown>
  is_default: boolean
}

export interface AddressSuggestion {
  provider: string
  place_id: string
  label: string
  lat: number
  lng: number
}

export interface SearchResult {
  kind: 'event' | 'customer' | 'profile' | 'task'
  id: string
  title: string
  subtitle: string
  extra: string | null
}
