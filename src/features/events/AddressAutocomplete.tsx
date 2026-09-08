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
  onManual,
  disabled,
}: {
  value: string
  onChange: (text: string) => void
  onPick: (s: AddressSuggestion) => void
  /** מוצא מהחיפוש: מה שהוקלד נלקח כפי שהוא, והשדה עובר להזנה ידנית. */
  onManual?: (text: string) => void
  disabled?: boolean
}) {
  return (
    <Autocomplete<AddressSuggestion>
      value={value}
      onChange={onChange}
      onPick={onPick}
      onManual={onManual}
      manualLabel={(text) => `הזנה ידנית: "${text}"`}
      disabled={disabled}
      placeholder="חיפוש כתובת או שם מקום..."
      minChars={MIN_QUERY_CHARS}
      debounce={300}
      leading={<MapPin size={ICON.sm} strokeWidth={STROKE} />}
      fetcher={(q) => addressProvider.search(q)}
      getKey={(s) => s.place_id}
      /* חיפוש שלא מצא אינו סוף הדרך: כשיש `onManual` הרשימה מציעה מתחת
         להודעה הזאת לקחת את מה שהוקלד כמות שהוא. */
      emptyText="לא נמצאה כתובת"
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
