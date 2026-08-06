import { useEffect, useRef, useState } from 'react'
import { MapPin } from 'lucide-react'
import { Input } from '../../components/ui'
import { addressProvider } from '../../lib/address'
import type { AddressSuggestion } from '../../types/domain'

export function AddressAutocomplete({
  value,
  onChange,
  onPick,
  disabled,
}: {
  value: string
  onChange: (text: string) => void
  onPick: (s: AddressSuggestion) => void
  disabled?: boolean
}) {
  const [suggestions, setSuggestions] = useState<AddressSuggestion[]>([])
  const [open, setOpen] = useState(false)
  const timer = useRef<ReturnType<typeof setTimeout>>(null)
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const h = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', h)
    return () => document.removeEventListener('mousedown', h)
  }, [])

  const handleChange = (text: string) => {
    onChange(text)
    if (timer.current) clearTimeout(timer.current)
    timer.current = setTimeout(async () => {
      const res = await addressProvider.search(text)
      setSuggestions(res)
      setOpen(res.length > 0)
    }, 400)
  }

  return (
    <div ref={ref} className="relative">
      <Input value={value} onChange={(e) => handleChange(e.target.value)} placeholder="חיפוש כתובת..." disabled={disabled} />
      {open && (
        <div className="absolute z-30 mt-1 w-full rounded-lg border border-[var(--border)] bg-[var(--panel)] shadow-lg">
          {suggestions.map((s) => (
            <button
              key={s.place_id}
              type="button"
              onClick={() => {
                onPick(s)
                setOpen(false)
              }}
              className="flex w-full items-start gap-2 px-3 py-2 text-start text-sm hover:bg-[var(--bg)]"
            >
              <MapPin size={14} className="mt-0.5 shrink-0 text-[var(--muted)]" />
              <span className="line-clamp-2">{s.label}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
