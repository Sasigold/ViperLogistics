/**
 * זוג חיצים משני צדי שם החודש — התנועה של הדשבורד בין חודשים.
 *
 * שני מסכים ולא אחד: ‏`DashboardPage` (צוות וקבלן) ו-`CustomerDashboard`,
 * שהוא מסך אחר לגמרי (`HomeRoute` מפצל ביניהם לפי `user_kind`). זו הסיבה
 * שהרכיב הזה קיים בכלל — בלעדיו התנועה נכתבה פעם אחת ונשארה בחצי מהקהל.
 *
 * הכיוון הוא של RTL, כמו בכל בורר חודש אחר במערכת (דוח הנוכחות, רישום
 * התקבולים, הפורטל): **ימין הוא אחורה.** ולחיצה על שם החודש עצמו מחזירה
 * לחודש הנוכחי — אותו idiom, ולכן אותה ציפייה.
 */
import { IconButton } from '../../components/ui'
import { ChevronLeft, ChevronRight, ICON, STROKE } from '../../components/ui/icons'
import { fmtMonth } from '../../lib/dates'

export function MonthStepper({
  month,
  onStep,
  onToday,
  atToday,
}: {
  /** התאריך שממנו נגזרת הכותרת — ה-1 בחודש המוצג. */
  month: Date
  onStep: (delta: number) => void
  onToday: () => void
  /** מצביע על החודש הנוכחי, ולכן "חזרה להיום" אינה פעולה. */
  atToday: boolean
}) {
  return (
    <div className="flex shrink-0 items-center gap-0.5">
      <IconButton size="sm" variant="ghost" label="חודש קודם" onClick={() => onStep(-1)}>
        <ChevronRight size={ICON.md} strokeWidth={STROKE} aria-hidden />
      </IconButton>
      <button
        type="button"
        onClick={onToday}
        title="חזרה לחודש הנוכחי"
        disabled={atToday}
        className="min-w-28 rounded-md px-2 py-1 text-center type-caption font-medium text-ink transition-colors hover:bg-hover disabled:cursor-default disabled:hover:bg-transparent"
      >
        {fmtMonth(month)}
      </button>
      <IconButton size="sm" variant="ghost" label="חודש הבא" onClick={() => onStep(1)}>
        <ChevronLeft size={ICON.md} strokeWidth={STROKE} aria-hidden />
      </IconButton>
    </div>
  )
}
