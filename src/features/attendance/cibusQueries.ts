/**
 * סיבוס מול השעון (0210). שלוש קריאות, כולן RPC: הטבלאות סגורות, וההצלבה
 * מול הנוכחות מחושבת בשרת בכל קריאה.
 *
 * המפתח מתחיל ב-'attendance', כך שכל מה שמרענן את הדוח (אישור, תיקון,
 * מחיקה — וגם האירועים החיים של useRealtimeSync) מרענן גם את ההצלבה: משמרת
 * שתוקנה יכולה להכניס משיכה פנימה או להוציא אותה.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import type { CibusImportResult, CibusImportRow, CibusReport } from '../../types/domain'

export function useCibusReport(f: { from: string; to: string; profileIds?: string[] | null }, enabled = true) {
  const has = useAuth((s) => s.has)
  return useQuery({
    queryKey: ['attendance', 'cibus', f.from, f.to, f.profileIds?.length ? f.profileIds : null],
    enabled: enabled && has(PERM.ATTENDANCE_CIBUS) && !!f.from && !!f.to,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('cibus_report', {
        p_from: f.from,
        p_to: f.to,
        p_profile_ids: f.profileIds?.length ? f.profileIds : null,
      })
      if (error) throw error
      return data as CibusReport
    },
  })
}

export function useCibusImport() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (rows: CibusImportRow[]) => {
      const { data, error } = await supabase.rpc('cibus_import', { p_rows: rows })
      if (error) throw error
      return data as CibusImportResult
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['attendance', 'cibus'] }),
  })
}

/** profileId null מבטל את הצימוד */
export function useCibusLink() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (v: { linkKey: string; profileId: string | null }) => {
      const { error } = await supabase.rpc('cibus_link', { p_link_key: v.linkKey, p_profile_id: v.profileId })
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['attendance', 'cibus'] }),
  })
}
