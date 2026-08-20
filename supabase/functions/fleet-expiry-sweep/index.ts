/**
 * סריקת תוקף מסמכי הרכב — הזרוע המתוזמנת של `fleet_expiry_sweep()` (0089 §9).
 *
 * למה פונקציה ולא טריגר: אין ברפו pg_cron, ואין אירוע שורה שאומר "עבר יום".
 * ‏notify-dispatch נקראת גם מ-pg_net כי יש לה טריגר טבעי — שורת משלוח חדשה;
 * לפקיעת מסמך אין אחד, ולכן הדלת היחידה היא קריאה חיצונית מתוזמנת. הכוונה
 * היא הרצה יומית אחת.
 *
 * הפונקציה עצמה כמעט ריקה בכוונה: כל ההיגיון — הספים, האידמפוטנטיות ובחירת
 * הנמענים — יושב ב-RPC, מקום אחד שגם נבדק בחבילת ה-SQL (19_vehicles). מה
 * שכאן הוא הזהות והשער.
 *
 * הקריאה בטוחה לחזור על עצמה: ה-RPC רושם כל (מסמך, תאריך פקיעה, סף) שכבר
 * נשלח, ונועל נעילה מייעצת לכל משך הטרנזקציה — שתי הרצות במקביל אינן שולחות
 * פעמיים ואינן נופלות זו על זו.
 *
 * משתני סביבה:
 *   FLEET_SWEEP_SECRET — חייב להתאים לכותרת x-sweep-secret שהתזמון שולח
 *
 * ‏supabase secrets set FLEET_SWEEP_SECRET='<אקראי>'
 * ותזמון יומי: POST בלי גוף, עם הכותרת.
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

  const secret = Deno.env.get('FLEET_SWEEP_SECRET') ?? ''
  // בלי סוד מוגדר הפונקציה מסרבת במקום לרוץ פתוחה — כמו notify-dispatch
  if (!secret) return json({ error: 'sweep secret not configured' }, 503)
  if (req.headers.get('x-sweep-secret') !== secret) return json({ error: 'forbidden' }, 403)

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  /*
   * זהות ה-service role היא בלי JWT, ולכן ה-RPC מדלג על app.require ורואה
   * את כל הצי — זו בדיוק ההבחנה שהוא עושה בראשו. ההרשאה נאכפת על מי *מקבל*
   * את ההתראה, לא על מי מריץ את הבדיקה.
   */
  const { data, error } = await admin.rpc('fleet_expiry_sweep')
  if (error) return json({ error: error.message }, 500)

  return json(data ?? { documents: 0, notifications: 0, suppressed: 0 })
})
