import { AlertTriangle, ICON, STROKE } from '../../components/ui/icons'
import { cx } from '../../components/ui'
import { TRAVEL_GAP_TEXT, travelGapReasonText, type TravelGapReason } from './travelGap'

/** השורה האדומה: המשפט, ואחריו למה. ‏`compact` — אייקון בלבד, עם tooltip. */
export function TravelGapNote({
  reason,
  compact,
  className,
}: {
  reason: TravelGapReason
  compact?: boolean
  className?: string
}) {
  const full = `${TRAVEL_GAP_TEXT} — ${travelGapReasonText(reason)}`
  if (compact) {
    return (
      <span title={full} aria-label={full} className={cx('inline-flex text-error-text', className)}>
        <AlertTriangle size={ICON.sm} strokeWidth={STROKE} />
      </span>
    )
  }
  return (
    <p
      role="alert"
      className={cx(
        'flex items-start gap-1.5 rounded-md border border-error-border bg-error-subtle px-2 py-1.5 type-caption font-medium text-error-text',
        className,
      )}
    >
      <AlertTriangle size={ICON.sm} strokeWidth={STROKE} className="mt-0.5 shrink-0" />
      <span>
        {TRAVEL_GAP_TEXT}
        <span className="font-normal"> — {travelGapReasonText(reason)}</span>
      </span>
    </p>
  )
}
