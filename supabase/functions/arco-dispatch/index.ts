// arco-dispatch — מנקז את תור הדיווח של ארקו (מיגרציה 0184) אל ה-webhook
// שהיא נתנה לנו.
//
// שתי דרכים להגיע לכאן, ושתיהן מנקזות את אותו תור במלואו:
//   • הטריגר `event_activity_arco_outbound` מצלצל דרך pg_net אחרי כל שמירה
//     ששינתה משהו באירוע של ארקו;
//   • קריאה מתוזמנת (או כפתור "שלח שוב" במסך), כרשת ביטחון.
//
//   supabase functions deploy arco-dispatch --no-verify-jwt
//
// סודות:
//   ARCO_DISPATCH_SECRET     מה שהטריגר שולח בכותרת x-arco-secret. חייב
//                            להיות זהה ל-GUC ‏app.arco_dispatch_secret.
//   ARCO_EVENT_WEBHOOK_URL   כתובת ה-webhook של התרחיש ב-Make שמקבל את
//                            העדכונים. היא סוד לכל דבר: מי שמחזיק אותה
//                            יכול לכתוב לתרחיש.
//   ARCO_WEBHOOK_TOKEN       רשות. אם הוגדר, נשלח ככותרת x-viper-token —
//                            כדי שהתרחיש בצד השני יוכל לדעת שזה אנחנו.
//
// כל הודעה מסומנת בנפרד: מה שנשלח יורד מהתור, ומה שנדחה חוזר אליו עם
// מספר הניסיון. חמישה ניסיונות ודי (0184 §4).

import { createClient } from 'npm:@supabase/supabase-js@2'
import { timingSafeEqual } from '../_shared/arco.ts'

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  })
}

const BATCH = 50

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method not allowed' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json', Allow: 'POST' },
    })
  }

  const secret = Deno.env.get('ARCO_DISPATCH_SECRET') ?? ''
  if (secret === '') return json({ error: 'dispatch secret not configured' }, 503)
  if (!timingSafeEqual(req.headers.get('x-arco-secret') ?? '', secret)) {
    return json({ error: 'unauthorized' }, 401)
  }

  const target = Deno.env.get('ARCO_EVENT_WEBHOOK_URL') ?? ''
  // בלי כתובת אין לאן לשלוח — והתור ממתין כפי שהוא, במכוון: ברגע שהכתובת
  // תוגדר, הניקוז הבא ישלח גם את מה שהצטבר.
  if (target === '') return json({ skipped: 'no webhook url configured' }, 200)

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  const { data, error } = await admin.rpc('arco_outbound_pending', { p_limit: BATCH })
  if (error) {
    console.error('arco_outbound_pending failed', error)
    return json({ error: 'queue unavailable' }, 503)
  }

  const pending = (data ?? []) as Array<Record<string, unknown>>
  let sent = 0
  let failed = 0

  for (const message of pending) {
    const id = message.outbound_id as string
    try {
      const res = await fetch(target, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(Deno.env.get('ARCO_WEBHOOK_TOKEN')
            ? { 'x-viper-token': Deno.env.get('ARCO_WEBHOOK_TOKEN')! }
            : {}),
        },
        body: JSON.stringify(message),
      })
      const ok = res.ok
      ok ? sent++ : failed++
      await admin.rpc('arco_outbound_mark', {
        p_id: id,
        p_ok: ok,
        p_status: res.status,
        p_error: ok ? null : (await res.text()).slice(0, 500),
      })
    } catch (e) {
      failed++
      await admin.rpc('arco_outbound_mark', {
        p_id: id,
        p_ok: false,
        p_status: null,
        p_error: String(e).slice(0, 500),
      })
    }
  }

  return json({ drained: pending.length, sent, failed })
})
