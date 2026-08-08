import { useLayoutEffect, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { Checkbox, Popover, StatusPill, Tooltip, cx } from '../../components/ui'
import { fmtHours, fmtTime } from '../../lib/dates'
import type {
  Contractor,
  ExecutionMethod,
  Profile,
  StaffRole,
  Status,
  Truck,
  WorkBoardRow,
} from '../../types/domain'
import { PERM } from '../../lib/permissions'

export interface BoardLookups {
  statuses: Status[]
  trucks: Truck[]
  methods: ExecutionMethod[]
  contractors: Contractor[]
  staff: Profile[]
}

export interface CellContext {
  row: WorkBoardRow
  canEdit: boolean
  /** any *other* key a cell needs — the team cell spans two assignment rights */
  can: (perm?: string) => boolean
  patch: (row: WorkBoardRow, patch: Record<string, unknown>) => void
  /** staffing is a row in task_assignments, not a column on tasks */
  assign: (row: WorkBoardRow, role: StaffRole, profileId: string, on: boolean) => void
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
}: {
  children: ReactNode
  className?: string
  dir?: 'ltr' | 'rtl'
  /** what the bubble says, when it isn't simply the text itself */
  title?: ReactNode
}) {
  const ref = useRef<HTMLSpanElement>(null)
  const [clipped, setClipped] = useState(false)

  useLayoutEffect(() => {
    const el = ref.current
    if (el) setClipped(el.scrollWidth > el.clientWidth + 1)
  })

  return (
    <Tooltip content={clipped ? (title ?? children) : null} openOnClick>
      <span
        ref={ref}
        dir={dir}
        className={cx('block w-full truncate px-1.5 py-0.5 text-center', clipped && 'cursor-help', FS, className)}
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
function openEditor(el: HTMLInputElement | null) {
  if (!el) return
  el.focus()
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

/** Enter commits (via blur), Escape abandons */
function editorKeys(close: () => void) {
  return (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Escape') {
      e.preventDefault()
      close()
    } else if (e.key === 'Enter') {
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
          options: lookups.trucks
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

function StatusCell({ row, canEdit, patch, lookups }: CellContext) {
  return (
    <PickCell
      canEdit={canEdit}
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
          options: lookups.statuses.map((s) => ({ id: s.id, label: s.name, checked: s.id === row.status_id })),
        },
      ]}
      /* a status is mandatory, so re-picking the current one is a no-op */
      onToggle={(_g, id, on) => on && patch(row, { status_id: id })}
    />
  )
}

function ContractorCell({ row, canEdit, patch, lookups }: CellContext) {
  return (
    <PickCell
      canEdit={canEdit}
      view={row.contractor_name ? <Clip>{row.contractor_name}</Clip> : <Muted />}
      empty="אין קבלנים פעילים"
      groups={[
        {
          key: 'contractors',
          multi: false,
          options: lookups.contractors
            .filter((c) => c.is_active || c.id === row.contractor_id)
            .map((c) => ({ id: c.id, label: c.name, checked: c.id === row.contractor_id })),
        },
      ]}
      onToggle={(_g, id, on) => patch(row, { contractor_id: on ? id : null })}
    />
  )
}

/** staff who hold a given role — the same filter the task drawer applies */
function staffFor(staff: Profile[], role: StaffRole) {
  return staff.filter((p) => (p.staff_roles ?? []).some((r) => r.role === role))
}

function TeamLeadCell({ row, canEdit, assign, lookups }: CellContext) {
  return (
    <PickCell
      canEdit={canEdit}
      view={row.team_lead_name ? <Clip>{row.team_lead_name}</Clip> : <Muted />}
      empty="אין עובדים עם תפקיד ראש צוות"
      groups={[
        {
          key: 'leads',
          multi: false,
          options: staffFor(lookups.staff, 'team_lead').map((p) => ({
            id: p.id,
            label: p.full_name,
            checked: p.id === row.team_lead_id,
          })),
        },
      ]}
      onToggle={(_g, id, on) => assign(row, 'team_lead', id, on)}
    />
  )
}

/**
 * Everyone assigned, by name, one per line — and now the place they are
 * assigned from. Workers and drivers are rows in task_assignments, so the
 * picker writes there rather than through the task patch; contractor staff
 * belong to a delegated contractor and stay read-only, because choosing them
 * is a question about that contractor's roster and not about this cell.
 */
function TeamCell({ row, canEdit, can, assign, lookups }: CellContext) {
  const workerIds = (row.workers ?? []).map((w) => w.profile_id)
  const driverIds = (row.drivers ?? []).map((d) => d.profile_id)
  const canDriver = can(PERM.TASKS_ASSIGN_DRIVER)
  const contractorWorkers = row.contractor_worker_list ?? []

  const people = [
    ...(row.workers ?? []).map((w) => ({ key: `w:${w.profile_id}`, name: w.name, mark: '', site: w.work_site })),
    ...(row.drivers ?? []).map((d) => ({
      key: `d:${d.profile_id}`,
      name: d.truck_name ? `${d.name} · ${d.truck_name}` : d.name,
      mark: '🚚',
      site: d.work_site,
    })),
    ...contractorWorkers.map((w) => ({ key: `c:${w.id}`, name: w.name, mark: '👷', site: w.work_site })),
  ]

  const view =
    people.length === 0 ? (
      <Muted>לא שובץ</Muted>
    ) : (
      <span className="flex w-full flex-col items-stretch gap-px px-1 py-0.5">
        {people.map((p) => (
          <span key={p.key} className={cx('flex items-center gap-1 text-start', FS)}>
            {p.mark && <span className="shrink-0 text-[10px]">{p.mark}</span>}
            {/* מי שיוצא מהמחסן מתחיל בשעה אחרת מכולם, ולכן הסימון נשאר לצד השם */}
            {p.site === 'warehouse' && <span className="shrink-0 text-[10px]">🏭</span>}
            <Clip className="text-start">{p.name}</Clip>
          </span>
        ))}
      </span>
    )

  return (
    <PickCell
      canEdit={canEdit || canDriver}
      view={view}
      empty="אין עובדים לשיבוץ"
      groups={[
        {
          key: 'worker',
          label: 'עובדים',
          multi: true,
          options: canEdit
            ? staffFor(lookups.staff, 'worker').map((p) => ({
                id: p.id,
                label: p.full_name,
                checked: workerIds.includes(p.id),
              }))
            : [],
        },
        {
          key: 'driver',
          label: 'נהגים',
          multi: true,
          options: canDriver
            ? staffFor(lookups.staff, 'driver').map((p) => ({
                id: p.id,
                label: p.full_name,
                checked: driverIds.includes(p.id),
              }))
            : [],
          note:
            contractorWorkers.length > 0
              ? `${contractorWorkers.length} עובדי קבלן משובצים — שינוי שלהם נעשה מתוך המשימה`
              : undefined,
        },
      ]}
      onToggle={(group, id, on) => assign(row, group as StaffRole, id, on)}
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
    label: 'לקוח האירוע',
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
    render: ({ row }) => (row.location_text ? <Clip>{row.location_text}</Clip> : <Muted />),
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
    render: ({ row, canEdit, patch }) => {
      const assigned = (row.workers?.length ?? 0) + (row.contractor_worker_list?.length ?? 0)
      const short = row.worker_count > 0 && assigned < row.worker_count
      return (
        <NumberCell
          canEdit={canEdit}
          value={row.worker_count}
          label="כמות עובדים נדרשת"
          view={
            <span className="flex items-center justify-center gap-1">
              <span className={cx('tabular', FS)}>{row.worker_count}</span>
              {short && (
                <Tooltip content={`משובצים ${assigned} מתוך ${row.worker_count}`}>
                  <span className="shrink-0 rounded bg-warning-subtle px-1 text-[10px] font-bold tabular text-warning-text">
                    {assigned}/{row.worker_count}
                  </span>
                </Tooltip>
              )}
            </span>
          }
          onCommit={(v) => patch(row, { worker_count: v ?? 0 })}
        />
      )
    },
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
    key: 'status',
    editPerm: PERM.TASKS_CHANGE_STATUS,
    label: 'סטטוס',
    render: (ctx) => <StatusCell {...ctx} />,
  },
  {
    key: 'notes',
    editPerm: PERM.TASKS_EDIT_NOTES,
    label: 'הערות',
    render: ({ row, canEdit, patch }) => (
      <Editable
        canEdit={canEdit}
        view={row.notes ? <Clip>{row.notes}</Clip> : <Muted>{canEdit ? 'הוספת הערה' : undefined}</Muted>}
        edit={(close) => (
          <input
            ref={openEditor}
            aria-label="הערות"
            defaultValue={row.notes ?? ''}
            onKeyDown={editorKeys(close)}
            onBlur={(e) => {
              const v = e.target.value || null
              if (v !== row.notes) patch(row, { notes: v })
              close()
            }}
            className={cx(INLINE, 'placeholder:text-ink-tertiary')}
          />
        )}
      />
    ),
  },
]

export const DEFAULT_HIDDEN_FIELDS = ['event_truck_count', 'volume_m']
