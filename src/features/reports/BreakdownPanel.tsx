import { useState } from 'react'
import { Card, CardBody, CardHeader, DataTable, EmptyState, IconButton, SegmentedControl, Skeleton } from '../../components/ui'
import { BarChart3, Download, ICON, List, STROKE } from '../../components/ui/icons'
import { errorMessage } from '../../lib/errors'
import { pctDelta } from '../../components/ui/format'
import { Disclosures } from '../dashboard/builder/CustomWidget'
import { VIZ_RENDERERS, formatValue } from '../dashboard/builder/viz/vizRenderers'
import { effectiveViz } from '../dashboard/builder/widgetSpec'
import { csvBlob } from './exportCsv'
import { panelToSheet } from './exportReports'
import { downloadBlob } from './download'
import type { RunRow } from '../dashboard/builder/widgetSpec'
import type { PanelRun } from './useReportRuns'

/**
 * פילוח אחד על המסך: גרף או טבלה, לבחירת הקורא, מעל אותה תשובת שרת.
 *
 * שלוש התוצאות של המנוע מטופלות כמו ב-`CustomWidget`, עם הבדל אחד מכוון:
 * `denied` שם מעלים את הווידג׳ט כולו, וכאן הפאנל נשאר עם הודעה שקטה — במסך
 * שכולו פילוחים שבחרת, פאנל שנעלם בלי מילה נקרא כתקלה ולא כהרשאה.
 */

interface RowPair {
  row: RunRow
  prev: number | null
  delta: number | null
}

export function BreakdownPanel({
  panel,
  title,
  canExport,
}: {
  panel: PanelRun
  title: string
  canExport: boolean
}) {
  const [view, setView] = useState<'chart' | 'table'>('chart')
  const { current, previous, spec, error } = panel

  const exportCsv = () => {
    const sheet = panelToSheet(
      { title, result: current, previous },
      !!previous,
      new Set(),
    )
    if (sheet) downloadBlob(csvBlob(sheet), `${title}.csv`)
  }

  const body = () => {
    if (error) return <p className="p-4 type-caption text-error">{errorMessage(error)}</p>
    if (current === undefined) return <Skeleton className="m-4 h-56" />
    if (current.rows === null) {
      return (
        <EmptyState
          compact
          art="table"
          title={current.meta?.unsupported ? 'הנתון המבוקש אינו קיים בקטלוג' : 'הנתון אינו זמין בהרשאות שלך'}
          description={current.meta?.unsupported ? `הנתון החסר: ${current.meta.unsupported}` : undefined}
        />
      )
    }
    if (current.rows.length === 0) {
      return <EmptyState compact art="box" title="אין נתונים בטווח שנבחר" />
    }

    if (view === 'table') return <PanelTable panel={panel} title={title} />

    const viz = effectiveViz(spec)
    const Renderer = viz === 'note' ? VIZ_RENDERERS.table : VIZ_RENDERERS[viz]
    return (
      <div className={panel.isFetching ? 'opacity-50 transition-opacity' : 'transition-opacity'}>
        <Renderer
          spec={spec}
          rows={current.rows}
          meta={current.meta ?? {}}
          height={260}
          title={title}
          notice={<Disclosures meta={current.meta ?? {}} />}
        />
      </div>
    )
  }

  const showToggle = current?.rows != null && current.rows.length > 0

  return (
    <Card className="print-panel">
      <CardHeader
        title={title}
        subtitle={current?.rows != null ? totalLine(panel) : undefined}
        actions={
          <div className="flex items-center gap-1.5 print:hidden">
            {canExport && showToggle && (
              <IconButton label={`הורדת CSV — ${title}`} size="sm" variant="ghost" onClick={exportCsv}>
                <Download size={ICON.sm} strokeWidth={STROKE} />
              </IconButton>
            )}
            {showToggle && (
              <SegmentedControl
                items={[
                  { key: 'chart', label: <BarChart3 size={ICON.sm} aria-label="גרף" /> },
                  { key: 'table', label: <List size={ICON.sm} aria-label="טבלה" /> },
                ]}
                value={view}
                onChange={setView}
              />
            )}
          </div>
        }
      />
      <CardBody padded={false}>{body()}</CardBody>
    </Card>
  )
}

/** "סך הכול 12,340 ₪ · תקופה קודמת 9,800 ₪" — מספרי השרת, לא סכימת שורות */
function totalLine(panel: PanelRun): string | undefined {
  const meta = panel.current?.meta
  if (!meta || meta.total === null || meta.total === undefined) return undefined
  let line = `סך הכול ${formatValue(Number(meta.total), meta)}`
  const prevTotal = panel.previous?.meta?.total
  if (prevTotal !== null && prevTotal !== undefined) {
    line += ` · תקופה קודמת ${formatValue(Number(prevTotal), meta)}`
    const delta = pctDelta(Number(meta.total), Number(prevTotal))
    if (delta !== null) line += ` (${delta > 0 ? '+' : ''}${delta}%)`
  }
  return line
}

function PanelTable({ panel, title }: { panel: PanelRun; title: string }) {
  const rows = panel.current?.rows ?? []
  const meta = panel.current?.meta ?? {}
  const withPrev = panel.previous?.rows != null
  const prevByKey = new Map((panel.previous?.rows ?? []).map((r) => [r.key ?? r.label, r.value]))

  const data: RowPair[] = rows.map((row) => {
    const prev = withPrev ? (prevByKey.get(row.key ?? row.label) ?? null) : null
    return {
      row,
      prev,
      delta: row.value !== null && prev !== null ? pctDelta(Number(row.value), Number(prev)) : null,
    }
  })

  return (
    <div className="p-2">
      <DataTable<RowPair>
        rows={data}
        getRowId={(r) => r.row.key ?? r.row.label}
        pageSize={0}
        zebra
        dense
        columns={[
          {
            key: 'label',
            header: title,
            fixed: true,
            render: (r) => (
              <span className="flex items-center gap-2">
                {r.row.color && <span aria-hidden className="size-2.5 shrink-0 rounded-full" style={{ background: r.row.color }} />}
                {r.row.label}
              </span>
            ),
            sortValue: (r) => r.row.label,
          },
          {
            key: 'value',
            header: 'ערך',
            align: 'end',
            render: (r) => <span className="tabular">{formatValue(r.row.value === null ? null : Number(r.row.value), meta)}</span>,
            sortValue: (r) => (r.row.value === null ? null : Number(r.row.value)),
          },
          ...(withPrev
            ? [
                {
                  key: 'prev',
                  header: 'תקופה קודמת',
                  align: 'end' as const,
                  render: (r: RowPair) => (
                    <span className="tabular">{r.prev === null ? '—' : formatValue(Number(r.prev), meta)}</span>
                  ),
                  sortValue: (r: RowPair) => (r.prev === null ? null : Number(r.prev)),
                },
                {
                  key: 'delta',
                  header: 'שינוי',
                  align: 'end' as const,
                  render: (r: RowPair) =>
                    r.delta === null ? (
                      <span className="text-ink-tertiary">—</span>
                    ) : (
                      <span className={`tabular ${r.delta >= 0 ? 'text-success-text' : 'text-error-text'}`}>
                        {r.delta > 0 ? '+' : ''}
                        {r.delta}%
                      </span>
                    ),
                  sortValue: (r: RowPair) => r.delta,
                },
              ]
            : []),
          {
            key: 'n',
            header: 'שורות',
            align: 'end',
            render: (r) => <span className="tabular text-ink-tertiary">{r.row.n.toLocaleString('he-IL')}</span>,
            sortValue: (r) => r.row.n,
          },
        ]}
      />
      <div className="px-3 pb-2 pt-1">
        <Disclosures meta={meta} />
      </div>
    </div>
  )
}
