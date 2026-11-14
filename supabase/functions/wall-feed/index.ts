/**
 * פיד הקיר — מה שמסך הפיקוד של ViperGroup קורא מכאן (0202).
 *
 * למה פונקציה ולא PostgREST ישיר: הקיר אינו משתמש. אין לו JWT, ולכן כל
 * `app.has()` שקר אצלו, ו-`work_board_view`/`dashboard_sections`/`app.margin_summary`
 * סגורים לו בדיוק כמו שהם צריכים להיות. ומפתח service role על מכשיר שתלוי
 * על קיר היה פותח את כל המסד. לכן הקיר מחזיק סוד אחד שאפשר לבטל, הפונקציה
 * הזו מחזיקה את המפתח, והמסד הוא שמחליט אם הסוד נכון.
 *
 * הפונקציה עצמה כמעט ריקה בכוונה: הבדיקה, הכללים העסקיים ("היום" בישראל,
 * מה נספר בכסף, מי מאחר) והצורה של ה-JSON יושבים ב-`public.wall_snapshot`
 * וב-`app.wall_snapshot_at` — מקום אחד שנבדק בחבילת ה-SQL (57_wall_feed).
 * החוזה מול הקיר: docs/FEEDS.md §1 ב-ViperGroup.
 *
 * ‏**הסוד אינו כאן ואינו בסודות של הפונקציה.** ב-Vault יושב רק ה-sha256 שלו,
 * והמסד משווה. אפשר כמה סודות במקביל — כל שורה ששמה מתחיל ב-
 * `wall_feed_secret` (‏`wall_feed_secret` ל-Vercel, `wall_feed_secret_minipc`
 * ל-Mini PC) והסוד מתקבל אם הוא שווה לאחת מהן. כך החלפת סוד היא שורת SQL
 * אחת, בלי פריסה, והקירות האחרים אינם מושפעים:
 *
 *   select vault.update_secret(
 *     (select id from vault.secrets where name = 'wall_feed_secret_minipc'),
 *     encode(sha256(convert_to('<סוד חדש, 32+ תווים>', 'UTF8')), 'hex'));
 *
 * בקשה: ‏GET או POST, כותרת `x-wall-secret`, ואופציונלית `?days=1..14`
 * (ברירת מחדל 3; המסד חותך בעצמו). תשובות:
 *   200 — התמונה (`Cache-Control: no-store` — היא של הרגע הזה)
 *   401 — אין סוד, או שהוא שגוי או קצר (‏SQLSTATE 28P01)
 *   503 — אין אף hash תקין ב-Vault (‏55000)
 *   500 — כל השאר. ההודעה של המסד נרשמת ביומן הפונקציה ואינה יוצאת החוצה.
 * אין CORS: הקורא הוא שרת (ה-route של ViperGroup), לא דפדפן.
 *
 * פריסה: ‏`supabase functions deploy wall-feed --no-verify-jwt` — אין JWT
 * לאמת, והסוד הוא השער.
 */
import { createClient } from 'npm:@supabase/supabase-js@2'

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
    },
  })
}

/** ‏`?days=` כמספר שלם בטווח 1..14, ו-3 כשאין או שאינו מספר. */
function parseDays(raw: string | null): number {
  if (raw === null || raw.trim() === '') return 3
  const n = Number.parseInt(raw, 10)
  if (!Number.isFinite(n)) return 3
  return Math.min(14, Math.max(1, n))
}

Deno.serve(async (req) => {
  if (req.method !== 'GET' && req.method !== 'POST') return json({ error: 'method not allowed' }, 405)

  const secret = req.headers.get('x-wall-secret') ?? ''
  // ריק — אין מה לשאול את המסד. ארוך מאוד — אין סוד כזה, ואין סיבה להעביר אותו.
  if (!secret || secret.length > 512) return json({ error: 'unauthorized' }, 401)

  const url = Deno.env.get('SUPABASE_URL')
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!url || !key) return json({ error: 'not configured' }, 503)

  const admin = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const days = parseDays(new URL(req.url).searchParams.get('days'))
  const { data, error } = await admin.rpc('wall_snapshot', { p_secret: secret, p_days: days })

  if (error) {
    if (error.code === '28P01') return json({ error: 'unauthorized' }, 401)
    if (error.code === '55000') return json({ error: 'not configured' }, 503)
    console.error('wall_snapshot failed', error.code, error.message)
    return json({ error: 'internal error' }, 500)
  }

  return json(data)
})
