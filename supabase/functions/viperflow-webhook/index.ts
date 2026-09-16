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
// The signature and redaction logic lives in ../_shared/viperflow.ts, which has
// no Deno imports so that vitest can cover it.

import { createClient } from 'npm:@supabase/supabase-js@2'
import {
  connectionIdFromPath,
  redactMoney,
  timestampAcceptable,
  verifySignature,
} from '../_shared/viperflow.ts'

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  })
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

  const { data, error } = await admin.rpc('viperflow_ingest', {
    p_envelope: redactMoney(envelope),
    p_meta: {
      connection_id: connectionIdFromPath(req.url),
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
