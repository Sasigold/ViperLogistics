/**
 * רשימת הריהוט של האירוע, כפי שהיא בהזמנה ב-ViperFlow (0176).
 *
 * זו לשונית במסך המפרט ולא מסך משלה, וזו ההכרעה המרכזית כאן: לאירוע של שיא
 * עיצובים **המפרט הוא רשימת הריהוט**. עד היום המסמך הגיע כקובץ שמישהו העלה,
 * ומעכשיו הוא מגיע דרך ה-API של המערכת שהפיקה אותו — אותה שאלה, מקור אחר.
 * לכן אותו כפתור, אותו מפתח (`events.specs_view`), ואותו קהל: מי שנוסע
 * לאירוע הוא מי שצריך לדעת מה לטעון (0102).
 *
 * **בלי מחירים.** אין כאן סינון של עמודה — פשוט אין עמודת מחיר: לא בטבלה,
 * לא בטיפוס, ולא במעטפה ששמורה אצלנו (0176 §2).
 */
import { Armchair, ICON, RefreshCw, STROKE } from '../../components/ui/icons'
import { Badge, EmptyState, ErrorState, SkeletonList, cx, fmtRelative } from '../../components/ui'
import { furnitureLines, furnitureSummary, furnitureSummaryText } from './furniture'
import { useViperflowOrderItems } from './furnitureQueries'
import type { ViperflowEventLink } from '../../types/domain'

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
  const { data: items = [], isLoading, error, refetch } = useViperflowOrderItems(eventId, enabled)

  if (isLoading) return <SkeletonList rows={5} />
  if (error) return <ErrorState error={error} onRetry={() => void refetch()} />

  const lines = furnitureLines(items)
  const summary = furnitureSummary(items)

  if (lines.length === 0) {
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
        {link?.order_number && (
          <Badge tone="neutral">
            הזמנה {link.order_number}
          </Badge>
        )}
        <span className="min-w-0 flex-1" />
        {link && (
          <span className="flex items-center gap-1 type-caption text-ink-tertiary">
            <RefreshCw size={ICON.sm} strokeWidth={STROKE} />
            סונכרן {fmtRelative(link.last_synced_at)}
          </span>
        )}
      </header>

      {/* טבלה ולא רשימה: במחסן קוראים "כמה" בעמודה אחת, מלמעלה למטה. */}
      <div className="overflow-x-auto">
        <table className="w-full text-start">
          <thead>
            <tr className="border-b border-line-subtle type-caption text-ink-tertiary">
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
            {lines.map((line, index) => (
              <tr key={line.id} className={cx(index % 2 === 1 && 'bg-subtle/30')}>
                <td className="px-3 py-2 align-top">
                  <span className="font-medium text-ink">{line.name}</span>
                  {line.isCustom && (
                    <>
                      {' '}
                      <Badge tone="neutral">פריט חופשי</Badge>
                    </>
                  )}
                  {line.options.length > 0 && (
                    <div className="type-caption text-ink-secondary">{line.options.join(' · ')}</div>
                  )}
                  {line.components.length > 0 && (
                    <ul className="mt-1 space-y-0.5 border-s-2 border-line-subtle ps-2 type-caption text-ink-secondary">
                      {line.components.map((component) => (
                        <li key={component.id}>
                          <span className="tabular">{component.quantity}×</span> {component.name}
                          {component.options.length > 0 && ` · ${component.options.join(' · ')}`}
                        </li>
                      ))}
                    </ul>
                  )}
                  {line.notes && (
                    <div className="type-caption text-ink-tertiary">{line.notes}</div>
                  )}
                </td>
                <td className="px-3 py-2 align-top tabular font-semibold text-ink">
                  {line.quantity}
                </td>
                <td className="px-3 py-2 align-top tabular text-ink-tertiary">
                  {line.spareQuantity > 0 ? `+${line.spareQuantity}` : '—'}
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
