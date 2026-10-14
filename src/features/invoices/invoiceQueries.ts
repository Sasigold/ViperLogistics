/**
 * חשבוניות ספקים (0233) — קריאות, העלאה וקריאה אוטומטית.
 *
 * הכול למנהלי מערכת. התיקייה של החודש והסיכום מגיעים מ-`invoices_board`;
 * החברות נקראות ישירות (RLS: מנהל מערכת); מצב Gmail — מ-`invoice_gmail_status`
 * בלבד, כי הטוקן סגור.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { QueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import type { Invoice, InvoiceCompany, InvoiceGmailStatus, InvoicesBoard } from '../../types/domain'
import { INVOICE_BUCKET } from './invoices'
import { pdfName, sha256Hex, toInvoicePdf } from './invoicePdf'

const KEY = 'invoices'
const invalidate = (qc: QueryClient) => qc.invalidateQueries({ queryKey: [KEY] })

const useIsAdmin = () => useAuth((s) => !!s.me?.profile.is_admin)

export function useInvoicesBoard(period: string) {
  const admin = useIsAdmin()
  return useQuery({
    queryKey: [KEY, 'board', period],
    enabled: admin,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('invoices_board', { p_period: period })
      if (error) throw error
      return data as InvoicesBoard
    },
  })
}

export function useInvoiceCompanies() {
  const admin = useIsAdmin()
  return useQuery({
    queryKey: [KEY, 'companies'],
    enabled: admin,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('invoice_companies')
        .select('id, name, tax_id, aliases, active')
        .is('deleted_at', null)
        .order('created_at')
      if (error) throw error
      return data as InvoiceCompany[]
    },
  })
}

export function useGmailStatus() {
  const admin = useIsAdmin()
  return useQuery({
    queryKey: [KEY, 'gmail'],
    enabled: admin,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('invoice_gmail_status')
      if (error) throw error
      return data as InvoiceGmailStatus
    },
  })
}

export function useInvalidateInvoices() {
  const qc = useQueryClient()
  return () => void invalidate(qc)
}

function useRpcMutation<V>(fn: (v: V) => PromiseLike<{ error: unknown }>) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (v: V) => {
      const { error } = await fn(v)
      if (error) throw error
    },
    onSuccess: () => void invalidate(qc),
  })
}

export const useSaveInvoice = () =>
  useRpcMutation((v: { id: string; fields: Record<string, unknown> }) =>
    supabase.rpc('invoice_save', { p_id: v.id, p: v.fields }),
  )

export const useRemoveInvoice = () => useRpcMutation((id: string) => supabase.rpc('invoice_remove', { p_id: id }))

export const useSaveCompany = () =>
  useRpcMutation((v: { id: string | null; name: string; tax_id: string; aliases: string[]; active: boolean }) =>
    supabase.rpc('invoice_company_save', {
      p_id: v.id,
      p: { name: v.name, tax_id: v.tax_id, aliases: v.aliases, active: v.active },
    }),
  )

export const useRemoveCompany = () =>
  useRpcMutation((id: string) => supabase.rpc('invoice_company_remove', { p_id: id }))

export const useSaveGmailSettings = () =>
  useRpcMutation((v: { id: string; query_extra: string; active: boolean }) =>
    supabase.rpc('invoice_gmail_settings_save', { p_id: v.id, p_query_extra: v.query_extra, p_active: v.active }),
  )

export const useDisconnectGmail = () =>
  useRpcMutation((id: string) => supabase.rpc('invoice_gmail_disconnect', { p_id: id }))

/* ===== העלאה וקריאה ===== */

export type UploadOutcome =
  | { name: string; status: 'uploaded'; id: string }
  | { name: string; status: 'duplicate'; id: string }
  | { name: string; status: 'failed'; error: string }

/** קובץ אחד (או כמה צילומים שכבר אוחדו) → PDF → שורה → Storage. */
export async function uploadInvoice(
  name: string,
  pdf: Uint8Array,
  source: 'upload' | 'camera',
): Promise<{ id: string; duplicate: boolean }> {
  const sha = await sha256Hex(pdf)
  const { data, error } = await supabase.rpc('invoice_create', {
    p_file_name: pdfName(name),
    p_source: source,
    p_sha256: sha,
  })
  if (error) throw error
  const r = data as { id?: string; path?: string; duplicate_of?: string }
  if (r.duplicate_of) return { id: r.duplicate_of, duplicate: true }
  const { error: upErr } = await supabase.storage
    .from(INVOICE_BUCKET)
    .upload(r.path!, new Blob([pdf as BlobPart], { type: 'application/pdf' }), {
      contentType: 'application/pdf',
      // נתיב חדש תמיד; upsert היה דורש גם פוליסת update על הדלי, ואין כזו
      upsert: false,
    })
  if (upErr) {
    await supabase.rpc('invoice_remove', { p_id: r.id })
    throw upErr
  }
  return { id: r.id!, duplicate: false }
}

export { toInvoicePdf }

class NotConfigured extends Error {}

/** כמה חשבוניות בכל קריאה ל-`invoice-read` — זהה ל-MAX_PER_CALL שם. */
export const READ_CHUNK = 4

export interface ReadOutcome {
  configured: boolean
  read: number
  failed: { id: string; error: string }[]
}

async function readChunk(ids: string[]): Promise<{ id: string; ok: boolean; error?: string }[]> {
  const { data, error } = await supabase.functions.invoke('invoice-read', { body: { ids } })
  if (error) {
    const ctx = (error as { context?: Response }).context
    const parsed = ctx ? await ctx.json().catch(() => null) : null
    if (parsed?.code === 'not_configured' || ctx?.status === 404) throw new NotConfigured()
    throw new Error(parsed?.error ?? 'שירות הקריאה אינו זמין')
  }
  return (data as { invoices: { id: string; ok: boolean; error?: string }[] }).invoices
}

export async function readInvoices(ids: string[], onProgress?: (done: number, total: number) => void): Promise<ReadOutcome> {
  const out: ReadOutcome = { configured: true, read: 0, failed: [] }
  onProgress?.(0, ids.length)
  try {
    for (let i = 0; i < ids.length; i += READ_CHUNK) {
      for (const r of await readChunk(ids.slice(i, i + READ_CHUNK))) {
        if (r.ok) out.read++
        else out.failed.push({ id: r.id, error: r.error ?? 'לא נקראה' })
      }
      onProgress?.(Math.min(i + READ_CHUNK, ids.length), ids.length)
    }
  } catch (e) {
    if (e instanceof NotConfigured) return { ...out, configured: false }
    throw e
  }
  return out
}

/* ===== הקובץ ===== */

export async function loadInvoicePdf(inv: Pick<Invoice, 'id'>): Promise<Blob> {
  const { data, error } = await supabase.storage.from(INVOICE_BUCKET).download(`${inv.id}.pdf`)
  if (error || !data) throw error ?? new Error('הקובץ לא נמצא')
  return new Blob([await data.arrayBuffer()], { type: 'application/pdf' })
}

/* ===== Gmail ===== */

async function invokeGmail<T>(body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke('invoice-gmail', { body })
  if (error) {
    const ctx = (error as { context?: Response }).context
    const parsed = ctx ? await ctx.json().catch(() => null) : null
    if (parsed?.code === 'not_configured' || ctx?.status === 404) {
      throw new Error('החיבור ל-Gmail עוד לא הוגדר בשרת — ראו docs/INVOICES.md')
    }
    throw new Error(parsed?.error ?? 'שירות Gmail אינו זמין')
  }
  return data as T
}

/** מעבר למסך ההסכמה של Google; החזרה ל-/invoices?gmail=connected. */
export async function connectGmail(): Promise<void> {
  const returnTo = `${window.location.origin}/invoices`
  const { url } = await invokeGmail<{ url: string }>({ action: 'auth_url', return_to: returnTo })
  window.location.assign(url)
}

export interface GmailSyncResult {
  accounts: { email: string; checked: number; imported: number; skipped: number; failed: number; error?: string }[]
  more: boolean
}

/** סריקה עכשיו — עד שאין עוד (או 8 סבבים, כדי שהמסך לא ייתקע). */
export async function syncGmail(onRound?: (r: GmailSyncResult) => void): Promise<GmailSyncResult> {
  const total: GmailSyncResult = { accounts: [], more: false }
  for (let round = 0; round < 8; round++) {
    const r = await invokeGmail<GmailSyncResult>({ action: 'sync' })
    for (const a of r.accounts) {
      const t = total.accounts.find((x) => x.email === a.email)
      if (!t) total.accounts.push({ ...a })
      else {
        t.checked += a.checked
        t.imported += a.imported
        t.skipped += a.skipped
        t.failed += a.failed
        t.error = a.error
      }
    }
    total.more = r.more
    onRound?.(total)
    if (!r.more) break
  }
  return total
}
