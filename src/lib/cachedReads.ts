/**
 * מנקה את כל מה שנשמר בדפדפן מקריאות Supabase — המטמון של ה-service worker
 * (‏`src/sw.ts`, ‏NetworkFirst) לשמותיו הישן והנוכחי. נקרא כשהמשתמש יוצא או
 * מתחלף: העותקים שייכים לו, ומי שנכנס אחריו באותו מכשיר אינו אמור לקבל אותם
 * גם כשהרשת איטית (0217).
 */
export const CACHED_READS = ['supabase-reads', 'supabase-reads-v2'] as const

export async function clearCachedReads(): Promise<void> {
  if (typeof caches === 'undefined') return
  try {
    await Promise.all(CACHED_READS.map((name) => caches.delete(name)))
  } catch {
    // מצב פרטי / אחסון חסום — אין מה לנקות
  }
}
