import type { ComponentType, ReactNode } from 'react'
import { useNavigate } from 'react-router'
import { SkeletonCard, StatCard } from '../../../components/ui'
import { ICON, STROKE } from '../../../components/ui/icons'
import { useDashboard } from '../dashboardContext'
import { useDashboardStats } from '../dashboardQueries'
import type { WidgetProps } from '../dashboardTypes'
import type { DashboardStats } from '../../../types/domain'

/**
 * Two dozen of the widgets differ only in which field they read, what colour
 * their icon chip is and where clicking them goes. Written out longhand the
 * registry would be a thousand lines of near-identical components and the
 * differences between them would be invisible; as a factory each one is six
 * lines of data.
 */
export interface StatKpiConfig {
  label: string
  icon: ComponentType<{ size?: number; strokeWidth?: number }>
  /** `null` from the server means "not for you" — the tile renders nothing */
  select: (s: DashboardStats) => number | null | undefined
  format?: (v: number) => ReactNode
  tone?: string
  /** true when a rising number is bad news */
  invertDelta?: boolean
  /** compare against the previous period */
  delta?: boolean
  hint?: (s: DashboardStats) => ReactNode
  to?: string
}

export function statKpi(cfg: StatKpiConfig): ComponentType<WidgetProps> {
  function StatKpiWidget(_props: WidgetProps) {
    const navigate = useNavigate()
    const { range, prev } = useDashboard()
    const { data, isLoading, error } = useDashboardStats(range.from, range.to)
    // only fetched when the tile actually shows a delta, so a dashboard with no
    // delta tiles never asks for the previous period at all
    const previous = useDashboardStats(cfg.delta ? prev.from : range.from, cfg.delta ? prev.to : range.to)

    if (isLoading && !data) return <SkeletonCard lines={0} />

    /* A tile that failed says so. Left as a skeleton it would spin forever —
       isLoading goes false while data stays undefined — which reads as "still
       loading" and never resolves. */
    if (error || !data) {
      const Icon = cfg.icon
      return (
        <StatCard
          icon={<Icon size={ICON.xl} strokeWidth={STROKE} />}
          label={cfg.label}
          value="—"
          tone="#ef4444"
          hint="לא נטען"
        />
      )
    }

    const value = cfg.select(data)
    // `null` is the server saying this section is not for this reader; `0` is a
    // real zero. The first is omitted, the second is drawn.
    if (value === null || value === undefined) return null

    const before = cfg.delta && previous.data ? cfg.select(previous.data) : null
    const Icon = cfg.icon

    return (
      <StatCard
        icon={<Icon size={ICON.xl} strokeWidth={STROKE} />}
        label={cfg.label}
        value={cfg.format ? cfg.format(value) : value}
        tone={cfg.tone}
        invertDelta={cfg.invertDelta}
        delta={before === null || before === undefined ? null : value - before}
        hint={cfg.delta && before != null ? 'מול התקופה הקודמת' : cfg.hint?.(data)}
        onClick={cfg.to ? () => navigate(cfg.to!) : undefined}
      />
    )
  }
  StatKpiWidget.displayName = `StatKpi(${cfg.label})`
  return StatKpiWidget
}
