import type { ReactNode } from 'react'
import { Checkbox, Popover, StatusPill, Tooltip, cx } from '../../components/ui'
import { fmtHours, fmtTime } from '../../lib/dates'
import type { ExecutionMethod, Status, Truck, WorkBoardRow } from '../../types/domain'
import { PERM } from '../../lib/permissions'

export interface BoardLookups {
  statuses: Status[]
  trucks: Truck[]
  methods: ExecutionMethod[]
}

export interface CellContext {
  row: WorkBoardRow
  canEdit: boolean
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
  /**
   * The cell holds its own trigger (a popover, a list) rather than a plain
   * input, so the board must not try to focus something inside it on click.
   */
  selfEditing?: boolean
}

/**
 * Cell text sizes off one variable the board sets on its own container, so the
 * minimal density and the phone can shrink every cell at once instead of each
 * field carrying its own literal.
 */
const FS = 'text-[length:var(--vl-board-fs,0.8125rem)]'

/* Inline editors share one look: invisible until hovered, so a screen full of
   editable cells doesn't read as a screen full of form controls. */
const INLINE =
  `w-full min-w-0 rounded border border-transparent bg-transparent px-1.5 py-0.5 text-center ${FS} tabular ` +
  'transition-colors duration-150 hover:border-line hover:bg-surface ' +
  'focus:border-primary focus:bg-surface focus:outline-none focus:ring-2 focus:ring-[var(--vl-focus-ring)] ' +
  'disabled:pointer-events-none disabled:opacity-70'

/**
 * The same editor look for a `<select>`, minus the platform's own disclosure
 * arrow: in a 19-row grid the arrows read as a column of chevrons rather than
 * as an affordance, and the cell is clickable in its entirety anyway.
 */
const INLINE_SELECT = cx(INLINE, 'cursor-pointer truncate appearance-none [&::-ms-expand]:hidden')

const READONLY = `block w-full truncate px-1.5 py-0.5 text-center ${FS}`

function Muted({ children }: { children?: ReactNode }) {
  return <span className={cx('block w-full px-1.5 text-center text-ink-tertiary', FS)}>{children ?? '—'}</span>
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
  const label = names.length > 0 ? names.join(', ') : row.truck_free_text || '—'
  const active = lookups.trucks.filter((t) => t.is_active || selected.includes(t.id))

  const toggle = (id: string) => {
    const next = selected.includes(id) ? selected.filter((x) => x !== id) : [...selected, id]
    patch(row, { truck_ids: next })
  }

  if (!canEdit)
    return names.length > 0 || row.truck_free_text ? (
      <Tooltip content={label}>
        <span className={READONLY}>{label}</span>
      </Tooltip>
    ) : (
      <Muted />
    )

  return (
    <Popover
      className="block px-1"
      trigger={({ toggle: open, ...aria }) => (
        <button
          type="button"
          onClick={open}
          {...aria}
          title={label}
          className={cx(INLINE, 'cursor-pointer truncate')}
        >
          {names.length > 0 ? (
            <span className="flex items-center justify-center gap-1">
              <span className="truncate">{names[0]}</span>
              {names.length > 1 && (
                <span className="shrink-0 rounded bg-subtle px-1 text-[10px] font-bold tabular text-ink-secondary">
                  +{names.length - 1}
                </span>
              )}
            </span>
          ) : (
            <span className="text-ink-tertiary">{row.truck_free_text || '—'}</span>
          )}
        </button>
      )}
    >
      {() => (
        <div className="max-h-72 w-52 overflow-y-auto p-1">
          {active.length === 0 ? (
            <p className="px-2 py-1.5 type-caption text-ink-tertiary">אין משאיות פעילות</p>
          ) : (
            active.map((t) => (
              <div key={t.id} className="px-2 py-1">
                <Checkbox label={t.name} checked={selected.includes(t.id)} onChange={() => toggle(t.id)} />
              </div>
            ))
          )}
        </div>
      )}
    </Popover>
  )
}

/**
 * Everyone assigned, by name, one per line. The counters this replaced fit in
 * a single row but answered the wrong question: a dispatcher looking at the
 * board wants to know *who* is on the job, and had to open the task to find
 * out. The board grows the row instead — see `teamRowHeight` on the page.
 */
function TeamCell({ row }: CellContext) {
  const people = [
    ...(row.workers ?? []).map((w) => ({ key: `w:${w.profile_id}`, name: w.name, mark: '', site: w.work_site })),
    ...(row.drivers ?? []).map((d) => ({
      key: `d:${d.profile_id}`,
      name: d.truck_name ? `${d.name} · ${d.truck_name}` : d.name,
      mark: '🚚',
      site: d.work_site,
    })),
    ...(row.contractor_worker_list ?? []).map((w) => ({
      key: `c:${w.id}`,
      name: w.name,
      mark: '👷',
      site: w.work_site,
    })),
  ]
  if (people.length === 0) return <Muted>לא שובץ</Muted>

  return (
    <span className="flex w-full flex-col items-stretch gap-px px-1 py-0.5">
      {people.map((p) => (
        <span key={p.key} className={cx('flex items-center gap-1 truncate text-start', FS)} title={p.name}>
          {p.mark && <span className="shrink-0 text-[10px]">{p.mark}</span>}
          {/* מי שיוצא מהמחסן מתחיל בשעה אחרת מכולם, ולכן הסימון נשאר לצד השם */}
          {p.site === 'warehouse' && (
            <Tooltip content="מתחיל מהמחסן">
              <span className="shrink-0 text-[10px]">🏭</span>
            </Tooltip>
          )}
          <span className="truncate">{p.name}</span>
        </span>
      ))}
    </span>
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
    render: ({ row }) => <span className={READONLY}>{row.end_client_name ?? row.title ?? '—'}</span>,
  },
  {
    key: 'event_number',
    label: "מס' אירוע",
    render: ({ row }) =>
      row.event_number ? <span className={cx(READONLY, 'tabular')}>{row.event_number}</span> : <Muted />,
  },
  {
    key: 'location',
    label: 'מיקום',
    render: ({ row }) =>
      row.location_text ? (
        <Tooltip content={row.location_text}>
          <span className={READONLY}>{row.location_text}</span>
        </Tooltip>
      ) : (
        <Muted />
      ),
  },
  {
    key: 'task_type',
    label: 'סוג משימה',
    render: ({ row }) => <span className={cx(READONLY, 'font-medium')}>{row.task_type_name}</span>,
  },
  {
    key: 'warehouse_start_time',
    editPerm: PERM.TASKS_RESCHEDULE,
    label: 'התחלה במחסן',
    render: ({ row, canEdit, patch }) => (
      <input
        type="time"
        aria-label={`התחלה במחסן — ${row.task_type_name}`}
        defaultValue={fmtTime(row.warehouse_start_time)}
        disabled={!canEdit}
        onBlur={(e) => {
          const v = e.target.value || null
          if ((v ?? '') !== fmtTime(row.warehouse_start_time)) patch(row, { warehouse_start_time: v })
        }}
        className={INLINE}
      />
    ),
  },
  {
    key: 'onsite_start_time',
    editPerm: PERM.TASKS_RESCHEDULE,
    label: 'התחלה בשטח',
    render: ({ row, canEdit, patch }) => (
      <input
        type="time"
        aria-label={`התחלה בשטח — ${row.task_type_name}`}
        defaultValue={fmtTime(row.onsite_start_time)}
        disabled={!canEdit}
        onBlur={(e) => {
          const v = e.target.value || null
          if ((v ?? '') !== fmtTime(row.onsite_start_time)) patch(row, { onsite_start_time: v })
        }}
        className={INLINE}
      />
    ),
  },
  {
    key: 'onsite_end_time',
    label: 'סיום בשטח',
    render: ({ row }) =>
      row.onsite_end_time ? (
        <span className={cx(READONLY, 'tabular')} dir="ltr">
          {fmtTime(row.onsite_end_time)}
        </span>
      ) : (
        <Muted />
      ),
  },
  {
    key: 'hours_count',
    editPerm: PERM.TASKS_RESCHEDULE,
    label: 'משך',
    render: ({ row, canEdit, patch }) => (
      <input
        type="number"
        step="0.5"
        min="0"
        aria-label="משך בשעות"
        title={fmtHours(row.hours_count)}
        defaultValue={row.hours_count ?? ''}
        disabled={!canEdit}
        onBlur={(e) => {
          const v = e.target.value === '' ? null : Number(e.target.value)
          if (v !== row.hours_count) patch(row, { hours_count: v })
        }}
        className={INLINE}
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
        <span className="flex items-center justify-center gap-1">
          <input
            type="number"
            min="0"
            aria-label="כמות עובדים נדרשת"
            defaultValue={row.worker_count}
            disabled={!canEdit}
            onBlur={(e) => {
              const v = Number(e.target.value) || 0
              if (v !== row.worker_count) patch(row, { worker_count: v })
            }}
            className={INLINE}
          />
          {short && (
            <Tooltip content={`משובצים ${assigned} מתוך ${row.worker_count}`}>
              <span className="shrink-0 rounded bg-warning-subtle px-1 text-[10px] font-bold tabular text-warning-text">
                {assigned}/{row.worker_count}
              </span>
            </Tooltip>
          )}
        </span>
      )
    },
  },
  {
    key: 'event_truck_count',
    label: 'משאיות באירוע',
    render: ({ row }) => (row.event_truck_count != null ? <span className={cx(READONLY, 'tabular')}>{row.event_truck_count}</span> : <Muted />),
  },
  {
    key: 'volume_m',
    label: 'נפח',
    render: ({ row }) => (row.volume_m != null ? <span className={cx(READONLY, 'tabular')}>{row.volume_m}</span> : <Muted />),
  },
  {
    key: 'truck',
    editPerm: PERM.TASKS_CHANGE_TRUCK,
    label: 'משאיות',
    selfEditing: true,
    render: (ctx) => <TruckCell {...ctx} />,
  },
  {
    key: 'execution_method',
    editPerm: PERM.TASKS_CHANGE_EXECUTION_METHOD,
    label: 'אופן ביצוע',
    render: ({ row, canEdit, patch, lookups }) => (
      <select
        aria-label="אופן ביצוע"
        value={row.execution_method_id ?? ''}
        disabled={!canEdit}
        onChange={(e) => patch(row, { execution_method_id: e.target.value || null })}
        className={INLINE_SELECT}
      >
        <option value="">—</option>
        {lookups.methods
          .filter((m) => m.is_active)
          .map((m) => (
            <option key={m.id} value={m.id}>
              {m.name}
            </option>
          ))}
      </select>
    ),
  },
  {
    key: 'team_lead',
    viewPerm: PERM.BOARD_VIEW_STAFFING,
    label: 'ראש צוות',
    render: ({ row }) => (row.team_lead_name ? <span className={READONLY}>{row.team_lead_name}</span> : <Muted />),
  },
  {
    key: 'team',
    viewPerm: PERM.BOARD_VIEW_STAFFING,
    label: 'צוות',
    tall: true,
    render: (ctx) => <TeamCell {...ctx} />,
  },
  {
    key: 'contractor',
    viewPerm: PERM.BOARD_VIEW_STAFFING,
    label: 'קבלן',
    render: ({ row }) => (row.contractor_name ? <span className={READONLY}>{row.contractor_name}</span> : <Muted />),
  },
  {
    key: 'status',
    editPerm: PERM.TASKS_CHANGE_STATUS,
    label: 'סטטוס',
    render: ({ row, canEdit, patch, lookups }) =>
      canEdit ? (
        <span className="relative block px-1">
          <select
            aria-label="סטטוס"
            value={row.status_id}
            onChange={(e) => patch(row, { status_id: e.target.value })}
            className="w-full cursor-pointer truncate appearance-none rounded-md border border-transparent px-1.5 py-0.5 text-center text-[0.75rem] font-semibold focus:outline-none focus:ring-2 focus:ring-[var(--vl-focus-ring)] [&::-ms-expand]:hidden"
            style={{
              background: `color-mix(in srgb, ${row.status_color} 20%, transparent)`,
              color: `color-mix(in srgb, ${row.status_color}, black 28%)`,
            }}
          >
            {lookups.statuses.map((s) => (
              <option key={s.id} value={s.id} style={{ color: 'var(--vl-text)', background: 'var(--vl-surface)' }}>
                {s.name}
              </option>
            ))}
          </select>
        </span>
      ) : (
        <span className="flex justify-center px-1.5">
          <StatusPill color={row.status_color}>{row.status_name}</StatusPill>
        </span>
      ),
  },
  {
    key: 'notes',
    editPerm: PERM.TASKS_EDIT_NOTES,
    label: 'הערות',
    render: ({ row, canEdit, patch }) => (
      <input
        aria-label="הערות"
        defaultValue={row.notes ?? ''}
        disabled={!canEdit}
        placeholder={canEdit ? 'הוספת הערה...' : ''}
        onBlur={(e) => {
          const v = e.target.value || null
          if (v !== row.notes) patch(row, { notes: v })
        }}
        className={cx(INLINE, 'placeholder:text-ink-tertiary')}
      />
    ),
  },
]

export const DEFAULT_HIDDEN_FIELDS = ['event_truck_count', 'volume_m']
