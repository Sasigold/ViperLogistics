// Geocoding proxy: keeps the address-provider swappable server-side without
// touching the client adapter, caches results, and holds the API keys.
//
// הספק הראשי הוא Google Places (Text Search) — כיסוי שמות עסקים, אולמות
// וסלחנות לשגיאות כתיב שמסד OSM פשוט לא מכיל. הוא פעיל רק כשהסוד
// GOOGLE_MAPS_API_KEY מוגדר; בלעדיו (או כשהקריאה נכשלת או חוזרת ריקה)
// הפונקציה נסוגה לצמד ה-OSM שהיה כאן קודם:
//
// שני ספקים, לא אחד. Nominatim בנוי לכתובת שלמה ומדויקת, ולכן מי שהקליד "אש
// התורה" לא קיבל את "ישיבת אש התורה" — הוא חיפוש כתובות, לא חיפוש שמות.
// Photon בנוי בדיוק להקלדה תוך כדי: התאמת מילים חלקיות, שגיאות כתיב ושמות של
// נקודות עניין. הוא הספק הראשי בנתיב הנסיגה, ו-Nominatim נשאר כמשלים
// לשאילתות שבהן Photon מחזיר מעט מדי או נופל.
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

const UA = 'ViperLogistics/1.0 (workforce management app)'

/** ישראל והשטח שסביבה. Photon מקבל מחרוזת, Google מקבל מלבן — מקור אחד לשניהם. */
const IL_LAT_MIN = 29.4
const IL_LAT_MAX = 33.45
const IL_LON_MIN = 34.2
const IL_LON_MAX = 35.95

/** בסדר minLon,minLat,maxLon,maxLat ש-Photon מצפה לו. */
const IL_BBOX = `${IL_LON_MIN},${IL_LAT_MIN},${IL_LON_MAX},${IL_LAT_MAX}`

/** מספר התוצאות שנשלחות ללקוח. הוא מדרג ומקצר מעבר לזה. */
const MAX_RESULTS = 12

interface Suggestion {
  provider: string
  place_id: string
  label: string
  lat: number
  lng: number
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
 * through a promise chain with a minimum interval between upstream calls.
 *
 * ל-Photon אין מכסה נוקשה כזו, אבל גם הוא שירות ציבורי בחינם — ולכן הוא עובר
 * דרך אותו מנגנון עם מרווח קצר יותר.
 */
function makeThrottle(minIntervalMs: number) {
  let chain: Promise<unknown> = Promise.resolve()
  let lastCall = 0
  return <T>(fn: () => Promise<T>): Promise<T> => {
    const run = chain.then(async () => {
      const wait = minIntervalMs - (Date.now() - lastCall)
      if (wait > 0) await new Promise((r) => setTimeout(r, wait))
      lastCall = Date.now()
      return fn()
    })
    // the chain must not break on a rejected link, or every later call rejects
    chain = run.then(
      () => undefined,
      () => undefined,
    )
    return run
  }
}

const nominatimThrottle = makeThrottle(1000)
const photonThrottle = makeThrottle(250)

/**
 * מפתח זהות של מקום ב-OSM. שני הספקים שואבים מאותו מסד, כך שאותו בית כנסת יחזור
 * פעמיים עם place_id שונה לחלוטין — רק צמד (סוג, מזהה) מזהה אותו כאותו מקום.
 */
function osmKey(type: unknown, id: unknown): string | null {
  if (id == null) return null
  const t = String(type ?? '')
    .charAt(0)
    .toUpperCase()
  return t ? `${t}${id}` : `?${id}`
}

/**
 * Photon מחזיר שדות מובנים ולא מחרוזת אחת. הרכבתם לכתובת בסדר של Nominatim —
 * מהפרט אל הכללי — משאירה את `shortAddress` בצד הלקוח עובד בדיוק כמו קודם:
 * הוא מקצץ את הזנב המנהלי (נפה, מחוז, מיקוד, "ישראל") מהסוף.
 */
function photonLabel(p: Record<string, unknown>): string {
  const s = (k: string) => (typeof p[k] === 'string' ? (p[k] as string).trim() : '')
  const street = s('street')
  const num = s('housenumber')
  // בעברית המספר בא אחרי שם הרחוב
  const line = street && num ? `${street} ${num}` : street || num
  const parts = [
    s('name'),
    line,
    s('locality'),
    s('district'),
    s('city'),
    s('county'),
    s('state'),
    s('postcode'),
    s('country'),
  ]
  return [...new Set(parts.filter(Boolean))].join(', ')
}

/**
 * Google Places פעיל רק כשהסוד מוגדר (Supabase Dashboard → Edge Functions →
 * Secrets). מחיקת הסוד היא מתג הכיבוי: הפונקציה חוזרת ל-OSM בלי שינוי קוד.
 */
const GOOGLE_KEY = Deno.env.get('GOOGLE_MAPS_API_KEY') ?? ''

/** השוואת "מתחיל ב-" סלחנית לפיסוק ולרישיות, כדי לא לשכפל שם שכבר בכתובת. */
function foldLabel(s: string): string {
  return s
    .toLowerCase()
    .replace(/["'`.,;:()[\]{}/\\|–—_-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
}

/**
 * Google מפריד בין שם המקום לכתובת. חיבורם — מהפרט אל הכללי, כמו אצל שאר
 * הספקים — משאיר את `shortAddress` בצד הלקוח עובד כרגיל: "אולמי הגן הקסום,
 * הרצל 5, ראשון לציון, ישראל". כשהכתובת עצמה כבר נפתחת בשם (חיפוש רחוב, למשל)
 * אין מה להוסיף.
 */
function googleLabel(place: {
  displayName?: { text?: string }
  formattedAddress?: string
}): string {
  const name = (place.displayName?.text ?? '').trim()
  const addr = (place.formattedAddress ?? '').trim()
  if (!name) return addr
  if (!addr) return name
  if (foldLabel(addr).startsWith(foldLabel(name))) return addr
  return `${name}, ${addr}`
}

async function searchGoogle(q: string): Promise<Suggestion[]> {
  const res = await fetch('https://places.googleapis.com/v1/places:searchText', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': GOOGLE_KEY,
      'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,places.location',
    },
    body: JSON.stringify({
      textQuery: q,
      languageCode: 'he',
      regionCode: 'IL',
      pageSize: 10,
      locationRestriction: {
        rectangle: {
          low: { latitude: IL_LAT_MIN, longitude: IL_LON_MIN },
          high: { latitude: IL_LAT_MAX, longitude: IL_LON_MAX },
        },
      },
    }),
  })
  if (!res.ok) throw new Error(`google ${res.status}`)
  const body = (await res.json()) as {
    places?: Array<{
      id?: string
      displayName?: { text?: string }
      formattedAddress?: string
      location?: { latitude?: number; longitude?: number }
    }>
  }
  return (body.places ?? []).flatMap((p) => {
    const lat = p.location?.latitude
    const lng = p.location?.longitude
    const label = googleLabel(p)
    if (!p.id || typeof lat !== 'number' || typeof lng !== 'number' || !label) return []
    return [{ provider: 'google', place_id: p.id, label, lat, lng }]
  })
}

/**
 * ברירת המחדל היא המופע הציבורי של Photon. `PHOTON_URL` מאפשר להצביע על מופע
 * עצמאי בלי לגעת בקוד, אם התעבורה תגדל מעבר למה שנאה לבקש משירות חינמי.
 */
const PHOTON_URL = Deno.env.get('PHOTON_URL') || 'https://photon.komoot.io/api/'

async function searchPhoton(q: string): Promise<Suggestion[]> {
  const url = new URL(PHOTON_URL)
  url.searchParams.set('q', q)
  url.searchParams.set('limit', '10')
  // Photon תומך ב-default/de/en/fr בלבד; "default" הוא השם המקומי, כלומר עברית
  url.searchParams.set('lang', 'default')
  url.searchParams.set('bbox', IL_BBOX)

  const res = await photonThrottle(() => fetch(url, { headers: { 'User-Agent': UA } }))
  if (!res.ok) throw new Error(`photon ${res.status}`)
  const body = (await res.json()) as {
    features?: Array<{ properties?: Record<string, unknown>; geometry?: { coordinates?: number[] } }>
  }
  return (body.features ?? []).flatMap((f) => {
    const p = f.properties ?? {}
    const [lng, lat] = f.geometry?.coordinates ?? []
    const label = photonLabel(p)
    if (typeof lat !== 'number' || typeof lng !== 'number' || !label) return []
    const key = osmKey(p.osm_type, p.osm_id)
    return [{ provider: 'photon', place_id: key ?? `photon:${lat},${lng}`, label, lat, lng }]
  })
}

async function searchNominatim(q: string): Promise<Suggestion[]> {
  const url = new URL('https://nominatim.openstreetmap.org/search')
  url.searchParams.set('q', q)
  url.searchParams.set('format', 'jsonv2')
  url.searchParams.set('limit', '6')
  url.searchParams.set('countrycodes', 'il')
  url.searchParams.set('accept-language', 'he')

  const res = await nominatimThrottle(() => fetch(url, { headers: { 'User-Agent': UA } }))
  if (!res.ok) throw new Error(`nominatim ${res.status}`)
  const raw = (await res.json()) as Array<Record<string, unknown>>
  return raw.flatMap((r) => {
    const lat = Number(r.lat)
    const lng = Number(r.lon)
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || typeof r.display_name !== 'string') return []
    const key = osmKey(r.osm_type, r.osm_id)
    return [
      {
        provider: 'nominatim',
        place_id: key ?? `nominatim:${r.place_id}`,
        label: r.display_name,
        lat,
        lng,
      },
    ]
  })
}

/** מוסיף לרשימה רק מקומות שעדיין אינם בה, לפי זהות ה-OSM. */
function merge(into: Suggestion[], more: Suggestion[]): Suggestion[] {
  const seen = new Set(into.map((s) => s.place_id))
  for (const s of more) {
    if (seen.has(s.place_id)) continue
    seen.add(s.place_id)
    into.push(s)
  }
  return into
}

/**
 * מילות תיאור שאדם מוסיף מעצמו ולא תמיד קיימות בשם ב-OSM ("אולם שמחות הגן
 * הקסום" כשהשם הוא "הגן הקסום"). מנוסות רק כשלא נמצא כלום — הן דווקא עוזרות
 * כשהן חלק מהשם.
 */
const DESCRIPTORS = new Set([
  'אולם',
  'אולמי',
  'בית',
  'בניין',
  'בנין',
  'גן',
  'גני',
  'היכל',
  'ישיבה',
  'ישיבת',
  'מלון',
  'מרכז',
  'מתחם',
  'קניון',
  'רחוב',
  "רח'",
  'שדרות',
  "שד'",
])

function loosen(q: string): string {
  const kept = q.split(/\s+/).filter((t) => t && !DESCRIPTORS.has(t))
  return kept.length ? kept.join(' ') : ''
}

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'GET') return json({ error: 'method not allowed' }, 405)

  // Whether this function is reachable without a JWT is a dashboard setting
  // (verify_jwt) that is not represented anywhere in this repo, so it is not
  // reviewable and not something a migration can assert. Checking in the body
  // makes the answer part of the code: an open proxy to a public geocoder is
  // both someone else's rate limit to burn and our IP that gets blocked for it.
  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader) return json({ error: 'לא מחובר' }, 401)
  const asUser = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  })
  const { data: claims, error: authErr } = await asUser.auth.getUser()
  if (authErr || !claims?.user) return json({ error: 'לא מחובר' }, 401)

  const url = new URL(req.url)
  // ניקוד וסימני טעמים נדבקים להדבקה מטקסט מנוקד ואף ספק לא מתאים איתם
  const q = (url.searchParams.get('q') ?? '')
    .replace(/[\u0591-\u05C7]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
  if (q.length < 2) return json([])
  // an unbounded query string is just cache keys and upstream bytes
  if (q.length > 200) return json({ error: 'שאילתת חיפוש ארוכה מדי' }, 400)

  // התחילית מבדילה בין מצב Google למצב OSM, כדי שהוספת המפתח (או הסרתו) לא
  // תגיש מ-isolate חם תוצאות שנשמרו מהספק הלא נכון.
  const key = (GOOGLE_KEY ? 'g:' : 'o:') + q.toLowerCase()
  const hit = cacheGet(key)
  if (hit !== null) return json(hit, 200, { 'X-Cache': 'HIT' })

  const out: Suggestion[] = []
  let reachedSomeone = false

  // Google ראשון כשיש מפתח. בלי throttle — זה API בתשלום עם מכסה משלו;
  // ה-throttles נועדו לנימוס מול שירותי ה-OSM החינמיים בנתיב הנסיגה.
  if (GOOGLE_KEY) {
    try {
      merge(out, await searchGoogle(q))
      reachedSomeone = true
    } catch {
      // Google נפל — נתיב ה-OSM למטה מכסה
    }
  }

  // נתיב ה-OSM: הנתיב היחיד כשאין מפתח Google, ורשת הביטחון כשהוא לא החזיר דבר.
  if (out.length === 0) {
    try {
      merge(out, await searchPhoton(q))
      reachedSomeone = true
    } catch {
      // Photon לא זמין — Nominatim למטה עדיין ינסה
    }

    // מעט מדי תוצאות מהספק המשלים-שמות: כתובת מדויקת היא בדיוק מה ש-Nominatim
    // טוב בו, ולכן שווה את שנייית ההמתנה של המכסה שלו.
    if (out.length < 3) {
      try {
        merge(out, await searchNominatim(q))
        reachedSomeone = true
      } catch {
        // ממשיכים עם מה שיש
      }
    }

    // ניסיון אחרון וסלחני: אותה שאילתה בלי מילות התיאור שהמשתמש הוסיף מעצמו.
    // Google לא צריך את זה — הוא כבר סלחני לניסוחים חלקיים.
    if (out.length === 0) {
      const loose = loosen(q)
      if (loose && loose !== q && loose.length >= 2) {
        try {
          merge(out, await searchPhoton(loose))
          reachedSomeone = true
        } catch {
          // אין יותר מה לנסות
        }
      }
    }
  }

  if (!reachedSomeone) return json([], 200, { 'X-Upstream-Status': 'unreachable' })

  const data = out.slice(0, MAX_RESULTS)
  cacheSet(key, data)
  return json(data, 200, { 'X-Cache': 'MISS' })
})
