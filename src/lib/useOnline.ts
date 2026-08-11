import { useSyncExternalStore } from 'react'

/**
 * האם הדפדפן מחובר לרשת, כערך ריאקטיבי.
 *
 * useSyncExternalStore ולא useState+useEffect: הערך חיצוני לריאקט (הדפדפן
 * מחזיק אותו), והדפוס הזה קורא אותו נכון גם ברינדור הראשון וגם בזמן
 * hydration, בלי חלון שבו המסך מציג "מחובר" על מכשיר מנותק.
 *
 * navigator.onLine הוא אות אופטימי — true אינו מבטיח שהשרת נגיש — אבל
 * false הוא ודאי, וזה כל מה שהבאנר צריך.
 */
function subscribe(onChange: () => void) {
  window.addEventListener('online', onChange)
  window.addEventListener('offline', onChange)
  return () => {
    window.removeEventListener('online', onChange)
    window.removeEventListener('offline', onChange)
  }
}

export function useOnline(): boolean {
  return useSyncExternalStore(subscribe, () => navigator.onLine)
}
