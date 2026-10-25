// Green API — אותו מספר בוט ש-Viper One משתמש בו (0236).
//
// סודות: GREENAPI_ID_INSTANCE, GREENAPI_API_TOKEN_INSTANCE, ו-GREENAPI_API_URL
// (רשות; instance חדש מקבל כתובת משלו בקונסולה, למשל https://7103.api.greenapi.com).

const base = () => (Deno.env.get('GREENAPI_API_URL') || 'https://api.green-api.com').replace(/\/+$/, '')
export const instanceId = () => Deno.env.get('GREENAPI_ID_INSTANCE') ?? ''
const token = () => Deno.env.get('GREENAPI_API_TOKEN_INSTANCE') ?? ''

export const greenConfigured = () => !!instanceId() && !!token()

async function call(method: string, body: unknown, timeoutMs = 15_000): Promise<Record<string, unknown> | null> {
  const res = await fetch(`${base()}/waInstance${instanceId()}/${method}/${token()}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(timeoutMs),
  })
  if (res.status === 404) return null
  if (!res.ok) throw new Error(`green-api ${method}: ${res.status} ${(await res.text().catch(() => '')).slice(0, 200)}`)
  const text = await res.text()
  return text ? (JSON.parse(text) as Record<string, unknown>) : {}
}

/** שולח הודעה (בציטוט ההודעה שאליה היא עונה) ומחזיר את המזהה שלה */
export async function sendMessage(chatId: string, message: string, quotedMessageId?: string | null): Promise<string | null> {
  const r = await call('sendMessage', { chatId, message, ...(quotedMessageId ? { quotedMessageId } : {}) })
  return typeof r?.idMessage === 'string' ? r.idMessage : null
}

export interface StoredMessage {
  type?: string
  chatId?: string
  senderId?: string
  textMessage?: string
  typeMessage?: string
  timestamp?: number
}

/** ההודעה כפי ש-Green API שמר אותה ביומן, או null כשאינה (עדיין) שם */
export async function getMessage(chatId: string, idMessage: string): Promise<StoredMessage | null> {
  const r = await call('getMessage', { chatId, idMessage })
  return r && Object.keys(r).length ? (r as StoredMessage) : null
}

export interface Participant {
  id: string
  lid?: string
  phoneNumber?: string
}

export async function getGroupData(groupId: string): Promise<{ subject: string | null; participants: Participant[] }> {
  const r = await call('getGroupData', { groupId })
  const list = Array.isArray(r?.participants) ? (r!.participants as Record<string, unknown>[]) : []
  return {
    subject: typeof r?.subject === 'string' ? r.subject : null,
    participants: list.map((p) => ({
      id: String(p.id ?? ''),
      lid: typeof p.lid === 'string' ? p.lid : undefined,
      phoneNumber: typeof p.phoneNumber === 'string' ? p.phoneNumber : undefined,
    })),
  }
}

/** הקובץ שצורף להודעה (קישור זמני של Green API), עד `maxBytes` */
export async function download(url: string, maxBytes: number): Promise<Uint8Array> {
  const res = await fetch(url, { signal: AbortSignal.timeout(30_000) })
  if (!res.ok) throw new Error(`הקובץ לא ירד (${res.status})`)
  const len = Number(res.headers.get('content-length') ?? 0)
  if (len > maxBytes) throw new Error('הקובץ גדול מדי')
  const bytes = new Uint8Array(await res.arrayBuffer())
  if (bytes.length > maxBytes) throw new Error('הקובץ גדול מדי')
  return bytes
}
