/**
 * "החזיקו כדי לאשר" — הלוגיקה הטהורה, בלי React.
 *
 * לחיצה אחת אינה מספיקה: הפעולה נורית רק אחרי שהאצבע (או המקש) נשארו
 * לחוצים `duration` מילישניות רצופות. שחרור מוקדם מבטל, ושום דבר לא נשלח.
 * זה מחליף דיאלוג "בטוח?" — ההחזקה היא האישור.
 *
 * הטיימר מוזרק כדי שהבדיקות ירוצו בלי שעון אמיתי.
 */
export interface HoldTimer {
  set(fn: () => void, ms: number): unknown
  clear(handle: unknown): void
}

const realTimer: HoldTimer = {
  set: (fn, ms) => setTimeout(fn, ms),
  clear: (h) => clearTimeout(h as ReturnType<typeof setTimeout>),
}

export interface HoldController {
  /** תחילת החזקה. קריאה נוספת בזמן החזקה — חזרת מקש — אינה מאפסת אותה. */
  start(): void
  /** שחרור לפני הזמן. אחרי שהפעולה נורתה — אין מה לבטל. */
  cancel(): void
  isHolding(): boolean
  /** ניקוי בעת פירוק, בלי לדווח שינוי */
  dispose(): void
}

export function createHoldController(opts: {
  duration: number
  onConfirm: () => void
  onChange?: (holding: boolean) => void
  timer?: HoldTimer
}): HoldController {
  const timer = opts.timer ?? realTimer
  let handle: unknown = null
  let holding = false

  const set = (v: boolean) => {
    if (holding === v) return
    holding = v
    opts.onChange?.(v)
  }

  return {
    start() {
      if (holding) return
      set(true)
      handle = timer.set(() => {
        handle = null
        set(false)
        opts.onConfirm()
      }, opts.duration)
    },
    cancel() {
      if (!holding) return
      if (handle != null) timer.clear(handle)
      handle = null
      set(false)
    },
    isHolding: () => holding,
    dispose() {
      if (handle != null) timer.clear(handle)
      handle = null
      holding = false
    },
  }
}
