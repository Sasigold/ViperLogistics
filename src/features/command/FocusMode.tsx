import { useEffect, useState } from 'react'
import { Check, ICON, Pause, Play, RotateCcw, STROKE, X } from '../../components/ui/icons'
import { Button, IconButton, cx } from '../../components/ui'
import type { Mission } from '../../types/domain'
import { countdown } from './warRoom'

const POMODORO = 25 * 60

/**
 * מצב פוקוס: מסך מלא, משימה אחת, טיימר של 25 דקות. שום דבר אחר על המסך.
 */
export function FocusMode({
  mission,
  nowMs,
  onClose,
  onComplete,
  onToggleStep,
}: {
  mission: Mission
  nowMs: number
  onClose: () => void
  onComplete: (el: HTMLElement) => void
  onToggleStep: (stepId: string) => void
}) {
  const [left, setLeft] = useState(POMODORO)
  const [running, setRunning] = useState(true)

  useEffect(() => {
    if (!running) return
    const t = setInterval(() => setLeft((s) => Math.max(0, s - 1)), 1000)
    return () => clearInterval(t)
  }, [running])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  const cd = countdown(mission.due_at, nowMs)
  const mm = String(Math.floor(left / 60)).padStart(2, '0')
  const ss = String(left % 60).padStart(2, '0')
  const r = 120
  const c = 2 * Math.PI * r

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={`מצב פוקוס: ${mission.title}`}
      className="fixed inset-0 z-[60] flex flex-col items-center justify-center gap-6 bg-[#0b1020] p-6 text-white"
    >
      <IconButton label="יציאה ממצב פוקוס" className="absolute end-4 top-4 text-white/70 hover:text-white" onClick={onClose}>
        <X size={ICON.xl} strokeWidth={STROKE} />
      </IconButton>

      <p className={cx('type-overline', cd.overdue ? 'text-red-400' : 'text-white/50')}>{cd.text}</p>
      <h2 className="max-w-2xl text-center text-3xl font-black sm:text-4xl">{mission.title}</h2>

      <div className="relative">
        <svg width={280} height={280} viewBox="0 0 280 280" className="-rotate-90" aria-hidden>
          <circle cx={140} cy={140} r={r} fill="none" stroke="rgb(255 255 255 / 0.08)" strokeWidth={10} />
          <circle
            cx={140}
            cy={140}
            r={r}
            fill="none"
            stroke={left === 0 ? '#10b981' : '#3563f0'}
            strokeWidth={10}
            strokeLinecap="round"
            strokeDasharray={c}
            strokeDashoffset={c * (left / POMODORO)}
            style={{ transition: 'stroke-dashoffset 1s linear' }}
          />
        </svg>
        <p className="absolute inset-0 flex items-center justify-center font-mono text-6xl font-black tabular-nums" aria-live="off">
          {left === 0 ? 'הפסקה!' : `${mm}:${ss}`}
        </p>
      </div>

      <div className="flex gap-2">
        <Button variant="secondary" onClick={() => setRunning((r) => !r)}>
          {running ? <Pause size={ICON.sm} /> : <Play size={ICON.sm} />}
          {running ? 'השהיה' : 'המשך'}
        </Button>
        <Button
          variant="secondary"
          onClick={() => {
            setLeft(POMODORO)
            setRunning(true)
          }}
        >
          <RotateCcw size={ICON.sm} />
          מההתחלה
        </Button>
      </div>

      {mission.steps.length > 0 && (
        <ul className="w-full max-w-md space-y-1.5">
          {mission.steps.map((s) => (
            <li key={s.id}>
              <label className="flex cursor-pointer items-center gap-2 rounded-lg bg-white/5 px-3 py-2">
                <input type="checkbox" checked={s.done} onChange={() => onToggleStep(s.id)} className="size-4 accent-emerald-500" />
                <span className={cx(s.done && 'text-white/40 line-through')}>{s.title}</span>
              </label>
            </li>
          ))}
        </ul>
      )}

      <Button variant="primary" size="lg" className="!bg-emerald-600 hover:!bg-emerald-500" onClick={(e) => onComplete(e.currentTarget)}>
        <Check size={ICON.md} strokeWidth={3} />
        בוצע. הבאה.
      </Button>
    </div>
  )
}
