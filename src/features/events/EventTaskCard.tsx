/**
 * משימה אחת של האירוע, בתצוגת הכרטיסים.
 *
 * הכרטיס נשען על ‏`work_board_view`, ולכן כל מה שהוא מצייר כבר סונן בשרת לפי
 * מה שהקורא רשאי לראות — מחיר שאין לו הרשאה אליו מגיע ‏null ולא 0.
 *
 * ההיררכיה היא של מי שסורק רשימה ולא של מי שקורא רשומה: פס הצבע בקצה נותן את
 * הסוג בלי מילים, הכותרת והסטטוס עונים "מה ומה מצבו", שורת מטא אחת עונה
 * "מתי", והתחתית עונה "מי". חמישה מפלסים במקום שבעה — הכרטיס הקודם עטף כל
 * תאריך ושעה בקופסה אפורה ממוסגרת משלו, וכפול מספר הכרטיסים ברשת זה מה
 * שהפך את הרשימה לרועשת.
 */
import { AvatarGroup, Badge, Select, StatusPill, cx, fmtMoney } from '../../components/ui'
import { Briefcase, Calendar, ChevronLeft, Clock, HardHat, ICON, STROKE } from '../../components/ui/icons'
import { fmtDate, fmtHours, fmtTime } from '../../lib/dates'
import type { PerformedBy, WorkBoardRow } from '../../types/domain'

/** פס הקצה נושא את סוג המשימה, ולכן אין יותר תג "הקמה"/"פירוק" בגוף הכרטיס. */
const EDGE: Record<string, string> = {
  setup: 'border-s-info',
  teardown: 'border-s-warning',
}

export function EventTaskCard({
  task: t,
  onOpen,
  showStaffing,
  performedByEnabled,
  canSetPerformedBy,
  onPerformedBy,
  performedByPending,
}: {
  task: WorkBoardRow
  /** ‏undefined כשלקורא אין רשות לפתוח את המשימה — אז הכרטיס אינו אינטראקטיבי. */
  onOpen?: () => void
  showStaffing?: boolean
  performedByEnabled?: boolean
  canSetPerformedBy?: boolean
  onPerformedBy?: (value: PerformedBy) => void
  performedByPending?: boolean
}) {
  const names = [
    ...(t.workers ?? []).map((w) => w.name),
    ...(t.drivers ?? []).map((d) => d.name),
    ...(t.contractor_worker_list ?? []).map((w) => w.name),
  ]

  const time = [fmtTime(t.onsite_start_time), t.onsite_end_time ? fmtTime(t.onsite_end_time) : null]
    .filter(Boolean)
    .join('–')

  return (
    <div
      /* ‏`role`/`tabIndex`/`onKeyDown`: עד כאן זה היה `<div onClick>` — לחיץ
         בעכבר בלבד ובלתי נגיש למקלדת. */
      role={onOpen ? 'button' : undefined}
      tabIndex={onOpen ? 0 : undefined}
      onClick={onOpen}
      onKeyDown={
        onOpen
          ? (e) => {
              if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault()
                onOpen()
              }
            }
          : undefined
      }
      className={cx(
        'group flex flex-col rounded-xl border border-s-2 border-line-subtle bg-surface p-3.5 transition-colors duration-150',
        EDGE[t.task_type_code ?? ''] ?? 'border-s-line-strong',
        onOpen &&
          'cursor-pointer hover:border-line hover:bg-hover focus-visible:outline-none focus-visible:focus-ring',
      )}
    >
      {/* מה, ומה מצבו */}
      <div className="flex items-start justify-between gap-2">
        <h3 className="min-w-0 type-title">{t.title || t.task_type_name}</h3>
        <div className="flex shrink-0 flex-col items-end gap-1">
          <StatusPill color={t.status_color}>{t.status_name}</StatusPill>
          {t.customer_price != null && (
            <span dir="ltr" className="type-caption font-semibold tabular text-success-text">
              {fmtMoney(t.customer_price)}
            </span>
          )}
        </div>
      </div>

      {/* מתי — שורה אחת, בלי קופסאות */}
      <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 type-caption tabular text-ink-secondary">
        <span className="inline-flex items-center gap-1">
          <Calendar size={ICON.xs} strokeWidth={STROKE} className="text-ink-tertiary" />
          {fmtDate(t.task_date)}
        </span>
        <span className="inline-flex items-center gap-1">
          <Clock size={ICON.xs} strokeWidth={STROKE} className="text-ink-tertiary" />
          <span dir="ltr">{time || '—'}</span>
        </span>
        {t.hours_count != null && (
          <span className="text-ink-tertiary">{fmtHours(t.hours_count)} שעות</span>
        )}
        {t.execution_method_name && !t.contractor_name && (
          <Badge>{t.execution_method_name}</Badge>
        )}
      </div>

      {/* ‏0120: "בוצע ע"י" — רק אצל לקוח שהאפשרות מופעלת אצלו */}
      {performedByEnabled && (
        <div
          className="mt-2.5 flex items-center gap-2"
          /* הבורר יושב בתוך כרטיס לחיץ; בלי זה כל בחירה פותחת גם את המגירה */
          onClick={(e) => e.stopPropagation()}
          onKeyDown={(e) => e.stopPropagation()}
        >
          <span className="type-caption text-ink-tertiary">בוצע ע"י</span>
          <Select
            selectSize="sm"
            aria-label={'בוצע ע"י'}
            value={t.performed_by}
            disabled={!canSetPerformedBy || performedByPending}
            onChange={(e) => onPerformedBy?.(e.target.value as PerformedBy)}
          >
            <option value="viper">וייפר</option>
            <option value="arko">ארקו</option>
          </Select>
        </div>
      )}

      {/* מי — קו הפרדה אחד, לא שניים */}
      <div className="mt-3 flex items-center justify-between gap-2 border-t border-line-subtle pt-2.5">
        <div className="flex min-w-0 flex-wrap items-center gap-x-2.5 gap-y-1 type-caption">
          {names.length > 0 ? (
            <span className="inline-flex items-center gap-1.5">
              <AvatarGroup names={names} max={4} size="xs" />
              <span className="tabular text-ink-tertiary">
                {names.length}/{t.worker_count || '—'}
              </span>
            </span>
          ) : showStaffing ? (
            <span className="text-ink-tertiary">לא שובצו עובדים</span>
          ) : null}
          {t.team_lead_name && (
            <span className="inline-flex items-center gap-1 text-ink-secondary">
              <HardHat size={ICON.xs} strokeWidth={STROKE} className="text-warning-text" />
              {t.team_lead_name}
            </span>
          )}
          {t.contractor_name && (
            <span className="inline-flex items-center gap-1 text-ink-secondary">
              <Briefcase size={ICON.xs} strokeWidth={STROKE} className="text-info-text" />
              {t.contractor_name}
            </span>
          )}
        </div>
        {onOpen && (
          /* קבוע ולא ב-hover בלבד: רמז שמופיע רק בריחוף אינו קיים במגע */
          <ChevronLeft
            aria-hidden
            size={ICON.sm}
            strokeWidth={STROKE}
            className="shrink-0 text-ink-tertiary transition-colors group-hover:text-primary"
          />
        )}
      </div>
    </div>
  )
}
