// viperflow-webhook — receives signed ViperFlow webhooks and hands them to the
// database, which does the translating (migration 0177).
//
// MUST be deployed with `--no-verify-jwt`. ViperFlow sends no Authorization and
// no apikey header, so the Supabase gateway would answer 401 — and ViperFlow
// treats any 4xx other than 408/425/429 as "never retry", then disables the
// endpoint after ten consecutive failures. A JWT check here silently kills the
// whole integration:
//
//   supabase functions deploy viperflow-webhook --no-verify-jwt
//
// Secrets (Edge Function secrets, never the database — 0176 §1):
//   VIPERFLOW_WEBHOOK_SECRET           whsec_… , the endpoint's signing secret
//   VIPERFLOW_WEBHOOK_SECRET_PREVIOUS  optional, during ViperFlow's 24 h rotation grace
//
// The URL may carry the connection id as a trailing path segment:
//   https://<ref>.supabase.co/functions/v1/viperflow-webhook/<connection uuid>
// Without it the database falls back to the single active connection, which is
// the common case. ViperFlow stores the URL as given and requests it verbatim,
// so the segment survives; it follows no redirects, so the URL must be final.
//
// Secrets, continued:
//   VIPERFLOW_API_KEY  optional here, and only for one thing: asking the
//                      catalogue whether each item is new equipment, so the
//                      furniture income can be split old/new (0190). Without
//                      it the envelope carries no `catalog_enriched` flag and
//                      the translator skips the income — everything else in
//                      the delivery is applied exactly the same.
//
// The signature, the redaction and the catalogue call live in
// ../_shared/viperflow.ts, which has no Deno imports so that vitest can cover
// what matters in them.

import { createClient } from 'npm:@supabase/supabase-js@2'
import {
  type CatalogEntry,
  catalogIds,
  connectionIdFromPath,
  fetchCatalog,
  redactMoney,
  timestampAcceptable,
  verifySignature,
  withCatalog,
} from '../_shared/viperflow.ts'

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  })
}

/**
 * The catalogue for this delivery's items, or null when it cannot be had.
 *
 * The base URL lives on the connection row and nowhere else (0176 §4.1), so
 * it is read the same way the translator resolves the connection: the one in
 * the path, or the single active one. Anything less certain than that answers
 * null rather than guessing which ViperFlow account to ask.
 */
async function catalogForOrder(
  admin: ReturnType<typeof createClient>,
  connectionId: string | null,
  order: unknown,
): Promise<Map<string, CatalogEntry> | null> {
  const apiKey = Deno.env.get('VIPERFLOW_API_KEY') ?? ''
  if (!apiKey) return null

  const items = (order as { items?: unknown } | null)?.items
  const ids = catalogIds(items)

  let query = admin
    .from('viperflow_connections')
    .select('id, api_base_url')
    .is('deleted_at', null)
    .eq('is_active', true)
  if (connectionId) query = query.eq('id', connectionId)

  const { data, error } = await query
  if (error || !data || data.length !== 1) return null

  return await fetchCatalog(String(data[0].api_base_url).replace(/\/+$/, ''), apiKey, ids)
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method not allowed' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json', Allow: 'POST' },
    })
  }

  const secrets = [
    Deno.env.get('VIPERFLOW_WEBHOOK_SECRET') ?? '',
    Deno.env.get('VIPERFLOW_WEBHOOK_SECRET_PREVIOUS') ?? '',
  ].filter((s) => s.length > 0)

  // No secret configured is our fault, not theirs: 503 is retryable, so the
  // events wait in ViperFlow's queue instead of being dropped for good.
  if (secrets.length === 0) {
    return json({ error: 'signing secret not configured' }, 503)
  }

  const timestamp = req.headers.get('x-viperflow-timestamp') ?? ''
  const signature = req.headers.get('x-viperflow-signature') ?? ''
  if (signature === '' || !timestampAcceptable(timestamp)) {
    return json({ error: 'missing or stale signature headers' }, 401)
  }

  // Read once, verify these exact bytes, and only then parse.
  const raw = await req.text()
  if (!(await verifySignature(secrets, signature, timestamp, raw))) {
    return json({ error: 'bad signature' }, 401)
  }

  let envelope: unknown
  try {
    envelope = JSON.parse(raw)
  } catch {
    return json({ error: 'invalid json' }, 400)
  }

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  const connectionId = connectionIdFromPath(req.url)
  const clean = redactMoney(envelope) as Record<string, unknown>

  /* ‏0190: which item is new equipment is a question about the catalogue, and
     the order does not answer it. A failure here costs the income split and
     nothing else — the delivery is applied either way. */
  const catalog = await catalogForOrder(admin, connectionId, clean.data)
  if (!catalog) console.warn('[viperflow-webhook] catalogue unavailable — income not split')

  const { data, error } = await admin.rpc('viperflow_ingest', {
    p_envelope: { ...clean, data: withCatalog(clean.data, catalog) },
    p_meta: {
      connection_id: connectionId,
      delivery_id: req.headers.get('x-viperflow-delivery'),
      attempt: req.headers.get('x-viperflow-attempt'),
      origin: req.headers.get('x-viperflow-origin'),
    },
  })

  // Only a broken pipe answers with a retryable status. A translation that
  // failed is already recorded as a red row with a "run again" button (0177
  // §5), and answering 4xx there would stop ViperFlow retrying forever and
  // eventually disable the endpoint.
  if (error) {
    console.error('viperflow_ingest failed', error)
    return json({ error: 'ingest unavailable' }, 503)
  }

  // Small body on purpose: ViperFlow reads at most 4 KB and stores 512 chars.
  return json({ received: true, status: (data as { status?: string })?.status ?? 'processed' })
})
