import { createClient } from '@supabase/supabase-js'
import { createAuthRetryFetch } from './authFetch'

const url = import.meta.env.VITE_SUPABASE_URL as string
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string

if (!url || !anonKey) {
  console.warn('חסרים משתני סביבה VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY')
}

/**
 * הסשן נשמר, מתרענן לבד, ונקרא גם מה-URL.
 *
 * שלושתם ברירת המחדל של supabase-js, וכתובים כאן במפורש מפני שכל אחד מהם
 * הוא החלטה שאסור שתשתנה בשקט עם שדרוג גרסה:
 *
 *   * ‏`persistSession` — בלעדיו הסשן חי בזיכרון בלבד, וכל רענון דף היה
 *     מסך התחברות. זה בדיוק מה שהמשתמשים דיווחו עליו.
 *   * ‏`autoRefreshToken` — טוקן הגישה חי שעה; בלי הרענון האוטומטי כל
 *     משמרת ארוכה מזה הייתה נגמרת בהתחברות מחדש.
 *   * ‏`detectSessionInUrl` — קישור איפוס הסיסמה מגיע עם הסשן ב-URL, וזה
 *     מה שקולט אותו (ראו ResetPasswordPage).
 */
export const supabase = createClient(url, anonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
  /**
   * ‏401 באמצע העבודה מתורגם לרענון ולשידור חוזר, ולא ל"ההתחברות פגה. יש
   * להתחבר מחדש" (ראו `createAuthRetryFetch`). הרענון נקרא בעצלתיים דרך
   * `supabase` עצמו — הפונקציה רצה הרבה אחרי שהמודול נטען.
   */
  global: { fetch: createAuthRetryFetch({ refresh: refreshAccessToken }) },
})

/**
 * מוצהרת כאן ולא כפונקציית חץ בתוך האובייקט: היא קוראת ל-`supabase` שהיא
 * עצמה חלק מהגדרתו, וטיפוס החזרה המפורש הוא מה שמתיר ל-TypeScript לפרום
 * את המעגל. בזמן ריצה אין מעגל — הפונקציה נקראת הרבה אחרי שהמודול נטען.
 */
async function refreshAccessToken(): Promise<string | null> {
  const { data, error } = await supabase.auth.refreshSession()
  return error ? null : (data.session?.access_token ?? null)
}

export async function invokeFunction<T>(name: string, body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke(name, { body })
  if (error) {
    // supabase-js wraps non-2xx as FunctionsHttpError with the response attached
    const ctx = (error as { context?: Response }).context
    if (ctx) {
      const parsed = await ctx.json().catch(() => null)
      if (parsed?.error) throw new Error(parsed.error)
    }
    throw error
  }
  if ((data as { error?: string })?.error) throw new Error((data as { error: string }).error)
  return data as T
}
