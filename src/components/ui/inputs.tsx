import { createContext, useContext, useEffect, useId, useMemo, useRef, useState } from 'react'
import type {
  InputHTMLAttributes,
  ReactNode,
  SelectHTMLAttributes,
  TextareaHTMLAttributes,
  KeyboardEvent as ReactKeyboardEvent,
} from 'react'
import { Check, ChevronDown, Search, X, Loader2 } from 'lucide-react'
import { cx } from './primitives'

/* ===== shared control surface ============================================= */

export type ControlSize = 'sm' | 'md' | 'lg'

const SIZES: Record<ControlSize, string> = {
  sm: 'h-8 px-2.5 text-[0.8125rem]',
  md: 'h-9 px-3 text-sm',
  lg: 'h-10 px-3.5 text-[0.9375rem]',
}

const CONTROL =
  /* min-w-0: a control is almost always a flex or grid child, and `min-width:
     auto` lets one with an intrinsic width — a date field, above all — push
     past its container instead of shrinking into it */
  'w-full min-w-0 rounded-md border bg-surface text-ink outline-none ' +
  'transition-[border-color,box-shadow,background-color] duration-150 ease-[cubic-bezier(.4,0,.2,1)] ' +
  'placeholder:text-ink-tertiary ' +
  'hover:border-line-strong ' +
  'focus:border-primary focus:ring-2 focus:ring-[var(--vl-focus-ring)] ' +
  'disabled:cursor-not-allowed disabled:border-line-subtle disabled:bg-[var(--vl-disabled-bg)] disabled:text-[var(--vl-disabled-fg)]'

const valid = 'border-line'
const invalidCls = 'border-error-border focus:border-error focus:ring-[color-mix(in_srgb,var(--vl-error),transparent_65%)]'

const hasWidth = (className?: string) => !!className && className.split(' ').some((c) => /^w-|^flex-1$/.test(c))

/* ===== Field ==============================================================
   Owns the control's id and description ids, and hands them to whichever
   control renders inside it — so every label is really bound to its input
   without touching a single call site.                                     */

interface FieldCtx {
  id: string
  describedBy?: string
  invalid?: boolean
  required?: boolean
}
const FieldContext = createContext<FieldCtx | null>(null)

/** Controls call this to inherit id / aria wiring from an enclosing Field. */
export function useFieldProps(own: { id?: string; 'aria-describedby'?: string; required?: boolean }) {
  const ctx = useContext(FieldContext)
  if (!ctx) return { id: own.id, 'aria-describedby': own['aria-describedby'], invalid: false }
  return {
    id: own.id ?? ctx.id,
    'aria-describedby': [own['aria-describedby'], ctx.describedBy].filter(Boolean).join(' ') || undefined,
    invalid: ctx.invalid,
  }
}

export function Field({
  label,
  required,
  children,
  hint,
  error,
  htmlFor,
  className,
  action,
}: {
  label?: ReactNode
  required?: boolean
  children: ReactNode
  hint?: ReactNode
  /** message shown in place of the hint; also flags the control as invalid */
  error?: ReactNode
  htmlFor?: string
  className?: string
  /** small control rendered at the end of the label row */
  action?: ReactNode
}) {
  const auto = useId()
  const id = htmlFor ?? auto
  const hintId = hint ? `${id}-hint` : undefined
  const errId = error ? `${id}-err` : undefined
  const describedBy = [errId, hintId].filter(Boolean).join(' ') || undefined

  const ctx = useMemo<FieldCtx>(
    () => ({ id, describedBy, invalid: !!error, required }),
    [id, describedBy, error, required],
  )

  return (
    /* min-w-0: as a grid or flex item this wrapper's automatic minimum size is
       its content's — and a native date control reports a very wide one, in
       Hebrew above all ("7 באוג׳ 2026"). Without this the wrapper, not the
       input, is what grows past the card's padding and out of the frame. */
    <div className={cx('min-w-0 space-y-1.5', className)}>
      {label && (
        <div className="flex items-center gap-2">
          <label htmlFor={id} className="block type-caption font-medium text-ink-secondary">
            {label}
            {required && (
              <span className="ms-0.5 text-error" aria-hidden>
                *
              </span>
            )}
          </label>
          {action && <span className="ms-auto">{action}</span>}
        </div>
      )}
      <FieldContext.Provider value={ctx}>{children}</FieldContext.Provider>
      {error ? (
        <p id={errId} className="type-caption text-error-text" role="alert">
          {error}
        </p>
      ) : (
        hint && (
          <p id={hintId} className="type-caption text-ink-tertiary">
            {hint}
          </p>
        )
      )}
    </div>
  )
}

/* ===== Input ============================================================== */

export interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  inputSize?: ControlSize
  invalid?: boolean
  leading?: ReactNode
  trailing?: ReactNode
}

export function Input({ className, inputSize = 'md', invalid, leading, trailing, ...rest }: InputProps) {
  const f = useFieldProps(rest)
  const bad = invalid ?? f.invalid
  const control = (
    <input
      {...rest}
      id={f.id}
      aria-describedby={f['aria-describedby']}
      aria-invalid={bad || undefined}
      className={cx(
        CONTROL,
        SIZES[inputSize],
        bad ? invalidCls : valid,
        !!leading && 'ps-9',
        !!trailing && 'pe-9',
        !leading && !trailing && !hasWidth(className) && 'w-full',
        leading || trailing ? 'w-full' : undefined,
        !leading && !trailing ? className : undefined,
      )}
    />
  )
  if (!leading && !trailing) return control
  return (
    <div className={cx('relative', !hasWidth(className) && 'w-full', className)}>
      {leading && (
        <span className="pointer-events-none absolute inset-y-0 start-0 flex w-9 items-center justify-center text-ink-tertiary">
          {leading}
        </span>
      )}
      {control}
      {trailing && <span className="absolute inset-y-0 end-0 flex w-9 items-center justify-center text-ink-tertiary">{trailing}</span>}
    </div>
  )
}

export function SearchInput({
  onClear,
  value,
  ...rest
}: InputProps & { onClear?: () => void }) {
  return (
    <Input
      {...rest}
      value={value}
      type="search"
      leading={<Search size={15} aria-hidden />}
      trailing={
        onClear && String(value ?? '').length > 0 ? (
          <button
            type="button"
            onClick={onClear}
            aria-label="ניקוי חיפוש"
            className="pointer-events-auto rounded p-0.5 text-ink-tertiary transition-colors hover:text-ink"
          >
            <X size={14} />
          </button>
        ) : undefined
      }
    />
  )
}

/* ===== Textarea =========================================================== */

export interface TextareaProps extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  invalid?: boolean
  /** grow with content instead of scrolling */
  autoGrow?: boolean
}

export function Textarea({ className, invalid, autoGrow, rows = 3, onChange, ...rest }: TextareaProps) {
  const f = useFieldProps(rest)
  const bad = invalid ?? f.invalid
  const ref = useRef<HTMLTextAreaElement>(null)

  const resize = () => {
    const el = ref.current
    if (!el || !autoGrow) return
    el.style.height = 'auto'
    el.style.height = `${el.scrollHeight}px`
  }
  useEffect(resize, [rest.value, autoGrow])

  return (
    <textarea
      {...rest}
      ref={ref}
      rows={rows}
      id={f.id}
      aria-describedby={f['aria-describedby']}
      aria-invalid={bad || undefined}
      onChange={(e) => {
        onChange?.(e)
        resize()
      }}
      className={cx(
        CONTROL,
        'resize-y px-3 py-2 text-sm leading-relaxed',
        autoGrow && 'resize-none overflow-hidden',
        bad ? invalidCls : valid,
        className,
      )}
    />
  )
}

/* ===== Select =============================================================
   Native <select> for reliability and mobile ergonomics, restyled with our
   own chevron so it doesn't look like an OS control.                       */

export interface SelectProps extends SelectHTMLAttributes<HTMLSelectElement> {
  selectSize?: ControlSize
  invalid?: boolean
}

export function Select({ className, children, selectSize = 'md', invalid, ...rest }: SelectProps) {
  const f = useFieldProps(rest)
  const bad = invalid ?? f.invalid
  return (
    <div className={cx('relative', !hasWidth(className) && 'w-full', className)}>
      <select
        {...rest}
        id={f.id}
        aria-describedby={f['aria-describedby']}
        aria-invalid={bad || undefined}
        className={cx(
          CONTROL,
          SIZES[selectSize],
          bad ? invalidCls : valid,
          'cursor-pointer appearance-none truncate pe-8',
        )}
      >
        {children}
      </select>
      <ChevronDown
        size={15}
        aria-hidden
        className="pointer-events-none absolute inset-y-0 end-2.5 my-auto text-ink-tertiary"
      />
    </div>
  )
}

/* ===== Checkbox / Radio / Switch ==========================================
   Drawn rather than native so the dark palette and focus ring are ours.    */

export function Checkbox({
  label,
  checked,
  onChange,
  disabled,
  description,
  indeterminate,
  className,
}: {
  label?: ReactNode
  checked: boolean
  onChange: (v: boolean) => void
  disabled?: boolean
  description?: ReactNode
  indeterminate?: boolean
  className?: string
}) {
  const ref = useRef<HTMLInputElement>(null)
  useEffect(() => {
    if (ref.current) ref.current.indeterminate = !!indeterminate && !checked
  }, [indeterminate, checked])

  return (
    <label
      className={cx(
        'group inline-flex cursor-pointer select-none items-start gap-2 text-sm',
        disabled && 'pointer-events-none opacity-55',
        className,
      )}
    >
      <span className="relative flex size-4 shrink-0 items-center justify-center" style={{ marginTop: '1px' }}>
        <input
          ref={ref}
          type="checkbox"
          className="peer absolute inset-0 cursor-pointer opacity-0"
          checked={checked}
          onChange={(e) => onChange(e.target.checked)}
          disabled={disabled}
        />
        <span
          aria-hidden
          className={cx(
            'flex size-4 items-center justify-center rounded-[5px] border transition-all duration-150',
            'peer-focus-visible:focus-ring',
            checked || indeterminate
              ? 'border-primary bg-primary text-on-primary'
              : 'border-line-strong bg-surface group-hover:border-primary',
          )}
        >
          {checked ? (
            <Check size={11} strokeWidth={3.5} />
          ) : indeterminate ? (
            <span className="h-0.5 w-2 rounded-full bg-current" />
          ) : null}
        </span>
      </span>
      {(label || description) && (
        <span className="min-w-0">
          {label && <span className="block leading-tight">{label}</span>}
          {description && <span className="mt-0.5 block type-caption text-ink-tertiary">{description}</span>}
        </span>
      )}
    </label>
  )
}

export function Radio({
  label,
  checked,
  onChange,
  disabled,
  name,
  description,
}: {
  label: ReactNode
  checked: boolean
  onChange: () => void
  disabled?: boolean
  name?: string
  description?: ReactNode
}) {
  return (
    <label
      className={cx(
        'group inline-flex cursor-pointer select-none items-start gap-2 text-sm',
        disabled && 'pointer-events-none opacity-55',
      )}
    >
      <span className="relative flex size-4 shrink-0 items-center justify-center" style={{ marginTop: '1px' }}>
        <input
          type="radio"
          name={name}
          className="peer absolute inset-0 cursor-pointer opacity-0"
          checked={checked}
          onChange={onChange}
          disabled={disabled}
        />
        <span
          aria-hidden
          className={cx(
            'flex size-4 items-center justify-center rounded-full border transition-all duration-150 peer-focus-visible:focus-ring',
            checked ? 'border-primary bg-primary' : 'border-line-strong bg-surface group-hover:border-primary',
          )}
        >
          {checked && <span className="size-1.5 rounded-full bg-on-primary" />}
        </span>
      </span>
      <span className="min-w-0">
        <span className="block leading-tight">{label}</span>
        {description && <span className="mt-0.5 block type-caption text-ink-tertiary">{description}</span>}
      </span>
    </label>
  )
}

export function Switch({
  checked,
  onChange,
  label,
  disabled,
  description,
  'aria-label': ariaLabel,
}: {
  checked: boolean
  onChange: (v: boolean) => void
  label?: ReactNode
  disabled?: boolean
  description?: ReactNode
  /**
   * לשימוש כשהטקסט מצויר מחוץ לרכיב ו-`label` היה מכפיל אותו.
   *
   * מוצהר במפורש ולא נשען על עודף props: TypeScript פוטר תכונות JSX מקופפות
   * מבדיקת עודף, ולכן `aria-label` על רכיב שאינו מכריז עליו עובר קומפילציה
   * ונזרק בשקט — כפתור בלי שם נגיש, בלי שדבר יתלונן.
   */
  'aria-label'?: string
}) {
  return (
    <label
      className={cx(
        'inline-flex cursor-pointer select-none items-center gap-2.5 text-sm',
        disabled && 'pointer-events-none opacity-55',
      )}
    >
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={ariaLabel ?? (typeof label === 'string' ? label : undefined)}
        disabled={disabled}
        onClick={() => onChange(!checked)}
        className={cx(
          'relative h-5 w-9 shrink-0 rounded-full transition-colors duration-200 focus-visible:outline-none focus-visible:focus-ring',
          checked ? 'bg-primary' : 'bg-line-strong',
        )}
      >
        <span
          aria-hidden
          className={cx(
            'absolute top-0.5 size-4 rounded-full bg-white shadow-sm transition-[inset-inline-start] duration-200 ease-[cubic-bezier(.4,0,.2,1)]',
            checked ? 'start-[1.125rem]' : 'start-0.5',
          )}
        />
      </button>
      {(label || description) && (
        <span className="min-w-0">
          {label && <span className="block leading-tight">{label}</span>}
          {description && <span className="mt-0.5 block type-caption text-ink-tertiary">{description}</span>}
        </span>
      )}
    </label>
  )
}

/* ===== popover plumbing shared by MultiSelect / Autocomplete ============== */

function useDismiss(open: boolean, close: () => void) {
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (!open) return
    const onDown = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) close()
    }
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') close()
    }
    document.addEventListener('mousedown', onDown)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('mousedown', onDown)
      document.removeEventListener('keydown', onKey)
    }
  }, [open, close])
  return ref
}

const POPOVER =
  'absolute z-40 mt-1 w-full origin-top animate-scale-in overflow-hidden rounded-lg border border-line bg-raised shadow-lg'

/* ===== MultiSelect ======================================================== */

export function MultiSelect({
  options,
  values,
  onToggle,
  placeholder,
  renderTag,
  disabled,
  className,
}: {
  options: { id: string; label: string }[]
  values: string[]
  onToggle: (id: string) => void
  placeholder: string
  renderTag?: (id: string) => ReactNode
  disabled?: boolean
  className?: string
}) {
  const [open, setOpen] = useState(false)
  const [q, setQ] = useState('')
  const [active, setActive] = useState(0)
  const listId = useId()
  const f = useFieldProps({})
  const ref = useDismiss(open, () => setOpen(false))

  const filtered = useMemo(
    () => options.filter((o) => o.label.toLowerCase().includes(q.trim().toLowerCase())),
    [options, q],
  )
  useEffect(() => setActive(0), [q, open])

  const onKeyDown = (e: ReactKeyboardEvent) => {
    if (!open && (e.key === 'ArrowDown' || e.key === 'Enter' || e.key === ' ')) {
      e.preventDefault()
      setOpen(true)
      return
    }
    if (!open) return
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setActive((i) => Math.min(i + 1, filtered.length - 1))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setActive((i) => Math.max(i - 1, 0))
    } else if (e.key === 'Home') {
      e.preventDefault()
      setActive(0)
    } else if (e.key === 'End') {
      e.preventDefault()
      setActive(filtered.length - 1)
    } else if (e.key === 'Enter' && filtered[active]) {
      e.preventDefault()
      onToggle(filtered[active].id)
    }
  }

  return (
    <div ref={ref} className={cx('relative', className)}>
      <button
        type="button"
        id={f.id}
        disabled={disabled}
        onClick={() => setOpen((v) => !v)}
        onKeyDown={onKeyDown}
        role="combobox"
        aria-expanded={open}
        aria-haspopup="listbox"
        aria-controls={open ? listId : undefined}
        aria-describedby={f['aria-describedby']}
        className={cx(
          CONTROL,
          'flex min-h-9 flex-wrap items-center gap-1 px-2 py-1 text-start text-sm',
          valid,
          open && 'border-primary ring-2 ring-[var(--vl-focus-ring)]',
        )}
      >
        {values.length === 0 && <span className="text-ink-tertiary">{placeholder}</span>}
        {values.map((id) =>
          renderTag ? (
            <span key={id}>{renderTag(id)}</span>
          ) : (
            <span
              key={id}
              className="inline-flex max-w-[12rem] items-center gap-1 rounded bg-primary-subtle px-1.5 py-0.5 type-caption font-medium text-primary-text"
            >
              <span className="truncate">{options.find((o) => o.id === id)?.label ?? '—'}</span>
              <span
                role="button"
                tabIndex={-1}
                aria-label="הסרה"
                onClick={(e) => {
                  e.stopPropagation()
                  onToggle(id)
                }}
                className="shrink-0 rounded-full p-0.5 opacity-60 transition-opacity hover:opacity-100"
              >
                <X size={10} />
              </span>
            </span>
          ),
        )}
        <ChevronDown
          size={15}
          aria-hidden
          className={cx('ms-auto shrink-0 text-ink-tertiary transition-transform duration-200', open && 'rotate-180')}
        />
      </button>

      {open && (
        <div className={POPOVER}>
          <div className="border-b border-line-subtle p-1.5">
            <Input
              inputSize="sm"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              onKeyDown={onKeyDown}
              placeholder="חיפוש..."
              leading={<Search size={13} aria-hidden />}
              autoFocus
            />
          </div>
          <ul id={listId} role="listbox" aria-multiselectable className="max-h-56 overflow-y-auto p-1">
            {filtered.length === 0 && <li className="px-2 py-3 text-center type-caption text-ink-tertiary">אין תוצאות</li>}
            {filtered.map((o, i) => {
              const on = values.includes(o.id)
              return (
                <li key={o.id} role="option" aria-selected={on}>
                  <button
                    type="button"
                    onMouseEnter={() => setActive(i)}
                    onClick={() => onToggle(o.id)}
                    className={cx(
                      'flex w-full items-center justify-between gap-2 rounded-md px-2 py-1.5 text-start text-sm transition-colors',
                      i === active && 'bg-hover',
                      on && 'font-medium text-primary-text',
                    )}
                  >
                    <span className="truncate">{o.label}</span>
                    {on && <Check size={14} className="shrink-0" aria-hidden />}
                  </button>
                </li>
              )
            })}
          </ul>
        </div>
      )}
    </div>
  )
}

/* ===== Autocomplete =======================================================
   Generic async combobox. AddressAutocomplete is one instance of it.       */

export function Autocomplete<T>({
  value,
  onChange,
  onPick,
  fetcher,
  getKey,
  renderOption,
  placeholder,
  disabled,
  minChars = 2,
  debounce = 350,
  leading,
  emptyText = 'אין תוצאות',
}: {
  value: string
  onChange: (text: string) => void
  onPick: (item: T) => void
  fetcher: (q: string) => Promise<T[]>
  getKey: (item: T) => string
  renderOption: (item: T) => ReactNode
  placeholder?: string
  disabled?: boolean
  minChars?: number
  debounce?: number
  leading?: ReactNode
  emptyText?: string
}) {
  const [items, setItems] = useState<T[]>([])
  const [open, setOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [active, setActive] = useState(0)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const seq = useRef(0)
  const listId = useId()
  const f = useFieldProps({})
  const ref = useDismiss(open, () => setOpen(false))

  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current)
    },
    [],
  )

  const run = (text: string) => {
    onChange(text)
    if (timer.current) clearTimeout(timer.current)
    if (text.trim().length < minChars) {
      setItems([])
      setOpen(false)
      return
    }
    timer.current = setTimeout(async () => {
      const mine = ++seq.current
      setBusy(true)
      try {
        const res = await fetcher(text)
        if (mine !== seq.current) return // a newer keystroke already won
        setItems(res)
        setActive(0)
        setOpen(true)
      } finally {
        if (mine === seq.current) setBusy(false)
      }
    }, debounce)
  }

  const pick = (item: T) => {
    onPick(item)
    setOpen(false)
  }

  return (
    <div ref={ref} className="relative">
      <Input
        value={value}
        disabled={disabled}
        placeholder={placeholder}
        role="combobox"
        aria-expanded={open}
        aria-controls={open ? listId : undefined}
        aria-autocomplete="list"
        onChange={(e) => run(e.target.value)}
        onFocus={() => items.length > 0 && setOpen(true)}
        onKeyDown={(e) => {
          if (!open) return
          if (e.key === 'ArrowDown') {
            e.preventDefault()
            setActive((i) => Math.min(i + 1, items.length - 1))
          } else if (e.key === 'ArrowUp') {
            e.preventDefault()
            setActive((i) => Math.max(i - 1, 0))
          } else if (e.key === 'Enter' && items[active]) {
            e.preventDefault()
            pick(items[active])
          }
        }}
        leading={leading}
        trailing={busy ? <Loader2 size={14} className="animate-spin" aria-hidden /> : undefined}
      />
      {open && (
        <ul id={listId} role="listbox" aria-labelledby={f.id} className={cx(POPOVER, 'max-h-64 overflow-y-auto p-1')}>
          {items.length === 0 && <li className="px-2 py-3 text-center type-caption text-ink-tertiary">{emptyText}</li>}
          {items.map((item, i) => (
            <li key={getKey(item)} role="option" aria-selected={i === active}>
              <button
                type="button"
                onMouseEnter={() => setActive(i)}
                onClick={() => pick(item)}
                className={cx(
                  'flex w-full items-start gap-2 rounded-md px-2 py-1.5 text-start text-sm transition-colors',
                  i === active && 'bg-hover',
                )}
              >
                {renderOption(item)}
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

/* ===== TagsInput ========================================================== */

export function TagsInput({
  values,
  onChange,
  placeholder,
  disabled,
}: {
  values: string[]
  onChange: (v: string[]) => void
  placeholder?: string
  disabled?: boolean
}) {
  const [draft, setDraft] = useState('')
  const f = useFieldProps({})

  const add = () => {
    const v = draft.trim()
    if (!v || values.includes(v)) return setDraft('')
    onChange([...values, v])
    setDraft('')
  }

  return (
    <div
      className={cx(
        CONTROL,
        valid,
        'flex min-h-9 flex-wrap items-center gap-1 px-2 py-1',
        disabled && 'pointer-events-none opacity-55',
      )}
    >
      {values.map((v) => (
        <span
          key={v}
          className="inline-flex items-center gap-1 rounded bg-primary-subtle px-1.5 py-0.5 type-caption font-medium text-primary-text"
        >
          {v}
          <button
            type="button"
            aria-label={`הסרת ${v}`}
            onClick={() => onChange(values.filter((x) => x !== v))}
            className="rounded-full opacity-60 transition-opacity hover:opacity-100"
          >
            <X size={10} />
          </button>
        </span>
      ))}
      <input
        id={f.id}
        value={draft}
        disabled={disabled}
        placeholder={values.length === 0 ? placeholder : undefined}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={add}
        onKeyDown={(e) => {
          if (e.key === 'Enter' || e.key === ',') {
            e.preventDefault()
            add()
          } else if (e.key === 'Backspace' && !draft && values.length) {
            onChange(values.slice(0, -1))
          }
        }}
        className="min-w-24 flex-1 bg-transparent text-sm outline-none placeholder:text-ink-tertiary"
      />
    </div>
  )
}
