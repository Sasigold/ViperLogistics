import { useMemo, useState } from 'react'
import {
  AlertTriangle,
  Calculator,
  ChevronLeft,
  ChevronRight,
  Eye,
  FileText,
  ICON,
  Receipt,
  STROKE,
  Trash2,
  Upload,
  UserCheck,
  Users,
  Wallet,
  X,
} from '../../components/ui/icons'
import {
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  ErrorState,
  IconButton,
  Modal,
  PageHeader,
  Select,
  SkeletonList,
  StatCard,
  Tooltip,
  cx,
  fmtMoney,
  useConfirm,
  useToast,
} from '../../components/ui'
import { PERM } from '../../lib/permissions'
import { useAuth } from '../../state/auth'
import { fmtDate } from '../../lib/dates'
import { errorMessage } from '../../lib/errors'
import type { PayslipBatchOverview, PayslipBoardRow } from '../../types/domain'
import {
  costFlags,
  defaultUploadPeriod,
  pageRangeLabel,
  periodLabel,
  periodOptions,
  shiftPeriod,
  slipPages,
} from './payslips'
import {
  openSlip,
  readPayslipBatch,
  useAssignPayslip,
  useInvalidatePayslips,
  usePayslipBatches,
  usePayslipsBoard,
  useRemovePayslip,
  useRemovePayslipBatch,
} from './payslipQueries'
import { PayslipAssignWizard } from './PayslipAssignWizard'
import { PayslipUploadModal } from './PayslipUploadModal'
import { PayslipAmountsModal } from './PayslipAmountsModal'
import { NiBracketsCard } from './NiBracketsTab'

/**
 * תלושי שכר (0218) — המסך של מי שמנהל אותם.
 *
 *   • ממתינים לשיוך: מה שהועלה ועוד לא שויך, לפי קובץ, עם כפתור לשיוך.
 *   • תלושי החודש: מי קיבל תלוש, ועם `payslips.employer_cost` — ברוטו, נטו,
 *     הפרשות המעביד ועלות המעביד, וסיכום החודש מהשרת.
 *   • הקבצים שהועלו: מה שעלה, כמה שויך, וקריאה חוזרת או הסרה.
 */
export default function PayslipsPage() {
  const has = useAuth((s) => s.has)
  const canManage = has(PERM.PAYSLIPS_MANAGE)
  const canCost = has(PERM.PAYSLIPS_EMPLOYER_COST)
  const [uploadOpen, setUploadOpen] = useState(false)
  const [bracketsOpen, setBracketsOpen] = useState(false)
  const [wizardBatch, setWizardBatch] = useState<string | null>(null)

  return (
    <div className="space-y-4">
      <PageHeader
        title="תלושי שכר"
        subtitle="מעלים את קובץ התלושים מרואה החשבון, משייכים כל תלוש לעובד — והעובד רואה אותו אצלו"
        actions={
          <>
            {/* המדרגות גם כאן — רואה עלות לא בהכרח רואה את /settings (0219) */}
            {canCost && (
              <Button onClick={() => setBracketsOpen(true)}>
                <Calculator size={ICON.sm} strokeWidth={STROKE} />
                מדרגות ביטוח לאומי
              </Button>
            )}
            {canManage && (
              <Button variant="primary" onClick={() => setUploadOpen(true)}>
                <Upload size={ICON.sm} strokeWidth={STROKE} />
                העלאת קובץ תלושים
              </Button>
            )}
          </>
        }
      />
      {bracketsOpen && (
        <Modal open size="lg" title="מדרגות ביטוח לאומי מעסיק" onClose={() => setBracketsOpen(false)}>
          <NiBracketsCard />
        </Modal>
      )}

      {canManage && <PendingCard onAssign={setWizardBatch} />}
      <MonthCard canManage={canManage} canCost={canCost} />
      <BatchesCard canManage={canManage} onAssign={setWizardBatch} />

      {uploadOpen && <PayslipUploadModal onClose={() => setUploadOpen(false)} onUploaded={setWizardBatch} />}
      {wizardBatch && <PayslipAssignWizard batchId={wizardBatch} onClose={() => setWizardBatch(null)} />}
    </div>
  )
}

/** שם בעל התלוש לתצוגה: העובד, ובתלוש "ללא שיוך" — השם שנקרא ממנו. */
const slipOwner = (r: PayslipBoardRow) => r.full_name ?? r.detected_name ?? 'תלוש ללא שם'

/* ===== ממתינים לשיוך ===== */

function PendingCard({ onAssign }: { onAssign: (batchId: string) => void }) {
  const { data, isLoading, error, refetch } = usePayslipsBoard({ unassigned: true })

  const groups = useMemo(() => {
    const map = new Map<
      string,
      { batchId: string; fileName: string; slips: number; other: number; periods: Set<string> }
    >()
    for (const r of data?.slips ?? []) {
      const g = map.get(r.batch_id) ?? {
        batchId: r.batch_id,
        fileName: r.file_name,
        slips: 0,
        other: 0,
        periods: new Set(),
      }
      if (r.detected_kind === 'other') g.other++
      else {
        g.slips++
        g.periods.add(r.period)
      }
      map.set(r.batch_id, g)
    }
    return [...map.values()].filter((g) => g.slips > 0)
  }, [data?.slips])

  if (error) return <ErrorState error={error} onRetry={() => void refetch()} />
  if (isLoading || !groups.length) return null

  return (
    <Card className="border-warning-border">
      <CardHeader
        icon={<AlertTriangle size={ICON.lg} strokeWidth={STROKE} className="text-warning-text" />}
        title="ממתינים לשיוך"
        subtitle="תלושים שהועלו ועוד לא שויכו לעובד — העובדים לא רואים אותם עד השיוך"
      />
      <CardBody className="space-y-2">
        {groups.map((g) => (
          <div
            key={g.batchId}
            className="flex flex-wrap items-center gap-3 rounded-lg border border-line-subtle px-3 py-2.5"
          >
            <FileText size={ICON.lg} strokeWidth={STROKE} className="shrink-0 text-ink-tertiary" />
            <div className="min-w-40 flex-1">
              <p className="truncate type-body font-semibold">{g.fileName}</p>
              <p className="type-caption text-ink-tertiary">
                {[...g.periods].map(periodLabel).join(', ')} · {g.slips} תלושים ממתינים
                {g.other > 0 && ` · ${g.other} עמודים שאינם תלוש`}
              </p>
            </div>
            <Button variant="primary" size="sm" onClick={() => onAssign(g.batchId)}>
              <UserCheck size={ICON.sm} strokeWidth={STROKE} />
              שיוך
            </Button>
          </div>
        ))}
      </CardBody>
    </Card>
  )
}

/* ===== תלושי החודש ===== */

function MonthCard({ canManage, canCost }: { canManage: boolean; canCost: boolean }) {
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const months = useMemo(() => periodOptions(new Date()), [])
  const [period, setPeriod] = useState(() => defaultUploadPeriod(new Date()))
  const [amountsFor, setAmountsFor] = useState<string | null>(null)
  const { data, isLoading, error, refetch } = usePayslipsBoard({ period })
  const assign = useAssignPayslip()
  const remove = useRemovePayslip()

  const rows = useMemo(
    () =>
      (data?.slips ?? [])
        // רק משויכים: "ללא שיוך" אינו בטבלה ואינו בסיכומים (0222)
        .filter((r) => r.profile_id)
        .sort((a, b) => slipOwner(a).localeCompare(slipOwner(b), 'he')),
    [data?.slips],
  )
  const waiting = (data?.slips ?? []).filter(
    (r) => !r.profile_id && !r.skipped && r.detected_kind !== 'other',
  ).length
  const skippedCount = (data?.slips ?? []).filter((r) => !r.profile_id && r.skipped).length
  const showCost = canCost && !!data?.can_view_cost
  const t = data?.totals
  const amountsSlip = amountsFor ? (data?.slips.find((r) => r.id === amountsFor) ?? null) : null

  const fail = (e: unknown) => toast.error(errorMessage(e))

  const unassign = async (r: PayslipBoardRow) => {
    const ok = await confirm(`לבטל את השיוך של התלוש ל${r.full_name}? הוא יחזור לרשימת הממתינים.`, {
      title: 'ביטול שיוך',
      confirmLabel: 'ביטול השיוך',
    })
    if (ok) assign.mutate({ id: r.id, profileId: null }, { onError: fail })
  }

  const removeSlip = async (r: PayslipBoardRow) => {
    const ok = await confirm(`להסיר את התלוש של ${slipOwner(r)} ל${periodLabel(r.period)}? הוא ייעלם גם אצלו.`, {
      title: 'הסרת תלוש',
      confirmLabel: 'הסרה',
    })
    if (ok) remove.mutate(r.id, { onSuccess: () => toast.success('התלוש הוסר'), onError: fail })
  }

  return (
    <Card>
      {dialog}
      <CardHeader
        icon={<Receipt size={ICON.lg} strokeWidth={STROKE} />}
        title={`תלושי ${periodLabel(period)}`}
        subtitle={showCost ? 'עלות המעביד מחושבת מהסכומים שבתלוש — רק אתה רואה אותה' : undefined}
        actions={
          <div className="flex items-center gap-1">
            <IconButton label="החודש הקודם" onClick={() => setPeriod((p) => shiftPeriod(p, -1))}>
              <ChevronRight size={ICON.md} strokeWidth={STROKE} />
            </IconButton>
            <Select selectSize="sm" className="w-36" value={period} onChange={(e) => setPeriod(e.target.value)}>
              {!months.includes(period) && <option value={period}>{periodLabel(period)}</option>}
              {months.map((m) => (
                <option key={m} value={m}>
                  {periodLabel(m)}
                </option>
              ))}
            </Select>
            <IconButton label="החודש הבא" onClick={() => setPeriod((p) => shiftPeriod(p, 1))}>
              <ChevronLeft size={ICON.md} strokeWidth={STROKE} />
            </IconButton>
          </div>
        }
      />
      <CardBody className="space-y-4">
        {error && <ErrorState error={error} onRetry={() => void refetch()} />}
        {isLoading && <SkeletonList rows={4} />}

        {showCost && t && t.count > 0 && (
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard
              icon={<Wallet size={ICON.xl} strokeWidth={STROKE} />}
              label="עלות מעביד כוללת"
              value={fmtMoney(t.employer_cost)}
              tone="#7c3aed"
              hint={t.with_amounts < t.count ? `${t.count - t.with_amounts} תלושים בלי סכומים` : undefined}
            />
            <StatCard
              icon={<Receipt size={ICON.xl} strokeWidth={STROKE} />}
              label="ברוטו"
              value={fmtMoney(t.gross_pay)}
            />
            <StatCard
              icon={<Calculator size={ICON.xl} strokeWidth={STROKE} />}
              label="הפרשות המעביד"
              value={fmtMoney(t.employer_contributions)}
              tone="#0ea5e9"
            />
            <StatCard
              icon={<Users size={ICON.xl} strokeWidth={STROKE} />}
              label="נטו ששולם"
              value={fmtMoney(t.net_pay)}
              tone="#22c55e"
            />
          </div>
        )}

        {waiting > 0 && (
          <p className="flex items-center gap-2 type-caption text-warning-text">
            <AlertTriangle size={ICON.sm} strokeWidth={STROKE} />
            עוד {waiting} תלושים ל{periodLabel(period)} ממתינים לשיוך
          </p>
        )}

        {skippedCount > 0 && (
          <p className="type-caption text-ink-tertiary">
            {skippedCount} תלושים ל{periodLabel(period)} סומנו ״ללא שיוך״ — אינם בטבלה ובסיכומים (אפשר לשייך אותם מאשף
            השיוך של הקובץ)
          </p>
        )}

        {data && rows.length === 0 && <EmptyState compact art="table" title="אין תלושים משויכים לחודש הזה" />}

        {rows.length > 0 && (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[36rem] type-body">
              <thead>
                <tr className="border-b border-line-subtle text-start type-caption text-ink-tertiary">
                  <th className="py-2 text-start font-medium">עובד</th>
                  {showCost && (
                    <>
                      <th className="py-2 text-end font-medium">ברוטו</th>
                      <th className="py-2 text-end font-medium">נטו</th>
                      <th className="py-2 text-end font-medium">הפרשות מעביד</th>
                      <th className="py-2 text-end font-medium">עלות מעביד</th>
                    </>
                  )}
                  <th className="py-2" />
                </tr>
              </thead>
              <tbody className="divide-y divide-line-subtle">
                {rows.map((r) => {
                  const flags = showCost ? costFlags(r.amounts) : []
                  return (
                    <tr key={r.id}>
                      <td className="py-2 pe-3">
                        <p className="font-semibold">
                          {slipOwner(r)}
                          {r.contractor_name && (
                            <span className="font-normal text-ink-tertiary"> · {r.contractor_name}</span>
                          )}
                        </p>
                        <p className="type-caption text-ink-tertiary">
                          {pageRangeLabel(r.page_from, r.page_to)} · {r.file_name}
                          {r.same_month_count > 0 && (
                            <Badge tone="warning" className="ms-1.5">
                              {r.same_month_count + 1} תלושים בחודש
                            </Badge>
                          )}
                        </p>
                      </td>
                      {showCost && (
                        <>
                          <Money value={r.amounts?.gross_pay} />
                          <Money value={r.amounts?.net_pay} />
                          <Money value={r.amounts ? r.amounts.employer_contributions : null} />
                          <td className="py-2 ps-3 text-end">
                            <span className="inline-flex items-center gap-1.5">
                              {flags.length > 0 && (
                                <Tooltip content={flags.map((f) => f.text).join(' · ')}>
                                  <AlertTriangle
                                    size={ICON.sm}
                                    strokeWidth={STROKE}
                                    className={cx(
                                      flags.some((f) => f.tone === 'warning')
                                        ? 'text-warning-text'
                                        : 'text-ink-tertiary',
                                    )}
                                  />
                                </Tooltip>
                              )}
                              <span dir="ltr" className="font-semibold tabular-nums">
                                {r.amounts?.employer_cost == null ? '—' : fmtMoney(r.amounts.employer_cost)}
                              </span>
                            </span>
                          </td>
                        </>
                      )}
                      <td className="py-2 ps-3">
                        <div className="flex justify-end gap-0.5">
                          <IconButton
                            label="צפייה בתלוש"
                            onClick={() => void openSlip(r.batch_id, r.page_from, r.page_to).catch(fail)}
                          >
                            <Eye size={ICON.md} strokeWidth={STROKE} />
                          </IconButton>
                          {showCost && (
                            <IconButton label="סכומים ועלות מעביד" onClick={() => setAmountsFor(r.id)}>
                              <Calculator size={ICON.md} strokeWidth={STROKE} />
                            </IconButton>
                          )}
                          {canManage && (
                            <>
                              <IconButton label="ביטול השיוך" onClick={() => void unassign(r)}>
                                <X size={ICON.md} strokeWidth={STROKE} />
                              </IconButton>
                              <IconButton label="הסרת התלוש" onClick={() => void removeSlip(r)}>
                                <Trash2 size={ICON.md} strokeWidth={STROKE} />
                              </IconButton>
                            </>
                          )}
                        </div>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
              {showCost && t && (
                <tfoot>
                  <tr className="border-t-2 border-line font-semibold">
                    <td className="py-2">סה״כ ({t.count})</td>
                    <Money value={t.gross_pay} />
                    <Money value={t.net_pay} />
                    <Money value={t.employer_contributions} />
                    <Money value={t.employer_cost} />
                    <td />
                  </tr>
                </tfoot>
              )}
            </table>
          </div>
        )}
      </CardBody>
      {amountsSlip && <PayslipAmountsModal slip={amountsSlip} onClose={() => setAmountsFor(null)} />}
    </Card>
  )
}

function Money({ value }: { value: number | null | undefined }) {
  return (
    <td className="py-2 ps-3 text-end">
      <span dir="ltr" className="tabular-nums">
        {value === null || value === undefined ? '—' : fmtMoney(value)}
      </span>
    </td>
  )
}

/* ===== הקבצים שהועלו ===== */

function BatchesCard({ canManage, onAssign }: { canManage: boolean; onAssign: (batchId: string) => void }) {
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const { data = [], isLoading, error, refetch } = usePayslipBatches()
  const removeBatch = useRemovePayslipBatch()
  const invalidate = useInvalidatePayslips()
  const [reading, setReading] = useState<{ id: string; done: number; total: number } | null>(null)

  // קובץ שכבר שויכו ממנו תלושים נקרא מחדש רק לסכומים — השיוך והקיבוץ נשארים (0219)
  const read = async (b: PayslipBatchOverview) => {
    // גם "ללא שיוך" הוא החלטה שקיבוץ מחדש היה מוחק (0221)
    const mode = b.assigned + b.skipped > 0 ? 'amounts' : 'group'
    setReading({ id: b.id, done: 0, total: b.page_count })
    try {
      const r = await readPayslipBatch(
        b.id,
        slipPages(1, b.page_count),
        (s) => {
          if (s.step === 'read') setReading({ id: b.id, done: s.done, total: s.total })
        },
        mode,
      )
      if (!r.configured) toast.info('הקריאה האוטומטית אינה מוגדרת — יש להגדיר את מפתח ה-API של Anthropic')
      else if (r.grouped)
        toast.success(
          `נקראו ${r.read} עמודים${r.failed.length ? `, ${r.failed.length} לא נקראו` : ''}` +
            (r.manual ? ` · ${r.manual} תלושים שהוקלדו ביד לא שונו` : ''),
        )
      else toast.error(r.failed[0]?.error ?? 'אף עמוד לא נקרא')
    } catch (e) {
      toast.error(errorMessage(e))
    } finally {
      setReading(null)
      invalidate()
    }
  }

  const remove = async (b: PayslipBatchOverview) => {
    const ok = await confirm(
      b.assigned
        ? `להסיר את "${b.file_name}"? ${b.assigned} תלושים שכבר שויכו ייעלמו מהעובדים.`
        : `להסיר את "${b.file_name}"?`,
      { title: 'הסרת קובץ', confirmLabel: 'הסרה' },
    )
    if (!ok) return
    removeBatch.mutate(
      { id: b.id, pageCount: b.page_count },
      { onSuccess: () => toast.success('הקובץ הוסר'), onError: (e) => toast.error(errorMessage(e)) },
    )
  }

  if (error) return <ErrorState error={error} onRetry={() => void refetch()} />

  return (
    <Card>
      {dialog}
      <CardHeader icon={<FileText size={ICON.lg} strokeWidth={STROKE} />} title="קבצים שהועלו" />
      <CardBody>
        {isLoading && <SkeletonList rows={3} />}
        {!isLoading && data.length === 0 && (
          <EmptyState
            compact
            art="box"
            title="עוד לא הועלו תלושים"
            description={canManage ? 'מעלים את קובץ ה-PDF מרואה החשבון בכפתור "העלאת קובץ תלושים"' : undefined}
          />
        )}
        {data.length > 0 && (
          <ul className="divide-y divide-line-subtle">
            {data.map((b) => (
              <li key={b.id} className="flex flex-wrap items-center gap-3 py-2.5">
                <div className="min-w-40 flex-1">
                  <p className="truncate type-body font-semibold">{b.file_name}</p>
                  <p className="type-caption text-ink-tertiary">
                    {periodLabel(b.period)} · הועלה {fmtDate(b.created_at)}
                    {b.uploaded_by && ` ע״י ${b.uploaded_by}`} · {b.page_count} עמודים
                    {b.read_at ? ' · נקרא אוטומטית' : ''}
                  </p>
                </div>
                <Badge tone={b.assigned + b.skipped >= b.slips && b.slips > 0 ? 'success' : 'warning'}>
                  {b.assigned}/{b.slips} שויכו{b.skipped ? ` · ${b.skipped} ללא שיוך` : ''}
                </Badge>
                {reading?.id === b.id ? (
                  <span className="type-caption text-ink-tertiary tabular-nums">
                    קורא… {reading.done}/{reading.total}
                  </span>
                ) : (
                  canManage && (
                    <div className="flex gap-1">
                      <Button size="sm" variant="ghost" onClick={() => onAssign(b.id)}>
                        שיוך
                      </Button>
                      <Button size="sm" variant="ghost" disabled={!!reading} onClick={() => void read(b)}>
                        {b.assigned + b.skipped > 0 ? 'קריאת הסכומים מחדש' : b.read_at ? 'קריאה מחדש' : 'קריאה אוטומטית'}
                      </Button>
                      <IconButton label="הסרת הקובץ" onClick={() => void remove(b)}>
                        <Trash2 size={ICON.md} strokeWidth={STROKE} />
                      </IconButton>
                    </div>
                  )
                )}
              </li>
            ))}
          </ul>
        )}
      </CardBody>
    </Card>
  )
}
