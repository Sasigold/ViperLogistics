/**
 * מסך הפתיחה עצמו יושב ב-index.html: הוא חייב להיראות לפני שהבאנדל ירד,
 * ולכן הוא HTML ו-CSS בלבד. כאן רק מסלקים אותו.
 *
 * הוא יורד כשהאימות ענה (`boot` הסתיים: יש סשן והרשאות, או שאין סשן), ולא
 * לפני שהפתיחה הסתיימה — אחרת בטעינה חמה הלוגו נחתך באמצע הנחיתה של הנקודה.
 * מי שביקש פחות תנועה לא מחכה לה בכלל.
 *
 * אם JS לא עלה בכלל, ה-CSS מעלים את המסך לבד אחרי 12 שניות (vl-sp-failsafe),
 * כדי שלוגו לא יסתיר שגיאה.
 */
const INTRO_MS = 1300
const EXIT_MS = 450

let dismissed = false

export function dismissSplash(): void {
  if (dismissed) return
  const el = document.getElementById('vl-splash')
  if (!el) return
  dismissed = true

  const calm = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  const elapsed = performance.now() - Number(el.dataset.t0 ?? 0)
  const wait = calm ? 0 : Math.max(0, INTRO_MS - elapsed)

  window.setTimeout(() => {
    el.classList.add('vl-splash--out')
    window.setTimeout(() => el.remove(), EXIT_MS)
  }, wait)
}
