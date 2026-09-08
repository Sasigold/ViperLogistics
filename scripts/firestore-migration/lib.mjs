/**
 * העזרים המשותפים להעברה מ-Firestore: פירוק מבנה ה-Values, זמן ישראל,
 * ו-UUID דטרמיניסטי.
 */
import { createHash } from 'node:crypto'

/** מבנה ה-Values של Firestore → JSON רגיל. */
export function un(v) {
  if (v == null) return null
  const k = Object.keys(v)[0]
  switch (k) {
    case 'nullValue': return null
    case 'booleanValue': return v.booleanValue
    case 'stringValue': return v.stringValue
    case 'timestampValue': return v.timestampValue
    case 'integerValue': return Number(v.integerValue)
    case 'doubleValue': return v.doubleValue
    case 'bytesValue': return v.bytesValue
    case 'geoPointValue': return v.geoPointValue
    case 'referenceValue': return v.referenceValue.replace(/^projects\/[^/]+\/databases\/\([^)]+\)\/documents\//, '')
    case 'arrayValue': return (v.arrayValue.values ?? []).map(un)
    case 'mapValue': return Object.fromEntries(Object.entries(v.mapValue.fields ?? {}).map(([a, b]) => [a, un(b)]))
    default: return null
  }
}

/** המסמך כולו, בלי העטיפה. */
export const fields = (doc) => Object.fromEntries(Object.entries(doc.fields ?? {}).map(([k, v]) => [k, un(v)]))

/** הנתיב היחסי של המסמך, למשל achaotMechir/abc/mesimotArco/def. */
export const docPath = (doc) => doc.name.split('/documents/')[1]

/*
 * כל חותמות הזמן ב-Firestore הן UTC, והמערכת הישנה כתבה אותן משעון ישראל:
 * `date` של אירוע הוא 21:00Z או 22:00Z — חצות בישראל, לפי שעון קיץ. חיתוך
 * ‏ISO ב-'T' היה מזיז חצי מהאירועים יום אחורה, ולכן ההמרה עוברת דרך
 * Intl עם אזור הזמן המפורש.
 */
const IL = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Jerusalem', hourCycle: 'h23',
  year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', second: '2-digit',
})
function ilParts(ts) {
  if (!ts) return null
  const d = new Date(ts)
  if (Number.isNaN(d.getTime())) return null
  const p = Object.fromEntries(IL.formatToParts(d).map((x) => [x.type, x.value]))
  return { date: `${p.year}-${p.month}-${p.day}`, time: `${p.hour}:${p.minute}:${p.second}` }
}
export const ilDate = (ts) => ilParts(ts)?.date ?? null
export const ilTime = (ts) => ilParts(ts)?.time ?? null

/*
 * UUIDv5 על נתיב המסמך ב-Firestore. הזהות של שורה בסופאבייס נגזרת מהמקור
 * ולא מוגרלת, ולכן הרצה חוזרת של הייבוא פוגעת באותן שורות בדיוק — וזה מה
 * שהופך את כל התהליך לניתן להרצה מחדש אחרי תיקון מיפוי.
 */
const NS = 'a4f1c0de-7b2e-5a91-9d3c-000000000001'
export function uuid5(name) {
  const nsBytes = Buffer.from(NS.replace(/-/g, ''), 'hex')
  const h = createHash('sha1').update(Buffer.concat([nsBytes, Buffer.from(name, 'utf8')])).digest()
  h[6] = (h[6] & 0x0f) | 0x50
  h[8] = (h[8] & 0x3f) | 0x80
  const s = h.subarray(0, 16).toString('hex')
  return `${s.slice(0, 8)}-${s.slice(8, 12)}-${s.slice(12, 16)}-${s.slice(16, 20)}-${s.slice(20, 32)}`
}

/* ── ליטרלים ל-SQL ─────────────────────────────────────────────────────── */
export const q = (v) => (v == null || v === '' ? 'null' : `'${String(v).replace(/'/g, "''")}'`)
export const num = (v) => (v == null || v === '' || Number.isNaN(Number(v)) ? 'null' : String(Number(v)))
export const bool = (v) => (v ? 'true' : 'false')
export const json = (o) => `'${JSON.stringify(o).replace(/'/g, "''")}'::jsonb`
export const uuidLit = (v) => (v ? `'${v}'::uuid` : 'null')
export const uuidArr = (a) => (a?.length ? `array[${a.map((x) => `'${x}'`).join(',')}]::uuid[]` : `'{}'::uuid[]`)

/** מנקה רווחים כפולים וקצוות; מחזיר null למחרוזת ריקה. */
export const txt = (v) => {
  if (v == null) return null
  const s = String(v).replace(/ /g, ' ').trim()
  return s === '' ? null : s
}
