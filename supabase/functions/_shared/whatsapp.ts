// החצי הטהור של עוזר הוואטסאפ (0236) — בלי שום import של Deno, כדי ש-vitest
// יכסה אותו (אותו שיקול של `_shared/viperflow.ts`).
//
// כאן: פענוח ה-webhook של Green API להודעה אחת, הפקודות שהבוט מכיר בלי AI
// ("קוד", "הפעל כאן", "כבה כאן", כן/לא), ההכרעה למי ההודעה שייכת (אלינו, ל-
// Viper One, או לאף אחד), פיצול תשובה ארוכה, והטווחים "היום / השבוע / החודש"
// בשעון ישראל — השרת רץ ב-UTC, ולכן כל טווח נבנה כאן ונשלח במפורש.

export type WaKind = 'text' | 'file' | 'audio' | 'reaction' | 'edited' | 'other'

export interface WaFile {
  url: string
  mime: string
  name: string
}

export interface InboundMessage {
  idMessage: string
  /** שניות מאז 1970, כפי ש-Green API מוסר */
  timestamp: number
  chatId: string
  isGroup: boolean
  sender: string
  senderName: string
  chatName: string
  instanceId: string
  /** מספר הבוט עצמו ("9725…@c.us") */
  botWid: string
  kind: WaKind
  /** הטקסט, או הכיתוב של קובץ; '' כשאין */
  text: string
  quotedId: string | null
  file: WaFile | null
}

const str = (v: unknown): string => (typeof v === 'string' ? v : typeof v === 'number' ? String(v) : '')
const obj = (v: unknown): Record<string, unknown> =>
  v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {}

export const isGroupId = (id: string) => /@g\.us$/.test(id)
export const isPrivateId = (id: string) => /@(c\.us|lid)$/.test(id)

/**
 * הודעה נכנסת אחת, או null כשזה לא `incomingMessageReceived` תקין.
 *
 * ריאקשן ועריכה מסומנים כסוג משלהם: הם לא נחשבים לאישור ("כן") ולא לבקשה.
 */
export function parseIncoming(body: unknown): InboundMessage | null {
  const b = obj(body)
  if (b.typeWebhook !== 'incomingMessageReceived') return null
  const sd = obj(b.senderData)
  const md = obj(b.messageData)
  const inst = obj(b.instanceData)
  const chatId = str(sd.chatId)
  const idMessage = str(b.idMessage)
  if (!chatId || !idMessage) return null

  const type = str(md.typeMessage)
  let kind: WaKind = 'other'
  let text = ''
  let quotedId: string | null = null
  let file: WaFile | null = null

  const ext = obj(md.extendedTextMessageData)
  switch (type) {
    case 'textMessage':
      kind = 'text'
      text = str(obj(md.textMessageData).textMessage)
      break
    case 'extendedTextMessage':
    case 'quotedMessage':
      kind = 'text'
      text = str(ext.text)
      quotedId = str(ext.stanzaId) || str(obj(md.quotedMessage).stanzaId) || null
      break
    case 'imageMessage':
    case 'documentMessage': {
      const f = obj(md.fileMessageData)
      kind = 'file'
      text = str(f.caption)
      const url = str(f.downloadUrl)
      file = url ? { url, mime: str(f.mimeType), name: str(f.fileName) } : null
      break
    }
    case 'audioMessage':
      kind = 'audio'
      break
    case 'reactionMessage':
      kind = 'reaction'
      text = str(ext.text)
      break
    case 'editedMessage':
      kind = 'edited'
      text = str(obj(md.editedMessageData).textMessage)
      break
    default:
      kind = 'other'
  }

  return {
    idMessage,
    timestamp: Number(b.timestamp) || 0,
    chatId,
    isGroup: isGroupId(chatId),
    sender: str(sd.sender) || chatId,
    senderName: str(sd.senderContactName) || str(sd.senderName),
    chatName: str(sd.chatName),
    instanceId: str(inst.idInstance),
    botWid: str(inst.wid),
    kind,
    text: text.trim(),
    quotedId,
    file,
  }
}

// ===== פקודות ==============================================================

export type Command =
  | { type: 'link'; code: string }
  | { type: 'bind' }
  | { type: 'unbind' }
  | { type: 'confirm' }
  | { type: 'cancel' }

/** רווחים מכווצים, בלי סימני פיסוק בקצוות, אותיות לטיניות קטנות. */
export function normalize(text: string): string {
  return text
    .replace(/\p{Bidi_Control}/gu, '') // סימני כיוון: LRM/RLM, הטבעות ובידודים
    .trim()
    .replace(/\s+/g, ' ')
    .replace(/^[.,!?:;"'״׳\s]+|[.,!?:;"'״׳\s]+$/g, '')
    .toLowerCase()
}

const CONFIRM = new Set([
  'כן', 'כן כן', 'כן בבקשה', 'כן תבצע', 'כן, תבצע', 'כן לבצע', 'כן אשר', 'אשר', 'מאשר', 'מאשרת',
  'אישור', 'מאושר', 'בצע', 'תבצע', 'סבבה', 'יאללה', 'אוקיי', 'אוקי', 'ok', 'okay', 'yes', 'y',
  '👍', '👍🏻', '👍🏼', '👍🏽', '👍🏾', '👍🏿', '✅', '✔️', '✔',
])

const CANCEL = new Set([
  'לא', 'לא תודה', 'לא לבצע', 'בטל', 'ביטול', 'תבטל', 'עזוב', 'עזבי', 'אל תבצע', 'no', 'n',
  '❌', '✖️', '👎',
])

/** פקודה שהבוט מבין בלי AI, או null. */
export function parseCommand(text: string): Command | null {
  const t = normalize(text)
  if (!t) return null
  const code = /^(?:קוד|code)\s*[:-]?\s*(\d{6})$/.exec(t)
  if (code) return { type: 'link', code: code[1] }
  if (/^(הפעל|חבר) (כאן|את הקבוצה)$/.test(t)) return { type: 'bind' }
  if (/^(כבה|נתק) (כאן|את הקבוצה)$/.test(t)) return { type: 'unbind' }
  if (CONFIRM.has(t)) return { type: 'confirm' }
  if (CANCEL.has(t)) return { type: 'cancel' }
  return null
}

// ===== למי ההודעה שייכת ====================================================

export interface RouteInput {
  msg: InboundMessage
  command: Command | null
  /** השורה ב-wa_chats, אם יש */
  chat: { active: boolean; isGroup: boolean; participantsOk: boolean } | null
  /** השולח המקושר, אם יש */
  sender: { allowed: boolean; isAdmin: boolean } | null
  forwardConfigured: boolean
}

export type Route =
  | { action: 'link'; code: string }
  | { action: 'link_in_group' }
  | { action: 'bind' }
  | { action: 'unbind' }
  | { action: 'process' }
  | { action: 'blocked_group' }
  | { action: 'forward' }
  | { action: 'ignore'; reason: string }

/**
 * ההכרעה, לפי הסדר: צ'אט פרטי חייב להיות של השולח עצמו; קוד — רק בפרטי;
 * "הפעל כאן" — מנהל מקושר בקבוצה; קבוצה מחוברת — שלנו לגמרי (לא מועברת
 * הלאה), ועונים בה רק כשכל המשתתפים מוכרים; צ'אט פרטי של משתמש מקושר — שלנו;
 * כל השאר — ל-Viper One, אם הוגדרה כתובת.
 */
export function route(input: RouteInput): Route {
  const { msg, command, chat, sender } = input
  const notOurs = (): Route => (input.forwardConfigured ? { action: 'forward' } : { action: 'ignore', reason: 'not_ours' })

  if (!msg.isGroup) {
    if (!isPrivateId(msg.chatId) || msg.chatId !== msg.sender) return { action: 'ignore', reason: 'dm_mismatch' }
    if (command?.type === 'link') return { action: 'link', code: command.code }
    if (sender?.allowed) return { action: 'process' }
    return notOurs()
  }

  const bound = !!chat?.active && chat.isGroup
  const admin = !!sender?.allowed && sender.isAdmin

  if (command?.type === 'link') return bound ? { action: 'link_in_group' } : notOurs()
  if (command?.type === 'bind') {
    if (admin) return { action: 'bind' }
    return bound ? { action: 'ignore', reason: 'bind_not_admin' } : notOurs()
  }
  if (!bound) return notOurs()

  if (command?.type === 'unbind') return admin ? { action: 'unbind' } : { action: 'ignore', reason: 'unbind_not_admin' }
  if (!sender?.allowed) return { action: 'ignore', reason: 'unknown_sender' }
  if (!chat?.participantsOk) return { action: 'blocked_group' }
  return { action: 'process' }
}

// ===== תשובה ===============================================================

/** תשובה ארוכה כמה הודעות, בגבולות שורה; שורה ארוכה מדי נחתכת בגבול מילה. */
export function splitMessage(text: string, max = 3500): string[] {
  const out: string[] = []
  let cur = ''
  const push = () => {
    if (cur.trim()) out.push(cur.trimEnd())
    cur = ''
  }
  for (const rawLine of text.split('\n')) {
    let line = rawLine
    while (line.length > max) {
      const cut = line.lastIndexOf(' ', max) > max / 2 ? line.lastIndexOf(' ', max) : max
      if (cur) push()
      out.push(line.slice(0, cut).trimEnd())
      line = line.slice(cut).trimStart()
    }
    if (cur.length + line.length + 1 > max) push()
    cur = cur ? `${cur}\n${line}` : line
  }
  push()
  return out.length ? out : ['']
}

/** "0501234567" לישראלי, "+…" לאחר, ו-@lid כמו שהוא. */
export function waPhone(waId: string): string {
  const m = /^(\d+)@c\.us$/.exec(waId)
  if (!m) return waId
  if (/^972\d{8,9}$/.test(m[1])) return `0${m[1].slice(3)}`
  return `+${m[1]}`
}

// ===== זמן בישראל ==========================================================

export const TZ = 'Asia/Jerusalem'
export const HE_DAYS = ['א׳', 'ב׳', 'ג׳', 'ד׳', 'ה׳', 'ו׳', 'ש׳'] as const

const ymd = new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit' })
const hm = new Intl.DateTimeFormat('en-GB', { timeZone: TZ, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })

/** התאריך והשעה עכשיו בישראל: {date: 'YYYY-MM-DD', time: 'HH:MM', weekday: 0=ראשון}. */
export function israelNow(now: Date): { date: string; time: string; weekday: number } {
  const date = ymd.format(now)
  return { date, time: hm.format(now), weekday: weekdayOf(date) }
}

const toUtc = (iso: string) => {
  const [y, m, d] = iso.split('-').map(Number)
  return Date.UTC(y, m - 1, d)
}
const fromUtc = (ms: number) => new Date(ms).toISOString().slice(0, 10)

export const weekdayOf = (iso: string) => new Date(toUtc(iso)).getUTCDay()
export const addDays = (iso: string, n: number) => fromUtc(toUtc(iso) + n * 86_400_000)
export const daysBetween = (a: string, b: string) => Math.round((toUtc(b) - toUtc(a)) / 86_400_000)
export const isIsoDate = (v: unknown): v is string =>
  typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v) && fromUtc(toUtc(v)) === v

export type Period = 'today' | 'tomorrow' | 'this_week' | 'next_week' | 'this_month' | 'last_month' | 'next_month'

/** שבוע מראשון עד שבת, חודש קלנדרי — כמו המסכים. */
export function periodRange(period: Period, now: Date): { from: string; to: string } {
  const { date, weekday } = israelNow(now)
  const [y, m] = date.split('-').map(Number)
  const monthStart = (yy: number, mm: number) => fromUtc(Date.UTC(yy, mm - 1, 1))
  const monthEnd = (yy: number, mm: number) => fromUtc(Date.UTC(yy, mm, 0))
  switch (period) {
    case 'today':
      return { from: date, to: date }
    case 'tomorrow': {
      const t = addDays(date, 1)
      return { from: t, to: t }
    }
    case 'this_week': {
      const from = addDays(date, -weekday)
      return { from, to: addDays(from, 6) }
    }
    case 'next_week': {
      const from = addDays(date, 7 - weekday)
      return { from, to: addDays(from, 6) }
    }
    case 'this_month':
      return { from: monthStart(y, m), to: monthEnd(y, m) }
    case 'last_month':
      return m === 1 ? { from: monthStart(y - 1, 12), to: monthEnd(y - 1, 12) } : { from: monthStart(y, m - 1), to: monthEnd(y, m - 1) }
    case 'next_month':
      return m === 12 ? { from: monthStart(y + 1, 1), to: monthEnd(y + 1, 1) } : { from: monthStart(y, m + 1), to: monthEnd(y, m + 1) }
  }
}

/** "יום ה׳ 12/11" (בלי שנה כשהיא השנה הנוכחית). */
export function fmtDay(iso: string, today?: string): string {
  const [y, m, d] = iso.split('-')
  const sameYear = !today || today.slice(0, 4) === y
  return `יום ${HE_DAYS[weekdayOf(iso)]} ${Number(d)}/${Number(m)}${sameYear ? '' : `/${y}`}`
}

/** "08:00" מתוך "08:00:00"; null — '' */
export const fmtTime = (t: string | null | undefined) => (t ? t.slice(0, 5) : '')

const money = new Intl.NumberFormat('he-IL', { maximumFractionDigits: 2 })
/** "₪12,500" — ומינוס לפני הסימן */
export const fmtMoney = (n: number) => `${n < 0 ? '-' : ''}₪${money.format(Math.abs(n))}`

/** קישור wa.me לצ'אט פרטי עם הבוט, עם טקסט מוכן לשליחה. */
export function waMeLink(botWid: string, text: string): string | null {
  const m = /^(\d{7,15})@c\.us$/.exec(botWid)
  if (!m) return null
  return `https://wa.me/${m[1]}?text=${encodeURIComponent(text)}`
}
