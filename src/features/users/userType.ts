/**
 * ‏"סוג משתמש" כפי שמסך העובדים שואל עליו — ארבע אפשרויות, לא שלוש.
 *
 * במסד יש שלושה סוגים (`user_kind`) ודגל נפרד, `profiles.is_admin`, ומנהל
 * מערכת הוא שילוב שלהם: שורת `staff` עם הדגל דלוק. זה נכון ונשאר נכון —
 * ‏`user_kind` מכריע עשרות פוליסות RLS, את `permission_roles.user_kind` ואת
 * ‏`kind_permission_defaults`, וערך אנום רביעי היה נוגע בכולן כדי לתאר מישהו
 * שממילא עוקף את כולן.
 *
 * מה שכן היה שגוי הוא *השאלה* שהטופס שאל. כדי לפתוח מנהל מערכת היה צריך
 * לרשום אותו כ"צוות", והטופס ממלא שם תפקיד `worker` כברירת מחדל — כך שהמנהל
 * נכנס לרוסטר לוח המשמרות, לרשימות השיבוץ ולכל מקום שסופר עובדים. הפרדה
 * במסך אחד פותרת את זה: מי שנפתח כ"מנהל מערכת" הוא פרופיל צוות **בלי תפקיד
 * צוות**, ולכן אינו עובד בשום מסך שסופר עובדים.
 *
 * הצירוף השני נשאר אפשרי ומפורש: "צוות" + המתג "מנהל מערכת" הוא מי שגם
 * מנהל וגם עובד — ורק הוא מקבל שעון נוכחות ומשמרות (ראו `forEmployees`
 * ב-nav.ts).
 *
 * ‏`app.notification_audience` (0046) כבר עושה בדיוק את ההבחנה הזאת בשרת:
 * "אדמין גובר על סוג המשתמש". זו אותה הבחנה, במסך.
 */
import type { StaffRole, UserKind } from '../../types/domain'

export type UserType = 'admin' | UserKind

/** הסדר כאן הוא סדר הצ׳יפים במסנן וסדר האפשרויות בבורר. */
export const USER_TYPE_LABELS: Record<UserType, string> = {
  staff: 'צוות',
  admin: 'מנהל מערכת',
  customer_user: 'לקוח',
  contractor_user: 'קבלן',
}

/** מה שכתוב באפשרות עצמה בבורר, שם התווית לבדה אינה מספיקה. */
export const USER_TYPE_OPTION_LABELS: Record<UserType, string> = {
  staff: 'צוות (עובד / נהג / ראש צוות)',
  admin: 'מנהל מערכת (גישה מלאה, בלי שיבוץ)',
  customer_user: 'משתמש לקוח',
  contractor_user: 'משתמש קבלן',
}

/** מה ש-`user_kind` יהיה במסד. מנהל מערכת הוא שורת צוות, כמו תמיד. */
export const kindOfType = (t: UserType): UserKind => (t === 'admin' ? 'staff' : t)

/**
 * הסוג של פרופיל קיים.
 *
 * ‏"מנהל מערכת" הוא מי שהדגל דלוק אצלו **ואין לו תפקיד צוות**: מנהל שהוא גם
 * עובד נשאר "צוות" עם מתג דלוק, כי זה מה שהוא — והמסכים האישיים שלו תלויים
 * בדיוק בתפקיד הזה.
 */
export function userTypeOf(p: {
  user_kind: UserKind
  is_admin: boolean
  staff_roles?: { role: StaffRole }[] | null
}): UserType {
  if (p.is_admin && p.user_kind === 'staff' && (p.staff_roles ?? []).length === 0) return 'admin'
  return p.user_kind
}
