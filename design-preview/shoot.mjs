// שימוש: node shoot.mjs <שם-וריאנט|baseline> [מסך...]
import { chromium } from 'playwright-core'
import { readFileSync, mkdirSync, existsSync } from 'node:fs'
import { installMock } from './mock.mjs'
import { events } from './fixtures.mjs'

const BASE = process.env.BASE ?? 'http://localhost:5199'
const variant = process.argv[2] ?? 'baseline'
const only = process.argv.slice(3)
// Heebo נטען בפרודקשן מ-Google Fonts; בסביבה הזו אין גישה אליו, אז טוענים את הקובץ המקומי כדי שהצילום ייראה כמו באמת
const FONT = `@font-face{font-family:'Heebo';src:url('/fonts/heebo-400.ttf');font-weight:100 550}@font-face{font-family:'Heebo';src:url('/fonts/heebo-700.ttf');font-weight:551 900}`
const css = FONT + (variant === 'baseline' ? '' : readFileSync(new URL(`./variants/${variant}.css`, import.meta.url), 'utf8'))
const _unused = variant === 'baseline' ? '' : readFileSync(new URL(`./variants/${variant}.css`, import.meta.url), 'utf8')
const out = new URL(`./shots/${variant}/`, import.meta.url).pathname
mkdirSync(out, { recursive: true })

const ev = events[0].id
const SCREENS = [
  { name: '01-calendar-month', path: '/calendar' },
  { name: '02-calendar-week', path: '/calendar', act: async (p) => { await p.getByRole('button', { name: /שבוע/ }).first().click(); await p.waitForTimeout(500); await p.getByRole('button', { name: /היום/ }).first().click() } },
  { name: '03-board', path: '/board' },
  { name: '04-event-detail', path: `/events/${ev}`, full: true },
  { name: '05-event-edit', path: `/events/${ev}`, act: async (p) => { await p.getByRole('button', { name: /עריכ/ }).first().click() } },
  { name: '06-board-edit-panel', path: '/board', act: async (p) => { const c = p.getByText('לא שובץ').first(); await c.click(); await p.waitForTimeout(500); await c.click() } },
]

const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' })
for (const theme of ['light', 'dark']) {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: process.env.CLIP ? 2 : 1, locale: 'he-IL', timezoneId: 'Asia/Jerusalem' })
  await ctx.addInitScript((t) => localStorage.setItem('vl-theme', t), theme)
  await installMock(ctx)
  await ctx.clock?.setFixedTime?.(new Date('2026-09-29T09:00:00+03:00'))
  const page = await ctx.newPage()
  page.on('pageerror', (e) => console.log('PAGEERROR', e.message))
  for (const s of SCREENS) {
    if (only.length && !only.some((o) => s.name.includes(o))) continue
    await page.goto(BASE + s.path, { waitUntil: 'networkidle' }).catch(() => {})
    await page.waitForTimeout(1200)
    await page.addStyleTag({ content: css })
    await page.evaluate(() => document.fonts.ready)
    if (s.act) { try { await s.act(page); await page.waitForTimeout(900) } catch (e) { console.log('act failed', s.name, e.message.split('\n')[0]) } }
    const clip = process.env.CLIP ? Object.fromEntries(process.env.CLIP.split(',').map((v, i) => [['x', 'y', 'width', 'height'][i], +v])) : undefined
    await page.screenshot({ path: clip ? `/tmp/clip-${s.name}-${theme}.png` : `${out}${s.name}-${theme}.png`, fullPage: !clip && !!s.full, clip })
    console.log('shot', variant, s.name, theme)
  }
  await ctx.close()
}
await browser.close()
