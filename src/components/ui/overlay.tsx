import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useId,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from 'react'
import type { ReactNode, MouseEvent as ReactMouseEvent } from 'react'
import { createPortal } from 'react-dom'
import { AlertTriangle, Check, Info, Undo2, X, XCircle } from 'lucide-react'
import { Button, IconButton, cx } from './primitives'

/* ===== shared overlay plumbing ============================================ */

let lockCount = 0
function useScrollLock(active: boolean) {
  useLayoutEffect(() => {
    if (!active) return
    if (lockCount === 0) {
      const pad = window.innerWidth - document.documentElement.clientWidth
      document.body.style.overflow = 'hidden'
      if (pad > 0) document.body.style.paddingInlineEnd = `${pad}px`
    }
    lockCount++
    return () => {
      lockCount--
      if (lockCount === 0) {
        document.body.style.overflow = ''
        document.body.style.paddingInlineEnd = ''
      }
    }
  }, [active])
}

const FOCUSABLE =
  'a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])'

/** Traps Tab inside the panel, restores focus to the opener on close. */
function useFocusTrap(active: boolean, onClose: () => void) {
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (!active) return
    const opener = document.activeElement as HTMLElement | null
    const panel = ref.current
    const first = panel?.querySelector<HTMLElement>('[data-autofocus]') ?? panel?.querySelector<HTMLElement>(FOCUSABLE)
    first?.focus()

    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation()
        onClose()
        return
      }
      if (e.key !== 'Tab' || !panel) return
      const nodes = Array.from(panel.querySelectorAll<HTMLElement>(FOCUSABLE)).filter(
        (n) => n.offsetParent !== null || n === document.activeElement,
      )
      if (nodes.length === 0) return
      const firstEl = nodes[0]
      const lastEl = nodes[nodes.length - 1]
      if (e.shiftKey && document.activeElement === firstEl) {
        e.preventDefault()
        lastEl.focus()
      } else if (!e.shiftKey && document.activeElement === lastEl) {
        e.preventDefault()
        firstEl.focus()
      }
    }
    document.addEventListener('keydown', onKey, true)
    return () => {
      document.removeEventListener('keydown', onKey, true)
      opener?.focus?.()
    }
  }, [active, onClose])
  return ref
}

/** Keeps the node mounted long enough to play the closing animation. */
function usePresence(open: boolean, ms = 150) {
  const [present, setPresent] = useState(open)
  useEffect(() => {
    if (open) {
      setPresent(true)
      return
    }
    const t = setTimeout(() => setPresent(false), ms)
    return () => clearTimeout(t)
  }, [open, ms])
  return present
}

/* ===== Modal ============================================================== */

export type ModalSize = 'sm' | 'md' | 'lg' | 'xl' | 'full'

const MODAL_WIDTHS: Record<ModalSize, string> = {
  sm: 'max-w-sm',
  md: 'max-w-lg',
  lg: 'max-w-3xl',
  xl: 'max-w-5xl',
  full: 'max-w-[min(96rem,calc(100vw-2rem))]',
}

export function Modal({
  open,
  onClose,
  title,
  description,
  children,
  wide,
  size,
  footer,
  /** hide the built-in header (for fully custom shells) */
  bare,
}: {
  open: boolean
  onClose: () => void
  title: ReactNode
  description?: ReactNode
  children: ReactNode
  /** legacy: equivalent to size="lg" */
  wide?: boolean
  size?: ModalSize
  footer?: ReactNode
  bare?: boolean
}) {
  const present = usePresence(open)
  const panelRef = useFocusTrap(open, onClose)
  const labelId = useId()
  const descId = useId()
  useScrollLock(present)

  if (!present) return null

  return createPortal(
    <div
      className={cx(
        'fixed inset-0 z-50 flex items-start justify-center overflow-y-auto scrim p-3 py-6 sm:p-4 sm:py-14',
        'transition-opacity duration-150',
        open ? 'opacity-100' : 'opacity-0',
      )}
      onMouseDown={(e) => e.target === e.currentTarget && onClose()}
    >
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={labelId}
        aria-describedby={description ? descId : undefined}
        className={cx(
          'surface-overlay my-auto w-full transition-all duration-200 ease-[cubic-bezier(.16,1,.3,1)]',
          MODAL_WIDTHS[size ?? (wide ? 'lg' : 'md')],
          open ? 'translate-y-0 scale-100 opacity-100' : 'translate-y-1 scale-[.98] opacity-0',
        )}
      >
        {!bare && (
          <div className="flex items-start gap-3 border-b border-line-subtle px-4 py-3.5 sm:px-5">
            <div className="min-w-0 flex-1">
              <h2 id={labelId} className="type-title">
                {title}
              </h2>
              {description && (
                <p id={descId} className="mt-0.5 type-caption text-ink-tertiary">
                  {description}
                </p>
              )}
            </div>
            <IconButton label="סגירה" size="sm" onClick={onClose} bare className="-me-1.5 -mt-1">
              <X size={16} />
            </IconButton>
          </div>
        )}
        {/* dvh, not vh: mobile browsers shrink the viewport when the URL bar
            and the on-screen keyboard appear, and vh does not follow */}
        <div className="max-h-[70dvh] overflow-y-auto overscroll-contain p-4 sm:max-h-[calc(100dvh-14rem)] sm:p-5">
          {children}
        </div>
        {footer && (
          <div className="flex flex-wrap items-center justify-end gap-2 border-t border-line-subtle bg-subtle/60 px-4 py-3 sm:px-5">
            {footer}
          </div>
        )}
      </div>
    </div>,
    document.body,
  )
}

/* ===== Drawer ============================================================= */

export function Drawer({
  open,
  onClose,
  title,
  description,
  children,
  footer,
  width = 'max-w-xl',
}: {
  open: boolean
  onClose: () => void
  title: ReactNode
  description?: ReactNode
  children: ReactNode
  footer?: ReactNode
  width?: string
}) {
  const present = usePresence(open, 200)
  const panelRef = useFocusTrap(open, onClose)
  const labelId = useId()
  useScrollLock(present)

  if (!present) return null

  return createPortal(
    <div
      className={cx('fixed inset-0 z-50 scrim transition-opacity duration-200', open ? 'opacity-100' : 'opacity-0')}
      onMouseDown={(e) => e.target === e.currentTarget && onClose()}
    >
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={labelId}
        className={cx(
          'absolute inset-y-0 start-0 flex w-full flex-col border-e border-line bg-surface shadow-overlay',
          'transition-transform duration-200 ease-[cubic-bezier(.16,1,.3,1)]',
          width,
          open ? 'translate-x-0' : 'ltr:-translate-x-full rtl:translate-x-full',
        )}
      >
        <div className="flex items-start gap-3 border-b border-line-subtle px-4 py-3.5 sm:px-5">
          <div className="min-w-0 flex-1">
            <h2 id={labelId} className="type-title">
              {title}
            </h2>
            {description && <p className="mt-0.5 type-caption text-ink-tertiary">{description}</p>}
          </div>
          <IconButton label="סגירה" size="sm" onClick={onClose} bare className="-me-1.5 -mt-1">
            <X size={16} />
          </IconButton>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain p-4 sm:p-5">{children}</div>
        {footer && (
          <div className="flex flex-wrap items-center justify-end gap-2 border-t border-line-subtle bg-subtle/60 px-4 py-3 pb-[calc(0.75rem+var(--vl-safe-bottom))] sm:px-5">
            {footer}
          </div>
        )}
      </div>
    </div>,
    document.body,
  )
}

/* ===== Popover ============================================================
   Anchored, dismiss-on-outside-click panel. Used for menus in the header.

   The panel is measured and placed in a portal rather than laid out by CSS
   against its trigger. Two reasons, both of which bit us: `end-0` under RTL
   pins the panel's *left* edge to a trigger that sits at the visual left of
   the screen, so the panel grew straight off the right edge of a phone; and
   the board renders inside an `overflow-hidden` main, which clipped whatever
   did fit. Measuring lets the panel keep its anchor and still stay on
   screen — the same trick Tooltip and useContextMenu already use.          */

const GAP = 6
const EDGE = 8

interface PanelPos {
  top: number
  left: number
  maxHeight: number
}

export function Popover({
  trigger,
  children,
  align = 'end',
  className,
  panelClassName,
}: {
  /** the spread rest is aria-only, so `{...aria}` never lands a stray DOM attribute */
  trigger: (props: { toggle: () => void; 'aria-expanded': boolean; 'aria-haspopup': 'menu' }) => ReactNode
  children: (close: () => void) => ReactNode
  align?: 'start' | 'end'
  className?: string
  panelClassName?: string
}) {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  const panel = useRef<HTMLDivElement>(null)
  const [pos, setPos] = useState<PanelPos | null>(null)
  const close = useCallback(() => {
    setOpen(false)
    setPos(null)
  }, [])

  const place = useCallback(() => {
    if (!ref.current || !panel.current) return
    const a = ref.current.getBoundingClientRect()
    const p = panel.current.getBoundingClientRect()
    const rtl = getComputedStyle(document.documentElement).direction === 'rtl'

    /* `align` is logical, so resolve it against the document's direction
       rather than assuming a side — `end` means the panel's end edge meets
       the trigger's end edge, which is the left pair under RTL. */
    const toStart = align === 'end' ? rtl : !rtl
    let left = toStart ? a.left : a.right - p.width
    left = Math.max(EDGE, Math.min(left, window.innerWidth - p.width - EDGE))

    /* Below the trigger by default; above it when that's where the room is.
       Whichever side wins, the panel is capped to the space it actually has
       and scrolls inside itself instead of running past the edge. */
    const below = window.innerHeight - a.bottom - GAP - EDGE
    const above = a.top - GAP - EDGE
    const flip = p.height > below && above > below
    setPos({
      top: flip ? Math.max(EDGE, a.top - GAP - Math.min(p.height, above)) : a.bottom + GAP,
      left,
      maxHeight: Math.max(120, flip ? above : below),
    })
  }, [align])

  useLayoutEffect(() => {
    if (open) place()
  }, [open, place])

  useEffect(() => {
    if (!open) return
    const onDown = (e: MouseEvent) => {
      const t = e.target as Node
      /* the panel no longer lives inside the trigger's subtree, so a click in
         it would otherwise read as a click outside */
      if (!ref.current?.contains(t) && !panel.current?.contains(t)) close()
    }
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && close()
    const onMove = (e: Event) => {
      /* scrolling the panel's own list must not drag the panel around */
      if (e.target instanceof Node && panel.current?.contains(e.target)) return
      place()
    }
    document.addEventListener('mousedown', onDown)
    document.addEventListener('keydown', onKey)
    window.addEventListener('scroll', onMove, true)
    window.addEventListener('resize', place)
    return () => {
      document.removeEventListener('mousedown', onDown)
      document.removeEventListener('keydown', onKey)
      window.removeEventListener('scroll', onMove, true)
      window.removeEventListener('resize', place)
    }
  }, [open, close, place])

  return (
    <div ref={ref} className={cx('relative', className)}>
      {trigger({ toggle: () => setOpen((v) => !v), 'aria-expanded': open, 'aria-haspopup': 'menu' })}
      {open &&
        createPortal(
          <div
            ref={panel}
            className={cx(
              'fixed z-[60] min-w-52 max-w-[calc(100vw-1rem)] origin-top animate-scale-in',
              'rounded-xl border border-line bg-raised p-1 shadow-lg',
              panelClassName,
            )}
            /* inline, not a class: a caller's own `overflow-hidden` would win
               the cascade otherwise, and a capped panel that cannot scroll is
               just a shorter way to hide content */
            style={{
              top: pos?.top ?? -9999,
              left: pos?.left ?? -9999,
              maxHeight: pos?.maxHeight,
              overflowY: 'auto',
              visibility: pos ? 'visible' : 'hidden',
            }}
          >
            {children(close)}
          </div>,
          document.body,
        )}
    </div>
  )
}

/** A row inside a Popover / ContextMenu. */
export function MenuItem({
  icon,
  children,
  onClick,
  danger,
  disabled,
  shortcut,
}: {
  icon?: ReactNode
  children: ReactNode
  onClick?: () => void
  danger?: boolean
  disabled?: boolean
  shortcut?: ReactNode
}) {
  return (
    <button
      type="button"
      role="menuitem"
      disabled={disabled}
      onClick={onClick}
      className={cx(
        'flex w-full items-center gap-2.5 rounded-lg px-2.5 py-1.5 text-start text-sm transition-colors',
        'disabled:pointer-events-none disabled:opacity-45',
        danger ? 'text-error-text hover:bg-error-subtle' : 'text-ink hover:bg-hover',
      )}
    >
      {icon && <span className="shrink-0 text-ink-tertiary">{icon}</span>}
      <span className="min-w-0 flex-1 truncate">{children}</span>
      {shortcut && <span className="shrink-0 type-caption text-ink-tertiary">{shortcut}</span>}
    </button>
  )
}

export function MenuSeparator() {
  return <div className="my-1 h-px bg-line-subtle" role="separator" />
}

export function MenuLabel({ children }: { children: ReactNode }) {
  return <div className="px-2.5 pb-1 pt-2 type-overline">{children}</div>
}

/* ===== ContextMenu ========================================================
   Right-click menu positioned at the pointer and kept inside the viewport. */

export interface ContextMenuItem {
  key: string
  label: ReactNode
  icon?: ReactNode
  onClick?: () => void
  danger?: boolean
  disabled?: boolean
  separator?: boolean
}

export function useContextMenu() {
  const [state, setState] = useState<{ x: number; y: number; items: ContextMenuItem[] } | null>(null)
  const ref = useRef<HTMLDivElement>(null)
  const [pos, setPos] = useState<{ top: number; left: number } | null>(null)

  const close = useCallback(() => {
    setState(null)
    setPos(null)
  }, [])

  const openMenu = useCallback((e: { clientX: number; clientY: number; preventDefault?: () => void }, items: ContextMenuItem[]) => {
    e.preventDefault?.()
    setState({ x: e.clientX, y: e.clientY, items })
  }, [])

  useLayoutEffect(() => {
    if (!state || !ref.current) return
    const r = ref.current.getBoundingClientRect()
    setPos({
      top: Math.min(state.y, window.innerHeight - r.height - 8),
      left: Math.min(Math.max(8, state.x - r.width), window.innerWidth - r.width - 8),
    })
  }, [state])

  useEffect(() => {
    if (!state) return
    const onDown = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) close()
    }
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && close()
    document.addEventListener('mousedown', onDown)
    document.addEventListener('keydown', onKey)
    window.addEventListener('scroll', close, true)
    window.addEventListener('resize', close)
    return () => {
      document.removeEventListener('mousedown', onDown)
      document.removeEventListener('keydown', onKey)
      window.removeEventListener('scroll', close, true)
      window.removeEventListener('resize', close)
    }
  }, [state, close])

  const menu = state
    ? createPortal(
        <div
          ref={ref}
          role="menu"
          className="fixed z-[70] min-w-52 animate-scale-in rounded-xl border border-line bg-raised p-1 shadow-overlay"
          style={{ top: pos?.top ?? -9999, left: pos?.left ?? -9999, visibility: pos ? 'visible' : 'hidden' }}
        >
          {state.items.map((it) =>
            it.separator ? (
              <MenuSeparator key={it.key} />
            ) : (
              <MenuItem
                key={it.key}
                icon={it.icon}
                danger={it.danger}
                disabled={it.disabled}
                onClick={() => {
                  close()
                  it.onClick?.()
                }}
              >
                {it.label}
              </MenuItem>
            ),
          )}
        </div>,
        document.body,
      )
    : null

  return { openMenu, closeMenu: close, menu }
}

/* ===== Toasts =============================================================
   success / error / warning / info, each dismissible and optionally paired
   with an Undo action.                                                     */

export type ToastKind = 'success' | 'error' | 'warning' | 'info'

export interface ToastOptions {
  /** shows an "בטל" button; the toast closes once it is used */
  undo?: () => void
  description?: string
  /** ms before auto-dismiss; 0 keeps it until dismissed */
  duration?: number
}

interface Toast extends ToastOptions {
  id: number
  kind: ToastKind
  text: string
  leaving?: boolean
}

const ToastCtx = createContext<{
  push: (kind: ToastKind, text: string, opts?: ToastOptions) => number
  dismiss: (id: number) => void
}>({ push: () => 0, dismiss: () => {} })

let toastSeq = 1

const TOAST_STYLE: Record<ToastKind, { cls: string; icon: ReactNode }> = {
  success: { cls: 'border-success-border bg-success-subtle text-success-text', icon: <Check size={16} /> },
  error: { cls: 'border-error-border bg-error-subtle text-error-text', icon: <XCircle size={16} /> },
  warning: { cls: 'border-warning-border bg-warning-subtle text-warning-text', icon: <AlertTriangle size={16} /> },
  info: { cls: 'border-info-border bg-info-subtle text-info-text', icon: <Info size={16} /> },
}

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([])
  const timers = useRef(new Map<number, ReturnType<typeof setTimeout>>())

  const remove = useCallback((id: number) => {
    setToasts((t) => t.filter((x) => x.id !== id))
    const h = timers.current.get(id)
    if (h) {
      clearTimeout(h)
      timers.current.delete(id)
    }
  }, [])

  const dismiss = useCallback(
    (id: number) => {
      setToasts((t) => t.map((x) => (x.id === id ? { ...x, leaving: true } : x)))
      setTimeout(() => remove(id), 160)
    },
    [remove],
  )

  const push = useCallback(
    (kind: ToastKind, text: string, opts?: ToastOptions) => {
      const id = toastSeq++
      const duration = opts?.duration ?? (opts?.undo ? 8000 : kind === 'error' ? 7000 : 4500)
      setToasts((t) => [...t.slice(-4), { id, kind, text, ...opts }])
      if (duration > 0) timers.current.set(id, setTimeout(() => dismiss(id), duration))
      return id
    },
    [dismiss],
  )

  useEffect(() => {
    const map = timers.current
    return () => map.forEach(clearTimeout)
  }, [])

  const value = useMemo(() => ({ push, dismiss }), [push, dismiss])

  return (
    <ToastCtx.Provider value={value}>
      {children}
      {createPortal(
        <div
          className={cx(
            'pointer-events-none fixed start-3 z-[80] flex flex-col gap-2 sm:start-4',
            // clears the mobile bottom bar; back to the corner once it's gone
            'bottom-shell lg:bottom-4',
            'w-[min(24rem,calc(100vw-1.5rem))]',
          )}
          role="region"
          aria-live="polite"
          aria-label="התראות מערכת"
        >
          {toasts.map((t) => {
            const s = TOAST_STYLE[t.kind]
            return (
              <div
                key={t.id}
                /* The region is `polite`, which is right for a save confirmation
                   and wrong for the ~40 places where a red toast is the only
                   sign a mutation failed: polite waits for the reader to finish
                   whatever it was saying, and by then the user has moved on
                   believing the thing worked. An `alert` on the item itself
                   overrides the region for that one node, so failures interrupt
                   and successes still wait their turn. */
                role={t.kind === 'error' ? 'alert' : undefined}
                className={cx(
                  'pointer-events-auto flex items-start gap-2.5 rounded-xl border p-3 shadow-lg backdrop-blur-sm',
                  'transition-all duration-150 ease-[cubic-bezier(.16,1,.3,1)]',
                  s.cls,
                  t.leaving ? 'translate-y-1 scale-[.98] opacity-0' : 'animate-slide-up',
                )}
              >
                <span className="mt-px shrink-0" aria-hidden>
                  {s.icon}
                </span>
                <div className="min-w-0 flex-1">
                  <p className="type-body font-medium text-ink">{t.text}</p>
                  {t.description && <p className="mt-0.5 type-caption text-ink-secondary">{t.description}</p>}
                </div>
                {t.undo && (
                  <Button
                    size="sm"
                    variant="ghost"
                    className="-my-1 shrink-0 text-current"
                    onClick={() => {
                      t.undo?.()
                      dismiss(t.id)
                    }}
                  >
                    <Undo2 size={13} />
                    בטל
                  </Button>
                )}
                <IconButton
                  label="סגירת ההתראה"
                  size="sm"
                  bare
                  className="-my-1 -me-1 shrink-0 text-current opacity-60 hover:opacity-100"
                  onClick={() => dismiss(t.id)}
                >
                  <X size={14} />
                </IconButton>
              </div>
            )
          })}
        </div>,
        document.body,
      )}
    </ToastCtx.Provider>
  )
}

export function useToast() {
  const { push, dismiss } = useContext(ToastCtx)
  return useMemo(
    () => ({
      success: (text: string, opts?: ToastOptions) => push('success', text, opts),
      error: (text: string, opts?: ToastOptions) => push('error', text, opts),
      warning: (text: string, opts?: ToastOptions) => push('warning', text, opts),
      info: (text: string, opts?: ToastOptions) => push('info', text, opts),
      dismiss,
    }),
    [push, dismiss],
  )
}

/* ===== Confirm ============================================================ */

export interface ConfirmOptions {
  title?: string
  confirmLabel?: string
  cancelLabel?: string
  tone?: 'danger' | 'primary'
}

export function useConfirm() {
  const [state, setState] = useState<{ text: string; opts: ConfirmOptions; resolve: (v: boolean) => void } | null>(null)

  const confirm = useCallback(
    (text: string, opts: ConfirmOptions = {}) => new Promise<boolean>((resolve) => setState({ text, opts, resolve })),
    [],
  )

  const settle = (v: boolean) => {
    state?.resolve(v)
    setState(null)
  }

  const tone = state?.opts.tone ?? 'danger'

  const dialog = state ? (
    <Modal
      open
      onClose={() => settle(false)}
      size="sm"
      title={state.opts.title ?? 'אישור פעולה'}
      footer={
        <>
          <Button onClick={() => settle(false)}>{state.opts.cancelLabel ?? 'ביטול'}</Button>
          <Button variant={tone === 'danger' ? 'danger' : 'primary'} data-autofocus onClick={() => settle(true)}>
            {state.opts.confirmLabel ?? 'אישור'}
          </Button>
        </>
      }
    >
      <div className="flex gap-3">
        <span
          className={cx(
            'flex size-9 shrink-0 items-center justify-center rounded-full',
            tone === 'danger' ? 'bg-error-subtle text-error-text' : 'bg-primary-subtle text-primary-text',
          )}
          aria-hidden
        >
          <AlertTriangle size={17} />
        </span>
        <p className="pt-1.5 type-body text-ink-secondary">{state.text}</p>
      </div>
    </Modal>
  ) : null

  return { confirm, dialog }
}

/* ===== Prompt =============================================================
   A themed replacement for window.prompt() — same await-a-value shape.     */

export function usePrompt() {
  const [state, setState] = useState<{
    label: string
    initial: string
    opts: { title?: string; placeholder?: string; confirmLabel?: string }
    resolve: (v: string | null) => void
  } | null>(null)
  const [draft, setDraft] = useState('')

  const prompt = useCallback(
    (label: string, initial = '', opts: { title?: string; placeholder?: string; confirmLabel?: string } = {}) =>
      new Promise<string | null>((resolve) => {
        setDraft(initial)
        setState({ label, initial, opts, resolve })
      }),
    [],
  )

  const settle = (v: string | null) => {
    state?.resolve(v)
    setState(null)
  }

  const dialog = state ? (
    <Modal
      open
      onClose={() => settle(null)}
      size="sm"
      title={state.opts.title ?? state.label}
      footer={
        <>
          <Button onClick={() => settle(null)}>ביטול</Button>
          <Button variant="primary" disabled={!draft.trim()} onClick={() => settle(draft.trim())}>
            {state.opts.confirmLabel ?? 'שמירה'}
          </Button>
        </>
      }
    >
      <form
        onSubmit={(e: ReactMouseEvent | React.FormEvent) => {
          e.preventDefault()
          if (draft.trim()) settle(draft.trim())
        }}
      >
        <label className="mb-1.5 block type-caption font-medium text-ink-secondary">{state.label}</label>
        <input
          data-autofocus
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder={state.opts.placeholder}
          className={cx(
            'h-9 w-full rounded-md border border-line bg-surface px-3 text-sm outline-none',
            'focus:border-primary focus:ring-2 focus:ring-[var(--vl-focus-ring)] placeholder:text-ink-tertiary',
          )}
        />
      </form>
    </Modal>
  ) : null

  return { prompt, dialog }
}
