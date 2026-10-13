import { useMemo, useRef, useState } from 'react'
import { AlertTriangle, CircleCheck, FileText, ICON, Info, STROKE, Upload } from '../../components/ui/icons'
import { Button, Field, Modal, ProgressBar, Select, Spinner, useToast } from '../../components/ui'
import { errorMessage } from '../../lib/errors'
import { defaultUploadPeriod, periodLabel, periodOptions, slipPages } from './payslips'
import { readPayslipBatch, uploadPayslipFile, useInvalidatePayslips } from './payslipQueries'
import type { ReadOutcome, UploadStep } from './payslipQueries'

const STEP_LABEL: Record<UploadStep['step'], string> = {
  split: 'מפצל את הקובץ לעמודים…',
  upload: 'מעלה את העמודים…',
  read: 'קורא את התלושים…',
  group: 'מסדר את העמודים לתלושים…',
}

/**
 * העלאת הקובץ של רואה החשבון (0218): פיצול לעמודים בדפדפן, העלאה, קריאה
 * אוטומטית (כשמוגדרת) וקיבוץ לתלושים בשרת. בסוף — מעבר ישר לשיוך.
 */
export function PayslipUploadModal({
  onClose,
  onUploaded,
}: {
  onClose: () => void
  /** הקובץ עלה; המסך פותח את השיוך שלו */
  onUploaded: (batchId: string) => void
}) {
  const toast = useToast()
  const invalidate = useInvalidatePayslips()
  const fileRef = useRef<HTMLInputElement>(null)
  const months = useMemo(() => periodOptions(new Date()), [])
  const [file, setFile] = useState<File | null>(null)
  const [period, setPeriod] = useState(() => defaultUploadPeriod(new Date()))
  const [step, setStep] = useState<UploadStep | null>(null)
  const [done, setDone] = useState<{ batchId: string; pages: number; read: ReadOutcome | null } | null>(null)
  const [failure, setFailure] = useState<string | null>(null)

  const running = step !== null && !done

  const run = async () => {
    if (!file) return
    setFailure(null)
    let uploaded: { batchId: string; pageCount: number } | null = null
    try {
      uploaded = await uploadPayslipFile(file, period, setStep)
      invalidate()
      const read = await readPayslipBatch(uploaded.batchId, slipPages(1, uploaded.pageCount), setStep)
      setDone({ batchId: uploaded.batchId, pages: uploaded.pageCount, read })
    } catch (e) {
      if (uploaded) {
        // הקובץ עלה; רק הקריאה נכשלה. השיוך ביד עדיין פתוח.
        setDone({ batchId: uploaded.batchId, pages: uploaded.pageCount, read: null })
        setFailure(`הקריאה האוטומטית נכשלה: ${errorMessage(e)}`)
      } else {
        setStep(null)
        setFailure(errorMessage(e))
      }
    } finally {
      invalidate()
    }
  }

  const progress =
    step && (step.step === 'upload' || step.step === 'read') && step.total > 0 ? (step.done / step.total) * 100 : null

  return (
    <Modal
      open
      onClose={running ? () => toast.info('ההעלאה עוד רצה — רגע…') : onClose}
      title="העלאת קובץ תלושים"
      description="קובץ ה-PDF מרואה החשבון, עם כל התלושים של החודש"
      footer={
        done ? (
          <Button
            variant="primary"
            onClick={() => {
              onUploaded(done.batchId)
              onClose()
            }}
          >
            לשיוך התלושים
          </Button>
        ) : (
          <>
            <Button onClick={onClose} disabled={running}>
              ביטול
            </Button>
            <Button variant="primary" loading={running} disabled={!file} onClick={() => void run()}>
              <Upload size={ICON.sm} strokeWidth={STROKE} />
              העלאה
            </Button>
          </>
        )
      }
    >
      <div className="space-y-4">
        {!step && (
          <>
            <button
              type="button"
              onClick={() => fileRef.current?.click()}
              className="surface flex w-full items-center gap-3 p-4 text-start transition-colors hover:border-line-strong hover:bg-subtle/60"
            >
              <span
                className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-primary-subtle text-primary"
                aria-hidden
              >
                <FileText size={ICON.lg} strokeWidth={STROKE} />
              </span>
              <span className="min-w-0">
                <span className="block type-title">{file ? 'בחירת קובץ אחר' : 'בחירת קובץ תלושים'}</span>
                <span className="block truncate type-caption text-ink-tertiary">{file?.name ?? 'PDF'}</span>
              </span>
            </button>
            <input
              ref={fileRef}
              type="file"
              accept="application/pdf,.pdf"
              className="hidden"
              onChange={(e) => {
                const f = e.target.files?.[0]
                if (f) setFile(f)
                e.target.value = ''
              }}
            />
            <Field label="חודש התלושים" hint="תלוש שכתוב בו חודש אחר יקבל את החודש שבו">
              <Select value={period} onChange={(e) => setPeriod(e.target.value)}>
                {months.map((m) => (
                  <option key={m} value={m}>
                    {periodLabel(m)}
                  </option>
                ))}
              </Select>
            </Field>
          </>
        )}

        {step && !done && (
          <div className="space-y-3 rounded-xl border border-line-subtle bg-subtle px-4 py-4">
            <p className="flex items-center gap-2 type-title">
              <Spinner size={18} />
              {STEP_LABEL[step.step]}
            </p>
            {progress !== null && <ProgressBar value={progress} />}
            {step.step === 'read' && (
              <p className="type-caption text-ink-tertiary tabular-nums">
                {step.done} מתוך {step.total} עמודים · כחצי דקה לכל כמה עמודים
              </p>
            )}
          </div>
        )}

        {done && (
          <div className="space-y-2">
            <p className="flex items-center gap-2 type-body font-semibold text-success-text">
              <CircleCheck size={ICON.md} strokeWidth={STROKE} />
              הקובץ עלה — {done.pages} עמודים
            </p>
            {done.read?.grouped && (
              <p className="type-body">
                הקריאה האוטומטית זיהתה את העובד והחודש בכל תלוש, ואיחדה תלושים של כמה עמודים. בשיוך כל תלוש יוצג עם
                העובד שהמערכת מציעה — לאישור שלך.
              </p>
            )}
            {done.read && !done.read.configured && (
              <p className="flex items-start gap-2 rounded-lg border border-line-subtle bg-subtle px-3 py-2 type-caption text-ink-secondary">
                <Info size={ICON.sm} strokeWidth={STROKE} className="mt-0.5 shrink-0" />
                הקריאה האוטומטית אינה מוגדרת, ולכן כל עמוד הוא תלוש. בשיוך יוצג כל עמוד ותבחר למי הוא שייך; עמוד שהוא
                המשך של הקודם מצרפים בלחיצה.
              </p>
            )}
            {done.read && done.read.failed.length > 0 && (
              <p className="flex items-start gap-2 rounded-lg border border-warning-border bg-warning-subtle px-3 py-2 type-caption text-warning-text">
                <AlertTriangle size={ICON.sm} strokeWidth={STROKE} className="mt-0.5 shrink-0" />
                {done.read.failed.length} עמודים לא נקראו ({done.read.failed[0].error}). הם יוצגו בשיוך כעמודים בודדים.
              </p>
            )}
          </div>
        )}

        {failure && (
          <p className="flex items-start gap-2 rounded-lg border border-warning-border bg-warning-subtle px-3 py-2 type-caption text-warning-text">
            <AlertTriangle size={ICON.sm} strokeWidth={STROKE} className="mt-0.5 shrink-0" />
            {failure}
          </p>
        )}
      </div>
    </Modal>
  )
}
