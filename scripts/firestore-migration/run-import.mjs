/**
 * מריץ את קובץ הייבוא מול המסד. חלופה ל-psql, למי שאין לו אותו מותקן.
 *
 *   npm i --no-save pg
 *   node scripts/firestore-migration/run-import.mjs <file.sql|file.sql.gz> "<connection string>"
 *
 * הקובץ נשלח כשאילתה אחת בפרוטוקול הפשוט ולא מפוצל לפקודות: פיצול על ';'
 * היה נשבר על נקודה-פסיק שיושבת בתוך הערה של אירוע. פוסטגרס מריץ מחרוזת
 * כזאת כיחידה אחת, וה-begin/commit שבתוך הקובץ עוטפים אותה.
 */
import { readFileSync } from 'node:fs'
import { gunzipSync } from 'node:zlib'
import pg from 'pg'

const [file, conn] = process.argv.slice(2)
if (!file || !conn) {
  console.error('שימוש: node run-import.mjs <file.sql|file.sql.gz> "<connection string>"')
  process.exit(1)
}

const raw = readFileSync(file)
const sql = (file.endsWith('.gz') ? gunzipSync(raw) : raw).toString('utf8')
console.log(`הקובץ: ${(sql.length / 1e6).toFixed(1)}MB`)

/* הפולר של סופאבייס דורש TLS, והתעודה שלו חתומה בשרשרת ציבורית — האימות
   נשאר דלוק. */
const client = new pg.Client({ connectionString: conn, ssl: true, statement_timeout: 0 })

const t0 = Date.now()
await client.connect()
console.log('מחובר. טוען...')
try {
  await client.query(sql)
  console.log(`נטען בהצלחה תוך ${((Date.now() - t0) / 1000).toFixed(0)} שניות.\n`)
} catch (e) {
  console.error('\nהטעינה נכשלה — שום דבר לא נכתב, הטרנזקציה התגלגלה אחורה:')
  console.error(e.message)
  await client.end()
  process.exit(1)
}

const { rows } = await client.query(`
  select 'events' t, count(*) n from events
  union all select 'tasks', count(*) from tasks
  union all select 'task_pricing', count(*) from task_pricing
  union all select 'task_contractor_terms', count(*) from task_contractor_terms
  union all select 'event_contacts', count(*) from event_contacts
  union all select 'event_activity', count(*) from event_activity
  union all select 'event_specs', count(*) from event_specs
  union all select 'event_signatures', count(*) from event_signatures
  union all select 'legacy_firestore_docs', count(*) from legacy_firestore_docs
  order by 1`)
console.table(rows)
await client.end()
