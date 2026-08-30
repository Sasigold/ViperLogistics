import { useLayoutEffect, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { Checkbox, Popover, StatusPill, Tooltip, cx } from '../../components/ui'
import { fmtHours, fmtTime } from '../../lib/dates'
import { shortAddress } from '../../lib/address'
import type { ExecutionMethod, Status, Truck, WorkBoardRow } from '../../types/domain'
import { PERM } from '../../lib/permissions'
import { statusOptions } from './statusOptions'

export interface BoardLookups {
  statuses: Status[]
  trucks: Truck[]
  /**
   * המשאיות שהלקוח *של השורה* רשאי לקבל (0116).
   *
   * פונקציה ולא מערך: הלוח מציג משימות של כמה לקוחות, ולכל שורה הרשימה
   * שלה. רשימה ריקה אצל הלקוח אינה "אין משאיות" אלא **אין הגבלה**, ואז
   * חוזר הקטלוג כולו — אותה סמנטיקה של `board_config` הריקה של איש צוות.
   * זה סינון ולא אכיפה: `app.enforce_customer_trucks` הוא הגבול.
   */
  trucksFor: (customerId: string | null) => Truck[]
  methods: ExecutionMethod[]
  /**
   * Whether the reader may pick a delegated contractor's staff.
   *
   * It rides on the lookups rather than on `can()` deliberately: `can()` is
   * `board.inline_edit && has(perm)`, and a contractor manager holds no
   * `board.inline_edit` — every cell of his is read-only, and routing this
   * through `can()` would leave the one control he *does* own permanently
   * disabled. Resolved once in WorkBoardPage from either assignment key.
   */
  canAssignContractor: boolean
  /**
   * האם הקורא רשאי לשבץ את סגל הלקוח שמבצע בעצמו (0133).
   *
   * נוסע כאן ולא ב-`can()` מאותו נימוק בדיוק של השורה שמעל: משתמש הלקוח
   * מחזיק `board.inline_edit` מ-0131, אבל תא "צוות" הוא שדה בלי `column_name`
   * — ולכן `boardFieldState` שלו נשאר `visible` ו-`canEditField` היה מנטרל
   * את הדבר האחד שהוא כן משבץ.
   */
  canAssignOwnStaff: boolean
  /**
   * לפתוח את הפאנל הממוקד של התא (0108).
   *
   * שיבוץ, נקודת התחלה, האצלה, כמות עובדים ותעריף אינם עמודות של המשימה —
   * הם שלוש טבלאות אחרות — ובורר בתוך תא ברוחב שתי אצבעות ידע לענות רק על
   * הראשונה שבהן. הפאנל הוא אותו רכיב שהכרטיס המלא מרכיב, ולכן הוא עונה על
   * כולן בלי להיות הכרטיס — שהוא מעכשיו של מנהל המערכת בלבד.
   */
  openPanel: (taskId: string, panel: 'staffing' | 'contractor') => void
  /**
   * כמה שורות טקסט שורת ההערות מחזיקה בפועל.
   *
   * ‏0079 נתן להערה `grow: 2` — שתי שורות קבועות — והערה ארוכה נחתכה בהן
   * בלי שדבר על המסך אמר שיש עוד. עכשיו הגובה נגזר מההערה הארוכה ביותר
   * שעל הלוח, בדיוק כפי ששורת הצוות נגזרת מהצוות הגדול ביותר, והמספר הזה
   * הוא מה שמחבר בין הגובה שנקבע שם לבין הקיטום שנעשה כאן.
   */
  noteLines: number
}

export interface CellContext {
  row: WorkBoardRow
  canEdit: boolean
  /** any *other* key a cell needs — the team cell spans two assignment rights */
  can: (perm?: string) => boolean
  patch: (row: WorkBoardRow, patch: Record<string, unknown>) => void
  lookups: BoardLookups
}

export interface BoardField {
  key: string
  label: string
  render: (ctx: CellContext) => ReactNode
  /**
   * Registry key that governs editing this cell. The board resolves it per
   * field, so someone who may change a status but not a date gets one live
   * control and one disabled one — matching exactly what the column trigger
   * would allow on the way to the database.
   */
  editPerm?: string
  /**
   * Registry key that governs seeing this row at all. Its counterpart to
   * `editPerm`: some rows read through a join RLS empties for the reader, and
   * an always-blank row reads as a broken board rather than as one that isn't
   * theirs. Absent means the row is for everyone who can open the board.
   */
  viewPerm?: string
  /** taller row — for the team list */
  tall?: boolean
  /** this many ordinary rows tall, for a cell that holds prose */
  grow?: number
}

/**
 * Cell text sizes off one variable the board sets on its own container, so the
 * minimal density and the phone can shrink every cell at once instead of each
 * field carrying its own literal.
 */
const FS = 'text-[length:var(--vl-board-fs,0.8125rem)]'

/* Inline editors share one look. They are mounted only while a cell is being
   edited, so they no longer need to hide themselves until hovered. */
const INLINE =
  `w-full min-w-0 rounded border border-line bg-surface px-1.5 py-0.5 text-center ${FS} tabular ` +
  'focus:border-primary focus:outline-none focus:ring-2 focus:ring-[var(--vl-focus-ring)]'

function Muted({ children }: { children?: ReactNode }) {
  return <span className={cx('block w-full px-1.5 text-center text-ink-tertiary', FS)}>{children ?? '—'}</span>
}

/**
 * Text that does not fit its cell, without losing what it says. A column two
 * fingers wide cannot show an address, and at the narrowest width it barely
 * holds a name — so anything cut carries the whole string with it: hover reads
 * it on a mouse, a tap opens it on a phone.
 *
 * The bubble is used rather than growing the cell in place, because the row is
 * a fixed height the whole grid is aligned to: text unfolded inside a 22px row
 * would have to scroll to be read, which is not reading.
 *
 * `Tooltip` renders nothing but its child when `content` is null, and wraps it
 * in a `display: contents` span otherwise — neither affects layout, so the
 * measurement below cannot oscillate between the two states.
 */
function Clip({
  children,
  className,
  dir,
  title,
  tight,
  lines = 1,
}: {
  children: ReactNode
  className?: string
  dir?: 'ltr' | 'rtl'
  /** what the bubble says, when it isn't simply the text itself */
  title?: ReactNode
  /** no vertical padding, and no claim on the full width — for the team list,
   *  whose row height is counted in whole lines and cannot afford four stray
   *  pixels per name, and whose names are centred as a line */
  tight?: boolean
  /** wrap to this many lines before clipping. 1 (the default) is one line */
  lines?: number
}) {
  const ref = useRef<HTMLSpanElement>(null)
  const [clipped, setClipped] = useState(false)

  useLayoutEffect(() => {
    const el = ref.current
    if (!el) return
    /* one line runs out of width, several run out of height */
    setClipped(lines > 1 ? el.scrollHeight > el.clientHeight + 1 : el.scrollWidth > el.clientWidth + 1)
  })

  return (
    <Tooltip content={clipped ? (title ?? children) : null} openOnClick>
      <span
        ref={ref}
        dir={dir}
        /* the clamp is a number and not a utility class: the notes row sizes
           itself to the longest note on the board, so how many lines fit is
           decided at render time rather than in the stylesheet */
        style={
          lines > 1
            ? { display: '-webkit-box', WebkitBoxOrient: 'vertical', WebkitLineClamp: lines }
            : undefined
        }
        className={cx(
          'block text-center',
          lines > 1 ? 'overflow-hidden whitespace-pre-wrap break-words' : 'truncate',
          tight ? 'min-w-0 max-w-full px-1' : 'w-full px-1.5 py-0.5',
          clipped && 'cursor-help',
          FS,
          className,
        )}
      >
        {children}
      </span>
    </Tooltip>
  )
}

/**
 * A cell is a *reading* surface first. A single click used to drop the reader
 * into an editor — and on a board where every other click is "scroll to that
 * day" or "read the rest of this address", that meant edits nobody asked for.
 * Editing now takes a deliberate double click, and one press of Escape puts
 * the cell back the way it was.
 */
function Editable({
  canEdit,
  view,
  edit,
}: {
  canEdit: boolean
  view: ReactNode
  edit: (close: () => void) => ReactNode
}) {
  const [open, setOpen] = useState(false)
  const armed = useArmed(() => setOpen(true))
  if (!canEdit) return <>{view}</>
  if (open) return <>{edit(() => setOpen(false))}</>
  return (
    <button type="button" {...armed}>
      {view}
    </button>
  )
}

/** two taps closer together than this are one gesture */
const DOUBLE_TAP_MS = 400

/**
 * The double press, and its keyboard equivalent.
 *
 * Counted from `click` rather than taken from `dblclick`, because a phone does
 * not send `dblclick`: a mobile browser reads two quick taps as its own zoom
 * gesture and the event never reaches the page. Two clicks inside the window
 * below are the gesture, on every input the board can be driven with.
 * `touch-manipulation` is the other half of it — it tells the browser there is
 * no zoom to wait for here, which also drops the tap delay that came with it.
 *
 * Enter and Space open on a single press: a keyboard has no "double" to give.
 */
function useArmed(open: () => void) {
  const last = useRef(0)
  return {
    onClick: () => {
      const now = Date.now()
      if (now - last.current < DOUBLE_TAP_MS) {
        last.current = 0
        open()
      } else {
        last.current = now
      }
    },
    onKeyDown: (e: React.KeyboardEvent) => {
      if (e.key !== 'Enter' && e.key !== ' ') return
      e.preventDefault()
      open()
    },
    className: 'block w-full cursor-cell touch-manipulation text-inherit',
  }
}

/** the editor is mounted by the double click, so it may claim the caret and,
 *  where the platform has one, the picker — both inside that user gesture */
function openEditor(el: HTMLInputElement | HTMLTextAreaElement | null) {
  if (!el) return
  el.focus()
  if (el instanceof HTMLTextAreaElement) {
    /* פרוזה נערכת מהסוף, לא נבחרת כולה: הערה בת שלוש שורות שהודפסה עליה
       אות אחת בטעות היא הערה שאבדה. */
    el.setSelectionRange(el.value.length, el.value.length)
    return
  }
  if (el.type === 'time' || el.type === 'date') {
    const picker = el as { showPicker?: () => void }
    try {
      picker.showPicker?.()
    } catch {
      /* Safari and Firefox focus without opening — still an editable cell */
    }
  } else {
    el.select()
  }
}

/**
 * Enter commits (via blur), Escape abandons.
 *
 * ‏`multiline` הופך את Enter לירידת שורה — בהערה, שהיא פרוזה, זה מה ש-Enter
 * אומר — ומשאיר את השמירה ל-Ctrl/⌘+Enter ולעזיבת התא.
 */
function editorKeys(close: () => void, multiline = false) {
  return (e: React.KeyboardEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    if (e.key === 'Escape') {
      e.preventDefault()
      close()
    } else if (e.key === 'Enter' && (!multiline || e.ctrlKey || e.metaKey)) {
      e.preventDefault()
      e.currentTarget.blur()
    }
  }
}

/* ===== the editors ======================================================== */

function TimeCell({
  row,
  canEdit,
  patch,
  field,
  label,
}: CellContext & { field: 'warehouse_start_time' | 'onsite_start_time'; label: string }) {
  const value = fmtTime(row[field])
  return (
    <Editable
      canEdit={canEdit}
      view={value ? <Clip className="tabular" dir="ltr">{value}</Clip> : <Muted />}
      edit={(close) => (
        <input
          type="time"
          ref={openEditor}
          aria-label={label}
          defaultValue={value}
          onKeyDown={editorKeys(close)}
          onBlur={(e) => {
            const v = e.target.value || null
            if ((v ?? '') !== value) patch(row, { [field]: v })
            close()
          }}
          className={INLINE}
        />
      )}
    />
  )
}

function NumberCell({
  canEdit,
  view,
  value,
  step,
  label,
  onCommit,
}: {
  canEdit: boolean
  view: ReactNode
  value: number | null
  step?: string
  label: string
  onCommit: (v: number | null) => void
}) {
  return (
    <Editable
      canEdit={canEdit}
      view={view}
      edit={(close) => (
        <input
          type="number"
          min="0"
          step={step}
          ref={openEditor}
          aria-label={label}
          defaultValue={value ?? ''}
          onKeyDown={editorKeys(close)}
          onBlur={(e) => {
            const v = e.target.value === '' ? null : Number(e.target.value)
            if (v !== value) onCommit(v)
            close()
          }}
          className={INLINE}
        />
      )}
    />
  )
}

/* ===== the pickers ========================================================
   One popover for every cell whose value comes from a list. It replaced the
   native `<select>`, which brought a disclosure arrow the board did not want
   and could only ever hold one value — and half of these cells are sets.   */

/** its own component so the double-press hook is not called from a render prop */
function PickTrigger({
  toggle,
  aria,
  view,
}: {
  toggle: () => void
  aria: Record<string, unknown>
  view: ReactNode
}) {
  const armed = useArmed(toggle)
  return (
    <button type="button" {...aria} {...armed}>
      {view}
    </button>
  )
}

interface PickOption {
  id: string
  label: string
  hint?: string
  checked: boolean
  disabled?: boolean
}

function PickCell({
  canEdit,
  view,
  groups,
  onToggle,
  empty,
}: {
  canEdit: boolean
  view: ReactNode
  /** `multi` decides only which control is drawn — the caller owns the writes */
  groups: { key: string; label?: string; multi: boolean; options: PickOption[]; note?: string }[]
  onToggle: (groupKey: string, id: string, on: boolean) => void
  empty: string
}) {
  const total = groups.reduce((n, g) => n + g.options.length, 0)
  if (!canEdit) return <>{view}</>
  return (
    <Popover
      className="block"
      trigger={({ toggle, ...aria }) => <PickTrigger toggle={toggle} aria={aria} view={view} />}
    >
      {(close) => (
        <div className="max-h-80 w-56 overflow-y-auto p-1">
          {total === 0 && <p className="px-2 py-1.5 type-caption text-ink-tertiary">{empty}</p>}
          {groups.map((g) => (
            <div key={g.key}>
              {g.label && g.options.length > 0 && (
                <p className="px-2 pb-0.5 pt-1.5 type-overline text-ink-tertiary">{g.label}</p>
              )}
              {g.options.map((o) =>
                g.multi ? (
                  <div key={o.id} className="px-2 py-1">
                    <Checkbox
                      label={o.hint ? `${o.label} · ${o.hint}` : o.label}
                      checked={o.checked}
                      disabled={o.disabled}
                      onChange={() => onToggle(g.key, o.id, !o.checked)}
                    />
                  </div>
                ) : (
                  /* deliberately not a radio: clicking the option that is
                     already chosen is how a cell is cleared, and a checked
                     radio fires no change event at all */
                  <button
                    key={o.id}
                    type="button"
                    disabled={o.disabled}
                    onClick={() => {
                      onToggle(g.key, o.id, !o.checked)
                      /* a set stays open — you are usually adding two or three
                         at once — but a single choice is finished by making it */
                      close()
                    }}
                    className={cx(
                      'flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-start type-body transition-colors hover:bg-hover disabled:opacity-55',
                      o.checked && 'font-semibold text-primary-text',
                    )}
                  >
                    <span aria-hidden className="w-3.5 shrink-0 text-center">
                      {o.checked ? '✓' : ''}
                    </span>
                    <span className="truncate">{o.hint ? `${o.label} · ${o.hint}` : o.label}</span>
                  </button>
                ),
              )}
              {g.note && <p className="px-2 py-1 type-caption text-ink-tertiary">{g.note}</p>}
            </div>
          ))}
        </div>
      )}
    </Popover>
  )
}

/**
 * תא שהעריכה שלו נפתחת בפאנל ולא בבורר.
 *
 * אותה מחווה בדיוק כמו כל תא אחר — לחיצה כפולה — אבל מה שנפתח הוא המסך
 * שעונה על כל השאלה ולא רק על החלק שנכנס בתפריט: מי משובץ *ומאיפה הוא
 * מתחיל*, לאיזה קבלן *ובאיזה תעריף וכמה עובדים*.
 */
function PanelCell({
  canEdit,
  view,
  onOpen,
}: {
  canEdit: boolean
  view: ReactNode
  onOpen: () => void
}) {
  const armed = useArmed(onOpen)
  if (!canEdit) return <>{view}</>
  return (
    <button type="button" {...armed}>
      {view}
    </button>
  )
}

/** the trucks a row currently carries, from the view's ordered list */
function truckNames(row: WorkBoardRow): string[] {
  const list = row.truck_list ?? []
  if (list.length > 0) return list.map((t) => t.name)
  return row.truck_name ? [row.truck_name] : []
}

/**
 * More than one truck goes out on a big event, so the cell is a set and not a
 * choice. The order is kept: the first truck is the one that stays in
 * `truck_id`, which is what pricing, attendance and the shift board read.
 */
function TruckCell({ row, canEdit, patch, lookups }: CellContext) {
  const selected = row.truck_ids ?? (row.truck_id ? [row.truck_id] : [])
  const names = truckNames(row)
  const label = names.join(', ') || row.truck_free_text || ''
  const view = label ? <Clip>{label}</Clip> : <Muted />

  return (
    <PickCell
      canEdit={canEdit}
      view={view}
      empty="אין משאיות פעילות"
      groups={[
        {
          key: 'trucks',
          multi: true,
          options: lookups
            .trucksFor(row.customer_id)
            /* משאית שכבר שובצה לשורה נשארת בבורר גם אם הושבתה או הוסרה
               מרשימת הלקוח — אחרת היא הייתה נעלמת מהתא בלי שאיש הסיר אותה */
            .filter((t) => t.is_active || selected.includes(t.id))
            .map((t) => ({ id: t.id, label: t.name, checked: selected.includes(t.id) })),
        },
      ]}
      onToggle={(_g, id, on) =>
        patch(row, { truck_ids: on ? [...selected, id] : selected.filter((x) => x !== id) })
      }
    />
  )
}

function MethodCell({ row, canEdit, patch, lookups }: CellContext) {
  return (
    <PickCell
      canEdit={canEdit}
      view={row.execution_method_name ? <Clip>{row.execution_method_name}</Clip> : <Muted />}
      empty="אין אופני ביצוע פעילים"
      groups={[
        {
          key: 'methods',
          multi: false,
          options: lookups.methods
            .filter((m) => m.is_active || m.id === row.execution_method_id)
            .map((m) => ({ id: m.id, label: m.name, checked: m.id === row.execution_method_id })),
        },
      ]}
      /* picking the row that is already picked clears it — the only way back
         to "no method" once one was chosen */
      onToggle={(_g, id, on) => patch(row, { execution_method_id: on ? id : null })}
    />
  )
}

function StatusCell({ row, canEdit, can, patch, lookups }: CellContext) {
  // פרסום ("משובץ") הוא מפתח נפרד מ-tasks.change_status. מי שאינו רשאי לפרסם
  // לא רואה את האפשרות — אך היא נשארת כשזה הסטטוס הנוכחי של השורה. ומאז 0117
  // גם היציאה ממנה שמורה לו, ולכן שורה שכבר פורסמה נעולה בפניו לגמרי.
  const canPublish = can(PERM.TASKS_PUBLISH)
  const { locked, options } = statusOptions(lookups.statuses, row.status_id, canPublish)
  return (
    <PickCell
      canEdit={canEdit && !locked}
      view={
        <span className="flex justify-center px-1.5 py-0.5">
          <StatusPill color={row.status_color}>{row.status_name}</StatusPill>
        </span>
      }
      empty="אין סטטוסים"
      groups={[
        {
          key: 'statuses',
          multi: false,
          options: options.map((s) => ({ id: s.id, label: s.name, checked: s.id === row.status_id })),
        },
      ]}
      /* a status is mandatory, so re-picking the current one is a no-op */
      onToggle={(_g, id, on) => on && patch(row, { status_id: id })}
    />
  )
}

/**
 * תא הקבלן — רב-בחירה מאז 0096: משימה יכולה לשאת כמה קבלנים, ו-`contractor_list`
 * הוא מקור האמת לרשימה.
 *
 * הבורר שהיה כאן ידע לענות רק על "לאיזה קבלן", וזו השאלה הקטנה: מה שנקבע
 * בהאצלה הוא גם כמה עובדים הוא מביא, מאיזה אתר, באיזה תעריף ומי מהסגל שלו
 * יוצא. מ-0108 התא נפתח לפאנל שמחזיק את כולן, ולכן גם ההוספה וההסרה עברו
 * לשם — הן ממילא עברו ב-RPC ‏(delegate/undelegate) ולא בכתיבה ל-
 * `tasks.contractor_id`, שהוא כיום רק שיקוף הקבלן הראשי.
 */
function ContractorCell({ row, canEdit, lookups }: CellContext) {
  const delegated = row.contractor_list ?? []
  const names = delegated.map((c) => c.name).join(', ')
  return (
    <PanelCell
      canEdit={canEdit}
      view={names ? <Clip>{names}</Clip> : <Muted />}
      onOpen={() => lookups.openPanel(row.id, 'contractor')}
    />
  )
}

/**
 * ראש הצוות — פנימי או של קבלן (0128). עד אז התא קרא רק שיבוץ פנימי, וראש
 * הצוות שהקבלן מינה נבלע ברשימת "צוות" עם כל השאר.
 */
function TeamLeadCell({ row, canEdit, lookups }: CellContext) {
  const canOwnStaff = lookups.canAssignOwnStaff && row.performed_by === 'arko'
  return (
    <PanelCell
      canEdit={canEdit || canOwnStaff}
      view={
        row.team_lead_name ? (
          <span className="flex items-center justify-center gap-0.5 overflow-hidden">
            {row.team_lead_kind === 'contractor' && <span className="shrink-0 text-[9px]">👷</span>}
            {row.team_lead_kind === 'customer' && <span className="shrink-0 text-[9px]">🏢</span>}
            <Clip>{row.team_lead_name}</Clip>
          </span>
        ) : (
          <Muted />
        )
      }
      onOpen={() => lookups.openPanel(row.id, 'staffing')}
    />
  )
}

/**
 * Everyone assigned, by name, one per line — and the place they are assigned
 * from. Staff, drivers and a delegated contractor's crew read as one list,
 * because in the field they are one crew.
 *
 * העריכה נפתחת בפאנל (0108) ולא בבורר שהיה כאן: הבורר ידע לענות רק על "מי",
 * ומחצית מהשאלה של התא הזה היא "מאיפה" — מי יוצא מהמחסן ומי מגיע לשטח, ומי
 * מהנהגים נוסע באיזו משאית. שתי אלה קובעות את שעת ההתחלה במשמרת ואת המיקום
 * שמולו נמדדת ההחתמה, והן מעולם לא נכנסו לתפריט ברוחב תא.
 */
function TeamCell({ row, canEdit, can, lookups }: CellContext) {
  const canDriver = can(PERM.TASKS_ASSIGN_DRIVER)
  const contractorWorkers = row.contractor_worker_list ?? []
  /* סגל של לקוח שמבצע בעצמו (0134). אותו תא בדיוק — בשטח הם צוות אחד. */
  const customerWorkers = row.customer_worker_list ?? []
  /* שיבוץ עובדי קבלן אינו עובר ב-`canEdit`: היא מכפילה ב-`board.inline_edit`,
     שאין למנהל קבלן — והתא הזה הוא הדבר האחד שהוא כן עורך. */
  const canContractor = lookups.canAssignContractor && !!row.contractor_id
  /* ‏0133: על משימה שסומנה "ארקו" זה הכרטיס היחיד שיהיה בפאנל, ולכן זה גם
     התנאי היחיד שפותח את התא לצד ההרשאות המשרדיות. */
  const canOwnStaff = lookups.canAssignOwnStaff && row.performed_by === 'arko'

  /* אותו אדם ששובץ גם כעובד וגם כנהג מופיע פעם אחת, עם שני האייקונים (0094).
     איחוד לפי profile_id; עובד קבלן נשאר נפרד (מרחב זהות אחר). */
  const staffMap = new Map<
    string,
    { name: string; roles: Set<'worker' | 'driver'>; site?: 'field' | 'warehouse'; truck?: string | null }
  >()
  for (const w of row.workers ?? []) {
    const e = staffMap.get(w.profile_id) ?? { name: w.name, roles: new Set(), site: w.work_site }
    e.roles.add('worker')
    staffMap.set(w.profile_id, e)
  }
  for (const d of row.drivers ?? []) {
    const e = staffMap.get(d.profile_id) ?? { name: d.name, roles: new Set(), site: d.work_site }
    e.roles.add('driver')
    if (d.truck_name) e.truck = d.truck_name
    staffMap.set(d.profile_id, e)
  }
  const people = [
    ...[...staffMap.entries()].map(([id, e]) => ({
      key: `s:${id}`,
      name: e.truck ? `${e.name} · ${e.truck}` : e.name,
      /* עובד רגיל נשאר בלי אייקון; ריבוי תפקידים מציג נהג+עובד. */
      mark:
        e.roles.size > 1
          ? ['driver', 'worker'].filter((r) => e.roles.has(r as 'worker' | 'driver')).map((r) => (r === 'driver' ? '🚚' : '🦺')).join('')
          : e.roles.has('driver')
            ? '🚚'
            : '',
      site: e.site,
    })),
    /* ראש צוות של קבלן יושב מ-0128 בשורה של ראש הצוות, ולכן אינו חוזר כאן:
       אדם אחד, מקום אחד. שאר הסגל — נהג הקבלן ועובדיו — נשאר. */
    ...contractorWorkers
      .filter((w) => w.role !== 'team_lead')
      .map((w) => ({
        key: `c:${w.id}`,
        name: w.name,
        mark: w.role === 'driver' ? '👷🚚' : '👷',
        site: w.work_site,
      })),
    ...customerWorkers
      .filter((w) => w.role !== 'team_lead')
      .map((w) => ({
        key: `o:${w.id}`,
        name: w.truck_name ? `${w.name} · ${w.truck_name}` : w.name,
        mark: w.role === 'driver' ? '🏢🚚' : '🏢',
        site: w.work_site,
      })),
  ]

  const view =
    people.length === 0 ? (
      <Muted>לא שובץ</Muted>
    ) : (
      <span className="flex w-full flex-col items-stretch">
        {people.map((p) => (
          /* exactly one `--vl-board-line` per person, which is the unit the
             row's height was computed in — the whole crew is on screen and
             nothing here scrolls */
          <span
            key={p.key}
            className={cx('flex items-center justify-center gap-0.5 overflow-hidden leading-none', FS)}
            style={{ height: 'var(--vl-board-line, 1rem)' }}
          >
            {p.mark && <span className="shrink-0 text-[9px]">{p.mark}</span>}
            {/* מי שיוצא מהמחסן מתחיל בשעה אחרת מכולם, ולכן הסימון נשאר לצד השם */}
            {p.site === 'warehouse' && <span className="shrink-0 text-[9px]">🏭</span>}
            <Clip tight>{p.name}</Clip>
          </span>
        ))}
      </span>
    )

  return (
    <PanelCell
      canEdit={canEdit || canDriver || canContractor || canOwnStaff}
      view={view}
      onOpen={() => lookups.openPanel(row.id, 'staffing')}
    />
  )
}

/**
 * The board is transposed: what used to be 22 columns is now 19 rows, one per
 * field, read down a task's column. Every editor keeps the original
 * optimistic-concurrency write — only the wrapper changed.
 */
export const BOARD_FIELDS: BoardField[] = [
  /* No `customer` row: the column's own header is painted in the customer's
     colour and carries the name, so a row repeating it was 1/19 of the board
     spent saying the same thing twice. */
  {
    key: 'end_client',
    label: 'לקוח',
    render: ({ row }) => <Clip>{row.end_client_name ?? row.title ?? '—'}</Clip>,
  },
  {
    key: 'event_number',
    label: "מס' אירוע",
    render: ({ row }) => (row.event_number ? <Clip className="tabular">{row.event_number}</Clip> : <Muted />),
  },
  {
    key: 'location',
    label: 'מיקום',
    render: ({ row }) =>
      row.location_text ? (
        /* הבועה נושאת את הכתובת המלאה, התא את המקוצרת */
        <Clip title={row.location_text}>{shortAddress(row.location_text)}</Clip>
      ) : (
        <Muted />
      ),
  },
  {
    key: 'task_type',
    label: 'סוג משימה',
    render: ({ row }) => <Clip className="font-medium">{row.task_type_name}</Clip>,
  },
  {
    key: 'warehouse_start_time',
    editPerm: PERM.TASKS_RESCHEDULE,
    label: 'התחלה במחסן',
    render: (ctx) => (
      <TimeCell {...ctx} field="warehouse_start_time" label={`התחלה במחסן — ${ctx.row.task_type_name}`} />
    ),
  },
  {
    key: 'onsite_start_time',
    editPerm: PERM.TASKS_RESCHEDULE,
    label: 'התחלה בשטח',
    render: (ctx) => (
      <TimeCell {...ctx} field="onsite_start_time" label={`התחלה בשטח — ${ctx.row.task_type_name}`} />
    ),
  },
  {
    key: 'onsite_end_time',
    label: 'סיום בשטח',
    render: ({ row }) =>
      row.onsite_end_time ? (
        <Clip className="tabular" dir="ltr">
          {fmtTime(row.onsite_end_time)}
        </Clip>
      ) : (
        <Muted />
      ),
  },
  {
    key: 'hours_count',
    editPerm: PERM.TASKS_RESCHEDULE,
    label: 'משך',
    render: ({ row, canEdit, patch }) => (
      <NumberCell
        canEdit={canEdit}
        value={row.hours_count}
        step="0.5"
        label="משך בשעות"
        view={
          row.hours_count != null ? (
            <Clip className="tabular" title={fmtHours(row.hours_count)}>
              {row.hours_count}
            </Clip>
          ) : (
            <Muted />
          )
        }
        onCommit={(v) => patch(row, { hours_count: v })}
      />
    ),
  },
  {
    key: 'worker_count',
    editPerm: PERM.TASKS_CHANGE_WORKER_COUNT,
    label: 'כמות עובדים',
    /* the number required, on its own. The "3/5 משובצים" badge that used to
       ride alongside it answered a question the צוות row below already answers
       by name, and it turned a one-figure cell into two competing figures. */
    render: ({ row, canEdit, patch }) => (
      <NumberCell
        canEdit={canEdit}
        value={row.worker_count}
        label="כמות עובדים נדרשת"
        view={<span className={cx('tabular', FS)}>{row.worker_count}</span>}
        onCommit={(v) => patch(row, { worker_count: v ?? 0 })}
      />
    ),
  },
  {
    key: 'event_truck_count',
    label: 'משאיות באירוע',
    render: ({ row }) =>
      row.event_truck_count != null ? <Clip className="tabular">{row.event_truck_count}</Clip> : <Muted />,
  },
  {
    key: 'volume_m',
    label: 'נפח',
    render: ({ row }) => (row.volume_m != null ? <Clip className="tabular">{row.volume_m}</Clip> : <Muted />),
  },
  {
    key: 'truck',
    editPerm: PERM.TASKS_CHANGE_TRUCK,
    label: 'משאיות',
    render: (ctx) => <TruckCell {...ctx} />,
  },
  {
    key: 'execution_method',
    editPerm: PERM.TASKS_CHANGE_EXECUTION_METHOD,
    label: 'אופן ביצוע',
    render: (ctx) => <MethodCell {...ctx} />,
  },
  {
    key: 'team_lead',
    viewPerm: PERM.BOARD_VIEW_STAFFING,
    editPerm: PERM.TASKS_ASSIGN_TEAM_LEAD,
    label: 'ראש צוות',
    render: (ctx) => <TeamLeadCell {...ctx} />,
  },
  {
    key: 'team',
    viewPerm: PERM.BOARD_VIEW_STAFFING,
    editPerm: PERM.TASKS_ASSIGN_WORKER,
    label: 'צוות',
    tall: true,
    render: (ctx) => <TeamCell {...ctx} />,
  },
  {
    key: 'contractor',
    viewPerm: PERM.BOARD_VIEW_STAFFING,
    editPerm: PERM.TASKS_DELEGATE,
    label: 'קבלן',
    render: (ctx) => <ContractorCell {...ctx} />,
  },
  {
    /* כמה עובדים הקבלן צריך להביא — לקריאה בלבד בלו״ז; נקבע בהאצלה (0095). */
    key: 'contractor_worker_count',
    viewPerm: PERM.BOARD_VIEW_STAFFING,
    label: 'עובדים להביא',
    render: ({ row }) =>
      row.contractor_worker_count != null ? (
        <Clip className="tabular">{row.contractor_worker_count}</Clip>
      ) : (
        <Muted />
      ),
  },
  {
    key: 'status',
    editPerm: PERM.TASKS_CHANGE_STATUS,
    label: 'סטטוס',
    render: (ctx) => <StatusCell {...ctx} />,
  },
  {
    key: 'notes',
    editPerm: PERM.TASKS_EDIT_NOTES,
    label: 'הערות',
    /* a note is the one field on the board that is prose, and a single line of
       a 74px column is not enough of it to be worth reading. `grow` is the
       floor — the board raises the row to the longest note it is showing. */
    grow: 2,
    render: ({ row, canEdit, patch, lookups }) => (
      <Editable
        canEdit={canEdit}
        view={
          row.notes ? (
            /* הבועה נושאת את ההערה כפי שנכתבה, כולל ירידות שורה, כדי שגם מה
               שלא נכנס בשורות שעל הלוח ייקרא במלואו */
            <Clip
              lines={lookups.noteLines}
              /* אותה יחידת שורה שהגובה נמדד בה, אחרת השורה האחרונה נחתכת
                 בשבריר פיקסל — `--vl-board-line` נקבע על מיכל הלוח. */
              className="leading-[var(--vl-board-line,1rem)]"
              title={<span className="block whitespace-pre-wrap text-start">{row.notes}</span>}
            >
              {row.notes}
            </Clip>
          ) : (
            <Muted>{canEdit ? 'הוספת הערה' : undefined}</Muted>
          )
        }
        /* ‏textarea ולא input: ההערה היא השדה היחיד בלוח שיש בו ירידות שורה,
           ו-`input` היה מוחק אותן בשקט בכל עריכה — גם כשלא נגעו בהן. */
        edit={(close) => (
          <textarea
            ref={openEditor}
            aria-label="הערות"
            rows={lookups.noteLines}
            defaultValue={row.notes ?? ''}
            onKeyDown={editorKeys(close, true)}
            onBlur={(e) => {
              const v = e.target.value.trim() || null
              if (v !== row.notes) patch(row, { notes: v })
              close()
            }}
            className={cx(INLINE, 'max-h-full resize-none overflow-auto text-start leading-[var(--vl-board-line,1rem)] placeholder:text-ink-tertiary')}
          />
        )}
      />
    ),
  },
]

export const DEFAULT_HIDDEN_FIELDS = ['event_truck_count', 'volume_m']
