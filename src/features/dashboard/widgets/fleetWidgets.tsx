import { Link } from 'react-router'
import { Card, CardBody, CardHeader, EmptyState, SkeletonCard, SkeletonList, StatCard } from '../../../components/ui'
import { AlertTriangle, ICON, STROKE, Truck } from '../../../components/ui/icons'
import { fmtDate } from '../../../lib/dates'
import { useSection } from '../dashboardContext'
import type { WidgetProps } from '../dashboardTypes'
import type { VehicleDocumentState } from '../../../types/domain'
import { DOC_STATE_COLORS, DOC_STATE_LABELS, expiryLabel, formatPlate } from '../../vehicles/vehicles'

/**
 * צי הרכב בדשבורד (0090).
 *
 * שני הווידג׳טים אינם `usesRange`, ובכוונה: תוקף מסמך הוא שאלה על היום ועל
 * מה שאחריו, ולא על הטווח שנבחר בראש הדשבורד. מי שיהפוך אותם לתלויי-טווח
 * ישנה את משמעותם בשקט — הכרטיס ייראה זהה ויספור משהו אחר.
 */

interface FleetStatus {
  total: number
  active: number
  in_garage: number
  inactive: number
}

export function FleetStatusWidget(_props: WidgetProps) {
  const { data, isLoading } = useSection<FleetStatus>('fleet.status')
  if (isLoading && data === undefined) return <SkeletonCard lines={0} />
  if (data === null || data === undefined) return null

  const unavailable = data.in_garage + data.inactive
  return (
    <StatCard
      icon={<Truck size={ICON.xl} strokeWidth={STROKE} />}
      label="רכבים בצי"
      value={data.total}
      tone={unavailable > 0 ? '#f59e0b' : '#3563f0'}
      hint={
        unavailable > 0
          ? `${data.active} זמינים · ${data.in_garage} במוסך · ${data.inactive} מושבתים`
          : 'כל הרכבים זמינים'
      }
    />
  )
}

interface ExpiringRow {
  vehicle_id: string
  name: string
  plate_number: string
  kind_name: string
  expires_at: string
  days_left: number | null
  status: VehicleDocumentState
}

export function FleetExpiringDocsWidget(_props: WidgetProps) {
  const { data, isLoading } = useSection<ExpiringRow[]>('fleet.documents_expiring')
  if (data === null) return null

  const expired = (data ?? []).filter((r) => r.status === 'expired').length

  return (
    <Card>
      <CardHeader
        title="מסמכי רכב שפגים"
        subtitle={data ? (expired > 0 ? `${expired} כבר פגו` : `${data.length} מתקרבים לפקיעה`) : undefined}
        icon={<AlertTriangle size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody padded={false}>
        {isLoading && !data ? (
          <div className="p-4">
            <SkeletonList rows={3} />
          </div>
        ) : !data?.length ? (
          <EmptyState compact art="check" title="כל מסמכי הרכב בתוקף" />
        ) : (
          <ul>
            {data.map((r) => (
              <li key={`${r.vehicle_id}-${r.kind_name}-${r.expires_at}`}>
                <Link
                  to={`/vehicles/${r.vehicle_id}?tab=documents`}
                  className="flex w-full items-center gap-2.5 border-b border-line-subtle px-4 py-2.5 text-start transition-colors last:border-0 hover:bg-hover"
                >
                  <span className="min-w-0 flex-1">
                    <span className="block truncate type-body font-medium">
                      {r.name} · {r.kind_name}
                    </span>
                    <span className="block truncate type-caption tabular text-ink-tertiary">
                      {formatPlate(r.plate_number)} · {fmtDate(r.expires_at)}
                    </span>
                  </span>
                  <span
                    className="shrink-0 rounded-full px-2 py-0.5 type-caption font-semibold"
                    style={{
                      background: `color-mix(in srgb, ${DOC_STATE_COLORS[r.status]} 14%, transparent)`,
                      color: DOC_STATE_COLORS[r.status],
                    }}
                  >
                    {r.status === 'expired' ? DOC_STATE_LABELS.expired : expiryLabel(r.expires_at)}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </CardBody>
    </Card>
  )
}
