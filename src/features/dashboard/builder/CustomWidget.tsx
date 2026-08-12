import { Card, CardBody, CardHeader, EmptyState, SkeletonCard } from '../../../components/ui'
import { AlertTriangle, ICON, STROKE } from '../../../components/ui/icons'
import { useCustomResult } from '../dashboardContext'
import { VIZ_RENDERERS, formatValue } from './viz/vizRenderers'
import { disclosureRule, effectiveViz, isNote } from './widgetSpec'
import type { RunMeta, RunResult, WidgetSpec } from './widgetSpec'
import type { WidgetProps } from '../dashboardTypes'

/**
 * A widget the user built, at runtime.
 *
 * The three outcomes the engine distinguishes land here as three different
 * renders, and getting them mixed up is the failure this component exists to
 * prevent:
 *
 *   `rows: null, denied`      → return null. The frame drops the widget, the
 *                               same way an unpermitted section does. A red
 *                               box would put a colleague's shared widget on
 *                               someone's dashboard as an error.
 *   `rows: null, unsupported` → a quiet card saying the data no longer exists.
 *                               The spec is untouched and will round-trip.
 *   `undefined`               → still loading.
 */

export function makeCustomComponent(row: { id: string; title: string; subtitle: string | null; spec: WidgetSpec }) {
  function CustomWidget({ height }: WidgetProps) {
    const result = useCustomResult(row.id)

    if (isNote(row.spec)) return <NoteBody title={row.title} spec={row.spec} />

    // undefined is "not loaded"; null is the server declining. Only the first
    // draws a skeleton.
    if (result === undefined) return <SkeletonCard lines={2} />
    if (result === null) return null

    const { rows, meta } = result as RunResult
    if (rows === null) {
      if (meta?.denied) return null
      return <RetiredCard title={row.title} missing={meta?.unsupported} />
    }

    const viz = effectiveViz(row.spec)
    const Renderer = viz === 'note' ? VIZ_RENDERERS.table : VIZ_RENDERERS[viz]
    return (
      <Renderer
        spec={row.spec}
        rows={rows}
        meta={meta ?? {}}
        height={height || 250}
        title={row.title}
        subtitle={row.subtitle ?? undefined}
        notice={<Disclosures meta={meta ?? {}} />}
      />
    )
  }
  CustomWidget.displayName = `CustomWidget(${row.title})`
  return CustomWidget
}

/* ===== what the number does not say =======================================
   Every one of these corresponds to a way the number can be quietly wrong,
   and the rule throughout the dashboard is that the card says so rather than
   the reader finding out later. Exported so the reports screen prints the
   same caveats under its panels instead of maintaining a second copy.        */

export function Disclosures({ meta }: { meta: RunMeta }) {
  const lines: string[] = []

  // an allocation, not a join: shifts with no task ids cannot be attributed
  const rule = disclosureRule(meta)
  if (meta.estimated) {
    lines.push('משוער — עלות המשמרת מחולקת בין המשימות לפי שעות')
    if (rule !== 'ok' && meta.unallocated != null) {
      lines.push(`${formatValue(Number(meta.unallocated), meta)} אינם משויכים ללקוח`)
    }
  }
  // app.attendance_calc returns null with no hourly rate, so those shifts
  // vanish from sum() — the count is what stops the total lying downward
  if (meta.unrated_shifts != null && Number(meta.unrated_shifts) > 0) {
    lines.push(`${meta.unrated_shifts} משמרות ללא תעריף אינן נספרות`)
  }
  // price is not null default 0, so a missing row and a zero row look alike
  if (meta.presence?.missing != null && Number(meta.presence.missing) > 0) {
    lines.push(`${meta.presence.missing} רשומות ללא ערך אינן נספרות`)
  }
  // unnest multiplies rows; the total is still right, the row count is not
  if (meta.fans_out) lines.push('שורה לכל משאית — סכום השורות גדול ממספר המשימות')
  if (meta.truncated) lines.push('מוצגות השורות המובילות בלבד')

  if (lines.length === 0) return null
  return (
    <p className="type-caption text-ink-tertiary">
      {lines.join(' · ')}
    </p>
  )
}

/* ===== a spec the catalogue no longer serves ==============================
   Deliberately not a deletion and not an error. The widget stays on the page
   with its title so the owner can see what broke, and the spec is preserved
   byte for byte — the same rule CondEditor applies to one filter row, at the
   scale of a whole widget.                                                   */

function RetiredCard({ title, missing }: { title: string; missing?: string }) {
  return (
    <Card>
      <CardHeader title={title} icon={<AlertTriangle size={ICON.md} strokeWidth={STROKE} />} />
      <CardBody>
        <EmptyState
          compact
          art="table"
          title="הווידג׳ט מבקש נתון שאינו קיים עוד"
          description={missing ? `הנתון החסר: ${missing}` : undefined}
        />
      </CardBody>
    </Card>
  )
}

/* ===== the free-text note =================================================
   No query at all. It still lives in `dashboard_widgets` so it takes part in
   sharing, ordering, sizing and export like everything else.                 */

const NOTE_TONES: Record<string, string> = {
  default: 'border-line bg-surface',
  info: 'border-primary/30 bg-primary/5',
  warn: 'border-amber-500/30 bg-amber-500/5',
}

function NoteBody({ title, spec }: { title: string; spec: Extract<WidgetSpec, { variant: 'note' }> }) {
  return (
    <div className={`rounded-xl border p-4 ${NOTE_TONES[spec.tone ?? 'default'] ?? NOTE_TONES.default}`}>
      <p className="type-body font-semibold text-ink">{title}</p>
      {/* whitespace-pre-wrap, not a markdown renderer: the body is plain text
          written by a colleague and rendered as text, so there is no path from
          a shared note to markup on someone else's screen */}
      <p className="mt-1 whitespace-pre-wrap type-caption text-ink-secondary">{spec.body}</p>
    </div>
  )
}
