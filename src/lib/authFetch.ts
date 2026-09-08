/**
 * טוקן שפג באמצע העבודה מתרענן ומנסה שוב, במקום להגיע למשתמש כהודעה.
 *
 * ‏supabase-js מרענן את הטוקן לבד לפני שהוא פג, ולכן 401 מ-PostgREST הוא,
 * כמעט תמיד, אחד משני מצבים שאינם באשמת המשתמש:
 *
 *   * **שעון המכשיר סוטה משעון השרת.** הטוקן "עדיין תקף" לפי הדפדפן ופג
 *     לפי השרת, ולכן שום רענון מקדים לא נורה.
 *   * **המכשיר ישן.** טלפון עם האפליקציה ברקע מקפיא את הטיימר, והבקשה
 *     הראשונה אחרי היקיצה יוצאת לפני שהרענון הספיק לנחות.
 *
 * שתי הדרכים נגמרו עד כאן ב-`PGRST301` — "ההתחברות פגה. יש להתחבר מחדש" —
 * הודעה שמבקשת מהעובד להתחבר שוב בזמן שהסשן שלו חי לגמרי. כאן הן נגמרות
 * ברענון אחד ובשידור חוזר של אותה בקשה.
 *
 * הפונקציה מקבלת את התלויות שלה כדי שתהיה ניתנת לבדיקה בלי רשת ובלי שעון
 * אמיתי — היא ההכרעה, לא החיבור לספק.
 */
export interface AuthRetryFetchOptions {
  /** ה-fetch שמבצע בפועל. ברירת המחדל היא זה של הדפדפן. */
  fetchImpl?: typeof fetch
  /** רענון כפוי; מחזיר טוקן גישה טרי, או null כשאין סשן להציל. */
  refresh: () => Promise<string | null>
  now?: () => number
  /**
   * כמה זמן לא לנסות שוב אחרי רענון. ‏401 שאינו קשור לטוקן — פונקציית קצה
   * שסירבה מסיבה משלה — לא יהפוך למטח קריאות אל `/token`, שגם מוגבל בקצב
   * בצד השרת.
   */
  cooldownMs?: number
}

const DEFAULT_COOLDOWN_MS = 30_000

const urlOf = (input: RequestInfo | URL): string =>
  typeof input === 'string' ? input : input instanceof URL ? input.href : input.url

export function createAuthRetryFetch({
  fetchImpl = fetch,
  refresh,
  now = Date.now,
  cooldownMs = DEFAULT_COOLDOWN_MS,
}: AuthRetryFetchOptions): typeof fetch {
  // null ולא 0: "עוד לא רועננו" אינו "רועננו ברגע", וכל מקור זמן שמתחיל
  // מאפס היה מבליע בכך את הניסיון הראשון.
  let lastRefresh: number | null = null

  return async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const res = await fetchImpl(input, init)
    if (res.status !== 401) return res

    // בקשות של Auth עצמו אינן נכנסות לכאן — הן היו רודפות את זנבן.
    if (urlOf(input).includes('/auth/v1/')) return res
    // גוף שאינו מחרוזת (העלאת קובץ, זרם) אינו ניתן לשידור חוזר
    if (init?.body != null && typeof init.body !== 'string') return res
    if (lastRefresh != null && now() - lastRefresh < cooldownMs) return res

    lastRefresh = now()
    const token = await refresh()
    if (!token) return res

    const headers = new Headers(init?.headers)
    headers.set('Authorization', `Bearer ${token}`)
    return fetchImpl(input, { ...init, headers })
  }
}
