import { MutationCache, QueryCache, QueryClient } from '@tanstack/react-query'
import { reportError } from './reportError'

/**
 * לקוח השאילתות, במודול משלו.
 *
 * הוא נבנה קודם ב-main.tsx, וזה עבד — עד שהתברר שיש עוד צד אחד שצריך אותו:
 * היציאה מהחשבון. מטמון שאינו ניתן לניקוי ממקום אחר הוא מטמון שאינו מתנקה.
 *
 * כל שגיאה עוברת דרך נקודה אחת בדרך החוצה. קודם לכן כישלון בפרודקשן היה
 * נראה רק למשתמש שנתקל בו, בטוסט, ולא השאיר שום עקבה. ה-cache-ים כאן הם
 * המקום היחיד שרואה *כל* שאילתה וכל מוטציה, ולכן הם המקום הנכון לחבר אליו
 * דיווח חיצוני — ולא כל onError בנפרד.
 */
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 30_000, retry: 1, refetchOnWindowFocus: false },
  },
  queryCache: new QueryCache({
    onError: (error, query) => reportError(error, { kind: 'query', key: query.queryHash }),
  }),
  mutationCache: new MutationCache({
    onError: (error, _vars, _ctx, mutation) =>
      reportError(error, { kind: 'mutation', key: mutation.options.mutationKey?.join('/') }),
  }),
})

/** שם המטמון ב-sw.ts. שינוי שם שם מחייב שינוי כאן. */
const SUPABASE_READ_CACHE = 'supabase-reads'

/**
 * כל מה שנשמר על המכשיר עבור המשתמש שיוצא.
 *
 * ‏`supabase.auth.signOut()` מוחק את הסשן ולא נוגע בשני מטמונים שנשארים
 * מלאים בנתונים שלו: המטמון של react-query בזיכרון, ומטמון ה-GET של
 * ה-Service Worker ב-CacheStorage, שמחזיק תשובות REST שבוע.
 *
 * ההערה ב-sw.ts מנמקת את המטמון בכך שהוא "אותה רמת אמון כמו הסשן שכבר נשמר
 * במכשיר", וזה נכון למכשיר אישי. זה אינו נכון לתרחיש שהמערכת הזו בנויה
 * סביבו: שעון נוכחות משותף במחסן, שני עובדים מתחלפים עליו — מצב ש-pushQueries
 * מתכנן עבורו במפורש. שם הסשן נמחק והנתונים לא, והעובד הבא נכנס לחשבון שלו
 * ורואה את הרשימות של מי שהיה לפניו עד שכל שאילתה מתרעננת.
 *
 * שני הניקויים בטוחים לכישלון: דפדפן בלי CacheStorage, או גלישה פרטית
 * שחוסמת אותו, אינם סיבה להיכשל ביציאה מהחשבון.
 */
export async function clearCachedUserData(): Promise<void> {
  queryClient.clear()
  /* ‏typeof ולא optional chaining: גלובל שלא הוכרז זורק ReferenceError ואינו
     undefined, וזה המצב ב-Node — שם רצות בדיקות היחידה — ובכל הקשר בלי
     CacheStorage. */
  if (typeof caches === 'undefined') return
  try {
    await caches.delete(SUPABASE_READ_CACHE)
  } catch {
    /* חסום בגלישה פרטית, למשל. הסשן כבר נמחק בכל מקרה. */
  }
}
