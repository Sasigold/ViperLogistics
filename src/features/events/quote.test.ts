import { describe, expect, it } from 'vitest'
import {
  buildQuoteLines,
  quoteFileName,
  quoteFixedNote,
  quoteFooterText,
  quoteStoragePath,
  quoteTotals,
  quoteWhatsAppText,
  taskWhenText,
  toWhatsAppNumber,
} from './quote'
import type { EventPriceAddon, WorkBoardRow } from '../../types/domain'

function task(over: Partial<WorkBoardRow> & { id: string }): WorkBoardRow {
  return {
    task_type_name: 'הקמה',
    title: null,
    task_date: '2026-09-12',
    onsite_start_time: '08:00:00',
    customer_price: 1000,
    ...over,
  } as WorkBoardRow
}

function addon(over: Partial<EventPriceAddon> & { id: string; task_id: string }): EventPriceAddon {
  return {
    task_label: 'הקמה',
    amount: 250,
    note: 'שעתיים המתנה בשער',
    created_at: '2026-09-01T00:00:00Z',
    creator_name: null,
    ...over,
  } as EventPriceAddon
}

describe('taskWhenText', () => {
  it('מחבר תאריך ושעה', () => {
    expect(taskWhenText('2026-09-12', '08:00:00')).toBe('12/09/2026 · 08:00')
  })
  it('תאריך בלבד כשאין שעה', () => {
    expect(taskWhenText('2026-09-12', null)).toBe('12/09/2026')
  })
  it('אינו מזיז את היום לפי אזור זמן', () => {
    // ‏new Date('2026-01-01') הוא חצות UTC, ובאזור שלילי הוא 31/12.
    expect(taskWhenText('2026-01-01', '00:00:00')).toBe('01/01/2026 · 00:00')
  })
  it('בלי תאריך אין מה להדפיס', () => {
    expect(taskWhenText(null, '08:00:00')).toBe('')
  })
})

describe('buildQuoteLines', () => {
  it('שורה לכל משימה, לפי הכותרת כשיש ולפי סוג המשימה כשאין', () => {
    const lines = buildQuoteLines(
      [task({ id: 't1' }), task({ id: 't2', title: 'פירוק מוקדם', task_type_name: 'פירוק' })],
      [],
    )
    expect(lines.map((l) => l.label)).toEqual(['הקמה', 'פירוק מוקדם'])
  })

  it('מציב כל תוספת מתחת למשימה שלה', () => {
    const lines = buildQuoteLines(
      [task({ id: 't1' }), task({ id: 't2' })],
      [addon({ id: 'a1', task_id: 't1' })],
    )
    expect(lines.map((l) => `${l.kind}:${l.id}`)).toEqual(['task:t1', 'addon:a1', 'task:t2'])
  })

  it('תוספת יתומה נספרת בסוף עם שם המשימה שלה', () => {
    const lines = buildQuoteLines(
      [task({ id: 't1' })],
      [addon({ id: 'a9', task_id: 'gone', task_label: 'משימה שהוסרה' })],
    )
    expect(lines[lines.length - 1].label).toBe('משימה שהוסרה — שעתיים המתנה בשער')
  })

  it('משימה בלי מחיר נכנסת כאפס ולא נשמטת', () => {
    const lines = buildQuoteLines([task({ id: 't1', customer_price: null })], [])
    expect(lines).toHaveLength(1)
    expect(lines[0].amount).toBe(0)
  })

  it('בלי משימות ובלי תוספות אין שורות', () => {
    expect(buildQuoteLines([], [])).toEqual([])
  })
})

describe('quoteTotals', () => {
  it('מוסיף מע״מ על סכום הביניים', () => {
    const lines = buildQuoteLines([task({ id: 't1', customer_price: 1000 })], [])
    expect(quoteTotals(lines, 18)).toEqual({ subtotal: 1000, vatAmount: 180, total: 1180 })
  })

  it('מעגל לאגורות', () => {
    const lines = buildQuoteLines([task({ id: 't1', customer_price: 333.33 })], [])
    expect(quoteTotals(lines, 18)).toEqual({ subtotal: 333.33, vatAmount: 60, total: 393.33 })
  })

  it('הנחה היא תוספת שלילית ומורידה את הסכום', () => {
    const lines = buildQuoteLines(
      [task({ id: 't1', customer_price: 1000 })],
      [addon({ id: 'a1', task_id: 't1', amount: -100, note: 'הנחת לקוח חוזר' })],
    )
    expect(quoteTotals(lines, 18).subtotal).toBe(900)
  })

  it('רשימה ריקה היא אפס ולא NaN', () => {
    expect(quoteTotals([], 18)).toEqual({ subtotal: 0, vatAmount: 0, total: 0 })
  })

  it('אחוז אפס אינו מוסיף שורת מע״מ', () => {
    const lines = buildQuoteLines([task({ id: 't1', customer_price: 500 })], [])
    expect(quoteTotals(lines, 0)).toEqual({ subtotal: 500, vatAmount: 0, total: 500 })
  })
})

describe('quoteFixedNote', () => {
  it('נושא את מספר המסמך, את שם הלקוח ואת תאריך השליחה', () => {
    const note = quoteFixedNote('12345', 'קיסר', new Date(2026, 8, 10, 14, 30))
    expect(note).toBe(
      'הצעת המחיר מתייחסת למפרט מס׳ 12345 כפי שנמסר ע״י חברת קיסר ונכון לתאריך 10/09/2026',
    )
  })

  it('שם הלקוח מגיע מהפרמטר — אין שם קבוע בקוד', () => {
    expect(quoteFixedNote('7', 'לקוח אחר', new Date(2026, 0, 1))).toContain('חברת לקוח אחר')
  })
})

describe('quoteFooterText', () => {
  it('אומר מתי המסמך נוצר', () => {
    expect(quoteFooterText('מסמך זה נוצר ע״י וייפר מערכות', new Date(2026, 8, 10, 9, 5))).toBe(
      'מסמך זה נוצר ע״י וייפר מערכות בתאריך 10/09/2026 בשעה 09:05',
    )
  })
})

describe('toWhatsAppNumber', () => {
  it.each([
    ['0501234567', '972501234567'],
    ['050-123-4567', '972501234567'],
    ['050 123 4567', '972501234567'],
    ['+972-50-1234567', '972501234567'],
    ['972501234567', '972501234567'],
    ['00972501234567', '972501234567'],
    ['0747600960', '972747600960'],
    ['03-1234567', '97231234567'],
  ])('מנרמל %s', (input, expected) => {
    expect(toWhatsAppNumber(input)).toBe(expected)
  })

  it.each([[''], [null], [undefined], ['לא מספר'], ['123'], ['05012345678901']])(
    'פוסל %s',
    (input) => {
      expect(toWhatsAppNumber(input as string | null)).toBeNull()
    },
  )
})

describe('שם הקובץ והנתיב', () => {
  it('שם הקובץ נושא את מספר המסמך', () => {
    expect(quoteFileName('12345')).toBe('הצעת מחיר 12345.pdf')
  })

  it('ומספר שיש בו לוכסן אינו הופך לתיקייה', () => {
    expect(quoteFileName('12/45')).toBe('הצעת מחיר 12-45.pdf')
  })

  it('הנתיב מתחיל במזהה האירוע — זה החוזה של הפוליסה', () => {
    expect(quoteStoragePath('ev-1', 'uu-2')).toBe('ev-1/uu-2.pdf')
  })

  it('ההודעה בוואטסאפ נושאת את המספר ואת שם החברה', () => {
    expect(quoteWhatsAppText('12345', 'וייפר')).toContain('12345')
    expect(quoteWhatsAppText('12345', 'וייפר')).toContain('וייפר')
  })
})
