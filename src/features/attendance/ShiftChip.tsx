/**
 * צ׳יפ של משמרת אחת.
 *
 * אותו רכיב משרת את שלושת המקומות שבהם משמרת מצוירת — תא בטבלת השיבוץ,
 * אירוע בציר הזמן, וכותרת מגירת הפירוט — כדי שמשמרת לא תיראה אחרת בכל מסך.
 * הגודל נקבע במשתנה --vl-shift-fs שיושב על המכל, ולא כאן: הצפיפות היא
 * החלטה של הלוח, לא של הצ׳יפ.
 */
import { ICON, MapPin, STROKE, Truck } from '../../components/ui/icons'
import { cx } from '../../components/ui'
import { chipPaint } from '../../lib/colors'
import { fmtDuration, fmtShiftRange, fmtWorkEnd } from './shiftFormat'
import type { PlannedShift } from '../../types/domain'

/** הגודל של הטקסט הצפוף בלוחות המשמרות. ברירת המחדל תואמת את לוח העבודה. */
export const SHIFT_FS = 'text-[length:var(--vl-shift-fs,0.8125rem)]'

export function ShiftChip({
  shift,
  name,
  onClick,
  className,
}: {
  shift: PlannedShift
  /** שם העובד — מוצג רק בציר הזמן, שבו כל המשמרות של כולם באותה עמודה */
  name?: string | null
  onClick?: () => void
  className?: string
}) {
  const paint = chipPaint(shift.customer_color)
  const tasks = shift.task_ids?.length ?? 0
  const Tag = onClick ? 'button' : 'div'
  /**
   * הנסיעה חזרה למחסן, שכבר כלולה ב-`shift_end` (0079 §4). היא 0 למי שהגיע
   * ישירות לשטח, ולכן המספר הזה הוא גם השאלה "האם חוזרים בכלל" וגם התשובה
   * "מתי יורדים מהעבודה" — שעת סיום שהצ׳יפ הראה עד היום כאילו עבדו עד לה.
   */
  const travel = shift.travel_hours ?? 0
  const title = [
    shift.label ?? 'משמרת',
    fmtShiftRange(shift.shift_start, shift.shift_end),
    travel > 0 &&
      `סיום עבודה ${fmtWorkEnd(shift.shift_end, travel)}, ואחריו נסיעה חזרה ${fmtDuration(travel)}`,
  ]
    .filter(Boolean)
    .join(' · ')

  return (
    <Tag
      type={onClick ? 'button' : undefined}
      onClick={onClick}
      title={title}
      className={cx(
        'flex w-full min-w-0 flex-col gap-0.5 overflow-hidden rounded-md px-1.5 py-1 text-start',
        SHIFT_FS,
        onClick && 'transition-[filter,box-shadow] hover:shadow-md hover:brightness-105',
        className,
      )}
      style={{ background: paint.background, color: paint.color }}
    >
      {name && <span className="truncate font-bold leading-tight">{name}</span>}
      <span className="truncate font-semibold leading-tight">{shift.label ?? 'משמרת'}</span>
      <span className="flex min-w-0 items-center gap-1 leading-tight opacity-90">
        <span className="truncate tabular" dir="ltr">
          {fmtShiftRange(shift.shift_start, shift.shift_end)}
        </span>
        {shift.work_site === 'warehouse' && (
          <MapPin size={ICON.xs} strokeWidth={STROKE} className="shrink-0" aria-label="יוצא מהמחסן" />
        )}
        {/* התאום של הסימון שמימין: שם — יוצאים מהמחסן, כאן — חוזרים אליו,
            והשעה שבצ׳יפ היא שעת ההגעה למחסן ולא סוף העבודה */}
        {travel > 0 && (
          <Truck size={ICON.xs} strokeWidth={STROKE} className="shrink-0" aria-label="כולל נסיעה חזרה למחסן" />
        )}
        {/* מספר המשימות הוא מה שהמגירה תפרט — כאן הוא רק רמז שיש מה לפתוח */}
        {tasks > 1 && (
          <span className="ms-auto shrink-0 rounded-full bg-black/20 px-1 font-bold tabular">{tasks}</span>
        )}
      </span>
    </Tag>
  )
}
