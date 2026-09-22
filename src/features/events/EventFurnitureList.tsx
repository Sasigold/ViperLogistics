/**
 * רשימת הריהוט של האירוע — המפרט, כפי שהוא בהזמנה ב-ViperFlow (0176, 0187).
 *
 * זו לשונית במסך המפרט ולא מסך משלה, וזו ההכרעה המרכזית כאן: לאירוע של שיא
 * עיצובים **המפרט הוא רשימת הריהוט**. עד היום המסמך הגיע כקובץ שמישהו העלה,
 * ומעכשיו הוא מגיע דרך ה-API של המערכת שהפיקה אותו — אותה שאלה, מקור אחר.
 * לכן אותו כפתור, אותו מפתח (`events.specs_view`), ואותו קהל: מי שנוסע
 * לאירוע הוא מי שצריך לדעת מה לטעון (0102).
 *
 * ‏**מה שהשתנה ב-0187, ולמה:**
 *
 *   • ‏**נמשך ב-API בלחיצה, ואינו נשמר.** התמונות הן החלק הכבד של הזמנה,
 *     והן חיות בקטלוג של ViperFlow ממילא. קריאה אחת בפתיחת המפרט נותנת את
 *     המצב העדכני, בלי נפח אצלנו ובלי תמונה שהתיישנה.
 *
 *   • ‏**בלי בנים, כמו בתעודת משלוח.** רכיב הוא בחירה בתוך האב, והבחירה
 *     כבר כתובה על האב ("צבע: ירוק"). מה שנשאר ברשימה הוא מה שבאמת עולה
 *     על המשאית.
 *
 *   • ‏**ומה ששמור נשאר הנפילה הרכה.** ‏API שאינו זמין, מפתח שלא הוגדר,
 *     רשת שנפלה — הרשימה עדיין מוצגת ממה שסונכרן (0176 §4.4), בלי תמונות
 *     ועם שורה שאומרת את זה. מפרט בלי תמונות טוב ממסך שגיאה.
 *
 * **בלי מחירים.** אין כאן סינון של עמודה — אין עמודת מחיר: לא בטבלה, לא
 * בטיפוס, ולא בתשובת הפונקציה, שנבנית שדה-שדה (0176 §2).
 */
import { useState } from 'react'
import { Armchair, ICON, Image as ImageIcon, RefreshCw, STROKE } from '../../components/ui/icons'
import { Badge, EmptyState, ErrorState, SkeletonList, cx, fmtRelative } from '../../components/ui'
import { furnitureSummaryText, specFromItems, specSummary } from './furniture'
import { useViperflowOrderItems, useViperflowSpec } from './furnitureQueries'
import type { ViperflowEventLink, ViperflowSpecLine } from '../../types/domain'

/**
 * התמונה של הפריט, ומה שיושב במקומה כשאין.
 *
 * ‏`onError` ולא רק `image_url === null`: הכתובת מגיעה מקטלוג חיצוני, ופריט
 * שתמונתו הוחלפה שם באמצע העונה יחזיר 404. ריבוע ריק במקום אייקון שבור.
 */
function SpecThumb({ line }: { line: ViperflowSpecLine }) {
  const [broken, setBroken] = useState(false)
  const shell =
    'flex size-12 shrink-0 items-center justify-center overflow-hidden rounded-lg border border-line-subtle bg-subtle'

  if (!line.image_url || broken) {
    return (
      <div className={shell} aria-hidden>
        <ImageIcon size={ICON.sm} strokeWidth={STROKE} className="text-ink-tertiary" />
      </div>
    )
  }
  return (
    <div className={shell}>
      <img
        src={line.image_url}
        alt=""
        loading="lazy"
        decoding="async"
        className="size-full object-cover"
        onError={() => setBroken(true)}
      />
    </div>
  )
}

export function EventFurnitureList({
  eventId,
  link,
  enabled,
}: {
  eventId: string
  link: ViperflowEventLink | null
  /** נטען רק כשהלשונית פתוחה: הזמנה גדולה היא מאות שורות */
  enabled: boolean
}) {
  const live = useViperflowSpec(eventId, enabled)
  /* הנפילה הרכה נטענת רק כשהחיה נכשלה — ולא "ליתר ביטחון" בכל פתיחה. */
  const stored = useViperflowOrderItems(eventId, enabled && live.isError)

  if (live.isLoading || (live.isError && stored.isLoading)) return <SkeletonList rows={5} />

  const spec = live.data ?? specFromItems(stored.data ?? [], link)
  const summary = specSummary(spec)
  const offline = !live.data

  /* קריאה שנכשלה ואין לה על מה ליפול היא שגיאה, ולא "ההזמנה ריקה": מסך
     שאומר "אין ריהוט" כשלא הצלחנו לקרוא הוא מסך שמשקר. */
  if (live.isError && spec.lines.length === 0) {
    return <ErrorState error={stored.error ?? live.error} onRetry={() => void live.refetch()} />
  }

  if (spec.lines.length === 0) {
    return (
      <EmptyState
        art="box"
        title="אין שורות ריהוט בהזמנה"
        description={
          link
            ? 'ההזמנה מקושרת, אך לא הגיעו ממנה שורות. היא עשויה להיות ריקה, או שטרם נכנס עדכון שנושא אותן.'
            : 'האירוע אינו מקושר להזמנה ב-ViperFlow.'
        }
      />
    )
  }

  return (
    <section className="flex min-w-0 flex-col overflow-hidden rounded-xl border border-line-subtle bg-surface">
      <header className="flex flex-wrap items-center gap-2 border-b border-line-subtle bg-subtle/60 px-3 py-2">
        <Armchair size={ICON.sm} strokeWidth={STROKE} className="text-ink-tertiary" />
        <span className="type-caption font-semibold text-ink">{furnitureSummaryText(summary)}</span>
        {(spec.order_number ?? link?.order_number) && (
          <Badge tone="neutral">הזמנה {spec.order_number ?? link?.order_number}</Badge>
        )}
        <span className="min-w-0 flex-1" />
        {link && (
          <span className="flex items-center gap-1 type-caption text-ink-tertiary">
            <RefreshCw size={ICON.sm} strokeWidth={STROKE} />
            סונכרן {fmtRelative(link.last_synced_at)}
          </span>
        )}
      </header>

      {/* הרשימה הוצגה ממה ששמור — וזה נאמר, כי חסרות בה התמונות ויכולה
          לחסור בה שורה שנוספה בדקה האחרונה. */}
      {offline && (
        <p className="border-b border-warning-border bg-warning-subtle px-3 py-2 type-caption text-warning-text">
          ‏ViperFlow אינו זמין כרגע, והרשימה מוצגת מהסנכרון האחרון — בלי תמונות.
        </p>
      )}

      {spec.truncated && (
        <p className="border-b border-line-subtle bg-subtle px-3 py-2 type-caption text-ink-secondary">
          ההזמנה ארוכה מהרשימה שמוצגת כאן. המסמך המלא נמצא ב-ViperFlow.
        </p>
      )}

      {/* טבלה ולא רשימה: במחסן קוראים "כמה" בעמודה אחת, מלמעלה למטה. */}
      <div className="overflow-x-auto">
        <table className="w-full text-start">
          <thead>
            <tr className="border-b border-line-subtle type-caption text-ink-tertiary">
              <th scope="col" className="w-16 px-3 py-2 text-start font-semibold">
                <span className="sr-only">תמונה</span>
              </th>
              <th scope="col" className="px-3 py-2 text-start font-semibold">
                פריט
              </th>
              <th scope="col" className="w-20 px-3 py-2 text-start font-semibold">
                כמות
              </th>
              <th scope="col" className="w-24 px-3 py-2 text-start font-semibold">
                עודף
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-line-subtle">
            {spec.lines.map((line, index) => (
              <tr key={line.id} className={cx(index % 2 === 1 && 'bg-subtle/30')}>
                <td className="px-3 py-2 align-top">
                  <SpecThumb line={line} />
                </td>
                <td className="px-3 py-2 align-top">
                  <span className="font-medium text-ink">{line.name}</span>
                  {line.is_custom && (
                    <>
                      {' '}
                      <Badge tone="neutral">פריט חופשי</Badge>
                    </>
                  )}
                  {line.options.length > 0 && (
                    <div className="type-caption text-ink-secondary">{line.options.join(' · ')}</div>
                  )}
                  {line.notes && (
                    <div className="type-caption text-ink-tertiary">{line.notes}</div>
                  )}
                </td>
                <td className="px-3 py-2 align-top tabular font-semibold text-ink">
                  {line.quantity}
                </td>
                <td className="px-3 py-2 align-top tabular text-ink-tertiary">
                  {line.spare_quantity > 0 ? `+${line.spare_quantity}` : '—'}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* הלוגיסטיקה אינה שורת ריהוט, אבל היא כן חלק ממה שהוזמן — ולכן היא
          נאמרת פעם אחת בתחתית ולא כשורה בטבלה. */}
      {(summary.trucks !== null || summary.workers !== null) && (
        <footer className="border-t border-line-subtle bg-subtle/40 px-3 py-2 type-caption text-ink-secondary">
          בהזמנה גם{' '}
          {[
            summary.trucks !== null && (summary.trucks === 1 ? 'משאית אחת' : `${summary.trucks} משאיות`),
            summary.workers !== null && (summary.workers === 1 ? 'עובד אחד' : `${summary.workers} עובדים`),
          ]
            .filter(Boolean)
            .join(' · ')}
        </footer>
      )}
    </section>
  )
}
