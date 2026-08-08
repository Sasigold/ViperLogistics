/**
 * The suite runs in `node`, without a DOM, on purpose — what it covers is pure
 * logic and jsdom would only make it slower.
 *
 * Two modules the app loads at import time reach for browser globals anyway:
 * the auth store reads the saved theme out of `localStorage` while zustand is
 * building it. Any test that imports a feature module pulls that in, long
 * before it gets to the function under test.
 *
 * So rather than give up the node environment, or bend the app to a shape the
 * browser never needs, the few globals that get touched during import live
 * here — in memory, per run.
 */
class MemoryStorage implements Storage {
  private map = new Map<string, string>()

  get length() {
    return this.map.size
  }

  clear() {
    this.map.clear()
  }

  getItem(key: string) {
    return this.map.get(key) ?? null
  }

  key(index: number) {
    return [...this.map.keys()][index] ?? null
  }

  removeItem(key: string) {
    this.map.delete(key)
  }

  setItem(key: string, value: string) {
    this.map.set(key, String(value))
  }
}

if (typeof globalThis.localStorage === 'undefined') {
  Object.defineProperty(globalThis, 'localStorage', { value: new MemoryStorage(), writable: true })
}
