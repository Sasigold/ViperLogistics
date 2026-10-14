// invoice-read — reads uploaded supplier invoices with Claude (migration 0233 §3).
//
// The browser uploads each invoice as one PDF (`invoices/<id>.pdf`; a photo is
// turned into a PDF first) and then calls this function with up to four ids.
// For every invoice it:
//
//   1. downloads the file with the service role,
//   2. sends it to Claude as a PDF document with a strict JSON schema
//      (`_shared/invoice.ts` holds the prompt, the schema and the normalizer),
//   3. stores the normalized reading through `invoice_store_reading`, which only
//      service_role may execute — and which never overwrites an invoice someone
//      already confirmed or corrected by hand.
//
// Caller: a system admin (the invoices are admins only, 0233 §1), over their
// own JWT, authorised by asking the database (`get_my_permissions`).
//
// Secrets: ANTHROPIC_API_KEY (shared with payslip-read; without it the function
// answers 503 `not_configured` and the screen falls back to typing by hand),
// INVOICE_MODEL optional.
//
// Deploy normally — JWT verification stays ON.

import { createClient } from 'npm:@supabase/supabase-js@2'
import { mapLimit } from '../_shared/payslip.ts'
import { invoiceClient, invoiceModel, readError, readInvoicePdf } from '../_shared/invoiceRead.ts'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const MAX_PER_CALL = 4
const CONCURRENCY = 2
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405)

  const url = Deno.env.get('SUPABASE_URL')!
  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader) return json({ error: 'לא מחובר' }, 401)
  const asUser = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authHeader } },
  })
  const { data: me, error: meErr } = await asUser.rpc('get_my_permissions')
  if (meErr || !me) return json({ error: 'לא מחובר' }, 401)
  if (!(me.profile as { is_admin: boolean }).is_admin) {
    return json({ error: 'החשבוניות פתוחות למנהלי מערכת בלבד' }, 403)
  }

  const apiKey = Deno.env.get('ANTHROPIC_API_KEY') ?? ''
  if (!apiKey) return json({ error: 'הקריאה האוטומטית אינה מוגדרת', code: 'not_configured' }, 503)

  const body = (await req.json().catch(() => ({}))) as { ids?: unknown }
  const ids = [...new Set(Array.isArray(body.ids) ? body.ids : [])].filter(
    (v): v is string => typeof v === 'string' && UUID_RE.test(v),
  )
  if (ids.length === 0 || ids.length > MAX_PER_CALL) {
    return json({ error: `יש לבקש בין 1 ל-${MAX_PER_CALL} חשבוניות` }, 400)
  }

  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
  const client = invoiceClient(apiKey)
  const model = invoiceModel()

  const results = await mapLimit(ids, CONCURRENCY, async (id) => {
    try {
      const { data: inv } = await admin
        .from('invoices')
        .select('id, file_name')
        .eq('id', id)
        .is('deleted_at', null)
        .maybeSingle()
      if (!inv) throw new Error('החשבונית לא נמצאה')
      const { data: file, error: dlErr } = await admin.storage.from('invoices').download(`${id}.pdf`)
      if (dlErr || !file) throw new Error('הקובץ לא הועלה')
      const pdf = new Uint8Array(await file.arrayBuffer())
      const { reading, model: used } = await readInvoicePdf(
        client,
        model,
        pdf,
        `File name: ${(inv as { file_name: string }).file_name}.`,
      )
      const { error: storeErr } = await admin.rpc('invoice_store_reading', {
        p_id: id,
        p_reading: reading,
        p_model: used,
      })
      if (storeErr) throw new Error(storeErr.message)
      return { id, ok: true as const, kind: reading.kind }
    } catch (e) {
      console.error(`invoice-read ${id}:`, e)
      const error = readError(e)
      await admin.rpc('invoice_read_failed', { p_id: id, p_error: error })
      return { id, ok: false as const, error }
    }
  })

  return json({ invoices: results })
})
