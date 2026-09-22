/**
 * The pure half of the ViperFlow integration — signature verification and money
 * redaction, with no Deno or Supabase imports so it can be unit-tested.
 *
 * Both edge functions import from here: `viperflow-webhook` verifies what
 * arrives, `viperflow-sync` redacts what it fetches. Getting the signature
 * wrong is not a degraded integration, it is no integration at all — every
 * delivery fails, and ViperFlow disables the endpoint after ten of them — so
 * this is the one part of the feature that carries a test of its own
 * (`viperflow.test.ts`, run by vitest under Node).
 *
 * The scheme, from ViperFlow's `docs/WEBHOOKS.md` §5:
 *
 *   signed payload = `${timestamp}.${raw body}`   timestamp = unix seconds
 *   key            = UTF-8 bytes of the WHOLE secret, `whsec_` prefix included
 *   signature      = lowercase hex HMAC-SHA256
 *   header         = `v1=<hex>`, or `v1=<new>,v1=<old>` during rotation
 *   replay window  = |now − timestamp| ≤ 300 s
 */

/** ViperFlow's own tolerance, and the one its docs tell receivers to use. */
export const TOLERANCE_SECONDS = 300

/**
 * Money, as it appears anywhere in a ViperFlow envelope.
 *
 * The furniture list must carry no prices (migration 0176 §2), and the
 * strongest way to promise that is for the number never to enter the building.
 * Redaction happens at the boundary, before the envelope is stored; the
 * translator in SQL does not read these keys either. Two layers, on purpose.
 */
export const MONEY_KEYS: ReadonlySet<string> = new Set([
  'unit_price',
  'line_total',
  'discount_percent',
  'totals',
  'payment',
  'deposit_amount',
  'paid_amount',
  'pending_amount',
  'balance_due',
  'subtotal',
  'taxable_amount',
  'vat_amount',
  'grand_total',
  'order_discount_percent',
  'total_discount',
  'currency',
])

/**
 * The one exception, added by migration 0187.
 *
 * An order's logistics lines — "הובלה" (`truck`) and "סידור ואיסוף"
 * (`worker`) — are not furniture: they are what WE do, and what we charge the
 * customer for. Their amount becomes the price of the setup and teardown
 * tasks, so it has to cross the boundary.
 *
 * Scoped as tightly as it can be: only these two keys, and only on a line
 * whose own `line_type` says it is logistics. A product line is redacted
 * exactly as before, and so is every order-level total — the promise of
 * 0176 §2 (no prices in the furniture list) is unchanged, because a
 * furniture line still carries none.
 */
export const LOGISTICS_LINE_TYPES: ReadonlySet<string> = new Set(['truck', 'worker'])
export const LOGISTICS_MONEY_KEYS: ReadonlySet<string> = new Set(['unit_price', 'line_total'])

/** True for an order line that is logistics rather than furniture. */
function isLogisticsLine(value: Record<string, unknown>): boolean {
  return LOGISTICS_LINE_TYPES.has(String(value.line_type ?? ''))
}

/**
 * Recursively drops every money key. Arrays keep their order and length.
 *
 * The decision is made per object, from that object's own `line_type`: a
 * nested object inside a logistics line does not inherit the exception, and
 * an order that happens to carry a `line_type` key of its own would only
 * expose the two line keys — never `totals`, `payment` or `grand_total`.
 */
export function redactMoney(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(redactMoney)
  if (value && typeof value === 'object') {
    const row = value as Record<string, unknown>
    const keepsLogistics = isLogisticsLine(row)
    const out: Record<string, unknown> = {}
    for (const [k, v] of Object.entries(row)) {
      if (MONEY_KEYS.has(k) && !(keepsLogistics && LOGISTICS_MONEY_KEYS.has(k))) continue
      out[k] = redactMoney(v)
    }
    return out
  }
  return value
}

/**
 * The shape of the spec, from an order the API answered with (0187).
 *
 * Here rather than inside `viperflow-spec/index.ts` for the same reason the
 * signature is here: this is the part that decides what the warehouse reads,
 * and it is the part worth a test. The function itself is then only fetching
 * and authorisation.
 */
export interface VfOrderItem {
  id?: string
  parent_item_id?: string | null
  line_type?: string
  is_component?: boolean
  product_id?: string | null
  name?: string
  quantity?: number
  spare_quantity?: number
  notes?: string | null
  is_custom?: boolean
  options?: { group_name?: string | null; value?: string | null }[]
  sort_order?: number
}

/** One line as the screen draws it. Whitelisted on purpose: no money can ride along. */
export interface SpecLine {
  id: string
  name: string
  quantity: number
  spare_quantity: number
  notes: string | null
  is_custom: boolean
  options: string[]
  image_url: string | null
}

/** "מפה: מפה לבנה", or just the value when the group has no name. */
export function specOptionLabels(item: VfOrderItem): string[] {
  const options = Array.isArray(item.options) ? item.options : []
  return options
    .map((o) => {
      const value = String(o?.value ?? '').trim()
      if (!value) return ''
      const group = String(o?.group_name ?? '').trim()
      return group ? `${group}: ${value}` : value
    })
    .filter((label) => label !== '')
}

/** The quantity ordered of a logistics line type, or null — zero is not an order. */
export function specLogisticsQuantity(items: VfOrderItem[], lineType: string): number | null {
  const total = items
    .filter((i) => i.line_type === lineType && i.is_component !== true)
    .reduce((sum, i) => sum + (Number(i.quantity) || 0), 0)
  return total > 0 ? total : null
}

/** The furniture lines of an order: parents only, no logistics, no money. */
export function specParents(items: VfOrderItem[]): VfOrderItem[] {
  return items.filter((i) => i.line_type === 'product' && i.is_component !== true)
}

/**
 * The parent lines, with the catalogue image of each one.
 *
 * Built field by field: the API answers with `unit_price` and `line_total` on
 * every product line, and the only way to promise they do not reach the
 * warehouse screen is for nothing to copy them.
 */
export function specLinesFromOrder(
  items: VfOrderItem[],
  images: Map<string, string>,
): SpecLine[] {
  return specParents(items).map((item, index) => ({
    id: String(item.id ?? `line-${index}`),
    name: String(item.name ?? '').trim() || 'פריט',
    quantity: Number(item.quantity) || 0,
    spare_quantity: Number(item.spare_quantity) || 0,
    notes: item.notes ? String(item.notes) : null,
    is_custom: item.is_custom === true,
    options: specOptionLabels(item),
    image_url: images.get(String(item.product_id ?? '')) ?? null,
  }))
}

export function hexToBytes(hex: string): Uint8Array | null {
  if (hex.length === 0 || hex.length % 2 !== 0 || !/^[0-9a-f]+$/i.test(hex)) return null
  const out = new Uint8Array(hex.length / 2)
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16)
  return out
}

/** Length-independent, and without an early exit on the first differing byte. */
export function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  let diff = a.length ^ b.length
  const n = Math.max(a.length, b.length)
  for (let i = 0; i < n; i++) diff |= (a[i] ?? 0) ^ (b[i] ?? 0)
  return diff === 0
}

/**
 * hex( HMAC_SHA256(key = the whole secret string, message = "<ts>.<raw body>") )
 *
 * Two details that bite people, both straight from ViperFlow's docs: the
 * `whsec_` prefix is part of the key and is NOT stripped, and the message is
 * the raw request bytes — re-serialising the parsed JSON will not match.
 */
export async function sign(secret: string, timestamp: string, body: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${timestamp}.${body}`))
  return new Uint8Array(mac)
}

/**
 * True when ANY `v1=` entry matches ANY configured secret.
 *
 * Both loops run to the end rather than returning on the first hit: during
 * ViperFlow's 24 h rotation grace the header carries `v1=<new>,v1=<old>`, and
 * the loop must not leak which one matched through its running time.
 */
export async function verifySignature(
  secrets: readonly string[],
  header: string,
  timestamp: string,
  body: string,
): Promise<boolean> {
  const offered = header
    .split(',')
    .map((part) => part.trim())
    .filter((part) => part.startsWith('v1='))
    .map((part) => hexToBytes(part.slice(3)))
    .filter((bytes): bytes is Uint8Array => bytes !== null)

  if (offered.length === 0 || secrets.length === 0) return false

  let ok = false
  for (const secret of secrets) {
    const expected = await sign(secret, timestamp, body)
    for (const candidate of offered) {
      if (timingSafeEqual(expected, candidate)) ok = true
    }
  }
  return ok
}

/** `^\d{1,12}$` and within the replay window. */
export function timestampAcceptable(timestamp: string, nowMs: number = Date.now()): boolean {
  if (!/^\d{1,12}$/.test(timestamp)) return false
  return Math.abs(Math.floor(nowMs / 1000) - Number(timestamp)) <= TOLERANCE_SECONDS
}

/**
 * The trailing path segment, when it is a uuid — the connection id, for a
 * second ViperFlow account. Anything else is ignored, and the database falls
 * back to the single active connection.
 */
export function connectionIdFromPath(url: string): string | null {
  const last = new URL(url).pathname.split('/').filter(Boolean).pop() ?? ''
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(last)
    ? last.toLowerCase()
    : null
}
