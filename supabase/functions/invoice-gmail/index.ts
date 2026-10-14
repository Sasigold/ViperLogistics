// invoice-gmail — connects a Gmail account and pulls supplier invoices from it
// (migration 0233 §7).
//
//   POST {action: 'auth_url', return_to}   admin JWT → Google consent URL
//   GET  /invoice-gmail/callback           Google redirects here after consent;
//                                          the refresh token goes straight into
//                                          `invoice_gmail_accounts` (service role)
//   POST {action: 'sync', account_id?}     admin JWT, or `x-sync-secret` from
//                                          pg_cron (`app.invoice_gmail_kick`)
//
// Sync: for every connected account, search Gmail for messages with a PDF or
// image attachment since the last full scan (first time: 60 days), skip
// messages already checked (`invoice_gmail_messages`), read each attachment with
// Claude, and keep it only when it is an invoice issued to one of the companies
// in `invoice_companies` (matched in SQL by tax id or name). One call handles a
// bounded amount of work and answers `more: true` when there is more; the
// screen calls again, and the next cron run continues.
//
// Scope: gmail.readonly — the function never sends, moves or labels mail.
//
// Secrets: GOOGLE_OAUTH_CLIENT_ID, GOOGLE_OAUTH_CLIENT_SECRET (also signs the
// OAuth state), INVOICE_GMAIL_SYNC_SECRET (cron), ANTHROPIC_API_KEY,
// optional INVOICE_MODEL, optional INVOICE_GMAIL_REDIRECT_URI.
//
// Deploy with --no-verify-jwt: Google's redirect carries no JWT. Every POST
// checks the caller itself.

import { createClient } from 'npm:@supabase/supabase-js@2'
import Anthropic from 'npm:@anthropic-ai/sdk@0.129.0'
import {
  base64UrlToBytes,
  findAttachments,
  gmailQuery,
  header,
  safeReturnUrl,
  sha256Hex,
  signState,
  verifyState,
} from '../_shared/invoice.ts'
import type { GmailPart } from '../_shared/invoice.ts'
import { imageToPdf, invoiceClient, invoiceModel, readError, readInvoicePdf } from '../_shared/invoiceRead.ts'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const SCOPES = 'https://www.googleapis.com/auth/gmail.readonly'
const GMAIL = 'https://gmail.googleapis.com/gmail/v1/users/me'
const TOKEN_URL = 'https://oauth2.googleapis.com/token'

/** אחרי זה הריצה עוצרת ומחזירה more — הרחק מגבול הזמן של הפונקציה */
const TIME_BUDGET_MS = 100_000
const MAX_LISTED = 500
const MAX_ATTACHMENTS_PER_MESSAGE = 5

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })
}

function redirect(to: string, params: Record<string, string>) {
  const u = new URL(to)
  for (const [k, v] of Object.entries(params)) u.searchParams.set(k, v)
  return new Response(null, { status: 302, headers: { Location: u.toString() } })
}

const env = (k: string) => Deno.env.get(k) ?? ''
const supabaseUrl = () => env('SUPABASE_URL')
const redirectUri = () => env('INVOICE_GMAIL_REDIRECT_URI') || `${supabaseUrl()}/functions/v1/invoice-gmail/callback`
const service = () => createClient(supabaseUrl(), env('SUPABASE_SERVICE_ROLE_KEY'))

class GoogleError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code?: string,
  ) {
    super(message)
  }
}

async function google<T>(url: string, init: RequestInit): Promise<T> {
  const res = await fetch(url, init)
  const body = await res.json().catch(() => ({}))
  if (!res.ok) {
    const b = body as { error?: string | { message?: string; status?: string }; error_description?: string }
    const code = typeof b.error === 'string' ? b.error : b.error?.status
    const msg = typeof b.error === 'string' ? (b.error_description ?? b.error) : (b.error?.message ?? res.statusText)
    throw new GoogleError(msg, res.status, code)
  }
  return body as T
}

async function accessToken(refreshToken: string): Promise<string> {
  const r = await google<{ access_token: string }>(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: env('GOOGLE_OAUTH_CLIENT_ID'),
      client_secret: env('GOOGLE_OAUTH_CLIENT_SECRET'),
      refresh_token: refreshToken,
      grant_type: 'refresh_token',
    }),
  })
  return r.access_token
}

/** מי קורא: מנהל מערכת לפי ה-JWT שלו. מחזיר את מזהה הפרופיל, או null. */
async function adminCaller(req: Request): Promise<string | null> {
  const auth = req.headers.get('Authorization') ?? ''
  if (!auth) return null
  const asUser = createClient(supabaseUrl(), env('SUPABASE_ANON_KEY'), { global: { headers: { Authorization: auth } } })
  const { data: me, error } = await asUser.rpc('get_my_permissions')
  if (error || !me) return null
  const p = me.profile as { id: string; is_admin: boolean }
  return p.is_admin ? p.id : null
}

/* ===== OAuth ===== */

async function authUrl(profileId: string, returnTo: unknown) {
  const r = safeReturnUrl(returnTo)
  if (!r) return json({ error: 'כתובת חזרה לא תקינה' }, 400)
  const state = await signState({ p: profileId, r, e: Date.now() + 15 * 60_000 }, env('GOOGLE_OAUTH_CLIENT_SECRET'))
  const u = new URL('https://accounts.google.com/o/oauth2/v2/auth')
  u.searchParams.set('client_id', env('GOOGLE_OAUTH_CLIENT_ID'))
  u.searchParams.set('redirect_uri', redirectUri())
  u.searchParams.set('response_type', 'code')
  u.searchParams.set('scope', SCOPES)
  u.searchParams.set('access_type', 'offline')
  // תמיד מסך הסכמה — אחרת Google לא מחזיר refresh token בחיבור חוזר
  u.searchParams.set('prompt', 'consent')
  u.searchParams.set('include_granted_scopes', 'true')
  u.searchParams.set('state', state)
  return json({ url: u.toString() })
}

async function callback(url: URL) {
  const state = await verifyState(url.searchParams.get('state') ?? '', env('GOOGLE_OAUTH_CLIENT_SECRET'), Date.now())
  if (!state) return new Response('החיבור פג או אינו תקין. חזרו למערכת ונסו שוב.', { status: 400 })
  if (url.searchParams.get('error')) return redirect(state.r, { gmail: 'denied' })
  const code = url.searchParams.get('code')
  if (!code) return redirect(state.r, { gmail: 'error' })
  try {
    const tokens = await google<{ access_token: string; refresh_token?: string; scope?: string }>(TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code,
        client_id: env('GOOGLE_OAUTH_CLIENT_ID'),
        client_secret: env('GOOGLE_OAUTH_CLIENT_SECRET'),
        redirect_uri: redirectUri(),
        grant_type: 'authorization_code',
      }),
    })
    if (!tokens.refresh_token) return redirect(state.r, { gmail: 'error', reason: 'no_refresh' })
    if (!(tokens.scope ?? '').includes('gmail.readonly')) return redirect(state.r, { gmail: 'error', reason: 'scope' })
    const profile = await google<{ emailAddress: string }>(`${GMAIL}/profile`, {
      headers: { Authorization: `Bearer ${tokens.access_token}` },
    })
    const { error } = await service().rpc('invoice_gmail_connect', {
      p_profile_id: state.p,
      p_email: profile.emailAddress,
      p_refresh_token: tokens.refresh_token,
    })
    if (error) throw new Error(error.message)
    return redirect(state.r, { gmail: 'connected' })
  } catch (e) {
    console.error('invoice-gmail callback:', e)
    return redirect(state.r, { gmail: 'error' })
  }
}

/* ===== Sync ===== */

interface Account {
  id: string
  email: string
  refresh_token: string
  query_extra: string
  synced_until: string | null
}

interface AccountResult {
  account_id: string
  email: string
  checked: number
  imported: number
  skipped: number
  failed: number
  more: boolean
  error?: string
}

/** שגיאה ששווה לנסות שוב בריצה הבאה — ההודעה לא מסומנת כנבדקה */
function transient(e: unknown) {
  if (e instanceof Anthropic.RateLimitError || e instanceof Anthropic.APIConnectionError) return true
  if (e instanceof Anthropic.AuthenticationError) return true
  if (e instanceof Anthropic.APIError && (e.status ?? 0) >= 500) return true
  if (e instanceof GoogleError && (e.status === 429 || e.status >= 500)) return true
  return false
}

async function syncAccount(acc: Account, started: number): Promise<AccountResult> {
  const db = service()
  const out: AccountResult = {
    account_id: acc.id,
    email: acc.email,
    checked: 0,
    imported: 0,
    skipped: 0,
    failed: 0,
    more: false,
  }
  const runStart = new Date()
  let token: string
  try {
    token = await accessToken(acc.refresh_token)
  } catch (e) {
    out.error =
      e instanceof GoogleError && e.code === 'invalid_grant'
        ? 'ההרשאה ל-Gmail בוטלה או פגה — יש לחבר מחדש'
        : 'אין גישה ל-Gmail כרגע'
    await db.rpc('invoice_gmail_run_done', { p_account_id: acc.id, p_synced_until: null, p_error: out.error })
    return out
  }
  const auth = { Authorization: `Bearer ${token}` }

  // ── what to look at ─────────────────────────────────────────────────────
  const q = gmailQuery(acc.query_extra ?? '', acc.synced_until, runStart)
  const listed: string[] = []
  let pageToken: string | undefined
  let exhausted = false
  while (listed.length < MAX_LISTED) {
    const u = new URL(`${GMAIL}/messages`)
    u.searchParams.set('q', q)
    u.searchParams.set('maxResults', '100')
    if (pageToken) u.searchParams.set('pageToken', pageToken)
    const page = await google<{ messages?: { id: string }[]; nextPageToken?: string }>(u.toString(), { headers: auth })
    for (const m of page.messages ?? []) listed.push(m.id)
    pageToken = page.nextPageToken
    if (!pageToken) {
      exhausted = true
      break
    }
  }
  const seen = new Set<string>()
  for (let i = 0; i < listed.length; i += 200) {
    const { data } = await db.rpc('invoice_gmail_seen', { p_account_id: acc.id, p_message_ids: listed.slice(i, i + 200) })
    for (const id of (data as string[] | null) ?? []) seen.add(id)
  }
  // הישנות קודם: כך ריצה שנקטעה ממשיכה מאותו מקום, ו-synced_until נכון
  const todo = listed.filter((id) => !seen.has(id)).reverse()

  const apiKey = env('ANTHROPIC_API_KEY')
  if (todo.length > 0 && !apiKey) {
    out.error = 'הקריאה האוטומטית אינה מוגדרת (ANTHROPIC_API_KEY)'
    await db.rpc('invoice_gmail_run_done', { p_account_id: acc.id, p_synced_until: null, p_error: out.error })
    return out
  }
  const client = invoiceClient(apiKey)
  const model = invoiceModel()

  // ── each message ────────────────────────────────────────────────────────
  let stoppedEarly = false
  for (const messageId of todo) {
    if (Date.now() - started > TIME_BUDGET_MS) {
      stoppedEarly = true
      break
    }
    let imported = 0
    let skipped = 0
    const notes: string[] = []
    try {
      const msg = await google<{ id: string; internalDate?: string; payload?: GmailPart }>(
        `${GMAIL}/messages/${messageId}?format=full`,
        { headers: auth },
      )
      const meta = {
        id: msg.id,
        from: header(msg.payload, 'From'),
        subject: header(msg.payload, 'Subject'),
        date: msg.internalDate ? new Date(Number(msg.internalDate)).toISOString() : null,
      }
      const atts = findAttachments(msg.payload).slice(0, MAX_ATTACHMENTS_PER_MESSAGE)
      for (const att of atts) {
        try {
          let data = att.data
          if (!data && att.attachmentId) {
            const a = await google<{ data: string }>(`${GMAIL}/messages/${messageId}/attachments/${att.attachmentId}`, {
              headers: auth,
            })
            data = a.data
          }
          if (!data) {
            skipped++
            continue
          }
          const raw = base64UrlToBytes(data)
          const pdf = att.mimeType === 'application/pdf' ? raw : await imageToPdf(raw, att.mimeType)
          const sha = await sha256Hex(pdf)

          const { reading, model: used } = await readInvoicePdf(
            client,
            model,
            pdf,
            `This file was attached to an email from ${meta.from ?? 'unknown'} with the subject "${meta.subject ?? ''}"; the attachment is named "${att.filename}".`,
          )
          if (reading.kind !== 'invoice') {
            skipped++
            notes.push(`${att.filename}: לא חשבונית`)
            continue
          }
          const { data: company } = await db.rpc('invoice_company_match', {
            p_name: reading.recipient_name,
            p_tax_id: reading.recipient_tax_id,
          })
          if (!company) {
            skipped++
            notes.push(`${att.filename}: עבור ${reading.recipient_name ?? 'נמען לא ידוע'}`)
            continue
          }

          const id = crypto.randomUUID()
          const { error: upErr } = await db.storage
            .from('invoices')
            .upload(`${id}.pdf`, new Blob([pdf as BlobPart], { type: 'application/pdf' }), {
              contentType: 'application/pdf',
              upsert: false,
            })
          if (upErr) throw new Error(upErr.message)
          const fileName = att.filename.replace(/\.(jpe?g|png)$/i, '.pdf')
          const { data: newId, error: impErr } = await db.rpc('invoice_gmail_import', {
            p_id: id,
            p_account_id: acc.id,
            p_message: meta,
            p_file_name: fileName,
            p_sha256: sha,
            p_reading: reading,
            p_model: used,
          })
          if (impErr || !newId) {
            await db.storage.from('invoices').remove([`${id}.pdf`])
            if (impErr) throw new Error(impErr.message)
            skipped++
            notes.push(`${att.filename}: כבר קיימת`)
            continue
          }
          imported++
        } catch (e) {
          if (transient(e)) throw e
          console.error(`invoice-gmail ${acc.email} ${messageId} ${att.filename}:`, e)
          out.failed++
          notes.push(`${att.filename}: ${readError(e)}`)
        }
      }
      await db.rpc('invoice_gmail_mark', {
        p_account_id: acc.id,
        p_message_id: messageId,
        p_imported: imported,
        p_skipped: skipped,
        p_note: notes.join(' · ') || null,
      })
      out.checked++
      out.imported += imported
      out.skipped += skipped
    } catch (e) {
      // שירות עמוס או לא זמין: עוצרים, וההודעה תיבדק שוב בריצה הבאה
      console.error(`invoice-gmail ${acc.email} ${messageId}:`, e)
      out.error = e instanceof GoogleError ? 'Gmail אינו זמין כרגע' : readError(e)
      stoppedEarly = true
      break
    }
  }

  out.more = stoppedEarly && !out.error
  const complete = exhausted && !stoppedEarly
  await db.rpc('invoice_gmail_run_done', {
    p_account_id: acc.id,
    p_synced_until: complete ? runStart.toISOString() : null,
    p_error: out.error ?? null,
  })
  return out
}

async function sync(accountId: string | null) {
  if (!env('GOOGLE_OAUTH_CLIENT_ID') || !env('GOOGLE_OAUTH_CLIENT_SECRET')) {
    return json({ error: 'החיבור ל-Gmail אינו מוגדר', code: 'not_configured' }, 503)
  }
  const { data, error } = await service().rpc('invoice_gmail_accounts_due', { p_id: accountId })
  if (error) return json({ error: error.message }, 500)
  const started = Date.now()
  const results: AccountResult[] = []
  for (const acc of (data as Account[]) ?? []) {
    if (Date.now() - started > TIME_BUDGET_MS) {
      results.push({ account_id: acc.id, email: acc.email, checked: 0, imported: 0, skipped: 0, failed: 0, more: true })
      continue
    }
    try {
      results.push(await syncAccount(acc, started))
    } catch (e) {
      console.error(`invoice-gmail ${acc.email}:`, e)
      const msg = e instanceof GoogleError ? 'Gmail אינו זמין כרגע' : readError(e)
      await service().rpc('invoice_gmail_run_done', { p_account_id: acc.id, p_synced_until: null, p_error: msg })
      results.push({ account_id: acc.id, email: acc.email, checked: 0, imported: 0, skipped: 0, failed: 0, more: false, error: msg })
    }
  }
  return json({ accounts: results, more: results.some((r) => r.more) })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  const url = new URL(req.url)

  if (req.method === 'GET' && url.pathname.endsWith('/callback')) return callback(url)
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405)

  const body = (await req.json().catch(() => ({}))) as { action?: string; return_to?: unknown; account_id?: unknown }
  const accountId = typeof body.account_id === 'string' && UUID_RE.test(body.account_id) ? body.account_id : null

  // pg_cron: סוד משותף במקום JWT
  const secret = env('INVOICE_GMAIL_SYNC_SECRET')
  const cronSecret = req.headers.get('x-sync-secret')
  if (cronSecret) {
    if (!secret || cronSecret !== secret) return json({ error: 'forbidden' }, 403)
    if (body.action !== 'sync') return json({ error: 'unknown action' }, 400)
    return sync(null)
  }

  const profileId = await adminCaller(req)
  if (!profileId) return json({ error: 'החשבוניות פתוחות למנהלי מערכת בלבד' }, 403)

  if (body.action === 'auth_url') {
    if (!env('GOOGLE_OAUTH_CLIENT_ID') || !env('GOOGLE_OAUTH_CLIENT_SECRET')) {
      return json({ error: 'החיבור ל-Gmail אינו מוגדר', code: 'not_configured' }, 503)
    }
    return authUrl(profileId, body.return_to)
  }
  if (body.action === 'sync') return sync(accountId)
  return json({ error: 'unknown action' }, 400)
})
