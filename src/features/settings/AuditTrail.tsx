import { useQuery } from '@tanstack/react-query'
import { ICON, STROKE, History } from '../../components/ui/icons'
import { EmptyState, Modal, Skeleton, StatusPill, Tooltip, fmtRelative } from '../../components/ui'
import { supabase } from '../../lib/supabase'
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
const actionColors = { INSERT: '#16a34a', UPDATE: '#3563f0', DELETE: '#dc2626' }

const fmtValue = (v: unknown) => {
  if (v == null || v === '') return '—'
  if (typeof v === 'boolean') return v ? 'כן' : 'לא'
  return String(v)
}

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
    <Modal open onClose={onClose} title="היסטוריית שינויים" description={`${rows.length} רשומות`} wide>
      {isLoading ? (
        <div className="space-y-2">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-20 w-full" />
          ))}
        </div>
      ) : rows.length === 0 ? (
        <EmptyState art="table" title="אין היסטוריה" description="שינויים ברשומה זו יתועדו כאן" />
      ) : (
        /* a vertical rail turns a list of events into a readable timeline */
        <ol className="relative max-h-[60vh] space-y-3 overflow-y-auto ps-6">
          <span aria-hidden className="absolute inset-y-1 start-2 w-px bg-line" />
          {rows.map((r) => {
            const isSoftDelete = r.action === 'UPDATE' && r.changed_cols?.length === 1 && r.changed_cols[0] === 'deleted_at'
            const color = isSoftDelete ? actionColors.DELETE : actionColors[r.action]
            const cols = (r.changed_cols ?? []).filter((c) => !['updated_at', 'search_tsv'].includes(c))
            return (
              <li key={r.id} className="relative">
                <span
                  aria-hidden
                  className="absolute -start-[1.375rem] top-3 size-2.5 rounded-full ring-4 ring-surface"
                  style={{ background: color }}
                />
                <div className="rounded-lg border border-line-subtle bg-surface p-3">
                  <div className="flex flex-wrap items-center gap-2">
                    <StatusPill color={color}>{isSoftDelete ? 'נמחק (רך)' : actionLabels[r.action]}</StatusPill>
                    <span className="font-mono type-caption text-ink-tertiary">{r.table_name}</span>
                    <Tooltip content={fmtDateTime(r.created_at)}>
                      <span className="ms-auto type-caption tabular text-ink-tertiary">{fmtRelative(r.created_at)}</span>
                    </Tooltip>
                  </div>

                  {r.action === 'UPDATE' && !isSoftDelete && cols.length > 0 && (
                    <table className="mt-2.5 w-full">
                      <tbody>
                        {cols.map((c) => (
                          <tr key={c} className="border-t border-line-subtle first:border-0">
                            <td className="py-1 pe-2 align-top font-mono type-caption text-ink-tertiary">{c}</td>
                            <td className="py-1 type-caption">
                              <span className="text-error-text line-through decoration-error/40">
                                {fmtValue(r.old_data?.[c])}
                              </span>
                              <span className="mx-1.5 text-ink-tertiary" aria-label="השתנה ל">
                                ←
                              </span>
                              <span className="font-medium text-success-text">{fmtValue(r.new_data?.[c])}</span>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </div>
              </li>
            )
          })}
        </ol>
      )}
    </Modal>
  )
}

/* History icon is the trigger's affordance elsewhere; kept in one import site. */
export const AUDIT_ICON = <History size={ICON.md} strokeWidth={STROKE} />
