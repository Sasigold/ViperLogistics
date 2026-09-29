// צילומי ה-Layout Lab: node shoot-lab.mjs [theme] [mobile]
import { chromium } from 'playwright-core'
import { mkdirSync } from 'node:fs'
import { installMock } from './mock.mjs'
const BASE = process.env.BASE ?? 'http://localhost:5199/design-preview/lab/index.html'
const mobile = !!process.env.MOBILE
const out = new URL('./shots/lab/', import.meta.url).pathname
mkdirSync(out, { recursive: true })
const SHOTS = [
  { n: '1-calendar-agenda', q: 'page=calendar&sel=e1-0000-4000-8000-000000000002' },
  { n: '2-dispatch-timeline', q: 'page=dispatch&day=2026-09-29', full: true },
  { n: '3-event-story', q: 'page=event&event=e1-0000-4000-8000-000000000001', full: true },
]
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' })
for (const theme of ['light', 'dark']) {
  const ctx = await b.newContext({ viewport: mobile ? { width: 390, height: 844 } : { width: 1440, height: 900 }, isMobile: mobile, hasTouch: mobile, locale: 'he-IL', timezoneId: 'Asia/Jerusalem' })
  await installMock(ctx)
  const p = await ctx.newPage()
  p.on('pageerror', (e) => console.log('PAGEERROR', e.message))
  p.on('console', (m) => m.type() === 'error' && !/WebSocket|CERT|Failed to load/.test(m.text()) && console.log('CONSOLE', m.text().slice(0, 200)))
  for (const s of SHOTS) {
    await p.goto(`${BASE}?${s.q}&theme=${theme}`, { waitUntil: 'networkidle' }).catch(() => {})
    await p.waitForTimeout(1500)
    if (s.full && !mobile) await p.setViewportSize({ width: 1440, height: 1500 }); else await p.setViewportSize(mobile ? { width: 390, height: 844 } : { width: 1440, height: 900 })
    await p.waitForTimeout(300)
    await p.screenshot({ path: `${out}${s.n}${mobile ? '-m' : ''}-${theme}.png`, fullPage: mobile && !!s.full })
    console.log('shot', s.n, theme)
  }
  await ctx.close()
}
await b.close()
