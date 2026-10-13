import { useMemo, useState } from 'react'
import {
  AlertTriangle,
  Check,
  ChevronLeft,
  ChevronRight,
  ExternalLink,
  ICON,
  Info,
  Link2,
  STROKE,
  Trash2,
  UserCheck,
} from '../../components/ui/icons'
import {
  Badge,
  Button,
  EmptyState,
  ErrorState,
  Field,
  Modal,
  Select,
  Skeleton,
  Spinner,
  cx,
  fmtMoney,
  useConfirm,
  useToast,
} from '../../components/ui'
import { errorMessage } from '../../lib/errors'
import type { PayslipBoardRow } from '../../types/domain'
import { pageRangeLabel, periodLabel, periodOptions } from './payslips'
import {
  openSlip,
  useAssignPayslip,
  useMergePayslip,
  usePayslipAssignees,
  usePayslipsBoard,
  useRemovePayslip,
  useSetPayslipPeriod,
  useSkipPayslip,
  useSplitPayslip,
} from './payslipQueries'
import { useSlipPdfUrl } from './useSlipPdf'

/** ממתין לשיוך: לא שויך, לא סומן "ללא שיוך" (0220), ואינו "לא תלוש". */
const isPending = (r: PayslipBoardRow) => !r.profile_id && !r.skipped && r.detected_kind !== 'other'

/** הבא בתור: התלוש הממתין הראשון אחרי `from`, במעגל. */
function nextPending(rows: PayslipBoardRow[], from: number): number {
  for (let step = 1; step <= rows.length; step++) {
    const i = (from + step) % rows.length
    if (isPending(rows[i])) return i
  }
  return -1
}

/**
 * השיוך, תלוש אחרי תלוש (0218): משמאל התלוש עצמו, מימין — למי הוא שייך.
 * העובד שהתלוש מציע (לפי מספר העובד או השם, וממה שנזכר מהחודש הקודם) כבר
 * בחור, אבל השאלה נשאלת על כל תלוש: "שיוך והבא" הוא החלטה, לא ברירת מחדל.
 */
export function PayslipAssignWizard({ batchId, onClose }: { batchId: string; onClose: () => void }) {
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const { data, isLoading, error, refetch } = usePayslipsBoard({ batchId })
  // אנשי צוות ועובדי קבלנים עם משתמש (0220)
  const { data: staff = [] } = usePayslipAssignees()
  const staffOnly = staff.filter((p) => p.user_kind === 'staff')
  const contractorWorkers = staff.filter((p) => p.user_kind === 'contractor_user')
  const assign = useAssignPayslip()
  const skip = useSkipPayslip()
  const setPeriod = useSetPayslipPeriod()
  const merge = useMergePayslip()
  const split = useSplitPayslip()
  const remove = useRemovePayslip()

  const rows = useMemo(() => [...(data?.slips ?? [])].sort((a, b) => a.page_from - b.page_from), [data?.slips])
  const [currentId, setCurrentId] = useState<string | null>(null)
  // ‏null — עוד לא נבחר; מחושב מהשורות בכל רינדור עד שנבחר תלוש במפורש
  const index = useMemo(() => {
    const byId = currentId ? rows.findIndex((r) => r.id === currentId) : -1
    if (byId >= 0) return byId
    const first = rows.findIndex(isPending)
    return first >= 0 ? first : rows.length ? 0 : -1
  }, [rows, currentId])
  const slip = index >= 0 ? rows[index] : null

  // הבחירה בטופס, לפי תלוש: מה שנבחר ביד גובר על ההצעה
  const [picked, setPicked] = useState<Record<string, { profileId?: string; period?: string }>>({})
  // הצעה רק כשהעובד ברשימה (פעיל) — אחרת הבחירה הייתה ריקה לעין ומלאה בשליחה
  const suggested =
    slip?.suggested_profile_id && staff.some((p) => p.id === slip.suggested_profile_id)
      ? slip.suggested_profile_id
      : null
  const profileId = slip ? (picked[slip.id]?.profileId ?? slip.profile_id ?? suggested ?? '') : ''
  const period = slip ? (picked[slip.id]?.period ?? slip.period) : ''
  const months = useMemo(() => periodOptions(new Date()), [])

  const pdf = useSlipPdfUrl(slip)
  const busy =
    assign.isPending || setPeriod.isPending || merge.isPending || split.isPending || remove.isPending || skip.isPending
  const pending = rows.filter(isPending).length

  const goTo = (i: number) => {
    if (i >= 0 && i < rows.length) setCurrentId(rows[i].id)
  }

  const fail = (e: unknown) => toast.error(errorMessage(e))

  const assignAndNext = async () => {
    if (!slip || !profileId) return
    try {
      if (period !== slip.period) await setPeriod.mutateAsync({ id: slip.id, period })
      if (profileId !== slip.profile_id) await assign.mutateAsync({ id: slip.id, profileId })
      const name = staff.find((p) => p.id === profileId)?.full_name ?? ''
      toast.success(`התלוש שויך ל${name}`)
      const next = nextPending(rows, index)
      if (next >= 0 && rows[next].id !== slip.id) goTo(next)
    } catch (e) {
      fail(e)
    }
  }

  const unassign = () => {
    if (!slip) return
    assign.mutate({ id: slip.id, profileId: null }, { onError: fail })
  }

  // "ללא שיוך" (0220): התלוש יורד מהממתינים, ואף עובד אינו רואה אותו
  const skipAndNext = () => {
    if (!slip) return
    const next = nextPending(rows, index)
    skip.mutate(
      { id: slip.id, skip: true },
      {
        onSuccess: () => {
          toast.success('סומן ללא שיוך')
          if (next >= 0 && rows[next].id !== slip.id) goTo(next)
        },
        onError: fail,
      },
    )
  }

  const unskip = () => {
    if (!slip) return
    skip.mutate({ id: slip.id, skip: false }, { onError: fail })
  }

  const mergePrev = async () => {
    if (!slip) return
    const ok = await confirm(`לצרף את ${pageRangeLabel(slip.page_from, slip.page_to)} לתלוש שלפניו בקובץ?`, {
      title: 'המשך של התלוש הקודם',
      confirmLabel: 'צירוף',
      tone: 'primary',
    })
    if (!ok) return
    const prev = rows[index - 1]
    merge.mutate(slip.id, {
      onSuccess: () => {
        if (prev) setCurrentId(prev.id)
        toast.success('העמודים צורפו לתלוש הקודם')
      },
      onError: fail,
    })
  }

  const splitPages = () => {
    if (!slip) return
    split.mutate(slip.id, { onSuccess: () => toast.success('התלוש פוצל לעמודים'), onError: fail })
  }

  const removeSlip = async () => {
    if (!slip) return
    const ok = await confirm('להסיר את העמוד הזה? הוא לא יוצג לאף עובד.', {
      title: 'לא תלוש',
      confirmLabel: 'הסרה',
    })
    if (!ok) return
    const next = nextPending(rows, index)
    remove.mutate(slip.id, {
      onSuccess: () => {
        if (next >= 0 && rows[next].id !== slip.id) goTo(next)
        toast.success('העמוד הוסר')
      },
      onError: fail,
    })
  }

  const suggestedHere = !!slip && !slip.profile_id && !!suggested && profileId === suggested

  return (
    <Modal
      open
      onClose={onClose}
      size="xl"
      title="שיוך תלושים לעובדים"
      description={
        data ? (
          pending ? (
            <>
              {pending} תלושים ממתינים לשיוך · {rows[0]?.file_name}
            </>
          ) : (
            <>כל התלושים בקובץ שויכו · {rows[0]?.file_name}</>
          )
        ) : undefined
      }
      footer={
        <Button variant={pending ? 'secondary' : 'primary'} onClick={onClose}>
          {pending ? 'סגירה — אמשיך אחר כך' : 'סיום'}
        </Button>
      }
    >
      {dialog}
      {error && <ErrorState error={error} onRetry={() => void refetch()} />}
      {isLoading && <Skeleton className="h-[60vh] w-full" />}
      {data && !slip && <EmptyState title="אין תלושים בקובץ" art="check" />}

      {slip && (
        <div className="space-y-4">
          {/* כל התלושים בקובץ — לקפוץ, ולראות מה כבר שויך */}
          <div className="flex flex-wrap gap-1.5" role="tablist" aria-label="התלושים בקובץ">
            {rows.map((r, i) => (
              <button
                key={r.id}
                type="button"
                role="tab"
                aria-selected={i === index}
                title={r.full_name ?? r.detected_name ?? pageRangeLabel(r.page_from, r.page_to)}
                onClick={() => goTo(i)}
                className={cx(
                  'flex h-8 min-w-8 items-center justify-center gap-1 rounded-lg border px-2 type-caption tabular-nums transition-colors',
                  i === index
                    ? 'border-primary bg-primary-subtle text-primary-text'
                    : r.profile_id
                      ? 'border-success-border bg-success-subtle text-success-text'
                      : r.skipped || r.detected_kind === 'other'
                        ? 'border-line-subtle bg-subtle text-ink-tertiary'
                        : 'border-line hover:bg-subtle',
                )}
              >
                {r.profile_id && <Check size={ICON.xs} strokeWidth={STROKE} aria-hidden />}
                {r.page_from === r.page_to ? r.page_from : `${r.page_from}–${r.page_to}`}
              </button>
            ))}
          </div>

          <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_20rem]">
            {/* התלוש */}
            <div className="relative min-h-[50vh] overflow-hidden rounded-xl border border-line-subtle bg-subtle lg:min-h-[68vh]">
              {pdf.url ? (
                <iframe
                  key={pdf.url}
                  // בלי חלונית התמונות הממוזערות של הצופה — התלוש ברוחב מלא
                  src={`${pdf.url}#navpanes=0&view=FitH`}
                  title={`תלוש — ${pageRangeLabel(slip.page_from, slip.page_to)}`}
                  className="absolute inset-0 size-full"
                />
              ) : pdf.error ? (
                <div className="absolute inset-0 grid place-items-center p-6 text-center type-body text-error-text">
                  {errorMessage(pdf.error)}
                </div>
              ) : (
                <div className="absolute inset-0 grid place-items-center">
                  <Spinner size={24} />
                </div>
              )}
            </div>

            {/* למי הוא שייך */}
            <div className="space-y-4">
              <div className="flex items-center justify-between gap-2">
                <p className="type-title tabular-nums">
                  תלוש {index + 1} מתוך {rows.length}
                </p>
                <div className="flex gap-1">
                  <Button
                    size="sm"
                    variant="ghost"
                    aria-label="התלוש הקודם"
                    disabled={index === 0}
                    onClick={() => goTo(index - 1)}
                  >
                    <ChevronRight size={ICON.md} strokeWidth={STROKE} />
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    aria-label="התלוש הבא"
                    disabled={index === rows.length - 1}
                    onClick={() => goTo(index + 1)}
                  >
                    <ChevronLeft size={ICON.md} strokeWidth={STROKE} />
                  </Button>
                </div>
              </div>

              <div className="space-y-1 rounded-xl border border-line-subtle bg-subtle px-3 py-2.5 type-caption">
                <p className="text-ink-secondary">{pageRangeLabel(slip.page_from, slip.page_to)} בקובץ</p>
                {slip.detected_kind === 'other' && (
                  <p className="flex items-center gap-1.5 font-semibold text-warning-text">
                    <AlertTriangle size={ICON.sm} strokeWidth={STROKE} />
                    העמוד לא נראה כתלוש של עובד
                  </p>
                )}
                {slip.detected_name && (
                  <p>
                    <span className="text-ink-tertiary">בתלוש: </span>
                    <span className="font-semibold">{slip.detected_name}</span>
                    {slip.detected_employee_no && (
                      <span className="text-ink-tertiary tabular-nums"> · מס׳ עובד {slip.detected_employee_no}</span>
                    )}
                  </p>
                )}
                {slip.detected_period && (
                  <p>
                    <span className="text-ink-tertiary">חודש בתלוש: </span>
                    {periodLabel(slip.detected_period)}
                  </p>
                )}
                {data?.can_view_cost && slip.amounts?.employer_cost != null && (
                  <p>
                    <span className="text-ink-tertiary">עלות מעביד: </span>
                    <span dir="ltr" className="font-semibold tabular-nums">
                      {fmtMoney(slip.amounts.employer_cost)}
                    </span>
                  </p>
                )}
              </div>

              <Field
                label="העובד"
                hint={
                  suggestedHere
                    ? 'הוצע לפי ' + (slip.detected_employee_no ? 'מספר העובד' : 'השם') + ' בתלוש — יש לוודא'
                    : undefined
                }
              >
                <Select
                  value={profileId}
                  disabled={busy || !!slip.profile_id}
                  onChange={(e) =>
                    setPicked((p) => ({ ...p, [slip.id]: { ...p[slip.id], profileId: e.target.value } }))
                  }
                >
                  <option value="">בחירת עובד…</option>
                  {staffOnly.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.full_name}
                    </option>
                  ))}
                  {contractorWorkers.length > 0 && (
                    <optgroup label="עובדי קבלנים">
                      {contractorWorkers.map((p) => (
                        <option key={p.id} value={p.id}>
                          {p.full_name}
                          {p.contractor_name ? ` — ${p.contractor_name}` : ''}
                        </option>
                      ))}
                    </optgroup>
                  )}
                </Select>
              </Field>

              <Field label="חודש התלוש">
                <Select
                  value={period}
                  disabled={busy || !!slip.profile_id}
                  onChange={(e) => setPicked((p) => ({ ...p, [slip.id]: { ...p[slip.id], period: e.target.value } }))}
                >
                  {!months.includes(period) && <option value={period}>{periodLabel(period)}</option>}
                  {months.map((m) => (
                    <option key={m} value={m}>
                      {periodLabel(m)}
                    </option>
                  ))}
                </Select>
              </Field>

              {slip.profile_id ? (
                <div className="space-y-2 rounded-xl border border-success-border bg-success-subtle px-3 py-2.5">
                  <p className="flex items-center gap-1.5 type-body font-semibold text-success-text">
                    <UserCheck size={ICON.md} strokeWidth={STROKE} />
                    שויך ל{slip.full_name}
                    {slip.contractor_name ? ` (${slip.contractor_name})` : ''} — מוצג לו
                  </p>
                  {slip.same_month_count > 0 && (
                    <p className="flex items-center gap-1.5 type-caption text-warning-text">
                      <Info size={ICON.sm} strokeWidth={STROKE} />
                      יש לו עוד תלוש ל{periodLabel(slip.period)}
                    </p>
                  )}
                  <Button size="sm" variant="ghost" disabled={busy} onClick={unassign}>
                    ביטול השיוך
                  </Button>
                </div>
              ) : (
                <div className="space-y-2">
                  {slip.skipped && (
                    <div className="space-y-1.5 rounded-xl border border-line-subtle bg-subtle px-3 py-2.5">
                      <p className="type-body font-semibold text-ink-secondary">
                        סומן ״ללא שיוך״ — לא ממתין, ואף עובד אינו רואה אותו
                      </p>
                      <Button size="sm" variant="ghost" disabled={busy} onClick={unskip}>
                        החזרה לממתינים
                      </Button>
                    </div>
                  )}
                  <Button
                    variant="primary"
                    className="w-full"
                    loading={assign.isPending || setPeriod.isPending}
                    disabled={!profileId || busy}
                    onClick={() => void assignAndNext()}
                  >
                    <UserCheck size={ICON.sm} strokeWidth={STROKE} />
                    שיוך והבא
                  </Button>
                  {/* עמוד "לא תלוש" נסגר בהסרה, לא בסימון (0221) */}
                  {!slip.skipped && slip.detected_kind !== 'other' && (
                    <Button className="w-full" loading={skip.isPending} disabled={busy} onClick={skipAndNext}>
                      ללא שיוך
                    </Button>
                  )}
                </div>
              )}

              <div className="flex flex-wrap gap-1.5 border-t border-line-subtle pt-3">
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => void openSlip(slip.batch_id, slip.page_from, slip.page_to).catch(fail)}
                >
                  <ExternalLink size={ICON.sm} strokeWidth={STROKE} />
                  פתיחה בחלון
                </Button>
                {slip.has_previous && (
                  <Button size="sm" variant="ghost" disabled={busy} onClick={() => void mergePrev()}>
                    <Link2 size={ICON.sm} strokeWidth={STROKE} />
                    המשך של הקודם
                  </Button>
                )}
                {slip.page_to > slip.page_from && (
                  <Button size="sm" variant="ghost" disabled={busy} onClick={splitPages}>
                    פיצול לעמודים
                  </Button>
                )}
                <Button size="sm" variant="ghost" disabled={busy} onClick={() => void removeSlip()}>
                  <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                  לא תלוש
                </Button>
              </div>

              {!pending && (
                <Badge tone="success" className="w-full justify-center py-1.5">
                  כל התלושים בקובץ שויכו
                </Badge>
              )}
            </div>
          </div>
        </div>
      )}
    </Modal>
  )
}
