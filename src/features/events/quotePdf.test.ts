import { readFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import { beforeAll, describe, expect, it } from 'vitest'
import { generateQuotePdf } from './quotePdf'
import type { QuoteDocModel } from './quotePdf'
import { EMPTY_COMPANY, buildQuoteLines, quoteFixedNote, quoteTotals } from './quote'
import type { EventPriceAddon, WorkBoardRow } from '../../types/domain'

/**
 * בדיקת עשן על המחולל עצמו.
 *
 * היא אינה בודקת איך המסמך *נראה* — לזה יש עיניים — אלא את שני הדברים
 * שנשברים בשקט: שקובצי הפונט באמת יושבים ב-`public/fonts` (‏Heebo אינו
 * חבילת npm, והוא הופקד ידנית), ושהציור עובר על מסמך רב-עמודי בלי לזרוק.
 * ‏`fetch` מוחלף בקריאה מהדיסק, כי סביבת הבדיקות היא node.
 */
beforeAll(() => {
  globalThis.fetch = (async (url: string | URL) => {
    const name = String(url).split('/').pop() ?? ''
    const bytes = await readFile(resolve(process.cwd(), 'public/fonts', name))
    return {
      ok: true,
      arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength),
    }
  }) as unknown as typeof fetch
})

function task(id: string, price: number, title?: string): WorkBoardRow {
  return {
    id,
    task_type_name: 'הקמה',
    title: title ?? null,
    task_date: '2026-09-12',
    onsite_start_time: '08:00:00',
    customer_price: price,
  } as WorkBoardRow
}

function model(tasks: WorkBoardRow[], addons: EventPriceAddon[] = []): QuoteDocModel {
  const lines = buildQuoteLines(tasks, addons)
  return {
    documentNumber: '12345',
    issuedAt: new Date(2026, 8, 10, 14, 30),
    company: { ...EMPTY_COMPANY, name: 'וייפר מיקור חוץ לעסקים בע״מ', tax_id: '516766748',
      phone: '0747600960', email: 'office@viper-tech.co.il' },
    logo: null,
    customerName: 'קיסר',
    endClientName: 'אולם הדס',
    contactName: 'רונן',
    contactPhone: '050-1234567',
    eventDate: '2026-09-12',
    eventLocation: 'רחוב הברזל 3, תל אביב',
    lines,
    totals: quoteTotals(lines, 18),
    vatPct: 18,
    fixedNote: quoteFixedNote('12345', 'קיסר', new Date(2026, 8, 10)),
    notes: 'הצוות מגיע שעה לפני תחילת האירוע.',
    paymentTerms: 'שוטף + 30',
  }
}

describe('generateQuotePdf', () => {
  it('מחזיר PDF תקין', async () => {
    const bytes = await generateQuotePdf(model([task('t1', 1000), task('t2', 800, 'פירוק')]))
    expect(bytes.byteLength).toBeGreaterThan(1000)
    expect(new TextDecoder().decode(bytes.slice(0, 5))).toBe('%PDF-')
  })

  it('גולש לעמוד נוסף כשיש הרבה שורות, ואינו נופל', async () => {
    const many = Array.from({ length: 60 }, (_, i) =>
      task(`t${i}`, 100 + i, `משימה ארוכה במיוחד מספר ${i} עם תיאור שגולש שורה`),
    )
    const bytes = await generateQuotePdf(model(many))
    const { PDFDocument } = await import('pdf-lib')
    const loaded = await PDFDocument.load(bytes)
    expect(loaded.getPageCount()).toBeGreaterThan(1)
  })

  it('מסמך בלי שורות ובלי הערות עדיין נוצר', async () => {
    const doc = model([])
    const bytes = await generateQuotePdf({ ...doc, notes: null, paymentTerms: null })
    expect(new TextDecoder().decode(bytes.slice(0, 5))).toBe('%PDF-')
  })
})
