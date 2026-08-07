import type { ReactNode } from 'react'
import { AvatarGroup, StatusPill, Tooltip, cx } from '../../components/ui'
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
  /** taller row — for the team list */
  tall?: boolean
}

/* Inline editors share one look: invisible until hovered, so a screen full of
   editable cells doesn't read as a screen full of form controls. */
const INLINE =
  'w-full rounded border border-transparent bg-transparent px-1.5 py-0.5 text-[0.8125rem] tabular ' +
  'transition-colors duration-150 hover:border-line hover:bg-surface ' +
  'focus:border-primary focus:bg-surface focus:outline-none focus:ring-2 focus:ring-[var(--vl-focus-ring)] ' +
  'disabled:pointer-events-none disabled:opacity-70'

const READONLY = 'block truncate px-1.5 py-0.5 text-[0.8125rem]'

function Muted({ children }: { children?: ReactNode }) {
  return <span className="px-1.5 text-[0.8125rem] text-ink-tertiary">{children ?? '—'}</span>
}

/**
 * The board is transposed: what used to be 22 columns is now 19 rows, one per
 * field, read down a task's column. Every editor keeps the original
 * optimistic-concurrency write — only the wrapper changed.
 */
export const BOARD_FIELDS: BoardField[] = [
  {
    key: 'customer',
    label: 'לקוח',
    render: ({ row }) =>
      row.customer_name ? (
        <span className="flex items-center gap-1.5 px-1.5">
          <span
            className="size-2 shrink-0 rounded-full"
            style={{ background: row.customer_color ?? 'var(--vl-text-tertiary)' }}
          />
          <span className="truncate text-[0.8125rem] font-medium">{row.customer_name}</span>
        </span>
      ) : (
        <Muted />
      ),
  },
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
        <span className="flex items-center gap-1">
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
    label: 'משאית',
    render: ({ row, canEdit, patch, lookups }) => (
      <select
        aria-label="משאית"
        value={row.truck_id ?? ''}
        disabled={!canEdit}
        onChange={(e) => patch(row, { truck_id: e.target.value || null })}
        className={cx(INLINE, 'cursor-pointer truncate')}
      >
        <option value="">{row.truck_free_text || '—'}</option>
        {lookups.trucks
          .filter((t) => t.is_active)
          .map((t) => (
            <option key={t.id} value={t.id}>
              {t.name}
            </option>
          ))}
      </select>
    ),
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
        className={cx(INLINE, 'cursor-pointer truncate')}
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
    label: 'ראש צוות',
    render: ({ row }) => (row.team_lead_name ? <span className={READONLY}>{row.team_lead_name}</span> : <Muted />),
  },
  {
    key: 'team',
    label: 'צוות',
    tall: true,
    render: ({ row }) => {
      const workers = (row.workers ?? []).map((w) => w.name)
      const drivers = (row.drivers ?? []).map((d) => (d.truck_name ? `${d.name} (${d.truck_name})` : d.name))
      const contractors = (row.contractor_worker_list ?? []).map((w) => w.name)
      const total = workers.length + drivers.length + contractors.length
      if (total === 0) return <Muted>לא שובץ</Muted>
      // מי שיוצא מהמחסן מתחיל בשעה אחרת מכולם, ולכן הספירה שווה מבט מהלוח
      // בלי לפתוח את המשימה.
      const fromWarehouse = [
        ...(row.workers ?? []),
        ...(row.drivers ?? []),
        ...(row.contractor_worker_list ?? []),
      ].filter((p) => p.work_site === 'warehouse')
      return (
        <span className="flex flex-wrap items-center gap-1 px-1.5">
          {workers.length > 0 && <AvatarGroup names={workers} max={4} size="xs" />}
          {fromWarehouse.length > 0 && (
            <Tooltip content={`מתחילים מהמחסן: ${fromWarehouse.map((p) => p.name).join(', ')}`}>
              <span className="inline-flex items-center gap-0.5 rounded bg-subtle px-1 text-[10px] font-bold tabular text-ink-secondary">
                🏭 {fromWarehouse.length}
              </span>
            </Tooltip>
          )}
          {drivers.length > 0 && (
            <Tooltip content={`נהגים: ${drivers.join(', ')}`}>
              <span className="inline-flex items-center gap-0.5 rounded bg-info-subtle px-1 text-[10px] font-bold tabular text-info-text">
                🚚 {drivers.length}
              </span>
            </Tooltip>
          )}
          {contractors.length > 0 && (
            <Tooltip content={`עובדי קבלן: ${contractors.join(', ')}`}>
              <span className="inline-flex items-center gap-0.5 rounded bg-warning-subtle px-1 text-[10px] font-bold tabular text-warning-text">
                👷 {contractors.length}
              </span>
            </Tooltip>
          )}
        </span>
      )
    },
  },
  {
    key: 'contractor',
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
            className="w-full cursor-pointer truncate rounded-md border border-transparent px-1.5 py-0.5 text-[0.75rem] font-semibold focus:outline-none focus:ring-2 focus:ring-[var(--vl-focus-ring)]"
            style={{
              background: `color-mix(in srgb, ${row.status_color} 14%, transparent)`,
              color: `color-mix(in srgb, ${row.status_color}, black 18%)`,
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
        <span className="block px-1.5">
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
        className={cx(INLINE, 'text-start placeholder:text-ink-tertiary')}
      />
    ),
  },
]

export const DEFAULT_HIDDEN_FIELDS = ['event_truck_count', 'volume_m']
