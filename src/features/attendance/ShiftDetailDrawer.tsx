/**
 * ממה מורכבת המשמרת.
 *
 * המסך היחיד שמתרגם את task_ids לרצף שאפשר לקרוא: מה קודם, מה אחר כך, כמה
 * זמן ממתינים בין לבין, ומתי נוסעים חזרה. הוא משרת גם את לוח המנהל וגם את
 * הלוח האישי בלי הסתעפות — ההרשאה מוכרעת ב-RPC, וענף ה"עצמי" שלו דורש בדיוק
 * את המפתח שהמסך האישי כבר מגודר עליו.
 */
import { useNavigate } from 'react-router'
import {
  Clock,
  ExternalLink,
  ICON,
  MapPin,
  Package,
  STROKE,
  Timer,
  Truck,
  User,
  Users,
} from '../../components/ui/icons'
import { Badge, Drawer, ErrorState, LocationText, Skeleton, cx } from '../../components/ui'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { chipPaint } from '../../lib/colors'
import { errorMessage } from '../../lib/errors'
import { useShiftTasks } from './attendanceQueries'
import {
  ASSIGNMENT_ROLE_LABELS,
  WORK_SITE_LABELS,
  fmtDayLabel,
  fmtDuration,
  fmtShiftRange,
} from './shiftFormat'
import type { ShiftGroupMember } from './shiftBoard'
import type { PlannedShift, ShiftTaskRow } from '../../types/domain'

const NEUTRAL = '#64748b'

const hhmm = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleTimeString('he-IL', { hour: '2-digit', minute: '2-digit', hour12: false }) : ''

export function ShiftDetailDrawer({
  shift,
  employeeName,
  team,
  onClose,
}: {
  shift: PlannedShift | null
  /** שם העובד. נשאר ריק בלוח האישי, שבו "המשמרת שלי" מדויק יותר. */
  employeeName?: string | null
  /**
   * כל מי שעובד במשמרת, כשהיא נפתחה מצ׳יפ מקובץ בציר השעות. הרצף שמתחתיו
   * זהה לכולם — אותן משימות — ולכן ההבדל היחיד ששווה להראות כאן הוא מי מהם
   * מתחיל במחסן.
   */
  team?: ShiftGroupMember[]
  onClose: () => void
}) {
  const { data, isLoading, error } = useShiftTasks(shift?.profile_id ?? null, shift?.task_ids ?? null)

  if (!shift) return null

  const tasks = data?.tasks ?? []
  const totals = data?.totals
  // הכותרת נשענת על השורה שנלחצה כדי להצטייר מיד, ומתיישבת מול השרת כשהוא חוזר
  const startsAtWarehouse = (data?.shift.work_site ?? shift.work_site) === 'warehouse'
  const warehouseName = data?.shift.warehouse_name ?? shift.warehouse_name
  const travel = totals?.travel_hours ?? shift.travel_hours ?? 0

  return (
    <Drawer
      open={!!shift}
      onClose={onClose}
      title={employeeName || data?.full_name || 'המשמרת שלי'}
      description={
        <span className="flex flex-wrap items-center gap-x-2 gap-y-1">
          <span>{fmtDayLabel(shift.work_date)}</span>
          {shift.seq > 1 && <span className="opacity-70">· משמרת {shift.seq}</span>}
        </span>
      }
    >
      <div className="space-y-4">
        <div className="flex flex-wrap items-center gap-1.5">
          <Badge tone="info">
            <Clock size={ICON.sm} strokeWidth={STROKE} />
            <span dir="ltr" className="tabular">
              {fmtShiftRange(data?.shift.start ?? shift.shift_start, data?.shift.end ?? shift.shift_end)}
            </span>
          </Badge>
          <Badge tone="neutral">{fmtDuration(shift.planned_hours)} ש׳</Badge>
          <Badge tone="neutral">
            {tasks.length || shift.task_ids.length} {tasks.length === 1 ? 'משימה' : 'משימות'}
          </Badge>
          {startsAtWarehouse && (
            <Badge tone="warning">
              <Package size={ICON.sm} strokeWidth={STROKE} />
              {warehouseName ? `יוצא מ${warehouseName}` : 'יוצא מהמחסן'}
            </Badge>
          )}
        </div>

        {team && team.length > 1 && (
          <div className="space-y-1.5">
            <div className="type-overline">מי במשמרת</div>
            <div className="flex flex-wrap gap-1.5">
              {team.map((m) => (
                <span
                  key={m.shift.profile_id}
                  className={cx(
                    'inline-flex items-center gap-1 rounded-full border px-2 py-0.5 type-caption',
                    m.fromWarehouse
                      ? 'border-warning-border bg-warning-subtle text-warning-text'
                      : 'border-line bg-subtle',
                  )}
                >
                  {m.fromWarehouse && <Package size={ICON.xs} strokeWidth={STROKE} />}
                  {m.name}
                  {m.fromWarehouse && (
                    <span className="tabular opacity-80" dir="ltr">
                      {hhmm(m.shift.shift_start)}
                    </span>
                  )}
                </span>
              ))}
            </div>
          </div>
        )}

        {error ? (
          <ErrorState error={errorMessage(error)} />
        ) : isLoading ? (
          <div className="space-y-2">
            <Skeleton className="h-24 w-full" />
            <Skeleton className="h-24 w-full" />
          </div>
        ) : (
          <ol className="relative">
            {/* פס אחד ומוחלט, כדי שהוא לא ייקטע בין הפריטים */}
            <span aria-hidden className="absolute inset-y-2 start-[7px] w-px bg-line" />

            {startsAtWarehouse && (
              <RailNode
                icon={<Package size={ICON.xs} strokeWidth={STROKE} />}
                time={hhmm(tasks[0]?.start_at ?? shift.shift_start)}
                text={warehouseName ? `יציאה מ${warehouseName}` : 'יציאה מהמחסן'}
              />
            )}

            {tasks.map((t) => (
              <li key={t.task_id}>
                {t.gap_minutes != null && t.gap_minutes > 0 && (
                  /* ההמתנה היא חלק מהמשמרת — רווח ריק היה מסתיר אותה */
                  <div className="relative py-1 ps-6">
                    <span
                      aria-hidden
                      className="absolute inset-y-0 start-[7px] w-0 border-s border-dashed border-line-strong"
                    />
                    <span className="inline-flex items-center gap-1 type-caption text-ink-tertiary">
                      <Timer size={ICON.xs} strokeWidth={STROKE} />
                      המתנה {fmtDuration(t.gap_minutes / 60)}
                    </span>
                  </div>
                )}
                <div className="relative py-1.5 ps-6">
                  <span
                    aria-hidden
                    className="absolute start-0 top-3.5 size-3.5 rounded-full ring-2 ring-surface"
                    style={{ background: t.customer_color ?? NEUTRAL }}
                  />
                  <TaskCard task={t} />
                </div>
              </li>
            ))}

            {travel > 0 && (
              <RailNode
                icon={<Truck size={ICON.xs} strokeWidth={STROKE} />}
                text={`נסיעה חזרה ${fmtDuration(travel)}`}
              />
            )}
            <RailNode
              terminal
              icon={<Clock size={ICON.xs} strokeWidth={STROKE} />}
              time={hhmm(data?.shift.end ?? shift.shift_end)}
              text="סיום המשמרת"
            />
          </ol>
        )}

        {totals && (
          <div className="surface grid grid-cols-3 gap-2 p-3 text-center">
            <Total label="עבודה" value={`${fmtDuration(totals.work_hours)} ש׳`} />
            <Total label="נסיעה" value={`${fmtDuration(totals.travel_hours)} ש׳`} />
            <Total label="המתנה" value={`${fmtDuration(totals.idle_minutes / 60)} ש׳`} />
          </div>
        )}
      </div>
    </Drawer>
  )
}

function Total({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="type-overline">{label}</div>
      <div className="type-subtitle tabular">{value}</div>
    </div>
  )
}

function RailNode({
  icon,
  time,
  text,
  terminal,
}: {
  icon: React.ReactNode
  time?: string
  text: string
  terminal?: boolean
}) {
  return (
    <li className="relative py-1.5 ps-6">
      <span
        aria-hidden
        className={cx(
          'absolute start-0 top-2.5 flex size-3.5 items-center justify-center rounded-full ring-2 ring-surface',
          terminal ? 'bg-ink-tertiary' : 'bg-subtle',
        )}
      />
      <span className="inline-flex items-center gap-1.5 type-caption text-ink-secondary">
        {icon}
        {time && (
          <span className="tabular" dir="ltr">
            {time}
          </span>
        )}
        <span>{text}</span>
      </span>
    </li>
  )
}

function TaskCard({ task: t }: { task: ShiftTaskRow }) {
  const navigate = useNavigate()
  const has = useAuth((s) => s.has)
  // קישור לאירוע רק למי שמורשה לפתוח אותו — לעובד מן השורה זה כרטיס סטטי
  const canOpen = !!t.event_id && has(PERM.EVENTS_VIEW)
  const paint = chipPaint(t.customer_color)
  const Tag = canOpen ? 'button' : 'div'

  const meta = [
    t.task_type_name,
    t.customer_name,
    t.end_client_name || (t.event_number ? `אירוע #${t.event_number}` : null),
  ].filter(Boolean)

  return (
    <Tag
      type={canOpen ? 'button' : undefined}
      onClick={canOpen ? () => navigate(`/events/${t.event_id}`) : undefined}
      className={cx(
        'surface relative w-full overflow-hidden p-2.5 text-start ps-3.5',
        canOpen && 'transition-colors hover:bg-hover',
      )}
    >
      <span
        aria-hidden
        className="absolute inset-y-0 start-0 w-1"
        style={{ background: paint.railColor }}
      />

      <div className="flex flex-wrap items-baseline justify-between gap-x-2 gap-y-0.5">
        <span className="type-subtitle font-semibold">{t.title}</span>
        <span className="flex shrink-0 items-center gap-1.5 type-caption text-ink-secondary">
          <span className="tabular" dir="ltr">
            {hhmm(t.start_at)}–{hhmm(t.end_at)}
          </span>
          {t.hours_count != null && <span className="tabular">({fmtDuration(t.hours_count)})</span>}
          {canOpen && <ExternalLink size={ICON.xs} strokeWidth={STROKE} className="opacity-60" />}
        </span>
      </div>

      {meta.length > 0 && (
        <div className="mt-0.5 truncate type-caption text-ink-tertiary">{meta.join(' · ')}</div>
      )}

      <div className="mt-1.5 flex flex-wrap items-center gap-x-2.5 gap-y-1 type-caption text-ink-secondary">
        <Chip icon={<MapPin size={ICON.xs} strokeWidth={STROKE} />}>
          {t.work_site === 'warehouse' && t.warehouse_name ? t.warehouse_name : WORK_SITE_LABELS[t.work_site]}
        </Chip>
        {t.location_text && (
          <Chip icon={<MapPin size={ICON.xs} strokeWidth={STROKE} />}>
            <LocationText value={t.location_text} />
          </Chip>
        )}
        {t.truck_name && <Chip icon={<Truck size={ICON.xs} strokeWidth={STROKE} />}>{t.truck_name}</Chip>}
        {t.my_role && (
          <Chip icon={<User size={ICON.xs} strokeWidth={STROKE} />}>{ASSIGNMENT_ROLE_LABELS[t.my_role]}</Chip>
        )}
        {t.assigned_count > 1 && (
          <Chip icon={<Users size={ICON.xs} strokeWidth={STROKE} />}>{t.assigned_count} משובצים</Chip>
        )}
        {t.status_name && <Badge color={t.status_color ?? undefined}>{t.status_name}</Badge>}
      </div>

      {t.team && t.team.length > 0 && (
        <div className="mt-1 truncate type-caption text-ink-tertiary">עם: {t.team.join(', ')}</div>
      )}

      {t.notes && <div className="mt-1.5 rounded-md bg-subtle p-2 type-caption whitespace-pre-wrap">{t.notes}</div>}
    </Tag>
  )
}

function Chip({ icon, children }: { icon: React.ReactNode; children: React.ReactNode }) {
  return (
    <span className="inline-flex min-w-0 items-center gap-1">
      <span className="shrink-0 opacity-70">{icon}</span>
      <span className="truncate">{children}</span>
    </span>
  )
}
