import { writeFileSync } from 'node:fs'
const B = 'https://firestore.googleapis.com/v1/projects/nihol-mishmarot/databases/(default)/documents'
const WORKERS = {
  'tbLD3RsfFnaAzSTJdevmCDiwGLW2': 'שמעון באך',
  'EboFsS1bAXhv5Sz0QfUx72rh7HQ2': 'אביתר עמדי',
  'JKYhtHAioBfoJvqr5J9QB3UdSWq1': 'שלומי אברמס',
  '8bq9XTRnYTTUVFdOIrNmLg8G5mn1': 'איציק אספיס',
  'V8auoF4mQUhuX0i3WzGKBJKsLuV2': 'אבי מיארה',
  'pRBsLtSym3WDs04fE3ti0RHncS53': 'מוחי אבו קמאל',
  'XpZ5QOKnYBVbRMeNm9KiZ0yM8eu2': 'מחמוד (בלי שם משפחה)',
  'Y2Q9x6k2cHZwHH3gsEU0G7qSoYI2': 'אברהיים מנסה',
  'FVlaqqJUZPWpi2lM7BsPFvKGYxc2': 'וואניס מנסה',
}
const all = {}
for (const [uid, name] of Object.entries(WORKERS)) {
  const out = []
  let token = null
  do {
    const r = await fetch(`${B}/users/${uid}/record?pageSize=300${token ? `&pageToken=${token}` : ''}`)
    if (!r.ok) { console.error(`${name}: ${r.status}`); break }
    const j = await r.json()
    out.push(...(j.documents ?? []))
    token = j.nextPageToken
  } while (token)
  all[uid] = out
  console.log(`${name.padEnd(24)} ${uid}  →  ${out.length} רשומות`)
}
writeFileSync('fb/records.json', JSON.stringify(all, null, 1))
console.log('\nסה״כ:', Object.values(all).reduce((a,b)=>a+b.length,0))
