// notify-dispatch — drains notification_deliveries and sends email/Web Push.
//
// Reliability rule: a delivery MUST be claimed in Postgres before any external
// request is made. Several statement triggers can invoke this Edge Function at
// the same time; selecting status='pending' and marking it only after send lets
// two invocations send the same row. claim_notification_deliveries() (0167)
// uses FOR UPDATE SKIP LOCKED, so every invocation owns a different set.

import { createClient } from 'npm:@supabase/supabase-js@2'
import webpush from 'npm:web-push@3.6.7'

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
    link: string | null
  } | null
  push_subscriptions: { endpoint: string; p256dh: string; auth: string } | null
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405)

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  const { data: secret, error: secretError } = await admin.rpc('get_notify_dispatch_secret')
  if (secretError || !secret) return json({ error: 'dispatch secret not configured' }, 503)
  if (req.headers.get('x-dispatch-secret') !== secret) return json({ error: 'forbidden' }, 403)

  const body = await req.json().catch(() => ({}))
  const one = (body as { delivery_id?: string }).delivery_id ?? null

  // Atomic ownership comes first. A concurrent invocation cannot receive the
  // same id while this claim is fresh.
  const { data: claimed, error: claimError } = await admin.rpc('claim_notification_deliveries', {
    p_delivery_id: one,
    p_limit: BATCH,
  })
  if (claimError) return json({ error: claimError.message }, 500)

  const ids = ((claimed ?? []) as { id: string }[]).map((row) => row.id)
  if (!ids.length) return json({ sent: 0, failed: 0, skipped: 0, gone: 0, claimed: 0 })

  const { data, error } = await admin
    .from('notification_deliveries')
    .select(
      'id, channel, address, attempts, subscription_id, notifications(title, body, type, entity_type, entity_id, link), push_subscriptions(endpoint, p256dh, auth)',
    )
    .in('id', ids)
  if (error) return json({ error: error.message }, 500)

  const deliveries = (data ?? []) as unknown as Delivery[]
  const apiKey = Deno.env.get('RESEND_API_KEY') ?? ''
  const { data: cfg } = await admin
    .from('app_settings')
    .select('key,value')
    .in('key', ['notifications.email', 'notifications.push'])
  const emailCfg = cfg?.find((r) => r.key === 'notifications.email')?.value as
    | { from?: string }
    | undefined
  const pushCfg = cfg?.find((r) => r.key === 'notifications.push')?.value as
    | { enabled?: boolean }
    | undefined
  const from = emailCfg?.from ?? 'ViperLogistics <noreply@example.com>'

  const mark = async (id: string, status: string, err: string | null) => {
    await admin
      .from('notification_deliveries')
      .update({
        status,
        claimed_at: null,
        last_error: err,
        sent_at: status === 'sent' ? new Date().toISOString() : null,
      })
      .eq('id', id)
  }

  const retryOrFail = async (d: Delivery, err: string) => {
    await mark(d.id, d.attempts >= MAX_ATTEMPTS ? 'failed' : 'pending', err)
  }

  let pushInitError: string | null = null
  let pushReady = false
  try {
    if (!pushCfg?.enabled) throw new Error('push channel disabled in app_settings')
    const subject = Deno.env.get('VAPID_SUBJECT') || 'mailto:admin@viperlogistics.app'
    const raw = Deno.env.get('VAPID_KEYS') || ''
    let publicKey = Deno.env.get('VAPID_PUBLIC_KEY') || ''
    let privateKey = Deno.env.get('VAPID_PRIVATE_KEY') || ''
    if (raw) {
      const parsed = JSON.parse(raw)
      publicKey = parsed.publicKey || publicKey
      privateKey = parsed.privateKey || privateKey
    }
    if (!publicKey || !privateKey) throw new Error('VAPID public/private key not configured')
    webpush.setVapidDetails(subject, publicKey, privateKey)
    pushReady = true
  } catch (e) {
    pushInitError = (e as Error).message
  }

  let sent = 0
  let failed = 0
  let skipped = 0
  let gone = 0

  for (const d of deliveries) {
    const n = d.notifications

    if (d.channel === 'email') {
      if (!apiKey) {
        await mark(d.id, 'skipped', 'RESEND_API_KEY not configured')
        skipped++
        continue
      }
      if (!d.address) {
        await mark(d.id, 'skipped', 'no address')
        skipped++
        continue
      }
      try {
        const res = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            from,
            to: [d.address],
            subject: n?.title ?? 'ViperLogistics',
            text: [n?.title, n?.body].filter(Boolean).join('\n\n'),
          }),
        })
        if (!res.ok) {
          const text = await res.text().catch(() => '')
          await retryOrFail(d, `${res.status}: ${text.slice(0, 300)}`)
          failed++
          continue
        }
        await mark(d.id, 'sent', null)
        sent++
      } catch (e) {
        await retryOrFail(d, (e as Error).message.slice(0, 300))
        failed++
      }
      continue
    }

    const sub = d.push_subscriptions
    if (!sub) {
      await mark(d.id, 'skipped', 'no subscription')
      skipped++
      continue
    }
    if (!pushReady) {
      await mark(d.id, 'skipped', pushInitError)
      skipped++
      continue
    }

    // notifications.link is written by app.notification_link. The bell and push
    // therefore navigate to exactly the same destination.
    const payload = JSON.stringify({
      title: n?.title ?? 'ViperLogistics',
      body: (n?.body ?? '').slice(0, 300),
      url: n?.link ?? '/',
      tag: d.id,
      type: n?.type ?? '',
    })

    try {
      await webpush.sendNotification(
        { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
        payload,
        { TTL: 86400 },
      )
      await mark(d.id, 'sent', null)
      await admin
        .from('push_subscriptions')
        .update({ last_seen_at: new Date().toISOString(), failure_count: 0, last_error: null })
        .eq('id', d.subscription_id!)
      sent++
    } catch (e) {
      const ex = e as { statusCode?: number; body?: string }
      const status = ex.statusCode ?? 0
      const detail =
        typeof ex.body === 'string'
          ? ex.body.slice(0, 250)
          : (e as Error).message.slice(0, 250)

      if (status === 404 || status === 410) {
        // FK cascade removes the claimed delivery together with the dead endpoint.
        await admin.from('push_subscriptions').delete().eq('id', d.subscription_id!)
        gone++
        continue
      }
      if (status === 400 || status === 403 || status === 413) {
        await mark(d.id, 'failed', `${status}: ${detail}`)
        await admin
          .from('push_subscriptions')
          .update({ last_error: `${status}: ${detail}` })
          .eq('id', d.subscription_id!)
        failed++
        continue
      }

      await retryOrFail(d, `${status || 'err'}: ${detail}`)
      failed++
    }
  }

  return json({ sent, failed, skipped, gone, claimed: ids.length })
})
