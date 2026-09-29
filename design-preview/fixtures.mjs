// נתוני דמה בלבד — אין כאן שום מידע אמיתי. משמשים לצילומי מסך של תצוגת עיצוב.
const TODAY = '2026-09-29'
const id = (p, n) => `${p}-0000-4000-8000-${String(n).padStart(12, '0')}`

export const customers = [
  { id: id('c1', 1), name: 'ארקו אירועים', color: '#3563f0' },
  { id: id('c1', 2), name: 'הפקות הכרמל', color: '#1fa189' },
  { id: id('c1', 3), name: 'סטודיו לב', color: '#e5484d' },
  { id: id('c1', 4), name: 'גולדן גייט', color: '#f5a524' },
  { id: id('c1', 5), name: 'לילך פסטיבלים', color: '#8e4ec6' },
].map((c) => ({
  ...c, can_create_events: true, contact_name: null, contact_phone: null, contact_email: null, notes: null,
  pricing_mode: 'manual', warehouse_id: null, performed_by_enabled: true, commission_pct: null,
  commission_min_event: 0, quote_enabled: true, warehouse_schedule_enabled: false, is_active: true, deleted_at: null,
}))

const st = (n, entity, code, name, color, sort, extra = {}) => ({
  id: id('s1', n), entity, code, name, color, sort_order: sort, is_default: sort === 1,
  is_terminal: false, is_active: true, deleted_at: null, ...extra,
})
export const statuses = [
  st(1, 'event', 'new', 'חדש', '#3563f0', 1),
  st(2, 'event', 'approved', 'מאושר', '#1fa189', 2),
  st(3, 'event', 'in_progress', 'בביצוע', '#f5a524', 3),
  st(4, 'event', 'done', 'הושלם', '#6b7280', 4, { is_terminal: true }),
  st(5, 'event', 'cancelled', 'בוטל', '#e5484d', 5, { is_terminal: true }),
  st(11, 'task', 'draft', 'טיוטה', '#8a93a5', 1),
  st(12, 'task', 'planned', 'מתוכנן', '#f5a524', 2),
  st(13, 'task', 'assigned', 'משובץ', '#1fa189', 3),
]
const S = Object.fromEntries(statuses.map((s) => [s.code + s.entity, s]))

export const taskTypes = [
  { id: id('t1', 1), name: 'העמסה והובלה', code: 'setup', is_system: true, auto_create_on_event: true, sort_order: 1, is_active: true, deleted_at: null },
  { id: id('t1', 2), name: 'פירוק ואיסוף', code: 'teardown', is_system: true, auto_create_on_event: true, sort_order: 2, is_active: true, deleted_at: null },
  { id: id('t1', 3), name: 'הכנה במחסן', code: 'prep', is_system: false, auto_create_on_event: false, sort_order: 3, is_active: true, deleted_at: null },
]
export const methods = [
  { id: id('m1', 1), name: 'משאית + צוות', sort_order: 1, is_transport_only: false, requires_team_lead: true, is_active: true, deleted_at: null },
  { id: id('m1', 2), name: 'הובלה בלבד', sort_order: 2, is_transport_only: true, requires_team_lead: false, is_active: true, deleted_at: null },
]
export const trucks = [
  { id: id('k1', 1), name: 'איווקו 12 טון', plate_number: '12-345-67', notes: null, is_active: true, deleted_at: null },
  { id: id('k1', 2), name: 'מרצדס ספרינטר', plate_number: '98-765-43', notes: null, is_active: true, deleted_at: null },
  { id: id('k1', 3), name: 'איסוזו 7.5 טון', plate_number: '55-221-09', notes: null, is_active: true, deleted_at: null },
]
export const contractors = [
  { id: id('r1', 1), name: 'הובלות דרום', contact_name: 'משה', phone: '050-1112233', email: null, notes: null, is_active: true, deleted_at: null },
  { id: id('r1', 2), name: 'צוות הצפון', contact_name: 'יעל', phone: '052-4445566', email: null, notes: null, is_active: true, deleted_at: null },
]
const staffNames = ['דניאל כהן', 'נועה לוי', 'איתי מזרחי', 'שירה אברהם', 'יוסי פרץ', 'מיכל דוד', 'עומר ביטון']
export const staff = staffNames.map((n, i) => ({
  id: id('p1', i + 1), user_id: id('u1', i + 1), user_kind: 'staff', is_admin: false, full_name: n, phone: `050-70000${i}0`,
  email: null, customer_id: null, contractor_id: null, notes: null, is_active: true, deleted_at: null,
  staff_roles: [{ role: i % 3 === 0 ? 'driver' : i % 3 === 1 ? 'team_lead' : 'worker' }],
}))

const places = ['גני התערוכה, תל אביב', 'קיסריה, אמפיתיאטרון', 'נמל יפו', 'מלון דן, אילת', 'קיבוץ עין גדי', 'הרצליה פיתוח, המרינה', 'ירושלים, מרכז הקונגרסים', 'חיפה, בת גלים', 'ראשון לציון, היכל התרבות', 'באר שבע, פארק הנחלים']
const names = ['חתונת כהן־לוי', 'כנס הייטק שנתי', 'פסטיבל יין', 'ערב גאלה', 'בר מצווה משפחת דהן', 'תערוכת רהיטים', 'אירוע חברה', 'חתונת אברהם', 'יום כיף לעובדים', 'השקת מוצר', 'קונצרט פתוח', 'חנוכת משרדים']
const evStatuses = ['approved', 'new', 'approved', 'in_progress', 'approved', 'done', 'new', 'cancelled']

const pad = (n) => String(n).padStart(2, '0')
export const events = []
for (let i = 0; i < 46; i++) {
  const day = 1 + ((i * 7) % 30) - (i % 4 === 0 ? 0 : 0)
  const month = i < 40 ? 9 : 10
  const c = customers[i % customers.length]
  const s = S[evStatuses[i % evStatuses.length] + 'event']
  events.push({
    id: id('e1', i + 1), customer_id: c.id, end_client_name: names[i % names.length], event_number: `${1040 + i}`,
    event_date: `2026-${pad(month)}-${pad(Math.min(day, 30))}`, location_text: places[i % places.length],
    location_provider: null, location_place_id: null, location_lat: 32.08, location_lng: 34.78, location_notes: i % 3 === 0 ? 'כניסה דרך שער אחורי, חניה מוגבלת' : null,
    volume_m: 20 + (i % 6) * 12, truck_count: 1 + (i % 3), notes: i % 2 ? 'לתאם הגעה שעה לפני. איש קשר באתר: אבי.' : null,
    status_id: s.id, no_parking: i % 5 === 0, porterage: i % 4 === 1, supplier_pickup: i % 6 === 2,
    approved_at: s.code === 'approved' ? '2026-09-10T08:00:00Z' : null, approved_by: null, custom_fields: {},
    created_by: staff[0].id, deleted_at: null,
    customers: { name: c.name, color: c.color, performed_by_enabled: true, quote_enabled: true },
    statuses: { name: s.name, color: s.color, code: s.code },
  })
}
// כמה אירועים בימים צפופים, כדי שהלוח ייראה אמיתי
;[[9, 29], [9, 29], [9, 29], [9, 29], [9, 29], [9, 30], [9, 30], [10, 1]].forEach(([m, d], k) => {
  const e = events[k]; e.event_date = `2026-${pad(m)}-${pad(d)}`
})

const times = [['06:00', '08:00', '16:00'], ['07:30', '09:30', '13:00'], ['12:00', '14:00', '22:00'], ['05:30', '07:00', '11:30']]
const times2 = [['17:00', '18:30', '23:30'], ['15:00', '16:00', '21:00'], ['20:00', '21:00', '23:45']]
export const workBoard = []
events.forEach((e, i) => {
  if (e.statuses.code === 'cancelled') return
  ;[0, 1].forEach((k) => {
    const tt = taskTypes[k]
    const [w, a, b] = k === 0 ? times[i % times.length] : times2[i % times2.length]
    const stt = [S.assignedtask, S.plannedtask, S.drafttask][(i + k) % 3]
    const lead = staff[(i + k) % 3 === 0 ? 1 : 4]
    const assigned = (i + k) % 3 !== 1
    const wn = 3 + (i % 3)
    const crew = [staff[2], staff[3], staff[5], staff[6], staff[4]].slice(0, Math.max(0, wn - 2 - ((i + k) % 4 === 0 ? 1 : 0)))
    workBoard.push({
      id: id('w1', i * 2 + k + 1), event_id: e.id, customer_id: e.customer_id, customer_name: e.customers.name, customer_color: e.customers.color,
      end_client_name: e.end_client_name, event_number: e.event_number, location_text: e.location_text, volume_m: e.volume_m, event_truck_count: e.truck_count,
      task_type_id: tt.id, task_type_name: tt.name, task_type_code: tt.code, title: null,
      task_date: k === 0 ? e.event_date : e.event_date, warehouse_start_time: w, onsite_start_time: a, onsite_end_time: b,
      hours_count: 6 + (i % 4), worker_count: wn, execution_method_id: methods[0].id, execution_method_name: methods[0].name,
      truck_id: (i + k) % 7 === 3 ? null : trucks[(i + k) % 3].id, truck_name: (i + k) % 7 === 3 ? null : trucks[(i + k) % 3].name, truck_free_text: null, truck_ids: (i + k) % 7 === 3 ? [] : [trucks[(i + k) % 3].id], truck_list: (i + k) % 7 === 3 ? [] : [{ id: trucks[(i + k) % 3].id, name: trucks[(i + k) % 3].name }],
      event_is_cancelled: false, hidden_on_board: false, notes: i % 3 === 0 ? 'להביא ציוד הגנה לרצפה' : null,
      status_id: stt.id, status_name: stt.name, status_color: stt.color, status_is_terminal: false, status_code: stt.code,
      contractor_id: i % 5 === 0 ? contractors[0].id : null, contractor_name: i % 5 === 0 ? contractors[0].name : null, updated_at: '2026-09-20T10:00:00Z',
      team_lead_id: assigned ? lead.id : null, team_lead_name: assigned ? lead.full_name : null, team_lead_kind: assigned ? 'staff' : null,
      team_lead_work_site: assigned ? 'warehouse' : null, team_lead_drives: assigned ? false : null, team_lead_truck_name: null,
      workers: assigned ? crew.map((p) => ({ profile_id: p.id, name: p.full_name, work_site: 'field' })) : [],
      drivers: assigned ? [{ profile_id: staff[0].id, name: staff[0].full_name, truck_id: trucks[0].id, truck_name: trucks[0].name, work_site: 'warehouse' }] : [],
      contractor_worker_list: [], customer_worker_list: [], customer_self_performing: false,
      customer_price: 1800 + i * 40, price_is_manual: false, price_breakdown: null, contractor_price: i % 5 === 0 ? 1200 : null,
      contractor_price_per_worker: null, contractor_work_site: null, contractor_worker_count: null, contractor_list: [],
      travel_hours: 1, requires_team_lead: true, performed_by: 'viper', supplier_pickup: e.supplier_pickup, supplier_names: e.supplier_pickup ? ['ספק תאורה בע״מ'] : null,
    })
  })
})

export const me = {
  profile: { id: staff[0].id, full_name: 'מנהל מערכת (דמו)', user_kind: 'staff', is_admin: true, customer_id: null, contractor_id: null, customer_worker_id: null, phone: null, email: 'demo@example.com' },
  roles: [], app_roles: [{ id: 'r', key: 'admin', name_he: 'מנהל' }], customer: null, permissions: {}, capabilities: {},
  creatable_user_kinds: ['staff'], field_permissions: [], scopes: [], form_config: [], board_config: [],
}

export const TABLES = {
  customers, statuses, task_types: taskTypes, execution_methods: methods, trucks, contractors, profiles: staff, events,
  work_board_view: workBoard, event_contacts: [{ event_id: events[0].id, contact_name: 'אבי כהן', contact_phone: '050-1234567' }],
  event_suppliers: [], saved_filters: [],
  tasks: workBoard.map((w) => ({ id: w.id, event_id: w.event_id, task_date: w.task_date, onsite_start_time: w.onsite_start_time, hours_count: w.hours_count, worker_count: w.worker_count, execution_method_id: w.execution_method_id, performed_by: 'viper', task_types: { code: w.task_type_code }, task_pricing: [{ price: w.customer_price, is_manual: false }], deleted_at: null })),
}
export { TODAY }

// ── נוכחות ──
const iso = (d, hm) => `${d}T${hm}:00+03:00`
const entry = (n, pid, date, inT, outT, o = {}) => ({
  id: id('a1', n), profile_id: pid, work_date: date, seq: 1, shift_start: iso(date, '06:00'), shift_end: iso(date, '15:00'), planned_hours: 9,
  work_site: 'warehouse', task_ids: [], clock_in_at: iso(date, inT), clock_out_at: outT ? iso(date, outT) : null,
  clock_in_lat: null, clock_in_lng: null, clock_in_distance_m: 40, clock_out_distance_m: outT ? 55 : null,
  raw_clock_in_at: null, raw_clock_out_at: null, actual_hours: outT ? +(((+outT.slice(0, 2) * 60 + +outT.slice(3)) - (+inT.slice(0, 2) * 60 + +inT.slice(3))) / 60).toFixed(2) : null,
  source: 'clock', status: 'approved', reviewed_by: null, reviewed_at: null, flags: [], employee_note: null, manager_note: null,
  clock_in_place: 'מחסן מרכזי, פתח תקווה', clock_out_place: outT ? 'מחסן מרכזי, פתח תקווה' : null, edited_at: null,
  req_clock_in_at: null, req_clock_out_at: null, req_note: null, req_at: null, ...o,
})
const T = '2026-09-29'
const clockRules = { version: 1, merge_gap_minutes: 30, clock_enabled: true, requires_location: false, location_radius_m: 150, allow_early_clock_in: true, early_grace_minutes: 30, allow_clock_without_shift: false, max_accuracy_m: 100, auto_close_after_hours: 16, self_entry: { enabled: true, max_backdate_days: 7, max_hours: 16 } }
const openEntry = entry(1, staff[0].id, T, '06:04', null)
export const RPCS = {
  attendance_my_status: {
    open_entry: openEntry,
    shift: { profile_id: staff[0].id, work_date: T, seq: 1, shift_start: iso(T, '06:00'), shift_end: iso(T, '15:00'), planned_hours: 9, work_site: 'warehouse', task_ids: [], first_task_id: null, last_task_id: null, start_lat: null, start_lng: null, end_lat: null, end_lng: null, travel_hours: 1, label: 'חתונת כהן־לוי', customer_id: customers[0].id, customer_color: customers[0].color, warehouse_id: null, warehouse_name: 'מחסן מרכזי' },
    rules: clockRules, location_required: false, can_clock_in: false, clock_in_block: null, can_submit: true, can_request_correction: true,
    today: [openEntry],
    reports: [entry(2, staff[0].id, '2026-09-27', '07:00', '16:10', { source: 'manual', status: 'pending', employee_note: 'שכחתי להחתים בכניסה' })],
    corrections: [entry(3, staff[0].id, '2026-09-25', '06:20', '15:05', { req_clock_in_at: iso('2026-09-25', '06:00'), req_clock_out_at: iso('2026-09-25', '15:00'), req_note: 'הטלפון היה כבוי', req_at: iso('2026-09-25', '16:00') })],
  },
}
const pay = (h, o = {}) => ({ version: 1, paid_hours: h, worked_hours: h, base_hours: Math.min(h, 8), overtime_hours: Math.max(0, h - 8), topup_hours: 0, is_rest_day: false, hourly_rate: 42, total: Math.round(h * 42 + Math.max(0, h - 8) * 21), bonus: 0, lines: [], ...o })
const rrows = []
let rn = 10
staff.slice(0, 6).forEach((p, pi) => {
  ;['2026-09-27', '2026-09-28', '2026-09-29'].forEach((d, di) => {
    const inT = ['06:00', '06:12', '07:30', '05:55'][(pi + di) % 4]
    const outT = ['15:05', '16:40', '14:20', '17:30'][(pi * 2 + di) % 4]
    const e = entry(rn++, p.id, d, inT, outT)
    const st = (pi + di) % 5 === 0 ? 'pending' : (pi + di) % 7 === 0 ? 'rejected' : 'approved'
    const flags = (pi + di) % 4 === 1 ? ['late'] : (pi + di) % 6 === 2 ? ['far_from_site'] : []
    rrows.push({
      ...e, full_name: p.full_name, contractor_id: null, in_distance_m: e.clock_in_distance_m, out_distance_m: e.clock_out_distance_m,
      in_lat: null, in_lng: null, out_lat: null, out_lng: null, status: st, flags, work_place: 'מחסן מרכזי', end_work_site: 'field', end_work_place: 'גני התערוכה',
      overtime_enabled: true, bonus_note: null, correction: null, pay: pay(e.actual_hours),
    })
  })
})
const sum = (f) => rrows.reduce((a, r) => a + f(r), 0)
RPCS.attendance_report = {
  rows: rrows, can_see_pay: true,
  totals: { entries: rrows.length, pending: rrows.filter((r) => r.status === 'pending').length, pending_hours: 21.5, actual_hours: +sum((r) => r.actual_hours).toFixed(1), paid_hours: +sum((r) => r.pay.paid_hours).toFixed(1), overtime_hours: +sum((r) => r.pay.overtime_hours).toFixed(1), corrections: 1, bonus: 300, total: sum((r) => r.pay.total) },
}
TABLES.warehouses = [{ id: 'w', name: 'מחסן מרכזי', address: 'פתח תקווה', lat: 32.09, lng: 34.88, radius_m: 150, color: '#3563f0', notes: null, is_active: true, sort_order: 1, deleted_at: null }]
TABLES.worker_pay_settings = []
