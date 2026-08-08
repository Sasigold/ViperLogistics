import type { ReactElement, ReactNode } from 'react'
import { ResponsiveContainer } from 'recharts'
import { Card, CardBody, CardHeader, EmptyState, Skeleton } from '../../../components/ui'

/** the height a chart gets when nobody says otherwise — what the page used before */
export const CHART_H = 250

/**
 * Card + header + a fixed-height plotting area, with the three states a chart
 * can be in before it has anything to draw.
 *
 * `height` is a prop rather than a constant because a widget's size decides how
 * tall its chart is; the default keeps every existing call site pixel-identical.
 */
export function ChartFrame({
  title,
  subtitle,
  actions,
  children,
  empty,
  emptyTitle = 'אין נתונים בטווח',
  loading,
  height = CHART_H,
}: {
  title: ReactNode
  subtitle?: ReactNode
  actions?: ReactNode
  children: ReactElement
  empty?: boolean
  emptyTitle?: string
  loading?: boolean
  height?: number
}) {
  return (
    <Card>
      <CardHeader title={title} subtitle={subtitle} actions={actions} />
      <CardBody>
        {loading ? (
          <Skeleton className="w-full" style={{ height }} />
        ) : empty ? (
          <div style={{ height }} className="flex items-center justify-center">
            <EmptyState compact art="table" title={emptyTitle} />
          </div>
        ) : (
          <ResponsiveContainer width="100%" height={height}>
            {children}
          </ResponsiveContainer>
        )}
      </CardBody>
    </Card>
  )
}
