/**
 * מנקז את outbox ההתראות ושולח מייל.
 *
 * נקרא בשתי דרכים, ובכוונה לא רק באחת:
 *   • pg_net, מהטריגר על notification_deliveries — מיידי.
 *   • קריאה חיצונית (תזמון) בלי גוף — מנקז את כל מה שממתין, כולל מה שנכשל
 *     קודם. בלי זה כישלון רגעי אצל ספק הדואר היה אובד לתמיד.
 *
 * הזהות כאן היא של המערכת ולא של משתמש, ולכן הגישה היא service role ישירות
 * לטבלאות. ה-RPCs notification_pending/notification_mark קיימים לאדם שרוצה
 * להסתכל או לנסות שוב ידנית, והם מגודרים במפתח — כאן הם לא בשימוש, כי
 * app.require היה נכשל בהיעדר JWT של משתמש.
 *
 * משתני סביבה:
 *   NOTIFY_DISPATCH_SECRET  — חייב להתאים ל-app.notify_dispatch_secret
 *   RESEND_API_KEY          — בלעדיו הפונקציה מסמנת skipped ולא נכשלת
 */
import { createClient } from 'npm:@supabase/supabase-js@2'

const MAX_ATTEMPTS = 5
const BATCH = 50

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

interface Delivery {
  id: string
  address: string | null
  attempts: number
  notifications: { title: string; body: string | null; type: string } | null
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405)

  const secret = Deno.env.get('NOTIFY_DISPATCH_SECRET') ?? ''
  // בלי סוד מוגדר הפונקציה מסרבת במקום לרוץ פתוחה
  if (!secret) return json({ error: 'dispatch secret not configured' }, 503)
  if (req.headers.get('x-dispatch-secret') !== secret) return json({ error: 'forbidden' }, 403)

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  const body = await req.json().catch(() => ({}))
  const one = (body as { delivery_id?: string }).delivery_id

  let q = admin
    .from('notification_deliveries')
    .select('id, address, attempts, notifications(title, body, type)')
    .eq('status', 'pending')
    .lt('attempts', MAX_ATTEMPTS)
    .order('created_at')
    .limit(BATCH)
  if (one) q = q.eq('id', one)

  const { data, error } = await q
  if (error) return json({ error: error.message }, 500)
  const deliveries = (data ?? []) as unknown as Delivery[]
  if (deliveries.length === 0) return json({ sent: 0, failed: 0, skipped: 0 })

  const apiKey = Deno.env.get('RESEND_API_KEY') ?? ''
  const { data: cfg } = await admin
    .from('app_settings')
    .select('value')
    .eq('key', 'notifications.email')
    .maybeSingle()
  const from = (cfg?.value as { from?: string } | null)?.from ?? 'ViperLogistics <noreply@example.com>'

  const mark = async (id: string, status: string, err: string | null, attempts: number) => {
    await admin
      .from('notification_deliveries')
      .update({
        status,
        attempts: attempts + 1,
        last_error: err,
        sent_at: status === 'sent' ? new Date().toISOString() : null,
      })
      .eq('id', id)
  }

  let sent = 0
  let failed = 0
  let skipped = 0

  for (const d of deliveries) {
    // מפתח חסר אינו כישלון של ההתראה הזו אלא של ההגדרה, ולכן הוא לא
    // צורך ניסיונות חוזרים
    if (!apiKey) {
      await mark(d.id, 'skipped', 'RESEND_API_KEY not configured', d.attempts)
      skipped++
      continue
    }
    if (!d.address) {
      await mark(d.id, 'skipped', 'no address', d.attempts)
      skipped++
      continue
    }

    const n = d.notifications
    try {
      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from,
          to: [d.address],
          subject: n?.title ?? 'ViperLogistics',
          text: [n?.title, n?.body].filter(Boolean).join('\n\n'),
        }),
      })
      if (!res.ok) {
        const text = await res.text().catch(() => '')
        await mark(d.id, 'pending', `${res.status}: ${text.slice(0, 300)}`, d.attempts)
        failed++
        continue
      }
      await mark(d.id, 'sent', null, d.attempts)
      sent++
    } catch (e) {
      // נשאר pending כדי שהניקוז הבא ינסה שוב, עד MAX_ATTEMPTS
      await mark(d.id, 'pending', (e as Error).message.slice(0, 300), d.attempts)
      failed++
    }
  }

  return json({ sent, failed, skipped })
})
