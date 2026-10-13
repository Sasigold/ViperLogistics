import { useState } from 'react'
import {
  Button,
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  Field,
  IconButton,
  Input,
  Skeleton,
  useConfirm,
  useToast,
} from '../../components/ui'
import { ICON, Info, Pencil, Plus, Receipt, STROKE, Trash2 } from '../../components/ui/icons'
import { errorMessage } from '../../lib/errors'
import type { PayslipNiBracket, PayslipNiSet } from '../../types/domain'
import { type BracketDraft, bracketLabel, fromMonthInput, parseBrackets, termLabel, toMonthInput } from './payslips'
import { useNiSets, useRemoveNiSet, useSaveNiSet } from './payslipQueries'

const toDraft = (b: PayslipNiBracket): BracketDraft => ({
  up_to: b.up_to === null ? '' : String(b.up_to),
  rate: String(b.rate),
})

/** לשונית "תלושי שכר" בהגדרות. */
export function NiBracketsTab() {
  return (
    <div className="max-w-2xl space-y-5">
      <NiBracketsCard />
    </div>
  )
}

/**
 * מדרגות ביטוח לאומי מעסיק לפי תקופה (0223) — בלשונית "תלושי שכר" בהגדרות,
 * ובמסך התלושים למי שרואה עלות מעביד בלי גישה להגדרות. כל תלוש מחושב בשרת
 * לפי התקופה שחודש התלוש בתוכה; שינוי של תקופה אחת אינו נוגע בחודשים אחרים.
 */
export function NiBracketsCard() {
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const { data: sets = [], isLoading } = useNiSets()
  const remove = useRemoveNiSet()
  // ‏null — אין עורך פתוח; 'new' — תקופה חדשה; אחרת — התקופה שבעריכה
  const [editing, setEditing] = useState<'new' | PayslipNiSet | null>(null)

  const removeSet = async (s: PayslipNiSet) => {
    const ok = await confirm(
      `להסיר את המדרגות של ${termLabel(s.valid_from, s.valid_to)}? תלושי התקופה יישארו בלי ביטוח לאומי מעסיק.`,
      { title: 'הסרת תקופה', confirmLabel: 'הסרה' },
    )
    if (!ok) return
    remove.mutate(s.id, {
      onSuccess: () => toast.success('התקופה הוסרה'),
      onError: (e) => toast.error(errorMessage(e)),
    })
  }

  return (
    <Card>
      {dialog}
      <CardHeader
        title="מדרגות ביטוח לאומי מעסיק"
        subtitle="לפי תקופה — כל תלוש מחושב לפי המדרגות של החודש שלו"
        icon={<Receipt size={ICON.md} strokeWidth={STROKE} />}
        actions={
          editing === null && (
            <Button size="sm" onClick={() => setEditing('new')}>
              <Plus size={ICON.sm} strokeWidth={STROKE} />
              תקופה חדשה
            </Button>
          )
        }
      />
      <CardBody className="space-y-4">
        <p className="flex items-start gap-2 type-caption text-ink-secondary">
          <Info size={ICON.sm} strokeWidth={STROKE} className="mt-0.5 shrink-0" />
          כל מדרגה חלה רק על החלק של הסכום שבתוכה (חייב מ.ה.). למשל עד 7,000 — 1% ומ-7,000 עד 15,000 — 5%: על 10,000 ₪
          יחושבו 70 + 150 = 220 ₪. מעל המדרגה האחרונה אין חיוב, אלא אם התקרה שלה ריקה. תקופות אינן חופפות; חודש שאין לו
          תקופה — אין בו ביטוח לאומי מעסיק.
        </p>

        {editing !== null && (
          <SetEditor
            key={editing === 'new' ? 'new' : editing.id}
            set={editing === 'new' ? null : editing}
            onDone={() => setEditing(null)}
          />
        )}

        {isLoading && <Skeleton className="h-24 w-full" />}
        {!isLoading && sets.length === 0 && editing === null && (
          <EmptyState
            compact
            art="table"
            title="עוד לא הוגדרו מדרגות"
            description="עד שיוגדרו, עלות המעביד אינה כוללת ביטוח לאומי"
          />
        )}
        {sets.length > 0 && (
          <ul className="divide-y divide-line-subtle">
            {sets.map((s) => (
              <li key={s.id} className="flex flex-wrap items-start gap-3 py-2.5">
                <div className="min-w-48 flex-1">
                  <p className="type-body font-semibold">{termLabel(s.valid_from, s.valid_to)}</p>
                  <ul className="type-caption text-ink-secondary">
                    {s.brackets.map((_, i) => (
                      <li key={i}>{bracketLabel(s.brackets, i)}</li>
                    ))}
                  </ul>
                </div>
                <div className="flex gap-0.5">
                  <IconButton label="עריכה" disabled={editing !== null} onClick={() => setEditing(s)}>
                    <Pencil size={ICON.md} strokeWidth={STROKE} />
                  </IconButton>
                  <IconButton label="הסרת התקופה" disabled={editing !== null} onClick={() => void removeSet(s)}>
                    <Trash2 size={ICON.md} strokeWidth={STROKE} />
                  </IconButton>
                </div>
              </li>
            ))}
          </ul>
        )}
      </CardBody>
    </Card>
  )
}

/** עורך של תקופה אחת: חודש תחולה, חודש תפוגה (לא חובה) והמדרגות. */
function SetEditor({ set, onDone }: { set: PayslipNiSet | null; onDone: () => void }) {
  const toast = useToast()
  const save = useSaveNiSet()
  const [from, setFrom] = useState(toMonthInput(set?.valid_from ?? null))
  const [to, setTo] = useState(toMonthInput(set?.valid_to ?? null))
  const [rows, setRows] = useState<BracketDraft[]>(set ? set.brackets.map(toDraft) : [{ up_to: '', rate: '' }])

  const parsed = parseBrackets(rows)
  const validFrom = fromMonthInput(from)
  const validTo = fromMonthInput(to)
  const error =
    'error' in parsed
      ? parsed.error
      : !validFrom
        ? 'יש לבחור חודש תחולה'
        : validTo && validTo < validFrom
          ? 'חודש התפוגה לפני חודש התחולה'
          : parsed.brackets.length === 0
            ? 'יש להזין לפחות מדרגה אחת'
            : null

  const set_ = (i: number, patch: Partial<BracketDraft>) =>
    setRows((r) => r.map((x, j) => (j === i ? { ...x, ...patch } : x)))

  const submit = () => {
    if (error || !('brackets' in parsed) || !validFrom) return
    save.mutate(
      { id: set?.id ?? null, validFrom, validTo, brackets: parsed.brackets },
      {
        onSuccess: () => {
          toast.success('המדרגות נשמרו — תלושי התקופה חושבו מחדש')
          onDone()
        },
        onError: (e) => toast.error(errorMessage(e)),
      },
    )
  }

  return (
    <form
      className="space-y-3 rounded-xl border border-line-subtle bg-subtle/40 p-3"
      onSubmit={(e) => {
        e.preventDefault()
        submit()
      }}
    >
      <p className="type-title">{set ? 'עריכת תקופה' : 'תקופה חדשה'}</p>
      <div className="flex flex-wrap gap-2">
        <Field label="חודש תחולה">
          <Input inputSize="sm" type="month" dir="ltr" value={from} onChange={(e) => setFrom(e.target.value)} />
        </Field>
        <Field label="חודש תפוגה" hint="כולל; ריק — בלי תפוגה">
          <Input inputSize="sm" type="month" dir="ltr" value={to} onChange={(e) => setTo(e.target.value)} />
        </Field>
      </div>

      {rows.map((r, i) => (
        <div key={i} className="flex flex-wrap items-end gap-2">
          <Field
            label={i === 0 ? 'עד סכום (₪)' : `מדרגה ${i + 1} — עד (₪)`}
            hint={i === rows.length - 1 ? 'ריק — בלי תקרה' : undefined}
          >
            <Input
              inputSize="sm"
              inputMode="decimal"
              dir="ltr"
              className="w-32 text-end tabular-nums"
              value={r.up_to}
              placeholder="—"
              onChange={(e) => set_(i, { up_to: e.target.value })}
            />
          </Field>
          <Field label="אחוז">
            <Input
              inputSize="sm"
              inputMode="decimal"
              dir="ltr"
              className="w-20 text-end tabular-nums"
              value={r.rate}
              onChange={(e) => set_(i, { rate: e.target.value })}
            />
          </Field>
          {/* type="button": בתוך הטופס, כפתור בלי type שולח אותו */}
          <IconButton
            type="button"
            label="הסרת המדרגה"
            onClick={() => setRows((x) => x.filter((_, j) => j !== i))}
          >
            <Trash2 size={ICON.md} strokeWidth={STROKE} />
          </IconButton>
        </div>
      ))}

      {'brackets' in parsed && parsed.brackets.length > 0 && (
        <ul className="list-inside list-disc type-caption text-ink-secondary">
          {parsed.brackets.map((_, i) => (
            <li key={i}>{bracketLabel(parsed.brackets, i)}</li>
          ))}
        </ul>
      )}
      {error && <p className="type-caption text-error-text">{error}</p>}

      <div className="flex flex-wrap gap-2">
        <Button
          type="button"
          size="sm"
          disabled={rows.length >= 12}
          onClick={() => setRows((x) => [...x, { up_to: '', rate: '' }])}
        >
          <Plus size={ICON.sm} strokeWidth={STROKE} />
          מדרגה
        </Button>
        <Button type="submit" size="sm" variant="primary" loading={save.isPending} disabled={!!error}>
          שמירה
        </Button>
        <Button type="button" size="sm" variant="ghost" onClick={onDone}>
          ביטול
        </Button>
      </div>
    </form>
  )
}
