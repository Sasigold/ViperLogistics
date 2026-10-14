// החצי הטהור של החשבוניות (0233) — בלי שום import של Deno, כדי ש-vitest
// יכסה אותו (אותו שיקול של `_shared/payslip.ts`).
//
// כאן: ההנחיה ל-Claude והסכמה של קריאת חשבונית, הנרמול של התשובה, ועזרי
// Gmail — שאילתת החיפוש, הקבצים המצורפים בהודעה, base64url, וחתימת ה-state
// של OAuth. המסד אינו סומך על הצורה: גם הוא מסנן כל סכום ותאריך.

/** ברירת המחדל. `INVOICE_MODEL` בסודות הפונקציה מחליף אותה. */
export const INVOICE_MODEL = 'claude-opus-5-5'

export const DOC_TYPES = ['tax_invoice', 'tax_invoice_receipt', 'receipt', 'credit', 'other'] as const
export type DocType = (typeof DOC_TYPES)[number]

export const CATEGORIES = [
  'subcontractors',
  'equipment',
  'vehicle',
  'fuel',
  'rent',
  'utilities',
  'communication',
  'software',
  'office',
  'food',
  'professional',
  'marketing',
  'insurance',
  'travel',
  'maintenance',
  'other',
] as const
export type Category = (typeof CATEGORIES)[number]

export interface InvoiceLine {
  description: string
  quantity: number | null
  unit_price: number | null
  total: number | null
}

export interface InvoiceReading {
  kind: 'invoice' | 'other'
  doc_type: DocType
  vendor_name: string | null
  vendor_tax_id: string | null
  invoice_number: string | null
  /** 'YYYY-MM-DD' */
  issue_date: string | null
  currency: string
  amount_before_vat: number | null
  vat_amount: number | null
  total_amount: number | null
  category: Category
  description: string | null
  recipient_name: string | null
  recipient_tax_id: string | null
  lines: InvoiceLine[]
  notes: string | null
}

export const INVOICE_SYSTEM = `You read a supplier document that a small Israeli company received — usually a tax invoice (חשבונית מס), a tax invoice/receipt (חשבונית מס/קבלה), a receipt (קבלה) or a credit invoice (חשבונית זיכוי) — and return its data as JSON. The document may be a PDF, a scan, or a phone photo saved as PDF; it may span several pages.

- kind: "invoice" when the document is one of the above. "other" for anything else (a quote, an order confirmation, a delivery note, a marketing email, a bank statement). For "other", fill what you can and leave amounts null.
- doc_type: tax_invoice / tax_invoice_receipt / receipt / credit / other, by the title printed on the document.
- vendor_name, vendor_tax_id: the issuer (the business that sent the invoice) and its ח.פ. / ע.מ. / עוסק מורשה number, digits only.
- recipient_name, recipient_tax_id: who the invoice was issued to (לכבוד / שם הלקוח / Bill to) and its ח.פ. / ע.מ. if printed. This decides which company the invoice belongs to, so copy it exactly as printed.
- invoice_number: the document number as printed.
- issue_date: the document date (תאריך / תאריך הפקה), as YYYY-MM-DD. Israeli dates are written day first (14/03/2026 is 14 March 2026).
- currency: ISO code, "ILS" for ₪ / ש"ח.
- amount_before_vat: the total before VAT (סה"כ לפני מע"מ / סכום חייב במע"מ plus any VAT-exempt amount).
- vat_amount: the VAT amount (מע"מ). 0 when the document states no VAT (עוסק פטור, a receipt, a foreign supplier).
- total_amount: the final total including VAT (סה"כ לתשלום / סה"כ כולל מע"מ).
  Plain numbers, no thousands separators, as printed; never compute a value that is not printed, except amount_before_vat = total_amount − vat_amount when only those two are printed. For a credit invoice return the amounts as negative numbers.
- category: what the expense is for — subcontractors (manpower, contractors), equipment (equipment purchase or rental), vehicle (vehicle leasing, repairs, parking, tolls), fuel, rent, utilities (electricity, water, municipal tax), communication (phone, internet), software (software, SaaS, hosting), office (office supplies, printing), food (food, refreshments, events catering), professional (accounting, legal, consulting), marketing (advertising), insurance, travel (flights, hotels, taxis), maintenance (repairs and cleaning of premises), other.
- description: one short Hebrew phrase saying what was bought (e.g. "דלק לרכב", "השכרת במה ותאורה").
- lines: the line items — description, quantity, unit price, line total — as printed, up to 50. Leave the list empty when the document has no itemised lines.
- notes: one short sentence about anything unclear, otherwise null.`

const num = { anyOf: [{ type: 'number' }, { type: 'null' }] }
const str = { anyOf: [{ type: 'string' }, { type: 'null' }] }

// ‏structured outputs מגביל ל-16 שדות nullable; כאן 15 (12 + 3 בשורה).
export const INVOICE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: [
    'kind',
    'doc_type',
    'vendor_name',
    'vendor_tax_id',
    'invoice_number',
    'issue_date',
    'currency',
    'amount_before_vat',
    'vat_amount',
    'total_amount',
    'category',
    'description',
    'recipient_name',
    'recipient_tax_id',
    'lines',
    'notes',
  ],
  properties: {
    kind: { type: 'string', enum: ['invoice', 'other'] },
    doc_type: { type: 'string', enum: [...DOC_TYPES] },
    vendor_name: str,
    vendor_tax_id: str,
    invoice_number: str,
    issue_date: str,
    currency: str,
    amount_before_vat: num,
    vat_amount: num,
    total_amount: num,
    category: { type: 'string', enum: [...CATEGORIES] },
    description: str,
    recipient_name: str,
    recipient_tax_id: str,
    lines: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['description', 'quantity', 'unit_price', 'total'],
        properties: {
          description: { type: 'string' },
          quantity: num,
          unit_price: num,
          total: num,
        },
      },
    },
    notes: str,
  },
} as const

const clean = (v: unknown, max: number): string | null => {
  if (typeof v !== 'string') return null
  const s = v.replace(/\s+/g, ' ').trim()
  return s ? s.slice(0, max) : null
}

/** סכום: מספר סופי בטווח של `numeric(12,2)`, מעוגל לאגורות. "1,234.50 ₪" מתקבל. */
export function money(v: unknown): number | null {
  const n = typeof v === 'string' ? Number(v.replace(/[,\s₪$€]/g, '')) : v
  if (typeof n !== 'number' || !Number.isFinite(n) || Math.abs(n) >= 1e9) return null
  return Math.round(n * 100) / 100
}

export const digits = (v: unknown): string | null => {
  const s = typeof v === 'number' ? String(v) : typeof v === 'string' ? v : ''
  const d = s.replace(/\D/g, '').slice(0, 12)
  return d.length >= 5 ? d : null
}

/** 'YYYY-MM-DD' תקין בין 2000 ל-2099; גם "14/03/2026" (יום קודם) מתקבל. */
export function isoDate(v: unknown): string | null {
  if (typeof v !== 'string') return null
  let s = v.trim()
  const il = /^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$/.exec(s)
  if (il) s = `${il[3]}-${il[2].padStart(2, '0')}-${il[1].padStart(2, '0')}`
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s)
  if (!m) return null
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])]
  const dt = new Date(Date.UTC(y, mo - 1, d))
  if (y < 2000 || y > 2099 || dt.getUTCMonth() !== mo - 1 || dt.getUTCDate() !== d) return null
  return s
}

export function normalizeInvoice(raw: unknown): InvoiceReading {
  const r = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>
  const kind = r.kind === 'other' ? 'other' : 'invoice'
  const docType = (DOC_TYPES as readonly string[]).includes(r.doc_type as string) ? (r.doc_type as DocType) : 'other'
  const category = (CATEGORIES as readonly string[]).includes(r.category as string)
    ? (r.category as Category)
    : 'other'
  const cur = typeof r.currency === 'string' ? r.currency.trim().toUpperCase() : ''
  const currency = cur === '₪' || cur === 'NIS' || cur === 'ש"ח' ? 'ILS' : /^[A-Z]{3}$/.test(cur) ? cur : 'ILS'

  let before = money(r.amount_before_vat)
  let vat = money(r.vat_amount)
  let total = money(r.total_amount)
  // זיכוי: הסכומים שליליים תמיד, גם כשהמודל החזיר אותם חיוביים
  if (docType === 'credit') {
    const neg = (n: number | null) => (n === null ? null : -Math.abs(n))
    before = neg(before)
    vat = neg(vat)
    total = neg(total)
  }
  if (before === null && total !== null && vat !== null) before = Math.round((total - vat) * 100) / 100

  const lines: InvoiceLine[] = []
  if (Array.isArray(r.lines)) {
    for (const e of r.lines as unknown[]) {
      const l = (e && typeof e === 'object' ? e : {}) as Record<string, unknown>
      const description = clean(l.description, 300)
      if (!description) continue
      lines.push({
        description,
        quantity: money(l.quantity),
        unit_price: money(l.unit_price),
        total: money(l.total),
      })
      if (lines.length >= 200) break
    }
  }

  return {
    kind,
    doc_type: docType,
    vendor_name: clean(r.vendor_name, 200),
    vendor_tax_id: digits(r.vendor_tax_id),
    invoice_number: clean(r.invoice_number, 60),
    issue_date: isoDate(r.issue_date),
    currency,
    amount_before_vat: before,
    vat_amount: vat,
    total_amount: total,
    category,
    description: clean(r.description, 300),
    recipient_name: clean(r.recipient_name, 200),
    recipient_tax_id: digits(r.recipient_tax_id),
    lines,
    notes: clean(r.notes, 300),
  }
}

/* ===== Gmail ===== */

/** כמה ימים אחורה הסריקה הראשונה מגיעה */
export const FIRST_SYNC_DAYS = 60

/**
 * שאילתת החיפוש: הודעות עם קובץ מצורף שהוא PDF או תמונה, מאז הסריקה המלאה
 * האחרונה פחות יומיים (מייל מתעכב), ובפעם הראשונה — 60 יום. `extra` היא מה
 * שהמנהל הוסיף ("from:billing@…").
 */
export function gmailQuery(extra: string, syncedUntil: string | null, now: Date): string {
  const sinceMs = syncedUntil ? Date.parse(syncedUntil) - 2 * 86_400_000 : now.getTime() - FIRST_SYNC_DAYS * 86_400_000
  const since = Math.floor((Number.isFinite(sinceMs) ? sinceMs : now.getTime() - FIRST_SYNC_DAYS * 86_400_000) / 1000)
  const parts = [
    'has:attachment',
    '(filename:pdf OR filename:jpg OR filename:jpeg OR filename:png)',
    `after:${since}`,
    '-in:chats',
  ]
  const x = extra.replace(/[\r\n]+/g, ' ').trim()
  if (x) parts.push(`(${x})`)
  return parts.join(' ')
}

export interface GmailPart {
  partId?: string
  mimeType?: string
  filename?: string
  headers?: { name: string; value: string }[]
  body?: { attachmentId?: string; size?: number; data?: string }
  parts?: GmailPart[]
}

export interface Attachment {
  partId: string
  filename: string
  mimeType: 'application/pdf' | 'image/jpeg' | 'image/png'
  attachmentId: string | null
  data: string | null
  size: number
}

/** מתחת לזה — לוגו או חתימה, לא חשבונית */
const MIN_IMAGE_BYTES = 30_000
export const MAX_ATTACHMENT_BYTES = 14 * 1024 * 1024

function attachmentType(p: GmailPart): Attachment['mimeType'] | null {
  const mime = (p.mimeType ?? '').toLowerCase()
  const name = (p.filename ?? '').toLowerCase()
  if (mime === 'application/pdf' || name.endsWith('.pdf')) return 'application/pdf'
  if (mime === 'image/png' || name.endsWith('.png')) return 'image/png'
  if (mime === 'image/jpeg' || mime === 'image/jpg' || /\.jpe?g$/.test(name)) return 'image/jpeg'
  return null
}

/** הקבצים המצורפים שאפשר שיהיו חשבונית: PDF, ותמונות שאינן זעירות. */
export function findAttachments(payload: GmailPart | undefined): Attachment[] {
  const out: Attachment[] = []
  const walk = (p: GmailPart | undefined) => {
    if (!p) return
    const type = p.filename ? attachmentType(p) : null
    const size = p.body?.size ?? 0
    if (type && (p.body?.attachmentId || p.body?.data) && size <= MAX_ATTACHMENT_BYTES) {
      if (type === 'application/pdf' || size >= MIN_IMAGE_BYTES) {
        out.push({
          partId: p.partId ?? String(out.length),
          filename: p.filename!,
          mimeType: type,
          attachmentId: p.body?.attachmentId ?? null,
          data: p.body?.data ?? null,
          size,
        })
      }
    }
    for (const c of p.parts ?? []) walk(c)
  }
  walk(payload)
  return out
}

export function header(payload: GmailPart | undefined, name: string): string | null {
  const h = payload?.headers?.find((x) => x.name.toLowerCase() === name.toLowerCase())
  return h?.value ?? null
}

export function base64UrlToBytes(s: string): Uint8Array {
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/')
  const pad = b64.length % 4 === 0 ? '' : '='.repeat(4 - (b64.length % 4))
  const bin = atob(b64 + pad)
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}

export function bytesToBase64Url(bytes: Uint8Array): string {
  let bin = ''
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', bytes as BufferSource)
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

/* ===== OAuth state ===== */

export interface OAuthState {
  /** הפרופיל שהתחיל את החיבור */
  p: string
  /** לאן לחזור אחרי ההסכמה */
  r: string
  /** תפוגה, ms */
  e: number
}

async function hmac(secret: string, data: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  return bytesToBase64Url(new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data))))
}

export async function signState(s: OAuthState, secret: string): Promise<string> {
  const body = bytesToBase64Url(new TextEncoder().encode(JSON.stringify(s)))
  return `${body}.${await hmac(secret, body)}`
}

/** ה-state אם החתימה נכונה ולא פג תוקפו; אחרת null. */
export async function verifyState(token: string, secret: string, now: number): Promise<OAuthState | null> {
  const [body, sig] = token.split('.')
  if (!body || !sig) return null
  const expected = await hmac(secret, body)
  if (expected.length !== sig.length) return null
  let diff = 0
  for (let i = 0; i < sig.length; i++) diff |= sig.charCodeAt(i) ^ expected.charCodeAt(i)
  if (diff !== 0) return null
  try {
    const s = JSON.parse(new TextDecoder().decode(base64UrlToBytes(body))) as OAuthState
    if (typeof s.p !== 'string' || typeof s.r !== 'string' || typeof s.e !== 'number' || s.e < now) return null
    return s
  } catch {
    return null
  }
}

/** כתובת חזרה מותרת: https (או localhost לפיתוח), בלי פרטי התחברות. */
export function safeReturnUrl(v: unknown): string | null {
  if (typeof v !== 'string' || v.length > 500) return null
  try {
    const u = new URL(v)
    const local = u.hostname === 'localhost' || u.hostname === '127.0.0.1'
    if (u.protocol !== 'https:' && !(local && u.protocol === 'http:')) return null
    if (u.username || u.password) return null
    return u.toString()
  } catch {
    return null
  }
}
