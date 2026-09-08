/**
 * שואב את המסמכים מ-Firestore אל תיקיית dump.
 *
 *   node fetch.mjs ./dump
 *
 * הקריאה היא ב-REST ולא ב-Admin SDK, כי אין כאן מפתח Service Account:
 * חוקי האבטחה נפתחו זמנית לקריאה בזמן ההעברה. מכאן גם ששאילתת
 * ‏`listCollectionIds` אינה זמינה (היא פעולת אדמין), ושמות תתי-הקולקציות
 * ידועים מראש — הם נגזרו מה-`referenceValue` שמופיע על מסמכי האירוע.
 */
import { writeFileSync, mkdirSync } from 'node:fs'
import { join } from 'node:path'

const PROJECT = process.env.FIRESTORE_PROJECT ?? 'nihol-mishmarot'
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`
const OUT = process.argv[2] ?? 'dump'
mkdirSync(OUT, { recursive: true })

async function getAll(path) {
  const out = []
  let token = null
  do {
    const r = await fetch(`${BASE}/${path}?pageSize=300${token ? `&pageToken=${token}` : ''}`)
    if (!r.ok) throw new Error(`${path}: ${r.status} ${await r.text()}`)
    const j = await r.json()
    out.push(...(j.documents ?? []))
    token = j.nextPageToken
  } while (token)
  return out
}

/** שאילתת collection-group: מביאה את כל תתי-הקולקציות בשם אחד, בלי לעבור מסמך-מסמך. */
async function group(collectionId) {
  const out = []
  let cursor = null
  for (;;) {
    const structuredQuery = {
      from: [{ collectionId, allDescendants: true }],
      orderBy: [{ field: { fieldPath: '__name__' }, direction: 'ASCENDING' }],
      limit: 300,
      ...(cursor ? { startAt: { values: [{ referenceValue: cursor }], before: false } } : {}),
    }
    const r = await fetch(`${BASE}:runQuery`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ structuredQuery }),
    })
    if (!r.ok) throw new Error(`${collectionId}: ${r.status} ${await r.text()}`)
    const rows = (await r.json()).filter((x) => x.document).map((x) => x.document)
    out.push(...rows)
    if (rows.length < 300) return out
    cursor = rows.at(-1).name
  }
}

const report = {}
for (const c of ['achaotMechir', 'caesar', 'eventsCdesign', 'mesimot']) {
  const docs = await getAll(c)
  writeFileSync(join(OUT, `${c}.json`), JSON.stringify(docs, null, 1))
  report[c] = docs.length
}
for (const c of ['mesimotArco', 'mesimotC', 'mesimotCaesar', 'mesimot']) {
  const docs = await group(c)
  /* 'mesimot' קיימת גם כקולקציה ראשית וגם כתת-קולקציה ישנה; כאן רק המקוננת. */
  const rows = c === 'mesimot' ? docs.filter((d) => d.name.split('/documents/')[1].split('/').length > 2) : docs
  writeFileSync(join(OUT, `grp_${c}.json`), JSON.stringify(rows, null, 1))
  report[`grp_${c}`] = rows.length
}
console.log(JSON.stringify(report, null, 2))
