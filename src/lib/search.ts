import { useEffect, useState } from 'react'

/**
 * תנאי `or` של PostgREST לחיפוש חופשי על כמה עמודות.
 *
 * הטקסט של המשתמש נכנס לתוך תחביר הסינון של PostgREST, שבו פסיק מפריד בין
 * תנאים וסוגריים פותחים קבוצה — "הרצל, תל אביב" או "(" שברו את הבקשה והציגו
 * מסך שגיאה. כאן הערך נעטף במירכאות כפולות (שם פסיק וסוגריים הם טקסט רגיל),
 * ומירכאות ולוכסן הפוך — התווים היחידים שעוד משמעותיים בתוכן — יורדים.
 * מחזיר null כשאין מה לחפש.
 */
export function ilikeAny(columns: readonly string[], q: string): string | null {
  const term = q.replace(/["\\]/g, ' ').trim()
  if (!term) return null
  return columns.map((c) => `${c}.ilike."%${term}%"`).join(',')
}

/** ערך שמתעדכן רק אחרי שההקלדה נרגעה — שאילתה אחת ל"אולם", ולא ארבע. */
export function useDebouncedValue<T>(value: T, ms = 250): T {
  const [v, setV] = useState(value)
  useEffect(() => {
    const t = setTimeout(() => setV(value), ms)
    return () => clearTimeout(t)
  }, [value, ms])
  return v
}
