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

/** Recursively drops every money key. Arrays keep their order and length. */
export function redactMoney(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(redactMoney)
  if (value && typeof value === 'object') {
    const out: Record<string, unknown> = {}
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      if (MONEY_KEYS.has(k)) continue
      out[k] = redactMoney(v)
    }
    return out
  }
  return value
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
