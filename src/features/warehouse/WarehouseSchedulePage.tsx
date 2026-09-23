import { useEffect, useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import { Link } from 'react-router'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { addMonths, endOfMonth, isSameMonth, startOfMonth } from 'date-fns'
import {
  Button,
  Card,
  EmptyState,
  ErrorState,
  Input,
  PageHeader,
  Popover,
  SkeletonTable,
  cx,
  useToast,
} from '../../components/ui'
import { Check, ICON, STROKE } from '../../components/ui/icons'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { fmtDate, fmtTime, fmtWeekday, toISODate } from '../../lib/dates'
import { errorMessage } from '../../lib/errors'
import { RequirePermission } from '../auth/guards'
import { MonthStepper } from '../dashboard/MonthStepper'
import type { WarehouseScheduleRow, WarehouseTaskKind } from '../../types/domain'
import {
  KIND_COLOR,
  KIND_LABEL,
  applyPatch,
  eventTones,
  groupByDay,
  rowKey,
} from './warehouseSchedule'
import type { WarehousePatch } from './warehouseSchedule'

/**
 * לו״ז מחסן (0196).
 *
 * אותה צורה של לו״ז העבודה, מוקטנת למה שהמחסן צריך: הימים רצים לרוחב,
 * השדות יורדים לגובה, והמקרא נדבק לקצה. לכל אירוע שתי עמודות — הכנה
 * (ביום ההקמה) והחזרה (ביום הפירוק) — צבועות בגוון של האירוע, והכותרת
 * של כל עמודה אומרת במבט אחד איזו מהשתיים היא.
 */
export default function WarehouseSchedulePage() {
  return (
    <RequirePermission perm={PERM.WAREHOUSE_VIEW}>
      <WarehouseSchedule />
    </RequirePermission>
  )
}

const COL_W = 148
const LEGEND_W = 116
const ROW_H = 38
const NOTES_H = 88

type Field = {
  key: string
  label: string
  height?: number
  render: (row: WarehouseScheduleRow, ctx: CellCtx) => ReactNode
}

interface CellCtx {
  canEdit: boolean
  canOpenEvent: boolean
  save: (row: WarehouseScheduleRow, patch: WarehousePatch) => void
}

const FIELDS: Field[] = [
  {
    key: 'start_time',
    label: 'בשעה',
    render: (row, { canEdit, save }) =>
      canEdit ? (
        <DraftInput
          type="time"
          ariaLabel="שעה"
          value={row.start_time ? row.start_time.slice(0, 5) : ''}
          onCommit={(v) => save(row, { start_time: v || null })}
        />
      ) : (
        <span className="tabular-nums">{row.start_time ? fmtTime(row.start_time) : '—'}</span>
      ),
  },
  {
    key: 'event_number',
    label: 'מס׳ תעודה',
    render: (row, { canOpenEvent }) =>
      canOpenEvent && row.event_number ? (
        <Link to={`/events/${row.event_id}`} className="tabular-nums underline-offset-2 hover:underline">
          {row.event_number}
        </Link>
      ) : (
        <span className="tabular-nums">{row.event_number ?? '—'}</span>
      ),
  },
  {
    key: 'end_client_name',
    label: 'שם לקוח',
    render: (row) => (
      <span className="block truncate" title={row.end_client_name ?? undefined}>
        {row.end_client_name ?? '—'}
      </span>
    ),
  },
  {
    key: 'duration_hours',
    label: 'זמן (שעות)',
    render: (row, { canEdit, save }) =>
      canEdit ? (
        <DraftInput
          type="number"
          ariaLabel="זמן בשעות"
          value={String(row.duration_hours ?? 0)}
          onCommit={(v) => {
            const n = v === '' ? 0 : Number(v)
            if (Number.isFinite(n) && n >= 0 && n <= 72) save(row, { duration_hours: n })
          }}
        />
      ) : (
        <span className="tabular-nums">{row.duration_hours ?? 0}</span>
      ),
  },
  {
    key: 'notes',
    label: 'הערות',
    height: NOTES_H,
    render: (row, { canEdit, save }) =>
      canEdit ? (
        <DraftInput
          multiline
          ariaLabel="הערות"
          value={row.notes ?? ''}
          onCommit={(v) => save(row, { notes: v.trim() || null })}
        />
      ) : (
        <span className="line-clamp-4 whitespace-pre-line" title={row.notes ?? undefined}>
          {row.notes}
        </span>
      ),
  },
  {
    key: 'final_approved',
    label: 'אישור סופי',
    render: (row, ctx) => <CheckCell row={row} field="final_approved" label="אישור סופי" {...ctx} />,
  },
  {
    key: 'event_ready',
    label: 'ארוע מוכן',
    render: (row, ctx) => <CheckCell row={row} field="event_ready" label="אירוע מוכן" {...ctx} />,
  },
  {
    key: 'checked',
    label: 'בדיקה',
    render: (row, ctx) => <CheckCell row={row} field="checked" label="בדיקה" {...ctx} />,
  },
]

function WarehouseSchedule() {
  const has = useAuth((s) => s.has)
  const qc = useQueryClient()
  const toast = useToast()
  const [month, setMonth] = useState(() => startOfMonth(new Date()))
  const from = toISODate(startOfMonth(month))
  const to = toISODate(endOfMonth(month))
  const queryKey = useMemo(() => ['warehouse_schedule', from, to] as const, [from, to])

  const { data: rows = [], isLoading, error, refetch } = useQuery({
    queryKey,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('warehouse_schedule', { p_from: from, p_to: to })
      if (error) throw error
      return (data ?? []) as WarehouseScheduleRow[]
    },
  })

  const mutation = useMutation({
    mutationFn: async ({ row, patch }: { row: WarehouseScheduleRow; patch: WarehousePatch }) => {
      const { error } = await supabase.rpc('warehouse_task_save', {
        p_event_id: row.event_id,
        p_kind: row.kind,
        p_patch: patch,
      })
      if (error) throw error
    },
    onMutate: async ({ row, patch }) => {
      await qc.cancelQueries({ queryKey })
      const prev = qc.getQueryData<WarehouseScheduleRow[]>(queryKey)
      qc.setQueryData<WarehouseScheduleRow[]>(queryKey, (old) =>
        old?.map((r) => (rowKey(r) === rowKey(row) ? applyPatch(r, patch) : r)),
      )
      return { prev }
    },
    onError: (e, _v, ctx) => {
      if (ctx?.prev) qc.setQueryData(queryKey, ctx.prev)
      toast.error(errorMessage(e))
    },
    /* תאריך שהוחזר לנגזר, או שיצא מהחודש, ידוע רק לשרת. */
    onSettled: (_d, _e, { patch }) => {
      if ('task_date' in patch) void qc.invalidateQueries({ queryKey: ['warehouse_schedule'] })
    },
  })

  const ctx: CellCtx = {
    canEdit: has(PERM.WAREHOUSE_EDIT),
    canOpenEvent: has(PERM.EVENTS_VIEW),
    save: (row, patch) => mutation.mutate({ row, patch }),
  }

  const days = useMemo(() => groupByDay(rows), [rows])
  const tones = useMemo(() => eventTones(rows), [rows])
  const today = toISODate(new Date())
  /* ‏`table-layout: fixed` מכבד את רוחב העמודות רק כשלטבלה עצמה יש רוחב
     מפורש; בלעדיו הדפדפן חוזר לפריסה האוטומטית, ושם לקוח ארוך או כותרת
     של יום בן עמודה אחת מותחים את העמודה שלהם. כל עמודה — אותו רוחב. */
  const columnCount = days.reduce((n, d) => n + d.rows.length, 0)
  const tableWidth = LEGEND_W + columnCount * COL_W

  return (
    <div className="space-y-4">
      <PageHeader
        title="לו״ז מחסן"
        subtitle="הכנה לפני כל אירוע, והחזרה אחריו"
        actions={
          <MonthStepper
            month={month}
            onStep={(d) => setMonth((m) => addMonths(m, d))}
            onToday={() => setMonth(startOfMonth(new Date()))}
            atToday={isSameMonth(month, new Date())}
          />
        }
      />

      {isLoading ? (
        <SkeletonTable />
      ) : error ? (
        <ErrorState error={error} onRetry={() => void refetch()} />
      ) : days.length === 0 ? (
        <Card>
          <EmptyState title="אין הכנות או החזרות בחודש הזה" description="אירוע חדש יופיע כאן עם משימת הכנה ומשימת החזרה." />
        </Card>
      ) : (
        <div className="overflow-x-auto rounded-xl border border-line bg-surface">
          <table className="border-separate border-spacing-0 text-[0.8125rem]" style={{ tableLayout: 'fixed', width: tableWidth }}>
            <colgroup>
              <col style={{ width: LEGEND_W }} />
              {days.flatMap((d) => d.rows.map((r) => <col key={rowKey(r)} style={{ width: COL_W }} />))}
            </colgroup>
            <thead>
              <tr>
                <th
                  className="sticky start-0 z-20 border-b border-e border-line bg-surface px-2 text-start type-caption font-medium text-ink-tertiary"
                  style={{ height: ROW_H }}
                >
                  יום
                </th>
                {days.map((d) => (
                  <th
                    key={d.date}
                    colSpan={d.rows.length}
                    className={cx(
                      'overflow-hidden text-ellipsis whitespace-nowrap border-b border-e border-line px-2 text-center type-caption font-semibold',
                      d.date === today ? 'bg-[var(--vl-board-today)] text-ink' : 'bg-[var(--vl-board-band)] text-ink',
                    )}
                  >
                    <span title={`${fmtWeekday(d.date)} · ${fmtDate(d.date)}`}>
                      {fmtWeekday(d.date)} · {fmtDate(d.date)}
                    </span>
                  </th>
                ))}
              </tr>
              <tr>
                <th
                  className="sticky start-0 z-20 border-b border-e border-line bg-surface px-2 text-start font-medium text-ink"
                  style={{ height: ROW_H + 6 }}
                >
                  הכנה / החזרה
                </th>
                {days.flatMap((d) =>
                  d.rows.map((r) => (
                    <th key={rowKey(r)} className="overflow-hidden border-b border-e border-line p-0" style={{ background: KIND_COLOR[r.kind] }}>
                      <KindHeader row={r} canEdit={ctx.canEdit} save={ctx.save} />
                    </th>
                  )),
                )}
              </tr>
            </thead>
            <tbody>
              {FIELDS.map((f) => (
                <tr key={f.key}>
                  <th
                    scope="row"
                    className="sticky start-0 z-10 border-b border-e border-line bg-surface px-2 text-start font-medium text-ink"
                    style={{ height: f.height ?? ROW_H }}
                  >
                    {f.label}
                  </th>
                  {days.flatMap((d) =>
                    d.rows.map((r) => (
                      <td
                        key={rowKey(r)}
                        className="overflow-hidden border-b border-e border-line px-1.5 text-center align-middle text-ink"
                        style={{ background: tones.get(r.event_id), height: f.height ?? ROW_H }}
                      >
                        {f.render(r, ctx)}
                      </td>
                    )),
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

/**
 * כותרת העמודה: הכנה או החזרה. למי שעורך היא גם הדרך להזיז את העמודה ליום
 * אחר — הכנה שנעשית יום לפני ההקמה, למשל — ולהחזיר אותה ליום הנגזר.
 */
function KindHeader({
  row,
  canEdit,
  save,
}: {
  row: WarehouseScheduleRow
  canEdit: boolean
  save: CellCtx['save']
}) {
  const label = (
    <span className="flex items-center justify-center gap-1 text-base font-semibold text-white">
      {KIND_LABEL[row.kind]}
      {row.date_is_manual && (
        <span className="text-[0.625rem] font-normal opacity-80" title="התאריך נקבע ביד">
          •
        </span>
      )}
    </span>
  )
  if (!canEdit) return <div className="px-2 py-2">{label}</div>

  return (
    <Popover
      className="block"
      trigger={({ toggle, ...aria }) => (
        <button
          type="button"
          onClick={toggle}
          {...aria}
          title="שינוי היום"
          className="block w-full px-2 py-2 hover:brightness-110 focus-visible:outline-none focus-visible:focus-ring"
        >
          {label}
        </button>
      )}
    >
      {(close) => <DatePanel row={row} save={save} close={close} />}
    </Popover>
  )
}

function DatePanel({
  row,
  save,
  close,
}: {
  row: WarehouseScheduleRow
  save: CellCtx['save']
  close: () => void
}) {
  const [date, setDate] = useState(row.task_date)
  return (
    <div className="w-60 space-y-2 p-3">
      <p className="type-caption text-ink-tertiary">
        {KIND_LABEL[row.kind as WarehouseTaskKind]} · {row.event_number ?? ''} · {row.end_client_name ?? ''}
      </p>
      <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} aria-label="יום" />
      <div className="flex flex-wrap gap-2">
        <Button
          size="sm"
          variant="primary"
          disabled={!date || date === row.task_date}
          onClick={() => {
            save(row, { task_date: date })
            close()
          }}
        >
          שמירה
        </Button>
        {row.date_is_manual && (
          <Button
            size="sm"
            onClick={() => {
              save(row, { task_date: null })
              close()
            }}
          >
            {row.kind === 'prep' ? 'חזרה ליום ההקמה' : 'חזרה ליום הפירוק'}
          </Button>
        )}
      </div>
    </div>
  )
}

/**
 * שדה שנשמר כשיוצאים ממנו, ולא בכל הקשה — שעה חצי-מוקלדת אינה שעה, והמסד
 * אינו צריך לשמוע על כל תו בהערה. Enter שומר בשדה של שורה אחת, Escape מבטל.
 */
function DraftInput({
  value,
  onCommit,
  type = 'text',
  multiline,
  ariaLabel,
}: {
  value: string
  onCommit: (v: string) => void
  type?: 'text' | 'time' | 'number'
  multiline?: boolean
  ariaLabel: string
}) {
  const [draft, setDraft] = useState(value)
  useEffect(() => setDraft(value), [value])
  const commit = () => {
    if (draft !== value) onCommit(draft)
  }
  const cls =
    'w-full rounded-md border border-transparent bg-transparent px-1 text-center text-ink hover:border-line focus:border-brand-500 focus:bg-surface focus:outline-none'

  if (multiline)
    return (
      <textarea
        aria-label={ariaLabel}
        value={draft}
        rows={3}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={commit}
        onKeyDown={(e) => {
          if (e.key === 'Escape') setDraft(value)
        }}
        className={cx(cls, 'h-full resize-none py-1 text-start')}
      />
    )

  return (
    <input
      aria-label={ariaLabel}
      type={type}
      dir={type === 'text' ? undefined : 'ltr'}
      step={type === 'number' ? 0.5 : undefined}
      min={type === 'number' ? 0 : undefined}
      value={draft}
      onChange={(e) => setDraft(e.target.value)}
      onBlur={commit}
      onKeyDown={(e) => {
        if (e.key === 'Enter') (e.target as HTMLInputElement).blur()
        if (e.key === 'Escape') setDraft(value)
      }}
      className={cx(cls, 'h-7 tabular-nums')}
    />
  )
}

function CheckCell({
  row,
  field,
  label,
  canEdit,
  save,
}: {
  row: WarehouseScheduleRow
  field: 'final_approved' | 'event_ready' | 'checked'
  label: string
} & CellCtx) {
  const on = row[field]
  const mark = on ? <Check size={ICON.lg} strokeWidth={STROKE + 0.75} aria-hidden /> : null
  if (!canEdit)
    return (
      <span className="flex justify-center" aria-label={on ? `${label}: כן` : `${label}: לא`}>
        {mark}
      </span>
    )
  return (
    <button
      type="button"
      role="checkbox"
      aria-checked={on}
      aria-label={label}
      onClick={() => save(row, { [field]: !on })}
      className="flex h-8 w-full items-center justify-center rounded-md text-ink hover:bg-black/5 focus-visible:outline-none focus-visible:focus-ring dark:hover:bg-white/10"
    >
      {mark}
    </button>
  )
}
