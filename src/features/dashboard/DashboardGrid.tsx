import { memo } from 'react'
import { WidgetFrame } from './WidgetFrame'
import type { LayoutItem, WidgetDef, WidgetSize } from './dashboardTypes'

/**
 * The twelve-column grid, read-only.
 *
 * `grid-auto-flow` stays normal rather than `dense`. Dense packing would fill
 * gaps by pulling later widgets forward, which moves them away from the order
 * the layout stores — "I put it third and it drew fifth". The order is the
 * user's, so the gaps are closed the other way round: every panel is held to its
 * size's height and fills the row it lands in, which leaves nothing ragged to
 * pack around. `WidgetFrame` owns both halves of that.
 */
export const DashboardGrid = memo(function DashboardGrid({
  items,
  byId,
  editing,
  onMove,
  onSize,
  onHeight,
  onRemove,
}: {
  items: LayoutItem[]
  byId: Map<string, WidgetDef>
  editing?: boolean
  onMove?: (id: string, offset: number) => void
  onSize?: (id: string, size: WidgetSize) => void
  onHeight?: (id: string, h: 'auto' | 'tall') => void
  onRemove?: (id: string) => void
}) {
  return (
    /* Stretch, not `items-start`: a row is as tall as its tallest card, and
       leaving the shorter ones at their natural height left that difference as
       page gap underneath them. Panels take the whole row; the one shape that
       must not be stretched — the KPI tile — opts out per item with `self-start`
       rather than the whole grid opting out on its behalf. */
    <div role="list" className="grid grid-cols-12 gap-4">
      {items.map((item, i) => {
        const def = byId.get(item.id)
        if (!def) return null
        return (
          <WidgetFrame
            key={item.id}
            item={item}
            def={def}
            editing={editing}
            position={{ index: i, total: items.length }}
            onMove={onMove}
            onSize={onSize}
            onHeight={onHeight}
            onRemove={onRemove}
          />
        )
      })}
    </div>
  )
})

/*
 * Memoised because the page above it owns five pieces of overlay state — the
 * task drawer, the event modal, edit mode, the catalogue, the builder — and
 * every one of them re-rendered this grid and, through it, every Recharts
 * container on the screen. Opening a task from a list widget re-laid-out the
 * charts behind the drawer.
 *
 * The read-only path takes only `items` and `byId`, and `useDashboardLayout`
 * already memoises both, so the comparison holds without threading callbacks
 * anywhere. Edit mode is a different component (`DashboardEditGrid`) and keeps
 * its own behaviour.
 */
