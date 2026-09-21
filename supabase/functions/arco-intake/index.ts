// arco-intake — הדלת שדרכה שני התרחישים של ארקו ב-Make מדברים איתנו.
//
//   POST /functions/v1/arco-intake/event   פתיחת הזמנה → אירוע + משימות + מחיר
//   POST /functions/v1/arco-intake/spec    מפרט חדש    → גרסה ברשימת המפרטים
//
// חייבת להיפרס עם `--no-verify-jwt`: המודול ב-Make נושא סוד משותף משלנו ולא
// ‏JWT של Supabase, ושער ה-JWT היה עונה 401 לפני שהקוד כאן רץ בכלל.
//
//   supabase functions deploy arco-intake --no-verify-jwt
//
// סודות (סודות של פונקציית קצה, לא המסד — 0182 §1):
//   ARCO_INTAKE_SECRET   הסוד המשותף. אותו ערך יושב בכותרת x-arco-secret
//                        של מודול ה-HTTP בשני התרחישים.
//
// למה התשובה תמיד 200 כשהמעטפה הגיעה: תרחיש ב-Make שמקבל 4xx נעצר ומסמן
// את עצמו כשבור, ומשלוח אחד שלא ידענו לעכל היה מפיל את הצינור כולו. כישלון
// עסקי חוזר כ-`status: "failed"` בגוף, נרשם כשורה אדומה במסך האינטגרציות,
// ויש לו כפתור "הרץ מחדש". רק תקלה אצלנו (סוד חסר, המסד לא ענה) מחזירה 5xx,
// שהוא הסטטוס היחיד שבגללו כדאי ל-Make לנסות שוב.

import { createClient } from 'npm:@supabase/supabase-js@2'
import { EVENT_KEYS, SPEC_KEYS, pick, pickSuggestion, routeFromPath, timingSafeEqual } from '../_shared/arco.ts'

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  })
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

/**
 * מיקום האירוע מגיע מארקו כטקסט בלבד, והמחיר אצלנו נגזר מאזור הנסיעה שהפין
 * נופל בתוכו (`app.pricing_vars` → `zone_for_point`, 0017). אירוע בלי פין
 * הוא אירוע עם `travel_hours` ריק — כלומר **מחיר נמוך מהאמת**, שנשלח ללקוח
 * כאילו הוא סופי. לכן הכתובת עוברת דרך `geocode-proxy` — אותו גיאוקודר,
 * אותו דירוג ואותו מטמון שהמסך משתמש בהם, ולא מימוש שני שיסטה ממנו.
 *
 * נכשל? האירוע נפתח בלי פין, והתשובה אומרת `location_resolved: false`. אין
 * שום סיבה שכתובת שהגיאוקודר לא הכיר תמנע פתיחת אירוע.
 */
async function geocode(query: string): Promise<Record<string, unknown>> {
  const q = query.trim()
  if (q.length < 3) return {}
  try {
    const res = await fetch(
      `${SUPABASE_URL}/functions/v1/geocode-proxy?q=${encodeURIComponent(q)}`,
      { headers: { Authorization: `Bearer ${SERVICE_KEY}`, apikey: SERVICE_KEY } },
    )
    if (!res.ok) return {}
    const hit = pickSuggestion(await res.json())
    if (!hit) return {}
    return {
      location_lat: hit.lat,
      location_lng: hit.lng,
      location_provider: hit.provider,
      location_place_id: hit.place_id,
    }
  } catch {
    return {}
  }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method not allowed' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json', Allow: 'POST' },
    })
  }

  const secret = Deno.env.get('ARCO_INTAKE_SECRET') ?? ''
  // סוד שלא הוגדר הוא התקלה שלנו ולא שלהם: 503 הוא מצב שכדאי לנסות שוב.
  if (secret === '') return json({ error: 'intake secret not configured' }, 503)

  const presented = req.headers.get('x-arco-secret') ?? ''
  if (!timingSafeEqual(presented, secret)) return json({ error: 'unauthorized' }, 401)

  const route = routeFromPath(req.url)
  if (route !== 'event' && route !== 'spec') {
    return json({ error: 'unknown route — use /event or /spec' }, 404)
  }

  // שני קידודים, ובמכוון: מודול ה-HTTP ב-Make שולח `x-www-form-urlencoded`,
  // שבו Make עצמו מקודד כל ערך — ולכן הערה חופשית שיש בה גרש או שורה חדשה
  // אינה שוברת את הגוף. גוף JSON נתמך כדי שאפשר יהיה לקרוא לכאן ב-curl
  // ומכל מי שיבוא אחרי Make.
  const raw = await req.text()
  let body: unknown
  if ((req.headers.get('Content-Type') ?? '').includes('x-www-form-urlencoded')) {
    body = Object.fromEntries(new URLSearchParams(raw))
  } else {
    try {
      body = JSON.parse(raw)
    } catch {
      return json({ error: 'invalid json' }, 400)
    }
  }

  const admin = createClient(SUPABASE_URL, SERVICE_KEY)

  if (route === 'spec') {
    const { data, error } = await admin.rpc('arco_ingest_spec', {
      p_payload: pick(body, SPEC_KEYS),
      p_meta: {},
    })
    if (error) {
      console.error('arco_ingest_spec failed', error)
      return json({ error: 'ingest unavailable' }, 503)
    }
    return json(data)
  }

  const payload = pick(body, EVENT_KEYS)
  const located = typeof payload.location === 'string' ? await geocode(payload.location) : {}

  const { data, error } = await admin.rpc('arco_ingest_event', {
    p_payload: { ...payload, ...located },
    p_meta: {},
  })
  if (error) {
    console.error('arco_ingest_event failed', error)
    return json({ error: 'ingest unavailable' }, 503)
  }

  // התשובה היא מה שהתרחיש מעביר הלאה ל-webhook של המחירים: האירוע, משימותיו
  // והמחיר של כל אחת. `location_resolved` אומר לרכז אם צריך לסמן פין ביד —
  // בלעדיו המחיר שיצא חסר את שעות הנסיעה.
  const result = (data ?? {}) as Record<string, unknown>
  return json({ ...result, location_resolved: Object.keys(located).length > 0 })
})
