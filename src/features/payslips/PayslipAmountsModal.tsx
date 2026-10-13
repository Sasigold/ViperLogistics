import { useState } from 'react'
import { AlertTriangle, ICON, Info, STROKE } from '../../components/ui/icons'
import { Badge, Button, Field, Input, Modal, cx, fmtMoney, useToast } from '../../components/ui'
import { errorMessage } from '../../lib/errors'
import type { PayslipAmountKey, PayslipBoardRow } from '../../types/domain'
import { AMOUNT_GROUPS, AMOUNT_KEYS, costFlags, parseAmountInput, periodLabel } from './payslips'
import { useSavePayslipAmounts } from './payslipQueries'

const asInput = (v: number | null | undefined) => (v === null || v === undefined ? '' : String(v))

/**
 * הסכומים של תלוש ועלות המעביד (0218 §4) — רק עם `payslips.employer_cost`.
 * העלות עצמה מחושבת בשרת; המסך מציג אותה כפי שחזרה, ומתעדכן אחרי שמירה.
 */
export function PayslipAmountsModal({ slip, onClose }: { slip: PayslipBoardRow; onClose: () => void }) {
  const toast = useToast()
  const save = useSavePayslipAmounts()
  const a = slip.amounts
  const [values, setValues] = useState<Record<PayslipAmountKey, string>>(
    () => Object.fromEntries(AMOUNT_KEYS.map((k) => [k, asInput(a?.[k])])) as Record<PayslipAmountKey, string>,
  )
  const invalid = AMOUNT_KEYS.filter((k) => values[k].trim() !== '' && parseAmountInput(values[k]) === null)
  const dirty = AMOUNT_KEYS.some((k) => values[k] !== asInput(a?.[k]))

  const submit = () => {
    save.mutate(
      { id: slip.id, amounts: Object.fromEntries(AMOUNT_KEYS.map((k) => [k, parseAmountInput(values[k])])) },
      {
        onSuccess: () => {
          toast.success('הסכומים נשמרו')
          onClose()
        },
        onError: (e) => toast.error(errorMessage(e)),
      },
    )
  }

  const flags = costFlags(a)

  return (
    <Modal
      open
      onClose={onClose}
      size="lg"
      title={`עלות מעביד — ${slip.full_name ?? slip.detected_name ?? 'תלוש'}`}
      description={`${periodLabel(slip.period)}${a ? ` · ${a.source === 'reading' ? 'נקרא מהתלוש' : 'הוקלד ביד'}` : ''}`}
      footer={
        <>
          <Button onClick={onClose}>סגירה</Button>
          <Button variant="primary" loading={save.isPending} disabled={!dirty || invalid.length > 0} onClick={submit}>
            שמירה
          </Button>
        </>
      }
    >
      <div className="space-y-5">
        <div className="grid gap-3 sm:grid-cols-3">
          {[
            { label: 'ברוטו', value: a?.gross_pay },
            { label: 'תשלומי המעסיק', value: a?.employer_contributions },
            { label: 'עלות מעביד', value: a?.employer_cost, strong: true },
          ].map((s) => (
            <div
              key={s.label}
              className={cx(
                'rounded-xl border px-3 py-2.5',
                s.strong ? 'border-primary-border bg-primary-subtle' : 'border-line-subtle bg-subtle',
              )}
            >
              <p className="type-caption text-ink-tertiary">{s.label}</p>
              <p dir="ltr" className={cx('text-end tabular-nums', s.strong ? 'text-xl font-bold' : 'type-title')}>
                {s.value === null || s.value === undefined ? '—' : fmtMoney(s.value)}
              </p>
            </div>
          ))}
        </div>

        <p className="flex items-start gap-2 type-caption text-ink-secondary">
          <Info size={ICON.sm} strokeWidth={STROKE} className="mt-0.5 shrink-0" />
          עלות מעביד = ברוטו + תשלומי המעסיק: פיצויים, קופ״ג מעסיק, ביטוח לאומי מעסיק (מחושב מ״חייב מ.ה.״ לפי
          המדרגות בהגדרות ← תלושי שכר) ושאר ההפרשות. ניכויי העובד כבר בתוך הברוטו, ולכן אינם נוספים לעלות.
        </p>

        {flags.length > 0 && (
          <div className="flex flex-wrap gap-1.5">
            {flags.map((f) => (
              <Badge key={f.text} tone={f.tone}>
                {f.tone === 'warning' && <AlertTriangle size={ICON.xs} strokeWidth={STROKE} />}
                {f.text}
              </Badge>
            ))}
          </div>
        )}

        {AMOUNT_GROUPS.map((g) => (
          <fieldset key={g.title} className="space-y-2">
            <legend className="type-title">{g.title}</legend>
            <p className="type-caption text-ink-tertiary">{g.hint}</p>
            <div className="grid gap-3 sm:grid-cols-2">
              {g.fields.map((f) => (
                <Field
                  key={f.key}
                  label={f.label}
                  hint={f.hint}
                  error={invalid.includes(f.key) ? 'מספר בלבד' : undefined}
                >
                  <Input
                    inputMode="decimal"
                    dir="ltr"
                    className="text-end tabular-nums"
                    value={values[f.key]}
                    placeholder="—"
                    onChange={(e) => setValues((v) => ({ ...v, [f.key]: e.target.value }))}
                  />
                </Field>
              ))}
              {g.fields.some((f) => f.key === 'taxable_income') && (
                <Field label="ביטוח לאומי מעסיק" hint="מחושב מ״חייב מ.ה.״ לפי המדרגות — מתעדכן אחרי שמירה">
                  <Input
                    dir="ltr"
                    className="text-end tabular-nums"
                    readOnly
                    disabled
                    value={a?.employer_national_insurance == null ? '—' : fmtMoney(a.employer_national_insurance)}
                  />
                </Field>
              )}
            </div>
          </fieldset>
        ))}
      </div>
    </Modal>
  )
}
