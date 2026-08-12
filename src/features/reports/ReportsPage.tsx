import { useEffect, useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'react-router'
import {
  Button,
  Checkbox,
  EmptyState,
  Input,
  MenuItem,
  MultiSelect,
  PageHeader,
  Popover,
  Select,
  Skeleton,
  StatCard,
  useToast,
} from '../../components/ui'
import { BarChart3, ChevronDown, Download, FileSpreadsheet, ICON, Printer, STROKE, TrendingUp } from '../../components/ui/icons'
import { fmtDate } from '../../lib/dates'
import { errorMessage } from '../../lib/errors'
import { PERM } from '../../lib/permissions'
import { useAuth } from '../../state/auth'
import { RequirePermission } from '../auth/guards'
import { FilterRows } from '../dashboard/builder/FilterRows'
import { useReportCatalog } from '../dashboard/builder/useReportCatalog'
import { formatValue } from '../dashboard/builder/viz/vizRenderers'
import {
  AGG_LABELS,
  BUCKETS,
  BUCKET_LABELS,
  dimensionsFor,
  filterableFields,
} from '../dashboard/builder/widgetSpec'
import { RANGE_PRESETS } from '../dashboard/dashboardRange'
import { pctDelta } from '../../components/ui/format'
import { BreakdownPanel } from './BreakdownPanel'
import { SavedReportsMenu } from './SavedReportsMenu'
import { downloadBlob } from './download'
import { buildReportExport } from './exportReports'
import {
  MAX_DIMS,
  autoBucket,
  fieldOf,
  measureOf,
  normalizeReportState,
  stateFromParam,
  stateToParam,
  summaryAllowed,
} from './reportState'
import { DOMAIN_LABELS, DOMAIN_ORDER, REPORT_TEMPLATES, stateFromTemplate, templatesByDomain } from './reportTemplates'
import { useReportRuns } from './useReportRuns'
import type { Filter } from '../dashboard/builder/widgetSpec'
import type { ReportState } from './reportState'
import type { ReportDomain } from './reportTemplates'
import type { PanelRun } from './useReportRuns'

/**
 * מסך הדוחות: מדד אחד, עד ארבעה פילוחים במקביל, ייצוא.
 *
 * לקוח קריאה-בלבד מעל מנוע הדוחות של 0043/0044 — אותו קטלוג, אותם specs
 * ואותם רנדררים של בונה הווידג׳טים, בלי מנוע שני ובלי הכרעת הרשאה בלקוח.
 * כל ה-state יושב ב-URL (פרמטר `r`), ולכן דוח הוא קישור: מי שפותח אותו
 * מקבל את *השאילתה*, והשרת עונה לו לפי ההרשאות שלו.
 */

export default function ReportsPage() {
  return (
    <RequirePermission perm={PERM.REPORTS_VIEW}>
      <ReportsScreen />
    </RequirePermission>
  )
}

function ReportsScreen() {
  const has = useAuth((s) => s.has)
  const toast = useToast()
  const canExport = has(PERM.REPORTS_EXPORT)
  const { catalog, isLoading: catalogLoading } = useReportCatalog()

  const [params, setParams] = useSearchParams()
  const [state, setState] = useState<ReportState | null>(() => stateFromParam(params.get('r')))
  const [domain, setDomain] = useState<ReportDomain>('ops')

  /* פותחים על התבנית הראשונה כשאין state ב-URL. מחוץ ל-render כי זה תלוי
     בקטלוג רק להצגה — התבנית עצמה סטטית. */
  useEffect(() => {
    if (!state) setState(stateFromTemplate(REPORT_TEMPLATES[0]))
  }, [state])

  /* ה-state ⇄ URL: replace, לא push — כל הקשה בפילטר אינה צעד היסטוריה */
  const skipUrl = useRef(true)
  useEffect(() => {
    if (!state) return
    if (skipUrl.current) {
      skipUrl.current = false
      return
    }
    setParams({ r: stateToParam(state) }, { replace: true })
  }, [state, setParams])

  if (!state) return <Skeleton className="h-72 w-full" />
  return (
    <ReportsBody
      state={state}
      setState={setState}
      domain={domain}
      setDomain={setDomain}
      catalogLoading={catalogLoading}
      catalog={catalog}
      canExport={canExport}
      toastError={(e: unknown) => toast.error(errorMessage(e))}
    />
  )
}

function ReportsBody({
  state,
  setState,
  domain,
  setDomain,
  catalog,
  catalogLoading,
  canExport,
  toastError,
}: {
  state: ReportState
  setState: (s: ReportState) => void
  domain: ReportDomain
  setDomain: (d: ReportDomain) => void
  catalog: ReturnType<typeof useReportCatalog>['catalog']
  catalogLoading: boolean
  canExport: boolean
  toastError: (e: unknown) => void
}) {
  const measure = measureOf(catalog, state)
  const dims = dimensionsFor(catalog, measure)
  const fields = filterableFields(catalog, state.source)
  const ready = !catalogLoading && !!measure

  const blocked = state.dims.length === 0 && ready && !summaryAllowed(state, catalog)
  const { panels, debouncedState } = useReportRuns(state, catalog, ready && !blocked)

  const panelTitle = (field: string | null | undefined) =>
    field ? (fieldOf(catalog, field)?.label_he ?? field) : (measure?.label_he ?? state.measure)

  const first = panels.find((p) => p.current?.rows != null)
  const anyTimeDim = state.dims.some((d) => fieldOf(catalog, d.field)?.kind === 'time')

  /* ── מעברי מדד ─────────────────────────────────────────────────────── */

  const setMeasure = (key: string) => {
    const m = catalog.measures.find((x) => x.key === key)
    if (!m) return
    if (m.source_key !== state.source) {
      // מקור חדש מפסיל פילוחים וסינונים — מתחילים נקי, כמו בבונה
      setState({
        ...state,
        source: m.source_key,
        measure: m.key,
        agg: m.default_agg,
        dims: [],
        filters: [],
      })
      return
    }
    // אותו מקור: פילוח שהמדד החדש אינו נושא נשמט, השאר נשארים
    const legal = dimensionsFor(catalog, m)
    setState({
      ...state,
      measure: m.key,
      agg: m.allowed_aggs.includes(state.agg) ? state.agg : m.default_agg,
      dims: state.dims.filter((d) => legal.some((f) => f.key === d.field)),
    })
  }

  const toggleDim = (key: string) => {
    const exists = state.dims.some((d) => d.field === key)
    if (exists) {
      setState({ ...state, dims: state.dims.filter((d) => d.field !== key) })
    } else if (state.dims.length < MAX_DIMS) {
      setState({ ...state, dims: [...state.dims, { field: key }] })
    }
  }

  const setRange = (from: string, to: string) => {
    if (!from || !to || to < from) return
    setState({ ...state, range: { from, to }, bucket: autoBucket({ from, to }) })
  }

  const applyTemplate = (key: string) => {
    const t = REPORT_TEMPLATES.find((x) => x.key === key)
    if (t) setState(stateFromTemplate(t, state.range))
  }

  /* ── ייצוא ─────────────────────────────────────────────────────────── */

  const exportXlsx = async () => {
    try {
      const plan = buildReportExport(
        debouncedState,
        panels.map((p) => ({ title: p.dim ? panelTitle(p.dim.field) : null, result: p.current, previous: p.previous })),
        catalog,
      )
      const { writeDashboardExport } = await import('../dashboard/exportDashboard')
      downloadBlob(await writeDashboardExport(plan), `דוחות-${state.range.from}-${state.range.to}.xlsx`)
    } catch (e) {
      toastError(e)
    }
  }

  /* ── המסך ──────────────────────────────────────────────────────────── */

  return (
    <div className="space-y-4">
      {/* כותרת שמודפסת בלבד: הקובץ צריך לומר מה הוא גם בלי המסך מסביב */}
      <div className="hidden print:block">
        <h1 className="type-heading">{measure?.label_he ?? 'דוח'}</h1>
        <p className="type-caption">
          {fmtDate(state.range.from)} – {fmtDate(state.range.to)} · הופק {fmtDate(new Date().toISOString().slice(0, 10))}
        </p>
      </div>

      <div className="print:hidden">
        <PageHeader
          title="דוחות"
          subtitle={`${fmtDate(state.range.from)} – ${fmtDate(state.range.to)}`}
          actions={
            <>
              <SavedReportsMenu state={state} onApply={(s) => setState(normalizeReportState(s))} />
              {canExport && (
                <Popover
                  trigger={(props) => (
                    <Button onClick={props.toggle} aria-expanded={props['aria-expanded']} aria-haspopup="menu">
                      <Download size={ICON.sm} strokeWidth={STROKE} />
                      ייצוא
                      <ChevronDown size={ICON.sm} strokeWidth={STROKE} />
                    </Button>
                  )}
                >
                  {(close) => (
                    <>
                      <MenuItem
                        icon={<FileSpreadsheet size={ICON.sm} strokeWidth={STROKE} />}
                        onClick={() => {
                          close()
                          void exportXlsx()
                        }}
                      >
                        Excel — כל הפילוחים
                      </MenuItem>
                      <MenuItem
                        icon={<Printer size={ICON.sm} strokeWidth={STROKE} />}
                        onClick={() => {
                          close()
                          window.print()
                        }}
                      >
                        PDF / הדפסה
                      </MenuItem>
                    </>
                  )}
                </Popover>
              )}
            </>
          }
        >
          {/* ── תבניות ── */}
          <div className="space-y-2">
            <div className="scroll-row flex items-center gap-1.5">
              {DOMAIN_ORDER.map((d) => (
                <button
                  key={d}
                  type="button"
                  onClick={() => setDomain(d)}
                  aria-pressed={domain === d}
                  className={`shrink-0 rounded-full border px-3 py-1.5 type-button transition-colors ${
                    domain === d
                      ? 'border-primary bg-primary/10 text-primary-text'
                      : 'border-line text-ink-secondary hover:bg-hover'
                  }`}
                >
                  {DOMAIN_LABELS[d]}
                </button>
              ))}
            </div>
            <div className="scroll-row flex items-center gap-1.5">
              {templatesByDomain(domain).map((t) => {
                const active = t.measure === state.measure && t.source === state.source
                return (
                  <button
                    key={t.key}
                    type="button"
                    title={t.hint}
                    onClick={() => applyTemplate(t.key)}
                    aria-pressed={active}
                    className={`shrink-0 rounded-lg border px-2.5 py-1.5 type-caption font-medium transition-colors ${
                      active
                        ? 'border-primary/50 bg-primary/5 text-primary-text'
                        : 'border-line-subtle text-ink-secondary hover:bg-hover'
                    }`}
                  >
                    {t.title}
                  </button>
                )
              })}
            </div>
          </div>
        </PageHeader>
      </div>

      {/* ── הבקרות ── */}
      <div className="surface space-y-3 p-3 print:hidden">
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <label className="block">
            <span className="mb-1 block type-caption font-medium text-ink-secondary">מה למדוד</span>
            {catalogLoading ? (
              <Skeleton className="h-9 w-full" />
            ) : (
              <Select value={state.measure} onChange={(e) => setMeasure(e.target.value)}>
                {catalog.sources.map((s) => (
                  <optgroup key={s.key} label={s.label_he}>
                    {catalog.measures
                      .filter((m) => m.source_key === s.key)
                      .map((m) => (
                        <option key={m.key} value={m.key}>
                          {m.label_he}
                        </option>
                      ))}
                  </optgroup>
                ))}
              </Select>
            )}
          </label>

          {(measure?.allowed_aggs.length ?? 0) > 1 && (
            <label className="block">
              <span className="mb-1 block type-caption font-medium text-ink-secondary">סוג החישוב</span>
              <Select value={state.agg} onChange={(e) => setState({ ...state, agg: e.target.value as ReportState['agg'] })}>
                {(measure?.allowed_aggs ?? []).map((a) => (
                  <option key={a} value={a}>
                    {AGG_LABELS[a]}
                  </option>
                ))}
              </Select>
            </label>
          )}

          <div className="block sm:col-span-2">
            <span className="mb-1 block type-caption font-medium text-ink-secondary">
              פילוחים <span className="text-ink-tertiary">(עד {MAX_DIMS} במקביל)</span>
            </span>
            <MultiSelect
              options={dims.map((f) => ({ id: f.key, label: f.label_he }))}
              values={state.dims.map((d) => d.field)}
              onToggle={toggleDim}
              placeholder={dims.length === 0 ? 'המדד הזה אינו ניתן לפילוח' : 'בחירת פילוחים…'}
              disabled={dims.length === 0}
            />
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
          <div className="flex items-center gap-1.5">
            {RANGE_PRESETS.map((p) => (
              <Button key={p.label} size="sm" variant="ghost" onClick={() => {
                const r = p.range()
                setRange(r.from, r.to)
              }}>
                {p.label}
              </Button>
            ))}
          </div>
          <div className="flex items-center gap-1.5">
            <Input
              type="date"
              aria-label="מתאריך"
              value={state.range.from}
              onChange={(e) => setRange(e.target.value, state.range.to)}
            />
            <span className="text-ink-tertiary">–</span>
            <Input
              type="date"
              aria-label="עד תאריך"
              value={state.range.to}
              onChange={(e) => setRange(state.range.from, e.target.value)}
            />
          </div>
          {anyTimeDim && (
            <Select
              aria-label="קיבוץ זמן"
              value={state.bucket}
              onChange={(e) => setState({ ...state, bucket: e.target.value as ReportState['bucket'] })}
            >
              {BUCKETS.map((b) => (
                <option key={b} value={b}>
                  {BUCKET_LABELS[b]}
                </option>
              ))}
            </Select>
          )}
          <Checkbox
            label="השוואה לתקופה הקודמת"
            checked={state.compare}
            onChange={(on) => setState({ ...state, compare: on })}
          />
        </div>

        {fields.length > 0 && (
          <FilterRows fields={fields} filters={state.filters} onChange={(next: Filter[]) => setState({ ...state, filters: next })} />
        )}
      </div>

      {/* ── שורת הסיכום ── */}
      <SummaryRow state={state} first={first} measureLabel={measure?.label_he} />

      {/* ── הפאנלים ── */}
      {blocked ? (
        <EmptyState
          art="table"
          title="המדד הזה מחייב פילוח"
          description="בחרו לפחות פילוח אחד כדי להציג את הדוח"
        />
      ) : (
        <div className={`grid gap-4 ${panels.length > 1 ? 'lg:grid-cols-2' : ''}`}>
          {panels.map((p) => (
            <BreakdownPanel
              key={p.dim?.field ?? '__summary__'}
              panel={p}
              title={panelTitle(p.dim?.field)}
              canExport={canExport}
            />
          ))}
        </div>
      )}
    </div>
  )
}

/** שני המספרים שמעל הפאנלים — של השרת, מהפאנל הראשון שענה */
function SummaryRow({
  state,
  first,
  measureLabel,
}: {
  state: ReportState
  first?: PanelRun
  measureLabel?: string
}) {
  const meta = first?.current?.meta
  const prevMeta = first?.previous?.meta

  const total = meta?.total
  const prevTotal = prevMeta?.total
  const delta = useMemo(
    () =>
      total !== null && total !== undefined && prevTotal !== null && prevTotal !== undefined
        ? pctDelta(Number(total), Number(prevTotal))
        : null,
    [total, prevTotal],
  )

  if (total === null || total === undefined) return null
  return (
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
      <StatCard
        icon={<BarChart3 size={ICON.xl} strokeWidth={STROKE} />}
        label={measureLabel ?? 'סך הכול'}
        value={formatValue(Number(total), meta ?? {})}
        hint={`${state.range.from} – ${state.range.to}`}
      />
      {state.compare && prevTotal !== null && prevTotal !== undefined && (
        <StatCard
          icon={<TrendingUp size={ICON.xl} strokeWidth={STROKE} />}
          label="תקופה קודמת"
          value={formatValue(Number(prevTotal), meta ?? {})}
          delta={delta}
        />
      )}
    </div>
  )
}
