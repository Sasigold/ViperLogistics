// Nominatim proxy: adds a proper User-Agent, caches results, and keeps the
// address-provider swappable server-side without touching the client adapter.
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
}

const cache = new Map<string, { at: number; data: unknown }>()
const TTL_MS = 1000 * 60 * 60 * 24 // 24h

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  const url = new URL(req.url)
  const q = (url.searchParams.get('q') ?? '').trim()
  if (q.length < 3) {
    return new Response(JSON.stringify([]), {
      headers: { ...cors, 'Content-Type': 'application/json' },
    })
  }

  const key = q.toLowerCase()
  const hit = cache.get(key)
  if (hit && Date.now() - hit.at < TTL_MS) {
    return new Response(JSON.stringify(hit.data), {
      headers: { ...cors, 'Content-Type': 'application/json', 'X-Cache': 'HIT' },
    })
  }

  const nominatim = new URL('https://nominatim.openstreetmap.org/search')
  nominatim.searchParams.set('q', q)
  nominatim.searchParams.set('format', 'jsonv2')
  nominatim.searchParams.set('limit', '6')
  nominatim.searchParams.set('countrycodes', 'il')
  nominatim.searchParams.set('accept-language', 'he')

  const res = await fetch(nominatim, {
    headers: { 'User-Agent': 'ViperLogistics/1.0 (workforce management app)' },
  })
  if (!res.ok) {
    return new Response(JSON.stringify([]), {
      status: 200,
      headers: { ...cors, 'Content-Type': 'application/json', 'X-Upstream-Status': String(res.status) },
    })
  }
  const raw = (await res.json()) as Array<Record<string, unknown>>
  const data = raw.map((r) => ({
    provider: 'nominatim',
    place_id: String(r.place_id),
    label: r.display_name as string,
    lat: Number(r.lat),
    lng: Number(r.lon),
  }))
  cache.set(key, { at: Date.now(), data })
  return new Response(JSON.stringify(data), {
    headers: { ...cors, 'Content-Type': 'application/json', 'X-Cache': 'MISS' },
  })
})
