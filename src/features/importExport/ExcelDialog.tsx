import { useMemo, useRef, useState } from 'react'
import ExcelJS from 'exceljs'
import { useQueryClient } from '@tanstack/react-query'
import {
  AlertTriangle,
  CircleCheck,
  Download,
  FileSpreadsheet,
  FileText,
  ICON,
  STROKE,
  Upload,
} from '../../components/ui/icons'
import { supabase } from '../../lib/supabase'
import { Button, Modal, Spinner, useToast } from '../../components/ui'
import { useAllCustomFormFields, useCustomers, useExecutionMethods, useTaskTypes } from '../../lib/queries'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { errorMessage } from '../../lib/errors'
import {
  EVENTS_SHEET,
  TASKS_SHEET,
  TASK_COLUMNS,
  buildImportPayload,
  buildSamplePlan,
  buildTemplatePlan,
  eventColumns,
  groupTasks,
  normalizeCell,
  parseEventSheet,
  parseSheet,
} from './eventsWorkbook'
import type { Matrix, SheetPlan, SheetRow } from './eventsWorkbook'
import { formatCustomValue } from '../events/CustomFieldInput'
import type { CustomFieldValue } from '../../types/domain'

const XLSX_MIME = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'

/** כותב תוכנית גיליונות לחוברת ExcelJS ומוריד אותה. */
async function downloadWorkbook(plans: SheetPlan[], filename: string) {
  const wb = new ExcelJS.Workbook()
  wb.creator = 'ViperLogistics'
  for (const plan of plans) {
    const ws = wb.addWorksheet(plan.name, { views: [{ rightToLeft: true, state: 'frozen', ySplit: 1 }] })
    if (plan.intro?.length) {
      // הכותרות יורדות מתחת לטקסט, ולכן אין כאן הקפאת שורה — היא הייתה מקפיאה
      // את שורת ההסבר הראשונה במקום את הכותרות.
      ws.views = [{ rightToLeft: true }]
      for (const line of plan.intro) {
        const row = ws.addRow([line])
        if (line && !line.startsWith(' ')) row.font = { bold: !/^\d/.test(line) }
      }
      ws.addRow([])
    }
    const header = ws.addRow(plan.columns.map((c) => c.header))
    header.font = { bold: true }
    plan.columns.forEach((c, i) => {
      ws.getColumn(i + 1).width = c.width
    })
    for (const r of plan.rows) ws.addRow(plan.columns.map((c) => r[c.key] ?? ''))
  }

  const buf = await wb.xlsx.writeBuffer()
  const url = URL.createObjectURL(new Blob([buf], { type: XLSX_MIME }))
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}

/** גיליון ExcelJS → מטריצת מחרוזות. שורה 0 היא הכותרות. */
function sheetToMatrix(ws: ExcelJS.Worksheet | undefined): Matrix {
  if (!ws) return []
  const matrix: Matrix = []
  ws.eachRow((row) => {
    const values = row.values as ExcelJS.CellValue[]
    // ExcelJS מחזיר מערך 1-בסיסי: התא הראשון הוא values[1].
    matrix.push(values.slice(1).map(normalizeCell))
  })
  return matrix
}

export function ExcelDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const toast = useToast()
  const qc = useQueryClient()
  const { data: customers = [] } = useCustomers()
  const { data: taskTypes = [] } = useTaskTypes()
  const { data: executionMethods = [] } = useExecutionMethods()
  /* Custom fields become extra columns. One file can carry rows for several
     customers, so the whole set is loaded, not one customer's. */
  const { data: customFields = [] } = useAllCustomFormFields(open)
  const customerNames = useMemo(() => new Map(customers.map((c) => [c.id, c.name])), [customers])
  const eventCols = useMemo(() => eventColumns(customFields, customerNames), [customFields, customerNames])
  const has = useAuth((s) => s.has)
  /**
   * Export and import were both reachable by anyone who could open the events
   * screen, and the export carries contact phone numbers out of the system into
   * a file. Each side now needs its own key; the server checks the same ones.
   */
  const canExport = has(PERM.EVENTS_EXPORT)
  const canImport = has(PERM.EVENTS_IMPORT)
  const canSeeContacts = has(PERM.EVENTS_VIEW_CONTACTS)
  const fileRef = useRef<HTMLInputElement>(null)
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState<{
    imported: number
    tasks_imported?: number
    errors: { row: number; error: string }[]
  } | null>(null)

  const exportEvents = async () => {
    setBusy(true)
    try {
      const { data, error } = await supabase
        .from('events')
        // event_contacts has its own RLS keyed on can_view_field('event',
        // 'contact_phone'), so the embed comes back empty for a user without
        // the right — the filtering is the server's, not this select's.
        .select('*, customers(name), event_contacts(contact_name, contact_phone)')
        .is('deleted_at', null)
        .order('event_date', { ascending: false })
        .limit(5000)
      if (error) throw error

      const rows = data as Record<string, unknown>[]
      // מזהה השורה מיוצר כאן ולא נשמר במסד — הוא קיים כדי שגיליון המשימות
      // יוכל להצביע על שורת האירוע, וכדי שקובץ שיצא יוכל לחזור פנימה.
      const keyById = new Map(rows.map((e, i) => [e.id as string, String(i + 1)]))

      const eventRows: SheetRow[] = rows.map((e) => {
        const contact = e.event_contacts as { contact_name?: string; contact_phone?: string } | null
        // a custom field belongs to one customer, so only that customer's rows
        // carry a value in its column — everyone else's cell stays empty
        const stored = (e.custom_fields ?? {}) as Record<string, CustomFieldValue>
        const custom: SheetRow = {}
        for (const f of customFields) {
          if (f.customer_id !== e.customer_id) continue
          custom[f.field_key] = formatCustomValue(f, stored[f.field_key])
        }
        return {
          ...custom,
          row_key: keyById.get(e.id as string) ?? '',
          customer_name: (e.customers as { name: string } | null)?.name ?? '',
          end_client_name: String(e.end_client_name ?? ''),
          event_number: String(e.event_number ?? ''),
          event_date: String(e.event_date ?? ''),
          location_text: String(e.location_text ?? ''),
          location_notes: String(e.location_notes ?? ''),
          volume_m: String(e.volume_m ?? ''),
          truck_count: String(e.truck_count ?? ''),
          contact_name: contact?.contact_name ?? '',
          contact_phone: contact?.contact_phone ?? '',
          notes: String(e.notes ?? ''),
        }
      })

      // הסינון מפוצל למנות: רשימת מזהים באורך אלפים נכנסת ל-query string של
      // PostgREST ומפוצצת את אורך ה-URL.
      const ids = [...keyById.keys()]
      const tasks: Record<string, unknown>[] = []
      for (let i = 0; i < ids.length; i += 200) {
        const { data: chunk, error: taskError } = await supabase
          .from('tasks')
          .select(
            'event_id, title, task_date, warehouse_start_time, onsite_start_time, hours_count, ' +
              'worker_count, truck_free_text, location_text, notes, ' +
              'task_types(name), execution_methods(name)',
          )
          .in('event_id', ids.slice(i, i + 200))
          .is('deleted_at', null)
          .order('task_date')
        if (taskError) throw taskError
        tasks.push(...(chunk as unknown as Record<string, unknown>[]))
      }

      const taskRows: SheetRow[] = tasks.map((t) => ({
        row_key: keyById.get(t.event_id as string) ?? '',
        task_type: (t.task_types as { name: string } | null)?.name ?? '',
        title: String(t.title ?? ''),
        task_date: String(t.task_date ?? ''),
        warehouse_start_time: String(t.warehouse_start_time ?? '').slice(0, 5),
        onsite_start_time: String(t.onsite_start_time ?? '').slice(0, 5),
        hours_count: String(t.hours_count ?? ''),
        worker_count: String(t.worker_count ?? ''),
        execution_method: (t.execution_methods as { name: string } | null)?.name ?? '',
        truck_free_text: String(t.truck_free_text ?? ''),
        location_text: String(t.location_text ?? ''),
        notes: String(t.notes ?? ''),
      }))

      await downloadWorkbook(
        [
          { name: EVENTS_SHEET, columns: eventCols, rows: eventRows },
          { name: TASKS_SHEET, columns: TASK_COLUMNS, rows: taskRows },
        ],
        `events-${new Date().toISOString().slice(0, 10)}.xlsx`,
      )
    } catch (e) {
      toast.error(errorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  const importFile = async (file: File) => {
    setBusy(true)
    setResult(null)
    try {
      const wb = new ExcelJS.Workbook()
      await wb.xlsx.load(await file.arrayBuffer())
      // איתור לפי שם, ובקובץ שנכתב ידנית — לפי מיקום. קובץ בן גיליון אחד
      // נשאר ייבוא אירועים בלבד, בדיוק כמו לפני שהמשימות נוספו.
      const eventsWs = wb.getWorksheet(EVENTS_SHEET) ?? wb.worksheets[0]
      const tasksWs = wb.getWorksheet(TASKS_SHEET) ?? (wb.worksheets.length > 1 ? wb.worksheets[1] : undefined)
      if (!eventsWs) throw new Error('הקובץ ריק')

      const events = parseEventSheet(sheetToMatrix(eventsWs), eventCols)
      if (events.length === 0) throw new Error('לא נמצאו שורות לייבוא')
      const taskRows = tasksWs === eventsWs ? [] : parseSheet(sheetToMatrix(tasksWs), TASK_COLUMNS)

      const { tasksByKey, errors } = groupTasks(events, taskRows)
      if (errors.length) throw new Error(errors.join(' · '))

      const { payloads, unknownCustomers } = buildImportPayload(events, tasksByKey, customers, customFields)
      if (unknownCustomers.length) {
        throw new Error(`לקוחות לא מוכרים בקובץ: ${unknownCustomers.join(', ')}`)
      }

      const { data, error } = await supabase.rpc('bulk_import_events', { p_rows: payloads })
      if (error) throw error
      setResult(data as { imported: number; tasks_imported?: number; errors: { row: number; error: string }[] })
      void qc.invalidateQueries({ queryKey: ['events'] })
      void qc.invalidateQueries({ queryKey: ['calendar'] })
      void qc.invalidateQueries({ queryKey: ['workboard'] })
    } catch (e) {
      toast.error(errorMessage(e))
    } finally {
      setBusy(false)
      if (fileRef.current) fileRef.current.value = ''
    }
  }

  const downloadTemplate = () => downloadWorkbook(buildTemplatePlan(eventCols), 'events-template.xlsx')

  const downloadSample = () =>
    downloadWorkbook(
      buildSamplePlan({
        customers: customers.map((c) => c.name),
        taskTypes: taskTypes.filter((t) => t.is_active).map((t) => t.name),
        executionMethods: executionMethods.filter((m) => m.is_active).map((m) => m.name),
      }, eventCols),
      'events-sample.xlsx',
    )

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="ייבוא / ייצוא אירועים"
      description="קובץ Excel עם גיליון אירועים וגיליון משימות"
      footer={<Button onClick={onClose}>סגירה</Button>}
    >
      {busy ? (
        <div className="flex flex-col items-center gap-3 py-10">
          <Spinner size={28} />
          <p className="type-body text-ink-secondary">מעבד את הקובץ...</p>
        </div>
      ) : (
        <div className="space-y-4">
          <div className="grid gap-2 sm:grid-cols-2">
            {canExport && (
              <ActionTile
                icon={<Download size={ICON.xl} strokeWidth={STROKE} />}
                title="ייצוא אירועים"
                description={canSeeContacts ? 'כל האירועים הפעילים והמשימות שלהם' : 'ללא פרטי אנשי קשר'}
                onClick={() => void exportEvents()}
              />
            )}
            {canImport && (
              <>
                <ActionTile
                  icon={<FileText size={ICON.xl} strokeWidth={STROKE} />}
                  title="הורדת קובץ לדוגמה"
                  description="אירועים ומשימות מלאים, עם גיליון הסבר"
                  onClick={() => void downloadSample()}
                />
                <ActionTile
                  icon={<FileSpreadsheet size={ICON.xl} strokeWidth={STROKE} />}
                  title="הורדת תבנית"
                  description="קובץ ריק עם הכותרות הנכונות"
                  onClick={() => void downloadTemplate()}
                />
                <ActionTile
                  icon={<Upload size={ICON.xl} strokeWidth={STROKE} />}
                  title="ייבוא אירועים ומשימות"
                  description="בחירת xlsx להעלאה"
                  primary
                  onClick={() => fileRef.current?.click()}
                />
              </>
            )}
            <input
              ref={fileRef}
              type="file"
              accept=".xlsx"
              className="hidden"
              onChange={(e) => {
                const f = e.target.files?.[0]
                if (f) void importFile(f)
              }}
            />
          </div>

          <div className="rounded-lg border border-info-border bg-info-subtle px-3 py-2.5">
            <p className="type-caption text-info-text">
              גיליון "אירועים" — שורה לכל אירוע. גיליון "משימות" — שורה לכל משימה, מקושרת לאירוע
              דרך עמודת "מזהה שורה". הייבוא מזהה לקוח לפי "שם לקוח במערכת" ומחיל את שדות החובה
              שהוגדרו לכל לקוח. משימות ההקמה והפירוק נוצרות לכל אירוע ממילא, ושורה בגיליון המשימות
              ממלאת אותן במקום להכפיל. אפשר להעלות גם קובץ בן גיליון אחד.
            </p>
          </div>

          {result && (
            <div className="space-y-2">
              <div className="flex items-center gap-2 rounded-lg border border-success-border bg-success-subtle px-3 py-2.5">
                <CircleCheck size={ICON.md} className="shrink-0 text-success-text" strokeWidth={STROKE} />
                <p className="type-body font-medium text-success-text">
                  {result.imported} אירועים
                  {result.tasks_imported ? ` ו-${result.tasks_imported} משימות` : ''} יובאו בהצלחה
                </p>
              </div>
              {result.errors.length > 0 && (
                <div className="rounded-lg border border-error-border bg-error-subtle p-3">
                  <p className="mb-1.5 flex items-center gap-1.5 type-body font-medium text-error-text">
                    <AlertTriangle size={ICON.sm} strokeWidth={STROKE} />
                    {result.errors.length} שורות נכשלו
                  </p>
                  <ul className="max-h-40 space-y-0.5 overflow-y-auto">
                    {result.errors.map((e) => (
                      <li key={e.row} className="type-caption text-error-text">
                        <span className="tabular font-semibold">שורה {e.row}:</span> {e.error}
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </Modal>
  )
}

function ActionTile({
  icon,
  title,
  description,
  onClick,
  primary,
}: {
  icon: React.ReactNode
  title: string
  description: string
  onClick: () => void
  primary?: boolean
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={
        'flex flex-col items-center gap-1.5 rounded-xl border p-4 text-center transition-all duration-150 ' +
        'hover:-translate-y-px hover:shadow-md focus-visible:outline-none focus-visible:focus-ring ' +
        (primary
          ? 'border-primary-border bg-primary-subtle text-primary-text'
          : 'border-line bg-surface hover:border-line-strong')
      }
    >
      <span className={primary ? 'text-primary' : 'text-ink-tertiary'}>{icon}</span>
      <span className="type-body font-semibold text-ink">{title}</span>
      <span className="type-caption text-ink-tertiary">{description}</span>
    </button>
  )
}
