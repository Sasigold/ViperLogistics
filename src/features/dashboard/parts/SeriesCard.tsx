import type { ReactNode } from 'react'
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
  ResponsiveContainer,
  Tooltip as RTooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { Card, CardBody, CardHeader, EmptyState, ProgressBar, Skeleton, cx } from '../../../components/ui'
import { fmtDate } from '../../../lib/dates'
import { ChartTooltip } from './ChartTooltip'
import { applySeriesOpts, plotHeight } from '../seriesOpts'
import type { SeriesRow } from '../seriesOpts'
import type { WidgetForm, WidgetOpts } from '../dashboardTypes'

/**
 * One card, seven ways to draw it.
 *
 * The builder proved the shape (`builder/viz/vizRenderers.tsx`): flatten the
 * data to `{key, label, value, color}` once and every renderer reads it
 * without knowing where it came from. What that file cannot do is serve the
 * hand-written widgets — it takes a `QuerySpec`, which a widget that knows the
 * shape of its own section does not have and should not have to invent.
 *
 * So this is the same idea against a plain row type. A widget hands over its
 * rows and declares which forms it can honestly be drawn in; the reader picks
 * one from the card's own menu and it costs nothing — the rows are already in
 * hand, no round trip, no new section. That is the whole reason the form is a
 * client-side option and not a server one.
 *
 * `onSelect` is the other half. A number on a dashboard is a question ("who are
 * those four?") and the answer is always on another screen, so a series that
 * can say where a row leads makes its bars, its slices and its rows clickable
 * in every form at once.
 */

const TICK = { fontSize: 11, fill: 'var(--vl-text-tertiary)' } as const
const AXIS = { tick: TICK, axisLine: false, tickLine: false } as const
const BRAND = 'var(--vl-primary)'

/** a spread wide enough that neighbouring slices never read as the same colour */
const PALETTE = ['#3b82f6', '#1fa189', '#f59e0b', '#8b5cf6', '#ef4444', '#06b6d4', '#84cc16', '#ec4899']

/* ===== the card =========================================================== */

export interface SeriesCardProps {
  title: ReactNode
  subtitle?: ReactNode
  icon?: ReactNode
  actions?: ReactNode
  /** `undefined` is "not loaded"; a widget whose section declined returns null itself */
  rows: SeriesRow[] | undefined
  loading?: boolean
  form: WidgetForm
  /** plotting height from the frame; the list and table forms grow instead */
  height: number
  opts: WidgetOpts
  /** the series' name in tooltips */
  seriesName: string
  /** how a value reads — money, hours, a plain count */
  format?: (v: number) => string
  /** labels are ISO dates and get formatted as such; also disables sorting */
  timeAxis?: boolean
  /** the fallback colour when a row has none */
  fill?: string
  emptyTitle?: string
  emptyDescription?: ReactNode
  /** a way out of an empty card — "add an event", "widen the range" */
  emptyAction?: ReactNode
  /** makes every bar, slice and row a link to wherever this number came from */
  onSelect?: (row: SeriesRow) => void
}

export function SeriesCard(props: SeriesCardProps) {
  const {
    title,
    subtitle,
    icon,
    actions,
    rows,
    loading,
    form,
    height,
    opts,
    emptyTitle = 'אין נתונים בטווח',
    emptyDescription,
    emptyAction,
  } = props

  const shown = rows ? applySeriesOpts(rows, opts, props.timeAxis) : undefined
  const busy = loading || rows === undefined

  return (
    <Card>
      <CardHeader title={title} subtitle={subtitle} icon={icon} actions={actions} />
      <CardBody padded={form === 'list' || form === 'table' ? false : undefined}>
        {busy ? (
          <Skeleton className="m-4 w-[calc(100%-2rem)]" style={{ height: Math.max(120, height) }} />
        ) : !shown?.length ? (
          /* An empty card is where a dashboard usually gives up. It is also the
             one moment the reader is most likely to act, so the state says what
             would fill it rather than only that it is empty. */
          <EmptyState
            compact
            art="table"
            title={emptyTitle}
            description={emptyDescription}
            action={emptyAction}
          />
        ) : (
          <SeriesBody {...props} rows={shown} />
        )}
      </CardBody>
    </Card>
  )
}

/* ===== the seven forms ==================================================== */

function SeriesBody({
  rows,
  form,
  height,
  opts,
  seriesName,
  format,
  timeAxis,
  fill,
  onSelect,
}: SeriesCardProps & { rows: SeriesRow[] }) {
  const fmt = format ?? ((v: number) => v.toLocaleString('he-IL', { maximumFractionDigits: 1 }))
  const data = rows.map((r, i) => ({
    ...r,
    name: timeAxis ? fmtDate(r.label) : r.label,
    fill: r.color ?? fill ?? PALETTE[i % PALETTE.length],
  }))
  /* recharts hands the datum straight back on a click, so the row travels with
     the mark and nothing has to be looked up by index */
  const pick = onSelect ? (d: unknown) => onSelect(d as SeriesRow) : undefined
  const clickable = !!onSelect

  if (form === 'table' || form === 'list') {
    return <RowsView rows={rows} form={form} fmt={fmt} timeAxis={timeAxis} fill={fill} opts={opts} onSelect={onSelect} />
  }

  const chart = () => {
    switch (form) {
      case 'row':
        return (
          <BarChart data={data} layout="vertical" margin={{ top: 4, right: 12, bottom: 4, left: 4 }}>
            <XAxis type="number" {...AXIS} />
            <YAxis type="category" dataKey="name" width={96} {...AXIS} />
            <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip format={fmt} />} />
            <Bar dataKey="value" name={seriesName} radius={[0, 6, 6, 0]} maxBarSize={18} onClick={pick}>
              {data.map((d, i) => (
                <Cell key={i} fill={d.fill} cursor={clickable ? 'pointer' : undefined} />
              ))}
            </Bar>
          </BarChart>
        )
      case 'line':
        return (
          <LineChart data={data} margin={{ top: 4, right: 8, bottom: 4, left: -20 }}>
            <XAxis dataKey="name" {...AXIS} />
            <YAxis {...AXIS} />
            <RTooltip content={<ChartTooltip format={fmt} />} />
            <Line
              type="monotone"
              dataKey="value"
              name={seriesName}
              stroke={fill ?? BRAND}
              strokeWidth={2}
              dot={data.length <= 12}
              activeDot={{ onClick: pick, cursor: clickable ? 'pointer' : undefined }}
            />
          </LineChart>
        )
      case 'area':
        return (
          <AreaChart data={data} margin={{ top: 4, right: 8, bottom: 4, left: -20 }}>
            <defs>
              <linearGradient id="vl-series-area" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor={fill ?? BRAND} stopOpacity={0.35} />
                <stop offset="100%" stopColor={fill ?? BRAND} stopOpacity={0.02} />
              </linearGradient>
            </defs>
            <XAxis dataKey="name" {...AXIS} />
            <YAxis {...AXIS} />
            <RTooltip content={<ChartTooltip format={fmt} />} />
            <Area
              type="monotone"
              dataKey="value"
              name={seriesName}
              stroke={fill ?? BRAND}
              strokeWidth={2}
              fill="url(#vl-series-area)"
              activeDot={{ onClick: pick, cursor: clickable ? 'pointer' : undefined }}
            />
          </AreaChart>
        )
      case 'donut':
        return (
          <PieChart>
            <Pie
              data={data}
              dataKey="value"
              nameKey="name"
              innerRadius="55%"
              outerRadius="82%"
              paddingAngle={2}
              onClick={pick}
            >
              {data.map((d, i) => (
                <Cell key={i} fill={d.fill} cursor={clickable ? 'pointer' : undefined} />
              ))}
            </Pie>
            <RTooltip content={<ChartTooltip format={fmt} />} />
          </PieChart>
        )
      default:
        return (
          <BarChart data={data} margin={{ top: 4, right: 4, bottom: 4, left: -20 }}>
            <XAxis
              dataKey="name"
              {...AXIS}
              interval={0}
              angle={timeAxis ? 0 : -25}
              textAnchor={timeAxis ? 'middle' : 'end'}
              height={timeAxis ? 24 : 54}
            />
            <YAxis {...AXIS} />
            <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip format={fmt} />} />
            <Bar dataKey="value" name={seriesName} radius={[6, 6, 0, 0]} maxBarSize={44} onClick={pick}>
              {data.map((d, i) => (
                <Cell key={i} fill={d.fill} cursor={clickable ? 'pointer' : undefined} />
              ))}
            </Bar>
          </BarChart>
        )
    }
  }

  return (
    <ResponsiveContainer width="100%" height={plotHeight(form, rows.length, height || 250)}>
      {chart()}
    </ResponsiveContainer>
  )
}

/* ===== the two forms that are not charts ==================================
   `list` is the progress-bar shape the spend and mix cards already use — it
   reads a share at a glance and survives a single row, which is exactly where
   a bar chart stops being a picture of anything. `table` is the fallback that
   always renders, and the honest answer for a card somebody wants to read as
   numbers rather than look at.                                              */

function RowsView({
  rows,
  form,
  fmt,
  timeAxis,
  fill,
  opts,
  onSelect,
}: {
  rows: SeriesRow[]
  form: 'list' | 'table'
  fmt: (v: number) => string
  timeAxis?: boolean
  fill?: string
  opts: WidgetOpts
  onSelect?: (row: SeriesRow) => void
}) {
  const max = rows.reduce((m, r) => Math.max(m, r.value), 0)
  const total = rows.reduce((s, r) => s + r.value, 0)
  const label = (r: SeriesRow) => (timeAxis ? fmtDate(r.label) : r.label)
  const showValues = opts.values !== false

  if (form === 'list') {
    return (
      <div className="space-y-2.5 p-4">
        {rows.map((r, i) => {
          const bar = (
            <ProgressBar
              value={r.value}
              max={max || 1}
              color={r.color ?? fill ?? PALETTE[i % PALETTE.length]}
              label={label(r)}
              hint={r.hint ?? (showValues ? fmt(r.value) : undefined)}
            />
          )
          return onSelect ? (
            <button
              key={r.key}
              type="button"
              onClick={() => onSelect(r)}
              className="-mx-1 block w-[calc(100%+0.5rem)] rounded-lg px-1 py-0.5 text-start transition-colors hover:bg-hover"
            >
              {bar}
            </button>
          ) : (
            <div key={r.key}>{bar}</div>
          )
        })}
      </div>
    )
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full">
        <tbody>
          {rows.map((r) => (
            /* `role`/`tabIndex`/Enter rather than a bare `onClick`: a row you can
               only reach with a mouse is a drill-down half the readers do not
               have. The charts are unavoidably pointer-only, which is part of
               why every one of them can be switched to this form. */
            <tr
              key={r.key}
              role={onSelect ? 'button' : undefined}
              tabIndex={onSelect ? 0 : undefined}
              onClick={onSelect ? () => onSelect(r) : undefined}
              onKeyDown={
                onSelect
                  ? (e) => {
                      if (e.key === 'Enter' || e.key === ' ') {
                        e.preventDefault()
                        onSelect(r)
                      }
                    }
                  : undefined
              }
              className={cx(
                'border-b border-line-subtle last:border-0',
                onSelect &&
                  'cursor-pointer transition-colors hover:bg-hover focus-visible:bg-hover focus-visible:outline-none',
              )}
            >
              <td className="px-4 py-2 type-caption text-ink-secondary">
                <span className="flex items-center gap-2">
                  {r.color && (
                    <span className="size-2.5 shrink-0 rounded-full" style={{ background: r.color }} aria-hidden />
                  )}
                  <span className="truncate">{label(r)}</span>
                </span>
                {r.hint && <span className="block truncate type-caption text-ink-tertiary">{r.hint}</span>}
              </td>
              <td className="px-4 py-2 text-end type-caption tabular font-semibold text-ink">{fmt(r.value)}</td>
            </tr>
          ))}
        </tbody>
        {rows.length > 1 && (
          <tfoot>
            <tr className="border-t border-line">
              <td className="px-4 py-2 type-caption text-ink-tertiary">סך הכול</td>
              <td className="px-4 py-2 text-end type-caption tabular font-bold text-ink">{fmt(total)}</td>
            </tr>
          </tfoot>
        )}
      </table>
    </div>
  )
}
