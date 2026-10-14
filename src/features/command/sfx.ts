/**
 * הצלילים של חדר המלחמה — מסונתזים ב-WebAudio, בלי קבצים.
 *
 * ההשתקה היא העדפה של המכשיר (localStorage), ולכן כל קריאה וכתיבה עטופה:
 * בחלון פרטי או באחסון חסום — פשוט יש צליל.
 */
const KEY = 'vl-command-muted'

export function isMuted(): boolean {
  try {
    return localStorage.getItem(KEY) === '1'
  } catch {
    return false
  }
}

export function setMuted(muted: boolean): void {
  try {
    localStorage.setItem(KEY, muted ? '1' : '0')
  } catch {
    /* אין אחסון — ההעדפה לא תישמר */
  }
}

let ctx: AudioContext | null = null
function audio(): AudioContext | null {
  if (isMuted() || typeof window === 'undefined') return null
  const Ctor = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext
  if (!Ctor) return null
  ctx ??= new Ctor()
  if (ctx.state === 'suspended') void ctx.resume()
  return ctx
}

function tone(freq: number, start: number, dur: number, type: OscillatorType = 'sine', gain = 0.15, slideTo?: number) {
  const a = audio()
  if (!a) return
  const t0 = a.currentTime + start
  const osc = a.createOscillator()
  const g = a.createGain()
  osc.type = type
  osc.frequency.setValueAtTime(freq, t0)
  if (slideTo) osc.frequency.linearRampToValueAtTime(slideTo, t0 + dur)
  g.gain.setValueAtTime(0.0001, t0)
  g.gain.exponentialRampToValueAtTime(gain, t0 + 0.02)
  g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur)
  osc.connect(g).connect(a.destination)
  osc.start(t0)
  osc.stop(t0 + dur + 0.05)
}

/** משימה נסגרה */
export function playDing(early = false) {
  tone(880, 0, 0.18, 'triangle', 0.18)
  tone(1320, 0.09, 0.3, 'triangle', 0.16)
  if (early) tone(1760, 0.2, 0.35, 'triangle', 0.12)
}

/** דרגה חדשה */
export function playFanfare() {
  ;[523, 659, 784, 1047].forEach((f, i) => tone(f, i * 0.12, 0.35, 'square', 0.08))
  tone(1047, 0.5, 0.7, 'triangle', 0.14)
}

/** קריסה — סירנה קצרה, פעמיים */
export function playSiren() {
  tone(520, 0, 0.6, 'sawtooth', 0.06, 880)
  tone(880, 0.6, 0.6, 'sawtooth', 0.06, 520)
  tone(520, 1.2, 0.6, 'sawtooth', 0.06, 880)
}

/** נודניק — צליל נמוך ומאוכזב */
export function playSnooze() {
  tone(330, 0, 0.25, 'sine', 0.12, 220)
}
