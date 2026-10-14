import { useEffect, useState } from 'react'
import { AlertTriangle, Check, Download, ICON, Plus, RefreshCw, STROKE, Trash2 } from '../../components/ui/icons'
import {
  Badge,
  Button,
  Drawer,
  Field,
  IconButton,
  Input,
  Select,
  Spinner,
  Textarea,
  useConfirm,
  useToast,
} from '../../components/ui'
import { errorMessage } from '../../lib/errors'
import type { Invoice, InvoiceCategory, InvoiceCompany, InvoiceDocType } from '../../types/domain'
import {
  CATEGORY_LABELS,
  DOC_TYPE_LABELS,
  FLAG_LABELS,
  SOURCE_LABELS,
  invoiceFlags,
  monthLabel,
  shiftMonth,
} from './invoices'
import { loadInvoicePdf, readInvoices, useInvalidateInvoices, useRemoveInvoice, useSaveInvoice } from './invoiceQueries'

interface LineDraft {
  description: string
  quantity: string
  unit_price: string
  total: string
}

interface Draft {
  doc_type: InvoiceDocType
  vendor_name: string
  vendor_tax_id: string
  invoice_number: string
  issue_date: string
  period: string
  currency: string
  amount_before_vat: string
  vat_amount: string
  total_amount: string
  category: InvoiceCategory
  description: string
  company_id: string
  notes: string
  lines: LineDraft[]
}

const str = (n: number | null) => (n === null || n === undefined ? '' : String(n))
const num = (s: string) => {
  const t = s.replace(/[,\s₪]/g, '')
  return t === '' || !Number.isFinite(Number(t)) ? null : Number(t)
}

function toDraft(i: Invoice): Draft {
  return {
    doc_type: i.doc_type,
    vendor_name: i.vendor_name ?? '',
    vendor_tax_id: i.vendor_tax_id ?? '',
    invoice_number: i.invoice_number ?? '',
    issue_date: i.issue_date ?? '',
    period: i.period,
    currency: i.currency,
    amount_before_vat: str(i.amount_before_vat),
    vat_amount: str(i.vat_amount),
    total_amount: str(i.total_amount),
    category: i.category,
    description: i.description ?? '',
    company_id: i.company_id ?? '',
    notes: i.notes ?? '',
    lines: i.lines.map((l) => ({
      description: l.description,
      quantity: str(l.quantity),
      unit_price: str(l.unit_price),
      total: str(l.total),
    })),
  }
}

/** כתובת blob לתצוגה; משוחררת כשהחשבונית מתחלפת. */
function usePdfUrl(id: string) {
  const [state, setState] = useState<{ id: string; url: string | null; error: unknown }>({ id: '', url: null, error: null })
  useEffect(() => {
    let url: string | null = null
    let alive = true
    loadInvoicePdf({ id })
      .then((b) => {
        if (!alive) return
        url = URL.createObjectURL(b)
        setState({ id, url, error: null })
      })
      .catch((error: unknown) => alive && setState({ id, url: null, error }))
    return () => {
      alive = false
      if (url) URL.revokeObjectURL(url)
    }
  }, [id])
  return state.id === id ? state : { id, url: null, error: null }
}

export function InvoiceDrawer({
  invoice,
  companies,
  onClose,
}: {
  invoice: Invoice
  companies: InvoiceCompany[]
  onClose: () => void
}) {
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const save = useSaveInvoice()
  const remove = useRemoveInvoice()
  const invalidate = useInvalidateInvoices()
  const [draft, setDraft] = useState(() => toDraft(invoice))
  const [rereading, setRereading] = useState(false)
  const pdf = usePdfUrl(invoice.id)

  const set = <K extends keyof Draft>(k: K, v: Draft[K]) => setDraft((d) => ({ ...d, [k]: v }))
  const setLine = (i: number, k: keyof LineDraft, v: string) =>
    setDraft((d) => ({ ...d, lines: d.lines.map((l, j) => (j === i ? { ...l, [k]: v } : l)) }))

  const flags = invoiceFlags(invoice, companies.length > 0)
  const months = Array.from({ length: 7 }, (_, k) => shiftMonth(invoice.period, k - 3))

  const submit = async () => {
    try {
      await save.mutateAsync({
        id: invoice.id,
        fields: {
          doc_type: draft.doc_type,
          vendor_name: draft.vendor_name,
          vendor_tax_id: draft.vendor_tax_id,
          invoice_number: draft.invoice_number,
          issue_date: draft.issue_date || null,
          period: draft.period,
          currency: draft.currency || 'ILS',
          amount_before_vat: num(draft.amount_before_vat),
          vat_amount: num(draft.vat_amount),
          total_amount: num(draft.total_amount),
          category: draft.category,
          description: draft.description,
          company_id: draft.company_id || null,
          notes: draft.notes,
          lines: draft.lines.map((l) => ({
            description: l.description,
            quantity: num(l.quantity),
            unit_price: num(l.unit_price),
            total: num(l.total),
          })),
          reviewed: true,
        },
      })
      toast.success('החשבונית נשמרה ואושרה')
      onClose()
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  const reread = async () => {
    if (invoice.reviewed_at && !(await confirm('החשבונית כבר אושרה. קריאה חוזרת תחליף את הפרטים שהוקלדו. להמשיך?', { tone: 'primary', confirmLabel: 'קריאה מחדש' }))) {
      return
    }
    setRereading(true)
    try {
      if (invoice.reviewed_at) await save.mutateAsync({ id: invoice.id, fields: { reviewed: false } })
      const r = await readInvoices([invoice.id])
      if (!r.configured) toast.error('הקריאה האוטומטית עוד לא מוגדרת בשרת')
      else if (r.failed.length) toast.error(r.failed[0].error)
      else toast.success('החשבונית נקראה מחדש')
      invalidate()
    } catch (e) {
      toast.error(errorMessage(e))
    } finally {
      setRereading(false)
    }
  }

  const del = async () => {
    if (!(await confirm('להסיר את החשבונית? היא תצא מהתיקייה ומהסיכום.', { confirmLabel: 'הסרה' }))) return
    try {
      await remove.mutateAsync(invoice.id)
      toast.success('החשבונית הוסרה')
      onClose()
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  const download = () => {
    if (!pdf.url) return
    const a = document.createElement('a')
    a.href = pdf.url
    a.download = invoice.file_name
    a.click()
  }

  return (
    <Drawer
      open
      onClose={onClose}
      width="max-w-5xl"
      title={invoice.vendor_name || invoice.file_name}
      description={
        <span className="flex flex-wrap items-center gap-2">
          <span>{SOURCE_LABELS[invoice.source]}</span>
          {invoice.gmail_from && <span className="text-ink-tertiary">· {invoice.gmail_from}</span>}
          {invoice.reviewed_at && (
            <Badge tone="success" dot>
              אושרה
            </Badge>
          )}
        </span>
      }
      footer={
        <div className="flex w-full flex-wrap items-center gap-2">
          <Button variant="primary" onClick={() => void submit()} disabled={save.isPending}>
            <Check size={ICON.sm} strokeWidth={STROKE} />
            שמירה ואישור
          </Button>
          <Button onClick={() => void reread()} disabled={rereading}>
            {rereading ? <Spinner size={ICON.sm} /> : <RefreshCw size={ICON.sm} strokeWidth={STROKE} />}
            קריאה מחדש
          </Button>
          <Button onClick={download} disabled={!pdf.url}>
            <Download size={ICON.sm} strokeWidth={STROKE} />
            הורדה
          </Button>
          <Button variant="danger" className="ms-auto" onClick={() => void del()}>
            <Trash2 size={ICON.sm} strokeWidth={STROKE} />
            הסרה
          </Button>
        </div>
      }
    >
      {dialog}
      <div className="grid gap-4 lg:grid-cols-2">
        <div className="min-h-[24rem] overflow-hidden rounded-xl border border-line bg-subtle lg:sticky lg:top-0 lg:h-[calc(100vh-14rem)]">
          {pdf.url ? (
            <iframe src={pdf.url} title="החשבונית" className="h-full min-h-[24rem] w-full" />
          ) : pdf.error ? (
            <p className="p-4 type-body text-error-text">{errorMessage(pdf.error)}</p>
          ) : (
            <div className="flex h-full items-center justify-center p-8">
              <Spinner />
            </div>
          )}
        </div>

        <div className="space-y-4">
          {flags.length > 0 && (
            <div className="flex flex-wrap gap-1.5">
              {flags.map((f) => (
                <Badge key={f} tone={f === 'unreviewed' ? 'info' : 'warning'}>
                  {FLAG_LABELS[f]}
                </Badge>
              ))}
            </div>
          )}
          {invoice.read_error && !invoice.reviewed_at && (
            <p className="flex items-center gap-2 type-caption text-error-text">
              <AlertTriangle size={ICON.sm} strokeWidth={STROKE} />
              {invoice.read_error}
            </p>
          )}

          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="ספק">
              <Input value={draft.vendor_name} onChange={(e) => set('vendor_name', e.target.value)} />
            </Field>
            <Field label="ח.פ. / ע.מ. ספק">
              <Input value={draft.vendor_tax_id} inputMode="numeric" onChange={(e) => set('vendor_tax_id', e.target.value)} />
            </Field>
            <Field label="מספר חשבונית">
              <Input value={draft.invoice_number} onChange={(e) => set('invoice_number', e.target.value)} />
            </Field>
            <Field label="סוג מסמך">
              <Select value={draft.doc_type} onChange={(e) => set('doc_type', e.target.value as InvoiceDocType)}>
                {Object.entries(DOC_TYPE_LABELS).map(([k, v]) => (
                  <option key={k} value={k}>
                    {v}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="תאריך החשבונית">
              <Input type="date" value={draft.issue_date} onChange={(e) => set('issue_date', e.target.value)} />
            </Field>
            <Field label="תיקייה (חודש לרואה החשבון)" hint="ברירת המחדל — חודש התאריך">
              <Select value={draft.period} onChange={(e) => set('period', e.target.value)}>
                {months.map((m) => (
                  <option key={m} value={m}>
                    {monthLabel(m)}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="סוג הוצאה">
              <Select value={draft.category} onChange={(e) => set('category', e.target.value as InvoiceCategory)}>
                {Object.entries(CATEGORY_LABELS).map(([k, v]) => (
                  <option key={k} value={k}>
                    {v}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="עבור חברה" hint={invoice.recipient_name ? `בחשבונית: ${invoice.recipient_name}` : undefined}>
              <Select value={draft.company_id} onChange={(e) => set('company_id', e.target.value)}>
                <option value="">—</option>
                {companies.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </Select>
            </Field>
          </div>

          <Field label="על מה">
            <Input value={draft.description} onChange={(e) => set('description', e.target.value)} />
          </Field>

          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <Field label="לפני מע״מ">
              <Input value={draft.amount_before_vat} inputMode="decimal" onChange={(e) => set('amount_before_vat', e.target.value)} />
            </Field>
            <Field label="מע״מ">
              <Input value={draft.vat_amount} inputMode="decimal" onChange={(e) => set('vat_amount', e.target.value)} />
            </Field>
            <Field label="סה״כ">
              <Input value={draft.total_amount} inputMode="decimal" onChange={(e) => set('total_amount', e.target.value)} />
            </Field>
            <Field label="מטבע">
              <Input value={draft.currency} maxLength={3} onChange={(e) => set('currency', e.target.value.toUpperCase())} />
            </Field>
          </div>
          {draft.doc_type === 'credit' && (
            <p className="type-caption text-ink-tertiary">בחשבונית זיכוי הסכומים שליליים — כך הם יורדים מהסיכום.</p>
          )}

          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <h3 className="type-body font-semibold">שורות</h3>
              <Button
                size="sm"
                onClick={() => set('lines', [...draft.lines, { description: '', quantity: '', unit_price: '', total: '' }])}
              >
                <Plus size={ICON.sm} strokeWidth={STROKE} />
                שורה
              </Button>
            </div>
            {draft.lines.length === 0 && <p className="type-caption text-ink-tertiary">אין שורות</p>}
            {draft.lines.map((l, i) => (
              <div key={i} className="grid grid-cols-[1fr_4.5rem_5.5rem_5.5rem_auto] items-center gap-1.5">
                <Input inputSize="sm" placeholder="תיאור" value={l.description} onChange={(e) => setLine(i, 'description', e.target.value)} />
                <Input inputSize="sm" placeholder="כמות" inputMode="decimal" value={l.quantity} onChange={(e) => setLine(i, 'quantity', e.target.value)} />
                <Input inputSize="sm" placeholder="מחיר" inputMode="decimal" value={l.unit_price} onChange={(e) => setLine(i, 'unit_price', e.target.value)} />
                <Input inputSize="sm" placeholder="סה״כ" inputMode="decimal" value={l.total} onChange={(e) => setLine(i, 'total', e.target.value)} />
                <IconButton label="הסרת שורה" size="sm" onClick={() => set('lines', draft.lines.filter((_, j) => j !== i))}>
                  <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                </IconButton>
              </div>
            ))}
          </div>

          <Field label="הערות">
            <Textarea rows={2} value={draft.notes} onChange={(e) => set('notes', e.target.value)} />
          </Field>
        </div>
      </div>
    </Drawer>
  )
}
