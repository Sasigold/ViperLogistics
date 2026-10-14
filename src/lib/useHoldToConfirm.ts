import { useEffect, useMemo, useRef, useState } from 'react'
import type { KeyboardEvent, MouseEvent, PointerEvent } from 'react'
import { createHoldController } from './holdToConfirm'

/**
 * כפתור שנורה רק אחרי החזקה (ברירת מחדל 800ms) — עכבר, מגע, או Enter/רווח
 * לחוצים. שחרור מוקדם, גלילה (pointercancel) או יציאת הפוקוס מבטלים.
 *
 * מחזיר `holding` לציור אנימציית המילוי, ו-`bind` לפרוש על ה-<button>.
 * אין כאן onClick רגיל: לחיצה קצרה לא עושה דבר. החריג הוא הפעלה מטכנולוגיה
 * מסייעת (קורא מסך שולח click בלי מצביע ובלי מקש — `detail === 0`), שאין לה
 * דרך "להחזיק"; שם הלחיצה עצמה היא ההחלטה המכוונת.
 */
export function useHoldToConfirm({
  onConfirm,
  duration = 800,
  disabled = false,
}: {
  onConfirm: () => void
  duration?: number
  disabled?: boolean
}) {
  const [holding, setHolding] = useState(false)
  const confirmRef = useRef(onConfirm)
  useEffect(() => {
    confirmRef.current = onConfirm
  }, [onConfirm])

  const ctl = useMemo(
    () =>
      createHoldController({
        duration,
        onConfirm: () => confirmRef.current(),
        onChange: setHolding,
      }),
    [duration],
  )
  useEffect(() => () => ctl.dispose(), [ctl])
  useEffect(() => {
    if (disabled) ctl.cancel()
  }, [disabled, ctl])

  const isKey = (e: KeyboardEvent) => e.key === 'Enter' || e.key === ' '

  const bind = {
    onPointerDown: (e: PointerEvent<HTMLElement>) => {
      if (disabled || e.button !== 0) return
      try {
        e.currentTarget.setPointerCapture(e.pointerId)
      } catch {
        /* דפדפן ישן — ההחזקה עובדת גם בלי לכידה */
      }
      ctl.start()
    },
    onPointerUp: () => ctl.cancel(),
    onPointerCancel: () => ctl.cancel(),
    onLostPointerCapture: () => ctl.cancel(),
    onKeyDown: (e: KeyboardEvent<HTMLElement>) => {
      if (!isKey(e)) return
      e.preventDefault()
      if (!disabled && !e.repeat) ctl.start()
    },
    onKeyUp: (e: KeyboardEvent<HTMLElement>) => {
      if (!isKey(e)) return
      e.preventDefault()
      ctl.cancel()
    },
    onBlur: () => ctl.cancel(),
    onClick: (e: MouseEvent<HTMLElement>) => {
      if (!disabled && e.detail === 0) confirmRef.current()
    },
    /* לחיצה ארוכה במובייל פותחת תפריט הקשר — לא כאן */
    onContextMenu: (e: MouseEvent<HTMLElement>) => e.preventDefault(),
  }

  return { holding, duration, bind }
}
