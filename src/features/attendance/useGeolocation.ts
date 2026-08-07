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

export function useGeolocation() {
  return useCallback(
    () =>
      new Promise<GeoReading>((resolve) => {
        // דורש הקשר מאובטח: בפרודקשן ובלוקלהוסט זה קיים, בשרת פיתוח
        // שנגישים אליו דרך כתובת IP ברשת המקומית — לא.
        if (typeof navigator === 'undefined' || !('geolocation' in navigator)) {
          resolve({ status: 'unsupported' })
          return
        }
        navigator.geolocation.getCurrentPosition(
          (p) =>
            resolve({
              status: 'ok',
              lat: p.coords.latitude,
              lng: p.coords.longitude,
              accuracy: p.coords.accuracy,
            }),
          (err) =>
            resolve({
              status:
                err.code === err.PERMISSION_DENIED
                  ? 'denied'
                  : err.code === err.TIMEOUT
                    ? 'timeout'
                    : 'error',
            }),
          { enableHighAccuracy: true, timeout: 10_000, maximumAge: 30_000 },
        )
      }),
    [],
  )
}
