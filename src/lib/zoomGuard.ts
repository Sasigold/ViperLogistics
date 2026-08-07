/**
 * חסימת זום ברמת הדף — כדי שהאפליקציה תתנהג כמו אפליקציה ולא כמו אתר.
 *
 * רוב העבודה נעשית ב-CSS (`html { touch-action: pan-x pan-y }`) וב-viewport,
 * אבל Safari של iOS מתעלם מ-`user-scalable=no` מאז iOS 10, ואירועי ה-gesture
 * הקנייניים של WebKit הם הדבר היחיד שבאמת עוצר שם צביטה. הם לא קיימים
 * בדפדפנים אחרים, ולכן זה מאזין ללא השפעה בכרום.
 *
 * המפות הן היוצא מן הכלל: Leaflet מנהל את הזום שלו בעצמו, וצביטה בתוך מפה
 * היא בדיוק מה שמשתמש מצפה לו.
 */

/** אלמנטים שמפעילים זום משלהם ולכן המחווה בתוכם נשארת שלהם. */
const GESTURE_OWNERS = '.leaflet-container'

const blockGesture = (e: Event) => {
  const target = e.target
  if (target instanceof Element && target.closest(GESTURE_OWNERS)) return
  e.preventDefault()
}

const GESTURE_EVENTS = ['gesturestart', 'gesturechange', 'gestureend'] as const

let installed = false

/**
 * מתקין את החסימה פעם אחת בלבד ומחזיר פונקציית ניקוי.
 * קריאה חוזרת (StrictMode, HMR) לא תרשום מאזינים כפולים.
 */
export function installZoomGuard(): () => void {
  if (installed) return () => {}
  installed = true

  for (const type of GESTURE_EVENTS) {
    document.addEventListener(type, blockGesture, { passive: false })
  }

  return () => {
    for (const type of GESTURE_EVENTS) {
      document.removeEventListener(type, blockGesture)
    }
    installed = false
  }
}
