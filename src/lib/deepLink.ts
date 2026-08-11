/**
 * "הגעתי לכאן מהתראה — איפה הפריט?"
 *
 * ‏app.notification_link (0054) בונה כתובת שנושאת מזהה: /board?task=…,
 * /portal?task=…, /my/attendance?entry=… . הפרמטר לבדו מביא למסך הנכון, אבל
 * ברשימה של חמישים שורות הוא לא עונה על השאלה השנייה — איזו מהן. ההוק כאן
 * גולל אל השורה ומבזיק אותה פעם אחת.
 *
 * שני דברים שנשמרים בכוונה:
 *
 *   • **הקריאה היא ב-useEffect ולא ב-useState initializer.** זה ההבדל בין
 *     "עובד כשנוחתים על המסך" לבין "עובד גם כשכבר עומדים עליו" — לחיצה על
 *     התראה שנייה בזמן שהמסך פתוח היא בדיוק המקרה שנשבר אחרת.
 *   • **ההבזק רץ פעם אחת לכל מזהה.** בלי המפתח שנשמר, כל render חוזר היה
 *     מפעיל אותו מחדש והשורה הייתה מהבהבת בלי סוף.
 */
import { useEffect, useRef } from 'react'

/**
 * @param id  המזהה שהגיע מה-URL, או null כשאין
 * @param ready האם הרשימה כבר נטענה — גלילה לפני כן לא תמצא דבר
 */
export function useDeepLinkHighlight(id: string | null | undefined, ready = true) {
  const ref = useRef<HTMLElement | null>(null)
  const done = useRef<string | null>(null)

  useEffect(() => {
    if (!id || !ready) return
    if (done.current === id) return
    const el = ref.current
    if (!el) return
    done.current = id
    el.scrollIntoView({ block: 'center', behavior: 'smooth' })
  }, [id, ready])

  return ref
}

/** המחלקה שמבזיקה. מוחלת רק על השורה שהמזהה מצביע עליה. */
export const HIGHLIGHT_CLASS = 'animate-highlight rounded-lg'
