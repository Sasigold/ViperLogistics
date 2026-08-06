import { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react'
import type { ReactNode, ButtonHTMLAttributes, InputHTMLAttributes, SelectHTMLAttributes, TextareaHTMLAttributes } from 'react'
import { createPortal } from 'react-dom'
import { X, Loader2, ChevronDown, Check } from 'lucide-react'

export function cx(...parts: Array<string | false | null | undefined>) {
  return parts.filter(Boolean).join(' ')
}

/* ===== Button ===== */
type BtnVariant = 'primary' | 'secondary' | 'ghost' | 'danger'
export function Button({
  variant = 'secondary',
  loading,
  className,
  children,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: BtnVariant; loading?: boolean }) {
  const styles: Record<BtnVariant, string> = {
    primary: 'bg-brand-600 text-white hover:bg-brand-700 border-transparent',
    secondary: 'bg-[var(--panel)] hover:bg-[var(--bg)] border-[var(--border)]',
    ghost: 'bg-transparent hover:bg-[var(--bg)] border-transparent',
    danger: 'bg-red-600 text-white hover:bg-red-700 border-transparent',
  }
  return (
    <button
      className={cx(
        'inline-flex items-center justify-center gap-1.5 rounded-lg border px-3 py-1.5 text-sm font-medium transition-colors disabled:opacity-50 disabled:pointer-events-none',
        styles[variant],
        className,
      )}
      disabled={loading || rest.disabled}
      {...rest}
    >
      {loading && <Loader2 size={14} className="animate-spin" />}
      {children}
    </button>
  )
}

/* ===== Inputs ===== */
const hasWidth = (className?: string) => !!className && className.split(' ').some((c) => c.startsWith('w-'))

export function Input({ className, ...rest }: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      className={cx(
        !hasWidth(className) && 'w-full',
        'rounded-lg border border-[var(--border)] bg-[var(--panel)] px-3 py-1.5 text-sm outline-none focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 placeholder:text-[var(--muted)]',
        className,
      )}
      {...rest}
    />
  )
}

export function Textarea({ className, ...rest }: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <textarea
      className={cx(
        'w-full rounded-lg border border-[var(--border)] bg-[var(--panel)] px-3 py-1.5 text-sm outline-none focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 placeholder:text-[var(--muted)]',
        className,
      )}
      rows={3}
      {...rest}
    />
  )
}

export function Select({ className, children, ...rest }: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      className={cx(
        !hasWidth(className) && 'w-full',
        'rounded-lg border border-[var(--border)] bg-[var(--panel)] px-3 py-1.5 text-sm outline-none focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20',
        className,
      )}
      {...rest}
    >
      {children}
    </select>
  )
}

export function Checkbox({
  label,
  checked,
  onChange,
  disabled,
}: {
  label: string
  checked: boolean
  onChange: (v: boolean) => void
  disabled?: boolean
}) {
  return (
    <label className={cx('inline-flex items-center gap-2 text-sm cursor-pointer select-none', disabled && 'opacity-50 pointer-events-none')}>
      <input
        type="checkbox"
        className="size-4 accent-brand-600"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
        disabled={disabled}
      />
      {label}
    </label>
  )
}

export function Field({ label, required, children, hint }: { label: string; required?: boolean; children: ReactNode; hint?: string }) {
  return (
    <div className="space-y-1">
      <label className="block text-xs font-medium text-[var(--muted)]">
        {label}
        {required && <span className="text-red-500 ms-0.5">*</span>}
      </label>
      {children}
      {hint && <p className="text-xs text-[var(--muted)]">{hint}</p>}
    </div>
  )
}

/* ===== Badge ===== */
export function Badge({ color, children }: { color?: string; children: ReactNode }) {
  return (
    <span
      className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium"
      style={{
        background: color ? `color-mix(in srgb, ${color} 15%, transparent)` : 'var(--bg)',
        color: color ?? 'var(--muted)',
      }}
    >
      {children}
    </span>
  )
}

/* ===== Modal / Drawer ===== */
export function Modal({
  open,
  onClose,
  title,
  children,
  wide,
}: {
  open: boolean
  onClose: () => void
  title: string
  children: ReactNode
  wide?: boolean
}) {
  useEffect(() => {
    if (!open) return
    const h = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', h)
    return () => window.removeEventListener('keydown', h)
  }, [open, onClose])
  if (!open) return null
  return createPortal(
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 p-4 pt-14" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className={cx('surface w-full shadow-xl', wide ? 'max-w-3xl' : 'max-w-lg')}>
        <div className="flex items-center justify-between border-b border-[var(--border)] px-4 py-3">
          <h2 className="text-sm font-bold">{title}</h2>
          <button onClick={onClose} className="text-[var(--muted)] hover:text-[var(--text)]">
            <X size={16} />
          </button>
        </div>
        <div className="p-4">{children}</div>
      </div>
    </div>,
    document.body,
  )
}

export function Drawer({ open, onClose, title, children }: { open: boolean; onClose: () => void; title: ReactNode; children: ReactNode }) {
  useEffect(() => {
    if (!open) return
    const h = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', h)
    return () => window.removeEventListener('keydown', h)
  }, [open, onClose])
  if (!open) return null
  return createPortal(
    <div className="fixed inset-0 z-50 bg-black/40" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="absolute inset-y-0 start-0 w-full max-w-xl overflow-y-auto border-e border-[var(--border)] bg-[var(--panel)] shadow-2xl">
        <div className="sticky top-0 z-10 flex items-center justify-between border-b border-[var(--border)] bg-[var(--panel)] px-4 py-3">
          <h2 className="text-sm font-bold">{title}</h2>
          <button onClick={onClose} className="text-[var(--muted)] hover:text-[var(--text)]">
            <X size={16} />
          </button>
        </div>
        <div className="p-4">{children}</div>
      </div>
    </div>,
    document.body,
  )
}

/* ===== Spinner / Empty ===== */
export function Spinner({ full }: { full?: boolean }) {
  const el = <Loader2 className="animate-spin text-brand-500" size={24} />
  if (full) return <div className="flex h-40 items-center justify-center">{el}</div>
  return el
}

export function EmptyState({ text }: { text: string }) {
  return <div className="flex h-32 items-center justify-center text-sm text-[var(--muted)]">{text}</div>
}

/* ===== MultiSelect popover ===== */
export function MultiSelect({
  options,
  values,
  onToggle,
  placeholder,
  renderTag,
}: {
  options: { id: string; label: string }[]
  values: string[]
  onToggle: (id: string) => void
  placeholder: string
  renderTag?: (id: string) => ReactNode
}) {
  const [open, setOpen] = useState(false)
  const [q, setQ] = useState('')
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const h = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', h)
    return () => document.removeEventListener('mousedown', h)
  }, [])
  const filtered = options.filter((o) => o.label.includes(q))
  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="flex w-full min-h-[34px] flex-wrap items-center gap-1 rounded-lg border border-[var(--border)] bg-[var(--panel)] px-2 py-1 text-sm text-start"
      >
        {values.length === 0 && <span className="text-[var(--muted)]">{placeholder}</span>}
        {values.map((id) =>
          renderTag ? (
            <span key={id}>{renderTag(id)}</span>
          ) : (
            <span key={id} className="rounded bg-brand-500/10 px-1.5 py-0.5 text-xs text-brand-600 dark:text-brand-300">
              {options.find((o) => o.id === id)?.label ?? '—'}
            </span>
          ),
        )}
        <ChevronDown size={14} className="ms-auto text-[var(--muted)]" />
      </button>
      {open && (
        <div className="absolute z-30 mt-1 w-full rounded-lg border border-[var(--border)] bg-[var(--panel)] shadow-lg">
          <div className="p-1.5">
            <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="חיפוש..." autoFocus />
          </div>
          <div className="max-h-52 overflow-y-auto p-1">
            {filtered.length === 0 && <div className="px-2 py-1.5 text-xs text-[var(--muted)]">אין תוצאות</div>}
            {filtered.map((o) => {
              const active = values.includes(o.id)
              return (
                <button
                  key={o.id}
                  type="button"
                  onClick={() => onToggle(o.id)}
                  className={cx(
                    'flex w-full items-center justify-between rounded-md px-2 py-1.5 text-sm text-start hover:bg-[var(--bg)]',
                    active && 'text-brand-600 dark:text-brand-300',
                  )}
                >
                  {o.label}
                  {active && <Check size={14} />}
                </button>
              )
            })}
          </div>
        </div>
      )}
    </div>
  )
}

/* ===== Toasts ===== */
interface Toast {
  id: number
  kind: 'success' | 'error'
  text: string
}
const ToastCtx = createContext<{ push: (kind: Toast['kind'], text: string) => void }>({ push: () => {} })
let toastSeq = 1

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([])
  const push = useCallback((kind: Toast['kind'], text: string) => {
    const id = toastSeq++
    setToasts((t) => [...t, { id, kind, text }])
    setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 4500)
  }, [])
  return (
    <ToastCtx.Provider value={{ push }}>
      {children}
      {createPortal(
        <div className="fixed bottom-4 start-4 z-[60] flex flex-col gap-2">
          {toasts.map((t) => (
            <div
              key={t.id}
              className={cx(
                'min-w-56 max-w-sm rounded-lg px-4 py-2.5 text-sm text-white shadow-lg',
                t.kind === 'success' ? 'bg-emerald-600' : 'bg-red-600',
              )}
            >
              {t.text}
            </div>
          ))}
        </div>,
        document.body,
      )}
    </ToastCtx.Provider>
  )
}

export function useToast() {
  const { push } = useContext(ToastCtx)
  return {
    success: (text: string) => push('success', text),
    error: (text: string) => push('error', text),
  }
}

/* ===== Confirm ===== */
export function useConfirm() {
  const [state, setState] = useState<{ text: string; resolve: (v: boolean) => void } | null>(null)
  const confirm = useCallback((text: string) => new Promise<boolean>((resolve) => setState({ text, resolve })), [])
  const dialog = state
    ? createPortal(
        <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/40 p-4">
          <div className="surface w-full max-w-sm p-4 shadow-xl">
            <p className="text-sm">{state.text}</p>
            <div className="mt-4 flex justify-end gap-2">
              <Button onClick={() => { state.resolve(false); setState(null) }}>ביטול</Button>
              <Button variant="danger" onClick={() => { state.resolve(true); setState(null) }}>אישור</Button>
            </div>
          </div>
        </div>,
        document.body,
      )
    : null
  return { confirm, dialog }
}
