import { describe, expect, it } from 'vitest'
import {
  furnitureSummaryText,
  specFromItems,
  specLinesFromItems,
  specSummary,
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

describe('specLinesFromItems', () => {
  it('משאיר רק ריהוט — עובדים ומשאיות אינם שורות ברשימה', () => {
    expect(specLinesFromItems(order()).map((l) => l.name)).toEqual([
      'שולחן עגול 1.8',
      'כיסא נפוליאון',
      'עיצוב פרחים',
    ])
  })

  /* ‏0187: כמו בתעודת משלוח — רכיב אינו שורה. */
  it('בן אינו שורה, וגם לא בן שאיבד את האב שלו', () => {
    const orphan = item({
      name: 'מפה לבנה',
      is_component: true,
      parent_external_item_id: 'ext-לא-קיים',
    })
    expect(specLinesFromItems([orphan])).toEqual([])
  })

  it('הבחירה של הפריט נקראת כטקסט, עם שם הקבוצה כשיש', () => {
    const [table] = specLinesFromItems(order())
    expect(table.options).toEqual(['מפה: מפה לבנה'])

    const [bare] = specLinesFromItems([
      item({ name: 'כיסא', options: [{ group: null, value: 'ריפוד שחור' }] }),
    ])
    expect(bare.options).toEqual(['ריפוד שחור'])
  })

  it('בחירה בלי ערך אינה מייצרת שורת תווית ריקה', () => {
    const [line] = specLinesFromItems([
      item({ name: 'כיסא', options: [{ group: 'ריפוד', value: '  ' }] }),
    ])
    expect(line.options).toEqual([])
  })

  it('הסדר הוא הסדר ש-ViperFlow שלח, ולא סדר השורות שחזרו מהמסד', () => {
    const rows = order()
    const shuffled = [rows[3], rows[0], rows[2], rows[1]]
    expect(specLinesFromItems(shuffled).map((l) => l.name)).toEqual([
      'שולחן עגול 1.8',
      'כיסא נפוליאון',
      'עיצוב פרחים',
    ])
  })

  it('הכמות לספירה חוזרת מהאב, והספייר נשמר בנפרד', () => {
    const [table] = specLinesFromItems(order())
    expect(table.quantity).toBe(10)
    expect(table.spare_quantity).toBe(2)
  })

  it('ולשורה שמורה אין תמונה — היא אינה נשמרת אצלנו', () => {
    expect(specLinesFromItems(order()).every((l) => l.image_url === null)).toBe(true)
  })
})

describe('specFromItems', () => {
  /* ‏0193: הכמויות מגיעות מה-view ולא נספרות כאן. ה-view סופר לפי רשימת
     השמות של החיבור — בדיוק כמו המתרגם — ולכן שורת פיקוח ("‏9 עובדים")
     ושורת "תוספת" שבאותה הזמנה אינן משנות את המספרים האלה. */
  it('מרכיב מפרט שלם ממה ששמור, והכמויות מהקישור', () => {
    const spec = specFromItems(
      [...order(), item({ name: 'פיקוח', line_type: 'worker', quantity: 9 })],
      {
        order_number: 'ORD-49-0001',
        last_synced_at: '2026-09-16T08:00:00.000Z',
        truck_quantity: 2,
        worker_quantity: 4,
      },
    )
    expect(spec.order_number).toBe('ORD-49-0001')
    expect(spec.trucks).toBe(2)
    expect(spec.workers).toBe(4)
    expect(spec.lines).toHaveLength(3)
  })

  it('קישור בלי כמויות אינו ממציא אותן', () => {
    const spec = specFromItems(order(), {
      order_number: 'ORD-49-0001',
      last_synced_at: null,
    })
    expect(spec.trucks).toBeNull()
    expect(spec.workers).toBeNull()
  })

  it('בלי קישור — מפרט בלי מספר הזמנה, ולא נפילה', () => {
    expect(specFromItems([], null).lines).toEqual([])
  })
})

describe('specSummary', () => {
  it('סופר שורות, פריטים ולוגיסטיקה', () => {
    expect(
      specSummary(
        specFromItems(order(), {
          order_number: null,
          last_synced_at: null,
          truck_quantity: 2,
          worker_quantity: 4,
        }),
      ),
    ).toEqual({
      lines: 3,
      units: 111,
      workers: 4,
      trucks: 2,
    })
  })

  it('רשימה ריקה אינה נופלת', () => {
    expect(specSummary(specFromItems([]))).toEqual({
      lines: 0,
      units: 0,
      workers: null,
      trucks: null,
    })
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
