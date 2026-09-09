import { useCallback } from 'react'

/**
 * הקריאה למיקום לעולם אינה נדחית — היא מחזירה סטטוס.
 *
 * לממשק אכפת מההבדל בין שלושת הכשלים: "סירבת לשתף" דורש הסבר על הגדרות
 * הדפדפן, "לא הצלחנו לקבל מיקום" דורש כפתור ניסיון חוזר, ו"הדפדפן לא תומך"
 * הוא סוף הדרך. Promise שנדחה היה מאחד את שלושתם להודעת שגיאה אחת.
 *
 * ההכרעה עצמה נעשית בשרת: הקריאה נשלחת ל-RPC, והוא זה שמחליט אם היא בטווח.
 * הבדיקה כאן היא כדי לא לבזבז נסיעה הלוך-חזור ולתת הודעה טובה יותר.
 */
export type GeoReading =
  | { status: 'ok'; lat: number; lng: number; accuracy: number }
  | { status: 'denied' | 'unsupported' | 'timeout' | 'error' }

export const GEO_MESSAGES: Record<Exclude<GeoReading['status'], 'ok'>, string> = {
  denied: 'שיתוף המיקום נחסם. יש לאשר גישה למיקום בהגדרות הדפדפן ולנסות שוב.',
  unsupported: 'הדפדפן הזה אינו תומך באיתור מיקום.',
  timeout: 'לא הצלחנו לאתר את המיקום שלך. בדוק שה-GPS פעיל ונסה שוב.',
  error: 'לא הצלחנו לאתר את המיקום שלך. נסה שוב.',
}

/**
 * כמה זמן מחכים לקריאה שאיש אינו חוסם עליה. ארבע שניות הן בערך המרחק בין
 * "המכשיר כבר יודע איפה הוא" לבין "הוא מחפש לוויין" — וזה בדיוק הגבול, כי
 * קריאה רכה שווה בדיוק את מה שהיא עולה בהמתנה.
 */
const SOFT_TIMEOUT_MS = 4_000

/**
 * ‏`soft` — קריאה שאינה חוסמת את ההחתמה.
 *
 * ‏0159 קבע שכשאין מול מה לאמת, אין דרישת מיקום: העובד לא נדרש לחכות לנעילת
 * לוויין בשביל ערך שיושלך. ‏0166 מבקש בכל זאת **לדגום** את הנקודה — לא כדי
 * לחסום אלא כדי שיהיה אפשר לראות מאיפה הוחתם — ולכן היא נקראת ברכות: דיוק
 * נמוך, קריאה מהמטמון מתקבלת, ומעל הכול מרוץ מול שעון. מה שלא הגיע בזמן פשוט
 * לא נדגם, וההחתמה נכנסת בלעדיו.
 *
 * המרוץ אינו כפילות של `timeout` שבאפשרויות: בדפדפנים שבהם חלון ההרשאה עדיין
 * פתוח, ספירת הטיים-אאוט של ה-API אינה מתחילה כלל — והמרוץ הוא מה שמונע
 * מהחתמה להיתקע מאחורי חלון שאיש לא ענה לו.
 */
export function useGeolocation() {
  return useCallback(
    ({ soft = false }: { soft?: boolean } = {}) =>
      new Promise<GeoReading>((resolve) => {
        // דורש הקשר מאובטח: בפרודקשן ובלוקלהוסט זה קיים, בשרת פיתוח
        // שנגישים אליו דרך כתובת IP ברשת המקומית — לא.
        if (typeof navigator === 'undefined' || !('geolocation' in navigator)) {
          resolve({ status: 'unsupported' })
          return
        }
        let done = false
        const settle = (r: GeoReading) => {
          if (done) return
          done = true
          resolve(r)
        }
        if (soft) setTimeout(() => settle({ status: 'timeout' }), SOFT_TIMEOUT_MS)
        navigator.geolocation.getCurrentPosition(
          (p) =>
            settle({
              status: 'ok',
              lat: p.coords.latitude,
              lng: p.coords.longitude,
              accuracy: p.coords.accuracy,
            }),
          (err) =>
            settle({
              status:
                err.code === err.PERMISSION_DENIED
                  ? 'denied'
                  : err.code === err.TIMEOUT
                    ? 'timeout'
                    : 'error',
            }),
          soft
            ? { enableHighAccuracy: false, timeout: SOFT_TIMEOUT_MS, maximumAge: 120_000 }
            : { enableHighAccuracy: true, timeout: 10_000, maximumAge: 30_000 },
        )
      }),
    [],
  )
}
