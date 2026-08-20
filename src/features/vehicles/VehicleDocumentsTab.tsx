import { useMemo, useState } from 'react'
import { useMutation } from '@tanstack/react-query'
import {
  AlertTriangle,
  Download,
  FileText,
  ICON,
  Paperclip,
  Pencil,
  Plus,
  STROKE,
  Trash2,
} from '../../components/ui/icons'
import {
  Button,
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  Field,
  IconButton,
  Input,
  Modal,
  Select,
  Skeleton,
  StatusPill,
  Textarea,
  useConfirm,
  useToast,
} from '../../components/ui'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { useVehicleDocumentKinds } from '../../lib/queries'
import { errorMessage } from '../../lib/errors'
import { fmtDate } from '../../lib/dates'
import type { Vehicle, VehicleDocumentStatus } from '../../types/domain'
import {
  useRemoveVehicleDocument,
  useSaveVehicleDocument,
  useVehicleDocuments,
  vehicleDocDownloadUrl,
} from './vehicleQueries'
import type { DocumentDraft } from './vehicleQueries'
import {
  DOC_STATE_COLORS,
  DOC_STATE_LABELS,
  VEHICLE_DOC_ACCEPT,
  expiryLabel,
  formatBytes,
  suggestExpiry,
  validateDocFile,
} from './vehicles'

/**
 * מסמכי הרכב: טסט, רישיון, ביטוחים, ואישורים שהצי הזה צריך.
 *
 * המצב (בתוקף / פג בקרוב / פג) מגיע מה-view בשרת ולא נחשב כאן, כדי שהוא
 * יסכים עם מה שהסוויפ שולח עליו התראה ועם מה שהדשבורד מציג.
 */
export function VehicleDocumentsTab({ vehicle }: { vehicle: Vehicle }) {
  const { has } = useAuth()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const canManage = has(PERM.FLEET_DOCS_MANAGE)

  const { data: kinds = [] } = useVehicleDocumentKinds()
  const { data: docs = [], isLoading } = useVehicleDocuments(vehicle.id)
  const remove = useRemoveVehicleDocument(vehicle.id)

  const [modal, setModal] = useState<{ open: boolean; editing: VehicleDocumentStatus | null }>({
    open: false,
    editing: null,
  })

  /* מסמכי חובה שאין להם שורה בתוקף — זה מה שהופך "אין מסמך" ממצב שקוף
     לשורה שרואים. הרכב אינו יודע אם יש לו מנוף, ולכן רק ה-is_required
     שבקטלוג קובע מה נחשב חסר. */
  const missing = useMemo(() => {
    const live = new Set(docs.filter((d) => d.status !== 'expired').map((d) => d.kind_id))
    return kinds.filter((k) => k.is_required && k.is_active && !live.has(k.id))
  }, [kinds, docs])

  const download = async (doc: VehicleDocumentStatus) => {
    try {
      const url = await vehicleDocDownloadUrl(doc)
      if (url) window.open(url, '_blank', 'noopener')
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  return (
    <div className="max-w-4xl space-y-4">
      {dialog}

      {missing.length > 0 && (
        <Card>
          <CardBody className="flex flex-wrap items-center gap-3">
            <span className="text-warning" aria-hidden>
              <AlertTriangle size={ICON.lg} strokeWidth={STROKE} />
            </span>
            <span className="min-w-0 flex-1">
              <span className="block type-body font-medium">חסרים מסמכי חובה</span>
              <span className="block type-caption text-ink-tertiary">{missing.map((k) => k.name).join(' · ')}</span>
            </span>
          </CardBody>
        </Card>
      )}

      <Card>
        <CardHeader
          title="מסמכים"
          subtitle={`${docs.length} מסמכים · ${docs.filter((d) => d.status === 'expired').length} פגי תוקף`}
          icon={<FileText size={ICON.md} strokeWidth={STROKE} />}
          actions={
            canManage && (
              <Button variant="primary" size="sm" onClick={() => setModal({ open: true, editing: null })}>
                <Plus size={ICON.sm} strokeWidth={STROKE} />
                מסמך חדש
              </Button>
            )
          }
        />
        <CardBody padded={false}>
          {isLoading ? (
            <div className="p-4">
              <Skeleton className="h-24 w-full" />
            </div>
          ) : docs.length === 0 ? (
            <EmptyState
              compact
              art="table"
              title="אין מסמכים לרכב"
              description={canManage ? 'טסט, רישיון וביטוח — עם תאריך פקיעה, כדי שנתריע לפני' : undefined}
            />
          ) : (
            <ul>
              {docs.map((d) => (
                <li
                  key={d.id}
                  className="flex flex-wrap items-center gap-3 border-b border-line-subtle px-4 py-3 last:border-0 hover:bg-hover"
                >
                  <span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-subtle text-ink-tertiary" aria-hidden>
                    <FileText size={ICON.sm} strokeWidth={STROKE} />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="flex flex-wrap items-center gap-2 truncate type-body font-medium">
                      {d.kind_name}
                      <StatusPill color={DOC_STATE_COLORS[d.status]}>{DOC_STATE_LABELS[d.status]}</StatusPill>
                    </p>
                    <p className="truncate type-caption text-ink-tertiary">
                      {[
                        d.expires_at ? `${fmtDate(d.expires_at)} · ${expiryLabel(d.expires_at)}` : 'ללא תאריך פקיעה',
                        d.document_number ? `מס׳ ${d.document_number}` : null,
                        d.issuer,
                      ]
                        .filter(Boolean)
                        .join(' · ')}
                    </p>
                  </div>
                  {d.storage_path && (
                    <IconButton label={`הורדת ${d.file_name ?? d.kind_name}`} size="sm" onClick={() => void download(d)}>
                      <Download size={ICON.sm} strokeWidth={STROKE} />
                    </IconButton>
                  )}
                  {canManage && (
                    <>
                      <IconButton label={`עריכת ${d.kind_name}`} size="sm" onClick={() => setModal({ open: true, editing: d })}>
                        <Pencil size={ICON.sm} strokeWidth={STROKE} />
                      </IconButton>
                      <IconButton
                        label={`הסרת ${d.kind_name}`}
                        size="sm"
                        className="hover:text-error"
                        onClick={async () => {
                          if (!(await confirm(`להסיר את "${d.kind_name}"?`, { title: 'הסרת מסמך', confirmLabel: 'הסרה' })))
                            return
                          remove.mutate(
                            { id: d.id },
                            {
                              onSuccess: () => toast.success('המסמך הוסר'),
                              onError: (e) => toast.error(errorMessage(e)),
                            },
                          )
                        }}
                      >
                        <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                      </IconButton>
                    </>
                  )}
                </li>
              ))}
            </ul>
          )}
        </CardBody>
      </Card>

      <DocumentModal
        vehicle={vehicle}
        open={modal.open}
        editing={modal.editing}
        onClose={() => setModal({ open: false, editing: null })}
      />
    </div>
  )
}

/* ===== הוספה ועריכה ======================================================= */

const BLANK: DocumentDraft = {
  kind_id: '',
  document_number: '',
  issued_at: '',
  expires_at: '',
  cost: '',
  issuer: '',
  note: '',
  file: null,
}

function DocumentModal({
  vehicle,
  open,
  editing,
  onClose,
}: {
  vehicle: Vehicle
  open: boolean
  editing: VehicleDocumentStatus | null
  onClose: () => void
}) {
  const toast = useToast()
  const { data: kinds = [] } = useVehicleDocumentKinds()
  const save = useSaveVehicleDocument(vehicle.id)
  const [draft, setDraft] = useState<DocumentDraft>(BLANK)
  const [fileError, setFileError] = useState<string | null>(null)

  const [openedFor, setOpenedFor] = useState<string | null>(null)
  const openKey = open ? (editing?.id ?? 'new') : null
  if (openKey !== openedFor) {
    setOpenedFor(openKey)
    setFileError(null)
    if (openKey) {
      setDraft(
        editing
          ? {
              kind_id: editing.kind_id,
              document_number: editing.document_number ?? '',
              issued_at: editing.issued_at ?? '',
              expires_at: editing.expires_at ?? '',
              cost: editing.cost == null ? '' : String(editing.cost),
              issuer: editing.issuer ?? '',
              note: editing.note ?? '',
              file: null,
            }
          : BLANK,
      )
    }
  }

  const kind = kinds.find((k) => k.id === draft.kind_id)
  const valid = draft.kind_id !== '' && !fileError

  /* בחירת סוג ותאריך הוצאה ממלאת את הפקיעה לפי `default_valid_months`
     שבקטלוג. זו הצעה בלבד — המשתמש יכול לדרוס אותה. */
  const setIssued = (issued: string) =>
    setDraft((d) => {
      const months = kinds.find((k) => k.id === d.kind_id)?.default_valid_months ?? null
      const suggested = suggestExpiry(issued, months)
      return { ...d, issued_at: issued, expires_at: d.expires_at || suggested }
    })

  const pickFile = (file: File | null) => {
    if (!file) {
      setFileError(null)
      return setDraft((d) => ({ ...d, file: null }))
    }
    const err = validateDocFile(file)
    setFileError(err)
    setDraft((d) => ({ ...d, file: err ? null : file }))
  }

  const submit = useMutation({
    mutationFn: () => save.mutateAsync({ draft, editing }),
    onSuccess: () => {
      toast.success(editing ? 'המסמך עודכן' : 'המסמך נוסף')
      onClose()
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={editing ? `עריכת ${editing.kind_name}` : 'מסמך חדש'}
      description="תאריך פקיעה הוא מה שמזין את ההתראות — מסמך בלי תאריך אינו מתריע"
      footer={
        <>
          <Button className="ms-auto" onClick={onClose}>
            ביטול
          </Button>
          <Button variant="primary" loading={submit.isPending} disabled={!valid} onClick={() => submit.mutate()}>
            {editing ? 'שמירה' : 'הוספה'}
          </Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="סוג המסמך" required>
          <Select
            data-autofocus
            disabled={!!editing}
            value={draft.kind_id}
            onChange={(e) => setDraft((d) => ({ ...d, kind_id: e.target.value }))}
          >
            <option value="">בחירת סוג...</option>
            {kinds
              .filter((k) => k.is_active)
              .map((k) => (
                <option key={k.id} value={k.id}>
                  {k.name}
                </option>
              ))}
          </Select>
        </Field>
        <Field label="מספר המסמך">
          <Input
            dir="ltr"
            value={draft.document_number}
            onChange={(e) => setDraft((d) => ({ ...d, document_number: e.target.value }))}
          />
        </Field>
        <Field label="תאריך הוצאה">
          <Input type="date" value={draft.issued_at} onChange={(e) => setIssued(e.target.value)} />
        </Field>
        <Field
          label="תאריך פקיעה"
          hint={kind ? `התראה ${kind.alert_days} ימים לפני` : undefined}
        >
          <Input
            type="date"
            value={draft.expires_at}
            onChange={(e) => setDraft((d) => ({ ...d, expires_at: e.target.value }))}
          />
        </Field>
        <Field label="מנפיק" hint="חברת הביטוח, מכון הרישוי, משרד התחבורה">
          <Input value={draft.issuer} onChange={(e) => setDraft((d) => ({ ...d, issuer: e.target.value }))} />
        </Field>
        <Field label="עלות (₪)">
          <Input
            type="number"
            step="any"
            dir="ltr"
            value={draft.cost}
            onChange={(e) => setDraft((d) => ({ ...d, cost: e.target.value }))}
          />
        </Field>
        <Field
          label="קובץ סרוק"
          className="sm:col-span-2"
          error={fileError ?? undefined}
          hint={
            editing?.file_name && !draft.file
              ? `כרגע: ${editing.file_name}${editing.size_bytes ? ` · ${formatBytes(editing.size_bytes)}` : ''}`
              : 'PDF או תמונה, עד 25MB'
          }
        >
          <Input type="file" accept={VEHICLE_DOC_ACCEPT} onChange={(e) => pickFile(e.target.files?.[0] ?? null)} />
        </Field>
        {draft.file && (
          <p className="flex items-center gap-2 type-caption text-ink-tertiary sm:col-span-2">
            <Paperclip size={ICON.xs} strokeWidth={STROKE} />
            {draft.file.name} · {formatBytes(draft.file.size)}
            {editing?.file_name && <span>· יחליף את {editing.file_name}</span>}
          </p>
        )}
        <Field label="הערה" className="sm:col-span-2">
          <Textarea autoGrow rows={2} value={draft.note} onChange={(e) => setDraft((d) => ({ ...d, note: e.target.value }))} />
        </Field>
      </div>
    </Modal>
  )
}
