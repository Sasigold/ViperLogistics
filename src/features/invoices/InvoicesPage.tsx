import { useEffect, useMemo, useState } from 'react'
import { useSearchParams } from 'react-router'
import {
  AlertTriangle,
  Calculator,
  Camera,
  ChevronLeft,
  ChevronRight,
  Download,
  FileText,
  Folder,
  FolderOpen,
  ICON,
  Mail,
  Percent,
  RefreshCw,
  Receipt,
  STROKE,
  Settings,
  Upload,
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
  PageHeader,
  ProgressBar,
  SkeletonList,
  Spinner,
  StatCard,
  cx,
  fmtMoney,
  useToast,
} from '../../components/ui'
import { errorMessage } from '../../lib/errors'
import type { Invoice, InvoicesBoard } from '../../types/domain'
import { InvoiceDrawer } from './InvoiceDrawer'
import { InvoiceSettingsModal } from './InvoiceSettingsModal'
import { InvoiceUploadModal } from './InvoiceUploadModal'
import { exportInvoicesZip } from './exportInvoices'
import {
  CATEGORY_LABELS,
  DOC_TYPE_LABELS,
  FLAG_LABELS,
  fmtAmount,
  fmtInvoiceDate,
  invoiceFlags,
  monthLabel,
  monthOf,
  shiftMonth,
} from './invoices'
import {
  loadInvoicePdf,
  readInvoices,
  syncGmail,
  useGmailStatus,
  useInvalidateInvoices,
  useInvoiceCompanies,
  useInvoicesBoard,
} from './invoiceQueries'

/**
 * חשבוניות ספקים (0233) — מנהלי מערכת בלבד. תיקייה לכל חודש, סיכום מע"מ,
 * העלאה/צילום, סריקת Gmail וייצוא ZIP לרואה החשבון.
 */
export default function InvoicesPage() {
  const toast = useToast()
  const [params, setParams] = useSearchParams()
  const [period, setPeriod] = useState(() => monthOf(new Date()))
  const [upload, setUpload] = useState<'files' | 'camera' | null>(null)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [openId, setOpenId] = useState<string | null>(null)

  const board = useInvoicesBoard(period)
  const companies = useInvoiceCompanies()
  const gmail = useGmailStatus()

  // חזרה ממסך ההסכמה של Google
  useEffect(() => {
    const g = params.get('gmail')
    if (!g) return
    if (g === 'connected') toast.success('Gmail חובר. אפשר להריץ סריקה ראשונה — ״סריקת Gmail״.')
    else if (g === 'denied') toast.info('החיבור ל-Gmail בוטל')
    else toast.error('החיבור ל-Gmail לא הושלם — נסו שוב')
    setSettingsOpen(true)
    params.delete('gmail')
    params.delete('reason')
    setParams(params, { replace: true })
  }, [params, setParams, toast])

  const invoices = board.data?.invoices ?? []
  const open = invoices.find((i) => i.id === openId) ?? null
  const hasGmail = (gmail.data?.accounts.length ?? 0) > 0

  return (
    <div className="space-y-4">
      <PageHeader
        title="חשבוניות"
        subtitle="חשבוניות הספקים — סריקה אוטומטית, תיקייה לכל חודש, וייצוא מסודר לרואה החשבון"
        actions={
          <>
            <IconButton label="הגדרות: חברות ו-Gmail" variant="secondary" onClick={() => setSettingsOpen(true)}>
              <Settings size={ICON.md} strokeWidth={STROKE} />
            </IconButton>
            {hasGmail && <GmailSyncButton />}
            <Button onClick={() => setUpload('camera')}>
              <Camera size={ICON.sm} strokeWidth={STROKE} />
              צילום
            </Button>
            <Button variant="primary" onClick={() => setUpload('files')}>
              <Upload size={ICON.sm} strokeWidth={STROKE} />
              העלאת חשבוניות
            </Button>
          </>
        }
      />

      <FoldersStrip board={board.data} period={period} onPick={setPeriod} />

      {board.error && <ErrorState error={board.error} onRetry={() => void board.refetch()} />}
      {board.isLoading && <SkeletonList rows={5} />}
      {board.data && (
        <MonthView
          board={board.data}
          hasCompanies={(companies.data?.length ?? 0) > 0}
          period={period}
          onPeriod={setPeriod}
          onOpen={setOpenId}
          onUpload={() => setUpload('files')}
        />
      )}

      {!gmail.isLoading && !hasGmail && (
        <p className="flex items-center gap-2 type-caption text-ink-tertiary">
          <Mail size={ICON.sm} strokeWidth={STROKE} />
          אפשר לחבר את Gmail, והחשבוניות שנשלחות אליו ייכנסו לכאן מעצמן —
          <button type="button" className="text-primary-text underline" onClick={() => setSettingsOpen(true)}>
            הגדרות
          </button>
        </p>
      )}

      {upload && <InvoiceUploadModal mode={upload} onClose={() => setUpload(null)} />}
      {settingsOpen && <InvoiceSettingsModal onClose={() => setSettingsOpen(false)} />}
      {open && (
        <InvoiceDrawer
          key={`${open.id}-${open.read_at ?? ''}`}
          invoice={open}
          companies={companies.data ?? []}
          onClose={() => setOpenId(null)}
        />
      )}
    </div>
  )
}

/* ===== התיקיות ===== */

function FoldersStrip({
  board,
  period,
  onPick,
}: {
  board: InvoicesBoard | undefined
  period: string
  onPick: (p: string) => void
}) {
  const current = monthOf(new Date())
  // החודש הנוכחי ושלפניו תמיד מוצגים, גם ריקים; השאר — מה שיש בו חשבוניות
  const months = useMemo(() => {
    const map = new Map((board?.months ?? []).map((m) => [m.period, m]))
    for (const p of [current, shiftMonth(current, -1), period]) {
      if (!map.has(p)) map.set(p, { period: p, count: 0, total: 0, vat: 0, unreviewed: 0 })
    }
    return [...map.values()].sort((a, b) => b.period.localeCompare(a.period))
  }, [board?.months, current, period])

  return (
    <div className="-mx-1 flex gap-2 overflow-x-auto px-1 pb-1">
      {months.map((m) => {
        const active = m.period === period
        const Icon = active ? FolderOpen : Folder
        return (
          <button
            key={m.period}
            type="button"
            onClick={() => onPick(m.period)}
            className={cx(
              'flex min-w-[9.5rem] shrink-0 flex-col items-start gap-1 rounded-xl border px-3 py-2.5 text-start transition',
              active ? 'border-primary bg-primary-subtle' : 'border-line bg-surface hover:border-primary/50',
            )}
          >
            <span className="flex items-center gap-1.5 type-body font-medium">
              <Icon size={ICON.md} strokeWidth={STROKE} className={active ? 'text-primary-text' : 'text-ink-tertiary'} />
              {monthLabel(m.period)}
            </span>
            <span className="type-caption text-ink-tertiary">
              {m.count} חשבוניות{m.count > 0 && ` · ${fmtMoney(m.total)}`}
            </span>
            {m.unreviewed > 0 && <Badge tone="info">{m.unreviewed} לבדיקה</Badge>}
          </button>
        )
      })}
    </div>
  )
}

/* ===== החודש ===== */

function MonthView({
  board,
  hasCompanies,
  period,
  onPeriod,
  onOpen,
  onUpload,
}: {
  board: InvoicesBoard
  hasCompanies: boolean
  period: string
  onPeriod: (p: string) => void
  onOpen: (id: string) => void
  onUpload: () => void
}) {
  const toast = useToast()
  const invalidate = useInvalidateInvoices()
  const [exporting, setExporting] = useState<{ done: number; total: number } | null>(null)
  const [reading, setReading] = useState<{ done: number; total: number } | null>(null)
  const t = board.totals
  const pending = board.invoices.filter((i) => !i.reviewed_at && i.read_status !== 'done')

  const doExport = async () => {
    setExporting({ done: 0, total: board.invoices.length })
    try {
      await exportInvoicesZip(board, (id) => loadInvoicePdf({ id }), (done, total) => setExporting({ done, total }))
    } catch (e) {
      toast.error(`הייצוא נכשל: ${errorMessage(e)}`)
    } finally {
      setExporting(null)
    }
  }

  const readPending = async () => {
    setReading({ done: 0, total: pending.length })
    try {
      const r = await readInvoices(
        pending.map((i) => i.id),
        (done, total) => setReading({ done, total }),
      )
      if (!r.configured) toast.error('הקריאה האוטומטית עוד לא מוגדרת בשרת (ANTHROPIC_API_KEY)')
      else if (r.failed.length) toast.error(`${r.failed.length} לא נקראו: ${r.failed[0].error}`)
      else toast.success(`${r.read} חשבוניות נקראו`)
    } catch (e) {
      toast.error(errorMessage(e))
    } finally {
      setReading(null)
      invalidate()
    }
  }

  return (
    <Card>
      <CardHeader
        icon={<FolderOpen size={ICON.lg} strokeWidth={STROKE} />}
        title={
          <span className="flex items-center gap-1">
            <IconButton label="החודש הקודם" size="sm" onClick={() => onPeriod(shiftMonth(period, -1))}>
              <ChevronRight size={ICON.md} strokeWidth={STROKE} />
            </IconButton>
            {monthLabel(period)}
            <IconButton label="החודש הבא" size="sm" onClick={() => onPeriod(shiftMonth(period, 1))}>
              <ChevronLeft size={ICON.md} strokeWidth={STROKE} />
            </IconButton>
          </span>
        }
        actions={
          <Button onClick={() => void doExport()} disabled={!!exporting || t.count === 0}>
            {exporting ? <Spinner size={ICON.sm} /> : <Download size={ICON.sm} strokeWidth={STROKE} />}
            ייצוא לרואה החשבון (ZIP)
          </Button>
        }
      />
      <CardBody className="space-y-4">
        {exporting && exporting.total > 0 && (
          <ProgressBar value={(exporting.done / exporting.total) * 100} label={`מכין את הקובץ… ${exporting.done}/${exporting.total}`} />
        )}

        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <StatCard icon={<Receipt size={ICON.xl} strokeWidth={STROKE} />} label="סה״כ כולל מע״מ" value={fmtMoney(t.total)} tone="#7c3aed" />
          <StatCard icon={<Calculator size={ICON.xl} strokeWidth={STROKE} />} label="לפני מע״מ" value={fmtMoney(t.before_vat)} />
          <StatCard icon={<Percent size={ICON.xl} strokeWidth={STROKE} />} label="מע״מ" value={fmtMoney(t.vat)} tone="#0ea5e9" />
          <StatCard
            icon={<FileText size={ICON.xl} strokeWidth={STROKE} />}
            label="חשבוניות"
            value={t.count}
            tone="#22c55e"
            hint={t.unreviewed > 0 ? `${t.unreviewed} ממתינות לבדיקה` : t.count > 0 ? 'כולן נבדקו' : undefined}
          />
        </div>

        {t.foreign > 0 && (
          <p className="type-caption text-ink-tertiary">
            {t.foreign} חשבוניות במטבע זר — מופיעות ברשימה ובייצוא, אבל אינן בסיכום בשקלים.
          </p>
        )}
        {t.missing_total > 0 && (
          <p className="flex items-center gap-2 type-caption text-warning-text">
            <AlertTriangle size={ICON.sm} strokeWidth={STROKE} />
            ל-{t.missing_total} חשבוניות חסר סכום — הן אינן בסיכום עד שיושלם.
          </p>
        )}

        {pending.length > 0 && (
          <div className="flex flex-wrap items-center gap-2 rounded-lg bg-info-subtle px-3 py-2 type-body text-info-text">
            <span>{pending.length} חשבוניות עוד לא נקראו</span>
            <Button size="sm" className="ms-auto" onClick={() => void readPending()} disabled={!!reading}>
              {reading ? <Spinner size={ICON.sm} /> : <RefreshCw size={ICON.sm} strokeWidth={STROKE} />}
              {reading ? `קורא… ${reading.done}/${reading.total}` : 'קריאה עכשיו'}
            </Button>
          </div>
        )}

        {board.categories.length > 0 && (
          <div className="flex flex-wrap gap-1.5">
            {board.categories.map((c) => (
              <span key={c.category} className="rounded-full bg-subtle px-2.5 py-1 type-caption text-ink-secondary">
                {CATEGORY_LABELS[c.category]} · {fmtMoney(c.total)}
              </span>
            ))}
          </div>
        )}

        {board.invoices.length === 0 ? (
          <EmptyState
            compact
            art="table"
            title={`אין חשבוניות ב${monthLabel(period)}`}
            description="מעלים קובץ, מצלמים, או מחברים Gmail"
            action={
              <Button variant="primary" onClick={onUpload}>
                <Upload size={ICON.sm} strokeWidth={STROKE} />
                העלאת חשבוניות
              </Button>
            }
          />
        ) : (
          <InvoiceTable invoices={board.invoices} hasCompanies={hasCompanies} onOpen={onOpen} />
        )}
      </CardBody>
    </Card>
  )
}

function InvoiceTable({
  invoices,
  hasCompanies,
  onOpen,
}: {
  invoices: Invoice[]
  hasCompanies: boolean
  onOpen: (id: string) => void
}) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[46rem] type-body">
        <thead>
          <tr className="border-b border-line text-start type-caption text-ink-tertiary">
            <th className="py-2 pe-3 text-start font-medium">תאריך</th>
            <th className="py-2 pe-3 text-start font-medium">ספק</th>
            <th className="py-2 pe-3 text-start font-medium">על מה</th>
            <th className="py-2 pe-3 text-end font-medium">לפני מע״מ</th>
            <th className="py-2 pe-3 text-end font-medium">מע״מ</th>
            <th className="py-2 pe-3 text-end font-medium">סה״כ</th>
            <th className="py-2 text-start font-medium">מצב</th>
          </tr>
        </thead>
        <tbody>
          {invoices.map((i) => {
            const flags = invoiceFlags(i, hasCompanies).filter((f) => f !== 'unreviewed')
            return (
              <tr
                key={i.id}
                onClick={() => onOpen(i.id)}
                className="cursor-pointer border-b border-line/60 hover:bg-subtle"
              >
                <td className="whitespace-nowrap py-2 pe-3 tabular-nums">{fmtInvoiceDate(i.issue_date) || '—'}</td>
                <td className="py-2 pe-3">
                  <div className="font-medium">{i.vendor_name || i.file_name}</div>
                  <div className="type-caption text-ink-tertiary">
                    {DOC_TYPE_LABELS[i.doc_type]}
                    {i.invoice_number && ` ${i.invoice_number}`}
                    {i.source === 'gmail' && ' · Gmail'}
                  </div>
                </td>
                <td className="py-2 pe-3">
                  <div>{CATEGORY_LABELS[i.category]}</div>
                  {i.description && <div className="type-caption text-ink-tertiary">{i.description}</div>}
                </td>
                <td className="whitespace-nowrap py-2 pe-3 text-end tabular-nums">{fmtAmount(i.amount_before_vat, i.currency)}</td>
                <td className="whitespace-nowrap py-2 pe-3 text-end tabular-nums">{fmtAmount(i.vat_amount, i.currency)}</td>
                <td className="whitespace-nowrap py-2 pe-3 text-end font-medium tabular-nums">
                  {fmtAmount(i.total_amount, i.currency)}
                </td>
                <td className="py-2">
                  <div className="flex flex-wrap gap-1">
                    {i.reviewed_at ? (
                      <Badge tone="success" dot>
                        אושרה
                      </Badge>
                    ) : i.read_status === 'pending' ? (
                      <Badge>ממתינה לקריאה</Badge>
                    ) : i.read_status === 'failed' ? (
                      <Badge tone="error">לא נקראה</Badge>
                    ) : (
                      <Badge tone="info">לבדיקה</Badge>
                    )}
                    {flags
                      .filter((f) => f !== 'unread' && f !== 'failed')
                      .map((f) => (
                        <Badge key={f} tone="warning">
                          {FLAG_LABELS[f]}
                        </Badge>
                      ))}
                  </div>
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

/* ===== Gmail ===== */

function GmailSyncButton() {
  const toast = useToast()
  const invalidate = useInvalidateInvoices()
  const [running, setRunning] = useState<string | null>(null)

  const run = async () => {
    setRunning('סורק…')
    try {
      const r = await syncGmail((p) => {
        const imported = p.accounts.reduce((s, a) => s + a.imported, 0)
        const checked = p.accounts.reduce((s, a) => s + a.checked, 0)
        setRunning(`נבדקו ${checked} מיילים · ${imported} חשבוניות`)
        invalidate()
      })
      const imported = r.accounts.reduce((s, a) => s + a.imported, 0)
      const errors = r.accounts.filter((a) => a.error)
      if (errors.length) toast.error(`${errors[0].email}: ${errors[0].error}`)
      else if (imported > 0) toast.success(`${imported} חשבוניות חדשות נמשכו מ-Gmail`)
      else toast.info(r.more ? 'הסריקה נמשכת — היא תמשיך מעצמה בריצה הבאה' : 'אין חשבוניות חדשות ב-Gmail')
    } catch (e) {
      toast.error(errorMessage(e))
    } finally {
      setRunning(null)
      invalidate()
    }
  }

  return (
    <Button onClick={() => void run()} disabled={!!running}>
      {running ? <Spinner size={ICON.sm} /> : <Mail size={ICON.sm} strokeWidth={STROKE} />}
      {running ?? 'סריקת Gmail'}
    </Button>
  )
}
