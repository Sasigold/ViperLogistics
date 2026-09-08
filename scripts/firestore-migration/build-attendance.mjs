/**
 * ממיר את הנוכחות מ-`users/{uid}/record` ל-attendance_entries.
 *
 *   node build-attendance.mjs <dumpDir> <profiles.json> <outDir>
 *
 * ‏`profiles.json` ממפה מזהה משתמש ב-Firestore ל-profiles.id בסופאבייס.
 * כמו build.mjs, הסקריפט אינו נוגע במסד — הוא פולט SQL אידמפוטנטי לקריאה.
 */
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { join } from 'node:path'
import { createHash } from 'node:crypto'
import { fields, docPath, ilDate, uuid5, q, num, json, txt } from './lib.mjs'

const [, , DUMP = 'dump', PROFILES = 'profiles.json', OUT = 'out-attendance'] = process.argv
const map = JSON.parse(readFileSync(PROFILES, 'utf8'))
const records = JSON.parse(readFileSync(join(DUMP, 'records.json'), 'utf8'))
/*
 * ‏`attendance_seq_uq` הוא unique על (profile_id, work_date, seq), והטבלה
 * אינה ריקה — האפליקציה החיה כותבת אליה. ‏`taken.json` הוא רשימת
 * ה-(profile, date, seq) שכבר תפוסים שם, ומספור הייבוא מדלג עליהם במקום
 * להתנגש. בלי הקובץ ההנחה היא טבלה ריקה.
 */
const TAKEN = join(DUMP, 'taken.json')
const taken = new Set(existsSync(TAKEN)
  ? JSON.parse(readFileSync(TAKEN, 'utf8')).map((t) => `${t[0]}|${t[1]}|${t[2]}`)
  : [])
mkdirSync(join(OUT, 'chunks'), { recursive: true })

const warn = new Map()
const note = (k) => warn.set(k, (warn.get(k) ?? 0) + 1)

/* כל הרשומות של כל העובדים, כל אחת עם הפרופיל שלה. */
const all = []
for (const [uid, docs] of Object.entries(records)) {
  const profile = map[uid]
  if (!profile) { if (docs.length) note(`אין פרופיל למשתמש ${uid}`); continue }
  for (const d of docs) all.push({ path: docPath(d), profile, uid, f: fields(d) })
}
all.sort((a, b) => String(a.f.start).localeCompare(String(b.f.start)))

/*
 * שלוש רשומות במקור אינן נוכחות שמישה: שתיים נפתחו ולא נסגרו לפני חודשים,
 * ואחת נפתחה ונסגרה באותה שנייה (cama=0). ‏`attendance_order` אוסר יציאה
 * שאינה אחרי הכניסה, ו-`attendance_one_open` מתיר משמרת פתוחה אחת לעובד —
 * שתי המשמרות הנטושות היו נראות במסך כאילו העובד מוחתם מאפריל.
 *
 * הן נטענות עם deleted_at: השורה קיימת, הארכיון מחזיק אותה במלואה, והלו״ז
 * אינו מציג עובד שאינו שם. המשמרת הפתוחה האחרונה של כל עובד נשארת פתוחה.
 */
const lastOpen = new Map()
for (const r of all) if (!r.f.end) lastOpen.set(r.profile, r.path)

const seqOf = new Map()
const rowsEntry = [], rowsBonus = [], rowsLegacy = [], verify = []
const rateByProfile = new Map()

for (const r of all) {
  const { f, path, profile } = r
  const id = uuid5(path)
  const workDate = ilDate(f.start)
  const key = `${profile}|${workDate}`
  let seq = (seqOf.get(key) ?? 0) + 1
  while (taken.has(`${profile}|${workDate}|${seq}`)) seq += 1
  seqOf.set(key, seq)

  const zeroLength = f.end && new Date(f.end) <= new Date(f.start)
  const staleOpen = !f.end && lastOpen.get(profile) !== path
  const unusable = zeroLength || staleOpen
  if (zeroLength) note('רשומה באורך אפס — נטענה מסומנת כמחוקה')
  if (staleOpen) note('משמרת נטושה שלא נסגרה — נטענה מסומנת כמחוקה')

  const flags = []
  if (f.daStEdit || f.daEnEdit) flags.push('edited')
  if (!f.mishmeretRef) flags.push('no_shift')
  if (!f.location) flags.push('no_site_coords')
  if (unusable) flags.push('auto_closed')
  /* סימון קבוע: מאיפה השורה הגיעה. הוא גם מה שמאפשר להסיר בדיוק את מה
     שהייבוא כתב בלי לגעת בשורה שנוצרה באפליקציה. */
  flags.push('legacy_import')

  const gp = (g) => (g ? [g.latitude ?? null, g.longitude ?? null] : [null, null])
  const [inLat, inLng] = gp(f.location)
  const [outLat, outLng] = gp(f.locationSiom)
  const clockOut = zeroLength ? null : (f.end ?? null)

  rowsEntry.push([
    `'${id}'`, `'${profile}'`, q(workDate), String(seq),
    q(f.start), clockOut ? q(clockOut) : 'null',
    num(inLat), num(inLng), num(outLat), num(outLng),
    `'clock'`, `'approved'`,
    `'{${flags.join(',')}}'`,
    unusable ? 'now()' : 'null',
    q(f.start), q(clockOut ?? f.start),
  ].join(','))

  /* ‏`attendance_entry_bonus.amount > 0`. אחת-עשרה רשומות נושאות בונוס 0
     ואחת נושאת ‎-210 (ניכוי); שורת בונוס לא נוצרת עבורן. */
  if (f.bonos != null && Number(f.bonos) > 0) {
    rowsBonus.push([`'${uuid5(`${path}#bonus`)}'`, `'${id}'`, num(f.bonos), q(f.start)].join(','))
  } else if (f.bonos != null && Number(f.bonos) !== 0) {
    note(`בונוס שלילי (${f.bonos}) — לא נטען`)
  }

  /* התעריף יושב על כל רשומה במקור ומשתנה לאורך השנים. worker_pay_settings
     מחזיקה ערך אחד, ולכן נלקח האחרון שאינו אפס — הרשומות ממוינות לפי זמן. */
  if (Number(f.sacar) > 0) rateByProfile.set(profile, Number(f.sacar))

  rowsLegacy.push([q(path), `'record'`, q(path.split('/').pop()), 'null', 'null', json(f)].join(','))
  /* חותמות הזמן משווֹת כאלפיות-שנייה מאז epoch ולא כמחרוזת: המקור כותב
     מיקרו-שניות, פוסטגרס מחזיר אותן בפורמט משלו, והשוואת מחרוזות הייתה
     בודקת עיצוב במקום ערך. */
  const ms = (t) => (t ? String(Math.floor(Date.parse(t))) : '')
  verify.push([id, profile, workDate, String(seq), ms(f.start), ms(clockOut), String(unusable)].join('|'))
}

const rowsPay = [...rateByProfile].map(([p, rate]) => [`'${p}'`, num(rate)].join(','))

/* ── פליטה ─────────────────────────────────────────────────────────────── */
const CHUNK_BYTES = Number(process.env.CHUNK_BYTES ?? 180_000)
let seqFile = 0
function emit(name, cols, rows, conflict) {
  if (!rows.length) return
  const head = `insert into ${name} (${cols}) values\n`
  let batch = [], size = 0
  const flush = () => {
    if (!batch.length) return
    const sql = `${head}(${batch.join('),\n(')})\n${conflict};`
    writeFileSync(join(OUT, 'chunks', `${String(++seqFile).padStart(3, '0')}_${name}.sql`), sql + '\n')
    batch = []; size = 0
  }
  for (const r of rows) {
    if (size && size + r.length > CHUNK_BYTES) flush()
    batch.push(r); size += r.length + 3
  }
  flush()
}

/* מחיקת מה שהייבוא כתב בריצה קודמת, לפי המזהים הדטרמיניסטיים עצמם.
   ‏`on conflict (id) do update` לבדו אינו מספיק: אם ריצה קודמת נתנה seq
   אחר, השורה הישנה הייתה נשארת ותופסת אותו. */
writeFileSync(join(OUT, 'chunks', '000_purge.sql'),
  `delete from attendance_entries where id in (${all.map((r) => `'${uuid5(r.path)}'`).join(',')});\n`)

emit('attendance_entries',
  'id,profile_id,work_date,seq,clock_in_at,clock_out_at,clock_in_lat,clock_in_lng,clock_out_lat,clock_out_lng,source,status,flags,deleted_at,created_at,updated_at',
  rowsEntry,
  'on conflict (id) do update set profile_id=excluded.profile_id,work_date=excluded.work_date,seq=excluded.seq,clock_in_at=excluded.clock_in_at,clock_out_at=excluded.clock_out_at,clock_in_lat=excluded.clock_in_lat,clock_in_lng=excluded.clock_in_lng,clock_out_lat=excluded.clock_out_lat,clock_out_lng=excluded.clock_out_lng,flags=excluded.flags,deleted_at=excluded.deleted_at,updated_at=excluded.updated_at')
emit('attendance_entry_bonus', 'id,entry_id,amount,created_at', rowsBonus,
  'on conflict (entry_id) do update set amount=excluded.amount')
emit('worker_pay_settings', 'profile_id,hourly_rate', rowsPay,
  'on conflict (profile_id) do update set hourly_rate=excluded.hourly_rate')
emit('legacy_firestore_docs', 'doc_path,collection,doc_id,event_id,task_id,data', rowsLegacy,
  'on conflict (doc_path) do update set data=excluded.data,imported_at=now()')

const md5 = createHash('md5').update([...verify].sort().join('\n')).digest('hex')
const stats = { attendance_entries: rowsEntry.length, attendance_entry_bonus: rowsBonus.length,
                worker_pay_settings: rowsPay.length, legacy_firestore_docs: rowsLegacy.length, md5 }
writeFileSync(join(OUT, '_verify.json'), JSON.stringify(stats, null, 1))
console.log(JSON.stringify(stats, null, 2))
if (warn.size) console.log('\nהערות:\n' + [...warn].sort((a, b) => b[1] - a[1]).map(([k, n]) => `  ${String(n).padStart(4)}  ${k}`).join('\n'))
console.log('\nתעריפים:', JSON.stringify(Object.fromEntries(rateByProfile)))
