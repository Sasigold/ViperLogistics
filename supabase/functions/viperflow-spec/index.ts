// viperflow-spec — the furniture list of one event, read live from ViperFlow's
// API and stored nowhere (migration 0187, and the screen in EventFurnitureList).
//
// Why a live read rather than the table we already sync:
//
//   1. **Images.** The spec has to look like the delivery note the warehouse
//      knows — a picture next to every line. Images are the one part of an
//      order that is heavy: a hundred lines is a hundred URLs that would have
//      to be stored, refreshed on every sync, and kept in step with a catalogue
//      that changes on their side. Read on open, they cost nothing and are
//      never stale.
//   2. **The parent lines only.** The delivery note lists what leaves the
//      warehouse. A "component" row (`is_component`) is a choice inside its
//      parent — "white cloth" under "round table" — and repeating it as a line
//      of its own is how you end up counting a table twice.
//
// What is still synced and stored is the list itself (`viperflow_order_items`,
// 0176 §4.4): it is what the "מפרט" button counts, and it is what the screen
// falls back to when this function cannot answer — an order without pictures
// beats no order at all.
//
// **No money, as ever.** The API answers with `unit_price` and `line_total` on
// every product line; this function builds its response field by field and
// those two are not among the fields. The promise of 0176 §2 is unchanged:
// nothing that reaches the furniture list carries a price. (The logistics
// lines' money does cross, but through the translator in SQL and into the task
// price — never into this response.)
//
// Authorisation is the stored list's own, in both halves, because this
// function answers exactly the question that table answers:
//
//   • **the event** — `viperflow_event_link` is a `security_invoker` view over
//     the policies that say who may see an event (0176 §5). Read as the
//     caller, it answers with the order id, or with nothing, which is the same
//     answer as "there is no such event";
//   • **the spec key** — `viperflow_order_items` is gated by
//     `events.specs_view` on top of that (0102), and a live read may not be
//     the way around a key somebody was denied. It is asked of
//     `get_my_permissions`, the same way `admin-users` and `viperflow-sync`
//     ask: from the database, never re-derived here.
//
// Secrets (Edge Function secrets, never the database — 0176 §1):
//   VIPERFLOW_API_KEY   vf_live_… , needs the `orders:read` + `products:read`
//                       scopes. Without it this function answers 503 and the
//                       screen falls back to the stored list.
//
// Deploy normally — JWT verification stays ON: every caller here is a person
// with a session.

import { createClient } from 'npm:@supabase/supabase-js@2'
import {
  type CatalogEntry,
  type VfOrderItem,
  catalogIds,
  fetchCatalog,
  specLinesFromOrder,
  specLogisticsQuantity,
  specParents,
} from '../_shared/viperflow.ts'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/** A spec nobody would read on one screen is a spec that is broken anyway. */
const MAX_LINES = 500

/** Long enough for a big order, short enough that the screen is not stuck. */
const TIMEOUT_MS = 15_000

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })
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
      'User-Agent': 'ViperLogistics-Spec/1.0',
    },
    signal: AbortSignal.timeout(TIMEOUT_MS),
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
  const body = (await req.json().catch(() => ({}))) as { event_id?: string }
  const eventId = String(body.event_id ?? '')
  if (!UUID.test(eventId)) {
    return json({ error: 'מזהה אירוע חסר' }, 400)
  }

  // ── who is asking, and may they see this event ──────────────────────────
  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader) return json({ error: 'לא מחובר' }, 401)

  const asUser = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authHeader } },
  })

  const { data: me, error: meErr } = await asUser.rpc('get_my_permissions')
  if (meErr || !me) return json({ error: 'לא מחובר' }, 401)
  const caller = me.profile as { is_admin: boolean }
  const caps = (me.capabilities ?? {}) as Record<string, boolean>
  if (!caller.is_admin && caps['events.specs_view'] !== true) {
    return json({ error: 'אין לך הרשאה לצפות במפרט' }, 403)
  }

  const { data: link, error: linkErr } = await asUser
    .from('viperflow_event_link')
    .select('event_id, connection_id, order_id, order_number, last_synced_at')
    .eq('event_id', eventId)
    .maybeSingle()

  if (linkErr) return json({ error: linkErr.message }, 400)
  // No row is either "no such order" or "not yours to see", and the two are
  // deliberately the same answer.
  if (!link) return json({ error: 'האירוע אינו מקושר להזמנה ב-ViperFlow' }, 404)

  const apiKey = Deno.env.get('VIPERFLOW_API_KEY') ?? ''
  if (!apiKey) return json({ error: 'מפתח ה-API של ViperFlow אינו מוגדר' }, 503)

  // ── the connection, for its address ─────────────────────────────────────
  //
  // Service role, because `viperflow_connections` is the office's screen
  // (`integrations.view`) and the person asking for a spec is usually a
  // dispatcher or a driver. The authorisation already happened above; what is
  // read here is an address, not a fact about the event.
  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
  const { data: connection, error: connErr } = await admin
    .from('viperflow_connections')
    .select('id, api_base_url, is_active')
    .eq('id', link.connection_id)
    .is('deleted_at', null)
    .maybeSingle()

  if (connErr) return json({ error: connErr.message }, 500)
  if (!connection) return json({ error: 'חיבור ViperFlow לא נמצא' }, 400)
  if (!connection.is_active) return json({ error: 'חיבור ViperFlow אינו פעיל' }, 400)

  const base = String(connection.api_base_url).replace(/\/+$/, '')

  // ── the order, live ─────────────────────────────────────────────────────
  let items: VfOrderItem[]
  try {
    const detail = (await vfGet(base, `/orders/${link.order_id}`, apiKey)) as {
      data?: { items?: VfOrderItem[] }
    }
    items = Array.isArray(detail.data?.items) ? detail.data!.items! : []
  } catch (e) {
    const err = e as VfError
    return json({ error: err.message ?? 'ViperFlow לא ענה' }, 502)
  }

  // Parents only, and furniture only — the two decisions in the header.
  const all = specParents(items)
  const shown = all.slice(0, MAX_LINES)

  /* A catalogue that would not answer costs the pictures and nothing else:
     the list is still the list (see `fetchCatalog`). */
  const catalog: Map<string, CatalogEntry> | null =
    await fetchCatalog(base, apiKey, catalogIds(shown), TIMEOUT_MS)
  if (!catalog) console.warn('[viperflow-spec] catalogue unavailable — no images')

  return json({
    order_number: link.order_number,
    last_synced_at: link.last_synced_at,
    fetched_at: new Date().toISOString(),
    truncated: shown.length < all.length,
    workers: specLogisticsQuantity(items, 'worker'),
    trucks: specLogisticsQuantity(items, 'truck'),
    lines: specLinesFromOrder(shown, catalog),
  })
})
