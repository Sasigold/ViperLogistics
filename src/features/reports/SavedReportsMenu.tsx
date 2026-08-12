import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Button, MenuItem, MenuLabel, MenuSeparator, Popover, usePrompt, useToast } from '../../components/ui'
import { Bookmark, ChevronDown, ICON, STROKE, Trash2 } from '../../components/ui/icons'
import { errorMessage } from '../../lib/errors'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { normalizeReportState, stateToParam } from './reportState'
import type { ReportState } from './reportState'
import type { SavedFilter } from '../../types/domain'

/**
 * דוחות שמורים — אותה טבלת `saved_filters` של לוח השנה, תחת screen='reports'.
 *
 * מה שנשמר הוא ה-state המלא (מדד, פילוחים, סינונים, טווח), והוא עובר
 * `normalizeReportState` בהחלה — שורה שנכתבה על ידי גרסה אחרת של הקובץ הזה
 * נפתחת כמיטב יכולתה במקום להפיל את המסך. השמירה אישית: RLS (sf_own) מציג
 * לכל אחד את שלו בלבד.
 */

export function SavedReportsMenu({
  state,
  onApply,
}: {
  state: ReportState
  onApply: (state: ReportState) => void
}) {
  const me = useAuth((s) => s.me)
  const qc = useQueryClient()
  const toast = useToast()
  const { prompt, dialog } = usePrompt()

  const { data: saved = [] } = useQuery({
    queryKey: ['saved_filters', 'reports'],
    enabled: !!me,
    queryFn: async () => {
      const { data, error } = await supabase.from('saved_filters').select('*').eq('screen', 'reports').order('name')
      if (error) throw error
      return data as SavedFilter[]
    },
  })

  const save = async () => {
    const name = await prompt('שם הדוח', '', {
      title: 'שמירת הדוח הנוכחי',
      placeholder: 'למשל: הכנסות רבעוניות לפי לקוח',
    })
    if (!name || !me) return
    const { error } = await supabase.from('saved_filters').insert({
      profile_id: me.profile.id,
      screen: 'reports',
      name,
      // דרך stateToParam/JSON כדי שמה שנשמר הוא בדיוק מה שקישור נושא
      filters: JSON.parse(stateToParam(state)) as Record<string, unknown>,
    })
    if (error) toast.error(errorMessage(error))
    else {
      toast.success('הדוח נשמר')
      void qc.invalidateQueries({ queryKey: ['saved_filters'] })
    }
  }

  const remove = async (row: SavedFilter) => {
    const { error } = await supabase.from('saved_filters').delete().eq('id', row.id)
    if (error) toast.error(errorMessage(error))
    else void qc.invalidateQueries({ queryKey: ['saved_filters'] })
  }

  return (
    <>
      <Popover
        trigger={(props) => (
          <Button variant="secondary" onClick={props.toggle} aria-expanded={props['aria-expanded']} aria-haspopup="menu">
            <Bookmark size={ICON.sm} strokeWidth={STROKE} />
            דוחות שמורים
            <ChevronDown size={ICON.sm} strokeWidth={STROKE} />
          </Button>
        )}
      >
        {(close) => (
          <>
            <MenuItem
              onClick={() => {
                close()
                void save()
              }}
            >
              שמירת הדוח הנוכחי…
            </MenuItem>
            {saved.length > 0 && (
              <>
                <MenuSeparator />
                <MenuLabel>הדוחות שלי</MenuLabel>
                {saved.map((row) => (
                  <div key={row.id} className="flex items-center">
                    <div className="min-w-0 flex-1">
                      <MenuItem
                        onClick={() => {
                          close()
                          onApply(normalizeReportState(row.filters))
                        }}
                      >
                        <span className="truncate">{row.name}</span>
                      </MenuItem>
                    </div>
                    <button
                      type="button"
                      aria-label={`מחיקת ${row.name}`}
                      className="me-1 rounded p-1.5 text-ink-tertiary transition-colors hover:bg-hover hover:text-error"
                      onClick={() => void remove(row)}
                    >
                      <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                    </button>
                  </div>
                ))}
              </>
            )}
          </>
        )}
      </Popover>
      {dialog}
    </>
  )
}
