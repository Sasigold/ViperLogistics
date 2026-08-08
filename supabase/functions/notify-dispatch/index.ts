/**
 * מנקז את outbox ההתראות ושולח מייל ו-Web Push.
 *
 * נקרא בשתי דרכים, ובכוונה לא רק באחת:
 *   • pg_net, מהטריגר על notification_deliveries — מיידי. הטריגר הוא
 *     statement-level מאז 0046, ולכן התראה שיוצאת לארבעה מכשירים ולמייל
 *     מייצרת קריאה אחת ולא חמש.
 *   • קריאה חיצונית (תזמון) בלי גוף — מנקז את כל מה שממתין, כולל מה שנכשל
 *     קודם. בלי זה כישלון רגעי אצל ספק היה אובד לתמיד.
 *
 * הזהות כאן היא של המערכת ולא של משתמש, ולכן הגישה היא service role ישירות
 * לטבלאות. ה-RPCs notification_pending/notification_mark קיימים לאדם שרוצה
 * להסתכל או לנסות שוב ידנית, והם מגודרים במפתח — כאן הם לא בשימוש, כי
 * app.require היה נכשל בהיעדר JWT של משתמש.
 *
 * משתני סביבה:
 *   NOTIFY_DISPATCH_SECRET  — חייב להתאים ל-app.notify_dispatch_secret
 *   RESEND_API_KEY          — בלעדיו משלוח מייל מסומן skipped ולא נכשל
 *   VAPID_KEYS              — JSON של זוג מפתחות VAPID (ראו README)
 *   VAPID_SUBJECT           — 'mailto:...' שמזהה את השולח מול שירות הדחיפה
 */
import { createClient } from 'npm:@supabase/supabase-js@2'
/**
 * ספריית ה-push נבחרה ל-Deno ולא ל-Node.
 *
 * npm:web-push היא הבחירה המתבקשת, אבל היא נשענת על node:https ועל
 * crypto.createECDH — בדיוק החלקים של שכבת התאימות שנוטים לזוז בין גרסאות
 * של ה-Edge Runtime. כישלון שם אינו רועש: הוא שורה שנשארת pending. הספרייה
 * הזו כתובה ל-Web Crypto, מממשת RFC 8291 ו-RFC 8292, ומתועדת לשימוש ב-
 * Supabase Edge Functions.
 */
import * as webpush from 'jsr:@negrel/webpush@0.3'

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
  channel: 'email' | 'push'
  address: string | null
  attempts: number
  subscription_id: string | null
  notifications: {
    title: string
    body: string | null
    type: string
    entity_type: string | null
    entity_id: string | null
  } | null
  push_subscriptions: { endpoint: string; p256dh: string; auth: string } | null
}

/**
 * לאן ההתראה מובילה כשלוחצים עליה.
 *
 * המפה יושבת כאן ולא ב-Service Worker במכוון: ה-SW צריך להישאר טיפש ולהציג
 * מה שקיבל, אחרת כל שינוי בניתוב היה מחייב פריסה של worker חדש והמתנה עד
 * שכל מכשיר יחליף אותו.
 *
 * שימו לב שאין מסך למשימה בודדת (‏router.tsx) — 'task' מוביל ללוח העבודה.
 */
function linkFor(type: string, entityType: string | null, entityId: string | null): string {
  if (entityType === 'event' && entityId) return `/events/${entityId}`
  if (entityType === 'task') return '/board'
  if (entityType === 'attendance_entry') {
    return type === 'attendance_submitted' ? '/attendance' : '/my/attendance'
  }
  return '/'
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
    .select(
      'id, channel, address, attempts, subscription_id, ' +
        'notifications(title, body, type, entity_type, entity_id), ' +
        'push_subscriptions(endpoint, p256dh, auth)',
    )
    .eq('status', 'pending')
    .lt('attempts', MAX_ATTEMPTS)
    .order('created_at')
    .limit(BATCH)
  if (one) q = q.eq('id', one)

  const { data, error } = await q
  if (error) return json({ error: error.message }, 500)
  const deliveries = (data ?? []) as unknown as Delivery[]
  if (deliveries.length === 0) return json({ sent: 0, failed: 0, skipped: 0, gone: 0 })

  const apiKey = Deno.env.get('RESEND_API_KEY') ?? ''
  const { data: cfg } = await admin
    .from('app_settings')
    .select('key, value')
    .in('key', ['notifications.email', 'notifications.push'])
  const emailCfg = cfg?.find((r) => r.key === 'notifications.email')?.value as
    | { from?: string }
    | undefined
  const pushCfg = cfg?.find((r) => r.key === 'notifications.push')?.value as
    | { enabled?: boolean }
    | undefined
  const from = emailCfg?.from ?? 'ViperLogistics <noreply@example.com>'

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

  /**
   * שרת האפליקציה נבנה פעם אחת ורק אם באמת יש push בתור. ImportVapidKeys
   * עושה ייבוא מפתחות, ואין סיבה לשלם עליו כשהאצווה כולה מיילים.
   */
  let appServer: webpush.ApplicationServer | null = null
  let pushInitError: string | null = null
  const pushServer = async () => {
    if (appServer || pushInitError) return appServer
    const raw = Deno.env.get('VAPID_KEYS') ?? ''
    const subject = Deno.env.get('VAPID_SUBJECT') ?? ''
    if (!raw || !subject) {
      pushInitError = 'VAPID_KEYS/VAPID_SUBJECT not configured'
      return null
    }
    if (!pushCfg?.enabled) {
      pushInitError = 'push channel disabled in app_settings'
      return null
    }
    try {
      const keys = await webpush.importVapidKeys(JSON.parse(raw), { extractable: false })
      appServer = await webpush.ApplicationServer.new({ contactInformation: subject, vapidKeys: keys })
      return appServer
    } catch (e) {
      pushInitError = `vapid init failed: ${(e as Error).message}`
      return null
    }
  }

  let sent = 0
  let failed = 0
  let skipped = 0
  let gone = 0

  for (const d of deliveries) {
    const n = d.notifications

    // ===== מייל =====
    if (d.channel === 'email') {
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
      continue
    }

    // ===== Push =====
    const sub = d.push_subscriptions
    if (!sub) {
      await mark(d.id, 'skipped', 'no subscription', d.attempts)
      skipped++
      continue
    }

    const server = await pushServer()
    if (!server) {
      await mark(d.id, 'skipped', pushInitError, d.attempts)
      skipped++
      continue
    }

    // המטען חייב להישאר קטן: אחרי ההצפנה יש תקרה של ~4KB, וגוף ארוך של
    // התראה אינו שווה משלוח שנדחה כולו.
    const payload = JSON.stringify({
      title: n?.title ?? 'ViperLogistics',
      body: (n?.body ?? '').slice(0, 300),
      url: linkFor(n?.type ?? '', n?.entity_type ?? null, n?.entity_id ?? null),
      tag: d.id,
      type: n?.type ?? '',
    })

    try {
      await server
        .subscribe({ endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } })
        .pushTextMessage(payload, { ttl: 86_400 })
      await mark(d.id, 'sent', null, d.attempts)
      await admin
        .from('push_subscriptions')
        .update({ last_seen_at: new Date().toISOString(), failure_count: 0, last_error: null })
        .eq('id', d.subscription_id!)
      sent++
    } catch (e) {
      const status = (e as { response?: Response }).response?.status ?? 0

      /*
       * 404/410 הם התשובה של שירות הדחיפה על מנוי שכבר אינו קיים — דפדפן
       * שנמחק, אפליקציה שהוסרה, מפתחות שהוחלפו. אין טעם לנסות שוב, ולכן
       * המנוי נמחק. מחיקתו מפילה בקסקייד גם את שורות המשלוח שתלויות בו,
       * ולכן אין כאן mark: השורה כבר איננה.
       */
      if (status === 404 || status === 410) {
        await admin.from('push_subscriptions').delete().eq('id', d.subscription_id!)
        gone++
        continue
      }

      // 400 (בקשה פגומה) ו-413 (מטען גדול מדי) לא ישתפרו בניסיון השישי
      if (status === 400 || status === 413) {
        await mark(d.id, 'failed', `${status}: ${(e as Error).message.slice(0, 200)}`, d.attempts)
        await admin
          .from('push_subscriptions')
          .update({ last_error: `${status}` })
          .eq('id', d.subscription_id!)
        failed++
        continue
      }

      // 429 ו-5xx ותקלות רשת — ננסה שוב בניקוז הבא
      await mark(d.id, 'pending', `${status || 'err'}: ${(e as Error).message.slice(0, 200)}`, d.attempts)
      failed++
    }
  }

  return json({ sent, failed, skipped, gone })
})
