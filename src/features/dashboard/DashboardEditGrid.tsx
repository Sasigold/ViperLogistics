import { useState } from 'react'
import {
  DndContext,
  KeyboardSensor,
  PointerSensor,
  closestCenter,
  useSensor,
  useSensors,
} from '@dnd-kit/core'
import type { DragEndEvent, DragStartEvent } from '@dnd-kit/core'
import { SortableContext, rectSortingStrategy, sortableKeyboardCoordinates, useSortable } from '@dnd-kit/sortable'
import { CSS } from '@dnd-kit/utilities'
import { WidgetFrame } from './WidgetFrame'
import type { LayoutItem, WidgetDef, WidgetSize } from './dashboardTypes'

/**
 * The grid while it is being rearranged.
 *
 * Loaded with `React.lazy` from the page, so none of dnd-kit reaches the
 * bundle until someone actually opens edit mode. The dashboard is the most
 * visited screen in the product and the ordinary render of it should not pay
 * for a feature most sessions never touch — the same reasoning the router
 * already applies to Recharts, FullCalendar and ExcelJS.
 *
 * Two notes on the sortable setup, both deliberate:
 *
 * `rectSortingStrategy` with `closestCenter` measures real DOM rectangles and
 * assumes nothing about direction, so RTL needs no special handling here. Its
 * horizontal sibling, `horizontalListSortingStrategy`, does assume — which is
 * why the grid is a grid of `grid-column: span N` and not a list.
 *
 * Dragging starts from the handle only, and only after 8px of travel. Anything
 * looser and a drag competes with tapping a chart and with scrolling the page
 * on a phone.
 */
export default function DashboardEditGrid({
  items,
  byId,
  onMove,
  onReorder,
  onSize,
  onHeight,
  onRemove,
}: {
  items: LayoutItem[]
  byId: Map<string, WidgetDef>
  onMove: (id: string, offset: number) => void
  onReorder: (activeId: string, overId: string) => void
  onSize: (id: string, size: WidgetSize) => void
  onHeight: (id: string, h: 'auto' | 'tall') => void
  onRemove: (id: string) => void
}) {
  const [dragging, setDragging] = useState<string | null>(null)
  const [announcement, setAnnouncement] = useState('')

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  )

  const announce = (id: string) => {
    const at = items.findIndex((i) => i.id === id)
    if (at >= 0) setAnnouncement(`${byId.get(id)?.title ?? ''} הועבר למקום ${at + 1} מתוך ${items.length}`)
  }

  return (
    <DndContext
      sensors={sensors}
      collisionDetection={closestCenter}
      onDragStart={(e: DragStartEvent) => setDragging(String(e.active.id))}
      onDragCancel={() => setDragging(null)}
      onDragEnd={(e: DragEndEvent) => {
        setDragging(null)
        const over = e.over?.id
        if (over && over !== e.active.id) {
          onReorder(String(e.active.id), String(over))
          announce(String(e.active.id))
        }
      }}
    >
      <SortableContext items={items.map((i) => i.id)} strategy={rectSortingStrategy}>
        {/* the same stretch-and-cap rhythm as the read-only grid, so nothing
            moves when edit mode opens — see DashboardGrid */}
        <div role="list" className="grid grid-cols-12 gap-4">
          {items.map((item, i) => {
            const def = byId.get(item.id)
            if (!def) return null
            return (
              <SortableWidget
                key={item.id}
                item={item}
                def={def}
                position={{ index: i, total: items.length }}
                dragging={dragging === item.id}
                onMove={(id, offset) => {
                  onMove(id, offset)
                  announce(id)
                }}
                onSize={onSize}
                onHeight={onHeight}
                onRemove={onRemove}
              />
            )
          })}
        </div>
      </SortableContext>

      {/* every move says where the widget ended up, so the arrows and the
          keyboard drag are usable without watching the screen */}
      <span aria-live="polite" className="sr-only">
        {announcement}
      </span>
    </DndContext>
  )
}

function SortableWidget({
  item,
  def,
  position,
  dragging,
  onMove,
  onSize,
  onHeight,
  onRemove,
}: {
  item: LayoutItem
  def: WidgetDef
  position: { index: number; total: number }
  dragging: boolean
  onMove: (id: string, offset: number) => void
  onSize: (id: string, size: WidgetSize) => void
  onHeight: (id: string, h: 'auto' | 'tall') => void
  onRemove: (id: string) => void
}) {
  const { attributes, listeners, setNodeRef, transform, transition } = useSortable({ id: item.id })

  return (
    <WidgetFrame
      item={item}
      def={def}
      editing
      position={position}
      dragging={dragging}
      innerRef={setNodeRef}
      style={{ transform: CSS.Transform.toString(transform), transition }}
      dragHandleProps={{ ...attributes, ...listeners }}
      onMove={onMove}
      onSize={onSize}
      onHeight={onHeight}
      onRemove={onRemove}
    />
  )
}
