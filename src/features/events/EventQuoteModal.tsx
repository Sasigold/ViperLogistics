import { useEffect, useMemo, useState } from 'react'
import {
  Badge,
  Button,
  Checkbox,
  EmptyState,
  Field,
  Modal,
  Textarea,
  fmtMoney,
  useToast,
} from '../../components/ui'
import { Download, FileText, ICON, Phone, STROKE } from '../../components/ui/icons'
import { fmtDateTime } from '../../lib/dates'
import { errorMessage } from '../../lib/errors'
import { downloadBlob } from '../reports/download'
import { useCompanyDetails, fetchCompanyLogo } from '../settings/companyQueries'
import type { EventPriceAddon, EventQuote, EventRow, FormField, WorkBoardRow } from '../../types/domain'
import {
  PAYMENT_TERMS_LABEL,
  buildQuoteLines,
  findPaymentTermsField,
  quoteFileName,
  quoteFixedNote,
  quoteTotals,
  quoteWhatsAppText,
  toWhatsAppNumber,
} from './quote'
import { formatCustomValue } from './CustomFieldInput'
import {
  downloadQuote,
  useEventQuotes,
  useIssueQuote,
  useMarkQuoteSent,
  useQuoteSignedUrl,
} from './quoteQueries'

/**
 * הפקת הצעת מחיר ללקוח הקצה ושליחתה (0170).
 *
 * **המסך הוא שני צעדים, וזו אינה החלטה עיצובית.** ‏`navigator.share` דורש
 * מחווה של המשתמש, וספארי באייפון מאבד אותה אחרי כל `await` — והפקת המסמך
 * היא טעינת פונט, ציור והעלאה. לכן "הפקה" ו"שיתוף" הן שתי לחיצות: השנייה
 * יושבת על קובץ שכבר מוכן בזיכרון.
 *
 * **ומה שוואטסאפ אינו מאפשר קבע את השאר.** ‏`wa.me/<מספר>` מגיע ישר למספר
 * אך אינו יכול לצרף קובץ; ‏`navigator.share` מצרף קובץ אמיתי אך אינו יכול
 * לבחור נמען. הבחירה כאן היא הקובץ, ובדפדפן שאינו תומך יש נסיגה: הורדה
 * **וגם** פתיחת שיחה עם המספר של איש הקשר, כדי שהקובץ שירד יצורף ביד.
 */
export function EventQuoteModal({
  open,
  onClose,
  event,
  customerName,
  contact,
  tasks,
  addons,
  customFields,
}: {
  open: boolean
  onClose: () => void
  event: EventRow
  customerName: string
  contact: { contact_name: string | null; contact_phone: string | null } | null
  tasks: WorkBoardRow[]
  addons: EventPriceAddon[]
  /** השדות המותאמים של הלקוח — מהם נלקחים תנאי התשלום (0171) */
  customFields: FormField[]
}) {
  const toast = useToast()
  const { company } = useCompanyDetails()
  const { data: history = [] } = useEventQuotes(event.id, open)
  const issue = useIssueQuote(event.id)
  const markSent = useMarkQuoteSent(event.id)

  /**
   * תנאי התשלום מגיעים מהשדה המותאם של הלקוח ולא משדה מערכת (0171).
   * ‏`formatCustomValue` היא אותה פונקציה שמציירת את הערך בדף האירוע, ולכן
   * מה שמודפס על המסמך הוא בדיוק מה שרואים על המסך.
   */
  const termsField = useMemo(() => findPaymentTermsField(customFields), [customFields])
  const paymentTerms = termsField
    ? formatCustomValue(termsField, event.custom_fields?.[termsField.field_key]) || null
    : null

  const allLines = useMemo(() => buildQuoteLines(tasks, addons), [tasks, addons])
  const [excluded, setExcluded] = useState<Set<string>>(new Set())
  const [notes, setNotes] = useState('')
  const [issued, setIssued] = useState<{ quote: EventQuote; file: File } | null>(null)

  // פתיחה מחדש מתחילה מדף חלק: הצעה שהופקה בפעם הקודמת אינה מה שעומד
  // עכשיו על המסך, ושיתוף שלה בטעות הוא בדיוק מה שאין לו דרך חזרה.
  useEffect(() => {
    if (!open) return
    setExcluded(new Set())
    setNotes('')
    setIssued(null)
  }, [open])

  const lines = allLines.filter((l) => !excluded.has(l.id))
  const totals = useMemo(() => quoteTotals(lines, company.vat_pct), [lines, company.vat_pct])
  const documentNumber = event.event_number ?? ''
  const waNumber = toWhatsAppNumber(contact?.contact_phone)

  const fixedNote = quoteFixedNote(documentNumber || '—', customerName, new Date())

  const toggle = (id: string) =>
    setExcluded((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })

  const generate = async () => {
    try {
      const { generateQuotePdf } = await import('./quotePdf')
      const logo = await fetchCompanyLogo(company.logo_path)
      const issuedAt = new Date()
      const bytes = await generateQuotePdf({
        documentNumber,
        issuedAt,
        company,
        logo,
        customerName,
        endClientName: event.end_client_name,
        contactName: contact?.contact_name ?? null,
        contactPhone: contact?.contact_phone ?? null,
        eventDate: event.event_date,
        eventLocation: event.location_text,
        lines,
        totals,
        vatPct: company.vat_pct,
        fixedNote: quoteFixedNote(documentNumber, customerName, issuedAt),
        notes: notes.trim() || null,
        paymentTerms,
      })
      const fileName = quoteFileName(documentNumber)
      const quote = await issue.mutateAsync({
        bytes,
        fileName,
        documentNumber,
        lines,
        totals,
        vatPct: company.vat_pct,
        paymentTerms,
        notes: notes.trim() || null,
      })
      setIssued({
        quote,
        file: new File([bytes], fileName, { type: 'application/pdf' }),
      })
      toast.success('המסמך הופק')
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  const share = async () => {
    if (!issued) return
    const text = quoteWhatsAppText(documentNumber, company.name)
    const canShareFile =
      typeof navigator !== 'undefined' &&
      !!navigator.canShare?.({ files: [issued.file] }) &&
      !!navigator.share

    try {
      if (canShareFile) {
        await navigator.share({ files: [issued.file], title: issued.file.name, text })
      } else {
        // אין תפריט שיתוף: הקובץ יורד, והשיחה עם המספר הנכון נפתחת לצדו.
        downloadBlob(issued.file, issued.file.name)
        if (waNumber) {
          window.open(
            `https://wa.me/${waNumber}?text=${encodeURIComponent(text)}`,
            '_blank',
            'noopener',
          )
        } else {
          toast.info('אין טלפון לאיש הקשר — הקובץ ירד ואפשר לצרף אותו ידנית')
        }
      }
    } catch (e) {
      // ביטול תפריט השיתוף אינו כישלון, והוא אינו מסמן שנשלח.
      if ((e as Error)?.name === 'AbortError') return
      toast.error(errorMessage(e))
      return
    }

    markSent.mutate(issued.quote.id, {
      onSuccess: () => {
        toast.success('נרשם ביומן האירוע שההצעה נשלחה')
        onClose()
      },
      onError: (err) => toast.error(errorMessage(err)),
    })
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      size="lg"
      title="הצעת מחיר ללקוח הקצה"
      description={
        documentNumber
          ? `מסמך מס׳ ${documentNumber} · ${event.end_client_name ?? 'ללא שם לקוח קצה'}`
          : undefined
      }
      footer={
        <div className="flex flex-wrap items-center justify-between gap-2">
          <span className="type-caption text-ink-tertiary">
            {issued ? 'המסמך מוכן לשליחה' : `סה״כ לתשלום ${fmtMoney(totals.total)}`}
          </span>
          <div className="flex flex-wrap gap-2">
            <Button onClick={onClose}>סגירה</Button>
            {issued ? (
              <>
                <Button onClick={() => downloadBlob(issued.file, issued.file.name)}>
                  <Download size={ICON.sm} strokeWidth={STROKE} />
                  הורדה
                </Button>
                <Button variant="primary" loading={markSent.isPending} onClick={() => void share()}>
                  <Phone size={ICON.sm} strokeWidth={STROKE} />
                  שיתוף בוואטסאפ
                </Button>
              </>
            ) : (
              <Button
                variant="primary"
                loading={issue.isPending}
                disabled={!documentNumber || !lines.length}
                onClick={() => void generate()}
              >
                <FileText size={ICON.sm} strokeWidth={STROKE} />
                הפקת המסמך
              </Button>
            )}
          </div>
        </div>
      }
    >
      <div className="space-y-5">
        {!documentNumber && (
          <p className="rounded-lg border border-warning-border bg-warning-subtle px-3 py-2 type-caption text-warning-text">
            לאירוע אין מספר אירוע, ומספר המסמך נגזר ממנו. יש להזין אותו בעריכת האירוע.
          </p>
        )}

        <section className="space-y-2">
          <h3 className="type-caption text-ink-tertiary">שורות ההצעה</h3>
          {allLines.length === 0 ? (
            <EmptyState compact art="box" title="אין משימות מתומחרות באירוע" />
          ) : (
            <ul className="divide-y divide-line-subtle rounded-lg border border-line-subtle">
              {allLines.map((l) => (
                <li key={l.id} className="flex items-center gap-3 px-3 py-2">
                  <Checkbox
                    checked={!excluded.has(l.id)}
                    onChange={() => toggle(l.id)}
                    aria-label={l.label}
                  />
                  <span className="min-w-0 flex-1">
                    <span className={`block truncate type-body ${l.kind === 'addon' ? 'text-ink-secondary' : 'font-medium'}`}>
                      {l.kind === 'addon' ? `↳ ${l.label}` : l.label}
                    </span>
                    {l.whenText && <span className="type-caption text-ink-tertiary">{l.whenText}</span>}
                  </span>
                  <span dir="ltr" className="shrink-0 tabular-nums type-body">
                    {fmtMoney(l.amount)}
                  </span>
                </li>
              ))}
            </ul>
          )}
          <dl className="space-y-1 px-3 type-caption">
            {[
              ['סכום ביניים', totals.subtotal],
              [`מע״מ ${company.vat_pct}%`, totals.vatAmount],
              ['סה״כ לתשלום', totals.total],
            ].map(([label, value], i) => (
              <div key={label as string} className="flex items-center justify-between gap-3">
                <dt className={i === 2 ? 'font-semibold text-ink' : 'text-ink-tertiary'}>{label}</dt>
                <dd dir="ltr" className={`tabular-nums ${i === 2 ? 'font-semibold' : ''}`}>
                  {fmtMoney(value as number)}
                </dd>
              </div>
            ))}
          </dl>
        </section>

        <section className="space-y-2">
          <h3 className="type-caption text-ink-tertiary">הערות</h3>
          <p className="rounded-lg bg-subtle/50 px-3 py-2 type-caption text-ink-secondary">{fixedNote}</p>
          <Field label="הערות נוספות" hint="נוספות מתחת למשפט הקבוע במסמך">
            <Textarea
              autoGrow
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              disabled={!!issued}
              placeholder="הצוות מגיע שעה לפני תחילת האירוע…"
            />
          </Field>
          <p className="type-caption text-ink-tertiary">
            תנאי תשלום:{' '}
            {paymentTerms ??
              (termsField
                ? 'לא נבחרו באירוע'
                : `אין ללקוח שדה בשם "${PAYMENT_TERMS_LABEL}"`)}
          </p>
        </section>

        {history.length > 0 && (
          <section className="space-y-2">
            <h3 className="type-caption text-ink-tertiary">הצעות שהופקו</h3>
            <ul className="divide-y divide-line-subtle rounded-lg border border-line-subtle">
              {history.map((q) => (
                <QuoteHistoryRow key={q.id} quote={q} />
              ))}
            </ul>
          </section>
        )}
      </div>
    </Modal>
  )
}

function QuoteHistoryRow({ quote }: { quote: EventQuote }) {
  const toast = useToast()
  const { data: url } = useQuoteSignedUrl(quote)
  return (
    <li className="flex flex-wrap items-center gap-2 px-3 py-2">
      <span className="min-w-0 flex-1">
        <span className="block truncate type-body">
          מס׳ {quote.document_number}
          {quote.version > 1 && <span className="text-ink-tertiary"> · גרסה {quote.version}</span>}
        </span>
        <span className="type-caption text-ink-tertiary">
          {quote.issuer_name} · {fmtDateTime(quote.created_at)}
        </span>
      </span>
      {quote.sent_at ? (
        <Badge tone="success">נשלחה</Badge>
      ) : (
        <Badge tone="neutral">הופקה</Badge>
      )}
      <span dir="ltr" className="shrink-0 tabular-nums type-body font-medium">
        {fmtMoney(quote.total)}
      </span>
      {url && (
        <a href={url} target="_blank" rel="noreferrer" className="type-caption text-accent underline">
          פתיחה
        </a>
      )}
      <button
        type="button"
        className="type-caption text-accent underline"
        onClick={() => {
          void downloadQuote(quote).catch((e) => toast.error(errorMessage(e)))
        }}
      >
        הורדה
      </button>
    </li>
  )
}
