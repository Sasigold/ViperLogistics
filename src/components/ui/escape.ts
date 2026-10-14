import { useEffect, useRef } from 'react'

/**
 * Escape סוגר רק את השכבה העליונה.
 *
 * כל שכבה (מודאל, מגירה, חלון אישור, פופאובר, רשימה נפתחת, Ctrl+K) נרשמת
 * כאן כשהיא נפתחת. מאזין אחד ב-capture על document מטפל ב-Escape: הוא סוגר
 * את האחרונה שנפתחה בלבד ועוצר את האירוע. קודם לכן כל מגירה רשמה מאזין
 * capture משלה ועצרה את האירוע — כך שהשכבה *החיצונית* (שנרשמה ראשונה) קיבלה
 * אותו: Escape בחלון אישור מעל מגירה סגר את שתיהן, ו-Escape ברשימה נפתחת
 * בתוך טופס זרק את הטופס כולו.
 */
const stack: { close: () => void }[] = []

function onKey(e: KeyboardEvent) {
  if (e.key !== 'Escape' || stack.length === 0) return
  e.stopPropagation()
  e.preventDefault()
  stack[stack.length - 1].close()
}

export function useEscapeLayer(active: boolean, close: () => void) {
  const closeRef = useRef(close)
  useEffect(() => {
    closeRef.current = close
  })
  useEffect(() => {
    if (!active) return
    const entry = { close: () => closeRef.current() }
    if (stack.length === 0) document.addEventListener('keydown', onKey, true)
    stack.push(entry)
    return () => {
      const i = stack.indexOf(entry)
      if (i >= 0) stack.splice(i, 1)
      if (stack.length === 0) document.removeEventListener('keydown', onKey, true)
    }
  }, [active])
}
