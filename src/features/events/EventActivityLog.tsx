/**
 * The event's activity log.
 *
 * Three kinds of entry share one timeline, on purpose. The database writes a row
 * whenever a tracked field on the event moves — כמות משאיות from 1 to 4 — and one
 * whenever a task joins the event or leaves it; a person writes a row when the
 * reason for any of it is worth keeping. Read together they answer "what
 * happened to this event", which no one of them answers alone.
 *
 * Everything a save touched carries the same transaction timestamp, so changes
 * made in one save are folded into a single entry rather than listed as four
 * separate ones a second apart.
 */
import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { History, ICON, MessageSquarePlus, STROKE } from '../../components/ui/icons'
import {
  Avatar,
  Button,
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  SegmentedControl,
  Skeleton,
  StatusPill,
  Textarea,
  Tooltip,
  fmtRelative,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { fmtDateTime } from '../../lib/dates'
import { shortAddress } from '../../lib/address'
import type { EventActivity, EventActivityKind } from '../../types/domain'
import { errorMessage } from '../../lib/errors'

/**
 * ערך של שדה שהשתנה, כפי שהוא נקרא ביומן.
 *
 * מיקום נשמר כ-display_name מלא, ושתי כתובות כאלה זו לצד זו הופכות שורה ביומן
 * לפסקה. מוצג הקיצור, והערך שנרשם באמת — זה שהיומן קיים כדי לתעד — נשאר בלחיצה.
 */
function ChangeValue({ field, value }: { field: string; value: string | null }) {
  if (!value) return <>—</>
  if (field !== 'location_text') return <>{value}</>

  const short = shortAddress(value)
  if (short === value) return <>{value}</>
  return (
    <Tooltip content={value} openOnClick>
      <span className="cursor-help">{short}</span>
    </Tooltip>
  )
}

const KIND_COLORS: Record<EventActivityKind, string> = {
  created: '#16a34a',
  changed: '#3563f0',
  note: '#1fa189',
  deleted: '#dc2626',
  restored: '#16a34a',
  task_added: '#7c3aed',
  task_removed: '#b45309',
  spec_added: '#0284c7',
  spec_removed: '#b45309',
  customer_signed: '#0d9488',
  price_addon_added: '#c2410c',
  price_addon_removed: '#b45309',
}

const KIND_LABELS: Record<EventActivityKind, string> = {
  created: 'האירוע נוצר',
  changed: 'עודכן',
  note: 'תיעוד',
  deleted: 'האירוע נמחק',
  restored: 'האירוע שוחזר',
  task_added: 'משימה נוספה',
  task_removed: 'משימה הוסרה',
  spec_added: 'מפרט הועלה',
  spec_removed: 'מפרט הוסר',
  customer_signed: 'חתימת לקוח',
  price_addon_added: 'תוספת מחיר',
  price_addon_removed: 'תוספת הוסרה',
}

/** One timeline entry: a note, a lifecycle event, or every field one save moved. */
interface Entry {
  id: number
  kind: EventActivityKind
  actor: string | null
  at: string
  note: string | null
  changes: { key: string; label: string; from: string | null; to: string | null }[]
}

/**
 * Rows arrive newest first. Consecutive 'changed' rows sharing an author and a
 * timestamp came out of one save, so they collapse into one entry.
 */
function toEntries(rows: EventActivity[]): Entry[] {
  const out: Entry[] = []
  for (const r of rows) {
    const last = out[out.length - 1]
    if (
      r.kind === 'changed' &&
      last?.kind === 'changed' &&
      last.at === r.created_at &&
      last.actor === r.actor_name
    ) {
      last.changes.push({ key: r.field_key!, label: r.field_label!, from: r.old_value, to: r.new_value })
      continue
    }
    out.push({
      id: r.id,
      kind: r.kind,
      actor: r.actor_name,
      at: r.created_at,
      note: r.note,
      changes:
        r.kind === 'changed'
          ? [{ key: r.field_key!, label: r.field_label!, from: r.old_value, to: r.new_value }]
          : [],
    })
  }
  return out
}

export function EventActivityLog({
  eventId,
  canNote,
  className,
}: {
  eventId: string
  /**
   * תיעוד מותר גם למי שאינו מחזיק את המפתח אבל הוא ראש הצוות של האירוע
   * הזה (0082). הקורא מכריע את זה, כי זו עובדה על האירוע ולא על המשתמש;
   * הפוליסה על `event_activity` בודקת בדיוק את אותו דבר בשרת.
   */
  canNote?: boolean
  className?: string
}) {
  const { has, me } = useAuth()
  const qc = useQueryClient()
  const [draft, setDraft] = useState('')
  // "הערות בלבד" מסתיר את הודעות המערכת. הבחירה נשמרת פר-דפדפן, כמו שאר
  // העדפות התצוגה (דפוס vl-*); המבחין הוא kind === 'note' — גם סוגים אחרים
  // נושאים טקסט ב-note, אבל רק 'note' נכתב בידי אדם.
  const [notesOnly, setNotesOnly] = useState(() => {
    try {
      return localStorage.getItem('vl-activity-notes-only') === '1'
    } catch {
      return false
    }
  })
  // ‏0122: שטח וקבלנים רואים רק רשומות מערכת. בלי events.activity_note_view
  // אין מלל חופשי — לא לקריאה (השרת מסנן ממילא) ולא לכתיבה (הערה שאי אפשר
  // לראות היא חסרת טעם, ולכן גם המחבר יורד).
  const canViewNotes = has(PERM.EVENTS_ACTIVITY_NOTE_VIEW)
  const canWrite = canViewNotes && (has(PERM.EVENTS_ACTIVITY_NOTE) || !!canNote)

  const { data: rows = [], isLoading } = useQuery({
    queryKey: ['event_activity', eventId],
    queryFn: async () => {
      // the feed view resolves the author's current name and drops changes to
      // fields this reader may not see — reading the table directly would leak
      // a contact phone through old_value/new_value
      const { data, error } = await supabase
        .from('event_activity_feed')
        .select('*')
        .eq('event_id', eventId)
        .order('created_at', { ascending: false })
        .order('id', { ascending: false })
        .limit(200)
      if (error) throw error
      return data as EventActivity[]
    },
  })

  const addNote = useMutation({
    mutationFn: async (note: string) => {
      const { error } = await supabase.from('event_activity').insert({
        event_id: eventId,
        kind: 'note',
        note,
        // the trigger stamps this from the session either way; sending it is
        // what lets the insert policy compare the two and reject a forgery
        actor_profile_id: me?.profile.id,
      })
      if (error) throw error
    },
    onSuccess: () => {
      setDraft('')
      void qc.invalidateQueries({ queryKey: ['event_activity', eventId] })
    },
  })

  const entries = useMemo(
    () =>
      toEntries(
        !canViewNotes
          ? rows.filter((r) => r.kind !== 'note')
          : notesOnly
            ? rows.filter((r) => r.kind === 'note')
            : rows,
      ),
    [rows, notesOnly, canViewNotes],
  )

  return (
    <Card className={`flex flex-col h-full ${className ?? ''}`}>
      <CardHeader
        title="יומן פעילות"
        subtitle="כל שינוי באירוע, ומה שרשמתם עליו"
        icon={<History size={ICON.md} strokeWidth={STROKE} />}
        actions={
          <span className="flex items-center gap-2">
            {canViewNotes && (
              <SegmentedControl
                items={[
                  { key: 'all', label: 'הכול' },
                  { key: 'notes', label: 'הערות בלבד' },
                ]}
                value={notesOnly ? 'notes' : 'all'}
                onChange={(k) => {
                  const next = k === 'notes'
                  setNotesOnly(next)
                  try {
                    localStorage.setItem('vl-activity-notes-only', next ? '1' : '0')
                  } catch {
                    /* פרטי/חסום — ההעדפה פשוט לא תישמר */
                  }
                }}
              />
            )}
            <span className="type-caption tabular text-ink-tertiary">{entries.length}</span>
          </span>
        }
      />

      {canWrite && (
        <div className="border-b border-line-subtle bg-subtle/40 p-3.5">
          <form
            className="flex flex-col gap-2"
            onSubmit={(e) => {
              e.preventDefault()
              const note = draft.trim()
              if (note) addNote.mutate(note)
            }}
          >
            <Textarea
              autoGrow
              rows={2}
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              placeholder="מה קרה? למשל: הלקוח ביקש משאית נוספת בטלפון"
              aria-label="תיעוד חופשי ליומן"
            />
            <Button
              type="submit"
              variant="primary"
              size="sm"
              className="self-end shrink-0"
              disabled={!draft.trim()}
              loading={addNote.isPending}
            >
              <MessageSquarePlus size={ICON.sm} strokeWidth={STROKE} />
              הוספה ליומן
            </Button>
          </form>
          {addNote.isError && (
            <p className="mt-2 type-caption text-error-text">{errorMessage(addNote.error)}</p>
          )}
        </div>
      )}

      <CardBody className="flex-1 min-h-0 flex flex-col p-4 overflow-hidden">
        {isLoading ? (
          <div className="space-y-3">
            {Array.from({ length: 4 }).map((_, i) => (
              <Skeleton key={i} className="h-16 w-full rounded-lg" />
            ))}
          </div>
        ) : entries.length === 0 ? (
          notesOnly && rows.length > 0 ? (
            <EmptyState
              compact
              art="table"
              title="אין הערות"
              description='ביומן יש רק הודעות מערכת — החזירו את הבורר ל"הכול" כדי לראות אותן'
            />
          ) : (
            <EmptyState
              compact
              art="table"
              title="היומן ריק"
              description={
                canWrite
                  ? 'שינויים באירוע יירשמו כאן אוטומטית, ואפשר גם לרשום תיעוד חופשי'
                  : 'שינויים באירוע יירשמו כאן אוטומטית'
              }
            />
          )
        ) : (
          /* a vertical rail turns a list of entries into a readable timeline */
          <ol className="relative flex-1 min-h-0 space-y-3 overflow-y-auto ps-6 pe-1 scrollbar-thin">
            <span aria-hidden className="absolute inset-y-1 start-2 w-px bg-line" />
            {entries.map((e) => (
              <li key={e.id} className="relative">
                <span
                  aria-hidden
                  className="absolute -start-[1.375rem] top-3 size-2.5 rounded-full ring-4 ring-surface"
                  style={{ background: KIND_COLORS[e.kind] }}
                />
                <div className="rounded-lg border border-line-subtle bg-surface p-3 transition-colors hover:border-line">
                  <div className="flex flex-wrap items-center gap-2">
                    <StatusPill color={KIND_COLORS[e.kind]}>{KIND_LABELS[e.kind]}</StatusPill>
                    {e.actor ? (
                      <span className="inline-flex items-center gap-1.5 type-caption text-ink-secondary">
                        <Avatar name={e.actor} size="xs" />
                        {e.actor}
                      </span>
                    ) : (
                      <span className="type-caption text-ink-tertiary">המערכת</span>
                    )}
                    {/* התאריך והשעה הם מה שמצטטים אחר כך ("נוסף ב-12:40"),
                        ולכן הם הכתוב; "לפני שעתיים" יושב ב-tooltip */}
                    <Tooltip content={fmtRelative(e.at)}>
                      <span className="ms-auto type-caption tabular text-ink-tertiary">{fmtDateTime(e.at)}</span>
                    </Tooltip>
                  </div>

                  {/* גם הערה חופשית וגם משימה שנוספה או ירדה הן משפט אחד */}
                  {e.note && (
                    <p className="mt-2 whitespace-pre-wrap type-body text-ink-primary bg-subtle/30 p-2.5 rounded border border-line-subtle/50">{e.note}</p>
                  )}

                  {e.changes.length > 0 && (
                    <table className="mt-2.5 w-full">
                      <tbody>
                        {e.changes.map((c, i) => (
                          // המפתח כולל אינדקס: שתי משימות מאותו סוג ששונו
                          // בשמירה אחת חולקות field_key
                          <tr key={`${c.key}-${i}`} className="border-t border-line-subtle first:border-0">
                            <td className="py-1 pe-2 align-top type-caption text-ink-tertiary">{c.label}</td>
                            <td className="py-1 type-caption">
                              <span className="text-error-text line-through decoration-error/40">
                                <ChangeValue field={c.key} value={c.from} />
                              </span>
                              <span className="mx-1.5 text-ink-tertiary" aria-label="השתנה ל">
                                ←
                              </span>
                              <span className="font-medium text-success-text">
                                <ChangeValue field={c.key} value={c.to} />
                              </span>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </div>
              </li>
            ))}
          </ol>
        )}
      </CardBody>
    </Card>
  )
}
