import { describe, expect, it } from 'vitest'
import { paidAmountOf, penaltyOf, summarize, taskLabel } from './portalTasks'
import { buildPortalTasksSheet, hasMoney, planHasMoney } from './exportPortalTasks'
import type { PortalTaskRow } from '../../types/domain'

/**
 * שתי ההבטחות של סיכום המשימות נבדקות כאן: ש-`null` במחיר אינו נספר כאפס,
 * ושמה ששולם הוא הסכום שנרשם ולא המחיר. שתיהן חיות גם בקובץ ה-Excel שיוצא
 * להנהלת חשבונות.
 */

function row(over: Partial<PortalTaskRow> = {}): PortalTaskRow {
  return {
    task_id: 't1',
    task_date: '2026-09-10',
    title: null,
    task_type_name: 'הקמה',
    status_name: 'שובץ',
    status_color: '#64748b',
    is_terminal: false,
    event_id: 'e1',
    event_date: '2026-09-10',
    event_number: 'EV-1',
    end_client_name: 'אולם הדס',
    customer_name: 'לקוח',
    location_text: 'הרצל 1, תל אביב',
    worker_count: 2,
    price: 1000,
    price_parts: null,
    paid_at: null,
    paid_amount: null,
    ...over,
  }
}

describe('taskLabel', () => {
  it('מעדיף את הכותרת שהוקלדה', () => {
    expect(taskLabel(row({ title: 'הקמה מוקדמת' }))).toBe('הקמה מוקדמת')
  })

  it('ונופל לשם סוג המשימה', () => {
    expect(taskLabel(row())).toBe('הקמה')
  })
})

describe('paidAmountOf', () => {
  it('שורה שלא שולמה אינה נושאת סכום', () => {
    expect(paidAmountOf(row())).toBeNull()
  })

  it('הסכום שנרשם גובר על המחיר', () => {
    expect(paidAmountOf(row({ paid_at: '2026-09-20T00:00:00Z', paid_amount: 900 }))).toBe(900)
  })

  it('ובהיעדרו המחיר הוא מה ששולם', () => {
    expect(paidAmountOf(row({ paid_at: '2026-09-20T00:00:00Z' }))).toBe(1000)
  })
})

describe('summarize', () => {
  it('מחיר חסום נספר בנפרד ואינו אפס', () => {
    const t = summarize([row({ price: 500 }), row({ task_id: 't2', price: null })])
    expect(t.tasks).toBe(2)
    expect(t.expected).toBe(500)
    expect(t.unpriced).toBe(1)
  })

  it('מפריד בין ששולם ליתרה, לפי הסכום שנרשם', () => {
    const t = summarize([
      row({ price: 1000, paid_at: '2026-09-20T00:00:00Z', paid_amount: 900 }),
      row({ task_id: 't2', price: 500 }),
    ])
    expect(t.paid).toBe(900)
    expect(t.paidTasks).toBe(1)
    expect(t.unpaid).toBe(500)
    // הצפוי הוא מה שסוכם על השורות, ולא מה ששולם בפועל
    expect(t.expected).toBe(1500)
  })

  it('סופר את מה שבוצע ואת הקנסות', () => {
    const parts = {
      base: 1200,
      surcharge: 0,
      worker_count: 2,
      transport: false,
      late_count: 1,
      late_penalty_each: 200,
      noshow_count: 0,
      noshow_penalty_each: 0,
      penalty_total: 200,
    }
    const t = summarize([row({ is_terminal: true, price: 1000, price_parts: parts }), row({ task_id: 't2' })])
    expect(t.completed).toBe(1)
    expect(t.penalties).toBe(200)
    expect(penaltyOf(row())).toBe(0)
  })

  it('רשימה ריקה היא אפסים ולא NaN', () => {
    expect(summarize([])).toEqual({
      tasks: 0,
      completed: 0,
      unpriced: 0,
      expected: 0,
      paid: 0,
      unpaid: 0,
      paidTasks: 0,
      penalties: 0,
    })
  })
})

describe('buildPortalTasksSheet', () => {
  it('קבלן בלי הרשאת כסף מקבל גיליון בלי אף עמודת סכום', () => {
    const rows = [row({ price: null }), row({ task_id: 't2', price: null })]
    expect(hasMoney(rows)).toBe(false)
    const plan = buildPortalTasksSheet(rows)
    expect(planHasMoney(plan)).toBe(false)
    expect(plan.rows).toHaveLength(2)
  })

  it('וכשיש מחיר — הוא, הקנס והתשלום יורדים לגיליון', () => {
    const plan = buildPortalTasksSheet([
      row({
        price: 800,
        paid_at: '2026-09-20T10:00:00Z',
        paid_amount: 800,
        price_parts: {
          base: 1000,
          surcharge: 0,
          worker_count: 2,
          transport: false,
          late_count: 1,
          late_penalty_each: 200,
          noshow_count: 0,
          noshow_penalty_each: 0,
          penalty_total: 200,
        },
      }),
    ])
    expect(planHasMoney(plan)).toBe(true)
    expect(plan.rows[0]).toMatchObject({ price: 800, penalty: 200, paid_amount: 800, paid_at: '2026-09-20' })
    expect(plan.footer[0].values).toMatchObject({ price: 800, paid_amount: 800 })
  })

  it('הסיכום שבתחתית סופר את השורות שבגיליון', () => {
    const plan = buildPortalTasksSheet([
      row({ price: 1000, paid_at: '2026-09-20T10:00:00Z', paid_amount: 900 }),
      row({ task_id: 't2', price: 500 }),
    ])
    expect(plan.footer[0].values).toMatchObject({ task: '2 משימות', price: 1500, paid_amount: 900 })
    expect(plan.footer[1].values).toMatchObject({ price: 500 })
  })
})
