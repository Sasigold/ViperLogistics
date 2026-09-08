import { Component } from 'react'
import type { CSSProperties, ErrorInfo, ReactNode } from 'react'
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
  Tooltip,
  cx,
} from '../../components/ui'
import {
  ChevronLeft,
  ChevronRight,
  GripVertical,
  ICON,
  Lock,
  LockOpen,
  MoreVertical,
  STROKE,
  SlidersHorizontal,
  X,
} from '../../components/ui/icons'
import { reportError } from '../../lib/reportError'
import { SIZE_LABELS, SPAN, bodyHeight, panelMaxHeight } from './layout'
import { WidgetOptions, hasWidgetOptions } from './WidgetOptions'
import type { LayoutItem, Packing, WidgetDef, WidgetSize } from './dashboardTypes'

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
  /** how the grid closes the space a short card leaves under itself */
  packing?: Packing
  /** where this widget sits among the ones on screen, for the announcement */
  position?: { index: number; total: number }
  onMove?: (id: string, offset: number) => void
  onSize?: (id: string, size: WidgetSize) => void
  onHeight?: (id: string, h: 'auto' | 'tall') => void
  onRemove?: (id: string) => void
  /** writes one key of this placement's options; absent means the reader may not */
  onOpt?: (id: string, key: string, value: string | number | boolean | undefined) => void
  /** administrator's flag: the ✕ is gone and the catalogue's switch is stuck on */
  onLock?: (id: string, on: boolean) => void
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
  packing = 'aligned',
  position,
  onMove,
  onSize,
  onHeight,
  onRemove,
  onOpt,
  onLock,
  dragHandleProps,
  dragging,
  style,
  innerRef,
}: WidgetFrameProps) {
  const height = bodyHeight(item.size, item.h)
  /* 0 for a KPI tile, which sizes to its content. For everything else this is
     both the ceiling and the reason the row can be filled: a panel that cannot
     run away is a panel its neighbours can safely match. */
  const maxHeight = panelMaxHeight(item.size, item.h)
  const compact = packing === 'compact'
  /* Offered outside edit mode too, and that is the point of it: changing a
     chart to a table is a question about *this* reading of the data, not an
     act of rearranging the page. Edit mode is for moving furniture. */
  const settings = onOpt && hasWidgetOptions(def)

  return (
    <div
      ref={innerRef}
      style={style}
      role="listitem"
      aria-label={def.title}
      className={cx(
        SPAN[item.size],
        'group/widget relative min-w-0',
        /* A KPI tile keeps its natural height — stretching a two-line number to
           a chart's height is not tidiness, it is a tall empty tile. Panels take
           the row's full height so their borders line up with each other —
           unless the whole view asked for `compact`, where nothing is stretched
           and the holes that leaves are packed by the grid instead. */
        (maxHeight === 0 || compact) && 'self-start',
        /* A widget may legitimately draw nothing: an unpermitted section, a
           custom widget whose spec the catalogue no longer serves, "no events
           booked". The slot itself is still a grid item, so it keeps its columns
           and its share of the row gap — an invisible hole in the arrangement.
           Nothing rendered means the inner wrapper has no element children,
           which is the one thing CSS can see from out here. In edit mode the
           empty slot stays visible: you cannot remove what isn't drawn. */
        !editing && '[&:has(>div:empty)]:hidden',
        /* the floor is for that same empty slot: edit mode is the only place it
           is visible, so it has to be tall enough to hold the bar that removes
           it — otherwise the one widget you cannot see is the one you cannot
           get rid of */
        editing && 'min-h-14 rounded-xl ring-1 ring-line-strong',
        dragging && 'z-10 opacity-80',
      )}
    >
      <div
        /* a custom property rather than `max-height` directly: `widget-fill`
           applies it from the `lg` breakpoint up, and an inline declaration
           would win over every media query in the stylesheet */
        style={maxHeight ? ({ '--panel-max': `${maxHeight}px` } as CSSProperties) : undefined}
        className={cx(
          maxHeight > 0 && (compact ? 'widget-cap' : 'widget-fill'),
          !editing && settings && 'widget-corner',
          editing && 'pointer-events-none select-none',
        )}
      >
        <WidgetBoundary id={def.id} title={def.title}>
          <def.Component size={item.size} height={height} opts={item.opts ?? {}} />
        </WidgetBoundary>
      </div>

      {/* Reading mode: one affordance, and it stays out of the way until the
          pointer is on the card. On touch there is no hover to wait for, so it
          is simply always faintly there. */}
      {!editing && settings && (
        <span
          className={cx(
            'absolute top-1.5 end-1.5 z-10 transition-opacity duration-150',
            'opacity-0 group-hover/widget:opacity-100 group-focus-within/widget:opacity-100',
            '[@media(pointer:coarse)]:opacity-60',
          )}
        >
          <Popover
            align="end"
            trigger={({ toggle, ...aria }) => (
              <IconButton
                size="sm"
                variant="ghost"
                label={`תצוגת ${def.title}`}
                onClick={toggle}
                className="bg-raised/90 shadow-sm backdrop-blur"
                {...aria}
              >
                <SlidersHorizontal size={ICON.md} strokeWidth={STROKE} aria-hidden />
              </IconButton>
            )}
          >
            {() => (
              <WidgetOptions
                def={def}
                opts={item.opts ?? {}}
                onOpt={(key, value) => onOpt?.(item.id, key, value)}
              />
            )}
          </Popover>
        </span>
      )}

      {editing && (
        <EditBar
          item={item}
          def={def}
          position={position}
          onMove={onMove}
          onSize={onSize}
          onHeight={onHeight}
          onRemove={onRemove}
          onOpt={onOpt}
          onLock={onLock}
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
  onHeight,
  onRemove,
  onOpt,
  onLock,
  dragHandleProps,
}: Pick<
  WidgetFrameProps,
  | 'item'
  | 'def'
  | 'position'
  | 'onMove'
  | 'onSize'
  | 'onHeight'
  | 'onRemove'
  | 'onOpt'
  | 'onLock'
  | 'dragHandleProps'
>) {
  const first = position ? position.index === 0 : false
  const last = position ? position.index === position.total - 1 : false
  const settings = onOpt && hasWidgetOptions(def)
  /* Every panel is offered the taller body, not only the ones that declared
     `resizableHeight`: the frame now holds a panel to its size's height, so
     "make it taller" is the answer for a list of eight whose last three sit
     below the fold. A KPI tile has no body height to grow. */
  const resizable = bodyHeight(item.size) > 0
  const tall = item.h === 'tall'

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

      {/* the bar sits over the widget's own header, so it has to say which
          widget is being moved — otherwise you are arranging blank rectangles */}
      <span className="flex min-w-0 flex-1 items-center gap-1 truncate type-caption font-semibold">
        {def.title}
        {item.lock && (
          <Tooltip content="נקבע על ידי מנהל המערכת">
            <Lock size={ICON.sm} strokeWidth={STROKE} className="shrink-0 text-ink-tertiary" aria-hidden />
          </Tooltip>
        )}
      </span>

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

      <span className="flex shrink-0 items-center gap-0.5">
        <Popover
          align="end"
          /* `onClick={toggle}`, not `{...p}`: spreading the whole trigger
             object put `toggle` on the DOM node, so this menu — the only route
             to "move to the top", the size list on a phone and the height —
             never opened at all. */
          trigger={({ toggle, ...aria }) => (
            <IconButton size="sm" variant="ghost" label="עוד" onClick={toggle} {...aria}>
              <MoreVertical size={ICON.md} strokeWidth={STROKE} aria-hidden />
            </IconButton>
          )}
        >
          {(close) => (
            <>
              {settings && (
                <>
                  <WidgetOptions
                    def={def}
                    opts={item.opts ?? {}}
                    onOpt={(key, value) => onOpt?.(item.id, key, value)}
                  />
                  <MenuSeparator />
                </>
              )}
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

              {/* Width is the segmented control's job; height is here, because
                  it is the escape hatch for the one panel whose content the
                  standard height cuts off. */}
              {resizable && onHeight && (
                <>
                  <MenuSeparator />
                  <MenuLabel>גובה</MenuLabel>
                  <MenuItem
                    disabled={!tall}
                    onClick={() => {
                      onHeight(item.id, 'auto')
                      close()
                    }}
                  >
                    רגיל
                  </MenuItem>
                  <MenuItem
                    disabled={tall}
                    onClick={() => {
                      onHeight(item.id, 'tall')
                      close()
                    }}
                  >
                    גבוה
                  </MenuItem>
                </>
              )}
              {/* Only where somebody may publish a default. Locking a widget on
                  your own layout would mean locking yourself out of your own
                  screen, so the caller passes `onLock` and nobody else sees it. */}
              {onLock && (
                <>
                  <MenuSeparator />
                  <MenuItem
                    icon={
                      item.lock ? (
                        <LockOpen size={ICON.md} strokeWidth={STROKE} aria-hidden />
                      ) : (
                        <Lock size={ICON.md} strokeWidth={STROKE} aria-hidden />
                      )
                    }
                    onClick={() => {
                      onLock(item.id, !item.lock)
                      close()
                    }}
                  >
                    {item.lock ? 'שחרור הנעילה' : 'נעילה למשתמשים'}
                  </MenuItem>
                </>
              )}
            </>
          )}
        </Popover>
        {/* A locked placement keeps every other affordance — it can be moved,
            resized and re-drawn. What it cannot be is gone. */}
        <IconButton
          size="sm"
          variant="ghost"
          label={item.lock ? `${def.title} נעול ואי אפשר להסירו` : `הסרת ${def.title}`}
          disabled={!!item.lock}
          onClick={() => onRemove?.(item.id)}
        >
          <X size={ICON.md} strokeWidth={STROKE} aria-hidden />
        </IconButton>
      </span>
    </div>
  )
}
