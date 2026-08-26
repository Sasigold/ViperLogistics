/**
 * בחירת מפרט — קובץ או קישור — בלי לדעת לאן הוא הולך.
 *
 * הרכיב הזה נולד משני מסכים שביקשו את אותו דבר: מסך המפרט מעלה גרסה לאירוע
 * קיים, וטופס יצירת האירוע אוסף מפרט לאירוע שעדיין אין לו מזהה. הוא מבוקר
 * במלואו ואינו יודע דבר על רשת — מי שמחזיק את ה-state הוא זה שמחליט מתי
 * ולאן שולחים.
 */
import type { ReactNode } from 'react'
import { useRef } from 'react'
import { ICON, Link2, STROKE, Upload } from '../../components/ui/icons'
import { Button, Field, Input, SegmentedControl } from '../../components/ui'
import { SPEC_ACCEPT, formatBytes } from './specs'
import type { SpecDraft } from './specs'

export function SpecPicker({
  value,
  onChange,
  problem,
  hint,
  disabled,
}: {
  value: SpecDraft
  onChange: (next: SpecDraft) => void
  /** ההודעה שמוצגת מתחת לשדה המקור. את *מתי* להציג אותה קובע המחזיק. */
  problem?: string | null
  /** טקסט משני לצד בורר הלשוניות — ההקשר שבו הבחירה הזאת נשמרת. */
  hint?: ReactNode
  disabled?: boolean
}) {
  const fileRef = useRef<HTMLInputElement>(null)

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <SegmentedControl<'file' | 'link'>
          value={value.source}
          onChange={(source) => onChange({ ...value, source })}
          items={[
            { key: 'file', label: 'קובץ', icon: <Upload size={ICON.sm} strokeWidth={STROKE} /> },
            { key: 'link', label: 'קישור', icon: <Link2 size={ICON.sm} strokeWidth={STROKE} /> },
          ]}
        />
        {hint && <span className="type-caption text-ink-tertiary">{hint}</span>}
      </div>

      {value.source === 'file' ? (
        <Field label="קובץ" hint="PDF או תמונה, עד 25MB" error={problem ?? undefined}>
          <div className="flex flex-wrap items-center gap-2">
            <Button disabled={disabled} onClick={() => fileRef.current?.click()}>
              <Upload size={ICON.sm} strokeWidth={STROKE} />
              בחירת קובץ
            </Button>
            <span className="min-w-0 flex-1 truncate type-caption text-ink-secondary">
              {value.file ? `${value.file.name} · ${formatBytes(value.file.size)}` : 'לא נבחר קובץ'}
            </span>
            {value.file && (
              <Button size="sm" disabled={disabled} onClick={() => onChange({ ...value, file: null })}>
                הסרה
              </Button>
            )}
            <input
              ref={fileRef}
              type="file"
              accept={SPEC_ACCEPT}
              className="hidden"
              onChange={(e) => {
                onChange({ ...value, file: e.target.files?.[0] ?? null })
                // בלי האיפוס, בחירה חוזרת של אותו קובץ אינה מפעילה change
                if (fileRef.current) fileRef.current.value = ''
              }}
            />
          </div>
        </Field>
      ) : (
        <Field label="קישור למסמך" error={problem ?? undefined}>
          <Input
            value={value.url}
            dir="ltr"
            placeholder="https://..."
            disabled={disabled}
            onChange={(e) => onChange({ ...value, url: e.target.value })}
          />
        </Field>
      )}

      <Field label="כותרת" hint="לא חובה — למשל ״אחרי הסיור באולם״">
        <Input value={value.title} disabled={disabled} onChange={(e) => onChange({ ...value, title: e.target.value })} />
      </Field>
    </div>
  )
}
