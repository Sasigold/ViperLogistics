import { useRef, useState } from 'react'
import { AlertTriangle, FileSpreadsheet, ICON, STROKE, Upload } from '../../components/ui/icons'
import { Button, Modal, Spinner, useToast } from '../../components/ui'
import { errorMessage } from '../../lib/errors'
import { fmtDate } from '../../lib/dates'
import { normalizeCell } from '../importExport/eventsWorkbook'
import { fmtCibusAmount, parseCibusMatrix, summarizeParsed } from './cibus'
import type { CibusParseResult } from './cibus'
import { useCibusImport } from './cibusQueries'
import { CibusLinkRow } from './CibusSummaryCard'
import type { CibusImportResult } from '../../types/domain'

/**
 * ייבוא הדוח המפורט של סיבוס (0210).
 *
 * שלושה שלבים: בחירת קובץ, תצוגה מקדימה של מה שנקרא (כדי שקובץ לא נכון ייעצר
 * לפני שהוא נשמר), ואחרי הייבוא — צימוד מיידי של מי שהשם שלו בסיבוס לא זוהה
 * מול עובד במערכת. הצימוד נזכר, ולכן בחודש הבא זה כבר לא יופיע.
 */
export function CibusImportModal({ onClose }: { onClose: () => void }) {
  const toast = useToast()
  const fileRef = useRef<HTMLInputElement>(null)
  const [reading, setReading] = useState(false)
  const [fileName, setFileName] = useState<string | null>(null)
  const [parsed, setParsed] = useState<CibusParseResult | null>(null)
  const [result, setResult] = useState<CibusImportResult | null>(null)
  const importMut = useCibusImport()

  const readFile = async (file: File) => {
    setReading(true)
    setParsed(null)
    setResult(null)
    setFileName(file.name)
    try {
      // ExcelJS כבד, והייבוא הוא הסיבה היחידה שהוא נחוץ במסך הזה
      const ExcelJS = (await import('exceljs')).default
      const wb = new ExcelJS.Workbook()
      await wb.xlsx.load(await file.arrayBuffer())
      const ws = wb.worksheets[0]
      if (!ws) throw new Error('הקובץ ריק')
      const matrix: string[][] = []
      ws.eachRow((row) => {
        matrix.push((row.values as unknown[]).slice(1).map(normalizeCell))
      })
      setParsed(parseCibusMatrix(matrix))
    } catch (e) {
      toast.error(errorMessage(e))
    } finally {
      setReading(false)
      if (fileRef.current) fileRef.current.value = ''
    }
  }

  const summary = parsed ? summarizeParsed(parsed.rows) : null

  const runImport = () => {
    if (!parsed?.rows.length) return
    importMut.mutate(parsed.rows, {
      onSuccess: (r) => {
        setResult(r)
        toast.success(`יובאו ${r.inserted + r.updated} משיכות`)
      },
      onError: (e) => toast.error(errorMessage(e)),
    })
  }

  return (
    <Modal
      open
      onClose={onClose}
      title="ייבוא סיבוס"
      description="הדוח המפורט של סיבוס לחודש (xlsx). כל משיכה מוצלבת מול דיווחי הנוכחות של העובד"
      footer={
        result ? (
          <Button variant="primary" onClick={onClose}>
            סיום
          </Button>
        ) : (
          <>
            <Button onClick={onClose}>ביטול</Button>
            <Button
              variant="primary"
              loading={importMut.isPending}
              disabled={!parsed?.rows.length}
              onClick={runImport}
            >
              ייבוא {parsed?.rows.length ? `${parsed.rows.length} משיכות` : ''}
            </Button>
          </>
        )
      }
    >
      <div className="space-y-4">
        {!result && (
          <button
            type="button"
            onClick={() => fileRef.current?.click()}
            className="surface flex w-full items-center gap-3 p-4 text-start transition-colors hover:border-line-strong hover:bg-subtle/60"
          >
            <span className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-primary-subtle text-primary" aria-hidden>
              {reading ? <Spinner size={20} /> : <Upload size={ICON.lg} strokeWidth={STROKE} />}
            </span>
            <span className="min-w-0">
              <span className="block type-title">{fileName ? 'בחירת קובץ אחר' : 'בחירת קובץ סיבוס'}</span>
              <span className="block truncate type-caption text-ink-tertiary">
                {fileName ?? 'דוח מפורט לחברה — Excel'}
              </span>
            </span>
          </button>
        )}
        <input
          ref={fileRef}
          type="file"
          accept=".xlsx"
          className="hidden"
          onChange={(e) => {
            const f = e.target.files?.[0]
            if (f) void readFile(f)
          }}
        />

        {summary && summary.count > 0 && !result && (
          <div className="rounded-xl border border-line-subtle bg-subtle px-4 py-3">
            <p className="flex items-center gap-2 type-title">
              <FileSpreadsheet size={ICON.md} strokeWidth={STROKE} className="text-ink-tertiary" />
              {summary.count} משיכות · {summary.employees} עובדים · {fmtCibusAmount(summary.amount)}
            </p>
            {summary.from && (
              <p className="type-caption text-ink-tertiary tabular" dir="rtl">
                {fmtDate(summary.from)} – {fmtDate(summary.to)}
              </p>
            )}
            <p className="mt-1 type-caption text-ink-secondary">
              ייבוא חוזר של אותו קובץ מעדכן ולא מכפיל — כל משיכה מזוהה לפי מספר העסקה.
            </p>
          </div>
        )}

        {parsed && parsed.errors.length > 0 && (
          <div className="rounded-xl border border-warning-border bg-warning-subtle px-4 py-3">
            <p className="flex items-center gap-2 type-body font-semibold text-warning-text">
              <AlertTriangle size={ICON.sm} strokeWidth={STROKE} />
              {parsed.rows.length ? `${parsed.errors.length} שורות לא נקראו` : 'הקובץ לא נקרא'}
            </p>
            <ul className="mt-1 list-disc space-y-0.5 ps-5 type-caption text-warning-text">
              {parsed.errors.slice(0, 8).map((e) => (
                <li key={e}>{e}</li>
              ))}
            </ul>
          </div>
        )}

        {result && (
          <div className="space-y-3">
            <p className="type-body">
              נוספו {result.inserted} משיכות חדשות
              {result.updated > 0 && `, ${result.updated} עודכנו (כבר יובאו בעבר)`}.
            </p>
            {result.unlinked.length > 0 ? (
              <div className="space-y-2">
                <p className="type-body font-semibold">
                  העובדים האלה לא זוהו לפי השם — יש לבחור לכל אחד את העובד במערכת:
                </p>
                {result.unlinked.map((u) => (
                  <CibusLinkRow key={u.link_key} linkKey={u.link_key} name={u.employee_name} />
                ))}
                <p className="type-caption text-ink-tertiary">הבחירה נשמרת, ובייבוא של החודש הבא הם יזוהו מעצמם.</p>
              </div>
            ) : (
              <p className="type-caption text-success-text">כל העובדים בקובץ זוהו.</p>
            )}
          </div>
        )}
      </div>
    </Modal>
  )
}
