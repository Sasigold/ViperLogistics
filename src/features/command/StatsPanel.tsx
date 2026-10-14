import { Area, AreaChart, Bar, BarChart, Cell, ComposedChart, Legend, Line, ReferenceLine, Tooltip as RTooltip, XAxis, YAxis } from 'recharts'
import { Card, CardBody, CardHeader, Tooltip, cx } from '../../components/ui'
import { fmtDate } from '../../lib/dates'
import { ChartFrame } from '../dashboard/parts/ChartFrame'
import { ChartTooltip } from '../dashboard/parts/ChartTooltip'
import type { MissionsStats } from '../../types/domain'
import { ACHIEVEMENTS, heatLevel, weeklyOnTime } from './warRoom'

const AXIS = { tick: { fontSize: 11, fill: 'var(--vl-text-tertiary)' }, axisLine: false, tickLine: false } as const
const shortDay = (d: string) => fmtDate(d).slice(0, 5)

/** עוצמות מפת החום — גוון אחד (הצלחה), מבהיר לכהה */
const HEAT = [
  'var(--vl-inset)',
  'color-mix(in srgb, var(--vl-success) 30%, var(--vl-surface))',
  'color-mix(in srgb, var(--vl-success) 55%, var(--vl-surface))',
  'color-mix(in srgb, var(--vl-success) 78%, var(--vl-surface))',
  'var(--vl-success)',
]

/**
 * הגרפים: ירידת המשימות הפתוחות, מפת חום של מה שנסגר, אחוז בזמן לפי שבוע,
 * והחוב לאורך זמן — ומתחתם ההישגים. כל המספרים מהשרת (`missions_stats`).
 */
export function StatsPanel({ stats, loading }: { stats: MissionsStats | undefined; loading: boolean }) {
  const daily = stats?.daily ?? []
  const last30 = daily.slice(-30)
  const weeks = weeklyOnTime(daily).slice(-12)
  const earned = new Map((stats?.achievements ?? []).map((a) => [a.key, a.earned_at]))
  const anything = daily.some((d) => d.open || d.done)

  return (
    <div className="space-y-4">
      <div className="grid gap-4 lg:grid-cols-2">
        <ChartFrame
          title="פתוחות מול באיחור · 30 יום"
          subtitle="קו = משימות פתוחות בסוף כל יום · אדום = מתוכן באיחור"
          loading={loading}
          empty={!anything}
          emptyTitle="עוד אין היסטוריה"
        >
          <ComposedChart data={last30} margin={{ top: 8, right: 8, bottom: 4, left: -24 }}>
            <XAxis dataKey="day" {...AXIS} tickFormatter={shortDay} minTickGap={16} />
            <YAxis {...AXIS} allowDecimals={false} width={40} />
            <RTooltip content={<ChartTooltip />} labelFormatter={(l) => fmtDate(String(l))} />
            <Legend wrapperStyle={{ fontSize: 11 }} />
            <Area
              dataKey="overdue"
              name="באיחור"
              type="monotone"
              fill="color-mix(in srgb, var(--vl-error) 22%, transparent)"
              stroke="var(--vl-error)"
              strokeWidth={2}
            />
            <Line dataKey="open" name="פתוחות" type="monotone" stroke="var(--vl-text-secondary)" strokeWidth={2} dot={false} />
          </ComposedChart>
        </ChartFrame>

        <ChartFrame
          title="החוב לאורך זמן"
          subtitle="סך שעות האיחור שהצטברו בסוף כל יום — המטרה: קו שטוח על האפס"
          loading={loading}
          empty={!anything}
          emptyTitle="עוד אין היסטוריה"
        >
          <AreaChart data={last30} margin={{ top: 8, right: 8, bottom: 4, left: -16 }}>
            <XAxis dataKey="day" {...AXIS} tickFormatter={shortDay} minTickGap={16} />
            <YAxis {...AXIS} width={48} tickFormatter={(v: number) => `${v}ש׳`} />
            <RTooltip content={<ChartTooltip format={(v) => `${v} שעות`} />} />
            <Area
              dataKey="debt_hours"
              name="חוב"
              type="monotone"
              fill="color-mix(in srgb, var(--vl-error) 18%, transparent)"
              stroke="var(--vl-error)"
              strokeWidth={2}
            />
          </AreaChart>
        </ChartFrame>

        <ChartFrame
          title="בזמן, שבוע אחר שבוע"
          subtitle="אחוז המשימות שנסגרו עד היעד · היעד: 90%"
          loading={loading}
          empty={!weeks.some((w) => w.done)}
          emptyTitle="עוד לא נסגרו משימות"
        >
          <BarChart data={weeks} margin={{ top: 8, right: 8, bottom: 4, left: -24 }}>
            <XAxis dataKey="week" {...AXIS} tickFormatter={shortDay} />
            <YAxis {...AXIS} domain={[0, 100]} width={40} tickFormatter={(v: number) => `${v}%`} />
            <RTooltip cursor={{ fill: 'var(--vl-hover)' }} content={<ChartTooltip format={(v) => `${v}%`} />} />
            <ReferenceLine y={90} stroke="var(--vl-success)" strokeDasharray="4 4" />
            <Bar dataKey="pct" name="בזמן" radius={[4, 4, 0, 0]} maxBarSize={28}>
              {weeks.map((w) => (
                <Cell
                  key={w.week}
                  fill={w.pct === null ? 'var(--vl-inset)' : w.pct >= 90 ? 'var(--vl-success)' : w.pct >= 60 ? 'var(--vl-warning)' : 'var(--vl-error)'}
                />
              ))}
            </Bar>
          </BarChart>
        </ChartFrame>

        <Card>
          <CardHeader title="12 שבועות" subtitle="כל ריבוע הוא יום · כהה יותר = יותר משימות נסגרו · מסגרת אדומה = היום נגמר באיחור" />
          <CardBody>
            {loading ? null : <Heatmap daily={daily.slice(-84)} />}
          </CardBody>
        </Card>
      </div>

      <Card>
        <CardHeader
          title="הישגים"
          subtitle={`${earned.size} מתוך ${ACHIEVEMENTS.length} · ${stats?.done_total ?? 0} משימות בוצעו, ${stats?.early_total ?? 0} מהן יום ומעלה לפני היעד`}
        />
        <CardBody>
          <ul className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-5">
            {ACHIEVEMENTS.map((a) => {
              const at = earned.get(a.key)
              return (
                <li
                  key={a.key}
                  className={cx(
                    'flex items-center gap-2 rounded-xl border px-3 py-2',
                    at ? 'border-warning-border bg-warning-subtle' : 'border-line-subtle bg-subtle opacity-60',
                  )}
                >
                  <span className={cx('text-2xl', !at && 'grayscale')} aria-hidden>
                    {at ? a.emoji : '🔒'}
                  </span>
                  <div className="min-w-0">
                    <p className="truncate type-caption font-bold text-ink">{a.label}</p>
                    <p className="truncate type-caption text-ink-tertiary">{at ? fmtDate(at) : a.hint}</p>
                  </div>
                </li>
              )
            })}
          </ul>
        </CardBody>
      </Card>
    </div>
  )
}

function Heatmap({ daily }: { daily: MissionsStats['daily'] }) {
  if (!daily.length) return null
  // עמודה לכל שבוע (ראשון–שבת), כמו ב-GitHub
  const first = new Date(`${daily[0].day}T00:00:00`)
  const lead = first.getDay()
  const cells: (MissionsStats['daily'][number] | null)[] = [...Array(lead).fill(null), ...daily]
  const cols: (typeof cells)[] = []
  for (let i = 0; i < cells.length; i += 7) cols.push(cells.slice(i, i + 7))

  return (
    <div className="flex justify-center gap-1 overflow-x-auto" dir="ltr">
      {cols.map((col, i) => (
        <div key={i} className="flex flex-col gap-1">
          {col.map((d, j) =>
            d ? (
              <Tooltip
                key={d.day}
                content={`${fmtDate(d.day)} · ${d.done} בוצעו${d.overdue ? ` · ${d.overdue} באיחור בסוף היום` : ''}`}
              >
                <span
                  className={cx('block size-3.5 rounded-[3px]', d.overdue > 0 && 'ring-1 ring-error ring-inset')}
                  style={{ background: HEAT[heatLevel(d.done)] }}
                />
              </Tooltip>
            ) : (
              <span key={`pad-${j}`} className="block size-3.5" />
            ),
          )}
        </div>
      ))}
    </div>
  )
}
