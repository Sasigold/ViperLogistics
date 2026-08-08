/// <reference lib="webworker" />
/**
 * ה-Service Worker של האפליקציה.
 *
 * עד 0046 לא היה כאן קובץ בכלל: vite-plugin-pwa רץ ב-generateSW ו-Workbox
 * ייצר worker שכל תפקידו precache. ‏Push מחייב handler משלנו — הדפדפן מעיר
 * את ה-worker כשמגיעה הודעה, והאפליקציה עצמה אינה רצה באותו רגע — ולכן
 * הקובץ הזה קיים, ולכן הוא נושא גם את ה-precache שהיה מיוצר קודם.
 *
 * ה-worker נשאר טיפש בכוונה: הוא מציג את מה שקיבל ומנווט לכתובת שקיבל.
 * ההחלטה מה נשלח, למי ולאן הוא מוביל נעשית בשרת (‏notify-dispatch), כי
 * worker מתחלף לאט — כל שינוי כאן ממתין עד שכל מכשיר יוריד גרסה חדשה.
 */
import { clientsClaim } from 'workbox-core'
import { cleanupOutdatedCaches, createHandlerBoundToURL, precacheAndRoute } from 'workbox-precaching'
import { NavigationRoute, registerRoute } from 'workbox-routing'

declare const self: ServiceWorkerGlobalScope & {
  __WB_MANIFEST: (string | { url: string; revision: string | null })[]
}

interface PushPayload {
  title?: string
  body?: string
  url?: string
  tag?: string
  type?: string
}

/*
 * ‏registerType: 'autoUpdate' סיפק את שני אלה בעצמו ב-generateSW. באסטרטגיה
 * הזו הם באחריותנו, ובלעדיהם המשתמשים היו נתקעים על worker ישן — תקלה גרועה
 * יותר מהתכונה שנוספת כאן.
 */
self.skipWaiting()
clientsClaim()
cleanupOutdatedCaches()

precacheAndRoute(self.__WB_MANIFEST)

// SPA: כל ניווט מוגש מ-index.html. הרשימה השחורה היא הנתיבים שאינם מסכים.
registerRoute(
  new NavigationRoute(createHandlerBoundToURL('index.html'), {
    denylist: [/^\/functions\//, /^\/rest\//, /^\/auth\//, /^\/storage\//],
  }),
)

self.addEventListener('push', (event: PushEvent) => {
  // מטען פגום או ריק אינו סיבה לזרוק: handler שנופל גורם לדפדפן להציג הודעה
  // גנרית משלו ("האתר עודכן ברקע"), וזה גרוע מהודעה סתמית שלנו.
  let data: PushPayload = {}
  try {
    data = (event.data?.json() ?? {}) as PushPayload
  } catch {
    data = { body: event.data?.text() }
  }

  const title = data.title || 'ViperLogistics'
  event.waitUntil(
    self.registration.showNotification(title, {
      body: data.body || '',
      // בלי שני אלה עברית עם סימני פיסוק מוצגת הפוך באנדרואיד
      dir: 'rtl',
      lang: 'he',
      icon: '/icons/icon-192.png',
      badge: '/icons/badge-96.png',
      tag: data.tag,
      data: { url: data.url || '/' },
    }),
  )
})

self.addEventListener('notificationclick', (event: NotificationEvent) => {
  event.notification.close()
  const url = (event.notification.data as { url?: string } | undefined)?.url || '/'

  event.waitUntil(
    (async () => {
      const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      for (const client of clients) {
        if (new URL(client.url).origin !== self.location.origin) continue
        await client.focus()
        try {
          await client.navigate(url)
        } catch {
          // חלון שאינו נשלט על ידי ה-worker דוחה navigate. ההודעה מאפשרת
          // לאפליקציה עצמה לנווט דרך ה-router שלה.
          client.postMessage({ type: 'navigate', url })
        }
        return
      }
      await self.clients.openWindow(url)
    })(),
  )
})
