import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  Cell,
  Line,
  LineChart,
  Pie,
  PieChart,
  Tooltip as RTooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { ProgressBar, StatCard, fmtHoursShort, fmtMoney } from '../../../../components/ui'
import { ICON, STROKE, Zap } from '../../../../components/ui/icons'
import { fmtDate } from '../../../../lib/dates'
import { ChartFrame } from '../../parts/ChartFrame'
import { ChartTooltip } from '../../parts/ChartTooltip'
import type { QuerySpec, RunMeta, RunRow, VizKind } from '../widgetSpec'

/**
 * Six renderers over one row shape.
 *
 * This is what `{key, label, color, value, n}` buys. The 65 hand-written
 * widgets each know the shape of their own section and can afford to; a widget
 * whose shape the user chooses at runtime cannot, so the server flattens
 * everything to one row type and these read it without knowing where it came
 * from.
 */

const TICK = { fontSize: 11, fill: 'var(--vl-text-tertiary)' } as const
const AXIS = { tick: TICK, axisLine: false, tickLine: false } as const
const BRAND = 'var(--vl-primary)'

/** a spread wide enough that neighbouring slices never read as the same colour */
const PALETTE = ['#3b82f6', '#1fa189', '#f59e0b', '#8b5cf6', '#ef4444', '#06b6d4', '#84cc16', '#ec4899']

export interface VizProps {
  spec: QuerySpec
  rows: RunRow[]
  meta: RunMeta
  height: number
  title: string
  subtitle?: string
  loading?: boolean
  /** rendered under the header — the estimate and coverage disclosures */
  notice?: React.ReactNode
}

/* ===== formatting ========================================================= */

export function formatValue(v: number | null | undefined, meta: RunMeta, decimals?: 0 | 1 | 2): string {
  if (v == null) return '—'
  switch (meta.unit) {
    case 'money':
      return fmtMoney(v)
    case 'hours':
      return fmtHoursShort(v)
    case 'percent':
      return `${v.toFixed(decimals ?? 1)}%`
    case 'volume':
      return `${v.toFixed(decimals ?? 1)} מ״ק`
    default:
      return v.toLocaleString('he-IL', { maximumFractionDigits: decimals ?? 0 })
  }
}

/** a time bucket arrives as an ISO date; anything else is already a label */
function axisLabel(row: RunRow, isTime: boolean): string {
  return isTime ? fmtDate(row.label) : row.label
}

function prepare(rows: RunRow[], spec: QuerySpec, meta: RunMeta) {
  const isTime = meta.bucket != null
  const entity = spec.viz_opts.palette === 'entity'
  return rows.map((r, i) => ({
    name: axisLabel(r, isTime),
    value: Number(r.value ?? 0),
    fill: (entity ? r.color : null) ?? PALETTE[i % PALETTE.length],
  }))
}

/* ===== one number ========================================================= */

function NumberViz({ rows, meta, spec, title, subtitle, notice }: VizProps) {
  const value = rows[0]?.value ?? meta.total ?? null
  return (
    <div className="space-y-1.5">
      <StatCard
        icon={<Zap size={ICON.xl} strokeWidth={STROKE} />}
        label={title}
        value={formatValue(value == null ? null : Number(value), meta, spec.viz_opts.decimals)}
        tone={BRAND}
        hint={subtitle}
      />
      {notice}
    </div>
  )
}

/* ===== value against a target =============================================
   The goal lives on the spec rather than in the data, because "am I on track"
   is the author's question and not something the server can know.            */

function GaugeViz({ rows, meta, spec, title, subtitle, notice }: VizProps) {
  const value = Number(rows[0]?.value ?? meta.total ?? 0)
  const target = spec.goal?.target ?? 0
  const pct = target > 0 ? Math.min(100, Math.round((value / target) * 100)) : 0
  const wantsMore = (spec.goal?.direction ?? 'up') === 'up'
  const good = wantsMore ? value >= target : value <= target
  return (
    <div className="rounded-xl border border-line bg-surface p-4">
      <p className="type-caption text-ink-tertiary">{title}</p>
      <p className="mt-1 type-title tabular font-bold text-ink">
        {formatValue(value, meta, spec.viz_opts.decimals)}
      </p>
      <div className="mt-2">
        <ProgressBar value={pct} color={good ? '#1fa189' : '#f59e0b'} />
      </div>
      <p className="mt-1.5 type-caption tabular text-ink-tertiary">
        {target > 0 ? `${pct}% מהיעד ${formatValue(target, meta, spec.viz_opts.decimals)}` : 'לא הוגדר יעד'}
      </p>
      {subtitle && <p className="type-caption text-ink-tertiary">{subtitle}</p>}
      {notice}
    </div>
  )
}

/* ===== bars =============================================================== */

function BarViz(props: VizProps) {
  const { rows, spec, meta, height, title, subtitle, loading, notice } = props
  const data = prepare(rows, spec, meta)
  return (
    <ChartFrame
      title={title}
      subtitle={subtitle}
      actions={notice}
      loading={loading}
      empty={!data.length}
      height={height}
    >
      <BarChart data={data} margin={{ top: 4, right: 4, bottom: 4, left: -20 }}>
        <XAxis dataKey="name" {...AXIS} interval={0} angle={-25} textAnchor="end" height={54} />
        <YAxis {...AXIS} allowDecimals={meta.unit !== 'count'} />
        <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip />} />
        <Bar dataKey="value" name={title} radius={[6, 6, 0, 0]} maxBarSize={44}>
          {data.map((d, i) => (
            <Cell key={i} fill={d.fill} />
          ))}
        </Bar>
      </BarChart>
    </ChartFrame>
  )
}

/* Horizontal, for the top-N shape: these labels are names, and a name tilted
   25° on a bottom axis is a name you read sideways. */
function RowViz(props: VizProps) {
  const { rows, spec, meta, height, title, subtitle, loading } = props
  const data = prepare(rows, spec, meta)
  return (
    <ChartFrame title={title} subtitle={subtitle} loading={loading} empty={!data.length} height={height}>
      <BarChart data={data} layout="vertical" margin={{ top: 4, right: 12, bottom: 4, left: 4 }}>
        <XAxis type="number" {...AXIS} allowDecimals={meta.unit !== 'count'} />
        <YAxis type="category" dataKey="name" width={96} {...AXIS} />
        <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip />} />
        <Bar dataKey="value" name={title} radius={[0, 6, 6, 0]} maxBarSize={18}>
          {data.map((d, i) => (
            <Cell key={i} fill={d.fill} />
          ))}
        </Bar>
      </BarChart>
    </ChartFrame>
  )
}

/* ===== time series ======================================================== */

function LineViz(props: VizProps) {
  const { rows, spec, meta, height, title, subtitle, loading } = props
  const data = prepare(rows, spec, meta)
  return (
    <ChartFrame title={title} subtitle={subtitle} loading={loading} empty={!data.length} height={height}>
      <LineChart data={data} margin={{ top: 4, right: 8, bottom: 4, left: -20 }}>
        <XAxis dataKey="name" {...AXIS} />
        <YAxis {...AXIS} allowDecimals={meta.unit !== 'count'} />
        <RTooltip content={<ChartTooltip />} />
        <Line type="monotone" dataKey="value" name={title} stroke={BRAND} strokeWidth={2} dot={false} />
      </LineChart>
    </ChartFrame>
  )
}

function AreaViz(props: VizProps) {
  const { rows, spec, meta, height, title, subtitle, loading } = props
  const data = prepare(rows, spec, meta)
  return (
    <ChartFrame title={title} subtitle={subtitle} loading={loading} empty={!data.length} height={height}>
      <AreaChart data={data} margin={{ top: 4, right: 8, bottom: 4, left: -20 }}>
        <defs>
          <linearGradient id="vl-custom-area" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={BRAND} stopOpacity={0.35} />
            <stop offset="100%" stopColor={BRAND} stopOpacity={0.02} />
          </linearGradient>
        </defs>
        <XAxis dataKey="name" {...AXIS} />
        <YAxis {...AXIS} allowDecimals={meta.unit !== 'count'} />
        <RTooltip content={<ChartTooltip />} />
        <Area
          type="monotone"
          dataKey="value"
          name={title}
          stroke={BRAND}
          strokeWidth={2}
          fill="url(#vl-custom-area)"
        />
      </AreaChart>
    </ChartFrame>
  )
}

/* ===== composition ======================================================== */

function DonutViz(props: VizProps) {
  const { rows, spec, meta, height, title, subtitle, loading } = props
  const data = prepare(rows, spec, meta)
  return (
    <ChartFrame title={title} subtitle={subtitle} loading={loading} empty={!data.length} height={height}>
      <PieChart>
        <Pie data={data} dataKey="value" nameKey="name" innerRadius="55%" outerRadius="82%" paddingAngle={2}>
          {data.map((d, i) => (
            <Cell key={i} fill={d.fill} />
          ))}
        </Pie>
        <RTooltip content={<ChartTooltip />} />
      </PieChart>
    </ChartFrame>
  )
}

/* ===== the fallback that always renders ===================================
   Also what an unrecognised `viz` degrades to: a table can draw any row shape,
   so a widget saved by a newer client still shows its numbers.               */

function TableViz({ rows, spec, meta, title, subtitle, notice }: VizProps) {
  const isTime = meta.bucket != null
  const total = meta.total == null ? null : Number(meta.total)
  return (
    <div className="rounded-xl border border-line bg-surface">
      <div className="border-b border-line-subtle px-4 py-2.5">
        <p className="type-body font-semibold text-ink">{title}</p>
        {subtitle && <p className="type-caption text-ink-tertiary">{subtitle}</p>}
      </div>
      {rows.length === 0 ? (
        <p className="px-4 py-6 text-center type-caption text-ink-tertiary">אין נתונים בטווח</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full">
            <tbody>
              {rows.map((r, i) => (
                <tr key={`${r.key ?? i}`} className="border-b border-line-subtle last:border-0">
                  <td className="px-4 py-2 type-caption text-ink-secondary">
                    <span className="flex items-center gap-2">
                      {r.color && (
                        <span
                          className="size-2.5 shrink-0 rounded-full"
                          style={{ background: r.color }}
                          aria-hidden
                        />
                      )}
                      <span className="truncate">{axisLabel(r, isTime)}</span>
                    </span>
                  </td>
                  <td className="px-4 py-2 text-end type-caption tabular font-semibold text-ink">
                    {formatValue(r.value, meta, spec.viz_opts.decimals)}
                  </td>
                </tr>
              ))}
            </tbody>
            {total != null && (
              <tfoot>
                <tr className="border-t border-line">
                  <td className="px-4 py-2 type-caption text-ink-tertiary">סך הכול</td>
                  <td className="px-4 py-2 text-end type-caption tabular font-bold text-ink">
                    {formatValue(total, meta, spec.viz_opts.decimals)}
                  </td>
                </tr>
              </tfoot>
            )}
          </table>
        </div>
      )}
      {notice && <div className="px-4 pb-3">{notice}</div>}
    </div>
  )
}

export const VIZ_RENDERERS: Record<Exclude<VizKind, 'note'>, (p: VizProps) => React.ReactElement> = {
  number: NumberViz,
  gauge: GaugeViz,
  bar: BarViz,
  row: RowViz,
  line: LineViz,
  area: AreaViz,
  donut: DonutViz,
  table: TableViz,
}
