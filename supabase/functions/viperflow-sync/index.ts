// viperflow-sync — pulls orders from ViperFlow's REST API and feeds them through
// the same translator the webhook uses (viperflow_ingest, migration 0177).
//
// The webhook is the live path; this is the safety net, and it has three jobs:
//
//   1. **Backfill.** Orders that already existed when the connection was made
//      never produced a webhook.
//   2. **Recovery.** ViperFlow disables an endpoint after ten consecutive
//      failures and keeps events for thirty days only. After an outage, the
//      queue is gone and the only way back is to ask.
//   3. **Reconciliation.** at-least-once delivery with no ordering is a promise
//      about single events, not about the end state. A nightly pull that finds
//      nothing is how you learn that nothing is missing.
//
// Callers, and there are exactly two:
//   • a person with `integrations.manage`, over their own JWT (the "סנכרון
//     עכשיו" button), authorised the same way admin-users authorises — by
//     asking the database, not by re-deriving the permission chain here;
//   • a scheduler, with `x-sync-secret: $VIPERFLOW_SYNC_SECRET`.
//
// Secrets (Edge Function secrets, never the database — 0176 §1):
//   VIPERFLOW_API_KEY     vf_live_… , needs `orders:read`, and `products:read`
//                         for the new/old furniture split (0190)
//   VIPERFLOW_SYNC_SECRET optional; without it the scheduled path is closed
//
// Deploy normally — JWT verification stays ON here, unlike viperflow-webhook,
// because nothing in this direction comes from ViperFlow. The consequence is
// that BOTH callers must send an `Authorization` header or the gateway answers
// 401 before this code runs: the browser sends the user's JWT by itself, and
// the scheduler must carry the (public) anon key alongside its `x-sync-secret`.
// docs/VIPERFLOW.md §6 has the exact curl.

import { createClient } from 'npm:@supabase/supabase-js@2'
import { catalogIds, fetchCatalog, redactMoney, withCatalog } from '../_shared/viperflow.ts'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-sync-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

/** One invocation stays well inside the function's wall clock and their rate limit. */
const MAX_ORDERS = 80
const PAGE_SIZE = 50

/** Their `updated_at` is the transaction START time, so a strictly-greater
 *  filter can miss a row committed out of order. Their docs prescribe this
 *  overlap; de-duplication is by event id, so re-reading is free. */
const OVERLAP_MINUTES = 2

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })
}

/**
 * A stable envelope id for a pulled order state.
 *
 * `evt_` + 32 hex of sha256(order id | updated_at). Two consequences, both
 * wanted: pulling the same unchanged order twice is answered "duplicate" and
 * writes nothing, and an order that changed since the last pull gets a fresh id
 * and is applied. The shape matches what `viperflow_ingest` validates, so a
 * pulled event and a delivered one are the same kind of row in the log.
 */
async function syntheticEventId(orderId: string, updatedAt: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(`${orderId}|${updatedAt}`),
  )
  const hex = Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
  return `evt_${hex.slice(0, 32)}`
}

interface VfOrder {
  id: string
  updated_at: string
  order_number?: string
}

class VfError extends Error {
  constructor(message: string, readonly status: number) {
    super(message)
  }
}

async function vfGet(base: string, path: string, key: string): Promise<unknown> {
  const res = await fetch(`${base}${path}`, {
    headers: {
      Authorization: `Bearer ${key}`,
      // The API runs next to its database; without this every call pays a
      // cross-region round trip.
      'x-region': 'ap-northeast-1',
      'User-Agent': 'ViperLogistics-Sync/1.0',
    },
  })

  if (!res.ok) {
    const body = await res.text().catch(() => '')
    let message = `ViperFlow ${res.status}`
    try {
      const parsed = JSON.parse(body) as { error?: { code?: string; message?: string } }
      if (parsed.error?.code) message = `${message} ${parsed.error.code}`
      if (parsed.error?.message) message = `${message}: ${parsed.error.message}`
    } catch {
      if (body) message = `${message}: ${body.slice(0, 200)}`
    }
    throw new VfError(message, res.status)
  }

  return await res.json()
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405)

  const url = Deno.env.get('SUPABASE_URL')!
  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)

  // ── who is asking ───────────────────────────────────────────────────────
  const schedulerSecret = Deno.env.get('VIPERFLOW_SYNC_SECRET') ?? ''
  const asScheduler = schedulerSecret !== '' &&
    req.headers.get('x-sync-secret') === schedulerSecret

  if (!asScheduler) {
    const authHeader = req.headers.get('Authorization') ?? ''
    if (!authHeader) return json({ error: 'לא מחובר' }, 401)

    const asUser = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: me, error: meErr } = await asUser.rpc('get_my_permissions')
    if (meErr || !me) return json({ error: 'לא מחובר' }, 401)

    const caller = me.profile as { is_admin: boolean }
    const caps = (me.capabilities ?? {}) as Record<string, boolean>
    if (!caller.is_admin && caps['integrations.manage'] !== true) {
      return json({ error: 'אין לך הרשאה לסנכרן מ-ViperFlow' }, 403)
    }
  }

  const apiKey = Deno.env.get('VIPERFLOW_API_KEY') ?? ''
  if (!apiKey) return json({ error: 'מפתח ה-API של ViperFlow אינו מוגדר' }, 503)

  const body = (await req.json().catch(() => ({}))) as {
    connection_id?: string
    since?: string
    order_ids?: string[]
    /** Re-apply even when nothing changed on their side — see below. */
    force?: boolean
  }
  const force = body.force === true

  // ── which connection ────────────────────────────────────────────────────
  let query = admin
    .from('viperflow_connections')
    .select('id, label, api_base_url, customer_id, synced_through')
    .is('deleted_at', null)
    .eq('is_active', true)
  if (body.connection_id) query = query.eq('id', body.connection_id)

  const { data: connections, error: connErr } = await query
  if (connErr) return json({ error: connErr.message }, 500)
  if (!connections || connections.length === 0) {
    return json({ error: 'אין חיבור ViperFlow פעיל' }, 400)
  }
  if (connections.length > 1) {
    return json({ error: 'יש יותר מחיבור פעיל אחד — יש לציין connection_id' }, 400)
  }

  const connection = connections[0] as {
    id: string
    label: string
    api_base_url: string
    customer_id: string
    synced_through: string | null
  }
  const base = connection.api_base_url.replace(/\/+$/, '')

  // ── from when ───────────────────────────────────────────────────────────
  //
  // The watermark is the connection's own `synced_through`, which only this
  // function advances — NOT max(order_updated_at) over the links.
  //
  // That distinction is the whole backfill. The webhook is live from the
  // moment the endpoint is created, so the newest link is always a brand new
  // order; a watermark derived from the links would jump to "a minute ago"
  // after the very first delivery, and the scan — which walks updated_at
  // ascending — would never reach the orders that existed beforehand.
  //
  // Nothing scanned yet means the first backfill: thirty days back is the
  // window an event-rental business actually plans in.
  let since = body.since ?? null
  if (!since && !body.order_ids) {
    since = connection.synced_through
      ? new Date(new Date(connection.synced_through).getTime() - OVERLAP_MINUTES * 60_000).toISOString()
      : new Date(Date.now() - 30 * 24 * 60 * 60_000).toISOString()
  }

  // ── collect the order ids to refresh ────────────────────────────────────
  const summary = {
    connection: connection.label,
    since,
    forced: force,
    scanned: 0,
    applied: 0,
    duplicate: 0,
    failed: 0,
    has_more: false,
    errors: [] as string[],
  }

  let ids: string[] = []
  let scannedThrough: string | null = null
  /** One line in the log for a scan of eighty orders, not eighty. */
  let catalogWarned = false
  try {
    if (body.order_ids?.length) {
      ids = body.order_ids.slice(0, MAX_ORDERS)
    } else {
      let cursor: string | null = null
      while (ids.length < MAX_ORDERS) {
        const params = new URLSearchParams({
          sort: 'updated_at',
          limit: String(PAGE_SIZE),
        })
        if (since) params.set('updated_since', since)
        if (cursor) params.set('cursor', cursor)

        const page = (await vfGet(base, `/orders?${params}`, apiKey)) as {
          data: VfOrder[]
          pagination: { has_more: boolean; next_cursor: string | null }
        }

        const rows = page.data ?? []
        for (const order of rows) {
          if (ids.length >= MAX_ORDERS) {
            // Dropped on the floor by the cap, not by the end of the data.
            // This has to be recorded HERE: when the truncation lands on the
            // last page there is no surviving cursor, and setting the flag
            // after the `break` below would leave the caller believing the
            // scan finished. The watermark still advances to what we did
            // read, so the next run picks up exactly here.
            summary.has_more = true
            break
          }
          ids.push(order.id)
        }

        if (!page.pagination?.has_more || !page.pagination.next_cursor) break
        if (ids.length >= MAX_ORDERS) {
          summary.has_more = true
          break
        }
        // A cursor is bound to the query that issued it, so nothing else about
        // the request may change while paging.
        cursor = page.pagination.next_cursor
      }
    }
  } catch (e) {
    const err = e as VfError
    return json({ error: err.message, status: err.status ?? 500 }, 502)
  }

  // ── and refresh each one ────────────────────────────────────────────────
  //
  // The list endpoint never returns `items` — the furniture list only exists on
  // the single-order response — so each id costs a second call. That is the
  // reason for MAX_ORDERS: their default key allows 120 requests a minute.
  for (const id of ids) {
    summary.scanned += 1
    try {
      const detail = (await vfGet(base, `/orders/${id}`, apiKey)) as { data: VfOrder }
      const order = detail.data
      if (!order?.id) continue

      /* ‏0190: the catalogue says which item is new equipment, and the order
         does not. Null costs the income split and nothing else. */
      const clean = redactMoney(order) as Record<string, unknown>
      const catalog = await fetchCatalog(base, apiKey, catalogIds(clean.items))
      if (!catalog && !catalogWarned) {
        catalogWarned = true
        console.warn('[viperflow-sync] catalogue unavailable — income not split')
      }

      const envelope = {
        id: await syntheticEventId(order.id, order.updated_at ?? ''),
        type: 'order.updated',
        created_at: new Date().toISOString(),
        api_version: 'v1',
        livemode: true,
        origin: { source: 'system', integration: 'viperlogistics-sync' },
        data: withCatalog(clean, catalog),
        previous: null,
      }

      const { data: result, error } = await admin.rpc('viperflow_ingest', {
        p_envelope: envelope,
        p_meta: { connection_id: connection.id, origin: 'system', force },
      })

      if (error) {
        summary.failed += 1
        summary.errors.push(`${order.order_number ?? id}: ${error.message}`)
        continue
      }

      // The watermark follows what we SCANNED, not what we applied: an order
      // that came back "duplicate" was still read, and a run that refused to
      // advance past it would re-read it forever.
      if (order.updated_at && (!scannedThrough || order.updated_at > scannedThrough)) {
        scannedThrough = order.updated_at
      }

      const status = (result as { status?: string })?.status
      if (status === 'duplicate') summary.duplicate += 1
      else if (status === 'processed') summary.applied += 1
      else if (status === 'failed') {
        summary.failed += 1
        summary.errors.push(
          `${order.order_number ?? id}: ${(result as { reason?: string })?.reason ?? 'נכשל'}`,
        )
      }
    } catch (e) {
      const err = e as VfError
      summary.failed += 1
      summary.errors.push(`${id}: ${err.message}`)
      // A 401/403 is a key problem and every further call will fail the same
      // way; a 429 means backing off now costs less than being throttled.
      if (err.status === 401 || err.status === 403 || err.status === 429) break
    }
  }

  // Advance the watermark only for a plain forward scan. An explicit `since`,
  // an `order_ids` list or a `force` repair are all "look at this again", and
  // letting them move the watermark would skip whatever sits between.
  if (!body.since && !body.order_ids && !force && scannedThrough) {
    const { error: markErr } = await admin
      .from('viperflow_connections')
      .update({ synced_through: scannedThrough })
      .eq('id', connection.id)
    if (markErr) summary.errors.push(`סמן הסנכרון לא נשמר: ${markErr.message}`)
  }

  // Housekeeping rides along with the scheduled run: the delivery log is an
  // audit trail, not an archive. Failed rows are never pruned — they are open
  // work (0176 §6).
  if (asScheduler) {
    await admin.rpc('viperflow_prune_deliveries', { p_days: 90 })
  }

  // Only the errors worth reading. A hundred identical lines help nobody.
  summary.errors = summary.errors.slice(0, 10)
  return json(summary)
})
