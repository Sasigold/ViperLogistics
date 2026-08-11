export type UserKind = 'staff' | 'customer_user' | 'contractor_user'
export type StaffRole = 'worker' | 'driver' | 'team_lead'
export type FieldState = 'visible' | 'hidden' | 'required'
export type PermissionAction = 'view' | 'create' | 'edit' | 'delete'

export type PricingMode = 'manual' | 'auto'

export interface Customer {
  id: string
  name: string
  color: string
  can_create_events: boolean
  contact_name: string | null
  contact_phone: string | null
  contact_email: string | null
  notes: string | null
  /** manual = המחיר מוזן ביד; auto = מחושב ממחשבון התמחור של הלקוח */
  pricing_mode: PricingMode
  /** המחסן שממנו יוצאים למשימות של הלקוח הזה */
  warehouse_id: string | null
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
  /** זהות יציבה לסטטוסי מערכת — השם ניתן לשינוי בהגדרות, הקוד לא. סטטוס
   *  שנוצר ידנית מחזיק null, ואין לו משמעות מיוחדת למסכים. */
  code: string | null
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

/** The shape a custom field takes in the event form. */
export type CustomFieldType =
  | 'text'
  | 'textarea'
  | 'number'
  | 'date'
  | 'time'
  | 'select'
  | 'checkbox'

/** A value a custom field can hold — see `app.event_custom_patch`. */
export type CustomFieldValue = string | number | boolean | null

export interface FormField {
  field_key: string
  label_he: string
  sort_order: number
  /** null for the fixed system fields; a customer id for one they defined */
  customer_id: string | null
  field_type: CustomFieldType
  /** 'select' only — the values the field offers */
  options: string[]
  deleted_at: string | null
}

export interface CustomerFormField {
  customer_id: string
  field_key: string
  state: FieldState
}

/** Per-user narrowing on top of CustomerFormField — see app.form_config. */
export interface UserFormField {
  profile_id: string
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
  /** values of this customer's custom form fields, keyed by field_key */
  custom_fields: Record<string, CustomFieldValue>
  created_by: string | null
  deleted_at: string | null
  customers?: { name: string; color: string }
  statuses?: { name: string; color: string } | null
}

export type EventActivityKind =
  | 'created'
  | 'changed'
  | 'note'
  | 'deleted'
  | 'restored'
  | 'task_added'
  | 'task_removed'

/**
 * A line of an event's activity log, as `event_activity_feed` returns it: a
 * tracked field the database saw move, or free text somebody wrote.
 */
export interface EventActivity {
  id: number
  event_id: string
  kind: EventActivityKind
  actor_profile_id: string | null
  actor_name: string | null
  /** 'changed' rows only — matches field_registry where an entry exists */
  field_key: string | null
  field_label: string | null
  old_value: string | null
  new_value: string | null
  /** free text: 'note' rows, and the description of a task that came or went */
  note: string | null
  created_at: string
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
  truck_ids: string[] | null
  truck_free_text: string | null
  notes: string | null
  status_id: string
  contractor_id: string | null
  location_text: string | null
  /** דריסה של זמן הנסיעה. null = לפי אזור הגיאופנס של מיקום האירוע. */
  travel_hours: number | null
  /** דריסה של "נדרש ראש צוות". null = לפי הקבוע במחשבון. */
  requires_team_lead: boolean | null
  /** מאיזה מחסן יוצאים. null = לפי המחסן הקרוב ביותר בעת ההחתמה. */
  warehouse_id: string | null
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
  /** null גם כשקיים מחיר, אם למשתמש אין pricing.view */
  price: number | null
  task_types: { code: 'setup' | 'teardown' }
}

export interface AssignmentPerson {
  profile_id: string
  name: string
  truck_id?: string | null
  truck_name?: string | null
  /** מהיכן הוא מתחיל — קובע את שעת ההתחלה של המשמרת שלו */
  work_site?: 'field' | 'warehouse'
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
  /** כל המשאיות של המשימה, לפי סדר. הראשונה היא גם `truck_id`. */
  truck_ids: string[] | null
  truck_list: { id: string; name: string }[] | null
  /** האירוע שהמשימה שייכת לו בוטל — הלוח משמיט אותה */
  event_is_cancelled: boolean
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
  contractor_worker_list: { id: string; name: string; work_site?: 'field' | 'warehouse' }[] | null
  /** null גם כשקיים מחיר, אם למשתמש אין pricing.view — הקבלן תמיד כאן. */
  customer_price: number | null
  price_is_manual: boolean | null
  price_breakdown: PriceBreakdown | null
  travel_hours: number | null
  requires_team_lead: boolean | null
}

/* ===== תמחור ============================================================== */

/**
 * שני מודלים, כי לתמחור אירועים יש שתי צורות שונות באמת:
 *   worker_hours — שעות × תעריף ⇒ מחיר לעובד, × כמות עובדים, + תוספות ומקדמים.
 *                  זו הצורה של הקמה/פירוק.
 *   line_items   — סכום שורות בלתי תלויות. כרטיס תעריפים לפי קוב או משאית.
 * הטיפוסים כאן חייבים להישאר תואמים ל-app.price_calc במיגרציה 0017 — היא
 * המבצעת, וזה רק החוזה מולה.
 */
export type PricingModel = 'worker_hours' | 'line_items'

export type PriceCondOp =
  | 'eq' | 'ne' | 'gt' | 'gte' | 'lt' | 'lte'
  | 'in' | 'not_in' | 'is_true' | 'is_false' | 'between'

export interface PriceTest {
  field: string
  op: PriceCondOp
  value?: unknown
}
/** null או אובייקט ריק = תמיד אמת. */
export type PriceCond = { all: PriceTest[] } | { any: PriceTest[] } | PriceTest | null

/** רכיב זמן במודל worker_hours. */
export interface PricingHourComponent {
  id: string
  label: string
  kind: 'const' | 'input' | 'stepped'
  /** const */
  hours?: number
  /** input — שם משתנה, עם מכפיל (למשל נסיעה ×2 להלוך-חזור) */
  input?: string
  multiplier?: number
  /** stepped — "הראשון שעה, כל נוסף חצי שעה" */
  first?: number
  each_additional?: number
  when?: PriceCond
  enabled?: boolean
}

export interface PricingWorkerAdjustment {
  id: string
  label: string
  /** ברירת מחדל fixed — כך נקראת גם תוספת ישנה שנשמרה בלי השדה */
  kind?: 'fixed' | 'per_unit'
  /** fixed — כמות העובדים; per_unit — כמות העובדים לכל יחידה */
  add: number
  /** per_unit — נתון הכמות, למשל truck_count */
  input?: string
  /** per_unit — חצי עובד אינו אדם, וכאן נקבע לאן מעגלים */
  rounding?: 'none' | 'up' | 'down' | 'nearest'
  when?: PriceCond
}

/** תוספת שמתווספת אחרי ההכפלה בכמות העובדים. */
export interface PricingAfterWorkers {
  id: string
  label: string
  kind: 'fixed' | 'per_worker' | 'percent' | 'var'
  amount?: number
  /** per_worker — לפי העובדים המקוריים או לפי אלה שיוצאים בפועל */
  workers_basis?: 'base' | 'effective'
  input?: string
  multiplier?: number
  when?: PriceCond
}

export interface PricingTier {
  up_to: number | null
  amount?: number
  rate?: number
}

/** רכיב במודל line_items. */
export interface PricingComponent {
  id: string
  label: string
  kind: 'fixed' | 'per_unit' | 'tiered' | 'surcharge' | 'var'
  amount?: number
  input?: string
  rate?: number
  multiplier?: number
  included_units?: number
  min_units?: number
  max_units?: number
  mode?: 'flat' | 'progressive'
  tiers?: PricingTier[]
  amount_kind?: 'fixed' | 'percent'
  when?: PriceCond
  enabled?: boolean
}

export interface PricingMultiplier {
  id: string
  label: string
  factor: number
  when?: PriceCond
  enabled?: boolean
}

export interface PricingConfig {
  version: number
  model: PricingModel
  /** ערכי בסיס למשתנים שאין להם שדה — הפסקה, ספייר, "נדרש ראש צוות" */
  constants?: Record<string, unknown>
  /* worker_hours */
  hour_rate?: number
  per_worker_fee?: number
  hours?: PricingHourComponent[]
  workers?: { input: string; adjustments?: PricingWorkerAdjustment[] }
  after_workers?: PricingAfterWorkers[]
  /* line_items */
  components?: PricingComponent[]
  /* משותף */
  multipliers?: PricingMultiplier[]
  discount?: { kind: 'fixed' | 'percent'; amount: number; label?: string } | null
  min_price?: number | null
  max_price?: number | null
  rounding?: { mode: 'nearest' | 'up' | 'down'; to: number }
}

/** שורת פירוט אחת בחישוב. amount null = השורה מסבירה ולא מוסיפה כסף. */
export interface PriceLine {
  id: string | null
  label: string | null
  amount: number | null
  detail: string | null
}

export interface PriceHourLine {
  id: string | null
  label: string | null
  hours: number
}

/** מה ש-app.price_calc מחזירה — נשמר כפי שהוא ב-task_pricing.breakdown. */
export interface PriceBreakdown {
  version: number
  model: PricingModel
  total: number
  subtotal: number
  hours: number
  per_worker: number
  base_workers: number
  workers: number
  hour_lines: PriceHourLine[]
  lines: PriceLine[]
}

export interface TaskPricing {
  task_id: string
  price: number
  is_manual: boolean
  breakdown: PriceBreakdown | null
  calculated_at: string | null
}

export interface CustomerPricingRule {
  id: string
  customer_id: string
  task_type_id: string
  config: PricingConfig
  is_active: boolean
}

export interface PricingZone {
  id: string
  /** null = אזור גלובלי. אזור של לקוח תמיד גובר עליו. */
  customer_id: string | null
  name: string
  shape: 'polygon' | 'circle'
  /** [[lat, lng], ...] — הסדר שבו Leaflet ו-events.location_lat עובדים */
  points: [number, number][] | null
  center_lat: number | null
  center_lng: number | null
  radius_km: number | null
  travel_hours: number
  surcharge: number
  /** נמוך יותר גובר, כדי שאזור קטן ינצח אזור גדול שמכיל אותו */
  priority: number
  color: string
  notes: string | null
  is_active: boolean
  deleted_at: string | null
}

export interface FieldPermission {
  entity: string
  field_key: string
  can_view: boolean
  can_edit: boolean
}

export type PermissionCategory = 'access' | 'crud' | 'field' | 'action' | 'admin'

export type ScopeType =
  | 'all'
  | 'own'
  | 'customers'
  | 'contractors'
  | 'task_types'
  | 'statuses'
  | 'execution_methods'
  | 'trucks'
  | 'date_window'

/** A row of `permission_registry` — the catalog the admin screens render from. */
export interface PermissionDef {
  key: string
  module: string
  resource: string
  action: string
  label_he: string
  description_he: string | null
  category: PermissionCategory
  is_dangerous: boolean
  applies_to: UserKind[]
  implied_by: string | null
  default_allowed: boolean
  sort_order: number
  is_active: boolean
}

export interface PermissionModule {
  key: string
  label_he: string
  description_he: string | null
  icon: string | null
  sort_order: number
}

/** A row of `field_registry` — drives the per-field view/edit editor. */
export interface FieldDef {
  entity: string
  field_key: string
  label_he: string
  module: string
  table_name: string | null
  column_name: string | null
  is_sensitive: boolean
  default_can_view: boolean
  default_can_edit: boolean
  edit_permission_key: string | null
  sort_order: number
}

export interface PermissionRole {
  id: string
  key: string
  name_he: string
  description_he: string | null
  user_kind: UserKind | null
  is_system: boolean
  sort_order: number
  is_active: boolean
  deleted_at: string | null
}

/** Which rows a user may see, for one resource and one dimension. */
export interface PermissionScope {
  id: string
  profile_id: string | null
  role_id: string | null
  resource: string
  scope_type: ScopeType
  scope_values: string[]
  days_back: number | null
  days_forward: number | null
}

/** The scope rows as `get_my_permissions` returns them (no ids, already resolved). */
export interface MyScope {
  resource: string
  scope_type: ScopeType
  values: string[]
  days_back: number | null
  days_forward: number | null
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
  /** worker / driver / team_lead — what the person does, not what they may do */
  roles: StaffRole[]
  /** the permission roles they belong to */
  app_roles: { id: string; key: string; name_he: string }[]
  customer: { id: string; name: string; color: string; can_create_events: boolean } | null
  /** legacy nested shape, kept so `can(resource, action)` call sites still work */
  permissions: Record<string, Partial<Record<PermissionAction, boolean>>>
  /** every registry key, already resolved by the server */
  capabilities: Record<string, boolean>
  /**
   * Which kinds of person this user may open an account for, resolved by the
   * server through `app.may_create_profile` — the same predicate the insert
   * policy uses, so the form can never offer an option the write would refuse.
   */
  creatable_user_kinds: UserKind[]
  field_permissions: FieldPermission[]
  scopes: MyScope[]
  /** company form config already intersected with this user's overrides */
  form_config: { field_key: string; state: FieldState }[]
}

/**
 * `dashboard_stats`, the one dashboard RPC. A section the caller holds no key
 * for comes back `null` rather than zero or `[]` — 0 means "none", null means
 * "not for you", and the screen draws the first and omits the second.
 */
export interface DashboardStats {
  events_count: number
  events_upcoming: number
  events_done: number
  tasks_count: number
  tasks_open: number
  tasks_today: number
  tasks_week: number
  tasks_overdue: number
  /** null ללא dashboard.all_workers */
  available_workers: number | null
  /** null ללא customers.view — ללקוח יש לקוח אחד והגרף חסר משמעות */
  by_customer: { name: string; color: string; cnt: number }[] | null
  /** null ללא dashboard.contractors */
  by_contractor: { name: string; cnt: number }[] | null
  /** null ללא dashboard.all_workers */
  by_worker: { name: string; cnt: number }[] | null
  by_status: { name: string; color: string; cnt: number }[]
  /** null ללא dashboard.financial */
  financial: { expected: number; paid: number } | null
  /** null ללא pricing.revenue */
  revenue: {
    total: number
    priced_tasks: number
    by_customer: { name: string; color: string; total: number }[] | null
  } | null
  next_events: {
    id: string
    event_date: string
    end_client_name: string | null
    event_number: string | null
    location_text: string | null
  }[]
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
  /** הסוג הושתק לנמען הזה: השורה נשמרה כיומן אך אינה מוצגת בפעמון. */
  muted: boolean
}

/** ערוצי ההתראות (0046). 'inapp' הוא הפעמון במערכת. */
export type NotificationChannel = 'inapp' | 'email' | 'push'

/**
 * המצב שמנהל קובע לתא במטריצה.
 *   off     — לא נשלח, והמשתמש אינו יכול להדליק
 *   opt_in  — כבוי כברירת מחדל, המשתמש יכול להדליק
 *   opt_out — דלוק כברירת מחדל, המשתמש יכול לכבות
 *   forced  — נעול: תמיד נשלח, והמשתמש אינו יכול לכבות
 */
export type NotificationMode = 'off' | 'opt_in' | 'opt_out' | 'forced'

/** הקהלים במטריצה. 'admin' אינו user_kind אלא profiles.is_admin. */
export type NotificationAudience = 'admin' | 'staff' | 'contractor_user' | 'customer_user'

export interface NotificationType {
  key: string
  label_he: string
  description_he: string | null
  group_he: string
  audiences: NotificationAudience[]
  entity_type: string | null
  default_mode_inapp: NotificationMode
  default_mode_email: NotificationMode
  default_mode_push: NotificationMode
  is_active: boolean
  sort_order: number
}

export interface NotificationPolicy {
  audience: NotificationAudience
  type: string
  channel: NotificationChannel
  mode: NotificationMode
}

export interface NotificationPolicyOverride extends Omit<NotificationPolicy, 'audience'> {
  profile_id: string
  note: string | null
}

/** תא בודד כפי ש-my_notification_settings מחזיר אותו. */
export interface NotificationCell {
  mode: NotificationMode
  enabled: boolean
  /** המנהל קבע — המשתמש אינו יכול לשנות. */
  locked: boolean
  /** הערוץ עצמו דלוק במערכת. */
  channel_enabled: boolean
}

export interface NotificationSetting {
  type: string
  label_he: string
  description_he: string | null
  group_he: string
  channels: Record<NotificationChannel, NotificationCell>
}

export interface PushSubscriptionRow {
  id: string
  profile_id: string
  endpoint: string
  user_agent: string | null
  created_at: string
  last_seen_at: string
  failure_count: number
  last_error: string | null
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

/* ===== נוכחות ומשמרות ===================================================== */

/** מהיכן העובד מתחיל את המשמרת. */
export type WorkSite = 'field' | 'warehouse'

export interface Warehouse {
  id: string
  name: string
  address: string | null
  lat: number | null
  lng: number | null
  /** null = לפי הרדיוס הגלובלי */
  radius_m: number | null
  color: string
  notes: string | null
  is_active: boolean
  sort_order: number
}

/** משמרת נגזרת — מיוצרת ב-app.planned_shifts ולא נשמרת בשום טבלה. */
export interface PlannedShift {
  profile_id: string
  work_date: string
  seq: number
  shift_start: string
  shift_end: string
  planned_hours: number | null
  work_site: WorkSite
  task_ids: string[]
  first_task_id: string | null
  last_task_id: string | null
  start_lat: number | null
  start_lng: number | null
  end_lat: number | null
  end_lng: number | null
  travel_hours: number | null
  label: string | null
  customer_id: string | null
  customer_color: string | null
  /** המחסן שממנו יוצאים, כשהמשמרת מתחילה במחסן ומישהו נקב בו */
  warehouse_id: string | null
  warehouse_name: string | null
}

/**
 * שורה ברוסטר של לוח המשמרות, מ-shift_roster.
 *
 * מגיעה מ-RPC ולא מ-profiles כי profiles_select מראה לעובד צוות רק שורות
 * user_kind='staff' — עובד קבלן שקיבל התחברות פשוט אינו שם.
 */
export interface ShiftRosterEntry {
  id: string
  full_name: string
  contractor_id: string | null
  contractor_name: string | null
  is_contractor: boolean
  /** עובד שהושבת מופיע רק אם יש לו שיבוץ בטווח המוצג */
  is_active: boolean
}

/** משימה אחת בתוך משמרת, מ-shift_task_breakdown. */
export interface ShiftTaskRow {
  task_id: string
  /** מיקומה בסדר הזמנים של המשמרת, החל מ-1 */
  ord: number
  title: string
  task_type_name: string
  task_type_code: string | null
  customer_id: string | null
  customer_name: string | null
  customer_color: string | null
  event_id: string | null
  event_number: string | null
  end_client_name: string | null
  location_text: string | null
  location_lat: number | null
  location_lng: number | null
  work_site: WorkSite
  warehouse_id: string | null
  warehouse_name: string | null
  start_at: string
  onsite_start_at: string
  end_at: string
  hours_count: number | null
  travel_hours: number | null
  /** דקות מסיום המשימה הקודמת. null בראשונה שבמשמרת. */
  gap_minutes: number | null
  status_name: string | null
  status_color: string | null
  truck_name: string | null
  execution_method_name: string | null
  /** null לעובד קבלן, שאין לו שורת task_assignments ולכן אין לו תפקיד */
  my_role: StaffRole | null
  worker_count: number | null
  assigned_count: number
  /** null למי שאין לו board.view_staffing */
  team: string[] | null
  notes: string | null
}

/** הפירוק המלא של משמרת אחת למשימות שמרכיבות אותה. */
export interface ShiftBreakdown {
  profile_id: string
  full_name: string | null
  tasks: ShiftTaskRow[]
  totals: {
    tasks: number
    work_hours: number
    /** הנסיעה של המשימה האחרונה בלבד — כמו בגזירה עצמה, ולא סכום */
    travel_hours: number
    idle_minutes: number
  }
  /** מחושב מחדש מהמשימות, ולא מהשורה שממנה נפתחה המגירה */
  shift: {
    start: string | null
    end: string | null
    work_site: WorkSite | null
    warehouse_name: string | null
  }
}

/**
 * שורת חישוב אחת בפירוט השכר.
 *
 * `hours` ו-`rate` הם null בשורה שאינה מכפלה — הבונוס למשמרת הוא סכום קבוע,
 * ו-"0:00 × 0" בעמודה שלידו היה שקר. מי שמציג שורות חייב לדלג עליהם.
 */
export interface PayLine {
  key: string
  label: string
  hours: number | null
  rate: number | null
  /** null כשאין תעריף שעתי, או כשלמשתמש אין הרשאה לראות סכומים */
  amount: number | null
}

export interface PayBreakdown {
  version: number
  paid_hours: number
  worked_hours: number
  base_hours: number
  overtime_hours: number
  topup_hours: number
  is_rest_day: boolean
  /** השדות האלה מושמטים מהאובייקט למי שאינו רשאי לראות כסף */
  hourly_rate?: number | null
  rate_hours?: number
  /** בונוס למשמרת. כלול ב-total ואינו נוסף עליו. */
  bonus?: number
  total?: number | null
  lines?: PayLine[]
}

/**
 * מצב האישור של רשומת נוכחות. pending הוא דיווח ידני של עובד שטרם הוכרע,
 * ואינו נספר בשעות ובשכר עד שיאושר.
 */
export type AttendanceStatus = 'pending' | 'approved' | 'rejected'

export interface AttendanceEntry {
  id: string
  profile_id: string
  work_date: string
  seq: number
  shift_start: string | null
  shift_end: string | null
  planned_hours: number | null
  work_site: WorkSite | null
  task_ids: string[]
  clock_in_at: string
  clock_out_at: string | null
  clock_in_lat: number | null
  clock_in_lng: number | null
  clock_in_distance_m: number | null
  clock_out_distance_m: number | null
  raw_clock_in_at: string | null
  raw_clock_out_at: string | null
  actual_hours: number | null
  source: 'clock' | 'manual'
  status: AttendanceStatus
  reviewed_by: string | null
  reviewed_at: string | null
  flags: string[]
  employee_note: string | null
  manager_note: string | null
  edited_at: string | null
}

/** שורת הדוח, כפי ש-attendance_report מרכיב אותה. */
export interface AttendanceReportRow {
  id: string
  profile_id: string
  full_name: string
  contractor_id: string | null
  work_date: string
  seq: number
  shift_start: string | null
  shift_end: string | null
  planned_hours: number | null
  work_site: WorkSite | null
  task_ids: string[]
  clock_in_at: string
  clock_out_at: string | null
  actual_hours: number | null
  in_distance_m: number | null
  out_distance_m: number | null
  raw_clock_in_at: string | null
  raw_clock_out_at: string | null
  source: 'clock' | 'manual'
  status: AttendanceStatus
  reviewed_at: string | null
  flags: string[]
  employee_note: string | null
  manager_note: string | null
  edited_at: string | null
  /** האם שעות נוספות חלות על העובד הזה — ההגדרה האפקטיבית שלו, לא כמה עשה */
  overtime_enabled: boolean
  /** נימוק הבונוס. null גם כשאין בונוס וגם כשאין הרשאה לראות סכומים */
  bonus_note: string | null
  pay: PayBreakdown
}

export interface AttendanceReport {
  rows: AttendanceReportRow[]
  can_see_pay: boolean
  /** הסיכומים סופרים שורות מאושרות בלבד; מה שממתין נספר בנפרד */
  totals: {
    entries: number
    pending: number
    pending_hours: number
    actual_hours: number
    paid_hours: number
    overtime_hours: number
    /** סך הבונוסים. כלול ב-total ואינו נוסף עליו; null בלי הרשאת כסף */
    bonus: number | null
    total: number | null
  }
}

export interface WorkerPaySettings {
  profile_id: string
  hourly_rate: number | null
  overtime_enabled: boolean
  min_hours_per_shift: number | null
  travel_paid: boolean
  /** null בכל אחד מאלה = לך לפי ההגדרה הגלובלית */
  clock_enabled: boolean | null
  requires_location: boolean | null
  location_radius_m: number | null
  allow_early_clock_in: boolean | null
  early_grace_minutes: number | null
  allow_clock_without_shift: boolean | null
  notes: string | null
}

export interface OvertimeTier {
  /** null = "וכל מה שמעל" */
  hours: number | null
  rate: number
}

export interface OvertimeConfig {
  version: number
  daily: { base_hours: number; tiers: OvertimeTier[] }
  rest_day: { dow: number[]; base_hours: number; base_rate: number; tiers: OvertimeTier[] }
  weekly: { enabled: boolean; base_hours: number; rate: number }
  rounding: { minutes: number; mode: 'nearest' | 'up' | 'down' }
  top_up: { counts_toward_overtime: boolean }
}

export interface ClockConfig {
  version: number
  merge_gap_minutes: number
  clock_enabled: boolean
  requires_location: boolean
  location_radius_m: number
  allow_early_clock_in: boolean
  early_grace_minutes: number
  allow_clock_without_shift: boolean
  max_accuracy_m: number
  auto_close_after_hours: number
  /** דיווח משמרת ידני של עובד, לאישור מנהל */
  self_entry: {
    enabled: boolean
    max_backdate_days: number
    max_hours: number
  }
}

/** מה שדף השעון צריך כדי לצייר את עצמו, מ-attendance_my_status. */
export interface ClockStatus {
  open_entry: AttendanceEntry | null
  shift: PlannedShift | null
  rules: ClockConfig
  can_submit: boolean
  today: AttendanceEntry[]
  /** הדיווחים הידניים שלי שממתינים לאישור או שנדחו, 45 יום אחורה */
  reports: AttendanceEntry[]
}

/**
 * שורה אחת מ-assignment_conflicts: מישהו שמשובץ למשימה הנבדקת ומשובץ גם
 * למשימה שחופפת לה בזמן.
 */
export interface AssignmentConflict {
  kind: 'worker' | 'contractor_worker' | 'truck'
  subject_id: string
  subject_name: string | null
  role: string | null
  task_id: string
  task_label: string | null
  customer_name: string | null
  task_date: string
  starts_at: string
  ends_at: string
}
