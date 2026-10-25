import { describe, expect, it } from 'vitest'
import {
  ArgError,
  args,
  contextBlock,
  crewSize,
  eventLabel,
  israelLocalToIso,
  lineAssign,
  lineCreateTask,
  lineInvoice,
  lineMission,
  lineMoney,
  lineTaskTimes,
  monthHe,
  TOOLS,
  toolsFor,
} from './assistant'

describe('the tool catalog', () => {
  it('has unique names and well-formed schemas', () => {
    const names = TOOLS.map((t) => t.name)
    expect(new Set(names).size).toBe(names.length)
    for (const t of TOOLS) {
      expect(t.input_schema.type).toBe('object')
      expect(t.input_schema.additionalProperties).toBe(false)
      for (const r of t.input_schema.required) expect(Object.keys(t.input_schema.properties)).toContain(r)
      expect(t.description.length).toBeGreaterThan(20)
    }
  })

  it('marks every write tool as one that prepares, never one that does', () => {
    for (const t of TOOLS.filter((x) => x.write)) expect(t.description).toMatch(/^PREPARE/)
    for (const t of TOOLS.filter((x) => !x.write)) expect(t.description).not.toMatch(/^PREPARE/)
  })

  it('gives every money tool the keys a group must hold', () => {
    for (const t of TOOLS.filter((x) => x.sensitive)) expect(t.groupKeys.length).toBeGreaterThan(0)
  })

  it('offers an admin everything, in a stable order', () => {
    const all = toolsFor({}, true).map((t) => t.name)
    expect(all).toHaveLength(TOOLS.length)
    expect(all).toEqual([...all].sort((a, b) => a.localeCompare(b)))
  })

  it('offers others only what their keys allow', () => {
    const names = (caps: Record<string, boolean>) => toolsFor(caps, false).map((t) => t.name)
    const viewer = names({ 'events.view': true, 'tasks.view': true })
    expect(viewer).toContain('find_events')
    expect(viewer).toContain('schedule')
    expect(viewer).not.toContain('reschedule_task')
    expect(viewer).not.toContain('finance_summary')
    expect(viewer).not.toContain('missions')
    expect(viewer).not.toContain('save_supplier_invoice')

    // tasks.edit לבדו אינו מספיק לשינוי זמנים; צריך גם tasks.reschedule
    expect(names({ 'tasks.edit': true })).not.toContain('reschedule_task')
    expect(names({ 'tasks.edit': true, 'tasks.reschedule': true })).toContain('reschedule_task')

    // שיבוץ: כל אחד ממפתחות התפקידים פותח את הכלי (השרת בודק את התפקיד עצמו)
    expect(names({ 'tasks.assign.driver': true })).toContain('assign_crew')
    expect(names({ 'pricing.revenue': true })).toContain('finance_summary')
    expect(names({ 'finance.cash_wallet_view': true })).toContain('cash_wallet')
    expect(names({ 'finance.cash_wallet_view': true })).not.toContain('add_cash_entry')
  })
})

describe('args', () => {
  it('accepts and normalizes good input', () => {
    const i = args.obj({ id: 'AAAAAAAA-0000-4000-8000-000000000001', d: '2026-11-12', t: '08:30', n: '4', s: '  שלום   עולם ' })
    expect(args.uuid(i, 'id')).toBe('aaaaaaaa-0000-4000-8000-000000000001')
    expect(args.date(i, 'd')).toBe('2026-11-12')
    expect(args.time(i, 't')).toBe('08:30')
    expect(args.num(i, 'n', { int: true })).toBe(4)
    expect(args.text(i, 's', { max: 20 })).toBe('שלום עולם')
  })

  it('tells "not sent" from "clear" for a time', () => {
    expect(args.time({}, 't')).toBeUndefined()
    expect(args.time({ t: '' }, 't')).toBeNull()
    expect(args.time({ t: null }, 't')).toBeNull()
  })

  it('refuses bad input with a message the model can act on', () => {
    expect(() => args.uuid({ id: 'event-1234' }, 'id')).toThrow(ArgError)
    expect(() => args.uuid({}, 'id')).toThrow(/required/)
    expect(() => args.date({ d: '2026-02-30' }, 'd')).toThrow(/real date/)
    expect(() => args.time({ t: '25:00' }, 't')).toThrow(/HH:MM/)
    expect(() => args.num({ n: -5 }, 'n', { min: 0.01 })).toThrow(/at least/)
    expect(() => args.num({ n: 2.5 }, 'n', { int: true })).toThrow(/whole/)
    expect(() => args.oneOf({ r: 'boss' }, 'r', ['worker', 'driver'] as const)).toThrow(/one of/)
    expect(() => args.uuids({ ids: [] }, 'ids', 30)).toThrow(/non-empty/)
    expect(() => args.obj('x')).toThrow(ArgError)
  })
})

describe('israelLocalToIso', () => {
  it('reads a local time in summer and in winter', () => {
    expect(israelLocalToIso('2026-07-01T09:00')).toBe('2026-07-01T06:00:00.000Z')
    expect(israelLocalToIso('2026-12-01T09:00')).toBe('2026-12-01T07:00:00.000Z')
  })

  it('handles the morning after the clocks change (25/10/2026)', () => {
    expect(israelLocalToIso('2026-10-25T09:00')).toBe('2026-10-25T07:00:00.000Z')
    expect(israelLocalToIso('2026-10-24T09:00')).toBe('2026-10-24T06:00:00.000Z')
  })

  it('refuses anything else', () => {
    expect(() => israelLocalToIso('2026-10-25 09:00')).toThrow(ArgError)
    expect(() => israelLocalToIso('2026-13-01T09:00')).toThrow(ArgError)
  })
})

describe('crewSize', () => {
  it('counts each person once, the team lead included', () => {
    expect(
      crewSize({
        workers: [{ profile_id: 'a', name: 'א' }, { profile_id: 'b', name: 'ב' }],
        // ב' גם נוהג; ראש הצוות (ל') נוהג גם הוא
        drivers: [{ profile_id: 'b', name: 'ב' }, { profile_id: 'l', name: 'ל' }],
        team_lead_id: 'l',
        team_lead_name: 'ל',
        team_lead_kind: 'staff',
        contractor_worker_list: [{ id: 'c1', name: 'ק', role: 'worker' }],
        customer_worker_list: [],
      }),
    ).toBe(4)
  })

  it('does not count a contractor team lead twice', () => {
    expect(
      crewSize({
        team_lead_name: 'ראש צוות קבלן',
        team_lead_kind: 'contractor',
        contractor_worker_list: [{ id: 'c1', name: 'ראש צוות קבלן', role: 'team_lead' }, { id: 'c2', name: 'עובד', role: 'worker' }],
      }),
    ).toBe(2)
  })

  it('is zero for an empty task', () => {
    expect(crewSize({})).toBe(0)
  })
})

describe('preview lines', () => {
  const today = '2026-10-25'
  const label = eventLabel({ end_client_name: 'כהן', customer_name: 'שיא עיצובים', event_number: '1234', event_date: '2026-11-12' }, today)

  it('names an event the way people say it', () => {
    expect(label).toBe('כהן · שיא עיצובים · #1234 · יום ה׳ 12/11')
    expect(eventLabel({ customer_name: 'קיסר', event_date: '2026-11-12' }, today)).toBe('קיסר · יום ה׳ 12/11')
  })

  it('shows a time change, and who will hear about it', () => {
    const line = lineTaskTimes('הקמה', label,
      { date: '2026-11-12', onsite: '08:00:00', warehouse: null, hours: 6 },
      { date: '2026-11-12', onsite: '10:00', warehouse: null, hours: 6 }, today, 4)
    expect(line).toBe('• *הקמה* · כהן · שיא עיצובים · #1234 · יום ה׳ 12/11: שטח 08:00 · 6 ש׳ ← שטח 10:00 · 6 ש׳\n  (4 אנשי צוות יקבלו התראה על השינוי)')
  })

  it('shows the date when it moves', () => {
    const line = lineTaskTimes('פירוק', 'x',
      { date: '2026-11-12', onsite: null, warehouse: null, hours: null },
      { date: '2026-11-13', onsite: null, warehouse: null, hours: null }, today, 0)
    expect(line).toBe('• *פירוק* · x: יום ה׳ 12/11 ← יום ו׳ 13/11')
  })

  it('writes the other changes', () => {
    expect(lineCreateTask('סידור', 'x', { date: '2026-11-12', onsite: '09:00', warehouse: null, hours: 3, workers: 2 }, today))
      .toBe('• *משימה חדשה:* סידור · x · יום ה׳ 12/11 · שטח 09:00 · 3 ש׳ · 2 עובדים (טיוטה)')
    expect(lineAssign('דני', 'driver', 'הקמה · x', null)).toBe('• *שיבוץ:* דני כנהג · הקמה · x')
    expect(lineAssign('דני', 'team_lead', 'הקמה · x', 'יוסי')).toBe('• *שיבוץ:* דני כראש צוות · הקמה · x (במקום יוסי)')
    expect(lineMoney('payment', 5000, 'x', 'יתרה אחרי: ₪0')).toBe('• *תשלום ₪5,000* · x\n  יתרה אחרי: ₪0')
    expect(lineMission('להתקשר לספק', '2026-10-26T06:00:00.000Z', 2, null))
      .toBe('• *משימת ניהול:* "להתקשר לספק" · יעד יום ב׳ 26/10 08:00 · עדיפות 2')
    expect(lineInvoice({ vendor: 'פז', docType: 'חשבונית מס', number: 'A-1', issueDate: '2026-10-20', total: 118, currency: 'ILS', folder: monthHe('2026-10-01') }))
      .toBe('• *חשבונית ספק:* פז · חשבונית מס · #A-1 · יום ג׳ 20/10 · ₪118\n  תיכנס לתיקייה של אוקטובר 2026')
  })
})

describe('contextBlock', () => {
  it('tells the model when and who, and what is pending', () => {
    const c = contextBlock({
      nowDate: '2026-10-25', nowTime: '09:41', name: 'שמחה', isAdmin: true, chat: 'group', chatName: 'וייפר',
      pending: ['• *הקמה* · x: שטח 08:00 ← שטח 10:00'], file: null,
    })
    expect(c).toContain('יום א׳ 2026-10-25 09:41')
    expect(c).toContain('מחר: 2026-10-26')
    expect(c).toContain('(מנהל מערכת)')
    expect(c).toContain('קבוצה "וייפר"')
    expect(c).toContain('שינוי שממתין לאישור')
  })
})
