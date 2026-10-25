import { describe, expect, it } from 'vitest'
import {
  addDays,
  fmtDay,
  fmtMoney,
  fmtTime,
  israelNow,
  isIsoDate,
  parseCommand,
  parseIncoming,
  periodRange,
  route,
  splitMessage,
  waMeLink,
  waPhone,
} from './whatsapp'
import type { InboundMessage, RouteInput } from './whatsapp'

const base = {
  typeWebhook: 'incomingMessageReceived',
  instanceData: { idInstance: 7103000000, wid: '972500000999@c.us', typeInstance: 'whatsapp' },
  timestamp: 1792900000,
  idMessage: 'F7AEC1B7086ECDC7E6E45923F5EDB825',
}

const groupText = (text: string) => ({
  ...base,
  senderData: {
    chatId: '120363369140947676@g.us',
    chatName: 'וייפר',
    sender: '972501234567@c.us',
    senderName: 'דני',
    senderContactName: 'דני כהן',
  },
  messageData: { typeMessage: 'textMessage', textMessageData: { textMessage: text } },
})

describe('parseIncoming', () => {
  it('reads a group text message', () => {
    const m = parseIncoming(groupText('  מה יש מחר?  '))!
    expect(m.isGroup).toBe(true)
    expect(m.chatId).toBe('120363369140947676@g.us')
    expect(m.sender).toBe('972501234567@c.us')
    expect(m.senderName).toBe('דני כהן')
    expect(m.text).toBe('מה יש מחר?')
    expect(m.kind).toBe('text')
    expect(m.instanceId).toBe('7103000000')
    expect(m.botWid).toBe('972500000999@c.us')
  })

  it('reads a quoted reply and its stanza', () => {
    const m = parseIncoming({
      ...groupText(''),
      messageData: {
        typeMessage: 'quotedMessage',
        extendedTextMessageData: { text: 'כן', stanzaId: 'BAE5ABC', participant: '972500000999@c.us' },
        quotedMessage: { stanzaId: 'BAE5ABC', typeMessage: 'textMessage', textMessage: 'לאשר?' },
      },
    })!
    expect(m.text).toBe('כן')
    expect(m.quotedId).toBe('BAE5ABC')
  })

  it('reads a file with its caption', () => {
    const m = parseIncoming({
      ...groupText(''),
      messageData: {
        typeMessage: 'imageMessage',
        fileMessageData: { downloadUrl: 'https://sw-media.example/abc.jpg', caption: 'חשבונית', fileName: 'abc.jpg', mimeType: 'image/jpeg' },
      },
    })!
    expect(m.kind).toBe('file')
    expect(m.text).toBe('חשבונית')
    expect(m.file).toEqual({ url: 'https://sw-media.example/abc.jpg', mime: 'image/jpeg', name: 'abc.jpg' })
  })

  it('marks reactions and edits so they never confirm anything', () => {
    const r = parseIncoming({
      ...groupText(''),
      messageData: { typeMessage: 'reactionMessage', extendedTextMessageData: { text: '👍' } },
    })!
    expect(r.kind).toBe('reaction')
    const e = parseIncoming({
      ...groupText(''),
      messageData: { typeMessage: 'editedMessage', editedMessageData: { textMessage: 'כן', stanzaId: 'X' } },
    })!
    expect(e.kind).toBe('edited')
  })

  it('recognises a voice note', () => {
    const m = parseIncoming({
      ...groupText(''),
      messageData: { typeMessage: 'audioMessage', fileMessageData: { downloadUrl: 'https://x/a.ogg', mimeType: 'audio/ogg' } },
    })!
    expect(m.kind).toBe('audio')
  })

  it('reads a private chat and an @lid sender', () => {
    const m = parseIncoming({
      ...base,
      senderData: { chatId: '123456789012345@lid', sender: '123456789012345@lid', senderName: 'x' },
      messageData: { typeMessage: 'textMessage', textMessageData: { textMessage: 'שלום' } },
    })!
    expect(m.isGroup).toBe(false)
    expect(m.sender).toBe('123456789012345@lid')
  })

  it('ignores everything that is not an incoming message', () => {
    expect(parseIncoming({ ...base, typeWebhook: 'outgoingAPIMessageReceived' })).toBeNull()
    expect(parseIncoming({ ...base, typeWebhook: 'stateInstanceChanged' })).toBeNull()
    expect(parseIncoming(null)).toBeNull()
    expect(parseIncoming({ typeWebhook: 'incomingMessageReceived' })).toBeNull()
  })
})

describe('parseCommand', () => {
  it('reads a link code', () => {
    expect(parseCommand('קוד 123456')).toEqual({ type: 'link', code: '123456' })
    expect(parseCommand(' קוד: 004512 ')).toEqual({ type: 'link', code: '004512' })
    expect(parseCommand('code 123456')).toEqual({ type: 'link', code: '123456' })
    expect(parseCommand('קוד 12345')).toBeNull()
    expect(parseCommand('הקוד הוא 123456 תודה')).toBeNull()
  })

  it('reads bind and unbind', () => {
    expect(parseCommand('הפעל כאן')).toEqual({ type: 'bind' })
    expect(parseCommand('חבר את הקבוצה')).toEqual({ type: 'bind' })
    expect(parseCommand('כבה כאן!')).toEqual({ type: 'unbind' })
    expect(parseCommand('הפעל כאן את המזגן')).toBeNull()
  })

  it('reads yes and no, and nothing longer', () => {
    for (const t of ['כן', 'כן!', 'כן.', 'מאשר', 'אשר', 'OK', '👍', '✅', 'כן תבצע']) {
      expect(parseCommand(t)).toEqual({ type: 'confirm' })
    }
    for (const t of ['לא', 'בטל', 'לא תודה', '❌']) {
      expect(parseCommand(t)).toEqual({ type: 'cancel' })
    }
    expect(parseCommand('כן אבל לשעה 9')).toBeNull()
    expect(parseCommand('לא, לשעה 9')).toBeNull()
    expect(parseCommand('')).toBeNull()
  })
})

describe('route', () => {
  const msg = (over: Partial<InboundMessage> = {}): InboundMessage => ({
    idMessage: 'X1',
    timestamp: 0,
    chatId: '120363000000000077@g.us',
    isGroup: true,
    sender: '972501234567@c.us',
    senderName: '',
    chatName: '',
    instanceId: '1',
    botWid: '972500000999@c.us',
    kind: 'text',
    text: 'מה יש מחר?',
    quotedId: null,
    file: null,
    ...over,
  })
  const dm = (over: Partial<InboundMessage> = {}) =>
    msg({ chatId: '972501234567@c.us', isGroup: false, ...over })
  const bound = { active: true, isGroup: true, participantsOk: true }
  const admin = { allowed: true, isAdmin: true }
  const staff = { allowed: true, isAdmin: false }
  const r = (over: Partial<RouteInput>) =>
    route({ msg: msg(), command: null, chat: null, sender: null, forwardConfigured: true, ...over })

  it('answers in a bound group whose members are all known', () => {
    expect(r({ chat: bound, sender: staff })).toEqual({ action: 'process' })
  })

  it('stops in a bound group with a stranger in it', () => {
    expect(r({ chat: { ...bound, participantsOk: false }, sender: staff })).toEqual({ action: 'blocked_group' })
  })

  it('never forwards the bound group — it is ours only', () => {
    expect(r({ chat: bound, sender: null })).toEqual({ action: 'ignore', reason: 'unknown_sender' })
    expect(r({ chat: bound, sender: { allowed: false, isAdmin: false } })).toEqual({ action: 'ignore', reason: 'unknown_sender' })
  })

  it('forwards any other group to Viper One, or ignores it when no forward is set', () => {
    expect(r({ sender: staff })).toEqual({ action: 'forward' })
    expect(r({ sender: staff, forwardConfigured: false })).toEqual({ action: 'ignore', reason: 'not_ours' })
    expect(r({ chat: { ...bound, active: false }, sender: admin })).toEqual({ action: 'forward' })
  })

  it('binds a group only for a linked admin', () => {
    expect(r({ command: { type: 'bind' }, sender: admin })).toEqual({ action: 'bind' })
    expect(r({ command: { type: 'bind' }, sender: staff })).toEqual({ action: 'forward' })
    expect(r({ command: { type: 'bind' }, sender: staff, chat: bound })).toEqual({ action: 'ignore', reason: 'bind_not_admin' })
    expect(r({ command: { type: 'unbind' }, sender: admin, chat: bound })).toEqual({ action: 'unbind' })
    expect(r({ command: { type: 'unbind' }, sender: staff, chat: bound })).toEqual({ action: 'ignore', reason: 'unbind_not_admin' })
  })

  it('takes a link code only in a private chat', () => {
    expect(route({ msg: dm(), command: { type: 'link', code: '123456' }, chat: null, sender: null, forwardConfigured: true }))
      .toEqual({ action: 'link', code: '123456' })
    expect(r({ command: { type: 'link', code: '123456' }, chat: bound })).toEqual({ action: 'link_in_group' })
    expect(r({ command: { type: 'link', code: '123456' } })).toEqual({ action: 'forward' })
  })

  it('answers a linked user in private, and forwards an unknown one', () => {
    expect(route({ msg: dm(), command: null, chat: null, sender: staff, forwardConfigured: true })).toEqual({ action: 'process' })
    expect(route({ msg: dm(), command: null, chat: null, sender: null, forwardConfigured: true })).toEqual({ action: 'forward' })
  })

  it('refuses a private chat that is not the sender’s own', () => {
    expect(route({ msg: dm({ chatId: '972509999999@c.us' }), command: null, chat: null, sender: staff, forwardConfigured: true }))
      .toEqual({ action: 'ignore', reason: 'dm_mismatch' })
  })
})

describe('splitMessage', () => {
  it('keeps a short reply whole', () => {
    expect(splitMessage('שלום\nעולם')).toEqual(['שלום\nעולם'])
  })

  it('splits on line boundaries', () => {
    const lines = Array.from({ length: 10 }, (_, i) => `שורה ${i} ${'x'.repeat(40)}`)
    const parts = splitMessage(lines.join('\n'), 120)
    expect(parts.length).toBeGreaterThan(1)
    expect(parts.join('\n')).toBe(lines.join('\n'))
    for (const p of parts) expect(p.length).toBeLessThanOrEqual(120)
  })

  it('cuts a single very long line at a word', () => {
    const words = Array.from({ length: 50 }, () => 'מילה').join(' ')
    const parts = splitMessage(words, 60)
    for (const p of parts) expect(p.length).toBeLessThanOrEqual(60)
    expect(parts.join(' ').replace(/\s+/g, ' ')).toBe(words)
  })
})

describe('Israel time', () => {
  it('knows the date in Israel while UTC is still on yesterday', () => {
    // 22:30 UTC on 24/10 is already 01:30 on 25/10 in Israel (summer time)
    expect(israelNow(new Date('2026-10-24T22:30:00Z'))).toEqual({ date: '2026-10-25', time: '01:30', weekday: 0 })
  })

  it('survives the end of summer time (25/10/2026)', () => {
    // 01:30 UTC after the switch = 03:30 Israel (winter, +2)
    expect(israelNow(new Date('2026-10-25T01:30:00Z')).time).toBe('03:30')
    expect(israelNow(new Date('2026-10-25T23:30:00Z')).date).toBe('2026-10-26')
  })

  it('builds the ranges the screens use', () => {
    const now = new Date('2026-10-28T09:00:00Z') // Wednesday
    expect(periodRange('today', now)).toEqual({ from: '2026-10-28', to: '2026-10-28' })
    expect(periodRange('tomorrow', now)).toEqual({ from: '2026-10-29', to: '2026-10-29' })
    expect(periodRange('this_week', now)).toEqual({ from: '2026-10-25', to: '2026-10-31' })
    expect(periodRange('next_week', now)).toEqual({ from: '2026-11-01', to: '2026-11-07' })
    expect(periodRange('this_month', now)).toEqual({ from: '2026-10-01', to: '2026-10-31' })
    expect(periodRange('last_month', now)).toEqual({ from: '2026-09-01', to: '2026-09-30' })
    expect(periodRange('next_month', now)).toEqual({ from: '2026-11-01', to: '2026-11-30' })
  })

  it('wraps the year for January and December', () => {
    expect(periodRange('last_month', new Date('2027-01-10T09:00:00Z'))).toEqual({ from: '2026-12-01', to: '2026-12-31' })
    expect(periodRange('next_month', new Date('2026-12-10T09:00:00Z'))).toEqual({ from: '2027-01-01', to: '2027-01-31' })
  })

  it('does date arithmetic without time zones', () => {
    expect(addDays('2026-10-31', 1)).toBe('2026-11-01')
    expect(addDays('2026-03-27', 1)).toBe('2026-03-28')
    expect(isIsoDate('2026-02-30')).toBe(false)
    expect(isIsoDate('2026-02-28')).toBe(true)
  })
})

describe('format', () => {
  it('writes days, times and money the Israeli way', () => {
    expect(fmtDay('2026-11-12', '2026-10-25')).toBe('יום ה׳ 12/11')
    expect(fmtDay('2027-01-03', '2026-10-25')).toBe('יום א׳ 3/1/2027')
    expect(fmtTime('08:00:00')).toBe('08:00')
    expect(fmtTime(null)).toBe('')
    expect(fmtMoney(12500)).toBe('₪12,500')
    expect(fmtMoney(-90.5)).toBe('-₪90.5')
  })

  it('writes a sender as a phone number', () => {
    expect(waPhone('972501234567@c.us')).toBe('0501234567')
    expect(waPhone('14155550100@c.us')).toBe('+14155550100')
    expect(waPhone('123456789012345@lid')).toBe('123456789012345@lid')
  })

  it('links to a private chat with the bot', () => {
    expect(waMeLink('972500000999@c.us', 'קוד 123456')).toBe('https://wa.me/972500000999?text=%D7%A7%D7%95%D7%93%20123456')
    expect(waMeLink('', 'x')).toBeNull()
  })
})
