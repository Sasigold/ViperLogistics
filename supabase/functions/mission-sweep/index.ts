/**
 * תזכורות חדר המלחמה — הזרוע המתוזמנת של `missions_sweep()` (0227 §6).
 *
 * אותו מבנה של `fleet-expiry-sweep`: אין pg_cron, ואין אירוע שורה שאומר
 * "היעד עבר". כל ההיגיון — הספים (24 שעות, שעה, עבר), מכתב הבוקר מ-08:00
 * ואידמפוטנטיות — יושב ב-RPC ונבדק בחבילה 74. מה שכאן הוא הזהות והשער.
 *
 * הדף עצמו מריץ את הסריקה כשמנהל פותח אותו; התזמון הוא מה שמביא את
 * התזכורת לטלפון כשאיש אינו בדף. הכוונה היא הרצה כל 15 דקות.
 *
 * משתני סביבה:
 *   MISSION_SWEEP_SECRET — חייב להתאים לכותרת x-sweep-secret שהתזמון שולח
 *
 * ‏supabase secrets set MISSION_SWEEP_SECRET='<אקראי>'
 * ‏supabase functions deploy mission-sweep --no-verify-jwt
 * ותזמון כל 15 דקות: POST בלי גוף, עם הכותרת.
 */
import { createClient } from 'npm:@supabase/supabase-js@2'

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405)

  const secret = Deno.env.get('MISSION_SWEEP_SECRET') ?? ''
  if (!secret) return json({ error: 'sweep secret not configured' }, 503)
  if (req.headers.get('x-sweep-secret') !== secret) return json({ error: 'forbidden' }, 403)

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  // בלי JWT ה-RPC מדלג על השער של מנהלי המערכת — ההרשאה נאכפת על הנמענים.
  const { data, error } = await admin.rpc('missions_sweep')
  if (error) return json({ error: error.message }, 500)

  return json(data ?? { reminders: 0, digests: 0 })
})
