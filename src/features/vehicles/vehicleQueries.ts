/**
 * צי הרכב — קריאה, כתיבה והעלאה.
 *
 * הדלי `vehicle-docs` פרטי (0089), ולכן אין URL קבוע לקובץ: כל תצוגה עוברת
 * ב-createSignedUrl. זו התבנית של specQueries.ts, והיא חוזרת כאן בלי שינוי —
 * המפרט של האירוע היה הצרכן הראשון של Storage, וזה השני.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { QueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import type {
  FleetExpirySummary,
  Vehicle,
  VehicleDocument,
  VehicleDocumentStatus,
  VehicleDriverAssignment,
  VehicleFuelCard,
} from '../../types/domain'
import { docStoragePath } from './vehicles'

export const VEHICLE_DOC_BUCKET = 'vehicle-docs'

/** תוקף הכתובת החתומה. ארוך מספיק לקרוא מסמך, קצר מספיק שלא ישוטט. */
const SIGNED_URL_TTL_SECONDS = 15 * 60

export function invalidateVehicle(qc: QueryClient, vehicleId?: string) {
  void qc.invalidateQueries({ queryKey: ['vehicles'] })
  void qc.invalidateQueries({ queryKey: ['fleet'] })
  if (vehicleId) {
    void qc.invalidateQueries({ queryKey: ['vehicle_documents', vehicleId] })
    void qc.invalidateQueries({ queryKey: ['vehicle_drivers', vehicleId] })
    void qc.invalidateQueries({ queryKey: ['vehicle_fuel_card', vehicleId] })
  }
}

/* ===== הרכב =============================================================== */

export function useVehicle(id: string | undefined) {
  return useQuery({
    queryKey: ['vehicles', 'one', id],
    enabled: !!id,
    queryFn: async () => {
      const { data, error } = await supabase.from('vehicles').select('*').eq('id', id!).single()
      if (error) throw error
      return data as Vehicle
    },
  })
}

/**
 * המונים שמעל הרשימה. מגיעים מ-RPC ולא מספירה בלקוח כדי שהמסך והדשבורד
 * לעולם לא יסתרו זה את זה — אותו נימוק שכתוב ב-ReceiptsPage על פס הסיכום.
 */
export function useFleetExpirySummary() {
  return useQuery({
    queryKey: ['fleet', 'summary'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('fleet_expiry_summary')
      if (error) throw error
      return data as FleetExpirySummary
    },
  })
}

/**
 * כל המסמכים שפגים או עומדים לפוג, על פני כל הצי. מזין את העמודה "תוקף"
 * ברשימה, ולכן הוא שאילתה אחת ולא אחת פר-רכב.
 */
export function useFleetExpiringDocuments(enabled = true) {
  return useQuery({
    queryKey: ['fleet', 'expiring'],
    enabled,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('vehicle_document_status')
        .select('*')
        .is('deleted_at', null)
        .in('status', ['expired', 'expiring'])
        .order('expires_at')
      if (error) throw error
      return data as VehicleDocumentStatus[]
    },
  })
}

/* ===== מסמכים ============================================================= */

export function useVehicleDocuments(vehicleId: string | undefined, enabled = true) {
  return useQuery({
    queryKey: ['vehicle_documents', vehicleId],
    enabled: !!vehicleId && enabled,
    queryFn: async () => {
      // RLS כבר מסתירה מסמכים שהוסרו ממי שאינו אדמין. הסינון כאן הוא כדי
      // שהמסך יראה אותו דבר לשני סוגי הקוראים.
      const { data, error } = await supabase
        .from('vehicle_document_status')
        .select('*')
        .eq('vehicle_id', vehicleId!)
        .is('deleted_at', null)
        .order('expires_at', { ascending: false, nullsFirst: false })
      if (error) throw error
      return data as VehicleDocumentStatus[]
    },
  })
}

export function useVehicleDocSignedUrl(doc: Pick<VehicleDocument, 'id' | 'storage_path'> | null | undefined) {
  return useQuery({
    queryKey: ['vehicle_doc_url', doc?.id],
    enabled: !!doc?.storage_path,
    // קצר מהתוקף במכוון: כתובת שפגה במטמון היא קישור שבור שאיש אינו מבין למה.
    staleTime: (SIGNED_URL_TTL_SECONDS - 300) * 1000,
    gcTime: SIGNED_URL_TTL_SECONDS * 1000,
    queryFn: async () => {
      if (!doc?.storage_path) return null
      const { data, error } = await supabase.storage
        .from(VEHICLE_DOC_BUCKET)
        .createSignedUrl(doc.storage_path, SIGNED_URL_TTL_SECONDS)
      if (error) throw error
      return data.signedUrl
    },
  })
}

/** הורדה מיידית — כתובת חתומה שהדפדפן שומר בשם המקורי של הקובץ. */
export async function vehicleDocDownloadUrl(doc: VehicleDocument): Promise<string | null> {
  if (!doc.storage_path) return null
  const { data, error } = await supabase.storage
    .from(VEHICLE_DOC_BUCKET)
    .createSignedUrl(doc.storage_path, SIGNED_URL_TTL_SECONDS, { download: doc.file_name ?? true })
  if (error) throw error
  return data.signedUrl
}

export interface DocumentDraft {
  kind_id: string
  document_number: string
  issued_at: string
  expires_at: string
  cost: string
  issuer: string
  note: string
  file?: File | null
}

/**
 * שמירת מסמך — הוספה או עריכה, ועם קובץ או בלעדיו.
 *
 * ההעלאה היא בשני צעדים ובניקוי אחריהם: הקובץ עולה לפני שיש לו שורה, ולכן
 * דחייה של ה-INSERT (הרשאה, רכב שנמחק) הייתה משאירה אובייקט יתום בדלי.
 * ה-remove בענף הכישלון הוא מה שמונע את זה, ופוליסת ה-delete על
 * storage.objects קיימת בשבילו בדיוק — אותה החלטה כמו ב-0077.
 */
export function useSaveVehicleDocument(vehicleId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ draft, editing }: { draft: DocumentDraft; editing: VehicleDocument | null }) => {
      const row: Record<string, unknown> = {
        vehicle_id: vehicleId,
        kind_id: draft.kind_id,
        document_number: draft.document_number.trim() || null,
        issued_at: draft.issued_at || null,
        expires_at: draft.expires_at || null,
        cost: draft.cost.trim() === '' ? null : Number(draft.cost),
        issuer: draft.issuer.trim() || null,
        note: draft.note.trim() || null,
      }

      let uploaded: string | null = null
      if (draft.file) {
        const path = docStoragePath(vehicleId, draft.file.name, crypto.randomUUID())
        const { error: upErr } = await supabase.storage.from(VEHICLE_DOC_BUCKET).upload(path, draft.file, {
          contentType: draft.file.type || undefined,
          upsert: false,
        })
        if (upErr) throw upErr
        uploaded = path
        row.storage_path = path
        row.file_name = draft.file.name
        row.mime_type = draft.file.type || null
        row.size_bytes = draft.file.size
      }

      const { error } = editing
        ? await supabase.from('vehicle_documents').update(row).eq('id', editing.id)
        : await supabase.from('vehicle_documents').insert(row)

      if (error) {
        if (uploaded) await supabase.storage.from(VEHICLE_DOC_BUCKET).remove([uploaded])
        throw error
      }
    },
    onSuccess: () => invalidateVehicle(qc, vehicleId),
  })
}

/**
 * הסרה עוברת ב-RPC ולא ב-UPDATE ישיר: פוסטגרס מחילה את פוליסת ה-select גם
 * על השורה החדשה, ולכן שורה אינה יכולה להעלים את עצמה מעיני מי שמחק אותה.
 * הקובץ עצמו נשאר בדלי — ההיסטוריה יורדת מהמסך ואינה נמחקת.
 */
export function useRemoveVehicleDocument(vehicleId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ id, restore = false }: { id: string; restore?: boolean }) => {
      const { error } = await supabase.rpc('remove_vehicle_document', { p_id: id, p_restore: restore })
      if (error) throw error
    },
    onSuccess: () => invalidateVehicle(qc, vehicleId),
  })
}

/* ===== נהגים ============================================================== */

export function useVehicleDrivers(vehicleId: string | undefined, enabled = true) {
  return useQuery({
    queryKey: ['vehicle_drivers', vehicleId],
    enabled: !!vehicleId && enabled,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('vehicle_driver_assignments')
        .select('*')
        .eq('vehicle_id', vehicleId!)
        .is('deleted_at', null)
        .order('from_date', { ascending: false })
      if (error) throw error
      return data as VehicleDriverAssignment[]
    },
  })
}

/**
 * פתיחת הצמדה. ה-RPC סוגר את הקודמת באותה טרנזקציה — שתי כתיבות מהלקוח היו
 * נופלות על האינדקס הייחודי בדיוק באמצע, ומשאירות רכב בלי נהג.
 */
export function useAssignDriver(vehicleId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (v: { profileId: string; from: string; note: string }) => {
      const { error } = await supabase.rpc('assign_vehicle_driver', {
        p_vehicle: vehicleId,
        p_profile: v.profileId,
        p_from: v.from || undefined,
        p_note: v.note.trim() || null,
      })
      if (error) throw error
    },
    onSuccess: () => invalidateVehicle(qc, vehicleId),
  })
}

export function useEndDriver(vehicleId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (to: string) => {
      const { error } = await supabase.rpc('end_vehicle_driver', { p_vehicle: vehicleId, p_to: to || undefined })
      if (error) throw error
    },
    onSuccess: () => invalidateVehicle(qc, vehicleId),
  })
}

/* ===== כרטיס דלק ========================================================== */

/**
 * `enabled` נשלט מבחוץ ולא נגזר כאן: בלי `fleet.view_fuel_card` ה-RLS מחזירה
 * אפס שורות ממילא, אבל אין טעם לשלוח שאילתה שידוע שתחזור ריקה.
 */
export function useVehicleFuelCard(vehicleId: string | undefined, enabled = true) {
  return useQuery({
    queryKey: ['vehicle_fuel_card', vehicleId],
    enabled: !!vehicleId && enabled,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('vehicle_fuel_cards')
        .select('*')
        .eq('vehicle_id', vehicleId!)
        .is('deleted_at', null)
        .maybeSingle()
      if (error) throw error
      return (data ?? null) as VehicleFuelCard | null
    },
  })
}

export function useSaveFuelCard(vehicleId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ card, values }: { card: VehicleFuelCard | null; values: Partial<VehicleFuelCard> }) => {
      const row = { ...values, vehicle_id: vehicleId }
      const { error } = card
        ? await supabase.from('vehicle_fuel_cards').update(row).eq('id', card.id)
        : await supabase.from('vehicle_fuel_cards').insert(row)
      if (error) throw error
    },
    onSuccess: () => invalidateVehicle(qc, vehicleId),
  })
}

/* ===== קישור למשאית ======================================================= */

export function useLinkTruck(vehicleId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (truckId: string | null) => {
      const { error } = await supabase.rpc('vehicle_link_truck', { p_vehicle: vehicleId, p_truck: truckId })
      if (error) throw error
    },
    onSuccess: () => {
      invalidateVehicle(qc, vehicleId)
      void qc.invalidateQueries({ queryKey: ['trucks'] })
    },
  })
}

export function useCreateTruckForVehicle(vehicleId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc('vehicle_create_truck', { p_vehicle: vehicleId })
      if (error) throw error
    },
    onSuccess: () => {
      invalidateVehicle(qc, vehicleId)
      void qc.invalidateQueries({ queryKey: ['trucks'] })
    },
  })
}

/* ===== סריקת תוקף ידנית =================================================== */

/**
 * "בדוק עכשיו". אין pg_cron ברפו, והתזמון האמיתי הוא פונקציית Edge; זה
 * הכפתור שמאפשר להריץ את אותה בדיקה בלי לחכות לה. הסוויפ אידמפוטנטי
 * (0089 §9), ולכן לחיצה חוזרת אינה שולחת דבר פעמיים.
 */
export function useFleetSweep() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.rpc('fleet_expiry_sweep')
      if (error) throw error
      return data as { documents: number; notifications: number }
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['fleet'] })
      void qc.invalidateQueries({ queryKey: ['notifications'] })
    },
  })
}
