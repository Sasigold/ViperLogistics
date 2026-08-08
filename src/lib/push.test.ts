import { afterEach, describe, expect, it, vi } from 'vitest'
import { describeDevice, isIos, isStandalone, pushBlockedReason, urlBase64ToUint8Array } from './push'

/**
 * ‏vitest רץ כאן ב-node ללא DOM, ולכן globalThis מקבל את מה שכל בדיקה
 * צריכה. זו גם הסיבה ש-push.ts נשאר נטול React ונטול Supabase.
 */
function stubBrowser(opts: {
  ua?: string
  platform?: string
  maxTouchPoints?: number
  standalone?: boolean
  displayMode?: boolean
  permission?: NotificationPermission
  push?: boolean
}) {
  vi.stubGlobal('navigator', {
    userAgent: opts.ua ?? 'Mozilla/5.0 (Windows NT 10.0) Chrome/120',
    platform: opts.platform ?? 'Win32',
    maxTouchPoints: opts.maxTouchPoints ?? 0,
    standalone: opts.standalone,
    serviceWorker: {},
  })
  // המפתח מושמט לגמרי ולא מקבל undefined: pushSupported בודק `in`, ומפתח
  // קיים עם ערך undefined היה נחשב נתמך.
  vi.stubGlobal('window', {
    ...(opts.push === false ? {} : { PushManager: function PushManager() {} }),
    Notification: function Notification() {},
    matchMedia: () => ({ matches: !!opts.displayMode }),
  })
  vi.stubGlobal('Notification', { permission: opts.permission ?? 'default' })
}

afterEach(() => vi.unstubAllGlobals())

describe('urlBase64ToUint8Array', () => {
  it('decodes a base64url VAPID key to 65 bytes', () => {
    // מפתח P-256 לא דחוס: 0x04 ואחריו שני קואורדינטות של 32 בתים
    const bytes = new Uint8Array(65)
    bytes[0] = 4
    for (let i = 1; i < 65; i++) bytes[i] = i
    const b64url = btoa(String.fromCharCode(...bytes))
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '')

    const out = urlBase64ToUint8Array(b64url)
    expect(out).toHaveLength(65)
    expect([...out]).toEqual([...bytes])
  })

  it('restores stripped padding', () => {
    // 'aGk' הוא 'hi' בלי ה-= החותם; בלי ההשלמה atob היה זורק
    expect([...urlBase64ToUint8Array('aGk')]).toEqual([104, 105])
  })

  it('translates the url-safe alphabet back', () => {
    // 0xfb 0xff מקודד ל-'+/8=' בבסיס הרגיל ול-'-_8' בגרסה הבטוחה ל-URL
    expect([...urlBase64ToUint8Array('-_8')]).toEqual([251, 255])
  })

  it('produces a buffer usable as applicationServerKey', () => {
    // ‏BufferSource פוסל SharedArrayBuffer, ולכן ה-buffer חייב להיות ArrayBuffer
    expect(urlBase64ToUint8Array('aGk').buffer).toBeInstanceOf(ArrayBuffer)
  })
})

describe('pushBlockedReason', () => {
  it('allows a desktop browser that has not been asked yet', () => {
    stubBrowser({})
    expect(pushBlockedReason()).toBeNull()
  })

  it('explains the home-screen requirement on an iPhone in Safari', () => {
    stubBrowser({ ua: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0) Safari/605' })
    expect(pushBlockedReason()).toContain('הוספה למסך הבית')
  })

  it('lets the same iPhone through once installed', () => {
    stubBrowser({
      ua: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0) Safari/605',
      standalone: true,
    })
    expect(pushBlockedReason()).toBeNull()
  })

  it('detects iPadOS, which reports itself as a Mac', () => {
    stubBrowser({ ua: 'Mozilla/5.0 (Macintosh; Intel Mac OS X) Safari/605', platform: 'MacIntel', maxTouchPoints: 5 })
    expect(isIos()).toBe(true)
    expect(pushBlockedReason()).toContain('הוספה למסך הבית')
  })

  it('does not mistake a real Mac for an iPad', () => {
    stubBrowser({ ua: 'Mozilla/5.0 (Macintosh; Intel Mac OS X) Safari/605', platform: 'MacIntel' })
    expect(isIos()).toBe(false)
    expect(pushBlockedReason()).toBeNull()
  })

  it('says so when the user has blocked notifications', () => {
    stubBrowser({ permission: 'denied' })
    expect(pushBlockedReason()).toContain('הגדרות הדפדפן')
  })

  it('says so when the browser has no PushManager at all', () => {
    stubBrowser({ push: false })
    expect(pushBlockedReason()).toContain('אינו תומך')
  })

  it('reads display-mode for installed non-iOS apps', () => {
    stubBrowser({ displayMode: true })
    expect(isStandalone()).toBe(true)
  })
})

describe('describeDevice', () => {
  it.each([
    ['Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537 Chrome/120 Safari/537', 'כרום ב-Windows'],
    ['Mozilla/5.0 (iPhone; CPU iPhone OS 17_0) AppleWebKit/605 Version/17 Safari/605', 'ספארי באייפון'],
    ['Mozilla/5.0 (Linux; Android 14) AppleWebKit/537 Chrome/120 Mobile Safari/537', 'כרום באנדרואיד'],
    ['Mozilla/5.0 (Macintosh; Intel Mac OS X) Gecko/20100101 Firefox/121', 'פיירפוקס במק'],
  ])('%s', (ua, expected) => {
    expect(describeDevice(ua)).toBe(expected)
  })

  it('falls back when the agent is unknown', () => {
    expect(describeDevice(null)).toBe('מכשיר לא מזוהה')
  })

  it('picks Edge over Chrome — its agent contains both', () => {
    expect(describeDevice('Mozilla/5.0 (Windows NT 10.0) Chrome/120 Safari/537 Edg/120')).toBe(
      'edge ב-Windows',
    )
  })
})
