/**
 * One custom event field, drawn from its definition.
 *
 * A custom field has no column, no `field_registry` entry and no line of
 * markup of its own — everything about it is a row in `form_fields`. Drawing
 * and formatting therefore both live here, so the form, the detail page, the
 * events table and the Excel export agree on what a value looks like instead
 * of each inventing its own rendering of the same jsonb.
 */
import { Checkbox, Field, Input, Select, Textarea, linkifyParts } from '../../components/ui'
import { ExternalLink, ICON, STROKE } from '../../components/ui/icons'
import type { CustomFieldValue, FormField } from '../../types/domain'

/** The form keeps every value as a string, except a checkbox which is a bool. */
export type CustomFormValue = string | boolean

/**
 * The value as it should reach the RPC payload — the server casts by type. A
 * checkbox always sends true/false: an untouched one is genuinely "no", and
 * sending '' there would store null and let a required checkbox slip through.
 */
export const toPayloadValue = (field: FormField, v: CustomFormValue | undefined): string =>
  field.field_type === 'checkbox' ? String(v === true) : typeof v === 'boolean' ? String(v) : (v ?? '')

/**
 * The stored `custom_fields` object into the shape the form edits. Done
 * without the field definitions on purpose — the event loads into the form
 * before the catalog query has necessarily resolved.
 */
export function toFormValues(stored: Record<string, CustomFieldValue> | null | undefined) {
  const out: Record<string, CustomFormValue> = {}
  for (const [k, v] of Object.entries(stored ?? {})) {
    out[k] = typeof v === 'boolean' ? v : v == null ? '' : String(v)
  }
  return out
}

/** Empty for the purpose of a "required" check. A checkbox must be ticked. */
export const isBlank = (v: CustomFormValue | undefined): boolean =>
  typeof v === 'boolean' ? !v : !String(v ?? '').trim()

/** A stored value as a person reads it — '—' is left to the caller. */
export function formatCustomValue(field: FormField, v: CustomFieldValue | undefined): string {
  if (v == null || v === '') return ''
  if (field.field_type === 'checkbox') return v ? 'כן' : 'לא'
  if (field.field_type === 'date') {
    const [y, m, d] = String(v).split('-')
    return y && m && d ? `${d}/${m}/${y}` : String(v)
  }
  return String(v)
}

export function CustomFieldInput({
  field,
  value,
  onChange,
  required,
  readOnly,
  error,
}: {
  field: FormField
  value: CustomFormValue | undefined
  onChange: (v: CustomFormValue) => void
  required?: boolean
  readOnly?: boolean
  error?: string
}) {
  /* A checkbox carries its own label, so wrapping it in a Field would print
     the name twice — the same choice the addons block already makes. */
  if (field.field_type === 'checkbox') {
    return (
      <Field error={error}>
        <Checkbox
          label={field.label_he}
          checked={value === true}
          disabled={readOnly}
          onChange={(v) => onChange(v)}
        />
      </Field>
    )
  }

  const text = typeof value === 'boolean' ? '' : (value ?? '')

  /**
   * שדה טקסט שכל ערכו כתובת — "קישור ל-Eruit" הוא בדיוק זה — מקבל דלת
   * לצידו. בתוך `<input>` אי אפשר ללחוץ על קישור, ומי שפתח את הטופס כדי
   * לעבוד על האירוע לא אמור לסמן, להעתיק ולהדביק כדי להגיע ליעד.
   *
   * רק ערך שכולו כתובת אחת: מלל שיש בתוכו כתובת אינו "קישור", והכפתור
   * שלידו היה מבטיח יעד שאינו בהכרח מה שהמשתמש מתכוון אליו.
   */
  const parts = linkifyParts(text)
  const linkHref = parts.length === 1 && parts[0].href ? parts[0].href : null

  return (
    <Field label={field.label_he} required={required} error={error}>
      {field.field_type === 'textarea' ? (
        <Textarea
          value={text}
          readOnly={readOnly}
          autoGrow
          onChange={(e) => onChange(e.target.value)}
        />
      ) : field.field_type === 'select' ? (
        <Select value={text} disabled={readOnly} onChange={(e) => onChange(e.target.value)}>
          <option value="">— בחירה —</option>
          {field.options.map((o) => (
            <option key={o} value={o}>
              {o}
            </option>
          ))}
        </Select>
      ) : (
        <Input
          type={
            field.field_type === 'number' ? 'number' : field.field_type === 'date' ? 'date' : field.field_type === 'time' ? 'time' : 'text'
          }
          value={text}
          readOnly={readOnly}
          onChange={(e) => onChange(e.target.value)}
        />
      )}
      {linkHref && (
        <a
          href={linkHref}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1 type-caption text-primary-text hover:underline"
        >
          <ExternalLink size={ICON.xs} strokeWidth={STROKE} />
          פתיחת הקישור
        </a>
      )}
    </Field>
  )
}
