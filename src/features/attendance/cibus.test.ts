import { describe, expect, it } from 'vitest'
import { cibusByEntry, cibusLocalDateTime, parseCibusMatrix, summarizeParsed, unmatchedFor } from './cibus'
import type { CibusReport, CibusTransaction } from '../../types/domain'

/**
 * הדוח המפורט של סיבוס, בצורה שבה הוא מגיע: כותרת, הערת "מידע רגיש", שורות
 * ריקות, שורת כותרות, המשיכות, שורת סה"כ והערה משפטית. השמות והמספרים כאן
 * בדויים.
 */
const HEADER = [
  'תאריך ושעה', 'תאריך', 'שעה', "מס' עסקה", "מס' עובד", 'ת.ז.', "מס' משתמש", 'שם פרטי', 'שם משפחה',
  'שם העובד/ת', 'שם קבוצה', 'מחלקה', 'שם בית העסק', 'סוג עסקה', 'הסכום שחוייב', 'חלק חברה', 'חלק עובד',
  'סכום פטור ממע"מ', 'סכום עסקאות שוברים', 'פעיל',
]

const txn = (over: Partial<Record<string, string>> = {}): string[] => {
  const v: Record<string, string> = {
    'תאריך ושעה': '31/08/2026 00:25',
    'תאריך': '2026-08-31',
    'שעה': '00:25',
    "מס' עסקה": '100001',
    "מס' עובד": '',
    'ת.ז.': '000000018',
    "מס' משתמש": '5000001',
    'שם פרטי': 'דני',
    'שם משפחה': 'כהן',
    'שם העובד/ת': 'דני כהן',
    'שם קבוצה': 'עובדים',
    'מחלקה': 'שטח',
    'שם בית העסק': 'מסעדה לדוגמה',
    'סוג עסקה': 'ישיבה',
    'הסכום שחוייב': '26.7',
    'חלק חברה': '26.7',
    'חלק עובד': '0',
    'סכום פטור ממע"מ': '0',
    'סכום עסקאות שוברים': '0',
    'פעיל': '1',
    ...over,
  }
  return HEADER.map((h) => v[h] ?? '')
}

const file = (...rows: string[][]): string[][] => [
  ['דוח מפורט לחברה לדוגמה 08/2026'],
  ['מסמך זה מכיל מידע רגיש*'],
  HEADER,
  ...rows,
  ["סה''כ:", '', '', '', '', '', '', '', '', '', '', '', '', '', '₪3127.98', '₪3127.98'],
  ['מסמך זה מכיל מידע עסקי רגיש'],
]

describe('parseCibusMatrix', () => {
  it('finds the header below the title rows and reads every withdrawal', () => {
    const { rows, errors } = parseCibusMatrix(
      file(txn(), txn({ "מס' עסקה": '100002', 'תאריך ושעה': '03/08/2026 22:25', 'הסכום שחוייב': '29' })),
    )
    expect(errors).toEqual([])
    expect(rows).toHaveLength(2)
    expect(rows[0]).toMatchObject({
      txn_no: 100001,
      occurred_local: '2026-08-31T00:25',
      user_no: 5000001,
      first_name: 'דני',
      last_name: 'כהן',
      employee_name: 'דני כהן',
      merchant: 'מסעדה לדוגמה',
      deal_type: 'ישיבה',
      amount: 26.7,
      company_part: 26.7,
      employee_part: 0,
    })
    expect(rows[1]!.occurred_local).toBe('2026-08-03T22:25')
  })

  // ת.ז. נשארת בקובץ — המסד לא צריך אותה כדי לזהות עובד
  it('never carries the national ID', () => {
    const { rows } = parseCibusMatrix(file(txn()))
    expect(JSON.stringify(rows)).not.toContain('000000018')
  })

  it('skips the totals row and the legal notice', () => {
    expect(parseCibusMatrix(file(txn())).rows).toHaveLength(1)
  })

  it('reads a file twice without duplicating a transaction number', () => {
    expect(parseCibusMatrix(file(txn(), txn())).rows).toHaveLength(1)
  })

  it('falls back to the separate date and time columns', () => {
    const { rows } = parseCibusMatrix(file(txn({ 'תאריך ושעה': '', 'תאריך': '2026-08-05', 'שעה': '19:09' })))
    expect(rows[0]!.occurred_local).toBe('2026-08-05T19:09')
  })

  it('builds the name from first + last when the full name column is empty', () => {
    const { rows } = parseCibusMatrix(file(txn({ 'שם העובד/ת': '' })))
    expect(rows[0]!.employee_name).toBe('דני כהן')
  })

  it('reports a row it could not date instead of guessing', () => {
    const { rows, errors } = parseCibusMatrix(file(txn({ 'תאריך ושעה': 'אתמול', 'תאריך': '', 'שעה': '' })))
    expect(rows).toHaveLength(0)
    expect(errors[0]).toContain('100001')
  })

  it('says so when this is not a Cibus report', () => {
    const { rows, errors } = parseCibusMatrix([['שם', 'טלפון'], ['א', '1']])
    expect(rows).toHaveLength(0)
    expect(errors[0]).toContain('כותרות')
  })

  it('reads amounts written with a shekel sign and thousands separator', () => {
    const { rows } = parseCibusMatrix(file(txn({ 'הסכום שחוייב': '₪1,029.50' })))
    expect(rows[0]!.amount).toBe(1029.5)
  })
})

describe('cibusLocalDateTime', () => {
  it('reads dd/mm/yyyy hh:mm, ISO, and the ExcelJS date cell form', () => {
    expect(cibusLocalDateTime('31/08/2026 00:25')).toBe('2026-08-31T00:25')
    expect(cibusLocalDateTime('2026-08-31 07:05')).toBe('2026-08-31T07:05')
    expect(cibusLocalDateTime('1/8/2026 7:05')).toBe('2026-08-01T07:05')
  })

  it('rejects an impossible time', () => {
    expect(cibusLocalDateTime('31/08/2026 25:00')).toBeNull()
    expect(cibusLocalDateTime('31/13/2026 10:00')).toBeNull()
  })
})

describe('summarizeParsed', () => {
  it('counts withdrawals, employees and the amount for the preview', () => {
    const { rows } = parseCibusMatrix(
      file(
        txn(),
        txn({ "מס' עסקה": '100002', 'הסכום שחוייב': '30', 'תאריך ושעה': '02/08/2026 12:00' }),
        txn({ "מס' עסקה": '100003', "מס' משתמש": '5000002', 'הסכום שחוייב': '10.1' }),
      ),
    )
    expect(summarizeParsed(rows)).toEqual({ count: 3, employees: 2, amount: 66.8, from: '2026-08-02', to: '2026-08-31' })
  })
})

const t = (over: Partial<CibusTransaction>): CibusTransaction => ({
  id: 'x',
  txn_no: 1,
  occurred_at: '2026-08-31T09:00:00Z',
  link_key: 'u:1',
  employee_name: 'דני כהן',
  profile_id: 'p1',
  full_name: 'דני כהן',
  merchant: 'מסעדה',
  deal_type: 'ישיבה',
  amount: 30,
  entry_id: null,
  ...over,
})

describe('cibusByEntry / unmatchedFor', () => {
  const report = {
    transactions: [
      t({ id: 'a', entry_id: 'e1' }),
      t({ id: 'b', entry_id: 'e1' }),
      t({ id: 'c', entry_id: null }),
      t({ id: 'd', entry_id: null, profile_id: null }),
    ],
  } as CibusReport

  it('groups withdrawals under the shift they fell in', () => {
    const map = cibusByEntry(report)
    expect(map.get('e1')?.map((x) => x.id)).toEqual(['a', 'b'])
    expect(map.size).toBe(1)
  })

  it('lists an employee’s withdrawals without attendance', () => {
    expect(unmatchedFor(report, 'p1').map((x) => x.id)).toEqual(['c'])
  })
})
