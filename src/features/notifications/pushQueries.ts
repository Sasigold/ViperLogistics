/**
 * רישום וניתוק של מכשירים לדחיפה.
 */
import { useEffect } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import {
  currentSubscription,
  pushSupported,
  serializeSubscription,
  subscribeToPush,
  unsubscribeFromPush,
} from '../../lib/push'
import { usePushConfig } from './notificationQueries'
import type { PushKeys } from '../../lib/push'

/**
 * ‏endpoint הוא המפתח, ולא (profile, endpoint).
 *
 * ה-endpoint שייך לדפדפן ולא לאדם. שני עובדים שמתחלפים על אותו מכשיר —
 * מצב רגיל במחסן — חייבים להעביר בעלות על השורה. בלי onConflict על
 * endpoint השני היה נחסם באילוץ הייחודיות, ואילו ההתראות של הראשון היו
 * ממשיכות להגיע למכשיר שכבר אינו שלו.
 */
async function upsertDevice(keys: PushKeys, profileId: string) {
  const { error } = await supabase.from('push_subscriptions').upsert(
    {
      profile_id: profileId,
      endpoint: keys.endpoint,
      p256dh: keys.p256dh,
      auth: keys.auth,
      user_agent: navigator.userAgent.slice(0, 400),
      last_seen_at: new Date().toISOString(),
      failure_count: 0,
      last_error: null,
    },
    { onConflict: 'endpoint' },
  )
  if (error) throw error
}

export function useEnablePush() {
  const qc = useQueryClient()
  const profileId = useAuth((s) => s.me?.profile.id)
  const { data: cfg } = usePushConfig()
  return useMutation({
    mutationFn: async () => {
      if (!profileId) throw new Error('אין משתמש מחובר')
      const keys = await subscribeToPush(cfg?.vapid_public_key ?? '')
      await upsertDevice(keys, profileId)
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['push_subscriptions'] }),
  })
}

export function useDisablePush() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async () => {
      const endpoint = await unsubscribeFromPush()
      if (!endpoint) return
      const { error } = await supabase.from('push_subscriptions').delete().eq('endpoint', endpoint)
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['push_subscriptions'] }),
  })
}

/** ניתוק מכשיר אחר מהרשימה. */
export function useForgetDevice() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('push_subscriptions').delete().eq('id', id)
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['push_subscriptions'] }),
  })
}

/**
 * הקשבה ללחיצה על התראה שהגיעה לחלון שאינו נשלט על ידי ה-Service Worker.
 *
 * ‏client.navigate() נדחה בחלון כזה, ולכן sw.ts נופל להודעה. בלי המאזין הזה
 * לחיצה על התראה הייתה מעבירה מיקוד לחלון ומשאירה אותו במסך שבו היה.
 */
export function usePushNavigation(navigate: (url: string) => void) {
  useEffect(() => {
    if (!('serviceWorker' in navigator)) return
    const handler = (e: MessageEvent) => {
      const data = e.data as { type?: string; url?: string } | null
      if (data?.type === 'navigate' && data.url) navigate(data.url)
    }
    navigator.serviceWorker.addEventListener('message', handler)
    return () => navigator.serviceWorker.removeEventListener('message', handler)
  }, [navigate])
}

/**
 * מיישר את מה שהדפדפן חושב מול מה שהמסד יודע, בכל עליית אפליקציה.
 *
 * זו הסיבה שאין ב-sw.ts מטפל ל-pushsubscriptionchange: ל-Service Worker אין
 * session של Supabase והוא אינו יכול לכתוב את ה-endpoint החדש. ההשוואה כאן
 * מכסה את אותם מקרים בדיוק — החלפת מפתחות ביוזמת הדפדפן, מנוי שנמחק בשרת
 * אחרי 410, וחשבון אחר שהתחבר על אותו מכשיר.
 */
export function usePushSync() {
  const profileId = useAuth((s) => s.me?.profile.id)
  useEffect(() => {
    if (!profileId || !pushSupported()) return
    if (Notification.permission !== 'granted') return
    let cancelled = false
    void (async () => {
      try {
        const sub = await currentSubscription()
        if (!sub || cancelled) return
        await upsertDevice(serializeSubscription(sub), profileId)
      } catch {
        // סנכרון שקט. כישלון כאן אינו משהו שהמשתמש יכול לתקן, והמכשיר
        // ייבדק שוב בעלייה הבאה.
      }
    })()
    return () => {
      cancelled = true
    }
  }, [profileId])
}
