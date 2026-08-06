import { useRef, useState } from 'react'
import ExcelJS from 'exceljs'
import { useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, CircleCheck, Download, FileSpreadsheet, ICON, STROKE, Upload } from '../../components/ui/icons'
import { supabase } from '../../lib/supabase'
import { Button, Modal, Spinner, useToast } from '../../components/ui'
import { useCustomers } from '../../lib/queries'

const headers = [
  ['customer_name', 'שם לקוח במערכת'],
  ['end_client_name', 'שם לקוח האירוע'],
  ['event_number', 'מספר אירוע'],
  ['event_date', 'תאריך אירוע (YYYY-MM-DD)'],
  ['location_text', 'מיקום'],
  ['location_notes', 'הערות למיקום'],
  ['volume_m', 'נפח במטר'],
  ['truck_count', 'כמות משאיות'],
  ['contact_name', 'איש קשר'],
  ['contact_phone', 'טלפון איש קשר'],
  ['notes', 'הערות'],
] as const

export function ExcelDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const toast = useToast()
  const qc = useQueryClient()
  const { data: customers = [] } = useCustomers()
  const fileRef = useRef<HTMLInputElement>(null)
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState<{ imported: number; errors: { row: number; error: string }[] } | null>(null)

  const exportEvents = async () => {
    setBusy(true)
    try {
      const { data, error } = await supabase
        .from('events')
        .select('*, customers(name), event_contacts(contact_name, contact_phone)')
        .is('deleted_at', null)
        .order('event_date', { ascending: false })
        .limit(5000)
      if (error) throw error

      const wb = new ExcelJS.Workbook()
      const ws = wb.addWorksheet('אירועים', { views: [{ rightToLeft: true }] })
      ws.columns = headers.map(([key, label]) => ({ header: label, key, width: 20 }))
      ws.getRow(1).font = { bold: true }
      for (const e of data as Record<string, unknown>[]) {
        const contact = e.event_contacts as { contact_name?: string; contact_phone?: string } | null
        ws.addRow({
          customer_name: (e.customers as { name: string } | null)?.name ?? '',
          end_client_name: e.end_client_name ?? '',
          event_number: e.event_number ?? '',
          event_date: e.event_date ?? '',
          location_text: e.location_text ?? '',
          location_notes: e.location_notes ?? '',
          volume_m: e.volume_m ?? '',
          truck_count: e.truck_count ?? '',
          contact_name: contact?.contact_name ?? '',
          contact_phone: contact?.contact_phone ?? '',
          notes: e.notes ?? '',
        })
      }
      const buf = await wb.xlsx.writeBuffer()
      const blob = new Blob([buf], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' })
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `events-${new Date().toISOString().slice(0, 10)}.xlsx`
      a.click()
      URL.revokeObjectURL(url)
    } catch (e) {
      toast.error((e as Error).message)
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
      const ws = wb.worksheets[0]
      if (!ws) throw new Error('הקובץ ריק')

      const rows: Record<string, unknown>[] = []
      ws.eachRow((row, rowNumber) => {
        if (rowNumber === 1) return
        const values = row.values as ExcelJS.CellValue[]
        const rec: Record<string, unknown> = {}
        headers.forEach(([key], i) => {
          let v = values[i + 1]
          if (v && typeof v === 'object' && 'text' in v) v = (v as { text: string }).text
          if (v instanceof Date) v = v.toISOString().slice(0, 10)
          rec[key] = v == null ? '' : String(v).trim()
        })
        if (Object.values(rec).some((v) => v !== '')) rows.push(rec)
      })
      if (rows.length === 0) throw new Error('לא נמצאו שורות לייבוא')

      // resolve customer names -> ids
      const payloads = rows.map((r) => {
        const customer = customers.find((c) => c.name === r.customer_name)
        return { ...r, customer_id: customer?.id ?? null, customer_name: undefined }
      })
      const missing = payloads.filter((p) => !p.customer_id)
      if (missing.length) {
        throw new Error(`לקוחות לא מוכרים בקובץ: ${[...new Set(missing.map((m) => m.customer_name ?? rows[payloads.indexOf(m)]?.customer_name))].join(', ') || 'שם לקוח חסר'}`)
      }

      const { data, error } = await supabase.rpc('bulk_import_events', { p_rows: payloads })
      if (error) throw error
      setResult(data as { imported: number; errors: { row: number; error: string }[] })
      void qc.invalidateQueries({ queryKey: ['events'] })
      void qc.invalidateQueries({ queryKey: ['calendar'] })
      void qc.invalidateQueries({ queryKey: ['workboard'] })
    } catch (e) {
      toast.error((e as Error).message)
    } finally {
      setBusy(false)
      if (fileRef.current) fileRef.current.value = ''
    }
  }

  const downloadTemplate = async () => {
    const wb = new ExcelJS.Workbook()
    const ws = wb.addWorksheet('אירועים', { views: [{ rightToLeft: true }] })
    ws.columns = headers.map(([key, label]) => ({ header: label, key, width: 20 }))
    ws.getRow(1).font = { bold: true }
    const buf = await wb.xlsx.writeBuffer()
    const blob = new Blob([buf], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'events-template.xlsx'
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="ייבוא / ייצוא אירועים"
      description="קובצי Excel בפורמט xlsx, עם כותרות בעברית"
      footer={<Button onClick={onClose}>סגירה</Button>}
    >
      {busy ? (
        <div className="flex flex-col items-center gap-3 py-10">
          <Spinner size={28} />
          <p className="type-body text-ink-secondary">מעבד את הקובץ...</p>
        </div>
      ) : (
        <div className="space-y-4">
          <div className="grid gap-2 sm:grid-cols-3">
            <ActionTile
              icon={<Download size={ICON.xl} strokeWidth={STROKE} />}
              title="ייצוא אירועים"
              description="כל האירועים הפעילים לקובץ"
              onClick={() => void exportEvents()}
            />
            <ActionTile
              icon={<FileSpreadsheet size={ICON.xl} strokeWidth={STROKE} />}
              title="הורדת תבנית"
              description="קובץ ריק עם הכותרות הנכונות"
              onClick={() => void downloadTemplate()}
            />
            <ActionTile
              icon={<Upload size={ICON.xl} strokeWidth={STROKE} />}
              title="ייבוא מקובץ"
              description="בחירת xlsx להעלאה"
              primary
              onClick={() => fileRef.current?.click()}
            />
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
              הייבוא מזהה לקוח לפי "שם לקוח במערכת" ומחיל את שדות החובה שהוגדרו לכל לקוח.
              כל אירוע שנוצר מקבל אוטומטית משימות הקמה ופירוק.
            </p>
          </div>

          {result && (
            <div className="space-y-2">
              <div className="flex items-center gap-2 rounded-lg border border-success-border bg-success-subtle px-3 py-2.5">
                <CircleCheck size={ICON.md} className="shrink-0 text-success-text" strokeWidth={STROKE} />
                <p className="type-body font-medium text-success-text">
                  {result.imported} אירועים יובאו בהצלחה
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
