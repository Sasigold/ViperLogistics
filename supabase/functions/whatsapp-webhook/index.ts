// whatsapp-webhook — עוזר הוואטסאפ של ViperLogistics (migration 0236, docs/WHATSAPP.md).
//
// Green API (אותו מספר בוט ש-Viper One משתמש בו) שולח לכאן כל הודעה נכנסת. כאן
// מוכרע למי היא שייכת:
//   • קבוצה שמנהל חיבר ("הפעל כאן"), או צ'אט פרטי של משתמש מקושר — שלנו. מחזירים
//     200 מיד, והעיבוד רץ ברקע: Claude עם הכלים, כל כלי בשם המשתמש (db.ts).
//   • כל הודעה נכנסת אחרת — מועברת כמו שהיא ל-Viper One (`WHATSAPP_FORWARD_URL`),
//     כדי שימשיך לעבוד אם יקושר לקבוצה אחרת. הקבוצה המחוברת לא מועברת לעולם.
//
// שינוי במערכת רץ רק אחרי "כן" של מי שביקש: הפעולות השמורות (wa_pending) רצות
// בדיוק כפי שהוצגו, בטרנזקציה אחת, ורק אחרי שההודעה "כן" אומתה מול היומן של
// Green API — כך שמי שהשיג את סוד ה-webhook עדיין לא משנה נתונים בשם אחר.
//
// סודות: WHATSAPP_WEBHOOK_SECRET (Authorization: Bearer, השדה Webhook URL token
// ב-Green API), GREENAPI_ID_INSTANCE, GREENAPI_API_TOKEN_INSTANCE, GREENAPI_API_URL
// (רשות), WHATSAPP_FORWARD_URL (רשות), ANTHROPIC_API_KEY, ASSISTANT_MODEL (רשות),
// APP_URL. SUPABASE_DB_URL / SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY מוזרקים.
//
// פריסה: --no-verify-jwt (Green API אינו שולח JWT; הסוד נבדק כאן).

import { CONFIRM_FOOTER, contextBlock } from '../_shared/assistant.ts'
import type { Msg } from '../_shared/assistantLoop.ts'
import { timingSafeEqual } from '../_shared/arco.ts'
import { israelNow, normalize, parseCommand, parseIncoming, route, splitMessage, waPhone } from '../_shared/whatsapp.ts'
import type { Command, InboundMessage, Route } from '../_shared/whatsapp.ts'
import { aiError, runTurn } from './agent.ts'
import { asUser, becomeUser, dbError, service } from './db.ts'
import { getGroupData, getMessage, greenConfigured, instanceId, sendMessage } from './greenapi.ts'
import { execOp } from './tools.ts'
import type { ExecResult, PendingOp, ToolCtx } from './tools.ts'

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void }

const APP_URL = (Deno.env.get('APP_URL') || 'https://viper-logistics.vercel.app').replace(/\/+$/, '')
const FORWARD_URL = Deno.env.get('WHATSAPP_FORWARD_URL') ?? ''
const SELF_URL = `${Deno.env.get('SUPABASE_URL')}/functions/v1/whatsapp-webhook`

/** תקציב עיבוד לכל עובד (מגבלת הפונקציה 150/400 שניות; החזקה 150) */
const BUDGET_MS = 100_000
const PARTICIPANTS_MAX_AGE_MS = 60 * 60_000
const HOURLY_LIMIT = 60

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } })

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))
const logError = (where: string) => (e: unknown) => console.error(`whatsapp-webhook ${where}:`, e)

function authorized(req: Request): boolean {
  const secret = Deno.env.get('WHATSAPP_WEBHOOK_SECRET') ?? ''
  if (!secret) return false
  // ‏Green API שולח את מה שהוגדר בשדה Webhook URL token, עם או בלי "Bearer"
  const header = (req.headers.get('authorization') ?? '').replace(/^((Bearer|Basic)\s+)+/i, '').trim()
  // ‏?token= נתמך רק כגיבוי; ה-URL נשמר ביומנים, ולכן עדיף ה-header
  const query = new URL(req.url).searchParams.get('token') ?? ''
  return (!!header && timingSafeEqual(header, secret)) || (!!query && timingSafeEqual(query, secret))
}

// ===== העובדות על ההודעה ====================================================

interface ChatFacts {
  active: boolean
  isGroup: boolean
  participantsOk: boolean
  participants: unknown[]
  checkedAt: string | null
  noticeAt: string | null
  name: string | null
}

interface SenderFacts {
  linkId: string
  profileId: string
  userId: string | null
  fullName: string
  isAdmin: boolean
  allowed: boolean
}

interface Facts {
  chat: ChatFacts | null
  sender: SenderFacts | null
}

async function loadFacts(chatId: string, waId: string): Promise<Facts> {
  return await service(async (tx) => {
    const [c] = await tx`
      select active, is_group, participants_ok, participants, participants_checked_at::text as checked_at,
             blocked_notice_at::text as notice_at, name
        from wa_chats where chat_id = ${chatId}`
    const [s] = await tx`select * from app.wa_sender(${waId})`
    return {
      chat: c
        ? {
            active: c.active as boolean,
            isGroup: c.is_group as boolean,
            participantsOk: c.participants_ok as boolean,
            participants: (c.participants ?? []) as unknown[],
            checkedAt: (c.checked_at as string | null) ?? null,
            noticeAt: (c.notice_at as string | null) ?? null,
            name: (c.name as string | null) ?? null,
          }
        : null,
      sender: s
        ? {
            linkId: s.link_id as string,
            profileId: s.profile_id as string,
            userId: (s.user_id as string | null) ?? null,
            fullName: s.full_name as string,
            isAdmin: s.is_admin as boolean,
            allowed: s.allowed as boolean,
          }
        : null,
    }
  })
}

let knownBot = ''
async function rememberBot(wid: string) {
  if (!wid || wid === knownBot) return
  knownBot = wid
  await service((tx) => tx`
    insert into app_settings (key, value) values ('whatsapp.bot', ${tx.json({ wid, phone: waPhone(wid) })})
    on conflict (key) do update set value = excluded.value, updated_at = now()
     where app_settings.value is distinct from excluded.value`)
}

/** ההודעה נרשמת (פעם אחת לכל idMessage). מחזיר false כשכבר נרשמה. */
async function recordInbound(msg: InboundMessage, facts: Facts, r: Route, command: Command | null): Promise<boolean> {
  return await service(async (tx) => {
    if (r.action === 'process' && !msg.isGroup) await tx`select app.wa_chat_dm(${msg.chatId}, ${msg.senderName || null})`
    const body = command?.type === 'link' ? 'קוד ******' : msg.text
    const rows = await tx`
      insert into wa_messages (message_id, direction, chat_id, wa_id, profile_id, kind, body, status, meta, sent_at)
      values (${msg.idMessage}, 'in', ${msg.chatId}, ${msg.sender}, ${facts.sender?.profileId ?? null},
              ${command ? 'command' : msg.kind}, ${body}, ${r.action === 'process' ? 'queued' : 'received'},
              ${tx.json({ route: r.action, msg: { ...msg, text: body } } as never)},
              to_timestamp(${msg.timestamp || Math.floor(Date.now() / 1000)}))
      on conflict (message_id) do nothing
      returning id`
    return rows.length > 0
  })
}

async function setStatus(messageId: string, status: string, extra: Record<string, unknown> = {}, error: string | null = null) {
  await service((tx) => tx`
    update wa_messages
       set status = ${status}, error = ${error}, processed_at = now(),
           meta = meta || ${tx.json(extra as never)}
     where message_id = ${messageId}`)
}

// ===== תשובה ================================================================

async function say(to: { chatId: string; idMessage: string }, text: string, profileId: string | null = null) {
  for (const part of splitMessage(text)) {
    let id: string | null = null
    let err: string | null = null
    try {
      id = await sendMessage(to.chatId, part, to.idMessage)
    } catch (e) {
      err = e instanceof Error ? e.message : String(e)
      logError('send')(e)
    }
    await service((tx) => tx`
      insert into wa_messages (message_id, direction, chat_id, profile_id, kind, body, status, error, processed_at)
      values (${id}, 'out', ${to.chatId}, ${profileId}, 'text', ${part}, ${id ? 'sent' : 'failed'}, ${err}, now())
      on conflict (message_id) do nothing`)
  }
}

/** ההודעה כפי ש-Green API שמר אותה ביומן — אותו שולח, אותו צ'אט, אותו טקסט */
async function verified(msg: InboundMessage): Promise<boolean> {
  for (const wait of [0, 2_000, 4_000, 8_000, 15_000, 25_000]) {
    if (wait) await sleep(wait)
    try {
      const m = await getMessage(msg.chatId, msg.idMessage)
      if (!m) continue
      const sender = m.senderId || m.chatId
      return m.type === 'incoming' && m.chatId === msg.chatId && sender === msg.sender &&
        normalize(m.textMessage ?? '') === normalize(msg.text)
    } catch (e) {
      logError('getMessage')(e)
    }
  }
  return false
}

/** המשתתפים בקבוצה, נבדקים מחדש ונשמרים. מחזיר אם מותר לענות בה. */
async function refreshParticipants(chatId: string, botWid: string): Promise<{ ok: boolean; participants: unknown[] }> {
  const g = await getGroupData(chatId)
  const ok = await service(async (tx) => {
    const [r] = await tx`select app.wa_chat_participants_set(${chatId}, ${tx.json(g.participants as never)}, ${botWid}) as ok`
    return r.ok === true
  })
  return { ok, participants: g.participants }
}

const stale = (at: string | null, maxAgeMs: number) => !at || Date.now() - Date.parse(at) > maxAgeMs

// ===== קישור וחיבור =========================================================

async function doLink(msg: InboundMessage, code: string) {
  const r = await service(async (tx) => {
    const [x] = await tx`select app.wa_link_redeem(${code}, ${msg.sender}, ${msg.senderName || null}) as r`
    return x.r as { ok: boolean; reason?: string; full_name?: string }
  })
  if (r.ok) {
    await service((tx) => tx`select app.wa_chat_dm(${msg.chatId}, ${msg.senderName || null})`)
    await say(msg, `✅ שלום ${r.full_name ?? ''}! הוואטסאפ שלך מחובר עכשיו ל-ViperLogistics.\n\n` +
      'אפשר לשאול אותי כאן, בפרטי, או בקבוצה שמנהל חיבר. למשל:\n• מה יש מחר?\n• כמה הכנסות החודש?\n' +
      '• תזיז את ההקמה של כהן לשלישי ב-10:00\n\nכל שינוי במערכת יחכה ל"כן" שלך.')
    await setStatus(msg.idMessage, 'answered', { linked: true })
    return
  }
  const text: Record<string, string> = {
    bad_code: 'הקוד לא תקין או שפג תוקפו. בקש קוד חדש ב-ViperLogistics, בעמוד "התראות" ← "חבר את הוואטסאפ שלי".',
    too_many: 'היו יותר מדי ניסיונות מהמספר הזה. נסה שוב בעוד שעה.',
    not_allowed: 'לחשבון הזה אין הרשאה לעוזר הוואטסאפ. מנהל המערכת יכול להפעיל אותה בהרשאות.',
  }
  if (text[r.reason ?? '']) await say(msg, text[r.reason ?? ''])
  await setStatus(msg.idMessage, 'answered', { linked: false, reason: r.reason })
}

async function doLinkInGroup(msg: InboundMessage, code: string) {
  // הקוד נחשף לכל חברי הקבוצה — הוא נשרף מיד, כדי שאף אחד אחר לא יפדה אותו
  await service((tx) => tx`
    update wa_link_codes set used_at = now() where code_hash = app.wa_code_hash(${code}) and used_at is null`)
  await say(msg, 'את הקוד שולחים בצ\'אט פרטי עם הבוט — כאן כל חברי הקבוצה רואים אותו. ' +
    'ביטלתי את הקוד הזה; בקש קוד חדש בעמוד "התראות".')
  await setStatus(msg.idMessage, 'answered', { code_burned: true })
}

async function doBind(msg: InboundMessage, facts: Facts) {
  if (!(await verified(msg))) {
    await say(msg, 'לא הצלחתי לאמת את ההודעה מול וואטסאפ. כתוב "הפעל כאן" שוב בעוד רגע.')
    await setStatus(msg.idMessage, 'failed', {}, 'not verified')
    return
  }
  const g = await getGroupData(msg.chatId)
  const r = await service(async (tx) => {
    const [x] = await tx`
      select app.wa_chat_bind(${msg.chatId}, ${g.subject ?? msg.chatName ?? null}, true, ${facts.sender!.profileId}::uuid,
                              ${tx.json(g.participants as never)}, ${msg.botWid}) as r`
    return x.r as { ok: boolean; participants_ok: boolean }
  })
  if (r.participants_ok) {
    await say(msg, '✅ מעכשיו אני עונה בקבוצה הזו, בהרשאות של מי שכותב.\n\n' +
      'אפשר לשאול למשל "מה יש מחר?" או "כמה הכנסות החודש?", ולבקש שינויים — כל שינוי יחכה ל"כן". ' +
      'לכיבוי: "כבה כאן".')
  } else {
    const strangers = await strangersOf(g.participants, msg.botWid)
    await say(msg, 'חיברתי את הקבוצה, אבל אני לא אענה בה עדיין: יש בה משתתפים שלא מקושרים ל-ViperLogistics' +
      (strangers.length ? ` (${strangers.join(', ')})` : '') +
      ', וכל מה שאכתוב כאן גלוי להם. כשכולם יהיו מקושרים (או יצאו מהקבוצה) — אענה כאן.')
  }
  await setStatus(msg.idMessage, 'answered', { bound: true, participants_ok: r.participants_ok })
}

async function strangersOf(participants: unknown[], botWid: string): Promise<string[]> {
  const ids = (participants as { id?: string; phoneNumber?: string; lid?: string }[])
    .filter((p) => p.id !== botWid && p.phoneNumber !== botWid)
  return await service(async (tx) => {
    const out: string[] = []
    for (const p of ids) {
      const keys = [p.id, p.phoneNumber, p.lid].filter((x): x is string => !!x)
      const [k] = await tx`
        select exists (select 1 from wa_links l where l.revoked_at is null
                          and l.wa_id = any (array(select jsonb_array_elements_text(${tx.json(keys)})))
                          and app.wa_allowed(l.profile_id)) as known`
      if (!k.known) out.push(waPhone(p.phoneNumber || p.id || p.lid || '?'))
    }
    return out.slice(0, 5)
  })
}

async function doUnbind(msg: InboundMessage, facts: Facts) {
  if (!(await verified(msg))) {
    await say(msg, 'לא הצלחתי לאמת את ההודעה מול וואטסאפ. כתוב "כבה כאן" שוב בעוד רגע.')
    await setStatus(msg.idMessage, 'failed', {}, 'not verified')
    return
  }
  await service((tx) => tx`select app.wa_chat_unbind(${msg.chatId}, ${facts.sender!.profileId}::uuid)`)
  await say(msg, 'כיביתי. לא אענה יותר בקבוצה הזו (אפשר להפעיל שוב: "הפעל כאן").')
  await setStatus(msg.idMessage, 'answered', { unbound: true })
}

async function doBlocked(msg: InboundMessage, facts: Facts) {
  if (stale(facts.chat?.checkedAt ?? null, 10 * 60_000)) {
    const r = await refreshParticipants(msg.chatId, msg.botWid)
    if (r.ok) {
      await service((tx) => tx`update wa_messages set status = 'queued' where message_id = ${msg.idMessage}`)
      await drain(msg.chatId)
      return
    }
  }
  if (stale(facts.chat?.noticeAt ?? null, 24 * 60 * 60_000)) {
    await say(msg, 'אני לא עונה בקבוצה הזו כרגע: יש בה משתתפים שלא מקושרים ל-ViperLogistics, וכל מה שאכתוב כאן ' +
      'גלוי להם. אפשר לכתוב לי בפרטי, או לקשר אותם (עמוד "התראות" ← "חבר את הוואטסאפ שלי").')
    await service((tx) => tx`update wa_chats set blocked_notice_at = now() where chat_id = ${msg.chatId}`)
  }
  await setStatus(msg.idMessage, 'ignored', { blocked: true })
}

// ===== התור =================================================================

/**
 * הודעה אחת בכל רגע לכל צ'אט: מי שתפס את החזקה מעבד את התור לפי הסדר, והאחרים
 * רק מוסיפים אליו. מה שנשאר כשנגמר הזמן — עובר לעובד חדש (קריאה לעצמנו).
 */
async function drain(chatId: string): Promise<void> {
  const deadline = Date.now() + BUDGET_MS
  const leased = await service((tx) => tx`
    update wa_chats set busy_until = now() + interval '150 seconds'
     where chat_id = ${chatId} and (busy_until is null or busy_until < now())
    returning chat_id`)
  if (!leased.length) return

  try {
    while (Date.now() < deadline - 30_000) {
      const [next] = await service((tx) => tx`
        update wa_messages set status = 'processing'
         where id = (select id from wa_messages
                      where chat_id = ${chatId} and direction = 'in' and status = 'queued'
                      order by created_at limit 1
                      for update skip locked)
        returning message_id, meta`)
      if (!next) break
      const msg = (next.meta as { msg: InboundMessage }).msg
      try {
        await processOne(msg, deadline)
      } catch (e) {
        logError('process')(e)
        await say(msg, '❌ משהו השתבש בעיבוד ההודעה. נסה שוב בעוד רגע.')
        await setStatus(msg.idMessage, 'failed', {}, e instanceof Error ? e.message : String(e))
      }
      await service((tx) => tx`update wa_chats set busy_until = now() + interval '150 seconds' where chat_id = ${chatId}`)
    }
  } finally {
    await service((tx) => tx`update wa_chats set busy_until = null where chat_id = ${chatId}`)
  }

  const [left] = await service((tx) => tx`
    select count(*)::int as n from wa_messages where chat_id = ${chatId} and direction = 'in' and status = 'queued'`)
  if ((left?.n as number) > 0) {
    if (Date.now() < deadline - 30_000) return await drain(chatId)
    await fetch(SELF_URL, {
      method: 'POST',
      headers: { authorization: `Bearer ${Deno.env.get('WHATSAPP_WEBHOOK_SECRET')}`, 'x-wa-drain': chatId },
      body: '{}',
    }).catch(logError('self-drain'))
  }
}

interface PendingRow {
  id: string
  preview: string[]
  expires_at: string
}

async function processOne(msg: InboundMessage, deadline: number): Promise<void> {
  const facts = await loadFacts(msg.chatId, msg.sender)
  const sender = facts.sender
  if (!sender?.allowed || !sender.userId) {
    await setStatus(msg.idMessage, 'ignored', { reason: 'not_allowed' })
    return
  }

  // קבוצה: המשתתפים נבדקים מחדש כל שעה
  let participants = facts.chat?.participants ?? []
  if (msg.isGroup) {
    if (!facts.chat?.active) {
      await setStatus(msg.idMessage, 'ignored', { reason: 'unbound' })
      return
    }
    let ok = facts.chat.participantsOk
    if (stale(facts.chat.checkedAt, PARTICIPANTS_MAX_AGE_MS)) {
      const r = await refreshParticipants(msg.chatId, msg.botWid)
      ok = r.ok
      participants = r.participants
    }
    if (!ok) {
      await doBlocked(msg, { ...facts, chat: { ...facts.chat, participantsOk: false, checkedAt: new Date().toISOString() } })
      return
    }
  }

  if (msg.kind === 'audio') {
    await say(msg, 'עדיין אני לא שומע הודעות קוליות — כתוב לי בבקשה.', sender.profileId)
    await setStatus(msg.idMessage, 'answered', { audio: true })
    return
  }

  const pending = await service(async (tx) => {
    const [p] = await tx`
      select id, preview, expires_at::text as expires_at from wa_pending
       where chat_id = ${msg.chatId} and profile_id = ${sender.profileId}::uuid and status = 'pending'`
    return (p as unknown as PendingRow | undefined) ?? null
  })

  const command = msg.kind === 'text' ? parseCommand(msg.text) : null
  if (pending && command?.type === 'confirm') return await confirm(msg, sender, pending)
  if (pending && command?.type === 'cancel') {
    await service((tx) => tx`
      update wa_pending set status = 'cancelled', finished_at = now() where id = ${pending.id}::uuid and status = 'pending'`)
    await say(msg, 'בוטל — לא שיניתי כלום.', sender.profileId)
    await setStatus(msg.idMessage, 'answered', { cancelled: pending.id })
    return
  }

  const [count] = await service((tx) => tx`
    select count(*)::int as n from wa_messages
     where profile_id = ${sender.profileId}::uuid and direction = 'in'
       and status in ('answered', 'failed', 'processing') and created_at > now() - interval '1 hour'`)
  if ((count?.n as number) > HOURLY_LIMIT) {
    await say(msg, `הגעת למגבלה של ${HOURLY_LIMIT} הודעות בשעה. נסה שוב מאוחר יותר.`, sender.profileId)
    await setStatus(msg.idMessage, 'ignored', { reason: 'rate_limit' })
    return
  }

  const anthropicKey = Deno.env.get('ANTHROPIC_API_KEY') ?? ''
  if (!anthropicKey) {
    await say(msg, '⚠️ העוזר עוד לא הוגדר עד הסוף (חסר מפתח AI). פנה למנהל המערכת.', sender.profileId)
    await setStatus(msg.idMessage, 'failed', {}, 'not_configured')
    return
  }

  await aiTurn(msg, sender, facts, participants, pending, anthropicKey, deadline)
}

async function aiTurn(
  msg: InboundMessage,
  sender: SenderFacts,
  facts: Facts,
  participants: unknown[],
  pending: PendingRow | null,
  anthropicKey: string,
  deadline: number,
) {
  const uid = sender.userId!
  const me = await asUser(uid, 'read', async (tx) => {
    const [r] = await tx`select get_my_permissions() as me`
    return r.me as { capabilities?: Record<string, boolean>; profile?: { is_admin?: boolean } } | null
  })
  if (!me) {
    await setStatus(msg.idMessage, 'ignored', { reason: 'no_profile' })
    return
  }
  const isAdmin = me.profile?.is_admin === true

  const history = await service(async (tx) => {
    const rows = await tx`
      select direction, body from (
        select direction, body, created_at from wa_messages
         where chat_id = ${msg.chatId} and profile_id = ${sender.profileId}::uuid
           and message_id is distinct from ${msg.idMessage}
           and body is not null and body <> '' and kind <> 'command'
           and status in ('answered', 'sent')
           and created_at > now() - interval '8 hours'
         order by created_at desc
         limit 12) x
       order by created_at`
    return rows.map((r) => ({ role: r.direction === 'in' ? 'user' : 'assistant', content: String(r.body) }) as Msg)
  })
  // השיחה חייבת להתחיל בהודעה של המשתמש
  while (history.length && history[0].role === 'assistant') history.shift()

  const now = new Date()
  const { date, time } = israelNow(now)
  const ctx: ToolCtx = {
    uid,
    profileId: sender.profileId,
    isAdmin,
    offered: new Set(),
    chat: { id: msg.chatId, isGroup: msg.isGroup, participants, botWid: msg.botWid },
    today: date,
    now,
    appUrl: APP_URL,
    file: msg.file,
    anthropicKey,
  }
  const context = contextBlock({
    nowDate: date,
    nowTime: time,
    name: sender.fullName,
    isAdmin,
    chat: msg.isGroup ? 'group' : 'private',
    chatName: facts.chat?.name ?? (msg.chatName || null),
    pending: pending?.preview ?? null,
    file: msg.file ? { name: msg.file.name, mime: msg.file.mime } : null,
  })

  let result
  try {
    result = await runTurn({
      ctx,
      caps: me.capabilities ?? {},
      history,
      context,
      userText: msg.text || (msg.file ? '(קובץ בלי כיתוב)' : ''),
      deadline: Math.min(deadline - 20_000, Date.now() + 75_000),
    })
  } catch (e) {
    logError('ai')(e)
    await say(msg, `❌ ${aiError(e)}.`, sender.profileId)
    await setStatus(msg.idMessage, 'failed', {}, e instanceof Error ? e.message : String(e))
    return
  }

  let reply = result.text
  if (result.pending.length) {
    const preview = result.pending.flatMap((p) => p.preview)
    await service(async (tx) => {
      await tx`
        update wa_pending set status = 'superseded', finished_at = now()
         where chat_id = ${msg.chatId} and profile_id = ${sender.profileId}::uuid and status = 'pending'`
      await tx`
        insert into wa_pending (chat_id, profile_id, ops, preview, request_message_id)
        values (${msg.chatId}, ${sender.profileId}::uuid, ${tx.json(result.pending as never)},
                array(select jsonb_array_elements_text(${tx.json(preview)})), ${msg.idMessage})`
    })
    reply = [result.text, preview.join('\n'), CONFIRM_FOOTER].filter(Boolean).join('\n\n')
  }
  if (!reply) {
    reply = {
      deadline: 'לקח לי יותר מדי זמן. נסה לנסח את הבקשה בקצרה, או לפצל אותה.',
      refusal: 'לא אוכל לעזור בזה.',
      max_rounds: 'לא הצלחתי להשלים את הבקשה. נסה לנסח אותה אחרת.',
      max_tokens: 'התשובה נקטעה. נסה לבקש פחות בבת אחת.',
      end: 'לא הבנתי. אפשר לנסח אחרת?',
    }[result.stop]
  }

  await say(msg, reply, sender.profileId)
  await setStatus(msg.idMessage, 'answered', {
    model: result.model,
    usage: result.usage,
    tools: result.tools,
    stop: result.stop,
    rounds: result.rounds,
    prepared: result.pending.length,
  })
}

// ===== "כן" ==================================================================

class AlreadyHandled extends Error {}

async function confirm(msg: InboundMessage, sender: SenderFacts, pending: PendingRow) {
  const sentAt = msg.timestamp ? msg.timestamp * 1000 : Date.now()
  if (sentAt > Date.parse(pending.expires_at) || Date.now() > Date.parse(pending.expires_at) + 60_000) {
    await service((tx) => tx`
      update wa_pending set status = 'expired', finished_at = now() where id = ${pending.id}::uuid and status = 'pending'`)
    await say(msg, 'עברו יותר מ-15 דקות, אז השינוי כבר לא בתוקף. בקש אותו שוב.', sender.profileId)
    await setStatus(msg.idMessage, 'answered', { expired: pending.id })
    return
  }

  if (!(await verified(msg))) {
    await say(msg, 'לא הצלחתי לאמת את האישור מול וואטסאפ. שלח *כן* שוב בעוד רגע.', sender.profileId)
    await setStatus(msg.idMessage, 'failed', {}, 'confirm not verified')
    return
  }

  const today = israelNow(new Date()).date
  let results: ExecResult[] = []
  let ops: PendingOp[] = []
  try {
    ;({ results, ops } = await service(async (tx) => {
      const claimed = await tx`
        update wa_pending set status = 'running', confirm_message_id = ${msg.idMessage}
         where id = ${pending.id}::uuid and status = 'pending'
         returning ops`
      if (!claimed.length) throw new AlreadyHandled()
      const ops = claimed[0].ops as PendingOp[]
      await becomeUser(tx, sender.userId!)
      const out: ExecResult[] = []
      for (const op of ops) out.push(await execOp(tx, { profileId: sender.profileId, today }, op, false))
      await tx.unsafe('reset role')
      await tx`
        update wa_pending set status = 'done', finished_at = now(), result = ${tx.json(out as never)}
         where id = ${pending.id}::uuid`
      return { results: out, ops }
    }))
  } catch (e) {
    if (e instanceof AlreadyHandled) {
      await say(msg, 'השינוי הזה כבר טופל.', sender.profileId)
      await setStatus(msg.idMessage, 'answered', { already: pending.id })
      return
    }
    logError('confirm')(e)
    const why = dbError(e)
    await service((tx) => tx`
      update wa_pending set status = 'failed', error = ${why}, finished_at = now()
       where id = ${pending.id}::uuid and status = 'pending'`)
    await say(msg, `❌ לא בוצע: ${why}\nלא שיניתי כלום.`, sender.profileId)
    await setStatus(msg.idMessage, 'answered', { failed: pending.id }, why)
    return
  }

  const links = [...new Set(ops.flatMap((o) => o.links ?? []))].slice(0, 3)
  await say(msg, ['✅ בוצע:', ...results.map((r) => r.done), ...links].join('\n'), sender.profileId)
  await setStatus(msg.idMessage, 'answered', { confirmed: pending.id })
}

// ===== הכניסה ===============================================================

async function handle(msg: InboundMessage, facts: Facts, r: Route) {
  switch (r.action) {
    case 'link':
      return await doLink(msg, r.code)
    case 'link_in_group':
      return await doLinkInGroup(msg, (parseCommand(msg.text) as { code: string }).code)
    case 'bind':
      return await doBind(msg, facts)
    case 'unbind':
      return await doUnbind(msg, facts)
    case 'blocked_group':
      return await doBlocked(msg, facts)
    case 'process':
      return await drain(msg.chatId)
  }
}

async function forward(raw: string): Promise<Response> {
  try {
    const res = await fetch(FORWARD_URL, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: raw,
      signal: AbortSignal.timeout(25_000),
    })
    return new Response(await res.text(), {
      status: res.status,
      headers: { 'content-type': res.headers.get('content-type') ?? 'application/json' },
    })
  } catch (e) {
    logError('forward')(e)
    return json({ error: 'forward failed' }, 502)
  }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('method not allowed', { status: 405, headers: { Allow: 'POST' } })
  if (!authorized(req)) return json({ error: 'unauthorized' }, 401)

  // המשך עיבוד התור בעובד חדש (drain קרא לעצמו)
  const drainChat = req.headers.get('x-wa-drain')
  if (drainChat) {
    EdgeRuntime.waitUntil(drain(drainChat).catch(logError('drain')))
    return json({ ok: true })
  }

  const raw = await req.text()
  let body: unknown
  try {
    body = JSON.parse(raw)
  } catch {
    return json({ error: 'invalid json' }, 400)
  }

  const b = (body ?? {}) as { typeWebhook?: string; instanceData?: { idInstance?: unknown } }
  const inst = String(b.instanceData?.idInstance ?? '')
  if (instanceId() && inst && inst !== instanceId()) return json({ error: 'unknown instance' }, 403)

  const msg = parseIncoming(body)
  // סטטוסים, הודעות יוצאות ושאר האירועים: Viper One מתעלם מהם בכל מקרה
  if (!msg) return json({ ok: true, ignored: b.typeWebhook ?? 'unknown' })

  try {
    EdgeRuntime.waitUntil(rememberBot(msg.botWid).catch(logError('bot')))
    const facts = await loadFacts(msg.chatId, msg.sender)
    const command = msg.kind === 'text' ? parseCommand(msg.text) : null
    const r = route({ msg, command, chat: facts.chat, sender: facts.sender, forwardConfigured: !!FORWARD_URL })

    if (r.action === 'forward') return await forward(raw)
    if (r.action === 'ignore') {
      if (r.reason === 'unknown_sender' && facts.chat && stale(facts.chat.checkedAt, 5 * 60_000)) {
        // מישהו חדש כותב בקבוצה המחוברת: אולי הצטרף משתתף — בודקים
        EdgeRuntime.waitUntil(refreshParticipants(msg.chatId, msg.botWid).catch(logError('participants')))
      }
      return json({ ok: true, ignored: r.reason })
    }
    // ריאקשן, עריכה וכו' בצ'אט שלנו — לא בקשה ולא אישור
    if (r.action === 'process' && !['text', 'file', 'audio'].includes(msg.kind)) {
      return json({ ok: true, ignored: msg.kind })
    }
    if (!greenConfigured()) {
      console.error('whatsapp-webhook: GREENAPI_ID_INSTANCE / GREENAPI_API_TOKEN_INSTANCE are not set')
      return json({ ok: true, ignored: 'not_configured' })
    }

    if (!(await recordInbound(msg, facts, r, command))) return json({ ok: true, duplicate: true })
    EdgeRuntime.waitUntil(handle(msg, facts, r).catch(logError('handle')))
    return json({ ok: true })
  } catch (e) {
    logError('request')(e)
    // ‏Green API ינסה שוב בעוד דקה
    return json({ error: 'internal' }, 500)
  }
})
