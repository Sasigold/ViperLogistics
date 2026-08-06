import { useQuery } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import { Modal, Spinner, EmptyState, Badge } from '../../components/ui'
import { fmtDateTime } from '../../lib/dates'

interface AuditRow {
  id: number
  actor_user_id: string | null
  action: 'INSERT' | 'UPDATE' | 'DELETE'
  table_name: string
  changed_cols: string[] | null
  old_data: Record<string, unknown> | null
  new_data: Record<string, unknown> | null
  created_at: string
}

const actionLabels = { INSERT: 'נוצר', UPDATE: 'עודכן', DELETE: 'נמחק' }
const actionColors = { INSERT: '#22c55e', UPDATE: '#3b82f6', DELETE: '#ef4444' }

export function AuditTrail({ entity, rowId, onClose }: { entity: string; rowId: string; onClose: () => void }) {
  const { data: rows = [], isLoading } = useQuery({
    queryKey: ['audit', entity, rowId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('audit_log')
        .select('*')
        .eq('row_id', rowId)
        .order('created_at', { ascending: false })
        .limit(100)
      if (error) throw error
      return data as AuditRow[]
    },
  })

  return (
    <Modal open onClose={onClose} title="היסטוריית שינויים" wide>
      {isLoading ? (
        <Spinner full />
      ) : rows.length === 0 ? (
        <EmptyState text="אין היסטוריה" />
      ) : (
        <div className="max-h-[60vh] space-y-2 overflow-y-auto">
          {rows.map((r) => {
            const isSoftDelete = r.action === 'UPDATE' && r.changed_cols?.length === 1 && r.changed_cols[0] === 'deleted_at'
            return (
              <div key={r.id} className="rounded-lg border border-[var(--border)] p-3 text-sm">
                <div className="flex items-center gap-2">
                  <Badge color={isSoftDelete ? '#ef4444' : actionColors[r.action]}>
                    {isSoftDelete ? 'נמחק (רך)' : actionLabels[r.action]}
                  </Badge>
                  <span className="text-xs text-[var(--muted)]">{r.table_name}</span>
                  <span className="ms-auto text-xs text-[var(--muted)]">{fmtDateTime(r.created_at)}</span>
                </div>
                {r.action === 'UPDATE' && !isSoftDelete && r.changed_cols && (
                  <div className="mt-2 space-y-1 text-xs">
                    {r.changed_cols
                      .filter((c) => !['updated_at', 'search_tsv'].includes(c))
                      .map((c) => (
                        <div key={c} className="flex flex-wrap gap-1">
                          <span className="font-medium">{c}:</span>
                          <span className="text-red-500 line-through">{String(r.old_data?.[c] ?? '—')}</span>
                          <span>←</span>
                          <span className="text-emerald-600">{String(r.new_data?.[c] ?? '—')}</span>
                        </div>
                      ))}
                  </div>
                )}
              </div>
            )
          })}
        </div>
      )}
    </Modal>
  )
}
