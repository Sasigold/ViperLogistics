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
import { NetworkFirst } from 'workbox-strategies'
import { ExpirationPlugin } from 'workbox-expiration'

declare const self: ServiceWorkerGlobalScope & {
  __WB_MANIFEST: (string | { url: string; revision: string | null })[]
}

/* tsconfig.worker.json מגדיר `types: []` במכוון (ראו ההערה שם), ולכן
   ImportMeta.env של vite/client לא קיים כאן ומוצהר מקומית. Vite עדיין
   מטמיע את הערך בזמן build — ה-worker נבנה באותו pipeline. */
declare global {
  interface ImportMeta {
    readonly env: { readonly VITE_SUPABASE_URL?: string }
  }
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

/*
 * SPA: כל ניווט מוגש מ-index.html. הרשימה השחורה היא הנתיבים שאינם מסכים.
 *
 * ‏`/employee-guide/` הוא עמוד סטטי ולא מסך (ראו public/): בלי השורה הזו כל
 * מי שהתקין את האפליקציה היה מקבל את ה-shell שלה במקום המדריך — והקישור
 * נשלח דווקא לעובדים, שהם מי שהתקין.
 */
registerRoute(
  new NavigationRoute(createHandlerBoundToURL('index.html'), {
    denylist: [/^\/functions\//, /^\/rest\//, /^\/auth\//, /^\/storage\//, /^\/employee-guide\//],
  }),
)

/*
 * קריאות נתונים ממשיכות לעבוד בלי קליטה — עובד מחסן שפותח את האפליקציה
 * בשטח מקבל את הלו"ז והשעון מהעותק האחרון שנטען, לא מסך ריק.
 *
 *   • ‏GET בלבד, ורק ‏/rest/v1/: קריאה. כתיבות (החתמות, שמירות) לעולם אינן
 *     נענות מהמטמון ולא נכנסות אליו.
 *   • ‏NetworkFirst עם timeout קצר: ברשת חיה התשובה תמיד טרייה מהשרת;
 *     המטמון עונה רק כשאין רשת או שהיא איטית מאוד.
 *   • ‏ignoreVary: התשובה נשמרת פר-URL. רענון טוקן לא מפסיל את העותק.
 *   • במכוון אין כאן תור כתיבות (Background Sync) להחתמות שעון:
 *     ‏attendance_clock_in/out חותמים ‎now()‎ בצד השרת, ושידור חוזר מאוחר
 *     היה רושם שעת כניסה שגויה ומזין את השכר. כשל גלוי + "דיווח משמרת
 *     שלא הוחתמה" (אישור מנהל, שעות מפורשות) הוא הנתיב הנכון.
 *
 * העותקים יושבים ב-CacheStorage של המכשיר — אותה רמת אמון כמו הסשן
 * שכבר נשמר בו — ופגים אחרי שבוע.
 */
const SUPABASE_ORIGIN = (() => {
  try {
    return new URL(import.meta.env.VITE_SUPABASE_URL ?? '').origin
  } catch {
    return null
  }
})()

/*
 * המטמון נשמר לפי משתמש. ‏ignoreVary למטה אומר שהכותרת Authorization אינה
 * חלק מהמפתח, ועד 0217 המפתח היה ה-URL לבדו: כשהשרת איחר מעבר ל-4 שניות,
 * עובד שנכנס במכשיר שבו מנהל פתח קודם את לוח השנה קיבל את לוח השנה **של
 * המנהל** — כל האירועים, בלי RLS. עכשיו ה-`sub` של הטוקן נכנס למפתח, ועותק
 * של משתמש אחד לעולם אינו עונה לאחר. (היציאה גם מנקה את המטמון כולו —
 * ‏`clearCachedReads` ב-src/lib/cachedReads.ts.)
 */
function requestUser(request: Request): string {
  const token = request.headers.get('Authorization')?.replace(/^Bearer\s+/i, '')
  const payload = token?.split('.')[1]
  if (!payload) return 'anon'
  try {
    const json = atob(payload.replace(/-/g, '+').replace(/_/g, '/'))
    const sub = (JSON.parse(json) as { sub?: unknown }).sub
    return typeof sub === 'string' && sub ? sub : 'anon'
  } catch {
    return 'anon'
  }
}

// המטמון הישן נשמר לפי URL בלבד (ראו למעלה) — עותקים בו אינם של משתמש ידוע
self.addEventListener('activate', (event: ExtendableEvent) => {
  event.waitUntil(caches.delete('supabase-reads'))
})

registerRoute(
  ({ url, request }) =>
    SUPABASE_ORIGIN != null &&
    url.origin === SUPABASE_ORIGIN &&
    url.pathname.startsWith('/rest/v1/') &&
    request.method === 'GET',
  new NetworkFirst({
    cacheName: 'supabase-reads-v2',
    networkTimeoutSeconds: 4,
    matchOptions: { ignoreVary: true },
    plugins: [
      {
        cacheKeyWillBeUsed: async ({ request }) => {
          const key = new URL(request.url)
          key.searchParams.set('__vl_user', requestUser(request))
          return key.href
        },
      },
      new ExpirationPlugin({ maxEntries: 64, maxAgeSeconds: 7 * 24 * 3600 }),
    ],
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
