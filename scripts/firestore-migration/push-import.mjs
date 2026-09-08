/**
 * דוחף את מנות ה-SQL אל המסד דרך PostgREST, כשאין דרך להתחבר בפרוטוקול
 * Postgres. הנתונים עוברים מהמכונה שמריצה ישירות לסופאבייס ב-HTTPS.
 *
 *   SUPABASE_URL=https://<ref>.supabase.co \
 *   SUPABASE_KEY=<anon או service_role> \
 *   MIG_SECRET=<הסוד של mig_exec> \
 *   node push-import.mjs <chunksDir> [filter]
 *
 * הצד השני הוא public.mig_exec(p_secret, p_sql) — פונקציה זמנית שנוצרת
 * לפני הטעינה ונמחקת אחריה. הסוד הוא מה שמונע ממי שמחזיק את ה-anon key
 * (הוא ממילא בקוד הלקוח) להריץ דרכה SQL.
 *
 * שום סוד אינו כתוב כאן: הכול מגיע מהסביבה.
 */
import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'

/* ההגדרות מגיעות מקובץ ולא ממשתני סביבה, כדי שהפקודה עצמה תישאר
   `node push-import.mjs <dir> <config>` בלי שום סוד בשורת הפקודה. */
const [dir, configPath, filter = ''] = process.argv.slice(2)
if (!dir || !configPath) {
  console.error('שימוש: node push-import.mjs <chunksDir> <config.json> [filter]')
  process.exit(1)
}
const { SUPABASE_URL, SUPABASE_KEY, MIG_SECRET } = JSON.parse(readFileSync(configPath, 'utf8'))
if (!SUPABASE_URL || !SUPABASE_KEY || !MIG_SECRET) {
  console.error('בקובץ ההגדרות חסר SUPABASE_URL / SUPABASE_KEY / MIG_SECRET')
  process.exit(1)
}

const endpoint = `${SUPABASE_URL.replace(/\/$/, '')}/rest/v1/rpc/mig_exec`
const files = readdirSync(dir).filter((f) => f.endsWith('.sql') && f.includes(filter)).sort()
if (!files.length) { console.error(`אין קבצים ב-${dir}`); process.exit(1) }
console.log(`${files.length} מנות`)

const t0 = Date.now()
let bytes = 0
for (const [i, f] of files.entries()) {
  const sql = readFileSync(join(dir, f), 'utf8')
  let err = null
  /* המנות גדולות והקשר יכול להיקטע באמצע; ניסיון חוזר בטוח, כי כל insert
     הוא on conflict do update ופקודה שהצליחה חלקית התגלגלה אחורה. */
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const r = await fetch(endpoint, {
        method: 'POST',
        headers: { apikey: SUPABASE_KEY, authorization: `Bearer ${SUPABASE_KEY}`, 'content-type': 'application/json' },
        body: JSON.stringify({ p_secret: MIG_SECRET, p_sql: sql }),
      })
      if (r.ok) { err = null; break }
      err = `${r.status} ${(await r.text()).slice(0, 500)}`
    } catch (e) { err = String(e.message ?? e).slice(0, 300) }
    if (attempt < 3) await new Promise((res) => setTimeout(res, attempt * 3000))
  }
  if (err) { console.error(`\nנכשל ב-${f}:\n${err}`); process.exit(1) }
  bytes += sql.length
  console.log(`  ${String(i + 1).padStart(3)}/${files.length}  ${f}  (${(bytes / 1e6).toFixed(1)}MB)`)
}
console.log(`\nהסתיים: ${files.length} מנות, ${(bytes / 1e6).toFixed(2)}MB, ${((Date.now() - t0) / 1000).toFixed(0)} שניות`)
