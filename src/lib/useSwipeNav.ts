/**
 * גרירה אופקית שמחליפה תקופה — חודש, שבוע, מה שהלוח מציג.
 *
 * הלוח נגרר עם האצבע לאורך כל הגרירה, וזה כל העניין: בלי המשוב הזה גרירה
 * היא הימור שמתגלה רק בסופו. עברה את הסף — הלוח ממשיך החוצה והתקופה
 * מתחלפת מאחוריו; לא עברה — הוא חוזר למקומו.
 *
 * הציר ננעל אחרי עשרה פיקסלים: תנועה שהוכרזה אנכית נשארת גלילה של העמוד,
 * ורק אחרי שהוכרזה אופקית המצביע נחטף. מכאן שנגיעה נשארת נגיעה, וגרירה
 * שמתחילה על אירוע (ignore) שייכת לאירוע — למשל גרירתו ליום אחר.
 */
import { useCallback, useRef, useState } from 'react'
import type { CSSProperties, PointerEvent as ReactPointerEvent } from 'react'

/** מתחת לזה זו נגיעה, לא גרירה */
const SWIPE_MIN = 56
/** משך ההחלקה החוצה ובחזרה */
const SLIDE_MS = 200

export interface SwipeNavOptions {
  onNext: () => void
  onPrev: () => void
  /** כשהוא כבוי הגרירה לא מתחילה בכלל — למשל כשיש סרגל ניווט משלו */
  enabled?: boolean
  /** סלקטור של אלמנטים שגרירה שמתחילה עליהם שייכת להם */
  ignore?: string
  /** 'touch' מגביל לאצבע; 'any' מאפשר גם גרירה בעכבר */
  pointers?: 'touch' | 'any'
}

export function useSwipeNav({ onNext, onPrev, enabled = true, ignore, pointers = 'any' }: SwipeNavOptions) {
  const surfaceRef = useRef<HTMLDivElement>(null)
  const [dx, setDx] = useState(0)
  const [sliding, setSliding] = useState(false)
  const drag = useRef<{ id: number; x: number; y: number; axis: 'unknown' | 'x' | 'y' } | null>(null)

  const settle = useCallback(
    (moved: number) => {
      const width = surfaceRef.current?.clientWidth ?? 0
      setSliding(true)
      if (Math.abs(moved) < SWIPE_MIN) {
        setDx(0)
        window.setTimeout(() => setSliding(false), SLIDE_MS)
        return
      }
      const dir = moved > 0 ? 1 : -1
      setDx(dir * (width || Math.abs(moved)))
      window.setTimeout(() => {
        if (dir > 0) onNext()
        else onPrev()
        // התקופה מתחלפת כשהלוח כבר מחוץ למסך, והחזרה למקום היא מיידית
        setSliding(false)
        setDx(0)
      }, SLIDE_MS)
    },
    [onNext, onPrev],
  )

  const onPointerDown = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (!enabled || sliding || drag.current) return
    if (pointers === 'touch' && e.pointerType === 'mouse') return
    if (e.pointerType === 'mouse' && e.button !== 0) return
    if (ignore && (e.target as HTMLElement | null)?.closest(ignore)) return
    drag.current = { id: e.pointerId, x: e.clientX, y: e.clientY, axis: 'unknown' }
  }

  const onPointerMove = (e: ReactPointerEvent<HTMLDivElement>) => {
    const d = drag.current
    if (!d || d.id !== e.pointerId) return
    const moved = e.clientX - d.x
    const vertical = e.clientY - d.y
    if (d.axis === 'unknown') {
      if (Math.abs(moved) < 10 && Math.abs(vertical) < 10) return
      d.axis = Math.abs(moved) > Math.abs(vertical) ? 'x' : 'y'
      if (d.axis === 'x') e.currentTarget.setPointerCapture(e.pointerId)
    }
    if (d.axis !== 'x') return
    setDx(moved)
  }

  const end = (e: ReactPointerEvent<HTMLDivElement>) => {
    const d = drag.current
    if (!d || d.id !== e.pointerId) return
    drag.current = null
    if (e.currentTarget.hasPointerCapture?.(e.pointerId)) e.currentTarget.releasePointerCapture(e.pointerId)
    if (d.axis === 'x') settle(e.clientX - d.x)
  }

  /** נכון כל עוד הלוח לא במקומו — מי שצריך לחתוך את מה שיוצא מהמסגרת */
  const active = dx !== 0 || sliding

  const trackStyle: CSSProperties = {
    transform: active ? `translate3d(${dx}px, 0, 0)` : undefined,
    transition: sliding ? `transform ${SLIDE_MS}ms ease-out` : 'none',
  }

  return {
    surfaceRef,
    trackStyle,
    active,
    swipeHandlers: {
      onPointerDown,
      onPointerMove,
      onPointerUp: end,
      onPointerCancel: end,
    },
  }
}
