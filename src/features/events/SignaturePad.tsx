/**
 * לוח חתימה — קנבס שהלקוח חותם עליו באצבע או בעכבר (0107).
 *
 * החתימה מצוירת בדיו כהה על רקע לבן, כך שה-PNG המיוצא נקרא זהה בכל ערכת נושא
 * ובהדפסה. הקנבס מוגדל לפי devicePixelRatio כדי שהקו יישאר חד, וממודד מחדש עם
 * הרוחב של המכל — שינוי רוחב מאפס את הלוח, כי חתימה נעשית בשנייה ולא באמצע גרירה.
 */
import { forwardRef, useEffect, useImperativeHandle, useLayoutEffect, useRef, useState } from 'react'
import { cx } from '../../components/ui'

export interface SignaturePadHandle {
  clear: () => void
  toDataURL: () => string
  isEmpty: () => boolean
}

const INK = '#0f172a'
const PAD_HEIGHT = 200

export const SignaturePad = forwardRef<
  SignaturePadHandle,
  { onDirtyChange?: (dirty: boolean) => void; disabled?: boolean; className?: string }
>(function SignaturePad({ onDirtyChange, disabled, className }, ref) {
  const wrapRef = useRef<HTMLDivElement>(null)
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const drawing = useRef(false)
  const dirtyRef = useRef(false)
  const last = useRef<{ x: number; y: number } | null>(null)
  const [width, setWidth] = useState(0)

  // רוחב הקנבס נגזר מהמכל. ResizeObserver כדי שסיבוב מכשיר או פתיחת המודאל
  // ייתפסו, ולא רק המדידה הראשונה.
  useLayoutEffect(() => {
    const el = wrapRef.current
    if (!el) return
    const measure = () => setWidth(el.clientWidth)
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  function setDirty(next: boolean) {
    if (dirtyRef.current === next) return
    dirtyRef.current = next
    onDirtyChange?.(next)
  }

  function paintBackground(ctx: CanvasRenderingContext2D, w: number, h: number) {
    ctx.fillStyle = '#ffffff'
    ctx.fillRect(0, 0, w, h)
  }

  // הכנת הקנבס בכל שינוי רוחב: קנה מידה לפי dpr, רקע לבן, ואיפוס הדיו.
  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas || width === 0) return
    const dpr = window.devicePixelRatio || 1
    canvas.width = Math.round(width * dpr)
    canvas.height = Math.round(PAD_HEIGHT * dpr)
    const ctx = canvas.getContext('2d')
    if (!ctx) return
    ctx.scale(dpr, dpr)
    ctx.lineCap = 'round'
    ctx.lineJoin = 'round'
    ctx.lineWidth = 2.2
    ctx.strokeStyle = INK
    paintBackground(ctx, width, PAD_HEIGHT)
    setDirty(false)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [width])

  function pointFrom(e: React.PointerEvent<HTMLCanvasElement>) {
    const rect = canvasRef.current!.getBoundingClientRect()
    return { x: e.clientX - rect.left, y: e.clientY - rect.top }
  }

  function onDown(e: React.PointerEvent<HTMLCanvasElement>) {
    if (disabled) return
    e.preventDefault()
    canvasRef.current?.setPointerCapture(e.pointerId)
    drawing.current = true
    last.current = pointFrom(e)
    // נקודה בודדת: לחיצה בלי גרירה עדיין משאירה סימן
    const ctx = canvasRef.current?.getContext('2d')
    if (ctx && last.current) {
      ctx.beginPath()
      ctx.arc(last.current.x, last.current.y, 1.1, 0, Math.PI * 2)
      ctx.fillStyle = INK
      ctx.fill()
    }
    setDirty(true)
  }

  function onMove(e: React.PointerEvent<HTMLCanvasElement>) {
    if (!drawing.current || disabled) return
    e.preventDefault()
    const ctx = canvasRef.current?.getContext('2d')
    const p = pointFrom(e)
    if (ctx && last.current) {
      ctx.beginPath()
      ctx.moveTo(last.current.x, last.current.y)
      ctx.lineTo(p.x, p.y)
      ctx.stroke()
    }
    last.current = p
  }

  function onUp(e: React.PointerEvent<HTMLCanvasElement>) {
    if (!drawing.current) return
    drawing.current = false
    last.current = null
    canvasRef.current?.releasePointerCapture(e.pointerId)
  }

  useImperativeHandle(ref, () => ({
    clear() {
      const ctx = canvasRef.current?.getContext('2d')
      if (ctx) paintBackground(ctx, width, PAD_HEIGHT)
      setDirty(false)
    },
    toDataURL() {
      return canvasRef.current?.toDataURL('image/png') ?? ''
    },
    isEmpty() {
      return !dirtyRef.current
    },
  }))

  return (
    <div
      ref={wrapRef}
      className={cx(
        'relative overflow-hidden rounded-xl border border-line bg-white',
        disabled && 'opacity-60',
        className,
      )}
      style={{ height: PAD_HEIGHT }}
    >
      {/* קו בסיס דקורטיבי, כמו על טופס נייר */}
      <div className="pointer-events-none absolute inset-x-6 bottom-9 border-b border-dashed border-line" aria-hidden />
      <canvas
        ref={canvasRef}
        className="absolute inset-0 h-full w-full touch-none"
        style={{ touchAction: 'none' }}
        onPointerDown={onDown}
        onPointerMove={onMove}
        onPointerUp={onUp}
        onPointerLeave={onUp}
        onPointerCancel={onUp}
        aria-label="אזור חתימה"
        role="img"
      />
    </div>
  )
})
