import { readFileSync, writeFileSync } from 'node:fs'
import { fields, docPath } from '/home/user/ViperLogistics/scripts/firestore-migration/lib.mjs'
const urls = []
for (const f of ['achaotMechir.json','caesar.json','eventsCdesign.json']) {
  for (const d of JSON.parse(readFileSync(`fb/${f}`,'utf8'))) {
    const x = fields(d)
    if (x.sign?.sign && /^https?:\/\//.test(String(x.sign.sign))) urls.push({ path: docPath(d), url: x.sign.sign })
  }
}
console.log('signatures:', urls.length)
const out = {}
let ok = 0, fail = 0
for (const u of urls) {
  try {
    const r = await fetch(u.url)
    if (!r.ok) { fail++; console.error(`  ${r.status} ${u.path}`); continue }
    const type = (r.headers.get('content-type') ?? 'image/png').split(';')[0]
    const buf = Buffer.from(await r.arrayBuffer())
    const mime = /png|jpeg|webp/.test(type) ? type.replace('image/jpg','image/jpeg') : 'image/png'
    out[u.path] = `data:${mime};base64,${buf.toString('base64')}`
    ok++
  } catch (e) { fail++; console.error(`  ERR ${u.path}: ${e.message}`) }
}
writeFileSync('signatures.json', JSON.stringify(out))
const sizes = Object.values(out).map(v => v.length)
console.log(`ok=${ok} fail=${fail}  max=${Math.max(...sizes,0)} bytes  total=${(sizes.reduce((a,b)=>a+b,0)/1e6).toFixed(2)}MB`)
