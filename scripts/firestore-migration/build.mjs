/**
 * בונה את ה-SQL של ההעברה מתוך ה-dump של Firestore.
 *
 *   node build.mjs <dumpDir> <catalog.json> <outDir>
 *
 * הסקריפט אינו נוגע במסד. הוא קורא את המסמכים כפי שהם, מצליב אותם, ופולט
 * קבצי SQL אידמפוטנטיים (`on conflict do update` על מפתח שנגזר מנתיב המסמך).
 * ההפרדה הזאת מכוונת: אפשר לקרוא את מה שעומד להיכתב לפני שכותבים אותו.
 */
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { fields, docPath, ilDate, ilTime, uuid5, q, num, bool, json, uuidLit, uuidArr, txt } from './lib.mjs'

const [, , DUMP = 'dump', CATALOG = 'catalog.json', OUT = 'out'] = process.argv
/* LIMIT=<n> בונה רק את n האירועים הראשונים מכל קולקציה. לטעינת ניסיון
   שעוברת בדיוק באותו קוד כמו הטעינה המלאה. */
const LIMIT = Number(process.env.LIMIT ?? 0) || 0
const cat = JSON.parse(readFileSync(CATALOG, 'utf8'))
const load = (f) => JSON.parse(readFileSync(join(DUMP, f), 'utf8'))
mkdirSync(OUT, { recursive: true })

/* ── הגדרות המקור ────────────────────────────────────────────────────────── */
const SOURCES = [
  { coll: 'achaotMechir',  customer: 'ארקו',        events: 'achaotMechir.json',  subs: ['grp_mesimotArco.json', 'grp_mesimot.json'] },
  { coll: 'caesar',        customer: 'קיסר',        events: 'caesar.json',        subs: ['grp_mesimotCaesar.json'] },
  { coll: 'eventsCdesign', customer: 'שיא עיצובים', events: 'eventsCdesign.json', subs: ['grp_mesimotC.json'] },
]

/* איחוד הכפילויות שסוכם מול הלקוח. מפתח שאינו כאן עובר כמות שהוא. */
const EVENT_STATUS = {
  'טרם אושר': 'טרם אושר', 'הזמנה חדשה': 'הזמנה חדשה',
  'מאושר סופית': 'אישור סופי', 'אושר סופית': 'אישור סופי',
  'הארוע אושר סופית': 'אישור סופי', 'מאושר': 'אישור סופי',
  'מתקיים': 'מתקיים', 'לא מתקיים': 'בוטל', 'בוטל': 'בוטל',
  'ארוע בוצע': 'אירוע בוצע', 'הקמה בוצעה': 'הקמה בוצעה',
  'תומחר': 'תומחר', 'בהמתנה לתמחור מחדש': 'בהמתנה לתמחור מחדש',
}
const EM_ALIAS = {
  'רק הרכבה': 'הרכבה בלבד', 'רק פירוק': 'פירוק בלבד',
  'הובלה': 'הובלה בלבד', 'עובד מחסן': 'מחסן', 'סידור מחסן': 'מחסן',
}

const warn = new Map()
const note = (k) => warn.set(k, (warn.get(k) ?? 0) + 1)

const statusEvent = (s, cancelled) => {
  if (cancelled) return cat.status_event['בוטל']
  const name = EVENT_STATUS[txt(s) ?? '']
  if (!name) { if (s) note(`סטטוס אירוע לא ממופה: ${txt(s)}`); return cat.status_event['טרם אושר'] }
  return cat.status_event[name]
}
/* למשימה יש שלושה סטטוסים בלבד (הושלם/בוטל/בביצוע נמחקו ב-0063 ואילך).
   "מתוכנן" הוא הנייטרלי: הוא אינו מפרסם לעובדים כמו "משובץ", ומשימה של
   אירוע מבוטל ממילא אינה נראית — app.live_tasks מסננת אותה לפי האירוע. */
const STATUS_TASK = cat.status_task['מתוכנן']

const execMethod = (name) => {
  const n = txt(name); if (!n) return null
  const id = cat.exec_methods[EM_ALIAS[n] ?? n]
  if (!id) note(`אופן ביצוע לא ממופה: ${n}`)
  return id ?? null
}
const contractor = (name) => {
  const n = txt(name); if (!n) return null
  const id = cat.contractors[n]
  if (!id) note(`קבלן לא ממופה: ${n}`)
  return id ?? null
}
function taskType(akameOperok) {
  const n = txt(akameOperok)
  if (!n) return { id: cat.task_types['אחר'], title: null, section: null }
  if (n === 'הקמה') return { id: cat.task_types['הקמה'], title: null, section: 'setup' }
  if (n === 'פירוק') return { id: cat.task_types['פירוק'], title: null, section: 'teardown' }
  if (/מחסן/.test(n)) return { id: cat.task_types['עבודה במחסן'], title: n, section: null }
  if (n === 'סידור') return { id: cat.task_types['סידור'], title: null, section: null }
  if (n === 'איסוף') return { id: cat.task_types['איסוף'], title: null, section: null }
  return { id: cat.task_types['אחר'], title: n, section: null }
}
/** rechev → משאיות מהקטלוג; מה שאין לו התאמה נשמר בטקסט החופשי. */
function trucks(rechev, ayzeMasait) {
  const ids = [], free = []
  for (const r of rechev ?? []) {
    const n = txt(r); if (!n) continue
    if (cat.trucks[n]) ids.push(cat.trucks[n]); else free.push(n)
  }
  const extra = txt(ayzeMasait)
  if (extra) free.push(extra)
  return { ids: [...new Set(ids)], free: free.length ? [...new Set(free)].join(', ') : null }
}
const ff = (customer, label) => cat.form_fields[`${customer}|${label}`]

/* ── קריאה ───────────────────────────────────────────────────────────────── */
const events = []        // {id, path, coll, customer, f}
const eventByPath = new Map()
const tasks = []         // {id, path, eventId, customerName, f, section, fromSub}
const legacy = []

for (const src of SOURCES) {
  const docs = load(src.events)
  for (const doc of (LIMIT ? docs.slice(0, LIMIT) : docs)) {
    const path = docPath(doc), id = uuid5(path), f = fields(doc)
    const e = { id, path, coll: src.coll, customer: src.customer, f }
    events.push(e); eventByPath.set(path, e)
    legacy.push({ path, coll: src.coll, docId: path.split('/').pop(), eventId: id, taskId: null, data: f })
  }
}
for (const src of SOURCES) {
  for (const file of src.subs) {
    for (const doc of load(file)) {
      const path = docPath(doc), f = fields(doc)
      const parentPath = path.split('/').slice(0, 2).join('/')
      const parent = eventByPath.get(parentPath)
      if (!parent) {
        /* תת-קולקציה שהאירוע שמעליה נמחק מ-Firestore. אין למשימה למה
           להתחבר, ולכן היא אינה נטענת כמשימה — אבל היא כן נשמרת בארכיון. */
        if (!LIMIT) note('משימה בתת-קולקציה שהאירוע שמעליה נמחק')
        if (!LIMIT) legacy.push({ path, coll: path.split('/')[2], docId: path.split('/').pop(), eventId: null, taskId: null, data: f })
        continue
      }
      const id = uuid5(path)
      tasks.push({ id, path, eventId: parent.id, event: parent, customer: src.customer, f, fromSub: true })
      legacy.push({ path, coll: path.split('/')[2], docId: path.split('/').pop(), eventId: parent.id, taskId: id, data: f })
    }
  }
}
/* הקולקציה הראשית: משימות של אירועי ארקו שאין להם תת-קולקציה, ולצידן
   משימות עצמאיות (כוח אדם / אחר) שאינן תלויות באירוע כלל. */
for (const doc of load('mesimot.json')) {
  const path = docPath(doc), id = uuid5(path), f = fields(doc)
  const ref = f.shyachacatMechir ?? f.shayach
  const parent = ref ? eventByPath.get(ref) : null
  if (LIMIT && !parent) continue
  if (ref && !parent) note('הפניה לאירוע שאינו קיים')
  const customer = parent ? parent.customer
    : f.type === 'ארקו' ? 'ארקו' : f.type === 'קיסר בינויים' ? 'קיסר' : null
  tasks.push({ id, path, eventId: parent?.id ?? null, event: parent ?? null, customer, f, fromSub: false })
  legacy.push({ path, coll: 'mesimot', docId: path.split('/').pop(), eventId: parent?.id ?? null, taskId: id, data: f })
}

/* ── שורות היעד ──────────────────────────────────────────────────────────── */
const rowsEvent = [], rowsContact = [], rowsTask = [], rowsPricing = [],
      rowsTerms = [], rowsActivity = [], rowsSpec = [], rowsSign = []

/** custom_fields לפי הלקוח. number נשמר כמספר, השאר כמחרוזת — כמו app.event_custom_patch. */
function customFields(customer, f) {
  const out = {}
  const put = (label, value, isNum) => {
    const key = ff(customer, label); if (!key) return
    if (value == null || value === '') return
    out[key] = isNum ? Number(value) : String(value)
  }
  if (customer === 'ארקו') {
    put('סכום הובלה', f.scomObala, true)
    put('מחיר לוגיסטיקה', f.mechirLogistica, true)
    put('פירוט לוגיסטיקה', txt(f.mechirLogisticaPirot))
    put('מחיר הובלה', f.mechirHovala, true)
    put('פירוט הובלה', txt(f.mechirHovalaPirot))
    put('מתגלגל להובלה', f.mitgalgelLaovala, true)
    put('תנאי תשלום', txt(f.tnaayTashlum))
  } else if (customer === 'קיסר') {
    put('מחיר ריהוט', f.mechirRihot, true)
    const gove = txt(f.myGove)
    if (gove === 'קיסר' || gove === 'וייפר') put('מי גובה', gove)
    const TERMS = { 'תאריך האירוע': 'תאריך הארוע', 'שוטף 30': 'שוטף + 30', 'שוטף 60': 'שוטף + 60' }
    const t = TERMS[txt(f.typePrice) ?? '']
    if (t) put('תנאי תשלום', t)
  } else if (customer === 'שיא עיצובים') {
    put('מחיר ריהוט', f.mechirRihot, true)
    put('מחיר חדש', f.priceChadash, true)
    put('קישור ל-Eruit', txt(f.linkToEroit))
  }
  return out
}

for (const e of events) {
  const f = e.f
  const msgs = (f.maseggges ?? []).map((m) => m?.timeCreate).filter(Boolean).sort()
  const createdAt = msgs[0] ?? f.date ?? null
  const updatedAt = msgs.at(-1) ?? createdAt

  rowsEvent.push([
    `'${e.id}'`, `'${cat.customers[e.customer]}'`,
    q(txt(f.name)), q(txt(f.makat)), q(ilDate(f.date)),
    q(txt(f.mikom)), q(txt(f.earotLmikom)),
    num(f.nefach), num(f.masaiot), q(txt(f.earot)),
    uuidLit(statusEvent(f.statos, f.mevutal === true)),
    /* chania=false פירושו שאין חניה. הכיוון הפוך מהעמודה, ולכן ההיפוך כאן. */
    bool(f.chania === false),
    bool(f.sabalot === true), bool(f.aisufMesapak === true),
    json(customFields(e.customer, f)),
    createdAt ? q(createdAt) : 'now()', updatedAt ? q(updatedAt) : 'now()',
  ].join(','))

  const cname = txt(f.nameAishKesher), cphone = txt(f.aishKesher)
  if (cname || cphone) rowsContact.push([`'${e.id}'`, q(cname), q(cphone)].join(','))

  ;(f.maseggges ?? []).forEach((m, i) => {
    const body = txt(String(m?.massege ?? '').replace(/<br\s*\/?>/gi, '\n'))
    if (!body) return
    const kind = i === 0 && m?.type === 'מערכת' ? 'created' : m?.type === 'הודעה' ? 'note' : 'changed'
    rowsActivity.push([`'${e.id}'`, `'${kind}'`, q(txt(m?.name)), q(body), q(m?.timeCreate ?? createdAt)].join(','))
  })

  /* מפרטים: `mifrat` (מערך עם time+url), `informationImage` (מערך URL-ים)
     ו-`pkodatMivcha`. הקבצים נשארים ב-Firebase Storage לפי החלטת הלקוח,
     ולכן source='link' וה-URL הוא הכתובת המקורית. */
  let version = 0
  const specs = []
  for (const m of f.mifrat ?? []) if (typeof m?.mifrat === 'string' && /^https?:\/\//.test(m.mifrat)) specs.push({ url: m.mifrat, at: m.time, title: 'מפרט' })
  if (typeof f.mifrat === 'string' && /^https?:\/\//.test(f.mifrat)) specs.push({ url: f.mifrat, at: null, title: 'מפרט' })
  for (const u of f.informationImage ?? []) if (typeof u === 'string' && /^https?:\/\//.test(u)) specs.push({ url: u, at: null, title: 'תמונה' })
  for (const s of specs) {
    version += 1
    rowsSpec.push([`'${uuid5(`${e.path}#spec${version}`)}'`, `'${e.id}'`, String(version),
      `'link'`, q(s.url), q(s.title), q(s.at ?? createdAt)].join(','))
  }

  if (f.sign?.sign && /^https?:\/\//.test(String(f.sign.sign))) {
    rowsSign.push([`'${uuid5(`${e.path}#sign`)}'`, `'${e.id}'`,
      q(txt(f.sign.name) ?? 'לא נרשם שם'), q(f.sign.sign), q(txt(f.sign.name)), q(updatedAt ?? createdAt)].join(','))
  }
}

/** שורת משימה אחת — ממסמך משימה או מהשדות הפנימיים של האירוע. */
function pushTask(t) {
  const { id, eventId, customer, f, event, section } = t
  const ev = event?.f ?? {}
  const tt = t.type ?? taskType(f.akameOperok)
  const sec = section ?? tt.section
  const { ids: truckIds, free } = trucks(f.rechev, f.ayzeMasait)
  const rashi = txt(f.cablanRashiName ?? (sec === 'setup' ? ev.cablanRashiAkamaName : sec === 'teardown' ? ev.cablanRashiPirokName : null))
  /* "בוצע ע״י" קיים אצל ארקו בלבד; אצל שאר הלקוחות העמודה חייבת להישאר viper. */
  const performedBy = customer === 'ארקו' && rashi === 'ארקו' ? 'arko' : 'viper'
  const cab = contractor(f.cablanName ?? f.cablan?.[0]?.name
    ?? (sec === 'setup' ? ev.cablanAkamaName : sec === 'teardown' ? ev.cablanPirokName : null))

  /* מסמך משימה אינו תמיד מלא: שעות/עובדים/אופן ביצוע נשמרו לעיתים על
     האירוע בלבד. הנפילה חזרה לשדות החלק המתאים באירוע היא מה שמונע
     משימות ריקות באלף אירועי ארקו הישנים. */
  const bySection = (setup, teardown) => (sec === 'setup' ? ev[setup] : sec === 'teardown' ? ev[teardown] : null)
  /* `tasks.onsite_end_time` היא עמודה מחושבת (start + hours_count) ולא ניתן
     לכתוב אליה. כדי שהשעה שמוצגת תהיה זו שהייתה במקור, כשאין zmanMesima
     נגזרות השעות מהפרש חותמות הזמן — וזה גם עובד חוצה-חצות. */
  const spanHours = (a, b) => {
    if (!a || !b) return null
    const h = (new Date(b) - new Date(a)) / 3_600_000
    return Number.isFinite(h) && h > 0 && h < 24 ? Math.round(h * 100) / 100 : null
  }
  /* הפרש חותמות הזמן קודם ל-zmanMesima: השניים מסכימים ב-1,483 מתוך 1,493
     המשימות שיש בהן שניהם, ובעשר שנותרו החותמות הן שמתארות את מה שהלו״ז
     הישן הציג בפועל (zmanMesima=0 מול טווח של שלוש שעות). */
  const hours = spanHours(f.start ?? f.dateStart, f.end ?? f.dateEnd)
    ?? f.zmanMesima ?? bySection('akamaZman', 'pirokZman')
  const workers = f.camotAnashim ?? bySection('akamaOvdim', 'pirokOvdim')
  const ofen = f.ofenBichoa ?? bySection('akamaOfenBichoa', 'pirokOfenBichoa')
  const notes = txt(f.earot) ?? txt(bySection('earotAkamaTifol', 'earotPirokTifol'))

  rowsTask.push([
    `'${id}'`, uuidLit(eventId), uuidLit(customer ? cat.customers[customer] : null),
    `'${tt.id}'`, q(tt.title), q(ilDate(f.date ?? f.dateStart)),
    q(ilTime(f.start ?? f.dateStart)), q(txt(f.timeMachsan)),
    num(hours),
    String(Number(workers ?? 0) || 0),
    uuidLit(execMethod(ofen)), uuidArr(truckIds), q(free),
    q(notes), `'${STATUS_TASK}'`, uuidLit(cab),
    q(txt(f.mikom) ?? txt(ev.mikom)), `'${performedBy}'`,
  ].join(','))

  /* מחיר ללקוח: על משימת הקמה/פירוק הוא יושב על האירוע (mechirAkama /
     mechirPirok); `mecir` של המשימה הוא הגיבוי, ועל משימה עצמאית — היחיד. */
  const price = sec === 'setup' ? (ev.mechirAkama ?? f.mecir)
    : sec === 'teardown' ? (ev.mechirPirok ?? f.mecir) : f.mecir
  if (price != null && price !== '') rowsPricing.push([`'${id}'`, num(price), 'true'].join(','))

  /* עלות הקבלן: המערך `cablan` על המשימה, או cablan_akama/cablan_pirok על
     האירוע. הסכומים כאן הם מה שמשלמים לקבלן, לא מה שגובים מהלקוח. */
  const arr = f.cablan ?? (sec === 'setup' ? ev.cablan_akama : sec === 'teardown' ? ev.cablan_pirok : null) ?? []
  const seen = new Set()
  for (const c of arr) {
    const cid = contractor(c?.name); if (!cid || seen.has(cid)) continue
    seen.add(cid)
    rowsTerms.push([`'${id}'`, `'${cid}'`, num(c?.price ?? 0), `'field'`].join(','))
  }
  if (!seen.size && cab) {
    const p = f.price ?? (sec === 'setup' ? ev.priceAkama : sec === 'teardown' ? ev.pricePirok : null)
    if (p != null && p !== '') rowsTerms.push([`'${id}'`, `'${cab}'`, num(p), `'field'`].join(','))
  }
}

for (const t of tasks) pushTask(t)

/* משימות שנגזרות מהאירוע עצמו: אירוע שאין לו מסמך משימה לחלק מסוים, אבל יש
   עליו את הנתונים שלו (עובדים/שעות/אופן ביצוע). בלי זה 143 אירועי ארקו
   היו נכנסים בלי משימות כלל. */
const covered = new Map()
for (const t of tasks) {
  if (!t.eventId) continue
  const sec = taskType(t.f.akameOperok).section
  if (sec) covered.set(`${t.eventId}|${sec}`, true)
}
let synthesized = 0
for (const e of events) {
  const f = e.f
  for (const [sec, pre] of [['setup', 'akama'], ['teardown', 'pirok']]) {
    if (covered.has(`${e.id}|${sec}`)) continue
    const ovdim = f[`${pre}Ovdim`], zman = f[`${pre}Zman`], ofen = f[`${pre}OfenBichoa`]
    if (ovdim == null && zman == null && !ofen) continue
    synthesized += 1
    pushTask({
      id: uuid5(`${e.path}#${sec}`), eventId: e.id, customer: e.customer, event: e, section: sec,
      type: { id: cat.task_types[sec === 'setup' ? 'הקמה' : 'פירוק'], title: null, section: sec },
      f: {
        date: sec === 'setup' ? (f.dateStart ?? f.date) : (f.dateEnd ?? f.date),
        dateStart: sec === 'setup' ? f.dateStart : f.dateEnd,
        end: sec === 'setup' ? null : f.dateEnd,
        camotAnashim: ovdim, zmanMesima: zman, ofenBichoa: ofen,
        earot: sec === 'setup' ? f.earotAkamaTifol : f.earotPirokTifol,
        mikom: f.mikom,
      },
    })
  }
}

/* ── פליטה ───────────────────────────────────────────────────────────────── */
/*
 * הטעינה עוברת דרך ערוץ עם תקרה לגודל בקשה, ולכן כל פקודה נכתבת לקובץ
 * משלה בתוך OUT/chunks — עם תקציב בתים ולא מספר שורות, כי אורך שורה משתנה
 * פי עשרה בין טבלה לטבלה. הסדר הלקסיקוגרפי של השמות הוא סדר ההרצה.
 */
const CHUNK_BYTES = Number(process.env.CHUNK_BYTES ?? 180_000)
mkdirSync(join(OUT, 'chunks'), { recursive: true })
let seq = 0
const chunkFiles = []
function writeChunk(table, sql) {
  const name = `${String(++seq).padStart(3, '0')}_${table}.sql`
  writeFileSync(join(OUT, 'chunks', name), sql + '\n')
  chunkFiles.push({ file: name, bytes: Buffer.byteLength(sql) })
}
function emit(name, cols, rows, conflict, prefix) {
  if (!rows.length) return
  const head = `insert into ${name} (${cols}) values\n`
  const parts = []
  let batch = [], size = 0
  const flush = () => {
    if (!batch.length) return
    parts.push(`${head}(${batch.join('),\n(')})\n${conflict};`)
    batch = []; size = 0
  }
  for (const r of rows) {
    if (size && size + r.length > CHUNK_BYTES) flush()
    batch.push(r); size += r.length + 3
  }
  flush()
  writeFileSync(join(OUT, `${name}.sql`), (prefix ? prefix + '\n\n' : '') + parts.join('\n\n') + '\n')
  if (prefix) writeChunk(name, prefix)
  for (const p of parts) writeChunk(name, p)
  return rows.length
}

const EV_COLS = 'id,customer_id,end_client_name,event_number,event_date,location_text,location_notes,volume_m,truck_count,notes,status_id,no_parking,porterage,supplier_pickup,custom_fields,created_at,updated_at'
const EV_UPD = 'on conflict (id) do update set customer_id=excluded.customer_id,end_client_name=excluded.end_client_name,event_number=excluded.event_number,event_date=excluded.event_date,location_text=excluded.location_text,location_notes=excluded.location_notes,volume_m=excluded.volume_m,truck_count=excluded.truck_count,notes=excluded.notes,status_id=excluded.status_id,no_parking=excluded.no_parking,porterage=excluded.porterage,supplier_pickup=excluded.supplier_pickup,custom_fields=excluded.custom_fields,updated_at=excluded.updated_at'
const TK_COLS = 'id,event_id,customer_id,task_type_id,title,task_date,onsite_start_time,warehouse_start_time,hours_count,worker_count,execution_method_id,truck_ids,truck_free_text,notes,status_id,contractor_id,location_text,performed_by'
const TK_UPD = 'on conflict (id) do update set event_id=excluded.event_id,customer_id=excluded.customer_id,task_type_id=excluded.task_type_id,title=excluded.title,task_date=excluded.task_date,onsite_start_time=excluded.onsite_start_time,warehouse_start_time=excluded.warehouse_start_time,hours_count=excluded.hours_count,worker_count=excluded.worker_count,execution_method_id=excluded.execution_method_id,truck_ids=excluded.truck_ids,truck_free_text=excluded.truck_free_text,notes=excluded.notes,contractor_id=excluded.contractor_id,location_text=excluded.location_text,performed_by=excluded.performed_by'

emit('events', EV_COLS, rowsEvent, EV_UPD)
emit('event_contacts', 'event_id,contact_name,contact_phone', rowsContact,
  'on conflict (event_id) do update set contact_name=excluded.contact_name,contact_phone=excluded.contact_phone')
emit('tasks', TK_COLS, rowsTask, TK_UPD)
emit('task_pricing', 'task_id,price,is_manual', rowsPricing,
  'on conflict (task_id) do update set price=excluded.price,is_manual=excluded.is_manual')
emit('task_contractor_terms', 'task_id,contractor_id,price,work_site', rowsTerms, 'on conflict do nothing')
emit('event_specs', 'id,event_id,version,source,url,title,created_at', rowsSpec, 'on conflict (id) do nothing')
emit('event_signatures', 'id,event_id,signer_name,signature_data,signed_by_name,created_at', rowsSign, 'on conflict (id) do nothing')

/* ליומן אין מפתח טבעי. המחיקה מכוונת לאירועים שהקובץ הזה עומד לכתוב, ולא
   לכל היומן — כדי שהרצה חוזרת לא תכפיל שורות ולא תמחק יומן של אירוע שנוצר
   באפליקציה. */
emit('event_activity', 'event_id,kind,actor_name,note,created_at', rowsActivity, '',
  `delete from event_activity where event_id in (${events.map((e) => `'${e.id}'`).join(',')});`)

const legacyRows = legacy.map((l) => [q(l.path), q(l.coll), q(l.docId), uuidLit(l.eventId), uuidLit(l.taskId), json(l.data)].join(','))
emit('legacy_firestore_docs', 'doc_path,collection,doc_id,event_id,task_id,data', legacyRows,
  'on conflict (doc_path) do update set event_id=excluded.event_id,task_id=excluded.task_id,data=excluded.data,imported_at=now()')

const stats = {
  events: rowsEvent.length, event_contacts: rowsContact.length,
  tasks: rowsTask.length, ' ├ from task docs': tasks.length, ' └ synthesized from event': synthesized,
  task_pricing: rowsPricing.length, task_contractor_terms: rowsTerms.length,
  event_activity: rowsActivity.length, event_specs: rowsSpec.length,
  event_signatures: rowsSign.length, legacy_firestore_docs: legacyRows.length,
}
console.log(JSON.stringify(stats, null, 2))
if (warn.size) console.log('\nהערות:\n' + [...warn].sort((a, b) => b[1] - a[1]).map(([k, n]) => `  ${String(n).padStart(5)}  ${k}`).join('\n'))
writeFileSync(join(OUT, '_stats.json'), JSON.stringify({ stats, warnings: Object.fromEntries(warn) }, null, 2))
writeFileSync(join(OUT, 'chunks', '_manifest.json'), JSON.stringify(chunkFiles, null, 1))
console.log(`\nchunks: ${chunkFiles.length}, largest ${Math.max(...chunkFiles.map((c) => c.bytes))} bytes`)
