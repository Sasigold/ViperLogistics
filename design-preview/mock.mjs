import { TABLES, RPCS, me } from './fixtures.mjs'

const REF = 'demo'
const SUPA = 'https://demo.supabase.co'
export const SUPABASE_URL = SUPA

function applyFilters(rows, params) {
  return rows.filter((r) => {
    for (const [k, v] of params) {
      if (['select', 'order', 'limit', 'offset', 'or', 'and'].includes(k)) continue
      const m = /^(eq|gte|lte|gt|lt|is|in|neq)\.(.*)$/.exec(v)
      if (!m || !(k in r)) continue
      const [, op, val] = m
      const cell = r[k]
      if (op === 'eq' && String(cell) !== val) return false
      if (op === 'neq' && String(cell) === val) return false
      if (op === 'gte' && !(String(cell) >= val)) return false
      if (op === 'lte' && !(String(cell) <= val)) return false
      if (op === 'is' && val === 'null' && cell != null) return false
      if (op === 'is' && val === 'false' && cell !== false) return false
      if (op === 'in' && !val.replace(/[()]/g, '').split(',').includes(String(cell))) return false
    }
    return true
  })
}

export async function installMock(context, opts = {}) {
  await context.addInitScript(
    ([ref, session]) => {
      localStorage.setItem(`sb-${ref}-auth-token`, JSON.stringify(session))
    },
    [REF, {
      access_token: 'demo.jwt.token', refresh_token: 'demo', token_type: 'bearer', expires_in: 36000,
      expires_at: Math.floor(Date.now() / 1000) + 36000,
      user: { id: me.profile.id, aud: 'authenticated', role: 'authenticated', email: 'demo@example.com', app_metadata: {}, user_metadata: {}, created_at: '2026-01-01' },
    }],
  )
  await context.route(`${SUPA}/**`, async (route) => {
    const req = route.request()
    const url = new URL(req.url())
    const json = (body, status = 200) =>
      route.fulfill({ status, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(body) })
    if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' } })
    if (url.pathname.startsWith('/auth/v1')) return json({})
    if (url.pathname.startsWith('/rest/v1/rpc/')) {
      const fn = url.pathname.split('/').pop()
      if (fn === 'get_my_permissions') return json(opts.employee ? { ...me, roles: ['worker'] } : me)
      if (RPCS[fn]) return json(RPCS[fn])
      return json(req.method() === 'POST' ? [] : null)
    }
    if (url.pathname.startsWith('/rest/v1/')) {
      const table = url.pathname.split('/').pop()
      let rows = TABLES[table] ?? []
      rows = applyFilters(rows, url.searchParams)
      const wantsObject = (req.headers()['accept'] ?? '').includes('vnd.pgrst.object')
      if (wantsObject) return rows[0] ? json(rows[0]) : json({ message: 'no rows' }, 406)
      return route.fulfill({
        status: 200, contentType: 'application/json',
        headers: { 'access-control-allow-origin': '*', 'content-range': `0-${Math.max(rows.length - 1, 0)}/${rows.length}` },
        body: JSON.stringify(rows),
      })
    }
    return json({})
  })
}
