import { useEffect, useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Button,
  Checkbox,
  Drawer,
  Field,
  Input,
  SegmentedControl,
  Select,
  Skeleton,
  Switch,
  Textarea,
  useToast,
} from '../../../components/ui'
import { AlertTriangle, Calculator, ICON, STROKE } from '../../../components/ui/icons'
import { errorMessage } from '../../../lib/errors'
import { PERM } from '../../../lib/permissions'
import { supabase } from '../../../lib/supabase'
import { useAuth } from '../../../state/auth'
import { FilterRows } from './FilterRows'
import { VIZ_RENDERERS } from './viz/vizRenderers'
import {
  AGG_LABELS,
  BUCKETS,
  BUCKET_LABELS,
  MAX_NOTE,
  VIZ_KINDS,
  allowsNoDimension,
  blankNoteSpec,
  blankQuerySpec,
  dimensionsFor,
  effectiveViz,
  filterableFields,
  isNote,
  isQuery,
  normalizeSpec,
  specProblems,
  specTitle,
  vizAllows,
} from './widgetSpec'
import type {
  Agg,
  Bucket,
  Catalog,
  Filter,
  QuerySpec,
  RunResult,
  VizKind,
  WidgetSpec,
} from './widgetSpec'
import type { DateRange } from '../dashboardRange'
import type { CustomWidgetRow, SaveWidgetInput } from './useCustomWidgets'

/**
 * The builder.
 *
 * Structurally a copy of `PricingTab`: a draft that falls back to the saved
 * value, a `patch` helper, add/remove/reorder rows, and a preview panel keyed
 * on a debounced copy of the draft. Two of those are load-bearing rather than
 * cosmetic:
 *
 *   • **The preview takes the draft as an RPC argument**, so nothing has to be
 *     saved to see a number — `preview_task_price(p_config, p_vars)` exactly.
 *     It is safe because `app.report_run` gates every field itself, whatever
 *     the client sends.
 *   • **`muted` while fetching**, not a skeleton. A chart that disappears on
 *     every keystroke reads as broken; one that dims reads as thinking.
 *
 * The pickers are filtered by the same `allowed_dims` the server validates
 * against, fetched from the server — so an illegal combination cannot be
 * offered. The server still rejects it, because the UI is not the boundary.
 */

const VIZ_LABELS: Record<VizKind, string> = {
  number: 'מספר',
  gauge: 'מד יעד',
  bar: 'עמודות',
  row: 'עמודות אופקיות',
  line: 'קו',
  area: 'שטח',
  donut: 'טבעת',
  table: 'טבלה',
  note: 'פתק',
}

export interface BuilderTarget {
  /** editing an existing row, or null for a new one */
  row: CustomWidgetRow | null
  /** 'note' starts a free-text widget instead of a query */
  variant?: 'query' | 'note'
}

export function WidgetBuilderDrawer({
  open,
  target,
  catalog,
  catalogLoading,
  range,
  onClose,
  onSave,
  saving,
}: {
  open: boolean
  target: BuilderTarget | null
  catalog: Catalog
  catalogLoading: boolean
  range: DateRange
  onClose: () => void
  onSave: (input: SaveWidgetInput) => Promise<unknown>
  saving: boolean
}) {
  const has = useAuth((s) => s.has)
  const toast = useToast()
  const canShare = has(PERM.DASHBOARD_SHARE_WIDGET)

  const [spec, setSpec] = useState<WidgetSpec>(() => blankNoteSpec())
  const [title, setTitle] = useState('')
  const [subtitle, setSubtitle] = useState('')
  const [shared, setShared] = useState(false)
  /* Once the author types a title of their own, the generated one stops
     overwriting it. Anything else quietly discards what they wrote. */
  const [titleTouched, setTitleTouched] = useState(false)

  useEffect(() => {
    if (!open || !target) return
    const initial = target.row
      ? normalizeSpec(target.row.spec)
      : target.variant === 'note'
        ? blankNoteSpec()
        : blankQuerySpec(catalog)
    setSpec(initial)
    setTitle(target.row?.title ?? '')
    setSubtitle(target.row?.subtitle ?? '')
    setShared(target.row?.shared ?? false)
    setTitleTouched(!!target.row)
    // catalog is intentionally out of the deps: reopening should not reset a
    // draft because a background refetch of the catalogue resolved
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, target])

  const auto = useMemo(() => specTitle(spec, catalog), [spec, catalog])
  const effectiveTitle = titleTouched && title.trim() ? title.trim() : auto
  const problems = useMemo(() => specProblems(spec, catalog), [spec, catalog])
  const blocking = problems.filter((p) => !p.unknown)

  const submit = async () => {
    try {
      await onSave({ id: target?.row?.id, title: effectiveTitle, subtitle, spec, shared })
      toast.success(target?.row ? 'הווידג׳ט עודכן' : 'הווידג׳ט נוסף לדשבורד')
      onClose()
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  return (
    <Drawer
      open={open}
      onClose={onClose}
      width="max-w-3xl"
      title={target?.row ? 'עריכת ווידג׳ט' : 'ווידג׳ט חדש'}
      description={
        isNote(spec)
          ? 'פתק טקסט חופשי — לא נשלפים נתונים'
          : 'בחרו מה למדוד, לפי מה לפלח, ובאיזו צורה להציג'
      }
      footer={
        <div className="flex items-center gap-2">
          <Button onClick={() => void submit()} disabled={saving || blocking.length > 0}>
            {target?.row ? 'שמירה' : 'הוספה לדשבורד'}
          </Button>
          <Button variant="ghost" onClick={onClose}>
            ביטול
          </Button>
          {blocking.length > 0 && (
            <span className="type-caption text-ink-tertiary">{blocking[0].message}</span>
          )}
        </div>
      }
    >
      <div className="space-y-5 p-4 sm:p-5">
        {catalogLoading && !isNote(spec) ? (
          <Skeleton className="h-40 w-full" />
        ) : isNote(spec) ? (
          <NoteEditor
            body={spec.body}
            tone={spec.tone ?? 'default'}
            onChange={(patch) => setSpec((s) => (isNote(s) ? { ...s, ...patch } : s))}
          />
        ) : isQuery(spec) ? (
          <QueryEditor spec={spec} catalog={catalog} onChange={setSpec} />
        ) : null}

        {/* ===== identity ===== */}
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="כותרת" hint={titleTouched ? undefined : `ברירת מחדל: ${auto}`}>
            <Input
              value={titleTouched ? title : auto}
              onChange={(e) => {
                setTitleTouched(true)
                setTitle(e.target.value)
              }}
              maxLength={60}
            />
          </Field>
          <Field label="כותרת משנה" hint="לא חובה">
            <Input value={subtitle} onChange={(e) => setSubtitle(e.target.value)} maxLength={120} />
          </Field>
        </div>

        {/* Sharing publishes a *query*, not a layout — and it is still safe,
            because every reader re-runs it against their own keys. The card
            says both halves so nobody has to guess. */}
        {canShare && (
          <div className="rounded-xl border border-line-subtle bg-subtle/30 p-3">
            <Switch
              checked={shared}
              onChange={setShared}
              label="זמין לכל הארגון"
              description="כל קורא רואה את הנתונים לפי ההרשאות שלו; למי שאין הרשאה הווידג׳ט פשוט לא יופיע"
            />
          </div>
        )}

        {isQuery(spec) && (
          <PreviewPanel spec={spec} range={range} title={effectiveTitle} problems={blocking.length > 0} />
        )}
      </div>
    </Drawer>
  )
}

/* ===== the note ==========================================================
   No query, no catalogue, no permission beyond reaching the builder.        */

function NoteEditor({
  body,
  tone,
  onChange,
}: {
  body: string
  tone: 'default' | 'info' | 'warn'
  onChange: (p: { body?: string; tone?: 'default' | 'info' | 'warn' }) => void
}) {
  return (
    <div className="space-y-3">
      <Field label="תוכן הפתק" hint={`${body.length}/${MAX_NOTE}`}>
        <Textarea rows={6} value={body} maxLength={MAX_NOTE} onChange={(e) => onChange({ body: e.target.value })} />
      </Field>
      <Field label="גוון">
        <SegmentedControl
          items={[
            { key: 'default', label: 'רגיל' },
            { key: 'info', label: 'מידע' },
            { key: 'warn', label: 'שימו לב' },
          ]}
          value={tone}
          onChange={(k) => onChange({ tone: k })}
        />
      </Field>
    </div>
  )
}

/* ===== the query ========================================================== */

function QueryEditor({
  spec,
  catalog,
  onChange,
}: {
  spec: QuerySpec
  catalog: Catalog
  onChange: (next: QuerySpec) => void
}) {
  const patch = (p: Partial<QuerySpec>) => onChange({ ...spec, ...p })

  const measures = catalog.measures.filter((m) => m.source_key === spec.source)
  const measure = measures.find((m) => m.key === spec.measure)
  const dims = dimensionsFor(catalog, measure)
  const fields = filterableFields(catalog, spec.source)
  const dimField = catalog.fields.find((f) => f.key === spec.dimension?.field)

  /* Changing the source invalidates the measure, the dimension and every
     filter at once — they are all keyed to it. Carrying any of them over
     would produce a spec the server rejects, which is a worse experience than
     starting the row fresh. */
  const setSource = (key: string) => {
    const first = catalog.measures.find((m) => m.source_key === key)
    onChange({
      ...spec,
      source: key,
      measure: first?.key ?? '',
      agg: first?.default_agg ?? 'sum',
      dimension: null,
      filters: [],
      viz: 'number',
    })
  }

  const setMeasure = (key: string) => {
    const m = measures.find((x) => x.key === key)
    const stillLegal = spec.dimension && dimensionsFor(catalog, m).some((f) => f.key === spec.dimension?.field)
    patch({
      measure: key,
      agg: m?.default_agg ?? 'sum',
      // a dimension the new measure cannot carry is dropped rather than kept
      // as something the server would refuse
      dimension: stillLegal ? spec.dimension : null,
      viz: stillLegal ? spec.viz : 'number',
    })
  }

  const setDimension = (key: string) => {
    if (!key) return patch({ dimension: null, viz: 'number' })
    const f = catalog.fields.find((x) => x.key === key)
    const next = f?.kind === 'time' ? ({ type: 'time', field: key, bucket: 'week' } as const) : ({ type: 'cat', field: key } as const)
    patch({
      dimension: next,
      viz: vizAllows(spec.viz, next) ? spec.viz : f?.kind === 'time' ? 'line' : 'bar',
      sort: f?.kind === 'time' ? { by: 'dimension', dir: 'asc' } : { by: 'measure', dir: 'desc' },
    })
  }

  const setFilters = (next: Filter[]) => patch({ filters: next })

  return (
    <div className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-3">
        <Field label="מקור נתונים">
          <Select value={spec.source} onChange={(e) => setSource(e.target.value)}>
            {catalog.sources.map((s) => (
              <option key={s.key} value={s.key}>
                {s.label_he}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="מה למדוד" hint={measure?.hint_he ?? undefined}>
          <Select value={spec.measure} onChange={(e) => setMeasure(e.target.value)}>
            {measures.map((m) => (
              <option key={m.key} value={m.key}>
                {m.label_he}
              </option>
            ))}
          </Select>
        </Field>
        {/* only offered when there is a real choice — a measure with one legal
            aggregate does not need a control that can only say one thing */}
        {(measure?.allowed_aggs.length ?? 0) > 1 && (
          <Field label="סוג החישוב">
            <Select value={spec.agg} onChange={(e) => patch({ agg: e.target.value as Agg })}>
              {(measure?.allowed_aggs ?? []).map((a) => (
                <option key={a} value={a}>
                  {AGG_LABELS[a]}
                </option>
              ))}
            </Select>
          </Field>
        )}
      </div>

      <div className="grid gap-3 sm:grid-cols-3">
        <Field label="פילוח" hint={dims.length === 0 ? 'המדד הזה אינו ניתן לפילוח' : undefined}>
          <Select
            value={spec.dimension?.field ?? ''}
            disabled={dims.length === 0}
            onChange={(e) => setDimension(e.target.value)}
          >
            {allowsNoDimension(measure) && <option value="">ללא — מספר יחיד</option>}
            {dims.map((f) => (
              <option key={f.key} value={f.key}>
                {f.label_he}
              </option>
            ))}
          </Select>
        </Field>
        {spec.dimension?.type === 'time' && (
          <Field label="קיבוץ">
            <Select
              value={spec.dimension.bucket}
              onChange={(e) =>
                patch({ dimension: { type: 'time', field: spec.dimension!.field, bucket: e.target.value as Bucket } })
              }
            >
              {BUCKETS.map((b) => (
                <option key={b} value={b}>
                  {BUCKET_LABELS[b]}
                </option>
              ))}
            </Select>
          </Field>
        )}
        {spec.dimension && (
          <Field label="כמה שורות">
            <Input
              type="number"
              min={1}
              max={50}
              value={spec.limit}
              onChange={(e) => patch({ limit: Number(e.target.value) || 12 })}
            />
          </Field>
        )}
      </div>

      {dimField?.is_estimate && (
        <p className="flex items-start gap-2 rounded-lg bg-amber-500/10 p-2.5 type-caption text-ink-secondary">
          <AlertTriangle size={ICON.sm} strokeWidth={STROKE} className="mt-0.5 shrink-0 text-amber-500" />
          הפילוח הזה הוא הקצאה משוערת. עלות המשמרת מחולקת בין המשימות לפי שעות, ומשמרת ללא משימות אינה משויכת לאיש.
        </p>
      )}

      <FilterRows fields={fields} filters={spec.filters} onChange={setFilters} />

      <VizPicker spec={spec} onChange={patch} />
    </div>
  )
}

/* ===== how to draw it ===================================================== */

function VizPicker({ spec, onChange }: { spec: QuerySpec; onChange: (p: Partial<QuerySpec>) => void }) {
  const dim = spec.dimension ?? null
  const usable = VIZ_KINDS.filter((v) => v !== 'note' && vizAllows(v, dim))

  return (
    <div className="space-y-3">
      <span className="type-body font-semibold text-ink">איך להציג</span>
      <div className="flex flex-wrap gap-1.5">
        {usable.map((v) => (
          <button
            key={v}
            type="button"
            onClick={() => onChange({ viz: v })}
            aria-pressed={spec.viz === v}
            className={`rounded-lg border px-2.5 py-1.5 type-caption font-medium transition-colors ${
              spec.viz === v
                ? 'border-primary bg-primary/10 text-primary-text'
                : 'border-line text-ink-secondary hover:bg-hover'
            }`}
          >
            {VIZ_LABELS[v]}
          </button>
        ))}
      </div>

      <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
        {dim && (
          <Checkbox
            label="צבע לפי הישות"
            checked={spec.viz_opts.palette === 'entity'}
            onChange={(on) => onChange({ viz_opts: { ...spec.viz_opts, palette: on ? 'entity' : 'brand' } })}
          />
        )}
        {dim && (
          <Checkbox
            label="מיון מהגדול לקטן"
            checked={spec.sort.by === 'measure' && spec.sort.dir === 'desc'}
            onChange={(on) =>
              onChange({ sort: on ? { by: 'measure', dir: 'desc' } : { by: 'dimension', dir: 'asc' } })
            }
          />
        )}
        {!dim && (
          <Field label="יעד" className="w-40" hint="לא חובה">
            <Input
              type="number"
              value={spec.goal?.target ?? ''}
              onChange={(e) =>
                onChange({
                  goal: e.target.value === '' ? null : { target: Number(e.target.value), direction: 'up' },
                })
              }
            />
          </Field>
        )}
      </div>
    </div>
  )
}

/* ===== the preview =======================================================
   The one detail that makes a live builder feel solid: the debounced draft is
   the query key, and the result dims rather than disappearing while the next
   one arrives.                                                              */

function PreviewPanel({
  spec,
  range,
  title,
  problems,
}: {
  spec: QuerySpec
  range: DateRange
  title: string
  problems: boolean
}) {
  const [debounced, setDebounced] = useState(spec)

  useEffect(() => {
    const t = setTimeout(() => setDebounced(spec), 350)
    return () => clearTimeout(t)
  }, [spec])

  const { data, isFetching, error } = useQuery({
    queryKey: ['dashboard_widget_preview', debounced, range.from, range.to],
    enabled: !problems && !!debounced.measure,
    queryFn: async (): Promise<RunResult> => {
      const { data, error } = await supabase.rpc('dashboard_widget_preview', {
        p_spec: debounced,
        p_from: range.from,
        p_to: range.to,
      })
      if (error) throw error
      return data as RunResult
    },
  })

  const viz = effectiveViz(debounced)
  const Renderer = viz === 'note' ? VIZ_RENDERERS.table : VIZ_RENDERERS[viz]

  return (
    <div className="rounded-xl border border-line-subtle bg-subtle/30 p-4">
      <div className="mb-3 flex items-center gap-2">
        <Calculator size={ICON.sm} strokeWidth={STROKE} className="text-ink-tertiary" />
        <span className="type-body font-semibold text-ink">תצוגה מקדימה</span>
        <span className="type-caption text-ink-tertiary">
          נתונים אמיתיים, בטווח שעל המסך — {range.from} – {range.to}
        </span>
      </div>

      {error ? (
        <p className="type-caption text-error">{errorMessage(error)}</p>
      ) : !data ? (
        <Skeleton className="h-40 w-full" />
      ) : data.rows === null ? (
        /* denied is not an error and not a zero: the widget is buildable, this
           reader simply would not see it. Saying so is more useful than an
           empty chart. */
        <p className="type-caption text-ink-tertiary">
          {data.meta?.unsupported
            ? 'הנתון המבוקש אינו קיים בקטלוג'
            : 'אין לך הרשאה לנתון הזה — הווידג׳ט לא יופיע אצלך'}
        </p>
      ) : (
        <div className={isFetching ? 'opacity-50 transition-opacity' : 'transition-opacity'}>
          <Renderer spec={debounced} rows={data.rows} meta={data.meta ?? {}} height={220} title={title} />
        </div>
      )}
    </div>
  )
}
