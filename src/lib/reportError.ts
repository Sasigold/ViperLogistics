/**
 * נקודת היציאה היחידה של שגיאות מהאפליקציה.
 *
 * עד עכשיו כישלון בפרודקשן היה נראה רק למשתמש שנתקל בו — טוסט בטאב אחד,
 * ואף אחד בצוות לא ידע שקרה. מה שחסר הוא לא ספק מסוים אלא המשפך: מקום אחד
 * שכל שגיאה עוברת בו, כדי שחיבור של שירות חיצוני יהיה שורה אחת ולא מסע בין
 * חמישים קריאות onError.
 *
 * המשפך מחובר ל-QueryCache, ל-MutationCache ול-ErrorBoundary ב-main.tsx.
 *
 * חיבור ספק (Sentry, למשל) נעשה פעם אחת ב-main.tsx:
 *
 *   import * as Sentry from '@sentry/react'
 *   Sentry.init({ dsn: import.meta.env.VITE_SENTRY_DSN, tracesSampleRate: 0.05 })
 *   setErrorSink((e, ctx) => Sentry.captureException(e, { extra: ctx }))
 *
 * הוא לא נכלל כאן כי אין בריפו DSN, ותלות שאי אפשר לאמת שהיא עובדת גרועה
 * מנקודת חיבור מוצהרת.
 */

export interface ErrorContext {
  kind: 'query' | 'mutation' | 'render' | 'manual'
  key?: string
  componentStack?: string | null
  [k: string]: unknown
}

type Sink = (error: unknown, context: ErrorContext) => void

let sink: Sink | null = null

/** מחבר ספק דיווח חיצוני. נקרא פעם אחת בעליית האפליקציה. */
export function setErrorSink(next: Sink | null) {
  sink = next
}

/**
 * לולאת render שנכשלת יכולה לירות אלפי פעמים בשנייה. חלון קצר עם מפתח
 * שמורכב מסוג השגיאה ומההודעה מונע גם הצפה של הספק וגם של הקונסול.
 */
const RECENT_MS = 10_000
const recent = new Map<string, number>()

function shouldReport(key: string): boolean {
  const now = Date.now()
  for (const [k, at] of recent) if (now - at > RECENT_MS) recent.delete(k)
  if (recent.has(key)) return false
  recent.set(key, now)
  return true
}

export function reportError(error: unknown, context: ErrorContext) {
  const message = error instanceof Error ? error.message : String(error)
  if (!shouldReport(`${context.kind}:${context.key ?? ''}:${message}`)) return

  if (import.meta.env.DEV) {
    console.error(`[${context.kind}]`, context.key ?? '', error)
  }

  try {
    sink?.(error, context)
  } catch {
    // דיווח שנכשל לא אמור להפיל את מה שניסה לדווח
  }
}
