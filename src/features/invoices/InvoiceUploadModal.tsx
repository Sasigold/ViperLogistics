import { useRef, useState } from 'react'
import { AlertTriangle, Camera, CircleCheck, FileText, ICON, Info, Plus, STROKE, Trash2, Upload } from '../../components/ui/icons'
import { Button, IconButton, Modal, ProgressBar, Spinner, useToast } from '../../components/ui'
import { errorMessage } from '../../lib/errors'
import { imagesToPdf, isImage, isPdf } from './invoicePdf'
import { readInvoices, toInvoicePdf, uploadInvoice, useInvalidateInvoices } from './invoiceQueries'
import type { ReadOutcome } from './invoiceQueries'

type Mode = 'files' | 'camera'

interface Result {
  name: string
  status: 'uploaded' | 'duplicate' | 'failed'
  error?: string
}

/**
 * העלאת חשבוניות (0233): קבצי PDF או תמונות — כל קובץ חשבונית — או צילום
 * במצלמה, כמה עמודים לחשבונית אחת. הכול נשמר כ-PDF, ואז נקרא אוטומטית.
 */
export function InvoiceUploadModal({ mode, onClose }: { mode: Mode; onClose: () => void }) {
  const toast = useToast()
  const invalidate = useInvalidateInvoices()
  const fileRef = useRef<HTMLInputElement>(null)
  const camRef = useRef<HTMLInputElement>(null)
  const [files, setFiles] = useState<File[]>([])
  const [shots, setShots] = useState<File[]>([])
  const [step, setStep] = useState<{ label: string; done: number; total: number } | null>(null)
  const [results, setResults] = useState<Result[] | null>(null)
  const [read, setRead] = useState<ReadOutcome | null>(null)
  const [failure, setFailure] = useState<string | null>(null)

  const running = step !== null && results === null
  const finished = results !== null

  const pick = (list: FileList | null) => {
    const ok = [...(list ?? [])].filter((f) => isPdf(f) || isImage(f))
    if (ok.length < (list?.length ?? 0)) toast.error('רק קבצי PDF ותמונות')
    setFiles((prev) => [...prev, ...ok].slice(0, 50))
  }

  const run = async () => {
    setFailure(null)
    // צילום: כל התמונות הן עמודים של חשבונית אחת
    const jobs: { name: string; source: 'upload' | 'camera'; make: () => Promise<Uint8Array> }[] =
      mode === 'camera'
        ? [{ name: `צילום ${new Date().toLocaleDateString('he-IL').replace(/\./g, '-')}.pdf`, source: 'camera', make: () => imagesToPdf(shots) }]
        : files.map((f) => ({ name: f.name, source: 'upload' as const, make: () => toInvoicePdf(f) }))

    const out: Result[] = []
    const ids: string[] = []
    setStep({ label: 'מעלה…', done: 0, total: jobs.length })
    for (const [n, job] of jobs.entries()) {
      try {
        const pdf = await job.make()
        const r = await uploadInvoice(job.name, pdf, job.source)
        out.push({ name: job.name, status: r.duplicate ? 'duplicate' : 'uploaded' })
        if (!r.duplicate) ids.push(r.id)
      } catch (e) {
        out.push({ name: job.name, status: 'failed', error: errorMessage(e) })
      }
      setStep({ label: 'מעלה…', done: n + 1, total: jobs.length })
    }
    invalidate()

    if (ids.length > 0) {
      try {
        const r = await readInvoices(ids, (done, total) => setStep({ label: 'קורא את החשבוניות…', done, total }))
        setRead(r)
      } catch (e) {
        setFailure(`הקריאה האוטומטית נכשלה: ${errorMessage(e)} — אפשר להקליד את הפרטים ביד`)
      }
    }
    invalidate()
    setResults(out)
  }

  const ready = mode === 'camera' ? shots.length > 0 : files.length > 0
  const progress = step && step.total > 0 ? (step.done / step.total) * 100 : null

  return (
    <Modal
      open
      onClose={running ? () => toast.info('ההעלאה עוד רצה — רגע…') : onClose}
      title={mode === 'camera' ? 'צילום חשבונית' : 'העלאת חשבוניות'}
      description={
        mode === 'camera'
          ? 'צלמו את החשבונית — כמה עמודים אם צריך. היא תישמר כקובץ PDF אחד ותיקרא אוטומטית.'
          : 'קבצי PDF או תמונות, כל קובץ חשבונית. הם נשמרים כ-PDF ונקראים אוטומטית.'
      }
      footer={
        finished ? (
          <Button variant="primary" onClick={onClose}>
            סגירה
          </Button>
        ) : (
          <>
            <Button onClick={onClose} disabled={running}>
              ביטול
            </Button>
            <Button variant="primary" onClick={() => void run()} disabled={!ready || running}>
              {running ? <Spinner size={ICON.sm} /> : <Upload size={ICON.sm} strokeWidth={STROKE} />}
              {mode === 'camera' ? 'שמירה וקריאה' : `העלאה וקריאה${files.length > 1 ? ` (${files.length})` : ''}`}
            </Button>
          </>
        )
      }
    >
      <div className="space-y-4">
        {!running && !finished && mode === 'files' && (
          <>
            <input
              ref={fileRef}
              type="file"
              multiple
              accept="application/pdf,image/*"
              className="hidden"
              onChange={(e) => {
                pick(e.target.files)
                e.target.value = ''
              }}
            />
            <button
              type="button"
              onClick={() => fileRef.current?.click()}
              onDragOver={(e) => e.preventDefault()}
              onDrop={(e) => {
                e.preventDefault()
                pick(e.dataTransfer.files)
              }}
              className="flex w-full flex-col items-center gap-2 rounded-xl border-2 border-dashed border-line p-6 text-ink-secondary hover:border-primary hover:text-primary-text"
            >
              <Upload size={ICON.hero} strokeWidth={STROKE} />
              <span className="type-body font-medium">בחירת קבצים, או גרירה לכאן</span>
              <span className="type-caption text-ink-tertiary">PDF, JPG, PNG — עד 15MB לקובץ</span>
            </button>
            {files.length > 0 && (
              <ul className="max-h-56 space-y-1 overflow-y-auto">
                {files.map((f, i) => (
                  <li key={`${f.name}-${i}`} className="flex items-center gap-2 rounded-lg bg-subtle px-3 py-1.5 type-body">
                    <FileText size={ICON.sm} strokeWidth={STROKE} className="shrink-0 text-ink-tertiary" />
                    <span className="min-w-0 flex-1 truncate">{f.name}</span>
                    <IconButton
                      label="הסרה"
                      size="sm"
                      onClick={() => setFiles((prev) => prev.filter((_, j) => j !== i))}
                    >
                      <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                    </IconButton>
                  </li>
                ))}
              </ul>
            )}
          </>
        )}

        {!running && !finished && mode === 'camera' && (
          <>
            <input
              ref={camRef}
              type="file"
              accept="image/*"
              capture="environment"
              className="hidden"
              onChange={(e) => {
                const f = e.target.files?.[0]
                if (f) setShots((prev) => [...prev, f].slice(0, 10))
                e.target.value = ''
              }}
            />
            {shots.length === 0 ? (
              <button
                type="button"
                onClick={() => camRef.current?.click()}
                className="flex w-full flex-col items-center gap-2 rounded-xl border-2 border-dashed border-line p-8 text-ink-secondary hover:border-primary hover:text-primary-text"
              >
                <Camera size={ICON.hero} strokeWidth={STROKE} />
                <span className="type-body font-medium">פתיחת המצלמה</span>
                <span className="type-caption text-ink-tertiary">במחשב — בחירת תמונה מהקבצים</span>
              </button>
            ) : (
              <div className="space-y-2">
                <div className="grid grid-cols-3 gap-2">
                  {shots.map((s, i) => (
                    <ShotThumb key={i} file={s} n={i + 1} onRemove={() => setShots((p) => p.filter((_, j) => j !== i))} />
                  ))}
                </div>
                <Button onClick={() => camRef.current?.click()}>
                  <Plus size={ICON.sm} strokeWidth={STROKE} />
                  עוד עמוד
                </Button>
              </div>
            )}
          </>
        )}

        {running && step && (
          <div className="space-y-2">
            <p className="type-body text-ink-secondary">
              {step.label} {step.total > 1 && `${step.done}/${step.total}`}
            </p>
            {progress !== null && <ProgressBar value={progress} />}
          </div>
        )}

        {finished && results && (
          <div className="space-y-3">
            <ul className="space-y-1">
              {results.map((r, i) => (
                <li key={i} className="flex items-start gap-2 type-body">
                  {r.status === 'failed' ? (
                    <AlertTriangle size={ICON.sm} strokeWidth={STROKE} className="mt-1 shrink-0 text-error-text" />
                  ) : r.status === 'duplicate' ? (
                    <Info size={ICON.sm} strokeWidth={STROKE} className="mt-1 shrink-0 text-warning-text" />
                  ) : (
                    <CircleCheck size={ICON.sm} strokeWidth={STROKE} className="mt-1 shrink-0 text-success-text" />
                  )}
                  <span className="min-w-0">
                    <span className="font-medium">{r.name}</span>
                    {r.status === 'duplicate' && <span className="text-ink-tertiary"> — כבר קיימת במערכת</span>}
                    {r.status === 'failed' && <span className="text-error-text"> — {r.error}</span>}
                  </span>
                </li>
              ))}
            </ul>
            {read && !read.configured && (
              <p className="type-caption text-warning-text">
                הקריאה האוטומטית עוד לא מוגדרת בשרת — הקבצים נשמרו, ואת הפרטים אפשר להקליד ביד.
              </p>
            )}
            {read && read.configured && read.read > 0 && (
              <p className="type-caption text-ink-secondary">
                {read.read} חשבוניות נקראו. כדאי לעבור עליהן ולאשר — הן מסומנות ״לבדיקה״.
              </p>
            )}
            {read && read.failed.length > 0 && (
              <p className="type-caption text-error-text">
                {read.failed.length} לא נקראו ({read.failed[0].error}) — אפשר לנסות שוב מהרשימה או להקליד ביד.
              </p>
            )}
            {failure && <p className="type-caption text-error-text">{failure}</p>}
          </div>
        )}
      </div>
    </Modal>
  )
}

function ShotThumb({ file, n, onRemove }: { file: File; n: number; onRemove: () => void }) {
  const [url] = useState(() => URL.createObjectURL(file))
  return (
    <div className="relative overflow-hidden rounded-lg border border-line">
      <img src={url} alt={`עמוד ${n}`} className="aspect-[3/4] w-full object-cover" onLoad={() => undefined} />
      <span className="absolute start-1 top-1 rounded bg-surface/90 px-1.5 type-caption">{n}</span>
      <button
        type="button"
        onClick={() => {
          URL.revokeObjectURL(url)
          onRemove()
        }}
        className="absolute end-1 top-1 rounded bg-surface/90 p-1 text-error-text"
        aria-label={`הסרת עמוד ${n}`}
      >
        <Trash2 size={ICON.xs} strokeWidth={STROKE} />
      </button>
    </div>
  )
}
