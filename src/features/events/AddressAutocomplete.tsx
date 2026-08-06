import { ICON, MapPin, STROKE } from '../../components/ui/icons'
import { Autocomplete } from '../../components/ui'
import { addressProvider } from '../../lib/address'
import type { AddressSuggestion } from '../../types/domain'

/**
 * Thin binding of the shared Autocomplete to the address provider — the
 * debounce, race-guard, keyboard navigation and ARIA wiring all live in the
 * design system now, so the address field behaves exactly like every other
 * combobox in the product.
 */
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
  return (
    <Autocomplete<AddressSuggestion>
      value={value}
      onChange={onChange}
      onPick={onPick}
      disabled={disabled}
      placeholder="חיפוש כתובת..."
      minChars={3}
      debounce={400}
      leading={<MapPin size={ICON.sm} strokeWidth={STROKE} />}
      fetcher={(q) => addressProvider.search(q)}
      getKey={(s) => s.place_id}
      emptyText="לא נמצאה כתובת תואמת"
      renderOption={(s) => (
        <>
          <MapPin size={ICON.sm} className="mt-0.5 shrink-0 text-ink-tertiary" strokeWidth={STROKE} aria-hidden />
          <span className="line-clamp-2">{s.label}</span>
        </>
      )}
    />
  )
}
