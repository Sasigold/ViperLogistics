import { describe, expect, it } from 'vitest'
import {
  furnitureLines,
  furnitureSummary,
  furnitureSummaryText,
  logisticsQuantity,
} from './furniture'
import type { ViperflowOrderItem } from '../../types/domain'

const EVENT = '30000000-0000-0000-0000-000000000049'
const CONNECTION = '40000000-0000-0000-0000-000000000049'

let seq = 0

function item(over: Partial<ViperflowOrderItem> & { name: string }): ViperflowOrderItem {
  seq += 1
  return {
    id: `row-${seq}`,
    event_id: EVENT,
    connection_id: CONNECTION,
    external_item_id: `ext-${seq}`,
    parent_external_item_id: null,
    line_type: 'product',
    quantity: 1,
    spare_quantity: 0,
    is_component: false,
    component_type: null,
    is_custom: false,
    options: [],
    notes: null,
    position: seq,
    synced_at: '2026-09-16T08:00:00.000Z',
    ...over,
  }
}

/** ההזמנה כפי ש-ViperFlow שולח אותה: אב, הרכיבים שלו, ואז הלוגיסטיקה. */
function order(): ViperflowOrderItem[] {
  seq = 0
  const table = item({
    name: 'שולחן עגול 1.8',
    quantity: 10,
    spare_quantity: 2,
    options: [{ group: 'מפה', value: 'מפה לבנה' }],
  })
  const cloth = item({
    name: 'מפה לבנה',
    quantity: 10,
    is_component: true,
    component_type: 'choice_group',
    parent_external_item_id: table.external_item_id,
  })
  const chair = item({ name: 'כיסא נפוליאון', quantity: 100 })
  const custom = item({ name: 'עיצוב פרחים', quantity: 1, is_custom: true, notes: 'לבן בלבד' })
  const workers = item({ name: 'סידור ואיסוף', line_type: 'worker', quantity: 4 })
  const truck = item({ name: 'הובלה', line_type: 'truck', quantity: 2 })
  return [table, cloth, chair, custom, workers, truck]
}

describe('furnitureLines', () => {
  it('משאיר רק ריהוט — עובדים ומשאיות אינם שורות ברשימה', () => {
    const lines = furnitureLines(order())
    expect(lines.map((l) => l.name)).toEqual([
      'שולחן עגול 1.8',
      'כיסא נפוליאון',
      'עיצוב פרחים',
    ])
  })

  it('רכיב יושב מתחת לאב שלו ולא כשורה בפני עצמו', () => {
    const [table] = furnitureLines(order())
    expect(table.components).toHaveLength(1)
    expect(table.components[0].name).toBe('מפה לבנה')
    expect(table.components[0].quantity).toBe(10)
  })

  it('הבחירה של הפריט נקראת כטקסט, עם שם הקבוצה כשיש', () => {
    const [table] = furnitureLines(order())
    expect(table.options).toEqual(['מפה: מפה לבנה'])

    const [bare] = furnitureLines([
      item({ name: 'כיסא', options: [{ group: null, value: 'ריפוד שחור' }] }),
    ])
    expect(bare.options).toEqual(['ריפוד שחור'])
  })

  it('בחירה בלי ערך אינה מייצרת שורת תווית ריקה', () => {
    const [line] = furnitureLines([
      item({ name: 'כיסא', options: [{ group: 'ריפוד', value: '  ' }] }),
    ])
    expect(line.options).toEqual([])
  })

  it('רכיב שאיבד את האב שלו מוצג כשורה ואינו נעלם', () => {
    const orphan = item({
      name: 'מפה לבנה',
      is_component: true,
      parent_external_item_id: 'ext-לא-קיים',
    })
    const lines = furnitureLines([orphan])
    expect(lines.map((l) => l.name)).toEqual(['מפה לבנה'])
  })

  it('הסדר הוא הסדר ש-ViperFlow שלח, ולא סדר השורות שחזרו מהמסד', () => {
    const rows = order()
    const shuffled = [rows[3], rows[0], rows[2], rows[1]]
    expect(furnitureLines(shuffled).map((l) => l.name)).toEqual([
      'שולחן עגול 1.8',
      'כיסא נפוליאון',
      'עיצוב פרחים',
    ])
  })

  it('הכמות לספירה חוזרת מהאב, והספייר נשמר בנפרד', () => {
    const [table] = furnitureLines(order())
    expect(table.quantity).toBe(10)
    expect(table.spareQuantity).toBe(2)
  })
})

describe('logisticsQuantity', () => {
  it('מחזיר את הכמות שהוזמנה', () => {
    expect(logisticsQuantity(order(), 'truck')).toBe(2)
    expect(logisticsQuantity(order(), 'worker')).toBe(4)
  })

  it('אפס אינו הזמנה — כל הזמנה נושאת את שתי השורות גם כשהן ריקות', () => {
    const rows = [item({ name: 'הובלה', line_type: 'truck', quantity: 0 })]
    expect(logisticsQuantity(rows, 'truck')).toBeNull()
  })
})

describe('furnitureSummary', () => {
  it('סופר שורות, פריטים ולוגיסטיקה', () => {
    const summary = furnitureSummary(order())
    expect(summary).toEqual({ lines: 3, units: 111, workers: 4, trucks: 2 })
  })

  it('רשימה ריקה אינה נופלת', () => {
    expect(furnitureSummary([])).toEqual({ lines: 0, units: 0, workers: null, trucks: null })
  })

  it('הטקסט אומר ביחיד כשהמספר אחד', () => {
    expect(
      furnitureSummaryText({ lines: 1, units: 1, workers: 1, trucks: 1 }),
    ).toBe('שורה אחת · 1 פריטים · משאית אחת · עובד אחד')
  })

  it('לוגיסטיקה שלא הוזמנה אינה מופיעה בטקסט', () => {
    expect(
      furnitureSummaryText({ lines: 3, units: 111, workers: null, trucks: null }),
    ).toBe('3 שורות · 111 פריטים')
  })
})
