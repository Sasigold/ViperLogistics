import type { Status } from '../../types/domain'

/**
 * אילו סטטוסים להציע למשימה, ומתי לא להציע כלום (0117).
 *
 * פרסום ("משובץ") הוא מפתח נפרד מ-`tasks.change_status`, ומאז 0117 הוא שומר
 * על **שני** קצותיו: מי שאינו רשאי לפרסם אינו מעלה משימה ל"משובץ" ואינו
 * מוריד אותה משם. השרת אוכף את שניהם ב-`app.enforce_task_publish`, וזה כאן
 * רק כדי שהמסך לא יצייר מה שיידחה — **תא שנראה פתוח ונדחה בשמירה גרוע מתא
 * שנראה נעול**, כניסוחה של 0109.
 *
 * הפונקציה טהורה ומשותפת לתא בלו״ז ולכרטיס המשימה, כדי שלא יהיו שני מקומות
 * שאפשר להם לחלוק על אותה שאלה.
 */
export function statusOptions(statuses: Status[], currentId: string | null, canPublish: boolean) {
  const current = currentId ? statuses.find((s) => s.id === currentId) : undefined

  /* משימה שכבר פורסמה נעולה למי שאינו רשאי לפרסם. בלי זה הבורר היה מציג לו
     "טיוטה" ו"מתוכנן" — שתי אפשרויות שכל אחת מהן נדחית ב-42501. */
  const locked = !canPublish && current?.code === 'assigned'

  return {
    locked,
    options: locked
      ? statuses.filter((s) => s.id === currentId)
      : /* הסטטוס הנוכחי נשאר ברשימה תמיד, גם כשהמפתח חסר: אחרת שורה שמישהו
           אחר פרסם הייתה מציגה בורר בלי הערך שבו היא נמצאת */
        statuses.filter((s) => canPublish || s.code !== 'assigned' || s.id === currentId),
  }
}
