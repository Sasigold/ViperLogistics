import { WidgetFrame } from './WidgetFrame'
import type { LayoutItem, WidgetDef, WidgetSize } from './dashboardTypes'

/**
 * The twelve-column grid, read-only.
 *
 * `grid-auto-flow` stays normal rather than `dense`. Dense packing would fill
 * gaps by pulling later widgets forward, which moves them away from the order
 * the layout stores — "I put it third and it drew fifth". An occasional gap is
 * the cheaper price for a grid that shows you what you arranged.
 */
export function DashboardGrid({
  items,
  byId,
  editing,
  onMove,
  onSize,
  onRemove,
}: {
  items: LayoutItem[]
  byId: Map<string, WidgetDef>
  editing?: boolean
  onMove?: (id: string, offset: number) => void
  onSize?: (id: string, size: WidgetSize) => void
  onRemove?: (id: string) => void
}) {
  return (
    /* `items-start` rather than the default stretch: the old page was a stack
       of separate grids, each holding one shape, so equal row heights came
       free. One grid holding every shape does not have that luxury — a KPI
       tile sharing a row with a chart would be stretched to the chart's
       height. Natural heights are the honest answer once the arrangement is
       the user's. */
    <div role="list" className="grid grid-cols-12 items-start gap-4">
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
            onRemove={onRemove}
          />
        )
      })}
    </div>
  )
}
