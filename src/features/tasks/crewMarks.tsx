/**
 * הסימונים שנאמרים לצד שם של משובץ: מה הוא, מאיפה הוא, ומאיפה הוא מתחיל.
 *
 * עד 0162 אלה היו אימוג׳י — 👷 לעובד קבלן, 🚚 לנהג, 🏭 למי שיוצא מהמחסן —
 * ושלושתם נכשלו באותו מקום: אימוג׳י מצויר בגופן של מערכת ההפעלה, ולכן הוא
 * נראה אחרת בכל מכשיר, אינו מקבל את צבע הטקסט (וב-מצב כהה נשאר כתם צבעוני),
 * ובגודל של תא בלו״ז — תשע פיקסלים — הוא נמרח. ‏`lucide` בקו אחיד, בצבע
 * הטקסט ובגודל שהתא נותן, הוא אותו סימון בכל מקום.
 *
 * לכל סימון יש `title` בעברית: התא צר, השם הוא מה שנקרא בו, והסימון צריך
 * להיות מוסבר למי שאינו מכיר אותו — וגם למי שקורא את המסך בהקראה.
 */
import { Building2, Crown, HardHat, STROKE, Truck, Warehouse } from '../../components/ui/icons'
import { cx } from '../../components/ui'
import type { CrewPerson, CrewSource } from './crew'

/** המקור שממנו הגיע האדם. לצוות הפנימי אין סימון — הוא ברירת המחדל. */
const SOURCE: Record<CrewSource, { icon: typeof HardHat; title: string } | null> = {
  staff: null,
  contractor: { icon: HardHat, title: 'עובד של קבלן' },
  customer: { icon: Building2, title: 'עובד של הלקוח' },
}

function Mark({
  icon: Icon,
  title,
  size,
  className,
}: {
  icon: typeof HardHat
  title: string
  size: number | string
  className?: string
}) {
  return (
    <span className={cx('inline-flex shrink-0 items-center text-ink-secondary', className)} title={title}>
      <Icon size={size} strokeWidth={STROKE} aria-hidden />
      <span className="sr-only">{title}</span>
    </span>
  )
}

/**
 * מה שנאמר לצד השם של משובץ אחד.
 *
 * הסדר קבוע — מקור, ראשות, נהיגה, מחסן — כדי ששורה מול שורה תיקרא כטור ולא
 * כערבוב, והכתר מוצג רק היכן שהראשות אינה כתובה ממילא בשם השורה.
 */
export function CrewMarks({
  person,
  lead,
  size = '1em',
  className,
}: {
  person: Pick<CrewPerson, 'source' | 'drives' | 'site'>
  /** להוסיף את סימון הראשות. מיותר בתא שכולו "ראש צוות". */
  lead?: boolean
  /**
   * ברירת המחדל היא `1em`, ולא מספר: הסימון יושב לצד שם, והלו״ז מקטין את
   * הטקסט שלו בארבע דרגות צפיפות. סימון בגודל קבוע היה גדל מול השם ככל
   * שהלוח מצטמצם — בדיוק שם שהמקום הכי צר.
   */
  size?: number | string
  className?: string
}) {
  const source = SOURCE[person.source]
  return (
    <>
      {source && <Mark icon={source.icon} title={source.title} size={size} className={className} />}
      {lead && <Mark icon={Crown} title="ראש צוות" size={size} className={className} />}
      {person.drives && <Mark icon={Truck} title="נהג" size={size} className={className} />}
      {/* מי שיוצא מהמחסן מתחיל בשעה אחרת מכולם, ולכן הסימון נשאר לצד השם */}
      {person.site === 'warehouse' && (
        <Mark icon={Warehouse} title="יוצא מהמחסן" size={size} className={className} />
      )}
    </>
  )
}
