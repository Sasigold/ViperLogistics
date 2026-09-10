/**
 * הצעות המחיר של האירוע — קריאה, הפקה וסימון שנשלחה (0169).
 *
 * שלושה חוזים שנשמרים כאן ולא בקומפוננטה:
 *   • **הפקה = קובץ ואז שורה, ואם השורה נדחתה הקובץ מוסר.** אותו דפוס של
 *     `specQueries.ts`, ומאותה סיבה: RLS על הטבלה נבדקת אחרי שהאובייקט כבר
 *     עלה, וכל דחייה שלה הייתה משאירה קובץ יתום בדלי.
 *   • **`version` נקבע בשרת** תחת נעילה פר-אירוע ואינו נשלח מכאן.
 *   • **`sent_at` נכתב פעם אחת.** הטריגר במסד הוא שכותב את שורת היומן, ולכן
 *     "נשלחה הצעת מחיר" אינו יכול להיאמר על מסמך שלא יצא.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { QueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import type { EventQuote } from '../../types/domain'
import type { QuoteLine, QuoteTotals } from './quote'
import { quoteStoragePath } from './quote'

export const QUOTE_BUCKET = 'event-quotes'

/** ארוך מספיק לפתוח מסמך, קצר מספיק שלא ישוטט — כמו המפרט. */
const SIGNED_URL_TTL_SECONDS = 15 * 60

export function useEventQuotes(eventId: string, enabled = true) {
  return useQuery({
    queryKey: ['event_quotes', eventId],
    enabled,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('event_quotes')
        .select('*')
        .eq('event_id', eventId)
        .is('deleted_at', null)
        .order('version', { ascending: false })
      if (error) throw error
      return data as EventQuote[]
    },
  })
}

export function useQuoteSignedUrl(quote: EventQuote | null | undefined) {
  return useQuery({
    queryKey: ['event_quote_url', quote?.id],
    enabled: !!quote,
    staleTime: (SIGNED_URL_TTL_SECONDS - 300) * 1000,
    gcTime: SIGNED_URL_TTL_SECONDS * 1000,
    queryFn: async () => {
      if (!quote) return null
      const { data, error } = await supabase.storage
        .from(QUOTE_BUCKET)
        .createSignedUrl(quote.storage_path, SIGNED_URL_TTL_SECONDS, { download: quote.file_name })
      if (error) throw error
      return data.signedUrl
    },
  })
}

function invalidateQuotes(qc: QueryClient, eventId: string) {
  void qc.invalidateQueries({ queryKey: ['event_quotes', eventId] })
  void qc.invalidateQueries({ queryKey: ['event_activity', eventId] })
}

export interface IssueQuoteInput {
  bytes: Uint8Array<ArrayBuffer>
  fileName: string
  documentNumber: string
  lines: QuoteLine[]
  totals: QuoteTotals
  vatPct: number
  paymentTerms: string | null
  notes: string | null
}

/** מפיק: מעלה את הקובץ, פותח שורה, ומחזיר אותה כדי שהמסך ידע מה לסמן כנשלח. */
export function useIssueQuote(eventId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (v: IssueQuoteInput): Promise<EventQuote> => {
      const path = quoteStoragePath(eventId, crypto.randomUUID())
      const blob = new Blob([v.bytes], { type: 'application/pdf' })
      const { error: upErr } = await supabase.storage
        .from(QUOTE_BUCKET)
        .upload(path, blob, { contentType: 'application/pdf', upsert: false })
      if (upErr) throw upErr

      const { data, error } = await supabase
        .from('event_quotes')
        .insert({
          event_id: eventId,
          document_number: v.documentNumber,
          storage_path: path,
          file_name: v.fileName,
          size_bytes: v.bytes.byteLength,
          lines: v.lines.map((l) => ({
            kind: l.kind,
            label: l.label,
            when_text: l.whenText,
            amount: l.amount,
          })),
          subtotal: v.totals.subtotal,
          vat_pct: v.vatPct,
          vat_amount: v.totals.vatAmount,
          total: v.totals.total,
          payment_terms: v.paymentTerms,
          notes: v.notes,
        })
        .select()
        .single()
      if (error) {
        await supabase.storage.from(QUOTE_BUCKET).remove([path])
        throw error
      }
      return data as EventQuote
    },
    onSuccess: () => invalidateQuotes(qc, eventId),
  })
}

/** מסמן שנשלחה. הטריגר במסד הוא שכותב את שורת היומן. */
export function useMarkQuoteSent(eventId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (quoteId: string) => {
      const { error } = await supabase
        .from('event_quotes')
        .update({ sent_at: new Date().toISOString() })
        .eq('id', quoteId)
      if (error) throw error
    },
    onSettled: () => invalidateQuotes(qc, eventId),
  })
}
