/**
 * מה שהמשתמש רואה כששאילתה נכשלה.
 *
 * הדפוס שהיה כאן קודם, בכל מסך, היה `toast.error((e as Error).message)` —
 * וההודעה הזו מגיעה מ-Postgres. שם של constraint, טקסט של פוליסת RLS, או
 * "duplicate key value violates unique constraint" באנגלית, בתוך ממשק עברי.
 * זה גם דולף שמות טבלאות ועמודות למי שלא אמור להכיר אותם.
 *
 * המיפוי כאן הוא לפי קוד ולא לפי טקסט: הטקסט משתנה בין גרסאות של Postgres,
 * הקוד לא.
 */

/** מה ש-supabase-js מחזיר בשדה error, בלי להתחייב על הצורה המלאה. */
export interface PostgrestLikeError {
  message?: string
  code?: string
  details?: string | null
  hint?: string | null
}

const BY_CODE: Record<string, string> = {
  // ── Postgres ──────────────────────────────────────────────────────────
  '23505': 'הערך הזה כבר קיים במערכת.',
  '23503': 'לא ניתן לבצע את הפעולה כי הרשומה מקושרת לרשומות אחרות.',
  '23502': 'חסר ערך בשדה חובה.',
  '23514': 'אחד הערכים אינו עומד בכללי המערכת.',
  '22P02': 'אחד הערכים אינו בפורמט הנכון.',
  '42501': 'אין לך הרשאה לבצע את הפעולה הזו.',
  '40001': 'הפעולה התנגשה בפעולה אחרת שנעשתה באותו רגע. נסה שוב.',
  '57014': 'הפעולה ארכה זמן רב מדי והופסקה.',
  // ── PostgREST ─────────────────────────────────────────────────────────
  PGRST116: 'הרשומה לא נמצאה.',
  PGRST301: 'ההתחברות פגה. יש להתחבר מחדש.',
  // ── GoTrue ────────────────────────────────────────────────────────────
  invalid_credentials: 'אימייל או סיסמה שגויים.',
  email_not_confirmed: 'החשבון עדיין לא אומת.',
  over_request_rate_limit: 'יותר מדי ניסיונות. המתן רגע ונסה שוב.',
}

const GENERIC = 'משהו השתבש. נסה שוב, ואם זה חוזר פנה למנהל המערכת.'
const OFFLINE = 'אין חיבור לרשת. בדוק את החיבור ונסה שוב.'

/**
 * הודעה שנכתבה במפורש בגוף RPC (`raise exception 'טקסט'`) היא הודעה למשתמש
 * וצריכה לעבור כמות שהיא — זו הנקודה שבה השרת מסביר *למה* סירב, ובעברית.
 * מה שמגיע מ-Postgres עצמו מזוהה לפי הצורה ומוחלף.
 */
const RAW_POSTGRES = [
  /violates (unique|foreign key|check|not-null) constraint/i,
  /duplicate key value/i,
  /new row violates row-level security/i,
  /permission denied for/i,
  /invalid input syntax for/i,
  /relation ".*" does not exist/i,
  /column ".*" of relation/i,
]

function looksLikeRawPostgres(message: string): boolean {
  return RAW_POSTGRES.some((re) => re.test(message))
}

/** true כשההודעה נכתבה על ידי המערכת עצמה ולא על ידי המנוע. */
function isAuthoredMessage(message: string): boolean {
  if (!message.trim()) return false
  if (looksLikeRawPostgres(message)) return false
  // ההודעות שלנו כתובות בעברית; אנגלית כאן היא כמעט תמיד המנוע
  return /[֐-׿]/.test(message)
}

/**
 * ההודעה שמוצגת למשתמש עבור שגיאה כלשהי — מ-Supabase, מ-fetch, או Error רגיל.
 */
export function errorMessage(error: unknown): string {
  if (error == null) return GENERIC

  if (typeof navigator !== 'undefined' && navigator.onLine === false) return OFFLINE

  const e = error as PostgrestLikeError & { name?: string }

  if (e.code && BY_CODE[e.code]) return BY_CODE[e.code]

  const message = typeof e.message === 'string' ? e.message : String(error)

  // TypeError: Failed to fetch — הדפדפן לא הצליח לצאת החוצה
  if (e.name === 'TypeError' && /fetch/i.test(message)) return OFFLINE

  if (isAuthoredMessage(message)) return message

  return GENERIC
}

/**
 * גרסה עם הקשר, לשימוש ב-onError של מוטציה: "לא הצלחנו לשמור את האירוע"
 * מוסיף למשתמש את מה שהשגיאה לבדה לא אומרת — איזו פעולה נכשלה.
 */
export function actionError(action: string, error: unknown): string {
  const detail = errorMessage(error)
  return detail === GENERIC ? `${action} נכשלה. נסה שוב.` : `${action} נכשלה: ${detail}`
}
