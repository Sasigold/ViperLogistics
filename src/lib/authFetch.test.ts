import { describe, expect, it, vi } from 'vitest'
import { createAuthRetryFetch } from './authFetch'

const REST = 'https://x.supabase.co/rest/v1/tasks'
const TOKEN_URL = 'https://x.supabase.co/auth/v1/token?grant_type=refresh_token'

/** תשובות לפי הסדר, וסופרת כמה פעמים נקראה */
function stubFetch(...statuses: number[]) {
  const calls: { input: RequestInfo | URL; init?: RequestInit }[] = []
  const impl = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    calls.push({ input, init })
    return new Response(null, { status: statuses[Math.min(calls.length - 1, statuses.length - 1)] })
  })
  return { impl: impl as unknown as typeof fetch, calls }
}

const authHeader = (init?: RequestInit) => new Headers(init?.headers).get('Authorization')

describe('createAuthRetryFetch', () => {
  it('תשובה תקינה עוברת כמות שהיא, בלי לגעת ברענון', async () => {
    const { impl, calls } = stubFetch(200)
    const refresh = vi.fn(async () => 'new-token')
    const res = await createAuthRetryFetch({ fetchImpl: impl, refresh })(REST)

    expect(res.status).toBe(200)
    expect(calls).toHaveLength(1)
    expect(refresh).not.toHaveBeenCalled()
  })

  it('‏401 מרענן ומשדר את אותה בקשה שוב, עם הטוקן החדש', async () => {
    const { impl, calls } = stubFetch(401, 200)
    const refresh = vi.fn(async () => 'new-token')
    const res = await createAuthRetryFetch({ fetchImpl: impl, refresh })(REST, {
      method: 'POST',
      body: '{"p":1}',
      headers: { Authorization: 'Bearer stale', apikey: 'anon' },
    })

    expect(res.status).toBe(200)
    expect(calls).toHaveLength(2)
    expect(authHeader(calls[0].init)).toBe('Bearer stale')
    expect(authHeader(calls[1].init)).toBe('Bearer new-token')
    // שאר הבקשה נשמר: אותה שיטה, אותו גוף, ושאר הכותרות
    expect(calls[1].init?.method).toBe('POST')
    expect(calls[1].init?.body).toBe('{"p":1}')
    expect(new Headers(calls[1].init?.headers).get('apikey')).toBe('anon')
  })

  it('רענון שלא הצליח מחזיר את התשובה המקורית ואינו משדר שוב', async () => {
    const { impl, calls } = stubFetch(401, 200)
    const res = await createAuthRetryFetch({ fetchImpl: impl, refresh: async () => null })(REST)

    expect(res.status).toBe(401)
    expect(calls).toHaveLength(1)
  })

  it('‏401 מ-Auth עצמו אינו מפעיל רענון — הוא היה רודף את זנבו', async () => {
    const { impl, calls } = stubFetch(401, 200)
    const refresh = vi.fn(async () => 'new-token')
    const res = await createAuthRetryFetch({ fetchImpl: impl, refresh })(TOKEN_URL, { method: 'POST' })

    expect(res.status).toBe(401)
    expect(calls).toHaveLength(1)
    expect(refresh).not.toHaveBeenCalled()
  })

  it('גוף שאינו מחרוזת אינו ניתן לשידור חוזר, ולכן אינו מנסה', async () => {
    const { impl, calls } = stubFetch(401, 200)
    const refresh = vi.fn(async () => 'new-token')
    const res = await createAuthRetryFetch({ fetchImpl: impl, refresh })(REST, {
      method: 'POST',
      body: new Uint8Array([1, 2, 3]),
    })

    expect(res.status).toBe(401)
    expect(calls).toHaveLength(1)
    expect(refresh).not.toHaveBeenCalled()
  })

  it('הקירור מונע מטח: 401 שני בתוך החלון אינו מרענן שוב', async () => {
    const { impl } = stubFetch(401)
    const refresh = vi.fn(async () => 'new-token')
    let clock = 1_000
    const f = createAuthRetryFetch({ fetchImpl: impl, refresh, now: () => clock, cooldownMs: 30_000 })

    await f(REST)
    clock += 5_000
    await f(REST)

    expect(refresh).toHaveBeenCalledTimes(1)
  })

  it('ואחרי שהחלון עבר מנסים שוב', async () => {
    const { impl } = stubFetch(401)
    const refresh = vi.fn(async () => 'new-token')
    let clock = 1_000
    const f = createAuthRetryFetch({ fetchImpl: impl, refresh, now: () => clock, cooldownMs: 30_000 })

    await f(REST)
    clock += 31_000
    await f(REST)

    expect(refresh).toHaveBeenCalledTimes(2)
  })
})
