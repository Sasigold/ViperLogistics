import { Component } from 'react'
import type { ErrorInfo, ReactNode } from 'react'
import {
  Card,
  CardBody,
  EmptyState,
  IconButton,
  MenuItem,
  MenuLabel,
  MenuSeparator,
  Popover,
  SegmentedControl,
  cx,
} from '../../components/ui'
import { ChevronLeft, ChevronRight, GripVertical, ICON, MoreVertical, STROKE, X } from '../../components/ui/icons'
import { reportError } from '../../lib/reportError'
import { SIZE_LABELS, SPAN, bodyHeight } from './layout'
import type { LayoutItem, WidgetDef, WidgetSize } from './dashboardTypes'

/**
 * One widget's slot on the grid.
 *
 * The frame owns *placement* and the edit affordances; the chrome is the
 * widget's own. A KPI tile is a `StatCard` and a chart is a `Card` with a
 * header — forcing both into one shell would mean unpicking it again inside
 * half the catalogue.
 */

/* ===== isolation ==========================================================
   The app-level ErrorBoundary is page-sized, and using it here would mean one
   widget with a bad payload takes the whole dashboard down with it. A widget
   is exactly the right blast radius: the other twenty keep working, and the
   broken one says so in its own slot.                                       */

class WidgetBoundary extends Component<{ id: string; title: string; children: ReactNode }, { failed: boolean }> {
  state = { failed: false }

  static getDerivedStateFromError() {
    return { failed: true }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    reportError(error, { kind: 'render', key: `widget:${this.props.id}`, componentStack: info.componentStack })
  }

  render() {
    if (!this.state.failed) return this.props.children
    return (
      <Card>
        <CardBody>
          <EmptyState
            compact
            art="alert"
            title="הווידג׳ט הזה נכשל"
            description={`אפשר להסיר את "${this.props.title}" מהדשבורד ולהמשיך`}
          />
        </CardBody>
      </Card>
    )
  }
}

/* ===== the slot =========================================================== */

export interface WidgetFrameProps {
  item: LayoutItem
  def: WidgetDef
  editing?: boolean
  /** where this widget sits among the ones on screen, for the announcement */
  position?: { index: number; total: number }
  onMove?: (id: string, offset: number) => void
  onSize?: (id: string, size: WidgetSize) => void
  onRemove?: (id: string) => void
  /** props the drag sensor needs on the handle; absent means no dragging */
  dragHandleProps?: Record<string, unknown>
  dragging?: boolean
  style?: React.CSSProperties
  innerRef?: (node: HTMLElement | null) => void
}

export function WidgetFrame({
  item,
  def,
  editing,
  position,
  onMove,
  onSize,
  onRemove,
  dragHandleProps,
  dragging,
  style,
  innerRef,
}: WidgetFrameProps) {
  const height = bodyHeight(item.size, item.h)

  return (
    <div
      ref={innerRef}
      style={style}
      role="listitem"
      aria-label={def.title}
      className={cx(
        SPAN[item.size],
        'relative min-w-0',
        editing && 'rounded-xl ring-1 ring-line-strong',
        dragging && 'z-10 opacity-80',
      )}
    >
      <div className={cx(editing && 'pointer-events-none select-none')}>
        <WidgetBoundary id={def.id} title={def.title}>
          <def.Component size={item.size} height={height} opts={item.opts ?? {}} />
        </WidgetBoundary>
      </div>

      {editing && (
        <EditBar
          item={item}
          def={def}
          position={position}
          onMove={onMove}
          onSize={onSize}
          onRemove={onRemove}
          dragHandleProps={dragHandleProps}
        />
      )}
    </div>
  )
}

/* ===== edit affordances ===================================================
   Three ways to do the same thing, all calling the same `onMove`: drag from
   the handle, the two arrows, and the menu's jump-to-edge. The arrows are not
   a fallback — they are how this works on a keyboard and how a twenty-widget
   reshuffle stays bearable.                                                 */

function EditBar({
  item,
  def,
  position,
  onMove,
  onSize,
  onRemove,
  dragHandleProps,
}: Pick<WidgetFrameProps, 'item' | 'def' | 'position' | 'onMove' | 'onSize' | 'onRemove' | 'dragHandleProps'>) {
  const first = position ? position.index === 0 : false
  const last = position ? position.index === position.total - 1 : false

  return (
    <div className="absolute inset-x-1 top-1 flex items-center gap-1 rounded-lg border border-line bg-raised/95 p-1 shadow-sm backdrop-blur">
      <button
        type="button"
        aria-label={`גרירת ${def.title}`}
        className="cursor-grab rounded p-1 text-ink-tertiary hover:bg-hover hover:text-ink active:cursor-grabbing"
        {...dragHandleProps}
      >
        <GripVertical size={ICON.md} strokeWidth={STROKE} aria-hidden />
      </button>

      {/* "אחורה" and "קדימה" describe intent; the glyph flips with the
          direction so the arrow always points where the widget will go */}
      <IconButton
        size="sm"
        variant="ghost"
        label="הזז אחורה"
        disabled={first}
        onClick={() => onMove?.(item.id, -1)}
      >
        <ChevronRight size={ICON.md} strokeWidth={STROKE} className="rtl:rotate-180" aria-hidden />
      </IconButton>
      <IconButton size="sm" variant="ghost" label="הזז קדימה" disabled={last} onClick={() => onMove?.(item.id, 1)}>
        <ChevronLeft size={ICON.md} strokeWidth={STROKE} className="rtl:rotate-180" aria-hidden />
      </IconButton>

      {def.sizes.length > 1 && (
        <SegmentedControl<WidgetSize>
          value={item.size}
          onChange={(s) => onSize?.(item.id, s)}
          items={def.sizes.map((s) => ({ key: s, label: SIZE_LABELS[s] }))}
          className="hidden sm:inline-flex"
        />
      )}

      <span className="ms-auto flex items-center gap-0.5">
        <Popover
          align="end"
          trigger={(p) => (
            <IconButton size="sm" variant="ghost" label="עוד" {...p}>
              <MoreVertical size={ICON.md} strokeWidth={STROKE} aria-hidden />
            </IconButton>
          )}
        >
          {(close) => (
            <>
              <MenuItem
                disabled={first}
                onClick={() => {
                  onMove?.(item.id, -Infinity)
                  close()
                }}
              >
                הזז לראש
              </MenuItem>
              <MenuItem
                disabled={last}
                onClick={() => {
                  onMove?.(item.id, Infinity)
                  close()
                }}
              >
                הזז לסוף
              </MenuItem>
              {/* the segmented control has no room on a phone, so the sizes
                  live here too rather than being unreachable on touch */}
              {def.sizes.length > 1 && (
                <span className="sm:hidden">
                  <MenuSeparator />
                  <MenuLabel>גודל</MenuLabel>
                  {def.sizes.map((s) => (
                    <MenuItem
                      key={s}
                      disabled={s === item.size}
                      onClick={() => {
                        onSize?.(item.id, s)
                        close()
                      }}
                    >
                      {SIZE_LABELS[s]}
                    </MenuItem>
                  ))}
                </span>
              )}
            </>
          )}
        </Popover>
        <IconButton size="sm" variant="ghost" label={`הסרת ${def.title}`} onClick={() => onRemove?.(item.id)}>
          <X size={ICON.md} strokeWidth={STROKE} aria-hidden />
        </IconButton>
      </span>
    </div>
  )
}
