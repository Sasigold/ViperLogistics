/**
 * צ׳יפ של משמרת שעובדים בה כמה אנשים.
 *
 * בציר השעות משמרת אחת שמשובצים אליה שלושה עובדים הייתה נמתחת לשלושה צ׳יפים
 * זהים זה לצד זה, ומי שהסתכל על הלוח לא יכול היה לדעת אם יש שם שלוש משמרות
 * או אחת. כאן היא צ׳יפ אחד ורשימת שמות, וכשיש רק חבר אחד הצ׳יפ חוזר להיות
 * ShiftChip רגיל — כדי שמשמרת של אדם אחד תיראה בדיוק כמו בטבלת השיבוץ.
 *
 * מי שיוצא מהמחסן מסומן פעמיים בכוונה: פס מקווקו שגובהו הוא בדיוק הנסיעה
 * מהמחסן לשטח, ואייקון ליד שמו. הפס עונה על "מתי" והאייקון על "מי", ובלי
 * שניהם הקבוצה מראה חלון שמתחיל מוקדם בלי לספר של מי הוא.
 *
 * ולמטה — הפס השני, של הנסיעה חזרה. שעת הסיום של המשמרת כללה אותה מאז
 * ומתמיד (0071: המשמרת מוסיפה את החזרה למחסן פעם אחת), ושום דבר בצ׳יפ לא
 * אמר זאת: הצ׳יפ נראה כאילו עובדים עד 15:00 בשטח, כשלמעשה יורדים מהעבודה
 * ב-14:15 ונוסעים. שני הפסים מקיפים את מה שהוא באמת עבודה בשטח.
 */
import { ICON, Package, STROKE, Truck, Users } from '../../components/ui/icons'
import { cx } from '../../components/ui'
import { chipPaint } from '../../lib/colors'
import { SHIFT_FS, ShiftChip } from './ShiftChip'
import { fmtShiftRange, fmtTime } from './shiftFormat'
import { warehouseBands } from './shiftBoard'
import type { ShiftGroup } from './shiftBoard'

/** הצללה מקווקוות על גבי צבע הלקוח — "זה עדיין אותה משמרת, אבל בדרך". */
const STRIPES =
  'repeating-linear-gradient(135deg, rgba(0,0,0,0.24) 0 5px, rgba(0,0,0,0) 5px 10px)'

export function ShiftGroupChip({
  group,
  onClick,
  className,
}: {
  group: ShiftGroup
  onClick?: () => void
  className?: string
}) {
  const { members, lead, onsiteStart, onsiteEnd, warehouseStart, warehouseName } = group

  if (members.length === 1) {
    return <ShiftChip shift={lead} name={members[0].name} onClick={onClick} className={className} />
  }

  const paint = chipPaint(lead.customer_color)
  const { lead: leadPct, tail: tailPct } = warehouseBands(group)
  const label = lead.label ?? 'משמרת'
  // כשכולם יוצאים מהמחסן אין ממה להבדיל אותם, ולכן אין פס ואין אייקון לשם
  const mixed = leadPct > 0
  const wh = members.filter((m) => m.fromWarehouse)
  const Tag = onClick ? 'button' : 'div'

  const title = [
    label,
    fmtShiftRange(onsiteStart ?? group.start, onsiteEnd ?? group.end),
    warehouseStart &&
      `יציאה מ${warehouseName ?? 'המחסן'} ב-${fmtTime(warehouseStart)}: ${wh.map((m) => m.name).join(', ')}`,
    onsiteEnd &&
      `נסיעה חזרה ל${warehouseName ?? 'מחסן'} ב-${fmtTime(onsiteEnd)}, סיום ${fmtTime(group.end)}`,
    `${members.length} עובדים: ${members.map((m) => m.name).join(', ')}`,
  ]
    .filter(Boolean)
    .join(' · ')

  return (
    <Tag
      type={onClick ? 'button' : undefined}
      onClick={onClick}
      title={title}
      className={cx(
        'flex w-full min-w-0 flex-col overflow-hidden rounded-md text-start',
        SHIFT_FS,
        onClick && 'transition-[filter,box-shadow] hover:shadow-md hover:brightness-105',
        className,
      )}
      style={{ background: paint.background, color: paint.color }}
    >
      {/* הפס נגמר בשעה שבה מתחילה העבודה בשטח, ולכן הטקסט שמתחתיו יושב על
          החלון המשותף לכולם ולא על הנסיעה של חלקם. שעת היציאה מהמחסן נכתבת
          בתוך הפס ולא מתחתיו — בצ׳יפ של משמרת קצרה כל שורה בגוף באה על חשבון
          שמות העובדים, וזה בדיוק מה שהתצוגה הזאת נועדה להראות. */}
      {mixed && (
        <span
          className="flex shrink-0 items-start gap-1 overflow-hidden border-b border-dashed border-current/50 px-1.5 pt-0.5 leading-tight"
          style={{ height: `${leadPct}%`, backgroundImage: STRIPES }}
        >
          <Package size={ICON.xs} strokeWidth={STROKE} className="mt-px shrink-0" />
          <span className="shrink-0 tabular" dir="ltr">
            {fmtTime(warehouseStart!)}
          </span>
          <span className="truncate opacity-90">{warehouseName ?? 'מחסן'}</span>
        </span>
      )}

      <span className="flex min-h-0 flex-1 flex-col gap-0.5 px-1.5 py-1">
        <span className="flex min-w-0 items-center gap-1 leading-tight">
          <span className="truncate font-semibold">{label}</span>
          <span className="ms-auto inline-flex shrink-0 items-center gap-0.5 rounded-full bg-black/20 px-1 font-bold">
            <Users size={ICON.xs} strokeWidth={STROKE} />
            <span className="tabular">{members.length}</span>
          </span>
        </span>

        <span className="flex min-w-0 items-center gap-1 leading-tight opacity-90">
          {/* החלון שבו באמת עובדים בשטח. הנסיעות משני צדיו הן הפסים, ולכן
              הכתיבה שלהן גם כאן הייתה אומרת את אותו דבר פעמיים. */}
          <span className="truncate tabular" dir="ltr">
            {fmtShiftRange(onsiteStart ?? group.start, onsiteEnd ?? group.end)}
          </span>
          {/* משמרת שכולה יוצאת מהמחסן: אין פס, ולכן הסימון יושב על השעות */}
          {warehouseStart && !mixed && (
            <Package size={ICON.xs} strokeWidth={STROKE} className="shrink-0" aria-label="יוצאים מהמחסן" />
          )}
        </span>

        {/* הנקודה המפרידה יושבת *בתוך* הפריט ולא בינו לבין הבא, כדי שגלישה
            לשורה חדשה לא תפתח שורה בנקודה מיותמת */}
        <span className="flex min-h-0 flex-1 flex-wrap content-start gap-x-1 overflow-hidden font-medium leading-tight">
          {members.map((m, i) => (
            <span key={m.shift.profile_id} className="inline-flex min-w-0 items-center gap-0.5">
              {i > 0 && <span className="opacity-50">·</span>}
              {mixed && m.fromWarehouse && (
                <Package size={ICON.xs} strokeWidth={STROKE} className="shrink-0" aria-label="מהמחסן" />
              )}
              <span className="truncate">{m.name}</span>
            </span>
          ))}
        </span>
      </span>

      {/* הפס התחתון מתחיל בשעה שבה יורדים מהעבודה ונגמר בסוף המשמרת. אותה
          הצללה בדיוק כמו למעלה — זו אותה נסיעה, בכיוון ההפוך — ולכן שעת
          הסיום נכתבת בתוכו: היא השעה שבה מגיעים למחסן, לא שעת סוף העבודה. */}
      {tailPct > 0 && (
        <span
          className="flex shrink-0 items-start gap-1 overflow-hidden border-t border-dashed border-current/50 px-1.5 pb-0.5 leading-tight"
          style={{ height: `${tailPct}%`, backgroundImage: STRIPES }}
        >
          <Truck size={ICON.xs} strokeWidth={STROKE} className="mt-px shrink-0" />
          <span className="shrink-0 tabular" dir="ltr">
            {fmtTime(group.end)}
          </span>
          <span className="truncate opacity-90">חזרה{warehouseName ? ` ל${warehouseName}` : ' למחסן'}</span>
        </span>
      )}
    </Tag>
  )
}
