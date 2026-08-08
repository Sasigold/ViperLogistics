/**
 * Recharts' default tooltip ignores the theme; this one uses our surfaces.
 *
 * Lived inside DashboardPage while there were three charts in one file. Every
 * widget that draws a chart needs it, so it moved out rather than being
 * imported back out of a page component.
 */
export function ChartTooltip({
  active,
  payload,
  label,
}: {
  active?: boolean
  payload?: { name?: string; value?: number | string; payload?: { name?: string } }[]
  label?: string
}) {
  if (!active || !payload?.length) return null
  return (
    <div className="rounded-lg border border-line bg-raised px-2.5 py-1.5 shadow-lg">
      <p className="type-caption font-semibold text-ink">{label ?? payload[0]?.payload?.name}</p>
      {payload.map((p, i) => (
        <p key={i} className="type-caption tabular text-ink-secondary">
          {p.name}: <span className="font-bold text-ink">{p.value}</span>
        </p>
      ))}
    </div>
  )
}
