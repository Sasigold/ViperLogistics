/**
 * קונפטי על canvas שנמחק בסוף — בלי ספרייה. מכבד prefers-reduced-motion.
 */
const COLORS = ['#10b981', '#3563f0', '#f59e0b', '#ef4444', '#a855f7', '#06b6d4', '#facc15']
const GOLD = ['#facc15', '#f59e0b', '#fde68a', '#eab308', '#fff7ae']

export function reducedMotion(): boolean {
  return typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
}

export function confetti(opts: { x?: number; y?: number; count?: number; gold?: boolean } = {}) {
  if (typeof document === 'undefined' || reducedMotion()) return
  const canvas = document.createElement('canvas')
  const dpr = window.devicePixelRatio || 1
  canvas.width = window.innerWidth * dpr
  canvas.height = window.innerHeight * dpr
  Object.assign(canvas.style, {
    position: 'fixed',
    inset: '0',
    width: '100vw',
    height: '100vh',
    pointerEvents: 'none',
    zIndex: '9999',
  })
  document.body.appendChild(canvas)
  const c = canvas.getContext('2d')
  if (!c) {
    canvas.remove()
    return
  }
  c.scale(dpr, dpr)
  const ox = opts.x ?? window.innerWidth / 2
  const oy = opts.y ?? window.innerHeight / 3
  const palette = opts.gold ? GOLD : COLORS
  const parts = Array.from({ length: opts.count ?? 160 }, () => {
    const a = Math.random() * Math.PI * 2
    const v = 4 + Math.random() * 9
    return {
      x: ox,
      y: oy,
      vx: Math.cos(a) * v,
      vy: Math.sin(a) * v - 6,
      r: Math.random() * Math.PI,
      vr: (Math.random() - 0.5) * 0.4,
      w: 6 + Math.random() * 6,
      h: 3 + Math.random() * 4,
      color: palette[Math.floor(Math.random() * palette.length)],
    }
  })
  const start = performance.now()
  const frame = (t: number) => {
    const age = t - start
    c.clearRect(0, 0, window.innerWidth, window.innerHeight)
    for (const p of parts) {
      p.vy += 0.28
      p.vx *= 0.99
      p.x += p.vx
      p.y += p.vy
      p.r += p.vr
      c.save()
      c.globalAlpha = Math.max(0, 1 - age / 2600)
      c.translate(p.x, p.y)
      c.rotate(p.r)
      c.fillStyle = p.color
      c.fillRect(-p.w / 2, -p.h / 2, p.w, p.h)
      c.restore()
    }
    if (age < 2600) requestAnimationFrame(frame)
    else canvas.remove()
  }
  requestAnimationFrame(frame)
}
