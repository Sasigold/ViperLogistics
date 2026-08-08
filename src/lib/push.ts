/**
 * הצד הדפדפני של Web Push.
 *
 * הקובץ נשאר נטול React ונטול Supabase בכוונה: הוא עוסק רק ב-API של
 * הדפדפן, וכך אפשר לבדוק אותו ביחידה בלי DOM מזויף. הכתיבה למסד יושבת
 * ב-pushQueries.ts.
 */

/** האם הדפדפן בכלל יודע לקבל התראות דחיפה. */
export function pushSupported(): boolean {
  return (
    typeof navigator !== 'undefined' &&
    'serviceWorker' in navigator &&
    typeof window !== 'undefined' &&
    'PushManager' in window &&
    'Notification' in window
  )
}

/** האם אנחנו רצים כאפליקציה מותקנת ולא בתוך לשונית דפדפן. */
export function isStandalone(): boolean {
  if (typeof window === 'undefined') return false
  return (
    window.matchMedia('(display-mode: standalone)').matches ||
    // ספארי ב-iOS לא מיישם display-mode ומחזיק דגל משלו
    (navigator as Navigator & { standalone?: boolean }).standalone === true
  )
}

/**
 * ‏iPadOS מדווח על עצמו כ-MacIntel מאז 13, ולכן בדיקת userAgent לבדה מפספסת
 * אותו. maxTouchPoints הוא מה שמבדיל בין מק אמיתי לאייפד.
 */
export function isIos(): boolean {
  if (typeof navigator === 'undefined') return false
  return (
    /iP(hone|ad|od)/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)
  )
}

/**
 * הסיבה שבגללה אי אפשר להפעיל התראות כרגע, בעברית — או null אם אפשר.
 *
 * המקרה שבגללו הפונקציה קיימת הוא iOS: ‏Web Push עובד שם רק מ-16.4 ורק
 * כשהאתר מותקן במסך הבית. ‏PushManager קיים באובייקט גם בלשונית רגילה,
 * ולכן בלי הבדיקה הזו המשתמש היה מקבל כפתור שנראה תקין ולא עושה דבר.
 */
export function pushBlockedReason(): string | null {
  if (!pushSupported()) {
    return 'הדפדפן שלך אינו תומך בהתראות דחיפה.'
  }
  if (isIos() && !isStandalone()) {
    return 'באייפון ובאייפד ההתראות עובדות רק כשהאפליקציה מותקנת במסך הבית. פתחו את תפריט השיתוף בספארי, בחרו «הוספה למסך הבית», וחזרו למסך הזה מתוך האפליקציה.'
  }
  if (typeof Notification !== 'undefined' && Notification.permission === 'denied') {
    return 'חסמת התראות עבור האתר הזה. יש לאפשר אותן בהגדרות הדפדפן ואז לנסות שוב.'
  }
  return null
}

/**
 * המרת מפתח VAPID מ-base64url למערך בתים.
 *
 * ‏applicationServerKey אינו מקבל מחרוזת base64url בכל הדפדפנים, ולכן
 * ההמרה נעשית כאן ולא נסמכת על הסובלנות של המימוש.
 */
export function urlBase64ToUint8Array(base64: string): Uint8Array<ArrayBuffer> {
  const padding = '='.repeat((4 - (base64.length % 4)) % 4)
  const normalized = (base64 + padding).replace(/-/g, '+').replace(/_/g, '/')
  const raw = atob(normalized)
  // ה-ArrayBuffer נוצר במפורש: תחת TypeScript 6 ‏Uint8Array הוא גנרי, ומערך
  // שנוצר מאורך בלבד מקבל ArrayBufferLike — שאינו מתקבל כ-BufferSource
  // ב-applicationServerKey, כי הוא עלול להיות SharedArrayBuffer.
  const out = new Uint8Array(new ArrayBuffer(raw.length))
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i)
  return out
}

/** תיאור קריא של מכשיר, לרשימת "המכשירים שלי". */
export function describeDevice(ua: string | null): string {
  if (!ua) return 'מכשיר לא מזוהה'
  const browser = /Edg\//.test(ua)
    ? 'edge'
    : /OPR\//.test(ua)
      ? 'אופרה'
      : /Firefox\//.test(ua)
        ? 'פיירפוקס'
        : /Chrome\//.test(ua)
          ? 'כרום'
          : /Safari\//.test(ua)
            ? 'ספארי'
            : 'דפדפן'
  const os = /iPhone/.test(ua)
    ? 'אייפון'
    : /iPad/.test(ua)
      ? 'אייפד'
      : /Android/.test(ua)
        ? 'אנדרואיד'
        : /Windows/.test(ua)
          ? 'Windows'
          : /Mac OS X/.test(ua)
            ? 'מק'
            : /Linux/.test(ua)
              ? 'לינוקס'
              : null
  return os ? `${browser} ב${os === 'Windows' || os === 'לינוקס' ? '-' : ''}${os}` : browser
}

export interface PushKeys {
  endpoint: string
  p256dh: string
  auth: string
}

function encodeKey(sub: PushSubscription, name: 'p256dh' | 'auth'): string {
  const key = sub.getKey(name)
  if (!key) throw new Error('הדפדפן לא סיפק את מפתחות ההצפנה של המנוי')
  let s = ''
  const bytes = new Uint8Array(key)
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i])
  return btoa(s)
}

export function serializeSubscription(sub: PushSubscription): PushKeys {
  return {
    endpoint: sub.endpoint,
    p256dh: encodeKey(sub, 'p256dh'),
    auth: encodeKey(sub, 'auth'),
  }
}

/** המנוי הקיים בדפדפן הזה, אם יש. */
export async function currentSubscription(): Promise<PushSubscription | null> {
  if (!pushSupported()) return null
  const reg = await navigator.serviceWorker.ready
  return reg.pushManager.getSubscription()
}

/**
 * מבקש רשות ונרשם.
 *
 * חייב להיקרא מתוך מחווה של המשתמש — ספארי דורש זאת ל-requestPermission,
 * וקריאה מתוך useEffect הייתה נדחית בשקט.
 */
export async function subscribeToPush(vapidPublicKey: string): Promise<PushKeys> {
  const blocked = pushBlockedReason()
  if (blocked) throw new Error(blocked)
  if (!vapidPublicKey) {
    throw new Error('לא הוגדר מפתח VAPID במערכת. יש לפנות למנהל המערכת.')
  }

  const permission = await Notification.requestPermission()
  if (permission !== 'granted') {
    throw new Error('לא ניתנה הרשאה להתראות.')
  }

  const reg = await navigator.serviceWorker.ready
  const existing = await reg.pushManager.getSubscription()
  // מנוי קיים שנוצר עם מפתח אחר אינו שמיש: שרת האפליקציה לא יוכל לחתום לו.
  if (existing) await existing.unsubscribe()

  const sub = await reg.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(vapidPublicKey),
  })
  return serializeSubscription(sub)
}

/** מבטל את המנוי בדפדפן ומחזיר את ה-endpoint שבוטל, אם היה. */
export async function unsubscribeFromPush(): Promise<string | null> {
  const sub = await currentSubscription()
  if (!sub) return null
  const endpoint = sub.endpoint
  await sub.unsubscribe()
  return endpoint
}
