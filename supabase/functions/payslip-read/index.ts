// payslip-read — reads uploaded payslip pages with Claude (migration 0218 §3).
//
// The browser splits the accountant's PDF into one file per page
// (`payslips/<batch_id>/<page>.pdf`) and then calls this function in small
// chunks of pages, so a 40-page file never runs into the function's wall clock
// and the screen can show progress. For every page it:
//
//   1. downloads the page with the service role,
//   2. sends it to Claude as a PDF document with a strict JSON schema
//      (`_shared/payslip.ts` holds the prompt, the schema and the normalizer),
//   3. stores the normalized reading through `payslip_store_reading`, which
//      only service_role may execute — what was read from a payslip never passes
//      through the browser, so nobody can hand-feed numbers into it.
//
// Grouping pages into payslips is NOT done here: once every chunk is read, the
// browser calls `payslip_apply_reading`, which groups the stored readings in
// SQL (tested in supabase/tests/68).
//
// Caller: a person with `payslips.manage`, over their own JWT, authorised the
// same way viperflow-sync authorises — by asking the database.
//
// Secrets (Edge Function secrets, never the database — CLAUDE.md §2.9):
//   ANTHROPIC_API_KEY  required; without it the function answers 503
//                      `not_configured` and the screen falls back to manual
//                      assignment, which works fully without reading.
//   PAYSLIP_MODEL      optional model override (default claude-opus-5-5).
//
// Deploy normally — JWT verification stays ON.

import { createClient } from 'npm:@supabase/supabase-js@2'
import Anthropic from 'npm:@anthropic-ai/sdk@0.129.0'
import {
  PAYSLIP_MODEL,
  PAYSLIP_SCHEMA,
  PAYSLIP_SYSTEM,
  bytesToBase64,
  mapLimit,
  normalizeReading,
} from '../_shared/payslip.ts'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

/** One call reads at most this many pages, a few at a time. */
const MAX_PAGES_PER_CALL = 6
const CONCURRENCY = 3

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })
}

/** A Hebrew line for the screen; the raw error goes to the function log. */
function pageError(e: unknown): string {
  if (e instanceof Anthropic.AuthenticationError) return 'מפתח ה-API של Anthropic אינו תקין'
  if (e instanceof Anthropic.RateLimitError) return 'עומס על שירות הקריאה — נסו שוב בעוד דקה'
  if (e instanceof Anthropic.BadRequestError) return 'השירות לא הצליח לקרוא את העמוד'
  if (e instanceof Anthropic.APIConnectionError) return 'אין חיבור לשירות הקריאה'
  if (e instanceof Anthropic.APIError) return `שגיאה בשירות הקריאה (${e.status ?? '?'})`
  if (e instanceof Error && e.message) return e.message
  return 'העמוד לא נקרא'
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405)

  const url = Deno.env.get('SUPABASE_URL')!

  // ── who is asking ───────────────────────────────────────────────────────
  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader) return json({ error: 'לא מחובר' }, 401)
  const asUser = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authHeader } },
  })
  const { data: me, error: meErr } = await asUser.rpc('get_my_permissions')
  if (meErr || !me) return json({ error: 'לא מחובר' }, 401)
  const caller = me.profile as { is_admin: boolean }
  const caps = (me.capabilities ?? {}) as Record<string, boolean>
  if (!caller.is_admin && caps['payslips.manage'] !== true) {
    return json({ error: 'אין לך הרשאה לקרוא תלושי שכר' }, 403)
  }

  const apiKey = Deno.env.get('ANTHROPIC_API_KEY') ?? ''
  if (!apiKey) {
    return json({ error: 'הקריאה האוטומטית של תלושים אינה מוגדרת', code: 'not_configured' }, 503)
  }

  // ── what to read ────────────────────────────────────────────────────────
  const body = (await req.json().catch(() => ({}))) as { batch_id?: unknown; pages?: unknown }
  const batchId = typeof body.batch_id === 'string' && UUID_RE.test(body.batch_id) ? body.batch_id : null
  if (!batchId) return json({ error: 'קובץ לא תקין' }, 400)
  const requested = Array.isArray(body.pages) ? body.pages : []
  if (requested.length === 0 || requested.length > MAX_PAGES_PER_CALL) {
    return json({ error: `יש לבקש בין 1 ל-${MAX_PAGES_PER_CALL} עמודים` }, 400)
  }

  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
  const { data: batch, error: batchErr } = await admin
    .from('payslip_batches')
    .select('id, page_count')
    .eq('id', batchId)
    .is('deleted_at', null)
    .maybeSingle()
  if (batchErr) return json({ error: batchErr.message }, 500)
  if (!batch) return json({ error: 'הקובץ לא נמצא' }, 404)

  const pageCount = (batch as { page_count: number }).page_count
  const pages = [...new Set(requested)].filter(
    (p): p is number => Number.isInteger(p) && (p as number) >= 1 && (p as number) <= pageCount,
  )
  if (pages.length === 0) return json({ error: 'העמודים אינם בקובץ' }, 400)

  // ── read ────────────────────────────────────────────────────────────────
  // Non-streaming with a bounded timeout: one page is a short answer, and a
  // stuck call must fail inside the function's wall clock, not after it.
  const client = new Anthropic({ apiKey, maxRetries: 1, timeout: 60_000 })
  const model = Deno.env.get('PAYSLIP_MODEL') || PAYSLIP_MODEL

  const results = await mapLimit(pages, CONCURRENCY, async (page) => {
    try {
      const { data: file, error: dlErr } = await admin.storage.from('payslips').download(`${batchId}/${page}.pdf`)
      if (dlErr || !file) throw new Error('העמוד לא הועלה')
      const data = bytesToBase64(new Uint8Array(await file.arrayBuffer()))

      const msg = await client.beta.messages.create({
        model,
        max_tokens: 16000,
        // A safety-classifier decline on a payslip is unlikely, but when it
        // happens the server retries on a fallback model inside the same call.
        betas: ['server-side-fallback-2026-07-01'],
        fallbacks: 'default',
        output_config: {
          effort: 'medium',
          format: { type: 'json_schema', schema: PAYSLIP_SCHEMA as unknown as Record<string, unknown> },
        },
        system: PAYSLIP_SYSTEM,
        messages: [
          {
            role: 'user',
            content: [
              { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data } },
              { type: 'text', text: `This is page ${page} of ${pageCount} in the file. Return the page's data.` },
            ],
          },
        ],
      })

      if (msg.stop_reason === 'refusal') throw new Error('השירות סירב לקרוא את העמוד')
      if (msg.stop_reason === 'max_tokens') throw new Error('התשובה נקטעה')
      const text = msg.content.find((b) => b.type === 'text')
      if (!text || text.type !== 'text') throw new Error('לא התקבלה תשובה')

      let parsed: unknown
      try {
        parsed = JSON.parse(text.text)
      } catch {
        throw new Error('התשובה אינה JSON תקין')
      }
      const reading = normalizeReading(parsed)

      const { error: storeErr } = await admin.rpc('payslip_store_reading', {
        p_batch_id: batchId,
        p_page: page,
        p_reading: reading,
        p_model: msg.model,
      })
      if (storeErr) throw new Error(storeErr.message)
      return { page, ok: true as const, kind: reading.kind }
    } catch (e) {
      console.error(`payslip-read ${batchId} page ${page}:`, e)
      return { page, ok: false as const, error: pageError(e) }
    }
  })

  return json({ pages: results })
})
