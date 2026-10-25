/**
 * עוזר הוואטסאפ (0236) — העזרים הטהורים של המסכים.
 *
 * אותם כללים כמו בפונקציית הקצה (`supabase/functions/_shared/whatsapp.ts`):
 * מזהה וואטסאפ הוא "9725…@c.us" (או "…@lid" אצל מי שוואטסאפ כבר העביר
 * למזהים החדשים), ומספר ישראלי נכתב כמו שאנשים כותבים אותו.
 */

/** "0501234567" לישראלי, "+…" לאחר; מזהה @lid נשאר כמו שהוא. */
export function waPhone(waId: string | null | undefined): string {
  if (!waId) return ''
  const m = /^(\d+)@c\.us$/.exec(waId)
  if (!m) return waId
  if (/^972\d{8,9}$/.test(m[1])) return `0${m[1].slice(3)}`
  return `+${m[1]}`
}

/** קישור שפותח צ'אט פרטי עם הבוט, עם הטקסט מוכן לשליחה; null כשהמספר לא ידוע. */
export function waMeLink(botWid: string | null | undefined, text: string): string | null {
  const m = /^(\d{7,15})@c\.us$/.exec(botWid ?? '')
  if (!m) return null
  return `https://wa.me/${m[1]}?text=${encodeURIComponent(text)}`
}

/** הטקסט שהמשתמש שולח לבוט כדי להתחבר */
export const linkMessage = (code: string) => `קוד ${code}`

/** כמה שניות נשארו לקוד (0 כשפג) */
export function secondsLeft(expiresAt: string, now: number): number {
  return Math.max(0, Math.round((Date.parse(expiresAt) - now) / 1000))
}
