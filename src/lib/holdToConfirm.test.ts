import { describe, expect, it } from 'vitest'
import { createHoldController, type HoldTimer } from './holdToConfirm'

/** טיימר ידני: `fire()` מריץ את מה שתוזמן, אם לא בוטל */
function fakeTimer() {
  let pending: { fn: () => void; ms: number; id: number } | null = null
  let next = 1
  const timer: HoldTimer = {
    set(fn, ms) {
      pending = { fn, ms, id: next++ }
      return pending.id
    },
    clear(h) {
      if (pending?.id === h) pending = null
    },
  }
  return {
    timer,
    pendingMs: () => pending?.ms ?? null,
    fire() {
      const p = pending
      pending = null
      p?.fn()
    },
  }
}

describe('createHoldController', () => {
  it('confirms only after the full hold', () => {
    const t = fakeTimer()
    const changes: boolean[] = []
    let confirmed = 0
    const c = createHoldController({
      duration: 800,
      timer: t.timer,
      onConfirm: () => confirmed++,
      onChange: (h) => changes.push(h),
    })
    c.start()
    expect(c.isHolding()).toBe(true)
    expect(t.pendingMs()).toBe(800)
    expect(confirmed).toBe(0)
    t.fire()
    expect(confirmed).toBe(1)
    expect(c.isHolding()).toBe(false)
    expect(changes).toEqual([true, false])
  })

  it('an early release cancels and never confirms', () => {
    const t = fakeTimer()
    let confirmed = 0
    const c = createHoldController({ duration: 800, timer: t.timer, onConfirm: () => confirmed++ })
    c.start()
    c.cancel()
    expect(c.isHolding()).toBe(false)
    expect(t.pendingMs()).toBeNull()
    t.fire()
    expect(confirmed).toBe(0)
  })

  it('a repeated start (key repeat) does not restart the hold', () => {
    const t = fakeTimer()
    const changes: boolean[] = []
    const c = createHoldController({
      duration: 800,
      timer: t.timer,
      onConfirm: () => {},
      onChange: (h) => changes.push(h),
    })
    c.start()
    c.start()
    expect(changes).toEqual([true])
  })

  it('cancel after confirm is a no-op', () => {
    const t = fakeTimer()
    const changes: boolean[] = []
    let confirmed = 0
    const c = createHoldController({
      duration: 800,
      timer: t.timer,
      onConfirm: () => confirmed++,
      onChange: (h) => changes.push(h),
    })
    c.start()
    t.fire()
    c.cancel()
    expect(confirmed).toBe(1)
    expect(changes).toEqual([true, false])
  })

  it('dispose clears the pending timer silently', () => {
    const t = fakeTimer()
    const changes: boolean[] = []
    let confirmed = 0
    const c = createHoldController({
      duration: 800,
      timer: t.timer,
      onConfirm: () => confirmed++,
      onChange: (h) => changes.push(h),
    })
    c.start()
    c.dispose()
    t.fire()
    expect(confirmed).toBe(0)
    expect(changes).toEqual([true])
  })
})
