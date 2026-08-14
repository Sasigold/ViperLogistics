import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { addMonths, endOfMonth, format, startOfMonth, subMonths } from 'date-fns'
import {
  Banknote,
  ChevronLeft,
  ChevronRight,
  ICON,
  Plus,
  Receipt as ReceiptIcon,
  STROKE,
  Trash2,
  XCircle,
} from '../../components/ui/icons'
import {
  Button,
  Card,
  CardBody,
  DataTable,
  EmptyState,
  Field,
  IconButton,
  Input,
  Modal,
  PageHeader,
  Select,
  StatCard,
  Textarea,
  useConfirm,
  useToast,
  fmtMoney,
} from '../../components/ui'
import type { Column } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { useCustomers } from '../../lib/queries'
import { fmtDate, fmtMonth } from '../../lib/dates'
import { errorMessage } from '../../lib/errors'
import type { Receipt } from '../../types/domain'

/**
 * רישום תקבולים (0068): מה שהלקוחות העבירו בפועל, מול מה שהם חייבים.
 *
 * פס הסיכום אינו מחושב כאן אלא נשאל מ-dashboard_sections — אותו מימוש שמזין
 * את כרטיסי שולם/לא שולם בדשבורד, כדי ששני המסכים לעולם לא יסתרו זה את זה.
 */
export default function ReceiptsPage() {
  const { has } = useAuth()
  const canManage = has(PERM.FINANCE_RECEIPTS_MANAGE)
  const qc = useQueryClient()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()

  const [monthDate, setMonthDate] = useState(() => startOfMonth(new Date()))
  const from = format(startOfMonth(monthDate), 'yyyy-MM-dd')
  const to = format(endOfMonth(monthDate), 'yyyy-MM-dd')

  const { data: customers = [] } = useCustomers()
  const customerOf = useMemo(() => new Map(customers.map((c) => [c.id, c])), [customers])

  const { data: receipts = [], isLoading } = useQuery({
    queryKey: ['receipts', from, to],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('receipts')
        .select('*')
        .gte('received_at', from)
        .lte('received_at', to)
        .is('deleted_at', null)
        .order('received_at', { ascending: false })
      if (error) throw error
      return data as Receipt[]
    },
  })

  interface Receivables {
    owed: number
    paid: number
    unpaid: number
  }
  const { data: summary } = useQuery({
    queryKey: ['receipts', 'summary', from, to],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('dashboard_sections', {
        p_sections: ['finance.receivables'],
        p_from: from,
        p_to: to,
        p_opts: {},
      })
      if (error) throw error
      return ((data as Record<string, unknown>)?.['finance.receivables'] ?? null) as Receivables | null
    },
  })

  const invalidate = () => {
    void qc.invalidateQueries({ queryKey: ['receipts'] })
    void qc.invalidateQueries({ queryKey: ['dashboard'] })
  }

  const [modal, setModal] = useState<{ open: boolean; editing: Receipt | null }>({ open: false, editing: null })

  const remove = async (r: Receipt) => {
    const name = customerOf.get(r.customer_id)?.name ?? ''
    if (
      !(await confirm(`למחוק את התקבול של ${fmtMoney(Number(r.amount))} מ-${name}?`, {
        title: 'מחיקת תקבול',
        confirmLabel: 'מחיקה',
      }))
    )
      return
    // מחיקה רכה — עמודת deleted_at, בלי rpc: פוליסת ה-update היא השער
    const { error } = await supabase
      .from('receipts')
      .update({ deleted_at: new Date().toISOString() })
      .eq('id', r.id)
    if (error) return toast.error(errorMessage(error))
    toast.success('התקבול נמחק')
    invalidate()
  }

  const columns: Column<Receipt>[] = [
    {
      key: 'received_at',
      header: 'תאריך',
      sticky: true,
      render: (r) => <span className="tabular">{fmtDate(r.received_at)}</span>,
      sortValue: (r) => r.received_at,
    },
    {
      key: 'customer',
      header: 'לקוח',
      render: (r) => {
        const c = customerOf.get(r.customer_id)
        return (
          <span className="flex items-center gap-2">
            <span className="size-2 shrink-0 rounded-full" style={{ background: c?.color ?? '#8a93a5' }} aria-hidden />
            <span className="truncate">{c?.name ?? '—'}</span>
          </span>
        )
      },
      sortValue: (r) => customerOf.get(r.customer_id)?.name ?? '',
    },
    {
      key: 'amount',
      header: 'סכום',
      align: 'end',
      render: (r) => (
        <span className={`tabular ${Number(r.amount) < 0 ? 'text-error-text' : ''}`}>{fmtMoney(Number(r.amount))}</span>
      ),
      sortValue: (r) => Number(r.amount),
    },
    { key: 'note', header: 'הערה', render: (r) => <span className="truncate">{r.note ?? ''}</span> },
    ...(canManage
      ? [
          {
            key: 'actions',
            header: '',
            align: 'end' as const,
            render: (r: Receipt) => (
              <IconButton label="מחיקת התקבול" size="sm" className="hover:text-error" onClick={() => void remove(r)}>
                <Trash2 size={ICON.sm} strokeWidth={STROKE} />
              </IconButton>
            ),
          },
        ]
      : []),
  ]

  return (
    <RequirePermission perm={PERM.FINANCE_RECEIPTS_VIEW}>
      <div className="space-y-4">
        {dialog}
        <PageHeader title="רישום תקבולים" subtitle="מה שהלקוחות העבירו בפועל, מול החוב של התקופה">
          {canManage && (
            <Button variant="primary" onClick={() => setModal({ open: true, editing: null })}>
              <Plus size={ICON.sm} strokeWidth={STROKE} />
              תקבול חדש
            </Button>
          )}
        </PageHeader>

        {/* בורר החודש — אותה תבנית של דוח הנוכחות: ימין = אחורה ב-RTL */}
        <Card className="flex flex-wrap items-center justify-between gap-3 p-3">
          <div className="flex items-center gap-1">
            <IconButton label="חודש קודם" variant="ghost" onClick={() => setMonthDate((d) => subMonths(d, 1))}>
              <ChevronRight size={ICON.lg} strokeWidth={STROKE} />
            </IconButton>
            <div className="min-w-36 text-center">
              <p className="type-title">{fmtMonth(monthDate)}</p>
              <p className="type-caption text-ink-tertiary tabular" dir="ltr">
                {from} — {to}
              </p>
            </div>
            <IconButton label="חודש הבא" variant="ghost" onClick={() => setMonthDate((d) => addMonths(d, 1))}>
              <ChevronLeft size={ICON.lg} strokeWidth={STROKE} />
            </IconButton>
          </div>
        </Card>

        {summary && (
          <div className="grid gap-3 sm:grid-cols-3">
            <StatCard
              icon={<Banknote size={ICON.xl} strokeWidth={STROKE} />}
              label="סה״כ תשלום לוויפר"
              value={fmtMoney(Number(summary.owed))}
              tone="#a855f7"
            />
            <StatCard
              icon={<ReceiptIcon size={ICON.xl} strokeWidth={STROKE} />}
              label="שולם"
              value={fmtMoney(Number(summary.paid))}
              tone="#22c55e"
            />
            <StatCard
              icon={<XCircle size={ICON.xl} strokeWidth={STROKE} />}
              label="לא שולם"
              value={fmtMoney(Number(summary.unpaid))}
              tone="#ef4444"
            />
          </div>
        )}

        <Card>
          <CardBody padded={false}>
            <DataTable
              rows={receipts}
              columns={columns}
              getRowId={(r) => r.id}
              loading={isLoading}
              onRowClick={canManage ? (r) => setModal({ open: true, editing: r }) : undefined}
              empty={
                <EmptyState
                  compact
                  art="table"
                  title="אין תקבולים בחודש הזה"
                  description={canManage ? 'כשהלקוח מעביר תשלום — נרשם אותו כאן' : undefined}
                />
              }
            />
          </CardBody>
        </Card>

        <ReceiptModal
          open={modal.open}
          editing={modal.editing}
          onClose={() => setModal({ open: false, editing: null })}
          onSaved={invalidate}
        />
      </div>
    </RequirePermission>
  )
}

/* ===== add / edit ========================================================= */

function ReceiptModal({
  open,
  editing,
  onClose,
  onSaved,
}: {
  open: boolean
  editing: Receipt | null
  onClose: () => void
  onSaved: () => void
}) {
  const toast = useToast()
  const { data: customers = [] } = useCustomers()
  const [form, setForm] = useState({ customer_id: '', amount: '', received_at: '', note: '' })

  // הטופס מאותחל בפתיחה — גם לעריכה וגם לרישום חדש
  const [openedFor, setOpenedFor] = useState<string | null>(null)
  const openKey = open ? (editing?.id ?? 'new') : null
  if (openKey !== openedFor) {
    setOpenedFor(openKey)
    if (openKey) {
      setForm(
        editing
          ? {
              customer_id: editing.customer_id,
              amount: String(editing.amount),
              received_at: editing.received_at,
              note: editing.note ?? '',
            }
          : { customer_id: '', amount: '', received_at: format(new Date(), 'yyyy-MM-dd'), note: '' },
      )
    }
  }

  const amount = Number(form.amount)
  const valid = form.customer_id && form.received_at && form.amount.trim() !== '' && Number.isFinite(amount) && amount !== 0

  const save = useMutation({
    mutationFn: async () => {
      const row = {
        customer_id: form.customer_id,
        amount,
        received_at: form.received_at,
        note: form.note.trim() || null,
      }
      if (editing) {
        const { error } = await supabase.from('receipts').update(row).eq('id', editing.id)
        if (error) throw error
      } else {
        const { error } = await supabase.from('receipts').insert(row)
        if (error) throw error
      }
    },
    onSuccess: () => {
      toast.success(editing ? 'התקבול עודכן' : 'התקבול נרשם')
      onSaved()
      onClose()
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={editing ? 'עריכת תקבול' : 'תקבול חדש'}
      footer={
        <>
          <Button className="ms-auto" onClick={onClose}>
            ביטול
          </Button>
          <Button variant="primary" loading={save.isPending} disabled={!valid} onClick={() => save.mutate()}>
            {editing ? 'שמירה' : 'רישום'}
          </Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="לקוח" required>
          <Select value={form.customer_id} onChange={(e) => setForm((f) => ({ ...f, customer_id: e.target.value }))}>
            <option value="">בחירת לקוח...</option>
            {customers.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="תאריך קבלה" required>
          <Input
            type="date"
            value={form.received_at}
            onChange={(e) => setForm((f) => ({ ...f, received_at: e.target.value }))}
          />
        </Field>
        <Field label="סכום (₪)" required hint="סכום שלילי = זיכוי או החזר ללקוח">
          <Input
            type="number"
            step="any"
            dir="ltr"
            value={form.amount}
            onChange={(e) => setForm((f) => ({ ...f, amount: e.target.value }))}
          />
        </Field>
        <Field label="הערה" className="sm:col-span-2">
          <Textarea autoGrow rows={2} value={form.note} onChange={(e) => setForm((f) => ({ ...f, note: e.target.value }))} />
        </Field>
      </div>
    </Modal>
  )
}
