import { useEffect, useMemo, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { ArrowDown, ArrowUp, ChevronLeft, ChevronRight, ChevronsUpDown, Columns3 } from 'lucide-react'
import { Button, IconButton, cx } from './primitives'
import { Checkbox } from './inputs'
import { EmptyState, SkeletonTable, ErrorState } from './feedback'
import { MenuLabel, Popover } from './overlay'
import { useIsPhone } from '../../lib/useMediaQuery'

export interface Column<T> {
  key: string
  header: ReactNode
  /** plain-text name for the column picker when `header` is a node */
  label?: string
  render: (row: T, index: number) => ReactNode
  /** returning a value enables sorting on this column */
  sortValue?: (row: T) => string | number | null | undefined
  width?: number
  minWidth?: number
  align?: 'start' | 'center' | 'end'
  /** pin to the inline-start edge while scrolling horizontally */
  sticky?: boolean
  /** exclude from the column picker — always visible */
  fixed?: boolean
  className?: string
  headerClassName?: string
}

type SortState = { key: string; dir: 'asc' | 'desc' } | null

interface Persisted {
  widths?: Record<string, number>
  hidden?: string[]
}

function loadState(key?: string): Persisted {
  if (!key) return {}
  try {
    return JSON.parse(localStorage.getItem(`vl-table:${key}`) ?? '{}') as Persisted
  } catch {
    return {}
  }
}

function saveState(key: string | undefined, state: Persisted) {
  if (!key) return
  try {
    localStorage.setItem(`vl-table:${key}`, JSON.stringify(state))
  } catch {
    /* storage full or blocked — view preferences are not worth failing over */
  }
}

const ALIGN = { start: 'text-start', center: 'text-center', end: 'text-end' } as const

export function DataTable<T>({
  rows,
  columns,
  getRowId,
  loading,
  error,
  onRetry,
  empty,
  onRowClick,
  rowClassName,
  selectable,
  selected,
  onSelectedChange,
  bulkActions,
  pageSize = 0,
  storageKey,
  zebra = true,
  dense,
  toolbar,
  defaultSort,
  className,
  maxHeight,
  mobileCard,
}: {
  rows: T[]
  columns: Column<T>[]
  getRowId: (row: T) => string
  loading?: boolean
  error?: unknown
  onRetry?: () => void
  empty?: ReactNode
  onRowClick?: (row: T) => void
  rowClassName?: (row: T) => string | undefined
  selectable?: boolean
  selected?: Set<string>
  onSelectedChange?: (next: Set<string>) => void
  bulkActions?: (ids: string[]) => ReactNode
  /** 0 disables pagination */
  pageSize?: number
  /** persists column widths and visibility */
  storageKey?: string
  zebra?: boolean
  dense?: boolean
  toolbar?: ReactNode
  defaultSort?: SortState
  className?: string
  /** caps the scroll area so the sticky header has something to stick to */
  maxHeight?: string
  /**
   * Below `md`, render each row as a card instead of a table row. A ten-column
   * table on a phone is a horizontal-scroll puzzle; the same record stacked
   * into two or three lines is readable at a glance. Sorting, paging and
   * selection all keep working — only the row's presentation changes.
   */
  mobileCard?: (row: T, index: number) => ReactNode
}) {
  const isPhone = useIsPhone()
  const asCards = isPhone && !!mobileCard
  const persisted = useRef(loadState(storageKey))
  const [widths, setWidths] = useState<Record<string, number>>(persisted.current.widths ?? {})
  const [hidden, setHidden] = useState<Set<string>>(new Set(persisted.current.hidden ?? []))
  const [sort, setSort] = useState<SortState>(defaultSort ?? null)
  const [page, setPage] = useState(0)

  useEffect(() => saveState(storageKey, { widths, hidden: [...hidden] }), [widths, hidden, storageKey])
  useEffect(() => setPage(0), [rows.length, sort])

  const visible = useMemo(() => columns.filter((c) => c.fixed || !hidden.has(c.key)), [columns, hidden])

  const sorted = useMemo(() => {
    if (!sort) return rows
    const col = columns.find((c) => c.key === sort.key)
    if (!col?.sortValue) return rows
    const dir = sort.dir === 'asc' ? 1 : -1
    return [...rows].sort((a, b) => {
      const av = col.sortValue!(a)
      const bv = col.sortValue!(b)
      if (av == null && bv == null) return 0
      if (av == null) return 1 // nulls always sink, regardless of direction
      if (bv == null) return -1
      if (typeof av === 'number' && typeof bv === 'number') return (av - bv) * dir
      return String(av).localeCompare(String(bv), 'he') * dir
    })
  }, [rows, sort, columns])

  const pageCount = pageSize > 0 ? Math.max(1, Math.ceil(sorted.length / pageSize)) : 1
  const pageRows = pageSize > 0 ? sorted.slice(page * pageSize, page * pageSize + pageSize) : sorted

  // cumulative inline-start offsets for pinned columns
  const stickyOffsets = useMemo(() => {
    const out: Record<string, number> = {}
    let acc = selectable ? 40 : 0
    for (const c of visible) {
      if (!c.sticky) continue
      out[c.key] = acc
      acc += widths[c.key] ?? c.width ?? 160
    }
    return out
  }, [visible, widths, selectable])

  const totalWidth = useMemo(
    () => (selectable ? 40 : 0) + visible.reduce((s, c) => s + (widths[c.key] ?? c.width ?? 160), 0),
    [visible, widths, selectable],
  )

  const pageIds = pageRows.map(getRowId)
  const allOnPageSelected = pageIds.length > 0 && pageIds.every((id) => selected?.has(id))

  const toggleAll = () => {
    if (!onSelectedChange) return
    const next = new Set(selected)
    if (allOnPageSelected) pageIds.forEach((id) => next.delete(id))
    else pageIds.forEach((id) => next.add(id))
    onSelectedChange(next)
  }

  const toggleOne = (id: string) => {
    if (!onSelectedChange) return
    const next = new Set(selected)
    if (next.has(id)) next.delete(id)
    else next.add(id)
    onSelectedChange(next)
  }

  const cycleSort = (key: string) =>
    setSort((s) => (s?.key !== key ? { key, dir: 'asc' } : s.dir === 'asc' ? { key, dir: 'desc' } : null))

  /* column resize — pointer events so it works with touch and pen too */
  const resizing = useRef<{ key: string; startX: number; startW: number; rtl: boolean } | null>(null)
  const startResize = (e: React.PointerEvent, col: Column<T>) => {
    e.preventDefault()
    e.stopPropagation()
    ;(e.target as HTMLElement).setPointerCapture(e.pointerId)
    resizing.current = {
      key: col.key,
      startX: e.clientX,
      startW: widths[col.key] ?? col.width ?? 160,
      rtl: getComputedStyle(document.documentElement).direction === 'rtl',
    }
  }
  const onResizeMove = (e: React.PointerEvent) => {
    const r = resizing.current
    if (!r) return
    const delta = (e.clientX - r.startX) * (r.rtl ? -1 : 1)
    const col = columns.find((c) => c.key === r.key)
    setWidths((w) => ({ ...w, [r.key]: Math.max(col?.minWidth ?? 64, r.startW + delta) }))
  }
  const endResize = () => {
    resizing.current = null
  }

  const hideable = columns.filter((c) => !c.fixed)
  const selectedIds = selected ? [...selected] : []

  return (
    <div className={cx('relative', className)}>
      {(toolbar || hideable.length > 0) && (
        <div className="mb-2 flex flex-wrap items-center gap-2">
          {toolbar}
          {/* the column picker has nothing to pick from once rows are cards */}
          {hideable.length > 0 && !asCards && (
            <Popover
              className="ms-auto"
              trigger={({ toggle, ...aria }) => (
                <Button size="sm" variant="ghost" onClick={toggle} {...aria}>
                  <Columns3 size={14} />
                  עמודות
                </Button>
              )}
            >
              {() => (
                <div className="max-h-72 w-56 overflow-y-auto">
                  <MenuLabel>עמודות מוצגות</MenuLabel>
                  {hideable.map((c) => (
                    <div key={c.key} className="px-2.5 py-1.5">
                      <Checkbox
                        label={c.label ?? (typeof c.header === 'string' ? c.header : c.key)}
                        checked={!hidden.has(c.key)}
                        onChange={(on) =>
                          setHidden((h) => {
                            const next = new Set(h)
                            if (on) next.delete(c.key)
                            else next.add(c.key)
                            return next
                          })
                        }
                      />
                    </div>
                  ))}
                </div>
              )}
            </Popover>
          )}
        </div>
      )}

      <div className="surface overflow-hidden">
        {loading ? (
          <SkeletonTable rows={dense ? 10 : 7} cols={Math.min(visible.length, 6)} />
        ) : error ? (
          <ErrorState error={error} onRetry={onRetry} />
        ) : sorted.length === 0 ? (
          (empty ?? <EmptyState art="table" />)
        ) : asCards ? (
          <ul className="divide-y divide-line-subtle">
            {selectable && (
              <li className="flex items-center gap-2 bg-subtle px-3 py-2">
                <Checkbox
                  label={<span className="type-caption font-semibold">בחר הכל</span>}
                  checked={allOnPageSelected}
                  indeterminate={pageIds.some((id) => selected?.has(id))}
                  onChange={toggleAll}
                />
              </li>
            )}
            {pageRows.map((row, i) => {
              const id = getRowId(row)
              const isSelected = !!selected?.has(id)
              return (
                <li
                  key={id}
                  className={cx('flex items-start gap-2 px-3', isSelected && 'bg-selected', rowClassName?.(row))}
                >
                  {selectable && (
                    <span className="pt-3.5">
                      <Checkbox checked={isSelected} onChange={() => toggleOne(id)} />
                    </span>
                  )}
                  <div
                    onClick={onRowClick ? () => onRowClick(row) : undefined}
                    className={cx('min-w-0 flex-1 py-3', onRowClick && 'cursor-pointer')}
                  >
                    {mobileCard!(row, i)}
                  </div>
                </li>
              )
            })}
          </ul>
        ) : (
          <div className="overflow-auto" style={{ maxHeight }} onPointerMove={onResizeMove} onPointerUp={endResize}>
            <table className="w-full table-fixed border-collapse" style={{ minWidth: totalWidth }}>
              <colgroup>
                {selectable && <col style={{ width: 40 }} />}
                {visible.map((c) => (
                  <col key={c.key} style={{ width: widths[c.key] ?? c.width ?? 160 }} />
                ))}
              </colgroup>

              <thead className="sticky top-0 z-20">
                <tr className="bg-subtle">
                  {selectable && (
                    <th
                      className="sticky z-10 border-b border-line bg-inherit px-2 py-2 text-start"
                      style={{ insetInlineStart: 0 }}
                    >
                      <Checkbox
                        checked={allOnPageSelected}
                        indeterminate={pageIds.some((id) => selected?.has(id))}
                        onChange={toggleAll}
                      />
                    </th>
                  )}
                  {visible.map((c) => {
                    const sortable = !!c.sortValue
                    const isSorted = sort?.key === c.key
                    return (
                      <th
                        key={c.key}
                        scope="col"
                        aria-sort={isSorted ? (sort!.dir === 'asc' ? 'ascending' : 'descending') : undefined}
                        className={cx(
                          'group relative border-b border-line bg-inherit px-3 py-2 type-table-head',
                          ALIGN[c.align ?? 'start'],
                          c.sticky && 'sticky z-10',
                          c.headerClassName,
                        )}
                        style={c.sticky ? { insetInlineStart: stickyOffsets[c.key] } : undefined}
                      >
                        {sortable ? (
                          <button
                            type="button"
                            onClick={() => cycleSort(c.key)}
                            className="inline-flex max-w-full items-center gap-1 rounded transition-colors hover:text-ink focus-visible:outline-none focus-visible:focus-ring"
                          >
                            <span className="truncate">{c.header}</span>
                            {isSorted ? (
                              sort!.dir === 'asc' ? (
                                <ArrowUp size={12} className="shrink-0 text-primary" aria-hidden />
                              ) : (
                                <ArrowDown size={12} className="shrink-0 text-primary" aria-hidden />
                              )
                            ) : (
                              <ChevronsUpDown
                                size={12}
                                aria-hidden
                                className="shrink-0 opacity-0 transition-opacity group-hover:opacity-50"
                              />
                            )}
                          </button>
                        ) : (
                          <span className="block truncate">{c.header}</span>
                        )}

                        <span
                          role="separator"
                          aria-orientation="vertical"
                          onPointerDown={(e) => startResize(e, c)}
                          className="absolute inset-y-0 end-0 w-1.5 cursor-col-resize touch-none opacity-0 transition-opacity hover:bg-primary group-hover:opacity-40"
                        />
                      </th>
                    )
                  })}
                </tr>
              </thead>

              <tbody>
                {pageRows.map((row, i) => {
                  const id = getRowId(row)
                  const isSelected = !!selected?.has(id)
                  return (
                    <tr
                      key={id}
                      onClick={onRowClick ? () => onRowClick(row) : undefined}
                      className={cx(
                        'border-b border-line-subtle transition-colors last:border-0',
                        isSelected ? 'bg-selected' : zebra && i % 2 === 1 ? 'bg-subtle/45' : 'bg-surface',
                        'hover:bg-hover',
                        onRowClick && 'cursor-pointer',
                        rowClassName?.(row),
                      )}
                    >
                      {selectable && (
                        <td
                          className="sticky z-10 bg-inherit px-2 align-middle"
                          style={{ insetInlineStart: 0 }}
                          onClick={(e) => e.stopPropagation()}
                        >
                          <Checkbox checked={isSelected} onChange={() => toggleOne(id)} />
                        </td>
                      )}
                      {visible.map((c) => (
                        <td
                          key={c.key}
                          className={cx(
                            'truncate bg-inherit px-3 type-table',
                            dense ? 'py-1.5' : 'py-2.5',
                            ALIGN[c.align ?? 'start'],
                            c.sticky && 'sticky z-10',
                            c.className,
                          )}
                          style={c.sticky ? { insetInlineStart: stickyOffsets[c.key] } : undefined}
                        >
                          {c.render(row, i)}
                        </td>
                      ))}
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}

        {pageSize > 0 && !loading && sorted.length > 0 && (
          <div className="flex flex-wrap items-center justify-between gap-2 border-t border-line-subtle px-3 py-2">
            <span className="type-caption tabular text-ink-tertiary">
              {page * pageSize + 1}–{Math.min((page + 1) * pageSize, sorted.length)} מתוך {sorted.length}
            </span>
            <div className="flex items-center gap-1">
              <IconButton
                label="עמוד קודם"
                size="sm"
                disabled={page === 0}
                onClick={() => setPage((p) => Math.max(0, p - 1))}
              >
                <ChevronRight size={15} />
              </IconButton>
              <span className="px-2 type-caption tabular text-ink-secondary">
                {page + 1} / {pageCount}
              </span>
              <IconButton
                label="עמוד הבא"
                size="sm"
                disabled={page >= pageCount - 1}
                onClick={() => setPage((p) => Math.min(pageCount - 1, p + 1))}
              >
                <ChevronLeft size={15} />
              </IconButton>
            </div>
          </div>
        )}
      </div>

      {bulkActions && selectedIds.length > 0 && (
        <BulkBar count={selectedIds.length} onClear={() => onSelectedChange?.(new Set())}>
          {bulkActions(selectedIds)}
        </BulkBar>
      )}
    </div>
  )
}

/* ===== BulkBar ============================================================
   Floating action bar — exported so the work board can reuse it.          */

export function BulkBar({ count, onClear, children }: { count: number; onClear: () => void; children: ReactNode }) {
  return (
    <div className="pointer-events-none fixed inset-x-0 z-40 flex justify-center px-3 bottom-shell lg:bottom-6">
      <div className="pointer-events-auto flex max-w-full animate-slide-up flex-wrap items-center justify-center gap-2 rounded-2xl border border-line bg-raised px-3 py-2 shadow-overlay sm:flex-nowrap sm:gap-3">
        <span className="inline-flex h-6 min-w-6 items-center justify-center rounded-full bg-primary px-1.5 type-caption font-bold tabular text-on-primary">
          {count}
        </span>
        <span className="type-body text-ink-secondary">נבחרו</span>
        <div className="mx-1 h-5 w-px bg-line" aria-hidden />
        {children}
        <Button size="sm" variant="ghost" onClick={onClear}>
          ניקוי
        </Button>
      </div>
    </div>
  )
}
