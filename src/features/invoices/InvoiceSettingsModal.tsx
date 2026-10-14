import { useState } from 'react'
import { Building2, ICON, Mail, Pencil, Plug, Plus, STROKE, Trash2 } from '../../components/ui/icons'
import {
  Badge,
  Button,
  Field,
  IconButton,
  Input,
  Modal,
  Spinner,
  Switch,
  TagsInput,
  useConfirm,
  useToast,
} from '../../components/ui'
import { fmtDateTime } from '../../lib/dates'
import { errorMessage } from '../../lib/errors'
import type { InvoiceCompany, InvoiceGmailAccount } from '../../types/domain'
import {
  connectGmail,
  useDisconnectGmail,
  useGmailStatus,
  useInvoiceCompanies,
  useRemoveCompany,
  useSaveCompany,
  useSaveGmailSettings,
} from './invoiceQueries'

/**
 * ההגדרות של החשבוניות (0233): החברות שהחשבוניות יוצאות עבורן, וחיבור Gmail.
 * Gmail מושך רק חשבוניות שהנמען בהן הוא אחת החברות.
 */
export function InvoiceSettingsModal({ onClose }: { onClose: () => void }) {
  return (
    <Modal open size="lg" title="הגדרות חשבוניות" onClose={onClose}>
      <div className="space-y-6">
        <CompaniesSection />
        <GmailSection />
      </div>
    </Modal>
  )
}

function CompaniesSection() {
  const { data: companies, isLoading } = useInvoiceCompanies()
  const [editing, setEditing] = useState<InvoiceCompany | 'new' | null>(null)
  const remove = useRemoveCompany()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()

  return (
    <section className="space-y-3">
      {dialog}
      <div className="flex items-center gap-2">
        <Building2 size={ICON.lg} strokeWidth={STROKE} className="text-ink-tertiary" />
        <h3 className="type-body font-semibold">החברות שלי</h3>
        <Button size="sm" className="ms-auto" onClick={() => setEditing('new')}>
          <Plus size={ICON.sm} strokeWidth={STROKE} />
          חברה
        </Button>
      </div>
      <p className="type-caption text-ink-tertiary">
        חשבוניות שיצאו עבור החברות האלה נמשכות מ-Gmail. ההתאמה לפי ח.פ., ואם אין — לפי השם או אחד השמות הנוספים.
      </p>
      {isLoading && <Spinner />}
      {companies?.length === 0 && !editing && (
        <p className="rounded-lg bg-warning-subtle px-3 py-2 type-caption text-warning-text">
          עוד לא הוגדרה חברה — בלי חברה, Gmail לא מושך אף חשבונית.
        </p>
      )}
      <ul className="space-y-1.5">
        {companies?.map((c) =>
          editing !== 'new' && editing?.id === c.id ? (
            <li key={c.id}>
              <CompanyForm company={c} onDone={() => setEditing(null)} />
            </li>
          ) : (
            <li key={c.id} className="flex items-center gap-2 rounded-lg border border-line px-3 py-2">
              <div className="min-w-0 flex-1">
                <p className="type-body font-medium">
                  {c.name} {!c.active && <Badge>מושבתת</Badge>}
                </p>
                <p className="type-caption text-ink-tertiary">
                  {c.tax_id ? `ח.פ. ${c.tax_id}` : 'בלי ח.פ.'}
                  {c.aliases.length > 0 && ` · גם: ${c.aliases.join(', ')}`}
                </p>
              </div>
              <IconButton label="עריכה" size="sm" onClick={() => setEditing(c)}>
                <Pencil size={ICON.sm} strokeWidth={STROKE} />
              </IconButton>
              <IconButton
                label="הסרה"
                size="sm"
                onClick={async () => {
                  if (!(await confirm(`להסיר את ${c.name}?`, { confirmLabel: 'הסרה' }))) return
                  remove.mutate(c.id, { onError: (e) => toast.error(errorMessage(e)) })
                }}
              >
                <Trash2 size={ICON.sm} strokeWidth={STROKE} />
              </IconButton>
            </li>
          ),
        )}
      </ul>
      {editing === 'new' && <CompanyForm onDone={() => setEditing(null)} />}
    </section>
  )
}

function CompanyForm({ company, onDone }: { company?: InvoiceCompany; onDone: () => void }) {
  const save = useSaveCompany()
  const toast = useToast()
  const [name, setName] = useState(company?.name ?? '')
  const [taxId, setTaxId] = useState(company?.tax_id ?? '')
  const [aliases, setAliases] = useState<string[]>(company?.aliases ?? [])
  const [active, setActive] = useState(company?.active ?? true)

  const submit = () =>
    save.mutate(
      { id: company?.id ?? null, name, tax_id: taxId, aliases, active },
      { onSuccess: onDone, onError: (e) => toast.error(errorMessage(e)) },
    )

  return (
    <div className="space-y-3 rounded-lg border border-primary/40 bg-subtle p-3">
      <div className="grid gap-3 sm:grid-cols-2">
        <Field label="שם החברה" required>
          <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="וייפר מיקור חוץ לעסקים בע״מ" />
        </Field>
        <Field label="ח.פ. / ע.מ.">
          <Input value={taxId} inputMode="numeric" onChange={(e) => setTaxId(e.target.value)} />
        </Field>
      </div>
      <Field label="שמות נוספים" hint="איך עוד החברה מופיעה בחשבוניות — למשל באנגלית">
        <TagsInput values={aliases} onChange={setAliases} placeholder="Viper Outsourcing" />
      </Field>
      <div className="flex items-center gap-2">
        <Switch checked={active} onChange={setActive} label="פעילה" />
        <Button size="sm" className="ms-auto" onClick={onDone}>
          ביטול
        </Button>
        <Button size="sm" variant="primary" onClick={submit} disabled={!name.trim() || save.isPending}>
          שמירה
        </Button>
      </div>
    </div>
  )
}

function GmailSection() {
  const { data, isLoading } = useGmailStatus()
  const toast = useToast()
  const [connecting, setConnecting] = useState(false)

  return (
    <section className="space-y-3">
      <div className="flex items-center gap-2">
        <Mail size={ICON.lg} strokeWidth={STROKE} className="text-ink-tertiary" />
        <h3 className="type-body font-semibold">Gmail</h3>
        <Button
          size="sm"
          className="ms-auto"
          disabled={connecting}
          onClick={async () => {
            setConnecting(true)
            try {
              await connectGmail()
            } catch (e) {
              toast.error(errorMessage(e))
              setConnecting(false)
            }
          }}
        >
          {connecting ? <Spinner size={ICON.sm} /> : <Plug size={ICON.sm} strokeWidth={STROKE} />}
          {data?.accounts.length ? 'חיבור חשבון נוסף' : 'חיבור Gmail'}
        </Button>
      </div>
      <p className="type-caption text-ink-tertiary">
        הרשאת קריאה בלבד. המערכת סורקת מיילים עם PDF או תמונה מצורפים — בפעם הראשונה 60 יום אחורה, ואחר כך כל 3 שעות —
        ושומרת רק חשבוניות שיצאו עבור החברות שלמעלה.
      </p>
      {isLoading && <Spinner />}
      {data?.accounts.map((a) => <GmailAccountRow key={a.id} account={a} />)}
    </section>
  )
}

function GmailAccountRow({ account: a }: { account: InvoiceGmailAccount }) {
  const save = useSaveGmailSettings()
  const disconnect = useDisconnectGmail()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const [query, setQuery] = useState(a.query_extra)

  return (
    <div className="space-y-3 rounded-lg border border-line p-3">
      {dialog}
      <div className="flex flex-wrap items-center gap-2">
        <span className="type-body font-medium" dir="ltr">
          {a.email}
        </span>
        {a.active ? <Badge tone="success" dot>מחובר</Badge> : <Badge>מושהה</Badge>}
        <span className="type-caption text-ink-tertiary">
          {a.imported} חשבוניות · {a.messages} מיילים נבדקו
          {a.last_run_at && ` · סריקה אחרונה ${fmtDateTime(a.last_run_at)}`}
        </span>
      </div>
      {a.last_error && <p className="type-caption text-error-text">{a.last_error}</p>}
      <Field label="סינון נוסף (לא חובה)" hint='בתחביר החיפוש של Gmail, למשל: from:(billing@pango.co.il OR invoice@) או label:חשבוניות'>
        <Input value={query} dir="ltr" onChange={(e) => setQuery(e.target.value)} />
      </Field>
      <div className="flex flex-wrap items-center gap-2">
        <Switch
          checked={a.active}
          onChange={(v) => save.mutate({ id: a.id, query_extra: query, active: v }, { onError: (e) => toast.error(errorMessage(e)) })}
          label="סריקה אוטומטית"
        />
        <Button
          size="sm"
          className="ms-auto"
          disabled={query === a.query_extra || save.isPending}
          onClick={() =>
            save.mutate(
              { id: a.id, query_extra: query, active: a.active },
              { onSuccess: () => toast.success('נשמר'), onError: (e) => toast.error(errorMessage(e)) },
            )
          }
        >
          שמירת הסינון
        </Button>
        <Button
          size="sm"
          variant="danger"
          onClick={async () => {
            if (
              !(await confirm(
                'לנתק את החשבון? החשבוניות שכבר נמשכו נשארות. כדי לבטל לגמרי את ההרשאה — גם ב-myaccount.google.com → אבטחה → אפליקציות של צד שלישי.',
                { confirmLabel: 'ניתוק' },
              ))
            ) {
              return
            }
            disconnect.mutate(a.id, { onError: (e) => toast.error(errorMessage(e)) })
          }}
        >
          ניתוק
        </Button>
      </div>
    </div>
  )
}
