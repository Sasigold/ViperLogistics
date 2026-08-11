/**
 * גרירת מסך עם העכבר — לתפוס את הלוח ולמשוך אותו לצדדים, כמו במפה.
 *
 * במגע הגלילה האופקית קיימת מאליה; בעכבר היא דרשה גלגלת עם Shift או סרגל
 * גלילה בתחתית המסך, ולכן לוח שרחב מהמסך נראה כאילו נגמר בקצה הימני שלו.
 * כאן לחיצה על כל מקום ריק בלוח והזזה מזיזה אותו איתה — בשני הצירים, כי
 * לוח המשמרות גבוה מהמסך בדיוק כמו שהוא רחב ממנו.
 *
 * הסף שומר על הקליקים: עד ארבעה פיקסלים זו לחיצה רגילה שממשיכה אל התא
 * שמתחתיה, ורק מעבר לו זו גרירה — ואז הקליק שמגיע בסופה נבלע, כדי
 * שגרירה שהסתיימה מעל משימה לא תפתח אותה.
 *
 * ‏`scrollLeft` נקרא ונכתב בדלתאות יחסיות בלבד, ולכן הכיווניות (RTL, שבה
 * הדפדפנים חלוקים על הסימן) לא נכנסת לתמונה כלל.
 */
import { useEffect } from 'react'
import type { RefObject } from 'react'

/** מתחת לזה זו לחיצה, לא גרירה */
const DRAG_MIN = 4
/** גרירה שמתחילה על אלה שייכת להם — שדות טקסט וכל מה שנבחר בעכבר */
const IGNORE = 'input, textarea, select, [contenteditable="true"], [contenteditable=""]'

export function useDragScroll(ref: RefObject<HTMLElement | null>, enabled = true) {
  useEffect(() => {
    const el = ref.current
    if (!el || !enabled) return

    let startX = 0
    let startY = 0
    let lastX = 0
    let lastY = 0
    let active = false
    let dragging = false

    /* הקליק שמסיים גרירה נבלע בשלב ה-capture, לפני שהוא מגיע לתא. מאזין
       חד-פעמי, ושחרורו ב-timeout למקרה שלא הגיע קליק בכלל (גרירה שיצאה
       מהחלון, למשל) — אחרת הוא היה בולע את הקליק האמיתי הבא. */
    const swallowClick = (e: MouseEvent) => {
      e.stopPropagation()
      e.preventDefault()
    }

    const stopDragging = () => {
      dragging = false
      active = false
      el.style.cursor = ''
      document.body.style.userSelect = ''
    }

    const onPointerMove = (e: PointerEvent) => {
      if (!active) return
      if (!dragging) {
        if (Math.abs(e.clientX - startX) < DRAG_MIN && Math.abs(e.clientY - startY) < DRAG_MIN) return
        dragging = true
        el.style.cursor = 'grabbing'
        // בלי זה הגרירה מסמנת טקסט לאורך כל הדרך
        document.body.style.userSelect = 'none'
        window.getSelection()?.removeAllRanges()
      }
      el.scrollLeft -= e.clientX - lastX
      el.scrollTop -= e.clientY - lastY
      lastX = e.clientX
      lastY = e.clientY
    }

    const onPointerUp = () => {
      if (!active) return
      const wasDragging = dragging
      stopDragging()
      window.removeEventListener('pointermove', onPointerMove)
      window.removeEventListener('pointerup', onPointerUp)
      window.removeEventListener('pointercancel', onPointerUp)
      if (!wasDragging) return
      window.addEventListener('click', swallowClick, { capture: true, once: true })
      window.setTimeout(() => window.removeEventListener('click', swallowClick, { capture: true }), 0)
    }

    const onPointerDown = (e: PointerEvent) => {
      // המגע גולל בעצמו, ועט מצייר; זו תוספת לעכבר בלבד
      if (e.pointerType !== 'mouse' || e.button !== 0) return
      if ((e.target as HTMLElement | null)?.closest(IGNORE)) return
      active = true
      dragging = false
      startX = lastX = e.clientX
      startY = lastY = e.clientY
      window.addEventListener('pointermove', onPointerMove)
      window.addEventListener('pointerup', onPointerUp)
      window.addEventListener('pointercancel', onPointerUp)
    }

    el.addEventListener('pointerdown', onPointerDown)
    return () => {
      el.removeEventListener('pointerdown', onPointerDown)
      window.removeEventListener('pointermove', onPointerMove)
      window.removeEventListener('pointerup', onPointerUp)
      window.removeEventListener('pointercancel', onPointerUp)
      window.removeEventListener('click', swallowClick, { capture: true })
      stopDragging()
    }
  }, [ref, enabled])
}
