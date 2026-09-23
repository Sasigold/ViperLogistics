import { describe, expect, it } from 'vitest'
import { applyPatch, eventTones, groupByDay } from './warehouseSchedule'
import type { WarehouseScheduleRow } from '../../types/domain'

const row = (over: Partial<WarehouseScheduleRow>): WarehouseScheduleRow => ({
  event_id: 'e1',
  kind: 'prep',
  customer_id: 'c1',
  customer_name: 'ארקו',
  customer_color: '#000',
  event_number: '26000311',
  end_client_name: 'איבנטיב',
  event_date: '2026-10-02',
  task_date: '2026-10-01',
  date_is_manual: false,
  start_time: null,
  duration_hours: 0,
  notes: null,
  final_approved: false,
  event_ready: false,
  checked: false,
  updated_at: null,
  ...over,
})

describe('groupByDay', () => {
  it('ימים לפי הסדר, ובתוך היום — לפי השעה, ובלי שעה בסוף', () => {
    const days = groupByDay([
      row({ event_id: 'b', task_date: '2026-10-02', start_time: '23:55:00', kind: 'return' }),
      row({ event_id: 'a', task_date: '2026-10-02', start_time: null }),
      row({ event_id: 'c', task_date: '2026-10-01', start_time: '05:55:00' }),
      row({ event_id: 'd', task_date: '2026-10-02', start_time: '05:55:00' }),
    ])
    expect(days.map((d) => d.date)).toEqual(['2026-10-01', '2026-10-02'])
    expect(days[1].rows.map((r) => r.event_id)).toEqual(['d', 'b', 'a'])
  })

  it('באותה שעה — הכנה לפני החזרה', () => {
    const [day] = groupByDay([
      row({ event_id: 'x', kind: 'return', start_time: '08:00:00' }),
      row({ event_id: 'y', kind: 'prep', start_time: '08:00:00' }),
    ])
    expect(day.rows.map((r) => r.kind)).toEqual(['prep', 'return'])
  })
})

describe('eventTones', () => {
  it('ההכנה וההחזרה של אותו אירוע באותו גוון, ואירוע אחר בגוון אחר', () => {
    const tones = eventTones([row({ event_id: 'a' }), row({ event_id: 'b' }), row({ event_id: 'a', kind: 'return' })])
    expect(tones.size).toBe(2)
    expect(tones.get('a')).not.toBe(tones.get('b'))
  })
})

describe('applyPatch', () => {
  it('מעדכן את השדה ואינו נוגע בשאר', () => {
    const next = applyPatch(row({ notes: 'x' }), { checked: true })
    expect(next.checked).toBe(true)
    expect(next.notes).toBe('x')
  })

  it('יום שנקבע ביד מסומן ככזה', () => {
    const next = applyPatch(row({}), { task_date: '2026-09-30' })
    expect(next).toMatchObject({ task_date: '2026-09-30', date_is_manual: true })
  })

  it('ניקוי היום משאיר את התאריך הנוכחי עד שהשרת יחזיר את הנגזר', () => {
    const next = applyPatch(row({ task_date: '2026-09-30', date_is_manual: true }), { task_date: null })
    expect(next).toMatchObject({ task_date: '2026-09-30', date_is_manual: false })
  })
})
