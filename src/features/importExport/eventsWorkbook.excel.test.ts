import { describe, expect, it } from 'vitest'
import ExcelJS from 'exceljs'
import {
  TASK_COLUMNS,
  buildImportPayload,
  buildSamplePlan,
  groupTasks,
  normalizeCell,
  parseEventSheet,
  parseSheet,
} from './eventsWorkbook'
import type { Matrix, SheetPlan } from './eventsWorkbook'

async function write(plans: SheetPlan[]): Promise<ExcelJS.Buffer> {
  const wb = new ExcelJS.Workbook()
  for (const plan of plans) {
    const ws = wb.addWorksheet(plan.name, { views: [{ rightToLeft: true }] })
    if (plan.intro?.length) {
      for (const line of plan.intro) ws.addRow([line])
      ws.addRow([])
    }
    ws.addRow(plan.columns.map((c) => c.header)).font = { bold: true }
    for (const r of plan.rows) ws.addRow(plan.columns.map((c) => r[c.key] ?? ''))
  }
  return wb.xlsx.writeBuffer()
}

function toMatrix(ws: ExcelJS.Worksheet | undefined): Matrix {
  if (!ws) return []
  const m: Matrix = []
  ws.eachRow((row) => {
    m.push((row.values as ExcelJS.CellValue[]).slice(1).map(normalizeCell))
  })
  return m
}

describe('round-trip דרך ExcelJS אמיתי', () => {
  it('קובץ הדוגמה שנכתב נקרא בחזרה ומייצר payload שלם', async () => {
    const buf = await write(
      buildSamplePlan({
        customers: ['אירועי הצפון'],
        taskTypes: ['הקמה', 'פירוק', 'סידור'],
        executionMethods: ['הובלה בלבד'],
        contractors: ['קבלן הדרום'],
        warehouses: ['מחסן ראשי'],
        suppliers: [{ customer: 'אירועי הצפון', name: 'ספק הבמות' }],
      }),
    )

    const wb = new ExcelJS.Workbook()
    await wb.xlsx.load(buf as ArrayBuffer)

    const events = parseEventSheet(toMatrix(wb.getWorksheet('אירועים')))
    const tasks = parseSheet(toMatrix(wb.getWorksheet('משימות')), TASK_COLUMNS)
    const { tasksByKey, errors } = groupTasks(events, tasks)
    expect(errors).toEqual([])

    const { payloads, unknownCustomers, taskCount } = buildImportPayload(events, tasksByKey, [
      { id: 'c1', name: 'אירועי הצפון' },
    ])
    expect(unknownCustomers).toEqual([])
    expect(payloads).toHaveLength(2)
    expect(taskCount).toBe(5)
    expect(payloads[0].event_date).toBe('2026-03-15')
    expect(payloads[0].contact_phone).toBe('050-1234567')
    // התוספות והספקים חוזרים כפי שהשרת מצפה לקבל אותם
    expect(payloads[0].no_parking).toBe('true')
    expect(payloads[0].supplier_pickup).toBe('false')
    expect(payloads[0].suppliers).toBe('ספק הבמות')
    expect(payloads[0].tasks[0]).toMatchObject({
      task_type: 'הקמה',
      warehouse_start_time: '06:00',
      onsite_start_time: '08:00',
      hours_count: '4',
      worker_count: '5',
      warehouse: 'מחסן ראשי',
      travel_hours: '1',
      requires_team_lead: 'true',
      price: '2400',
    })
    const delegated = payloads[0].tasks.find((t) => t.contractor)
    expect(delegated).toMatchObject({ contractor: 'קבלן הדרום', contractor_price: '900' })
    // גיליון ההסבר קיים ואינו מפריע לפרסור
    expect(wb.getWorksheet('הסבר')).toBeTruthy()
  })

  it('תא מחיר שעוצב כמטבע ותא כן/לא נקראים נכון', async () => {
    const wb = new ExcelJS.Workbook()
    const ws = wb.addWorksheet('משימות')
    ws.addRow(TASK_COLUMNS.map((c) => c.header))
    const cells: Record<string, string> = {
      row_key: '1', task_type: 'הקמה', price: '2400', requires_team_lead: 'כן',
    }
    const row = ws.addRow(TASK_COLUMNS.map((c) => cells[c.key] ?? ''))
    const priceCell = row.getCell(TASK_COLUMNS.findIndex((c) => c.key === 'price') + 1)
    priceCell.value = 2400
    priceCell.numFmt = '#,##0.00 ₪'

    const wb2 = new ExcelJS.Workbook()
    await wb2.xlsx.load((await wb.xlsx.writeBuffer()) as ArrayBuffer)
    expect(parseSheet(toMatrix(wb2.getWorksheet('משימות')), TASK_COLUMNS)[0]).toMatchObject({
      price: '2400',
      requires_team_lead: 'true',
    })
  })

  it('תאי תאריך ושעה אמיתיים של Excel (Date, לא טקסט) נקראים נכון', async () => {
    const wb = new ExcelJS.Workbook()
    const ws = wb.addWorksheet('משימות')
    ws.addRow(TASK_COLUMNS.map((c) => c.header))
    const cells: Record<string, string> = { row_key: '1', task_type: 'הקמה', hours_count: '4', worker_count: '5' }
    const row = ws.addRow(TASK_COLUMNS.map((c) => cells[c.key] ?? ''))
    const at = (key: string) => row.getCell(TASK_COLUMNS.findIndex((c) => c.key === key) + 1)
    at('task_date').value = new Date(Date.UTC(2026, 2, 15))
    at('warehouse_start_time').value = new Date(Date.UTC(1899, 11, 30, 6, 0))
    at('onsite_start_time').value = new Date(Date.UTC(1899, 11, 30, 8, 30))

    const wb2 = new ExcelJS.Workbook()
    await wb2.xlsx.load((await wb.xlsx.writeBuffer()) as ArrayBuffer)
    const parsed = parseSheet(toMatrix(wb2.getWorksheet('משימות')), TASK_COLUMNS)
    expect(parsed[0]).toMatchObject({
      task_date: '2026-03-15',
      warehouse_start_time: '06:00',
      onsite_start_time: '08:30',
    })
  })
})
