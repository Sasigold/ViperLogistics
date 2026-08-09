import { lazy } from 'react'
import type { ComponentType } from 'react'

/**
 * ‏lazy שיודע לשרוד פריסה חדשה.
 *
 * כל מסך באפליקציה נטען כנתח נפרד, ולשמות הקבצים יש hash שמשתנה בכל בנייה.
 * ברגע שפריסה חדשה עולה, קובצי הבנייה הקודמת מוחזרים 404 — והאפליקציה
 * שפתוחה בטלפון ממשיכה להריץ בדיוק אותה בנייה קודמת. ה-import הראשון של
 * מסך שעוד לא נטען מבקש קובץ שאינו קיים יותר, ובמקביל ה-Service Worker
 * (‏skipWaiting + clientsClaim + cleanupOutdatedCaches ב-sw.ts) כבר מחק את
 * ה-precache של אותה בנייה — כך שגם המטמון אינו מציל.
 *
 * התוצאה הייתה מסך "משהו נשבר במסך הזה" על המסך הראשון שנפתח אחרי כל פריסה,
 * תקלה שלמשתמש אין שום דרך להבין או לתקן, ושהתדירות שלה היא תדירות הפריסות.
 *
 * הריפוי הוא רענון אחד: מושכים worker עדכני — שכבר עשה precache לבנייה
 * החדשה — וטוענים מחדש, כך שהמסך מגיע במקום השגיאה. הדגל ב-sessionStorage
 * מונע לולאה: כישלון שאינו נובע מפריסה מגיע למסך השגיאה כרגיל.
 */
const RELOAD_FLAG = 'vl-chunk-reload'

/** נפילה של *טעינת* הנתח, להבדיל משגיאה שהמודול עצמו זרק בהרצה */
function isChunkLoadError(e: unknown): boolean {
  const text = e instanceof Error ? `${e.name}: ${e.message}` : String(e)
  return /dynamically imported module|Importing a module script failed|error loading|Failed to fetch|MIME type/i.test(
    text,
  )
}

function readFlag(): boolean {
  try {
    return sessionStorage.getItem(RELOAD_FLAG) === '1'
  } catch {
    /* גלישה פרטית חוסמת אחסון. בלי דגל אין הגנה מלולאה — ולכן נחשב כאילו
       כבר ניסינו, ומוותרים על הרענון לטובת מסך שגיאה יחיד. */
    return true
  }
}

function writeFlag(on: boolean) {
  try {
    if (on) sessionStorage.setItem(RELOAD_FLAG, '1')
    else sessionStorage.removeItem(RELOAD_FLAG)
  } catch {
    /* אחסון חסום אינו סיבה להפיל טעינה שהצליחה */
  }
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function lazyPage<T extends ComponentType<any>>(load: () => Promise<{ default: T }>) {
  return lazy(async () => {
    try {
      const mod = await load()
      /* נטען בהצלחה — החלון הזה על הבנייה הנוכחית, והדגל סיים את תפקידו */
      writeFlag(false)
      return mod
    } catch (e) {
      if (readFlag() || !isChunkLoadError(e)) throw e
      writeFlag(true)

      const reg = await navigator.serviceWorker?.getRegistration()
      /* בלי זה הרענון עלול להיות מוגש מה-precache הישן ולחזור לאותו מצב */
      await reg?.update().catch(() => {})
      window.location.reload()

      /* הטעינה נעצרת כאן בכוונה: החלון עומד להתחלף, והבהוב של מסך שגיאה
         לרגע לפני הרענון גרוע ממסך הטעינה שכבר מוצג */
      return await new Promise<{ default: T }>(() => {})
    }
  })
}
