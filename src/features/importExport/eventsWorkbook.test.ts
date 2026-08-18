import { describe, expect, it } from 'vitest'
import {
  EVENT_COLUMNS,
  eventColumns,
  TASK_COLUMNS,
  buildImportPayload,
  buildSamplePlan,
  buildTemplatePlan,
  coerceValue,
  groupTasks,
  normalizeCell,
  parseEventSheet,
  parseSheet,
} from './eventsWorkbook'
import type { Matrix, SheetColumn, SheetRow } from './eventsWorkbook'
import type { FormField } from '../../types/domain'

const CUSTOMERS = [
  { id: 'cust-1', name: 'אירועי הצפון' },
  { id: 'cust-2', name: 'הפקות דרום' },
]

const headerRow = (cols: { header: string }[]) => cols.map((c) => c.header)

const eventsMatrix = (...rows: string[][]): Matrix => [headerRow(EVENT_COLUMNS), ...rows]
const tasksMatrix = (...rows: string[][]): Matrix => [headerRow(TASK_COLUMNS), ...rows]

/* השורות נבנות לפי מפתח ולא לפי מיקום: עמודה שתיווסף באמצע הגיליון לא תזיז
   כאן ערכים לעמודות שכנות בשקט. */
const cellsOf = (cols: SheetColumn[], values: SheetRow) => cols.map((c) => values[c.key] ?? '')

/** שורת אירוע לפי EVENT_COLUMNS */
const eventCells = (key: string, customer: string, date = '2026-03-15', extra: SheetRow = {}) =>
  cellsOf(EVENT_COLUMNS, {
    row_key: key, customer_name: customer, end_client_name: 'חתונה', event_number: '101',
    event_date: date, location_text: 'תל אביב', volume_m: '18', truck_count: '2',
    contact_name: 'דנה', contact_phone: '050-1111111', ...extra,
  })

/** שורת משימה לפי TASK_COLUMNS */
const taskCells = (key: string, type: string, date = '2026-03-15', extra: SheetRow = {}) =>
  cellsOf(TASK_COLUMNS, {
    row_key: key, task_type: type, task_date: date, warehouse_start_time: '06:00',
    onsite_start_time: '08:00', hours_count: '4', worker_count: '5', ...extra,
  })

describe('normalizeCell', () => {
  it('מחזיר מחרוזת מקוצצת לטקסט ולמספר', () => {
    expect(normalizeCell('  שלום  ')).toBe('שלום')
    expect(normalizeCell(18.5)).toBe('18.5')
    expect(normalizeCell(null)).toBe('')
    expect(normalizeCell(undefined)).toBe('')
  })

  it('תא תאריך של ExcelJS הופך ל-YYYY-MM-DD', () => {
    expect(normalizeCell(new Date(Date.UTC(2026, 2, 15)))).toBe('2026-03-15')
  })

  it('תא שעה יושב על בסיס 1899 ולכן מזוהה כשעה ולא כתאריך', () => {
    expect(normalizeCell(new Date(Date.UTC(1899, 11, 30, 8, 30)))).toBe('08:30')
  })

  it('חולץ טקסט מתא היפר-קישור, נוסחה ו-richText', () => {
    expect(normalizeCell({ text: 'רחוב הרצל 12', hyperlink: 'https://x' })).toBe('רחוב הרצל 12')
    expect(normalizeCell({ formula: 'A1', result: 7 })).toBe('7')
    expect(normalizeCell({ richText: [{ text: 'א' }, { text: 'ב' }] })).toBe('אב')
  })
})

describe('coerceValue', () => {
  it('מקבל תאריך גם בפורמט ישראלי', () => {
    expect(coerceValue('event_date', '15/03/2026')).toBe('2026-03-15')
    expect(coerceValue('task_date', '2026-3-5')).toBe('2026-03-05')
  })

  it('מרפד שעה חד-ספרתית ומתעלם מחלק התאריך', () => {
    expect(coerceValue('onsite_start_time', '8:05')).toBe('08:05')
    expect(coerceValue('warehouse_start_time', '2026-03-15 06:00')).toBe('06:00')
  })

  it('מנקה מטבע ומפרידי אלפים ממחיר', () => {
    expect(coerceValue('price', '1,200 ₪')).toBe('1200')
    expect(coerceValue('contractor_price', '₪900.50')).toBe('900.50')
    expect(coerceValue('travel_hours', '1.5')).toBe('1.5')
  })

  it('מה שאינו מספר חוזר כפי שהוא — השרת הוא שידווח על השורה', () => {
    expect(coerceValue('price', 'לפי סיכום')).toBe('לפי סיכום')
  })

  it('כן/לא הופכים ל-true/false, בעברית ובאנגלית', () => {
    expect(coerceValue('no_parking', 'כן')).toBe('true')
    expect(coerceValue('porterage', ' לא ')).toBe('false')
    expect(coerceValue('supplier_pickup', 'V')).toBe('true')
    expect(coerceValue('requires_team_lead', 'TRUE')).toBe('true')
    expect(coerceValue('requires_team_lead', '0')).toBe('false')
    expect(coerceValue('no_parking', 'אולי')).toBe('אולי')
  })
})

describe('parseSheet', () => {
  it('מדלג על שורות ריקות', () => {
    const rows = parseEventSheet(eventsMatrix(eventCells('1', 'אירועי הצפון'), ['', '', '', '']))
    expect(rows).toHaveLength(1)
    expect(rows[0].customer_name).toBe('אירועי הצפון')
  })

  it('סדר העמודות אינו קובע — המיפוי הוא לפי הכותרת', () => {
    const shuffled = [...EVENT_COLUMNS].reverse()
    const matrix: Matrix = [
      headerRow(shuffled),
      shuffled.map((c) => (c.key === 'customer_name' ? 'הפקות דרום' : c.key === 'event_date' ? '2026-04-01' : '')),
    ]
    const rows = parseEventSheet(matrix)
    expect(rows[0].customer_name).toBe('הפקות דרום')
    expect(rows[0].event_date).toBe('2026-04-01')
  })

  it('עמודה לא מוכרת אינה מפילה את הפרסור', () => {
    const matrix: Matrix = [
      [...headerRow(EVENT_COLUMNS), 'עמודה שהמשתמש הוסיף'],
      [...eventCells('1', 'אירועי הצפון'), 'בלה בלה'],
    ]
    expect(parseEventSheet(matrix)[0].customer_name).toBe('אירועי הצפון')
  })

  it('קובץ ישן בן גיליון אחד — בלי עמודת מזהה שורה — נקלט כמו קודם', () => {
    const legacyHeaders = [
      'שם לקוח במערכת', 'שם לקוח האירוע', 'מספר אירוע', 'תאריך אירוע (YYYY-MM-DD)',
      'מיקום', 'הערות למיקום', 'נפח במטר', 'כמות משאיות', 'איש קשר', 'טלפון איש קשר', 'הערות',
    ]
    const rows = parseEventSheet([
      legacyHeaders,
      ['אירועי הצפון', 'חתונה', '101', '2026-03-15', 'תל אביב', '', '18', '2', 'דנה', '050-1111111', ''],
    ])
    expect(rows[0].customer_name).toBe('אירועי הצפון')
    expect(rows[0].event_date).toBe('2026-03-15')
    expect(rows[0].row_key).toBeUndefined()
  })

  it('קובץ בלי שורת כותרות מובנת נקרא לפי מיקום', () => {
    const rows = parseSheet([['a', 'b', 'c'], ['1', 'אירועי הצפון', 'חתונה']], EVENT_COLUMNS)
    expect(rows[0].row_key).toBe('1')
    expect(rows[0].customer_name).toBe('אירועי הצפון')
  })
})

describe('groupTasks', () => {
  const events = parseEventSheet(
    eventsMatrix(eventCells('1', 'אירועי הצפון'), eventCells('2', 'הפקות דרום')),
  )

  it('מקבץ משימות לפי מזהה השורה', () => {
    const tasks = parseSheet(tasksMatrix(taskCells('1', 'הקמה'), taskCells('1', 'פירוק'), taskCells('2', 'הקמה')), TASK_COLUMNS)
    const { tasksByKey, errors } = groupTasks(events, tasks)
    expect(errors).toEqual([])
    expect(tasksByKey.get('1')).toHaveLength(2)
    expect(tasksByKey.get('2')).toHaveLength(1)
  })

  it('מזהה שורה כפול בגיליון האירועים הוא שגיאה', () => {
    const dupes = parseEventSheet(eventsMatrix(eventCells('1', 'אירועי הצפון'), eventCells('1', 'הפקות דרום')))
    expect(groupTasks(dupes, []).errors).toEqual(['מזהה שורה כפול בגיליון האירועים: 1'])
  })

  it('משימה שמפנה למזהה שאינו קיים היא שגיאה', () => {
    const tasks = parseSheet(tasksMatrix(taskCells('9', 'הקמה')), TASK_COLUMNS)
    expect(groupTasks(events, tasks).errors).toEqual([
      'משימה מפנה למזהה שורה שאינו קיים בגיליון האירועים: 9',
    ])
  })

  it('משימה בלי סוג היא שגיאה', () => {
    const tasks = parseSheet(tasksMatrix(taskCells('1', '')), TASK_COLUMNS)
    expect(groupTasks(events, tasks).errors).toEqual(['שורת משימה במזהה 1 בלי סוג משימה'])
  })

  it('כשיש אירוע יחיד, משימה בלי מזהה משויכת אליו', () => {
    const single = parseEventSheet(eventsMatrix(eventCells('', 'אירועי הצפון')))
    const tasks = parseSheet(tasksMatrix(taskCells('', 'הקמה')), TASK_COLUMNS)
    const { tasksByKey, errors } = groupTasks(single, tasks)
    expect(errors).toEqual([])
    expect(tasksByKey.get('')).toHaveLength(1)
  })

  it('כששני אירועים ומעלה, משימה בלי מזהה היא שגיאה', () => {
    const tasks = parseSheet(tasksMatrix(taskCells('', 'הקמה')), TASK_COLUMNS)
    expect(groupTasks(events, tasks).errors).toEqual(['שורת משימה "הקמה" בלי מזהה שורה'])
  })
})

describe('buildImportPayload', () => {
  const events = parseEventSheet(
    eventsMatrix(eventCells('1', 'אירועי הצפון'), eventCells('2', 'הפקות דרום')),
  )
  const tasks = parseSheet(
    tasksMatrix(taskCells('1', 'הקמה'), taskCells('1', 'סידור'), taskCells('2', 'פירוק')),
    TASK_COLUMNS,
  )

  it('מייצר payload לכל אירוע עם המשימות שלו', () => {
    const { tasksByKey } = groupTasks(events, tasks)
    const { payloads, unknownCustomers, taskCount } = buildImportPayload(events, tasksByKey, CUSTOMERS)

    expect(unknownCustomers).toEqual([])
    expect(taskCount).toBe(3)
    expect(payloads).toHaveLength(2)
    expect(payloads[0].customer_id).toBe('cust-1')
    expect(payloads[0].event_date).toBe('2026-03-15')
    expect(payloads[0].tasks.map((t) => t.task_type)).toEqual(['הקמה', 'סידור'])
    expect(payloads[1].tasks.map((t) => t.task_type)).toEqual(['פירוק'])
  })

  it('לא נשלחים מפתחות פנימיים ולא ערכים ריקים', () => {
    const { tasksByKey } = groupTasks(events, tasks)
    const { payloads } = buildImportPayload(events, tasksByKey, CUSTOMERS)
    expect(payloads[0]).not.toHaveProperty('row_key')
    expect(payloads[0]).not.toHaveProperty('customer_name')
    // location_notes היה ריק בשורה
    expect(payloads[0]).not.toHaveProperty('location_notes')
    expect(payloads[0].tasks[0]).not.toHaveProperty('execution_method')
  })

  it('תאריך משימה ריק לא נשלח — השרת ייקח את תאריך האירוע', () => {
    const noDate = parseSheet(
      tasksMatrix(taskCells('1', 'הקמה', '', { warehouse_start_time: '' })),
      TASK_COLUMNS,
    )
    const { tasksByKey } = groupTasks(events, noDate)
    const { payloads } = buildImportPayload(events, tasksByKey, CUSTOMERS)
    expect(payloads[0].tasks[0]).not.toHaveProperty('task_date')
    expect(payloads[0].tasks[0].onsite_start_time).toBe('08:00')
  })

  it('עמודות התוספות והספקים נוסעות עם שורת האירוע', () => {
    const withAddons = parseEventSheet(
      eventsMatrix(
        eventCells('1', 'אירועי הצפון', '2026-03-15', {
          no_parking: 'כן', porterage: 'לא', suppliers: 'ספק א, ספק ב',
        }),
      ),
    )
    const { payloads } = buildImportPayload(withAddons, new Map(), CUSTOMERS)
    expect(payloads[0].no_parking).toBe('true')
    expect(payloads[0].porterage).toBe('false')
    expect(payloads[0].suppliers).toBe('ספק א, ספק ב')
    // תא ריק אינו "לא" — הוא פשוט אינו נשלח
    expect(payloads[0]).not.toHaveProperty('supplier_pickup')
  })

  it('עמודות הכסף והשיוך נוסעות עם שורת המשימה', () => {
    const money = parseSheet(
      tasksMatrix(
        taskCells('1', 'הקמה', '2026-03-15', {
          warehouse: 'מחסן ראשי', travel_hours: '1', requires_team_lead: 'כן',
          price: '2,400 ₪', contractor: 'קבלן הדרום', contractor_price: '900',
        }),
      ),
      TASK_COLUMNS,
    )
    const { tasksByKey } = groupTasks(events, money)
    const { payloads } = buildImportPayload(events, tasksByKey, CUSTOMERS)
    expect(payloads[0].tasks[0]).toMatchObject({
      task_type: 'הקמה',
      warehouse: 'מחסן ראשי',
      travel_hours: '1',
      requires_team_lead: 'true',
      price: '2400',
      contractor: 'קבלן הדרום',
      contractor_price: '900',
    })
  })

  it('שם לקוח לא מוכר מדווח בשמו ולא כ"חסר"', () => {
    const rows: SheetRow[] = [{ row_key: '1', customer_name: 'לקוח שלא קיים', event_date: '2026-03-15' }]
    const { payloads, unknownCustomers } = buildImportPayload(rows, new Map(), CUSTOMERS)
    expect(payloads).toEqual([])
    expect(unknownCustomers).toEqual(['לקוח שלא קיים'])
  })

  it('התאמת שם לקוח מתעלמת מרישיות ומרווחים', () => {
    const rows: SheetRow[] = [{ row_key: '1', customer_name: '  אירועי הצפון ', event_date: '2026-03-15' }]
    const { payloads } = buildImportPayload(rows, new Map(), CUSTOMERS)
    expect(payloads[0].customer_id).toBe('cust-1')
  })
})

describe('שדות מותאמים', () => {
  const field = (field_key: string, label_he: string, field_type: FormField['field_type']): FormField => ({
    field_key, label_he, field_type, sort_order: 10, customer_id: 'cust-1', options: [], deleted_at: null,
  })

  it('תיבת סימון מותאמת נקראת ל-true/false ולא נשארת "כן"', () => {
    const cols = eventColumns([field('cf_vip', 'אירוע VIP', 'checkbox'), field('cf_qty', 'כמות כיסאות', 'number')])
    const rows = parseEventSheet(
      [cols.map((c) => c.header), cellsOf(cols, { customer_name: 'אירועי הצפון', cf_vip: 'כן', cf_qty: '1,200' })],
      cols,
    )
    // app.event_custom_patch ממירה ב-::boolean וב-::numeric, ואלה הערכים שהיא מקבלת
    expect(rows[0].cf_vip).toBe('true')
    expect(rows[0].cf_qty).toBe('1200')
  })
})

describe('תבנית וקובץ דוגמה', () => {
  it('התבנית היא שני גיליונות ריקים עם הכותרות', () => {
    const plan = buildTemplatePlan()
    expect(plan.map((s) => s.name)).toEqual(['אירועים', 'משימות'])
    expect(plan.every((s) => s.rows.length === 0)).toBe(true)
    expect(plan[0].columns[0].key).toBe('row_key')
  })

  const REFS = {
    customers: ['אירועי הצפון', 'הפקות דרום'],
    taskTypes: ['הקמה', 'פירוק', 'סידור'],
    executionMethods: ['הובלה בלבד'],
    contractors: ['קבלן הדרום'],
    warehouses: ['מחסן ראשי'],
    suppliers: [{ customer: 'אירועי הצפון', name: 'ספק הבמות' }],
  }

  it('קובץ הדוגמה מכיל אירועים, משימות וגיליון הסבר', () => {
    const plan = buildSamplePlan(REFS)
    expect(plan.map((s) => s.name)).toEqual(['אירועים', 'משימות', 'הסבר'])
    expect(plan[0].rows.length).toBeGreaterThan(0)
    expect(plan[1].rows.length).toBeGreaterThan(0)
    expect(plan[2].intro?.length).toBeGreaterThan(0)
    expect(plan[2].rows.map((r) => r.value)).toContain('הובלה בלבד')
  })

  it('גיליון ההסבר מונה גם מחסנים, קבלנים וספקים — עם הלקוח של הספק', () => {
    const guide = buildSamplePlan(REFS)[2]
    expect(guide.rows).toContainEqual({ kind: 'מחסן יציאה', value: 'מחסן ראשי' })
    expect(guide.rows).toContainEqual({ kind: 'קבלן', value: 'קבלן הדרום' })
    expect(guide.rows).toContainEqual({ kind: 'ספק של אירועי הצפון', value: 'ספק הבמות' })
  })

  it('שורות הדוגמה נושאות מחירים, תוספות ושיוך לקבלן', () => {
    const [eventsSheet, tasksSheet] = buildSamplePlan(REFS)
    expect(eventsSheet.rows[0].no_parking).toBe('כן')
    expect(eventsSheet.rows[0].suppliers).toBe('ספק הבמות')
    // ספק של לקוח אחר לא יימצא, ולכן התא נשאר ריק ולא ייפול בייבוא
    expect(eventsSheet.rows[1].suppliers).toBe('')
    expect(tasksSheet.rows[0].price).toBe('2400')
    const delegated = tasksSheet.rows.find((r) => r.contractor)
    expect(delegated?.contractor).toBe('קבלן הדרום')
    expect(delegated?.contractor_price).toBe('900')
  })

  it('מה שאסור למוריד יורד מהדוגמה, כדי שהקובץ ייקלט כפי שהוא', () => {
    const tasksSheet = buildSamplePlan({
      ...REFS,
      allow: { price: false, contractor: false, contractorPrice: false },
    })[1]
    expect(tasksSheet.rows.every((r) => r.price === '')).toBe(true)
    expect(tasksSheet.rows.every((r) => r.contractor === '')).toBe(true)
    expect(tasksSheet.rows.every((r) => r.contractor_price === '')).toBe(true)
  })

  it('בלי קבלן במערכת אין גם מחיר לקבלן — הצירוף הזה נפסל בשרת', () => {
    const tasksSheet = buildSamplePlan({ ...REFS, contractors: [] })[1]
    expect(tasksSheet.rows.every((r) => r.contractor === '' && r.contractor_price === '')).toBe(true)
  })

  it('כל משימה בדוגמה מצביעה על אירוע שקיים בגיליון האירועים', () => {
    const plan = buildSamplePlan({ customers: [], taskTypes: [], executionMethods: [] })
    const keys = new Set(plan[0].rows.map((r) => r.row_key))
    expect(plan[1].rows.every((r) => keys.has(r.row_key))).toBe(true)
  })

  it('הדוגמה עוברת את אותו מסלול פרסור שהייבוא עובר', () => {
    const plan = buildSamplePlan({
      customers: ['אירועי הצפון'],
      taskTypes: ['הקמה', 'פירוק', 'סידור'],
      executionMethods: [],
    })
    const toMatrix = (i: number): Matrix => [
      plan[i].columns.map((c) => c.header),
      ...plan[i].rows.map((r) => plan[i].columns.map((c) => r[c.key] ?? '')),
    ]
    const events = parseEventSheet(toMatrix(0))
    const tasks = parseSheet(toMatrix(1), TASK_COLUMNS)
    const { tasksByKey, errors } = groupTasks(events, tasks)
    expect(errors).toEqual([])
    // שני האירועים בדוגמה נופלים על אותו לקוח כשיש רק אחד במערכת
    const { payloads, unknownCustomers, taskCount } = buildImportPayload(events, tasksByKey, [CUSTOMERS[0]])
    expect(unknownCustomers).toEqual([])
    expect(payloads).toHaveLength(2)
    expect(taskCount).toBe(5)
  })
})
