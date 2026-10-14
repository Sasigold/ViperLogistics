// קריאת חשבונית אחת ב-Claude (0233) — משותף ל-`invoice-read` ול-`invoice-gmail`.
// החצי הטהור (ההנחיה, הסכמה, הנרמול) ב-`invoice.ts`; כאן רק הקריאה לשירות,
// והפיכת תמונה מצורפת ל-PDF (pdf-lib, כמו בדפדפן).

import Anthropic from 'npm:@anthropic-ai/sdk@0.129.0'
import { PDFDocument } from 'npm:pdf-lib@1.17.1'
import { INVOICE_MODEL, INVOICE_SCHEMA, INVOICE_SYSTEM, normalizeInvoice } from './invoice.ts'
import type { InvoiceReading } from './invoice.ts'
import { bytesToBase64 } from './payslip.ts'

export function invoiceClient(apiKey: string) {
  // בלי streaming, עם גבול זמן: חשבונית היא תשובה קצרה, וקריאה תקועה צריכה
  // להיכשל בתוך זמן הפונקציה ולא אחריו.
  return new Anthropic({ apiKey, maxRetries: 1, timeout: 90_000 })
}

export const invoiceModel = () => Deno.env.get('INVOICE_MODEL') || INVOICE_MODEL

/** A Hebrew line for the screen; the raw error goes to the function log. */
export function readError(e: unknown): string {
  if (e instanceof Anthropic.AuthenticationError) return 'מפתח ה-API של Anthropic אינו תקין'
  if (e instanceof Anthropic.RateLimitError) return 'עומס על שירות הקריאה — נסו שוב בעוד דקה'
  if (e instanceof Anthropic.BadRequestError) return 'השירות לא הצליח לקרוא את הקובץ'
  if (e instanceof Anthropic.APIConnectionError) return 'אין חיבור לשירות הקריאה'
  if (e instanceof Anthropic.APIError) return `שגיאה בשירות הקריאה (${e.status ?? '?'})`
  if (e instanceof Error && e.message) return e.message
  return 'החשבונית לא נקראה'
}

export async function readInvoicePdf(
  client: Anthropic,
  model: string,
  pdf: Uint8Array,
  context: string,
): Promise<{ reading: InvoiceReading; model: string }> {
  const msg = await client.beta.messages.create({
    model,
    max_tokens: 16000,
    // סירוב של מסווג בטיחות על חשבונית אינו צפוי, אבל אם קורה — השרת מנסה
    // שוב על מודל חלופי באותה קריאה.
    betas: ['server-side-fallback-2026-07-01'],
    fallbacks: 'default',
    output_config: {
      effort: 'medium',
      format: { type: 'json_schema', schema: INVOICE_SCHEMA as unknown as Record<string, unknown> },
    },
    system: INVOICE_SYSTEM,
    messages: [
      {
        role: 'user',
        content: [
          { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: bytesToBase64(pdf) } },
          { type: 'text', text: `${context} Return the document's data.` },
        ],
      },
    ],
  })

  if (msg.stop_reason === 'refusal') throw new Error('השירות סירב לקרוא את הקובץ')
  if (msg.stop_reason === 'max_tokens') throw new Error('התשובה נקטעה')
  const text = msg.content.find((b) => b.type === 'text')
  if (!text || text.type !== 'text') throw new Error('לא התקבלה תשובה')
  let parsed: unknown
  try {
    parsed = JSON.parse(text.text)
  } catch {
    throw new Error('התשובה אינה JSON תקין')
  }
  return { reading: normalizeInvoice(parsed), model: msg.model }
}

/** תמונה (JPEG/PNG) כעמוד PDF אחד בגודל התמונה, מוקטן ל-A4 בקירוב. */
export async function imageToPdf(bytes: Uint8Array, mime: 'image/jpeg' | 'image/png'): Promise<Uint8Array> {
  const doc = await PDFDocument.create()
  const img = mime === 'image/png' ? await doc.embedPng(bytes) : await doc.embedJpg(bytes)
  const scale = Math.min(1, 842 / Math.max(img.width, img.height))
  const w = img.width * scale
  const h = img.height * scale
  const page = doc.addPage([w, h])
  page.drawImage(img, { x: 0, y: 0, width: w, height: h })
  return doc.save()
}
