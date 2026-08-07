// Nominatim proxy: adds a proper User-Agent, caches results, and keeps the
// address-provider swappable server-side without touching the client adapter.
import { createClient } from 'npm:@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
}

function json(body: unknown, status = 200, extra: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json', ...extra },
  })
}

/**
 * The cache is bounded. It used to be a plain Map that was only ever read
 * past its TTL and never deleted, so a warm isolate grew for as long as it
 * lived — one distinct query per entry, and the query is attacker-chosen.
 */
const MAX_ENTRIES = 500
const TTL_MS = 1000 * 60 * 60 * 24 // 24h
const cache = new Map<string, { at: number; data: unknown }>()

function cacheGet(key: string): unknown | null {
  const hit = cache.get(key)
  if (!hit) return null
  if (Date.now() - hit.at >= TTL_MS) {
    cache.delete(key)
    return null
  }
  // re-insert so iteration order is least-recently-used first
  cache.delete(key)
  cache.set(key, hit)
  return hit.data
}

function cacheSet(key: string, data: unknown) {
  cache.delete(key)
  cache.set(key, { at: Date.now(), data })
  while (cache.size > MAX_ENTRIES) {
    const oldest = cache.keys().next()
    if (oldest.done) break
    cache.delete(oldest.value)
  }
}

/**
 * Nominatim's usage policy is one request per second for an application, and
 * exceeding it gets the caller's IP blocked — which would take address search
 * down for everyone, not just whoever triggered it. The cache alone doesn't
 * bound this: every distinct query is a miss. Misses are therefore serialised
 * through a promise chain with a one-second floor between upstream calls.
 */
const MIN_INTERVAL_MS = 1000
let upstreamChain: Promise<unknown> = Promise.resolve()
let lastCall = 0

function throttled<T>(fn: () => Promise<T>): Promise<T> {
  const run = upstreamChain.then(async () => {
    const wait = MIN_INTERVAL_MS - (Date.now() - lastCall)
    if (wait > 0) await new Promise((r) => setTimeout(r, wait))
    lastCall = Date.now()
    return fn()
  })
  // the chain must not break on a rejected link, or every later call rejects
  upstreamChain = run.then(
    () => undefined,
    () => undefined,
  )
  return run
}

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'GET') return json({ error: 'method not allowed' }, 405)

  // Whether this function is reachable without a JWT is a dashboard setting
  // (verify_jwt) that is not represented anywhere in this repo, so it is not
  // reviewable and not something a migration can assert. Checking in the body
  // makes the answer part of the code: an open proxy to Nominatim is both
  // someone else's rate limit to burn and our IP that gets blocked for it.
  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader) return json({ error: 'לא מחובר' }, 401)
  const asUser = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  })
  const { data: claims, error: authErr } = await asUser.auth.getUser()
  if (authErr || !claims?.user) return json({ error: 'לא מחובר' }, 401)

  const url = new URL(req.url)
  const q = (url.searchParams.get('q') ?? '').trim()
  if (q.length < 3) return json([])
  // an unbounded query string is just cache keys and upstream bytes
  if (q.length > 200) return json({ error: 'שאילתת חיפוש ארוכה מדי' }, 400)

  const key = q.toLowerCase()
  const hit = cacheGet(key)
  if (hit !== null) return json(hit, 200, { 'X-Cache': 'HIT' })

  const nominatim = new URL('https://nominatim.openstreetmap.org/search')
  nominatim.searchParams.set('q', q)
  nominatim.searchParams.set('format', 'jsonv2')
  nominatim.searchParams.set('limit', '6')
  nominatim.searchParams.set('countrycodes', 'il')
  nominatim.searchParams.set('accept-language', 'he')

  let res: Response
  try {
    res = await throttled(() =>
      fetch(nominatim, {
        headers: { 'User-Agent': 'ViperLogistics/1.0 (workforce management app)' },
      }),
    )
  } catch {
    return json([], 200, { 'X-Upstream-Status': 'unreachable' })
  }
  if (!res.ok) {
    return json([], 200, { 'X-Upstream-Status': String(res.status) })
  }
  const raw = (await res.json()) as Array<Record<string, unknown>>
  const data = raw.map((r) => ({
    provider: 'nominatim',
    place_id: String(r.place_id),
    label: r.display_name as string,
    lat: Number(r.lat),
    lng: Number(r.lon),
  }))
  cacheSet(key, data)
  return json(data, 200, { 'X-Cache': 'MISS' })
})
