import { useEffect, useState } from "react";
import {
  Button,
  Card,
  CardBody,
  CardHeader,
  Field,
  IconButton,
  Input,
  Skeleton,
  useToast,
} from "../../components/ui";
import {
  ICON,
  Info,
  Plus,
  Receipt,
  STROKE,
  Trash2,
} from "../../components/ui/icons";
import { errorMessage } from "../../lib/errors";
import type { PayslipNiBracket } from "../../types/domain";
import { type BracketDraft, bracketLabel, parseBrackets } from "./payslips";
import { useNiBrackets, useSaveNiBrackets } from "./payslipQueries";

const toDraft = (b: PayslipNiBracket): BracketDraft => ({
  up_to: b.up_to === null ? "" : String(b.up_to),
  rate: String(b.rate),
});

/**
 * מדרגות ביטוח לאומי מעסיק (0219) — לשונית "תלושי שכר" בהגדרות. ביטוח
 * לאומי מעסיק בכל תלוש מחושב בשרת מ"חייב מ.ה." לפי המדרגות האלה; שמירה
 * מחשבת מחדש את כל התלושים.
 */
export function NiBracketsTab() {
  const toast = useToast();
  const { data, isLoading } = useNiBrackets();
  const save = useSaveNiBrackets();
  const [rows, setRows] = useState<BracketDraft[]>([]);
  useEffect(() => setRows((data ?? []).map(toDraft)), [data]);

  const parsed = parseBrackets(rows);
  const error = "error" in parsed ? parsed.error : null;
  const saved = JSON.stringify((data ?? []).map(toDraft));
  const dirty = JSON.stringify(rows) !== saved;

  const set = (i: number, patch: Partial<BracketDraft>) =>
    setRows((r) => r.map((x, j) => (j === i ? { ...x, ...patch } : x)));

  const submit = () => {
    if (!("brackets" in parsed)) return;
    save.mutate(parsed.brackets, {
      onSuccess: (n) =>
        toast.success(`המדרגות נשמרו${n ? ` · ${n} תלושים חושבו מחדש` : ""}`),
      onError: (e) => toast.error(errorMessage(e)),
    });
  };

  return (
    <div className="max-w-2xl space-y-5">
      <Card>
        <CardHeader
          title="מדרגות ביטוח לאומי מעסיק"
          subtitle="מחושב מ״חייב מ.ה.״ שבתלוש, ונכנס לעלות המעביד"
          icon={<Receipt size={ICON.md} strokeWidth={STROKE} />}
        />
        <CardBody className="space-y-4">
          <p className="flex items-start gap-2 type-caption text-ink-secondary">
            <Info
              size={ICON.sm}
              strokeWidth={STROKE}
              className="mt-0.5 shrink-0"
            />
            כל מדרגה חלה רק על החלק של הסכום שבתוכה. למשל עד 7,000 — 1% ומ-7,000
            עד 15,000 — 5%: על 10,000 ₪ חייב מ.ה. יחושבו 70 + 150 = 220 ₪. מעל
            המדרגה האחרונה אין חיוב, אלא אם התקרה שלה ריקה. שינוי המדרגות מחשב
            מחדש את כל התלושים, גם של חודשים קודמים.
          </p>

          {isLoading ? (
            <Skeleton className="h-24 w-full" />
          ) : (
            <form
              className="space-y-3"
              onSubmit={(e) => {
                e.preventDefault();
                submit();
              }}
            >
              {rows.length === 0 && (
                <p className="type-body text-ink-tertiary">
                  עוד לא הוגדרו מדרגות — עד שיוגדרו, עלות המעביד אינה כוללת
                  ביטוח לאומי.
                </p>
              )}
              {rows.map((r, i) => (
                <div key={i} className="flex flex-wrap items-end gap-2">
                  <Field
                    label={i === 0 ? "עד סכום (₪)" : `מדרגה ${i + 1} — עד (₪)`}
                    hint={i === rows.length - 1 ? "ריק — בלי תקרה" : undefined}
                  >
                    <Input
                      inputSize="sm"
                      inputMode="decimal"
                      dir="ltr"
                      className="w-32 text-end tabular-nums"
                      value={r.up_to}
                      placeholder="—"
                      onChange={(e) => set(i, { up_to: e.target.value })}
                    />
                  </Field>
                  <Field label="אחוז">
                    <Input
                      inputSize="sm"
                      inputMode="decimal"
                      dir="ltr"
                      className="w-20 text-end tabular-nums"
                      value={r.rate}
                      onChange={(e) => set(i, { rate: e.target.value })}
                    />
                  </Field>
                  <IconButton
                    label="הסרת המדרגה"
                    onClick={() => setRows((x) => x.filter((_, j) => j !== i))}
                  >
                    <Trash2 size={ICON.md} strokeWidth={STROKE} />
                  </IconButton>
                </div>
              ))}

              {"brackets" in parsed && parsed.brackets.length > 0 && (
                <ul className="list-inside list-disc type-caption text-ink-secondary">
                  {parsed.brackets.map((_, i) => (
                    <li key={i}>{bracketLabel(parsed.brackets, i)}</li>
                  ))}
                </ul>
              )}
              {error && <p className="type-caption text-error-text">{error}</p>}

              <div className="flex flex-wrap gap-2">
                <Button
                  size="sm"
                  disabled={rows.length >= 12}
                  onClick={() =>
                    setRows((x) => [...x, { up_to: "", rate: "" }])
                  }
                >
                  <Plus size={ICON.sm} strokeWidth={STROKE} />
                  מדרגה
                </Button>
                <Button
                  type="submit"
                  size="sm"
                  variant="primary"
                  loading={save.isPending}
                  disabled={!!error || !dirty}
                >
                  שמירה
                </Button>
              </div>
            </form>
          )}
        </CardBody>
      </Card>
    </div>
  );
}
