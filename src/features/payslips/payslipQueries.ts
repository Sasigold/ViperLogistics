/**
 * תלושי שכר (0218) — קריאות, העלאה וקריאה אוטומטית.
 *
 * המנהל קורא דרך RPC (`payslips_board`, `payslip_batches_overview`) כי השרת
 * מחשב שם את ההצעה ואת הסיכומים ומסתיר את הסכומים ממי שאין לו עלות מעביד.
 * העובד קורא את `payslips` ישירות — ה-RLS מחזירה לו רק את שלו.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { QueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import type {
  MyPayslip,
  PayslipAmountKey,
  PayslipBatchOverview,
  PayslipBoard,
  PayslipNiBracket,
} from '../../types/domain'
import { PAYSLIP_BUCKET, READ_CHUNK, chunks, pagePath, slipPages } from './payslips'
import { mergePdfs, splitPages } from './payslipPdf'

const KEY = 'payslips'

const invalidate = (qc: QueryClient) => qc.invalidateQueries({ queryKey: [KEY] })

export interface BoardFilter {
  batchId?: string | null
  period?: string | null
  unassigned?: boolean
}

export function usePayslipsBoard(f: BoardFilter, enabled = true) {
  const has = useAuth((s) => s.has)
  const allowed = has(PERM.PAYSLIPS_MANAGE) || has(PERM.PAYSLIPS_EMPLOYER_COST)
  return useQuery({
    queryKey: [KEY, 'board', f.batchId ?? null, f.period ?? null, !!f.unassigned],
    enabled: enabled && allowed,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('payslips_board', {
        p_batch_id: f.batchId ?? null,
        p_period: f.period ?? null,
        p_unassigned: !!f.unassigned,
      })
      if (error) throw error
      return data as PayslipBoard
    },
  })
}

export function usePayslipBatches(enabled = true) {
  const has = useAuth((s) => s.has)
  const allowed = has(PERM.PAYSLIPS_MANAGE) || has(PERM.PAYSLIPS_EMPLOYER_COST)
  return useQuery({
    queryKey: [KEY, 'batches'],
    enabled: enabled && allowed,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('payslip_batches_overview', { p_limit: 24 })
      if (error) throw error
      return data as PayslipBatchOverview[]
    },
  })
}

export function useMyPayslips() {
  const profileId = useAuth((s) => s.me?.profile.id ?? null)
  return useQuery({
    queryKey: [KEY, 'mine', profileId],
    enabled: !!profileId,
    queryFn: async () => {
      // מי שמנהל תלושים רואה ב-RLS את כולם; כאן רק את שלו
      const { data, error } = await supabase
        .from('payslips')
        .select('id, batch_id, page_from, page_to, period, assigned_at')
        .eq('profile_id', profileId!)
        .is('deleted_at', null)
        .order('period', { ascending: false })
        .order('assigned_at', { ascending: false })
      if (error) throw error
      return data as MyPayslip[]
    },
  })
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

/** profileId null מבטל את השיוך */
export const useAssignPayslip = () =>
  useRpcMutation((v: { id: string; profileId: string | null }) =>
    supabase.rpc('payslip_assign', { p_payslip_id: v.id, p_profile_id: v.profileId }),
  )

export const useSetPayslipPeriod = () =>
  useRpcMutation((v: { id: string; period: string }) =>
    supabase.rpc('payslip_set_period', { p_payslip_id: v.id, p_period: v.period }),
  )

export const useMergePayslip = () =>
  useRpcMutation((id: string) => supabase.rpc('payslip_merge_previous', { p_payslip_id: id }))

export const useSplitPayslip = () => useRpcMutation((id: string) => supabase.rpc('payslip_split', { p_payslip_id: id }))

export const useRemovePayslip = () =>
  useRpcMutation((id: string) => supabase.rpc('payslip_remove', { p_payslip_id: id }))

export const useSavePayslipAmounts = () =>
  useRpcMutation((v: { id: string; amounts: Partial<Record<PayslipAmountKey, number | null>> }) =>
    supabase.rpc('payslip_amounts_save', { p_payslip_id: v.id, p_amounts: v.amounts }),
  )

/** הקובץ כולו. העמודים נמחקים מ-Storage אחרי ההסרה — השער מתיר זאת למי שמנהל. */
export function useRemovePayslipBatch() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (b: { id: string; pageCount: number }) => {
      const { error } = await supabase.rpc('payslip_batch_remove', { p_batch_id: b.id })
      if (error) throw error
      await supabase.storage.from(PAYSLIP_BUCKET).remove(slipPages(1, b.pageCount).map((p) => pagePath(b.id, p)))
    },
    onSuccess: () => void invalidate(qc),
  })
}

/* ===== העלאה ===== */

export type UploadStep =
  | { step: 'split' }
  | { step: 'upload'; done: number; total: number }
  | { step: 'read'; done: number; total: number }
  | { step: 'group' }

async function runLimited<T>(items: readonly T[], limit: number, fn: (item: T) => Promise<void>) {
  let next = 0
  const worker = async () => {
    while (next < items.length) await fn(items[next++])
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker))
}

/**
 * מפצל את ה-PDF לעמודים, יוצר את הקובץ במסד ומעלה עמוד-עמוד. נכשל באמצע —
 * הקובץ מוסר ומה שעלה נמחק, כדי שלא יישאר קובץ חצי-מועלה ברשימה.
 */
export async function uploadPayslipFile(
  file: File,
  period: string,
  onStep: (s: UploadStep) => void,
): Promise<{ batchId: string; pageCount: number }> {
  onStep({ step: 'split' })
  const pages = await splitPages(await file.arrayBuffer())

  const { data: batchId, error } = await supabase.rpc('payslip_batch_create', {
    p_file_name: file.name,
    p_page_count: pages.length,
    p_period: period,
  })
  if (error) throw error
  const id = batchId as string

  let done = 0
  onStep({ step: 'upload', done, total: pages.length })
  try {
    await runLimited(
      pages.map((bytes, i) => ({ bytes, page: i + 1 })),
      4,
      async ({ bytes, page }) => {
        const { error: upErr } = await supabase.storage
          .from(PAYSLIP_BUCKET)
          .upload(pagePath(id, page), new Blob([bytes as BlobPart], { type: 'application/pdf' }), {
            contentType: 'application/pdf',
            upsert: true,
          })
        if (upErr) throw upErr
        onStep({ step: 'upload', done: ++done, total: pages.length })
      },
    )
  } catch (e) {
    await supabase.rpc('payslip_batch_remove', { p_batch_id: id })
    await supabase.storage.from(PAYSLIP_BUCKET).remove(slipPages(1, pages.length).map((p) => pagePath(id, p)))
    throw e
  }
  return { batchId: id, pageCount: pages.length }
}

export interface ReadOutcome {
  /** false — אין מפתח לשירות הקריאה; השיוך נעשה ביד */
  configured: boolean
  read: number
  failed: { page: number; error: string }[]
  /** הקיבוץ לתלושים הוחל (או, ב-'amounts', הסכומים עודכנו) */
  grouped: boolean
  /** ב-'amounts': תלושים שהסכומים שלהם הוקלדו ביד ולכן לא עודכנו */
  manual?: number
}

interface PageResult {
  page: number
  ok: boolean
  error?: string
}

class NotConfigured extends Error {}

async function readChunk(batchId: string, pages: number[]): Promise<PageResult[]> {
  const { data, error } = await supabase.functions.invoke('payslip-read', { body: { batch_id: batchId, pages } })
  if (error) {
    const ctx = (error as { context?: Response }).context
    const parsed = ctx ? await ctx.json().catch(() => null) : null
    // ‏404 — הפונקציה עוד לא נפרסה; מבחינת המסך זה אותו "לא מוגדר"
    if (parsed?.code === 'not_configured' || ctx?.status === 404) throw new NotConfigured()
    throw new Error(parsed?.error ?? 'שירות הקריאה אינו זמין')
  }
  return (data as { pages: PageResult[] }).pages
}

/**
 * הקריאה האוטומטית, במנות קטנות כדי שקובץ גדול לא ייתקע בגבול הזמן של
 * הפונקציה, ואז הקיבוץ לתלושים בשרת. עמודים שלא נקראו נשארים תלוש-לעמוד.
 */
export async function readPayslipBatch(
  batchId: string,
  pages: number[],
  onStep: (s: UploadStep) => void,
  /** 'group' — קיבוץ מחדש לתלושים; 'amounts' — רק הסכומים, לקובץ שכבר שויכו ממנו תלושים (0219) */
  mode: 'group' | 'amounts' = 'group',
): Promise<ReadOutcome> {
  const failed: ReadOutcome['failed'] = []
  let read = 0
  onStep({ step: 'read', done: 0, total: pages.length })
  try {
    for (const chunk of chunks(pages, READ_CHUNK)) {
      for (const r of await readChunk(batchId, chunk)) {
        if (r.ok) read++
        else failed.push({ page: r.page, error: r.error ?? 'העמוד לא נקרא' })
      }
      onStep({ step: 'read', done: read + failed.length, total: pages.length })
    }
  } catch (e) {
    if (e instanceof NotConfigured) return { configured: false, read: 0, failed: [], grouped: false }
    throw e
  }
  if (read === 0) return { configured: true, read, failed, grouped: false }

  onStep({ step: 'group' })
  if (mode === 'amounts') {
    const { data, error } = await supabase.rpc('payslip_refresh_amounts', { p_batch_id: batchId })
    if (error) throw error
    return { configured: true, read, failed, grouped: true, manual: (data as { manual: number }).manual }
  }
  const { error } = await supabase.rpc('payslip_apply_reading', { p_batch_id: batchId })
  if (error) throw error
  return { configured: true, read, failed, grouped: true }
}

/* ===== מדרגות ביטוח לאומי מעסיק (0219) ===== */

export function useNiBrackets() {
  const has = useAuth((s) => s.has)
  return useQuery({
    queryKey: [KEY, 'ni_brackets'],
    enabled: has(PERM.PAYSLIPS_EMPLOYER_COST),
    queryFn: async () => {
      const { data, error } = await supabase
        .from('payslip_settings')
        .select('value')
        .eq('key', 'employer_ni_brackets')
        .maybeSingle()
      if (error) throw error
      return ((data?.value as PayslipNiBracket[] | undefined) ?? []).map((b) => ({
        up_to: b.up_to === null ? null : Number(b.up_to),
        rate: Number(b.rate),
      }))
    },
  })
}

/** שמירה מחשבת מחדש את ביטוח הלאומי של כל התלושים; מחזירה כמה. */
export function useSaveNiBrackets() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (brackets: PayslipNiBracket[]) => {
      const { data, error } = await supabase.rpc('payslip_ni_brackets_save', { p_brackets: brackets })
      if (error) throw error
      return data as number
    },
    onSuccess: () => void invalidate(qc),
  })
}

export function useInvalidatePayslips() {
  const qc = useQueryClient()
  return () => void invalidate(qc)
}

/* ===== פתיחת תלוש ===== */

/** העמודים של התלוש כקובץ אחד. RLS על Storage מחליטה מי רשאי. */
export async function loadSlipPdf(batchId: string, from: number, to: number): Promise<Blob> {
  const parts = await Promise.all(
    slipPages(from, to).map(async (p) => {
      const { data, error } = await supabase.storage.from(PAYSLIP_BUCKET).download(pagePath(batchId, p))
      if (error || !data) throw error ?? new Error('העמוד לא נמצא')
      return new Uint8Array(await data.arrayBuffer())
    }),
  )
  const bytes = await mergePdfs(parts)
  return new Blob([bytes as BlobPart], { type: 'application/pdf' })
}

/**
 * פתיחה בחלון חדש. החלון נפתח *לפני* ההורדה, בתוך הלחיצה עצמה — דפדפנים
 * חוסמים window.open שמגיע אחרי await.
 */
export async function openSlip(batchId: string, from: number, to: number): Promise<void> {
  const w = window.open('', '_blank')
  try {
    const url = URL.createObjectURL(await loadSlipPdf(batchId, from, to))
    if (w) w.location.href = url
    else window.location.assign(url)
    setTimeout(() => URL.revokeObjectURL(url), 5 * 60_000)
  } catch (e) {
    w?.close()
    throw e
  }
}

export async function downloadSlip(batchId: string, from: number, to: number, fileName: string): Promise<void> {
  const url = URL.createObjectURL(await loadSlipPdf(batchId, from, to))
  const a = document.createElement('a')
  a.href = url
  a.download = fileName
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 60_000)
}
