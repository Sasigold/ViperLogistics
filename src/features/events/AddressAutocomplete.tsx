import { ICON, MapPin, STROKE } from '../../components/ui/icons'
import { Autocomplete } from '../../components/ui'
import { addressProvider, MIN_QUERY_CHARS, shortAddress } from '../../lib/address'
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
      placeholder="חיפוש כתובת או שם מקום..."
      minChars={MIN_QUERY_CHARS}
      debounce={300}
      leading={<MapPin size={ICON.sm} strokeWidth={STROKE} />}
      fetcher={(q) => addressProvider.search(q)}
      getKey={(s) => s.place_id}
      // מיקום הוא שדה טקסט חופשי; מה שהוקלד נשמר גם בלי לבחור מהרשימה
      emptyText="לא נמצאה כתובת — אפשר להשאיר את מה שהוקלד"
      renderOption={(s) => (
        <>
          <MapPin size={ICON.sm} className="mt-0.5 shrink-0 text-ink-tertiary" strokeWidth={STROKE} aria-hidden />
          {/* מוצג מקוצר; onPick עדיין מקבל את ההצעה המלאה, וזו שנשמרת */}
          <span className="line-clamp-2">{shortAddress(s.label)}</span>
        </>
      )}
    />
  )
}
