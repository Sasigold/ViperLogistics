import { describe, expect, it } from 'vitest'
import {
  MONEY_KEYS,
  connectionIdFromPath,
  hexToBytes,
  redactMoney,
  timestampAcceptable,
  timingSafeEqual,
  verifySignature,
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
      totals: { grand_total: 4248, subtotal: 3600 },
      payment: { status: 'unpaid', balance_due: 4248 },
      items: [
        { name: 'שולחן', quantity: 10, unit_price: 120, line_total: 1200, discount_percent: 0 },
        { name: 'כיסא', quantity: 100, unit_price: 12, line_total: 1200, discount_percent: 5 },
      ],
    },
  }

  it('לא נשאר בשום מקום שדה כספי', () => {
    const clean = JSON.stringify(redactMoney(envelope))
    for (const key of MONEY_KEYS) {
      expect(clean).not.toContain(`"${key}"`)
    }
  })

  it('ומה שאינו כסף נשאר כפי שהוא', () => {
    expect(redactMoney(envelope)).toEqual({
      id: 'evt_x',
      data: {
        id: 'order-1',
        order_number: 'ORD-1',
        items: [
          { name: 'שולחן', quantity: 10 },
          { name: 'כיסא', quantity: 100 },
        ],
      },
    })
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
