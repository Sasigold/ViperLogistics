/**
 * החתמת לקוח על האירוע (0107).
 *
 * מסך אחד בשני מצבים: צפייה בחתימה שנקלטה, והחתמה חדשה (שם לקוח + לוח חתימה).
 * מי שרשאי רק לצפות (למשל רכז שהוענק לו `sign_view` בלבד) רואה את המצב הראשון
 * ותו לא; ראש צוות ההקמה, הלקוח ומנהל המערכת רשאים גם להחתים.
 *
 * הרשומה קבועה: החתמה חוזרת אינה דורסת אלא מוסיפה שורה, והאחרונה היא הפעילה.
 */
import { useEffect, useRef, useState } from 'react'
import { Check, Eye, ICON, PencilLine, RotateCcw, STROKE } from '../../components/ui/icons'
import {
  Badge,
  Button,
  EmptyState,
  ErrorState,
  Field,
  Input,
  Modal,
  SkeletonList,
  useToast,
} from '../../components/ui'
import { errorMessage } from '../../lib/errors'
import { fmtDateTime } from '../../lib/dates'
import type { EventSignature } from '../../types/domain'
import { SignaturePad, type SignaturePadHandle } from './SignaturePad'
import { useAddSignature, useEventSignatures } from './signatureQueries'

type Mode = 'view' | 'sign'

export function CustomerSignatureModal({
  eventId,
  eventTitle,
  open,
  onClose,
  canCapture,
}: {
  eventId: string
  eventTitle: string
  open: boolean
  onClose: () => void
  /** ראש צוות ההקמה, הלקוח, ומי שהוענק לו `sign_capture` — או מנהל המערכת */
  canCapture: boolean
}) {
  const { data: signatures = [], isLoading, error, refetch } = useEventSignatures(eventId, open)
  const latest = signatures[0] ?? null

  // מצב פתיחה: אם אין חתימה עדיין ומותר להחתים — ישר ללוח החתימה. אחרת, צפייה.
  const [mode, setMode] = useState<Mode>('view')
  useEffect(() => {
    if (!open) return
    setMode(!latest && canCapture ? 'sign' : 'view')
  }, [open, latest, canCapture])

  return (
    <Modal
      open={open}
      onClose={onClose}
      size="lg"
      title={
        <span className="flex flex-wrap items-center gap-2">
          <PencilLine size={ICON.lg} strokeWidth={STROKE} />
          החתמת לקוח
          {signatures.length > 0 && (
            <Badge tone="success">
              <Check size={ICON.xs} strokeWidth={STROKE} /> נחתם
            </Badge>
          )}
        </span>
      }
      description={eventTitle}
    >
      <div className="flex flex-col gap-4">
        {isLoading && <SkeletonList rows={2} />}
        {error && <ErrorState error={error} onRetry={() => void refetch()} />}

        {!isLoading && !error && mode === 'sign' && canCapture && (
          <SignForm eventId={eventId} onDone={() => setMode('view')} onCancel={latest ? () => setMode('view') : undefined} />
        )}

        {!isLoading && !error && mode === 'view' && (
          latest ? (
            <>
              <SignatureCard signature={latest} primary />
              {canCapture && (
                <div>
                  <Button size="sm" onClick={() => setMode('sign')}>
                    <PencilLine size={ICON.sm} strokeWidth={STROKE} />
                    החתמה מחדש
                  </Button>
                </div>
              )}
              {signatures.length > 1 && <History signatures={signatures.slice(1)} />}
            </>
          ) : (
            <EmptyState
              art="box"
              title="טרם נקלטה חתימה"
              description={
                canCapture
                  ? 'אפשר להחתים את הלקוח על שם וחתימה, והחתימה תישמר על האירוע.'
                  : 'כשתיקלט חתימה על האירוע הזה היא תופיע כאן.'
              }
              action={
                canCapture ? (
                  <Button variant="primary" onClick={() => setMode('sign')}>
                    <PencilLine size={ICON.sm} strokeWidth={STROKE} />
                    החתמת לקוח
                  </Button>
                ) : undefined
              }
            />
          )
        )}
      </div>
    </Modal>
  )
}

/* ===== צפייה בחתימה ======================================================= */

function SignatureCard({ signature, primary }: { signature: EventSignature; primary?: boolean }) {
  return (
    <section className="rounded-xl border border-line-subtle bg-surface p-3">
      <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <Eye size={ICON.sm} strokeWidth={STROKE} className="text-ink-tertiary" />
          <span className="type-body font-semibold">{signature.signer_name}</span>
          {primary && <Badge tone="success">חתימה פעילה</Badge>}
        </div>
        <span className="type-caption text-ink-tertiary">{fmtDateTime(signature.created_at)}</span>
      </div>
      {/* רקע לבן קבוע: הדיו כהה, ולכן החתימה נקראת זהה בכל ערכת נושא */}
      <div className="overflow-hidden rounded-lg border border-line-subtle bg-white">
        <img
          src={signature.signature_data}
          alt={`חתימת ${signature.signer_name}`}
          className="mx-auto max-h-64 w-full object-contain"
        />
      </div>
      {signature.signed_by_name && (
        <p className="mt-2 type-caption text-ink-tertiary">נקלט על ידי {signature.signed_by_name}</p>
      )}
    </section>
  )
}

function History({ signatures }: { signatures: EventSignature[] }) {
  return (
    <section className="rounded-xl border border-line-subtle">
      <h3 className="border-b border-line-subtle px-3 py-2 type-caption font-semibold text-ink-secondary">
        חתימות קודמות
      </h3>
      <ul className="divide-y divide-line-subtle">
        {signatures.map((s) => (
          <li key={s.id} className="flex flex-wrap items-center gap-2 px-3 py-2">
            <img
              src={s.signature_data}
              alt={`חתימת ${s.signer_name}`}
              className="h-8 w-20 shrink-0 rounded border border-line-subtle bg-white object-contain"
            />
            <span className="min-w-0 flex-1 truncate type-caption font-medium text-ink-secondary">
              {s.signer_name}
            </span>
            {s.signed_by_name && (
              <span className="type-caption text-ink-tertiary">נקלט על ידי {s.signed_by_name}</span>
            )}
            <span className="type-caption tabular text-ink-tertiary">{fmtDateTime(s.created_at)}</span>
          </li>
        ))}
      </ul>
    </section>
  )
}

/* ===== החתמה חדשה ========================================================= */

function SignForm({
  eventId,
  onDone,
  onCancel,
}: {
  eventId: string
  onDone: () => void
  onCancel?: () => void
}) {
  const toast = useToast()
  const add = useAddSignature(eventId)
  const padRef = useRef<SignaturePadHandle>(null)
  const [name, setName] = useState('')
  const [hasInk, setHasInk] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)

  async function submit() {
    const trimmed = name.trim()
    if (!trimmed) return setProblem('צריך להזין שם לקוח')
    if (!padRef.current || padRef.current.isEmpty()) return setProblem('צריך לחתום באזור החתימה')
    try {
      await add.mutateAsync({ signerName: trimmed, signatureData: padRef.current.toDataURL() })
      toast.success('החתימה נקלטה')
      onDone()
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  return (
    <div className="space-y-3">
      <Field label="שם לקוח" required error={problem && !name.trim() ? problem : undefined}>
        <Input
          value={name}
          placeholder="שם החותם"
          onChange={(e) => {
            setName(e.target.value)
            setProblem(null)
          }}
        />
      </Field>

      <Field
        label="חתימה"
        required
        error={problem && name.trim() ? problem : undefined}
        action={
          <button
            type="button"
            onClick={() => {
              padRef.current?.clear()
              setProblem(null)
            }}
            className="inline-flex items-center gap-1 type-caption text-ink-tertiary hover:text-ink focus-visible:outline-none focus-visible:focus-ring"
          >
            <RotateCcw size={ICON.xs} strokeWidth={STROKE} />
            ניקוי
          </button>
        }
      >
        <SignaturePad
          ref={padRef}
          disabled={add.isPending}
          onDirtyChange={(dirty) => {
            setHasInk(dirty)
            if (dirty) setProblem(null)
          }}
        />
      </Field>

      <div className="flex justify-end gap-2">
        {onCancel && (
          <Button onClick={onCancel} disabled={add.isPending}>
            ביטול
          </Button>
        )}
        <Button
          variant="primary"
          loading={add.isPending}
          disabled={!name.trim() || !hasInk}
          onClick={() => void submit()}
        >
          <Check size={ICON.sm} strokeWidth={STROKE} />
          שמירת חתימה
        </Button>
      </div>
    </div>
  )
}
