// החיבור למסד של עוזר הוואטסאפ (0236).
//
// אין כאן JWT של משתמש — ההודעה הגיעה מ-Green API — ולכן הפונקציה מתחברת
// ישירות ל-Postgres (`SUPABASE_DB_URL`) ומריצה כל קריאה של כלי בטרנזקציה בשם
// המשתמש: `set local role authenticated` ו-`request.jwt.claims` שלו. זה בדיוק
// מה שהבדיקות עושות (ומה שמסך ה-SQL של Supabase עושה ב"התחזות למשתמש"), ולכן
// RLS, ‏`app.has`, ‏`app.require` והטריגרים פוסקים כמו בדפדפן.
//
// הכול `local` / `set_config(…, true)`: ה-pooler מחזיר את החיבור לאחרים בסוף
// הטרנזקציה, וזהות שנשארת על החיבור הייתה עוברת למי שבא אחריה.

import postgres from 'npm:postgres@3.4.5'

export type Tx = postgres.TransactionSql<Record<string, unknown>>

let pool: postgres.Sql | null = null

function db(): postgres.Sql {
  if (!pool) {
    pool = postgres(Deno.env.get('SUPABASE_DB_URL')!, {
      // מצב transaction של ה-pooler: בלי prepared statements
      prepare: false,
      max: 1,
      idle_timeout: 20,
      connect_timeout: 10,
      onnotice: () => {},
    })
  }
  return pool
}

class Rollback extends Error {}

/** הזהות של המשתמש בתוך הטרנזקציה הנוכחית */
export async function becomeUser(tx: Tx, uid: string): Promise<void> {
  await tx`
    select set_config('request.jwt.claims', ${JSON.stringify({ sub: uid, role: 'authenticated', aud: 'authenticated' })}, true),
           set_config('request.jwt.claim.sub', ${uid}, true),
           set_config('statement_timeout', '15s', true)`
  await tx.unsafe('set local role authenticated')
}

/** חזרה לחיבור השירות בתוך אותה טרנזקציה (לטבלאות של הבוט), וחזרה למשתמש אחר כך */
export async function asServiceWithin<T>(tx: Tx, fn: () => Promise<T>): Promise<T> {
  await tx.unsafe('reset role')
  try {
    return await fn()
  } finally {
    await tx.unsafe('set local role authenticated')
  }
}

/**
 * `read` — טרנזקציית קריאה בלבד; `write` — רגילה; `dryrun` — רצה עד הסוף
 * ומתבטלת (ROLLBACK): מה שהפונקציה החזירה חוזר, ושום דבר לא נשאר במסד —
 * גם לא התראות, שורות ל-pg_net או שידור בזמן אמת, שכולם שורות באותה טרנזקציה.
 */
export async function asUser<T>(uid: string, mode: 'read' | 'write' | 'dryrun', fn: (tx: Tx) => Promise<T>): Promise<T> {
  const run = async (tx: Tx) => {
    await becomeUser(tx, uid)
    return await fn(tx)
  }
  if (mode === 'dryrun') {
    let out: T | undefined
    try {
      await db().begin(async (tx) => {
        out = await run(tx as Tx)
        throw new Rollback()
      })
    } catch (e) {
      if (!(e instanceof Rollback)) throw e
    }
    return out as T
  }
  if (mode === 'read') return (await db().begin('read only', (tx) => run(tx as Tx))) as T
  return (await db().begin((tx) => run(tx as Tx))) as T
}

/** הטבלאות של הבוט עצמו (wa_*) והפונקציות הפנימיות `app.wa_*` */
export async function service<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
  return (await db().begin((tx) => fn(tx as Tx))) as T
}

/** הודעת השגיאה של Postgres כפי שהמשתמש צריך לשמוע אותה */
export function dbError(e: unknown): string {
  const err = e as { message?: string; code?: string }
  const msg = (err?.message ?? '').trim()
  if (err?.code === '42501' && !/[א-ת]/.test(msg)) return 'אין לך הרשאה לפעולה הזו'
  if (err?.code === '23505') return 'זה כבר קיים'
  if (err?.code === '57014') return 'השאילתה לקחה יותר מדי זמן'
  return msg || 'שגיאה במסד'
}
