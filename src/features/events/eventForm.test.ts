import { describe, expect, it } from 'vitest'
import {
  draftFormValues,
  emptyEventForm,
  eventFormValues,
  incomeValuesFromRows,
  sectionValuesFromTasks,
} from './eventForm'
import type { EventAutoTask, EventRow } from '../../types/domain'

const EVENT = '30000000-0000-0000-0000-000000000016'
const CUSTOMER = '10000000-0000-0000-0000-000000000001'

function ev(over: Partial<EventRow> = {}): EventRow {
  return {
    id: EVENT,
    customer_id: CUSTOMER,
    end_client_name: null,
    event_number: null,
    event_date: '2026-09-01',
    location_text: null,
    location_provider: null,
    location_place_id: null,
    location_lat: null,
    location_lng: null,
    location_notes: null,
    volume_m: null,
    truck_count: null,
    notes: null,
    status_id: null,
    no_parking: false,
    porterage: false,
    supplier_pickup: false,
    custom_fields: null,
    ...over,
  } as unknown as EventRow
}

function task(over: Partial<EventAutoTask> & { code: 'setup' | 'teardown' }): EventAutoTask {
  const { code, ...rest } = over
  return {
    id: `task-${code}`,
    task_date: '2026-09-01',
    onsite_start_time: null,
    hours_count: null,
    worker_count: 0,
    execution_method_id: null,
    price: null,
    task_types: { code },
    ...rest,
  }
}

describe('eventFormValues', () => {
  it('turns every null column into an empty field', () => {
    const f = eventFormValues(ev())
    expect(f.end_client_name).toBe('')
    expect(f.event_number).toBe('')
    expect(f.location_text).toBe('')
    expect(f.notes).toBe('')
    expect(f.status_id).toBe('')
  })

  /** הטופס מחזיק מחרוזות: `<input type="number">` מחזיר מחרוזת ממילא. */
  it('stringifies the numeric columns, and leaves the coordinates as numbers', () => {
    const f = eventFormValues(ev({ volume_m: 12.5, truck_count: 3, location_lat: 32.1, location_lng: 34.8 }))
    expect(f.volume_m).toBe('12.5')
    expect(f.truck_count).toBe('3')
    expect(f.location_lat).toBe(32.1)
    expect(f.location_lng).toBe(34.8)
  })

  it('reads the contact from the second table, and survives its absence', () => {
    expect(eventFormValues(ev(), null).contact_name).toBe('')
    expect(eventFormValues(ev(), undefined).contact_phone).toBe('')
    const f = eventFormValues(ev(), { contact_name: 'דנה', contact_phone: null })
    expect(f.contact_name).toBe('דנה')
    expect(f.contact_phone).toBe('')
  })

  it('takes the suppliers as given, and an empty list when there are none', () => {
    expect(eventFormValues(ev()).supplier_ids).toEqual([])
    expect(eventFormValues(ev(), null, ['a', 'b']).supplier_ids).toEqual(['a', 'b'])
  })

  it('maps the customer fields through the same converter the inputs use', () => {
    const f = eventFormValues(ev({ custom_fields: { hall: 'אולם ב', floors: 3, lift: true } }))
    expect(f.custom).toEqual({ hall: 'אולם ב', floors: '3', lift: true })
  })

  /** התאריכים האלה אינם על האירוע אלא על המשימות; זה placeholder עד שהן מגיעות. */
  it('pre-fills the two section dates from the event date, and nothing else', () => {
    const f = eventFormValues(ev({ event_date: '2026-09-01' }))
    expect(f.setup_date).toBe('2026-09-01')
    expect(f.teardown_date).toBe('2026-09-01')
    expect(f.setup_time).toBe('')
    expect(f.setup_worker_count).toBe('')
    expect(f.teardown_price).toBe('')
  })

  /** זה מה שמבטיח שפתיחת אירוע ב' לא יורשת שדה מאירוע א'. */
  it('returns a whole form and never a patch', () => {
    expect(Object.keys(eventFormValues(ev())).sort()).toEqual(Object.keys(emptyEventForm).sort())
  })
})

describe('sectionValuesFromTasks', () => {
  it('reads each task by its type and not by the order the server returned', () => {
    const patch = sectionValuesFromTasks([
      task({ code: 'teardown', task_date: '2026-09-03', execution_method_id: 'm2' }),
      task({ code: 'setup', task_date: '2026-09-01', execution_method_id: 'm1' }),
    ])
    expect(patch.setup_date).toBe('2026-09-01')
    expect(patch.setup_execution_method).toBe('m1')
    expect(patch.teardown_date).toBe('2026-09-03')
    expect(patch.teardown_execution_method).toBe('m2')
  })

  it('cuts the seconds off the on-site time', () => {
    expect(sectionValuesFromTasks([task({ code: 'setup', onsite_start_time: '07:30:00' })]).setup_time).toBe('07:30')
  })

  /** אפס שעות הוא ערך שהוזן, ולא שדה ריק. */
  it('keeps a zero in the hours field', () => {
    expect(sectionValuesFromTasks([task({ code: 'setup', hours_count: 0 })]).setup_hours_count).toBe('0')
    expect(sectionValuesFromTasks([task({ code: 'setup', hours_count: null })]).setup_hours_count).toBe('')
  })

  /**
   * כמות עובדים מתנהגת אחרת מכמות שעות: 0 מוצג כשדה ריק. ההתנהגות נעולה כאן
   * כמו שהיא — הערך הזה נשלח ל-RPC כמות שהוא, ושינוי שלו משנה מה נשמר. הכרעה
   * נפרדת, לא בתיקון הזה.
   */
  it('still shows zero workers as an empty field', () => {
    expect(sectionValuesFromTasks([task({ code: 'setup', worker_count: 0 })]).setup_worker_count).toBe('')
    expect(sectionValuesFromTasks([task({ code: 'setup', worker_count: 4 })]).setup_worker_count).toBe('4')
  })

  /** ל-RLS על task_pricing יש דעה: למי שאין לו pricing.view המחיר חוזר null. */
  it('leaves the price empty when the reader may not see it', () => {
    expect(sectionValuesFromTasks([task({ code: 'setup', price: null })]).setup_price).toBe('')
    expect(sectionValuesFromTasks([task({ code: 'setup', price: 1200 })]).setup_price).toBe('1200')
  })

  /* מפתח נעדר היה משאיר בטופס את מה שכבר היה בו — בדיוק התקלה שהמנגנון מונע. */
  it('writes six empty fields for a section that has no task', () => {
    const patch = sectionValuesFromTasks([task({ code: 'setup', task_date: '2026-09-01' })])
    expect(patch.teardown_date).toBe('')
    expect(patch.teardown_time).toBe('')
    expect(patch.teardown_worker_count).toBe('')
    expect(patch.teardown_hours_count).toBe('')
    expect(patch.teardown_execution_method).toBe('')
    expect(patch.teardown_price).toBe('')
  })

  it('empties all twelve when there are no tasks at all', () => {
    const patch = sectionValuesFromTasks([])
    expect(Object.keys(patch)).toHaveLength(12)
    expect(Object.values(patch).every((v) => v === '')).toBe(true)
  })
})

describe('incomeValuesFromRows', () => {
  it('keys the amounts by category, as strings', () => {
    expect(incomeValuesFromRows([{ category_id: 'c1', amount: 1500 }, { category_id: 'c2', amount: 0 }])).toEqual({
      c1: '1500',
      c2: '0',
    })
  })

  it('says nothing when the event has no income rows', () => {
    expect(incomeValuesFromRows([])).toEqual({})
  })
})

describe('draftFormValues', () => {
  it('opens an empty form when there is no draft', () => {
    expect(draftFormValues(null)).toEqual(emptyEventForm)
  })

  it('merges a partial draft over the empty form', () => {
    const f = draftFormValues(JSON.stringify({ end_client_name: 'חתונה בגן', truck_count: '2' }))
    expect(f.end_client_name).toBe('חתונה בגן')
    expect(f.truck_count).toBe('2')
    expect(f.notes).toBe('')
    expect(f.supplier_ids).toEqual([])
  })

  /** טיוטה משובשת אינה סיבה למסך שגיאה — הזריקה הגיעה עד ל-ErrorBoundary. */
  it('drops a draft it cannot read instead of throwing', () => {
    expect(() => draftFormValues('{oops')).not.toThrow()
    expect(draftFormValues('{oops')).toEqual(emptyEventForm)
  })
})
