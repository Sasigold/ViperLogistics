import { useState } from 'react'
import { format } from 'date-fns'
import { Banknote, HandCoins, ICON, Plus, STROKE, Trash2 } from '../../components/ui/icons'
import {
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  ErrorState,
  Field,
  IconButton,
  Input,
  Modal,
  ProgressBar,
  SegmentedControl,
  SkeletonList,
  Textarea,
  cx,
  fmtMoney,
  useConfirm,
  useToast,
} from '../../components/ui'
import { fmtDate } from '../../lib/dates'
import { errorMessage } from '../../lib/errors'
import type { EventPayment, EventPaymentLine, PaymentMethod } from '../../types/domain'
import {
  METHOD_LABELS,
  STATE_LABELS,
  STATE_TONES,
  lineLabel,
  overpayWarning,
  parseAmount,
  paymentState,
} from './eventPayments'
import {
  useAddEventCharge,
  useAddEventPayment,
  useEventPaymentSummary,
  useRemoveEventCharge,
  useRemoveEventPayment,
} from './eventPaymentQueries'

/**
 * תשלומים על אירוע (0205): כמה מגיע לוייפר, כמה התקבל, ומה נשאר.
 *
 * ‏`bare` — בלי מעטפת הכרטיס, לשימוש בתוך חלון (מסך התשלומים פותח את אותו
 * תוכן בדיוק, כדי שהיסטוריה ו"אוסף תשלום" יהיו אותו דבר בשני המקומות).
 *
 * אינו מצייר דבר כשהמודול סגור ללקוח של האירוע: השרת עונה `enabled: false`,
 * והדף אינו צריך לדעת למה.
 */
export function EventPaymentsCard({ eventId, bare }: { eventId: string; bare?: boolean }) {
  const { data, isLoading, error, refetch } = useEventPaymentSummary(eventId)
  const remove = useRemoveEventPayment()
  const removeCharge = useRemoveEventCharge()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const [collectOpen, setCollectOpen] = useState(false)
  const [chargeOpen, setChargeOpen] = useState(false)

  if (isLoading) {
    return bare ? (
      <SkeletonList rows={4} />
    ) : (
      <Card>
        <CardBody>
          <SkeletonList rows={4} />
        </CardBody>
      </Card>
    )
  }
  if (error) return <ErrorState error={error} onRetry={() => void refetch()} />
  if (!data || !data.enabled) return null

  const state = paymentState(data.due, data.paid)
  const canManage = data.can_manage

  const removePayment = async (p: EventPayment) => {
    const ok = await confirm(`למחוק את התשלום של ${fmtMoney(p.amount)} מ-${fmtDate(p.received_at)}?`, {
      title: 'מחיקת תשלום',
      confirmLabel: 'מחיקה',
    })
    if (!ok) return
    remove.mutate(p.id, {
      onSuccess: () => toast.success('התשלום נמחק'),
      onError: (e) => toast.error(errorMessage(e)),
    })
  }

  const removeChargeLine = async (l: EventPaymentLine) => {
    if (!l.charge_id) return
    const ok = await confirm(`למחוק את החיוב "${l.label}" של ${fmtMoney(l.amount)}?`, {
      title: 'מחיקת חיוב',
      confirmLabel: 'מחיקה',
    })
    if (!ok) return
    removeCharge.mutate(l.charge_id, {
      onSuccess: () => toast.success('החיוב נמחק'),
      onError: (e) => toast.error(errorMessage(e)),
    })
  }

  const collectButton = canManage && (
    <Button size="sm" variant="primary" onClick={() => setCollectOpen(true)}>
      <Plus size={ICON.sm} strokeWidth={STROKE} />
      אוסף תשלום
    </Button>
  )

  /* חיוב ידני (0206): "עלות ייצור 1,000" — נוסף למה שמגיע. אירוע שבוטל
     אינו חייב דבר, ולכן אין עליו חיוב חדש. */
  const chargeButton = canManage && !data.cancelled && (
    <Button size="sm" variant="ghost" onClick={() => setChargeOpen(true)}>
      <Plus size={ICON.sm} strokeWidth={STROKE} />
      הוספת חיוב
    </Button>
  )

  const body = (
    <div className="space-y-4">
      {dialog}

      {data.cancelled && (
        <p className="rounded-lg border border-warning-border bg-warning-subtle px-3 py-2 type-caption text-warning-text">
          האירוע בוטל — אין עליו סכום לגבייה. תשלום שכבר התקבל נשאר רשום.
        </p>
      )}

      {/* הפירוט: מה מגיע ועל מה */}
      <dl className="divide-y divide-line-subtle">
        {data.lines.map((l) => (
          <div key={l.key} className="flex items-start justify-between gap-3 py-2 first:pt-0">
            <dt className="min-w-0 shrink type-caption text-ink-tertiary">
              {lineLabel(l)}
              {l.pct != null && l.pct < 100 && l.gross != null && (
                <span className="ms-1.5 tabular-nums">
                  ({Number(l.pct)}% מתוך {fmtMoney(l.gross)})
                </span>
              )}
              {l.charge_id && <Badge className="ms-1.5">חיוב ידני</Badge>}
              {l.note && <span className="block whitespace-pre-line text-ink-secondary">{l.note}</span>}
            </dt>
            <dd className="flex shrink-0 items-center gap-1">
              <span dir="ltr" className="tabular-nums type-body font-medium">
                {fmtMoney(l.amount)}
              </span>
              {canManage && l.charge_id && (
                <IconButton
                  label="מחיקת חיוב"
                  size="sm"
                  loading={removeCharge.isPending && removeCharge.variables === l.charge_id}
                  onClick={() => void removeChargeLine(l)}
                >
                  <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                </IconButton>
              )}
            </dd>
          </div>
        ))}
        {data.lines.length === 0 && !data.cancelled && (
          <p className="py-2 type-caption text-ink-tertiary">
            עדיין אין על האירוע מחיר או הכנסות — אין סכום לגבייה.
          </p>
        )}
        {chargeButton && <div className="py-1.5">{chargeButton}</div>}
        <div className="flex items-baseline justify-between gap-3 pt-2">
          <dt className="type-body font-semibold">סך הכול מגיע</dt>
          <dd dir="ltr" className="tabular-nums type-title font-semibold text-primary">
            {fmtMoney(data.due)}
          </dd>
        </div>
      </dl>

      {/* שולם מול יתרה */}
      <div className="space-y-2 rounded-xl border border-line-subtle bg-subtle/50 p-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <Badge tone={STATE_TONES[state]}>{STATE_LABELS[state]}</Badge>
          {state !== 'paid' && state !== 'none' && (
            <span className="type-caption text-ink-tertiary">
              {state === 'credit' ? 'שולם יותר מהסכום שמגיע' : `נותרו ${fmtMoney(data.balance)} לגבייה`}
            </span>
          )}
        </div>
        {data.due > 0 && <ProgressBar value={Math.min(data.paid, data.due)} max={data.due} tone="success" />}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <p className="type-caption text-ink-tertiary">שולם</p>
            <p dir="ltr" className="text-end tabular-nums type-title font-semibold text-success-text">
              {fmtMoney(data.paid)}
            </p>
          </div>
          <div>
            <p className="type-caption text-ink-tertiary">{data.balance < 0 ? 'יתרת זכות' : 'יתרה'}</p>
            <p
              dir="ltr"
              className={cx(
                'text-end tabular-nums type-title font-semibold',
                data.balance > 0 ? 'text-error-text' : data.balance < 0 ? 'text-info-text' : 'text-success-text',
              )}
            >
              {fmtMoney(Math.abs(data.balance))}
            </p>
          </div>
        </div>
      </div>

      {/* היסטוריה */}
      <div>
        <div className="mb-2 flex items-center justify-between gap-2">
          <h3 className="type-body font-semibold">היסטוריית תשלומים</h3>
          {bare && collectButton}
        </div>
        {data.payments.length === 0 ? (
          <p className="type-caption text-ink-tertiary">עוד לא נרשמו תשלומים על האירוע.</p>
        ) : (
          <ul className="divide-y divide-line-subtle rounded-xl border border-line-subtle">
            {data.payments.map((p) => (
              <li key={p.id} className="flex items-start gap-3 px-3 py-2">
                <Banknote size={ICON.sm} strokeWidth={STROKE} className="mt-1 shrink-0 text-ink-tertiary" />
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <span dir="ltr" className="tabular-nums type-body font-semibold">
                      {fmtMoney(p.amount)}
                    </span>
                    {p.method && <Badge tone={p.method === 'cash' ? 'success' : 'neutral'}>{METHOD_LABELS[p.method]}</Badge>}
                    <span className="tabular-nums type-caption text-ink-tertiary">{fmtDate(p.received_at)}</span>
                  </div>
                  {p.note && <p className="mt-0.5 whitespace-pre-line type-caption text-ink-secondary">{p.note}</p>}
                  {p.created_by_name && (
                    <p className="mt-0.5 type-caption text-ink-tertiary">נרשם ע״י {p.created_by_name}</p>
                  )}
                </div>
                {canManage && (
                  <IconButton
                    label="מחיקת תשלום"
                    size="sm"
                    loading={remove.isPending && remove.variables === p.id}
                    onClick={() => void removePayment(p)}
                  >
                    <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                  </IconButton>
                )}
              </li>
            ))}
          </ul>
        )}
      </div>

      <CollectPaymentModal
        open={collectOpen}
        onClose={() => setCollectOpen(false)}
        eventId={eventId}
        balance={data.balance}
      />
      <AddChargeModal open={chargeOpen} onClose={() => setChargeOpen(false)} eventId={eventId} />
    </div>
  )

  if (bare) return body

  return (
    <Card>
      <CardHeader
        title="תשלומים"
        subtitle="כמה מגיע לוייפר על האירוע, וכמה כבר התקבל"
        icon={<HandCoins size={ICON.md} strokeWidth={STROKE} />}
        actions={collectButton || undefined}
      />
      <CardBody>{body}</CardBody>
    </Card>
  )
}

/** חיוב ידני על האירוע (0206): על מה, כמה, והערה. */
function AddChargeModal({ open, onClose, eventId }: { open: boolean; onClose: () => void; eventId: string }) {
  const toast = useToast()
  const add = useAddEventCharge()
  const [label, setLabel] = useState('')
  const [raw, setRaw] = useState('')
  const [note, setNote] = useState('')

  const [openedFor, setOpenedFor] = useState(false)
  if (open !== openedFor) {
    setOpenedFor(open)
    if (open) {
      setLabel('')
      setRaw('')
      setNote('')
    }
  }

  const amount = parseAmount(raw)
  const valid = amount != null && !!label.trim()

  const save = () => {
    if (amount == null) return
    add.mutate(
      { eventId, label: label.trim(), amount, note: note.trim() || null },
      {
        onSuccess: () => {
          toast.success(`נוסף חיוב של ${fmtMoney(amount)}`)
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
      title="הוספת חיוב"
      description="סכום נוסף שמגיע על האירוע — נכנס ל״סך הכול מגיע״ וליתרה"
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
        <Field label="על מה" required>
          <Input autoFocus placeholder="למשל: עלות ייצור" value={label} onChange={(e) => setLabel(e.target.value)} />
        </Field>
        <Field label="סכום (₪)" required error={raw.trim() && amount == null ? 'סכום לא תקין' : undefined}>
          <Input inputMode="decimal" dir="ltr" placeholder="0" value={raw} onChange={(e) => setRaw(e.target.value)} />
        </Field>
        <Field label="הערות">
          <Textarea autoGrow rows={2} value={note} onChange={(e) => setNote(e.target.value)} />
        </Field>
      </div>
    </Modal>
  )
}

type AmountMode = 'full' | 'partial'

/**
 * "אוסף תשלום": כל הסכום או חלק ממנו, מזומן או אחר עם הערה, ותאריך — היום,
 * אלא אם נבחר אחר. השרת רושם את היתרה החדשה; החלון רק אומר אותה.
 */
export function CollectPaymentModal({
  open,
  onClose,
  eventId,
  balance,
}: {
  open: boolean
  onClose: () => void
  eventId: string
  balance: number
}) {
  const toast = useToast()
  const add = useAddEventPayment()
  const hasBalance = balance > 0
  const [mode, setMode] = useState<AmountMode>('full')
  const [raw, setRaw] = useState('')
  const [method, setMethod] = useState<PaymentMethod>('cash')
  const [note, setNote] = useState('')
  const [date, setDate] = useState('')

  // הטופס מאותחל בכל פתיחה — אותו דפוס של חלון התקבולים
  const [openedFor, setOpenedFor] = useState(false)
  if (open !== openedFor) {
    setOpenedFor(open)
    if (open) {
      setMode(hasBalance ? 'full' : 'partial')
      setRaw('')
      setMethod('cash')
      setNote('')
      setDate(format(new Date(), 'yyyy-MM-dd'))
    }
  }

  const amount = mode === 'full' ? (hasBalance ? Math.round(balance * 100) / 100 : null) : parseAmount(raw)
  const warning = overpayWarning(amount, balance)
  const valid = amount != null && !!date

  const save = () => {
    if (amount == null) return
    add.mutate(
      { eventId, amount, method, note: note.trim() || null, receivedAt: date || null },
      {
        onSuccess: () => {
          const left = Math.round((balance - amount) * 100) / 100
          toast.success(
            left > 0
              ? `נרשם תשלום של ${fmtMoney(amount)} · נותרו ${fmtMoney(left)}`
              : `נרשם תשלום של ${fmtMoney(amount)} · האירוע שולם במלואו`,
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
      title="אוסף תשלום"
      description={hasBalance ? `יתרה לתשלום: ${fmtMoney(balance)}` : 'לאירוע הזה אין יתרה פתוחה'}
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
        <Field label="סכום">
          <SegmentedControl<AmountMode>
            block
            items={[
              { key: 'full', label: hasBalance ? `כל הסכום · ${fmtMoney(balance)}` : 'כל הסכום' },
              { key: 'partial', label: 'חלק מהסכום' },
            ]}
            value={mode}
            onChange={(m) => {
              if (m === 'full' && !hasBalance) return
              setMode(m)
            }}
          />
        </Field>

        {mode === 'partial' && (
          <Field label="כמה התקבל (₪)" required error={raw.trim() && amount == null ? 'סכום לא תקין' : undefined}>
            <Input
              inputMode="decimal"
              dir="ltr"
              autoFocus
              placeholder="0"
              value={raw}
              onChange={(e) => setRaw(e.target.value)}
            />
          </Field>
        )}

        {warning && (
          <p className="rounded-lg border border-warning-border bg-warning-subtle px-3 py-2 type-caption text-warning-text">
            {warning}
          </p>
        )}

        <Field label="אמצעי תשלום">
          <SegmentedControl<PaymentMethod>
            block
            items={[
              { key: 'cash', label: METHOD_LABELS.cash },
              { key: 'other', label: METHOD_LABELS.other },
            ]}
            value={method}
            onChange={setMethod}
          />
        </Field>

        <Field
          label="הערות"
          hint={
            method === 'other'
              ? 'למשל: העברה בנקאית, צ׳ק, ביט — ומספר אסמכתא'
              : 'תשלום במזומן נכנס גם לארנק המזומנים'
          }
        >
          <Textarea autoGrow rows={2} value={note} onChange={(e) => setNote(e.target.value)} />
        </Field>

        <Field label="תאריך קבלה" required>
          <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
        </Field>
      </div>
    </Modal>
  )
}
