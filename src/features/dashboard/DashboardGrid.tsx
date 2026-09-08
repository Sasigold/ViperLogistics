import { WidgetFrame } from './WidgetFrame'
import { PACK_CLASS } from './layout'
import { cx } from '../../components/ui'
import type { LayoutItem, Packing, WidgetDef } from './dashboardTypes'

/**
 * The twelve-column grid, read-only.
 *
 * The order the layout stores is the order the grid draws — with one opt-in
 * exception the reader controls. In `aligned` packing every panel is held to
 * its size's height and fills the row it lands in, which leaves nothing ragged
 * to pack around; `WidgetFrame` owns both halves of that. In `compact` packing
 * each card stands at its own height and `grid-auto-flow: dense` fills the
 * holes that leaves by pulling a later card that fits into one.
 *
 * Dense packing is not the default and never happens behind the reader's back:
 * it moves a card forward of where they put it, which is a real cost and only
 * worth paying on a screen whose cards have little to say. `layout.ts` carries
 * the whole argument.
 */
export function DashboardGrid({
  items,
  byId,
  packing = 'aligned',
  onOpt,
}: {
  items: LayoutItem[]
  byId: Map<string, WidgetDef>
  packing?: Packing
  onOpt?: (id: string, key: string, value: string | number | boolean | undefined) => void
}) {
  return (
    /* Stretch, not `items-start`: a row is as tall as its tallest card, and
       leaving the shorter ones at their natural height left that difference as
       page gap underneath them. Panels take the whole row; the two shapes that
       must not be stretched — the KPI tile, and every card in `compact` —
       opt out per item with `self-start` rather than the whole grid opting out
       on their behalf. */
    <div role="list" className={cx('grid grid-cols-12 gap-4', PACK_CLASS[packing])}>
      {items.map((item, i) => {
        const def = byId.get(item.id)
        if (!def) return null
        return (
          <WidgetFrame
            key={item.id}
            item={item}
            def={def}
            packing={packing}
            position={{ index: i, total: items.length }}
            onOpt={onOpt}
          />
        )
      })}
    </div>
  )
}
