/**
 * החתמת לקוח על האירוע — קריאה וקליטה (0107).
 *
 * החתימה נשמרת כ-data URL בעמודת טקסט, ולא ב-Storage: היא קלה, וכך היא נשארת
 * עצמאית ותחת RLS בלבד. הרשומה קבועה — החתמה חוזרת מוסיפה שורה, והאחרונה היא
 * הפעילה. RLS כבר מסתירה חתימות ממי שאינו ראש צוות ההקמה / הלקוח / מנהל המערכת,
 * ולכן הקליינט רק מצייר את מה שהוחזר לו.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import type { EventSignature } from '../../types/domain'

export function useEventSignatures(eventId: string, enabled = true) {
  return useQuery({
    queryKey: ['event_signatures', eventId],
    enabled,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('event_signatures')
        .select('*')
        .eq('event_id', eventId)
        .order('created_at', { ascending: false })
      if (error) throw error
      return data as EventSignature[]
    },
  })
}

export interface NewSignature {
  signerName: string
  /** data URL של תמונת החתימה */
  signatureData: string
}

/**
 * קליטת חתימה. `signed_by` נכפה בשרת מהפרופיל של הקורא (0107), ולכן אינו נשלח
 * מכאן — כל ניסיון לחתום בשם אדם אחר נדרס.
 */
export function useAddSignature(eventId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (next: NewSignature) => {
      const { error } = await supabase.from('event_signatures').insert({
        event_id: eventId,
        signer_name: next.signerName.trim(),
        signature_data: next.signatureData,
      })
      if (error) throw error
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['event_signatures', eventId] })
      // הטריגר במסד רשם שורה ביומן, והיומן פתוח על אותו מסך
      void qc.invalidateQueries({ queryKey: ['event_activity', eventId] })
    },
  })
}
