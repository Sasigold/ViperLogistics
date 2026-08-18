import { useEffect, useState } from 'react'

/**
 * הערך, אחרי שהפסיקו להקליד.
 *
 * מסך שמכניס את תיבת החיפוש ישירות ל-queryKey יורה בקשה על כל הקשה. באירועים
 * זה עד 200 שורות עם join-ים פר-תו; בלוח העבודה עד 2000. וגרוע מהעומס: מפתח
 * חדש הוא שאילתה חדשה, ולכן `isLoading` חוזר ל-true והטבלה מתקפלת לשלד באמצע
 * ההקלדה — המשתמש רואה את התוצאות שלו נעלמות בזמן שהוא מנסח את השאלה.
 *
 * הדפוס הזה כבר קיים בקוד בארבע גרסאות (useReportRuns, CommandPalette,
 * Autocomplete, וסינון בזיכרון בלוח השנה). זו אותה החלטה, במקום אחד.
 */
export function useDebounced<T>(value: T, ms = 300): T {
  const [settled, setSettled] = useState(value)
  useEffect(() => {
    const t = setTimeout(() => setSettled(value), ms)
    return () => clearTimeout(t)
  }, [value, ms])
  return settled
}
