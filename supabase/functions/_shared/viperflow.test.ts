import { describe, expect, it } from 'vitest'
import {
  MONEY_KEYS,
  catalogIds,
  connectionIdFromPath,
  hexToBytes,
  redactMoney,
  specLinesFromOrder,
  specLogisticsQuantity,
  specParents,
  timestampAcceptable,
  timingSafeEqual,
  verifySignature,
  withCatalog,
} from './viperflow'

/**
 * מה שבודקים כאן הוא שהמנעול והמפתח מאותה סדרה.
 *
 * ‏`viperflowSign` למטה אינו קריאה לקוד שלנו אלא **מימוש עצמאי של האלגוריתם
 * של ViperFlow**, כפי שהוא כתוב ב-`_shared/integrations/signature.ts` אצלם
 * וב-`docs/WEBHOOKS.md` §5: ‏`` `${ts}.${body}` ``, המפתח הוא כל מחרוזת הסוד
 * כולל התחילית `whsec_`, והפלט הוא hex באותיות קטנות. אם מישהו "ישפר" את
 * הקולט שלנו — יקצץ את התחילית, יחתום על ה-JSON המפורסר מחדש, יעבור ל-base64
 * — הבדיקה הזו תיפול, וזה כל תפקידה. חתימה שגויה אינה אינטגרציה מדרדרת אלא
 * אינטגרציה שאינה קיימת: כל משלוח נכשל, ואחרי עשרה ViperFlow מכבה את נקודת
 * הקצה.
 */
async function viperflowSign(secret: string, timestamp: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${timestamp}.${body}`))
  return Array.from(new Uint8Array(mac))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

const SECRET = 'whsec_abcdefghijklmnopqrstuvwxyz0123456789ABCD'
const OLD_SECRET = 'whsec_9876543210ZYXWVUTSRQPONMLKJIHGFEDCBAzyxw'
const TS = '1789459923'
/** מעטפה אמיתית בצורתה: מפתחות עליונים בסדר קבוע, בלי רווחים. */
const BODY =
  '{"id":"evt_9b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e","type":"order.updated","created_at":"2026-09-15T08:12:03.417Z","api_version":"v1","livemode":true,"origin":{"source":"app"},"data":{"id":"a3e1b2c4-5d6f-4a7b-8c9d-0e1f2a3b4c5d","object":"order","order_number":"ORD-2026-0412"},"previous":null}'

describe('אימות החתימה', () => {
  it('מקבל חתימה שנוצרה באלגוריתם של ViperFlow', async () => {
    const header = `v1=${await viperflowSign(SECRET, TS, BODY)}`
    expect(await verifySignature([SECRET], header, TS, BODY)).toBe(true)
  })

  it('התחילית whsec_ היא חלק מהמפתח ואינה נחתכת', async () => {
    const stripped = SECRET.slice('whsec_'.length)
    const header = `v1=${await viperflowSign(stripped, TS, BODY)}`
    expect(await verifySignature([SECRET], header, TS, BODY)).toBe(false)
  })

  it('החתימה היא על הבייטים שהתקבלו ולא על ה-JSON שהם מתארים', async () => {
    const header = `v1=${await viperflowSign(SECRET, TS, BODY)}`
    // אותו ערך בדיוק, בייטים אחרים. זה מה שקורה למי שמפרסר ואז חותם על מה
    // שהוא בנה מחדש — ‏`await req.json()` במקום `await req.text()`.
    const reserialised = JSON.stringify(JSON.parse(BODY), null, 2)
    expect(JSON.parse(reserialised)).toEqual(JSON.parse(BODY))
    expect(reserialised).not.toBe(BODY)
    expect(await verifySignature([SECRET], header, TS, reserialised)).toBe(false)
  })

  it('חתימה על חותמת זמן אחרת אינה מתקבלת', async () => {
    const header = `v1=${await viperflowSign(SECRET, '1789459000', BODY)}`
    expect(await verifySignature([SECRET], header, TS, BODY)).toBe(false)
  })

  it('גוף ששונה בתו אחד נדחה', async () => {
    const header = `v1=${await viperflowSign(SECRET, TS, BODY)}`
    const tampered = BODY.replace('"quantity"', '"quantity "').replace('ORD-2026-0412', 'ORD-2026-0413')
    expect(await verifySignature([SECRET], header, TS, tampered)).toBe(false)
  })

  describe('החלפת סוד — 24 שעות שבהן שתי חתימות תקפות', () => {
    it('הסוד החדש מתקבל כשהוא הראשון בכותרת', async () => {
      const header = `v1=${await viperflowSign(SECRET, TS, BODY)},v1=${await viperflowSign(OLD_SECRET, TS, BODY)}`
      expect(await verifySignature([SECRET], header, TS, BODY)).toBe(true)
    })

    it('והישן מתקבל כשהוא השני — הקולט אינו מניח סדר', async () => {
      const header = `v1=${await viperflowSign(SECRET, TS, BODY)},v1=${await viperflowSign(OLD_SECRET, TS, BODY)}`
      expect(await verifySignature([OLD_SECRET], header, TS, BODY)).toBe(true)
    })

    it('ושני סודות מוגדרים אצלנו מקבלים כל אחת מהשתיים', async () => {
      const onlyOld = `v1=${await viperflowSign(OLD_SECRET, TS, BODY)}`
      expect(await verifySignature([SECRET, OLD_SECRET], onlyOld, TS, BODY)).toBe(true)
    })

    it('סוד שלישי שאיש לא הגדיר עדיין נדחה', async () => {
      const header = `v1=${await viperflowSign('whsec_zzzz', TS, BODY)}`
      expect(await verifySignature([SECRET, OLD_SECRET], header, TS, BODY)).toBe(false)
    })
  })

  it('כותרת בלי v1=, ריקה או פגומה נדחית', async () => {
    for (const header of ['', 'sha256=abc', 'v1=', 'v1=zz', 'v1=abc']) {
      expect(await verifySignature([SECRET], header, TS, BODY)).toBe(false)
    }
  })

  it('רווחים סביב הפריטים אינם שוברים את הפיצול', async () => {
    const header = ` v1=${await viperflowSign(SECRET, TS, BODY)} , v1=deadbeef `
    expect(await verifySignature([SECRET], header, TS, BODY)).toBe(true)
  })

  it('בלי סוד מוגדר אצלנו אין חתימה שמתקבלת', async () => {
    const header = `v1=${await viperflowSign(SECRET, TS, BODY)}`
    expect(await verifySignature([], header, TS, BODY)).toBe(false)
  })
})

describe('חלון החזרה', () => {
  const now = Number(TS) * 1000

  it('חותמת עכשווית מתקבלת', () => {
    expect(timestampAcceptable(TS, now)).toBe(true)
  })

  it('חמש דקות לשני הכיוונים עדיין בפנים', () => {
    expect(timestampAcceptable(String(Number(TS) - 300), now)).toBe(true)
    expect(timestampAcceptable(String(Number(TS) + 300), now)).toBe(true)
  })

  it('ומעבר להן — בחוץ', () => {
    expect(timestampAcceptable(String(Number(TS) - 301), now)).toBe(false)
    expect(timestampAcceptable(String(Number(TS) + 301), now)).toBe(false)
  })

  it('חותמת שאינה מספר שלם נדחית', () => {
    for (const bad of ['', 'abc', '17894599.23', '-1789459923', '17894599231234']) {
      expect(timestampAcceptable(bad, now)).toBe(false)
    }
  })
})

describe('ניקוי הכסף', () => {
  const envelope = {
    id: 'evt_x',
    data: {
      id: 'order-1',
      order_number: 'ORD-1',
      currency: 'ILS',
      totals: { grand_total: 4248, subtotal: 3600, order_discount_percent: 10 },
      payment: { status: 'unpaid', balance_due: 4248 },
      items: [
        { name: 'שולחן', line_type: 'product', quantity: 10, unit_price: 120, line_total: 1200, discount_percent: 0 },
        { name: 'כיסא', line_type: 'product', quantity: 100, unit_price: 12, line_total: 1200, discount_percent: 5 },
      ],
    },
  }

  it('לא נשאר סכום ברמת ההזמנה, ולא מחיר יחידה על שורת ריהוט', () => {
    const clean = JSON.stringify(redactMoney(envelope))
    for (const key of MONEY_KEYS) {
      // ‏0190: `line_total` הוא החריג — הוא מה שמפצל את הכנסת הריהוט.
      // ‏0192: ‏`order_discount_percent` הוא השני, ו-`totals` שורד כמעטפת
      // שלו בלבד — מה שנשאר בתוכו נבדק בשורה שאחרי הלולאה.
      if (key === 'line_total' || key === 'order_discount_percent' || key === 'totals') continue
      expect(clean).not.toContain(`"${key}"`)
    }
    expect((redactMoney(envelope) as { data: { totals: unknown } }).data.totals)
      .toEqual({ order_discount_percent: 10 })
  })

  it('ומה שאינו כסף נשאר כפי שהוא, ועמו אחוז ההנחה בלבד', () => {
    expect(redactMoney(envelope)).toEqual({
      id: 'evt_x',
      data: {
        id: 'order-1',
        order_number: 'ORD-1',
        totals: { order_discount_percent: 10 },
        items: [
          { name: 'שולחן', line_type: 'product', quantity: 10, line_total: 1200 },
          { name: 'כיסא', line_type: 'product', quantity: 100, line_total: 1200 },
        ],
      },
    })
  })

  /* ‏0190: סכום השורה עובר על כל שורה — הוא ההכנסה — ומחיר היחידה רק על
     לוגיסטיקה. אובייקט שאינו שורה אינו מקבל כלום. */
  it('סכום שורה עובר גם על ריהוט, ומחיר יחידה לא', () => {
    const line = { line_type: 'product', quantity: 3, unit_price: 120, line_total: 360, discount_percent: 5 }
    expect(redactMoney(line)).toEqual({ line_type: 'product', quantity: 3, line_total: 360 })
  })

  it('ואובייקט בלי line_type אינו שורה, ואינו שומר דבר', () => {
    expect(redactMoney({ name: 'x', line_total: 999, unit_price: 5 })).toEqual({ name: 'x' })
  })

  /* ‏0187: שורת לוגיסטיקה היא מה שאנחנו עושים, והסכום שלה הוא מחיר ההקמה
     והפירוק. שתי עמודות בלבד עוברות, ורק עליה. */
  it('שורת הובלה וסידור שומרות את הסכום שלהן', () => {
    const items = [
      { name: 'הובלה', line_type: 'truck', quantity: 1, unit_price: 2400, line_total: 2400, discount_percent: 0 },
      { name: 'סידור ואיסוף', line_type: 'worker', quantity: 2, unit_price: 1500, line_total: 3000 },
    ]
    expect(redactMoney(items)).toEqual([
      { name: 'הובלה', line_type: 'truck', quantity: 1, unit_price: 2400, line_total: 2400 },
      { name: 'סידור ואיסוף', line_type: 'worker', quantity: 2, unit_price: 1500, line_total: 3000 },
    ])
  })

  it('והחריג אינו נדבק: סכום ההזמנה נמחק גם כשההזמנה עצמה נושאת line_type', () => {
    const order = {
      line_type: 'truck',
      line_total: 2400,
      totals: { grand_total: 4248 },
      payment: { balance_due: 4248 },
      grand_total: 4248,
      currency: 'ILS',
    }
    expect(redactMoney(order)).toEqual({ line_type: 'truck', line_total: 2400 })
  })

  it('ורכיב בתוך שורת לוגיסטיקה אינו יורש את החריג', () => {
    const line = {
      line_type: 'truck',
      line_total: 2400,
      meta: { unit_price: 99, note: 'x' },
    }
    expect(redactMoney(line)).toEqual({
      line_type: 'truck',
      line_total: 2400,
      meta: { note: 'x' },
    })
  })

  /* ‏0192: ‏`totals` אינו נמחק אלא מצטמצם. הנימוק הוא כסף אמיתי: בלי אחוז
     ההנחה של ההזמנה, ההכנסה שנכתבת היא המחירון ולא מה שהלקוח משלם. */
  it('אחוז ההנחה של ההזמנה שורד, ושורת התחתית של ההזמנה לא', () => {
    const order = {
      id: 'o1',
      totals: {
        subtotal: 3600,
        total_discount: 400,
        taxable_amount: 3200,
        vat_amount: 544,
        grand_total: 3744,
        order_discount_percent: 12.5,
      },
    }
    expect(redactMoney(order)).toEqual({ id: 'o1', totals: { order_discount_percent: 12.5 } })
  })

  it('ו-totals בלי הנחה נעלם כולו, כמו לפני 0192', () => {
    expect(redactMoney({ id: 'o1', totals: { grand_total: 10 } })).toEqual({ id: 'o1' })
    expect(redactMoney({ id: 'o1', totals: {} })).toEqual({ id: 'o1' })
  })

  it('והחריג אינו חל על שורה שנושאת totals משלה', () => {
    const line = { line_type: 'product', line_total: 100, totals: { grand_total: 9 } }
    expect(redactMoney(line)).toEqual({ line_type: 'product', line_total: 100 })
  })

  it('מערך שומר על האורך ועל הסדר — המיקום הוא חוזה', () => {
    const items = [{ a: 1, unit_price: 5 }, { b: 2 }, { c: 3, totals: {} }]
    expect(redactMoney(items)).toEqual([{ a: 1 }, { b: 2 }, { c: 3 }])
  })

  it('null וערכים פרימיטיביים עוברים בשלום', () => {
    expect(redactMoney(null)).toBe(null)
    expect(redactMoney({ previous: null, n: 0, s: '', b: false })).toEqual({
      previous: null,
      n: 0,
      s: '',
      b: false,
    })
  })
})

describe('הקטלוג: חדש או ישן (0190)', () => {
  const items = [
    { line_type: 'product', is_component: false, product_id: 'aaaaaaaa-1111-2222-3333-444444444444', name: 'כיסא' },
    { line_type: 'product', is_component: true, product_id: 'bbbbbbbb-1111-2222-3333-444444444444', name: 'רכיב' },
    { line_type: 'product', is_component: false, product_id: null, name: 'פריט חופשי' },
    { line_type: 'truck', is_component: false, name: 'הובלה' },
  ]

  it('נשאלים רק מוצרי אב, פעם אחת לכל מוצר', () => {
    expect(catalogIds([...items, items[0]])).toEqual(['aaaaaaaa-1111-2222-3333-444444444444'])
  })

  it('מזהה שאינו uuid אינו נשאל — הצד השני עונה עליו 400', () => {
    expect(catalogIds([{ line_type: 'product', product_id: 'לא-uuid' }])).toEqual([])
  })

  it('כל שורת ריהוט מסומנת, ומה שאינו חדש הוא ישן', () => {
    const catalog = new Map([
      ['aaaaaaaa-1111-2222-3333-444444444444', { is_new: true, image_url: null }],
    ])
    const out = withCatalog({ items }, catalog) as { catalog_enriched: boolean; items: { is_new?: boolean }[] }
    expect(out.catalog_enriched).toBe(true)
    expect(out.items.map((i) => i.is_new)).toEqual([true, false, false, undefined])
  })

  it('ובלי קטלוג — אין דגל, ואין סימון', () => {
    const out = withCatalog({ items }, null) as { catalog_enriched?: boolean }
    expect(out.catalog_enriched).toBeUndefined()
    expect(out).toEqual({ items })
  })

  it('הזמנה בלי שורות אינה נופלת', () => {
    expect(withCatalog({ id: 'x' }, new Map())).toEqual({ id: 'x' })
  })
})

describe('המפרט שנמשך חי (0187)', () => {
  /* כפי ש-`dto_order` אצלם מחזיר: אב, הרכיבים שלו מיד אחריו, ואז הלוגיסטיקה. */
  const items = [
    {
      id: 'i1',
      line_type: 'product',
      is_component: false,
      product_id: 'p1',
      name: 'כיסא ניו דלהי',
      quantity: 71,
      spare_quantity: 2,
      unit_price: 110,
      line_total: 7810,
      options: [{ group_name: 'צבע', value: 'ירוק' }],
    },
    {
      id: 'i2',
      parent_item_id: 'i1',
      line_type: 'product',
      is_component: true,
      product_id: 'p2',
      name: 'בסיס כיסא ניו דלהי',
      quantity: 71,
    },
    {
      id: 'i3',
      line_type: 'product',
      is_component: false,
      product_id: null,
      name: '  ',
      quantity: 4,
      is_custom: true,
      notes: 'לבן בלבד',
    },
    { id: 'i4', line_type: 'worker', is_component: false, name: 'סידור ואיסוף', quantity: 2 },
    { id: 'i5', line_type: 'truck', is_component: false, name: 'הובלה', quantity: 1 },
  ]

  it('שורות האב בלבד — בלי בנים ובלי לוגיסטיקה', () => {
    expect(specParents(items).map((i) => i.id)).toEqual(['i1', 'i3'])
  })

  it('התמונה מגיעה מהקטלוג לפי המוצר, ופריט בלי מוצר נשאר בלעדיה', () => {
    const lines = specLinesFromOrder(
      items,
      new Map([['p1', { is_new: false, image_url: 'https://cdn/x.webp' }]]),
    )
    expect(lines.map((l) => l.image_url)).toEqual(['https://cdn/x.webp', null])
  })

  it('ובלי קטלוג — רשימה בלי תמונות, ולא נפילה', () => {
    expect(specLinesFromOrder(items, null).every((l) => l.image_url === null)).toBe(true)
  })

  it('והשורה נבנית שדה-שדה: כסף אינו מועתק אליה', () => {
    const [line] = specLinesFromOrder(items, new Map())
    expect(Object.keys(line).sort()).toEqual([
      'id',
      'image_url',
      'is_custom',
      'name',
      'notes',
      'options',
      'quantity',
      'spare_quantity',
    ])
    expect(JSON.stringify(line)).not.toContain('7810')
  })

  it('הבחירה נקראת כטקסט, ושם ריק נופל לברירת מחדל', () => {
    const lines = specLinesFromOrder(items, new Map())
    expect(lines[0].options).toEqual(['צבע: ירוק'])
    expect(lines[1].name).toBe('פריט')
    expect(lines[1].is_custom).toBe(true)
  })

  it('הלוגיסטיקה נספרת בנפרד, ואפס אינו הזמנה', () => {
    expect(specLogisticsQuantity(items, 'truck')).toBe(1)
    expect(specLogisticsQuantity(items, 'worker')).toBe(2)
    expect(specLogisticsQuantity([{ line_type: 'truck', quantity: 0 }], 'truck')).toBeNull()
  })
})

describe('עזר', () => {
  it('hexToBytes דוחה אורך אי-זוגי ותווים שאינם hex', () => {
    expect(hexToBytes('abc')).toBeNull()
    expect(hexToBytes('zz')).toBeNull()
    expect(hexToBytes('')).toBeNull()
    expect(hexToBytes('00ff')).toEqual(new Uint8Array([0, 255]))
  })

  it('timingSafeEqual משווה גם אורך', () => {
    expect(timingSafeEqual(new Uint8Array([1, 2]), new Uint8Array([1, 2]))).toBe(true)
    expect(timingSafeEqual(new Uint8Array([1, 2]), new Uint8Array([1, 3]))).toBe(false)
    expect(timingSafeEqual(new Uint8Array([1, 2]), new Uint8Array([1, 2, 0]))).toBe(false)
  })

  it('מזהה החיבור נקרא מסוף הנתיב, ורק כשהוא uuid', () => {
    expect(
      connectionIdFromPath('https://x.supabase.co/functions/v1/viperflow-webhook/AB1C2D3E-4F5A-4B6C-8D7E-9F0A1B2C3D4E'),
    ).toBe('ab1c2d3e-4f5a-4b6c-8d7e-9f0a1b2c3d4e')
    expect(connectionIdFromPath('https://x.supabase.co/functions/v1/viperflow-webhook')).toBeNull()
    expect(connectionIdFromPath('https://x.supabase.co/functions/v1/viperflow-webhook/')).toBeNull()
    expect(connectionIdFromPath('https://x.supabase.co/functions/v1/viperflow-webhook/abc')).toBeNull()
  })
})
