import { useState } from 'react'
import { format } from 'date-fns'
import { useNavigate } from 'react-router'
import {
  AlertTriangle,
  Banknote,
  ICON,
  Minus,
  Plus,
  STROKE,
  Trash2,
  TrendingDown,
  TrendingUp,
  Wallet,
} from '../../components/ui/icons'
import {
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  ErrorState,
  Field,
  FilterBar,
  IconButton,
  Input,
  Modal,
  PageHeader,
  SegmentedControl,
  SkeletonList,
  StatCard,
  Textarea,
  cx,
  fmtMoney,
  useConfirm,
  useToast,
} from '../../components/ui'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { fmtDate } from '../../lib/dates'
import { errorMessage } from '../../lib/errors'
import type { CashWalletEntry } from '../../types/domain'
import { PRESET_LABELS, parseAmount } from './eventPayments'
import type { RangePreset } from './eventPayments'
import { SOURCE_LABELS, SOURCE_TONES, entryTitle, isManual, walletRange, walletRangeError } from './cashWallet'
import type { WalletPreset } from './cashWallet'
import { useAddWalletEntry, useCashWallet, useRemoveWalletEntry } from './cashWalletQueries'

const PRESETS: RangePreset[] = ['month', 'prev_month', 'quarter', 'year']

type EntryKind = 'expense' | 'income'

/**
 * ארנק המזומנים (0207): כל תשלום שנרשם על אירוע כ"מזומן" נכנס לכאן, וכל
 * הוצאה (או הכנסה) שנרשמת ביד — יוצאת (או נכנסת). למעלה: היתרה היום. למטה:
 * התנועות בטווח, החדשה ראשונה, עם היתרה אחרי כל אחת — כמו דף בנק.
 */
export default function CashWalletPage() {
  const navigate = useNavigate()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const [preset, setPreset] = useState<WalletPreset | null>('month')
  const [range, setRange] = useState(() => walletRange('month', new Date()))
  const [entryKind, setEntryKind] = useState<EntryKind | null>(null)

  const invalid = walletRangeError(range.from, range.to)
  const { data, isLoading, error, refetch } = useCashWallet(range.from, range.to, !invalid)
  const remove = useRemoveWalletEntry()

  const pickPreset = (p: WalletPreset) => {
    setPreset(p)
    setRange(walletRange(p, new Date()))
  }

  const removeEntry = async (e: CashWalletEntry) => {
    const ok = await confirm(`למחוק את "${entryTitle(e)}" (${fmtMoney(Math.abs(e.amount))}) מהארנק?`, {
      title: 'מחיקה מהארנק',
      confirmLabel: 'מחיקה',
    })
    if (!ok) return
    remove.mutate(e.id, {
      onSuccess: () => toast.success('נמחק מהארנק'),
      onError: (err) => toast.error(errorMessage(err)),
    })
  }

  const canManage = !!data?.can_manage

  return (
    <RequirePermission perm={PERM.FINANCE_CASH_WALLET_VIEW}>
      <div className="space-y-4">
        {dialog}
        <PageHeader
          title="ארנק מזומנים"
          subtitle="כל תשלום שהתקבל במזומן נכנס לכאן; הוצאות נרשמות ביד"
          actions={
            canManage && (
              <>
                <Button onClick={() => setEntryKind('income')}>
                  <Plus size={ICON.sm} strokeWidth={STROKE} />
                  הכנסה
                </Button>
                <Button variant="primary" onClick={() => setEntryKind('expense')}>
                  <Minus size={ICON.sm} strokeWidth={STROKE} />
                  הוספת הוצאה
                </Button>
              </>
            )
          }
        >
          <FilterBar>
            <div className="max-w-full overflow-x-auto">
              <SegmentedControl<WalletPreset | 'custom'>
                items={[
                  ...PRESETS.map((p) => ({ key: p, label: PRESET_LABELS[p] })),
                  { key: 'all' as const, label: 'הכול' },
                  { key: 'custom' as const, label: 'טווח' },
                ]}
                value={preset ?? 'custom'}
                onChange={(k) => (k === 'custom' ? setPreset(null) : pickPreset(k))}
              />
            </div>
            <div className="flex items-center gap-1.5">
              <Input
                type="date"
                aria-label="מתאריך"
                value={range.from}
                onChange={(e) => {
                  setPreset(null)
                  setRange((r) => ({ ...r, from: e.target.value }))
                }}
                className="w-40"
              />
              <span className="type-caption text-ink-tertiary">עד</span>
              <Input
                type="date"
                aria-label="עד תאריך"
                value={range.to}
                onChange={(e) => {
                  setPreset(null)
                  setRange((r) => ({ ...r, to: e.target.value }))
                }}
                className="w-40"
              />
            </div>
          </FilterBar>
        </PageHeader>

        {invalid && (
          <p className="flex items-center gap-2 rounded-lg border border-warning-border bg-warning-subtle px-3 py-2 type-caption text-warning-text">
            <AlertTriangle size={ICON.sm} strokeWidth={STROKE} />
            {invalid}
          </p>
        )}

        {error && <ErrorState error={error} onRetry={() => void refetch()} />}

        {isLoading && !invalid && (
          <Card>
            <CardBody>
              <SkeletonList rows={5} />
            </CardBody>
          </Card>
        )}

        {data && !invalid && (
          <>
            {/* היתרה היום — בלי קשר לטווח שנבחר */}
            <Card>
              <CardBody className="flex flex-wrap items-center gap-4">
                <span className="grid size-12 shrink-0 place-items-center rounded-2xl bg-primary-subtle text-primary-text">
                  <Wallet size={ICON.hero} strokeWidth={STROKE} />
                </span>
                <div className="min-w-0">
                  <p className="type-caption text-ink-tertiary">יתרת הארנק היום</p>
                  <p
                    dir="ltr"
                    className={cx(
                      'text-end tabular-nums text-3xl font-bold',
                      data.balance < 0 ? 'text-error-text' : 'text-ink',
                    )}
                  >
                    {fmtMoney(data.balance)}
                  </p>
                </div>
              </CardBody>
            </Card>

            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <StatCard
                icon={<Banknote size={ICON.xl} strokeWidth={STROKE} />}
                label="נכנס במזומן מאירועים"
                value={fmtMoney(data.cash_in)}
                tone="#22c55e"
              />
              <StatCard
                icon={<TrendingUp size={ICON.xl} strokeWidth={STROKE} />}
                label="הכנסות ידניות"
                value={fmtMoney(data.income)}
                tone="#3563f0"
              />
              <StatCard
                icon={<TrendingDown size={ICON.xl} strokeWidth={STROKE} />}
                label="הוצאות"
                value={fmtMoney(data.expenses)}
                tone="#ef4444"
              />
              <StatCard
                icon={<Wallet size={ICON.xl} strokeWidth={STROKE} />}
                label="יתרה בסוף הטווח"
                value={fmtMoney(data.closing)}
                tone="#a855f7"
                hint={`בתחילת הטווח: ${fmtMoney(data.opening)}`}
              />
            </div>

            <Card>
              <CardHeader title="תנועות" subtitle={`${data.entries.length} תנועות בטווח`} />
              <CardBody padded={false}>
                {data.entries.length === 0 ? (
                  <EmptyState
                    compact
                    art="table"
                    title="אין תנועות בטווח"
                    description="תשלום שנרשם על אירוע כ״מזומן״ נכנס לכאן אוטומטית"
                  />
                ) : (
                  <ul className="divide-y divide-line-subtle">
                    {data.entries.map((e) => (
                      <WalletRow
                        key={`${e.source}:${e.id}`}
                        entry={e}
                        canRemove={canManage && isManual(e)}
                        removing={remove.isPending && remove.variables === e.id}
                        onRemove={() => void removeEntry(e)}
                        onOpenEvent={e.event_id ? () => navigate(`/events/${e.event_id}`) : undefined}
                      />
                    ))}
                  </ul>
                )}
              </CardBody>
            </Card>
          </>
        )}

        <WalletEntryModal kind={entryKind} onClose={() => setEntryKind(null)} />
      </div>
    </RequirePermission>
  )
}

function WalletRow({
  entry: e,
  canRemove,
  removing,
  onRemove,
  onOpenEvent,
}: {
  entry: CashWalletEntry
  canRemove: boolean
  removing: boolean
  onRemove: () => void
  onOpenEvent?: () => void
}) {
  const title = entryTitle(e)
  return (
    <li className="flex items-start gap-3 px-4 py-3">
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-2">
          {onOpenEvent ? (
            <button type="button" className="truncate type-body font-semibold hover:underline" onClick={onOpenEvent}>
              {title}
            </button>
          ) : (
            <span className="truncate type-body font-semibold">{title}</span>
          )}
          <Badge tone={SOURCE_TONES[e.source]}>{SOURCE_LABELS[e.source]}</Badge>
        </div>
        <p className="mt-0.5 type-caption text-ink-tertiary">
          <span className="tabular-nums">{fmtDate(e.date)}</span>
          {e.source === 'payment' && e.customer_name && <span> · {e.customer_name}</span>}
          {e.created_by_name && <span> · נרשם ע״י {e.created_by_name}</span>}
        </p>
        {e.note && <p className="mt-0.5 whitespace-pre-line type-caption text-ink-secondary">{e.note}</p>}
      </div>
      <div className="shrink-0 text-end">
        <p
          dir="ltr"
          className={cx('tabular-nums type-body font-semibold', e.amount < 0 ? 'text-error-text' : 'text-success-text')}
        >
          {e.amount < 0 ? '−' : '+'}
          {fmtMoney(Math.abs(e.amount))}
        </p>
        <p dir="ltr" className="tabular-nums type-caption text-ink-tertiary">
          יתרה {fmtMoney(e.running)}
        </p>
      </div>
      {canRemove && (
        <IconButton label="מחיקה מהארנק" size="sm" loading={removing} onClick={onRemove}>
          <Trash2 size={ICON.sm} strokeWidth={STROKE} />
        </IconButton>
      )}
    </li>
  )
}

/** הוצאה או הכנסה ידנית: על מה, כמה, ומתי (ברירת מחדל — היום). */
function WalletEntryModal({ kind, onClose }: { kind: EntryKind | null; onClose: () => void }) {
  const toast = useToast()
  const add = useAddWalletEntry()
  const [current, setCurrent] = useState<EntryKind>('expense')
  const [label, setLabel] = useState('')
  const [raw, setRaw] = useState('')
  const [note, setNote] = useState('')
  const [date, setDate] = useState('')

  const open = kind != null
  const [openedFor, setOpenedFor] = useState<EntryKind | null>(null)
  if (kind !== openedFor) {
    setOpenedFor(kind)
    if (kind) {
      setCurrent(kind)
      setLabel('')
      setRaw('')
      setNote('')
      setDate(format(new Date(), 'yyyy-MM-dd'))
    }
  }

  const amount = parseAmount(raw)
  const valid = amount != null && !!label.trim() && !!date

  const save = () => {
    if (amount == null) return
    add.mutate(
      { kind: current, amount, label: label.trim(), note: note.trim() || null, date: date || null },
      {
        onSuccess: () => {
          toast.success(
            current === 'expense' ? `נרשמה הוצאה של ${fmtMoney(amount)}` : `נרשמה הכנסה של ${fmtMoney(amount)}`,
          )
          onClose()
        },
        onError: (e) => toast.error(errorMessage(e)),
      },
    )
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={current === 'expense' ? 'הוספת הוצאה' : 'הוספת הכנסה'}
      description={
        current === 'expense' ? 'הסכום יירד מיתרת הארנק' : 'הסכום ייכנס לארנק — למשל יתרת פתיחה או מזומן שלא מאירוע'
      }
      footer={
        <>
          <Button className="ms-auto" onClick={onClose}>
            ביטול
          </Button>
          <Button variant="primary" loading={add.isPending} disabled={!valid} onClick={save}>
            שמירה
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <Field label="סוג">
          <SegmentedControl<EntryKind>
            block
            items={[
              { key: 'expense', label: 'הוצאה' },
              { key: 'income', label: 'הכנסה' },
            ]}
            value={current}
            onChange={setCurrent}
          />
        </Field>
        <Field label="על מה" required>
          <Input
            autoFocus
            placeholder={current === 'expense' ? 'למשל: קניתי אוטו' : 'למשל: יתרת פתיחה'}
            value={label}
            onChange={(e) => setLabel(e.target.value)}
          />
        </Field>
        <Field label="סכום (₪)" required error={raw.trim() && amount == null ? 'סכום לא תקין' : undefined}>
          <Input inputMode="decimal" dir="ltr" placeholder="0" value={raw} onChange={(e) => setRaw(e.target.value)} />
        </Field>
        <Field label="תאריך" required>
          <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
        </Field>
        <Field label="הערות">
          <Textarea autoGrow rows={2} value={note} onChange={(e) => setNote(e.target.value)} />
        </Field>
      </div>
    </Modal>
  )
}
