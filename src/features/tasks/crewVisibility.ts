/**
 * מה שהקורא רואה על **הצוות של המשימה** — בכל מסך, ולא רק בלו״ז.
 *
 * שדות הלו״ז פר-לקוח (0109) הם הכרעה של מנהל המערכת על מה שלקוח מסוים רואה,
 * והם נשמרים ב-`customer_board_fields`. עד כאן קרא אותם הלו״ז בלבד: `available`
 * שם מסנן את `BOARD_FIELDS` לפי `boardFieldState`, ולכן לקוח שהוגדר לו
 * ‏`team`/`worker_count`/`hours_count` כ-`hidden` באמת לא ראה אותם שם — אבל
 * ראה את שלושתם בדף האירוע, בכרטיסי המשימות שבו ובכרטיס הנייד של הלו״ז, שכולם
 * מציירים את אותם נתונים מ-`work_board_view` בלי לשאול את הקונפיגורציה.
 *
 * ההכרעה יושבת כאן כדי שתיענה אותו דבר בכל מקום. שתי שכבות, והראשונה קודמת:
 *
 * 1. **מפתח.** ‏`board.view_staffing` הוא מה שמכריע אם יש בכלל אנשים לראות —
 *    ה-join של הצוות וראש הצוות ריק בלעדיו, ועמודה שנשענת עליו נעלמת ולא
 *    מוצגת ריקה. ‏`worker_count` ו-`hours_count` הן עמודות של המשימה עצמה
 *    ואינן מפתח, בדיוק כפי שהן ב-`BOARD_FIELDS`.
 * 2. **הקונפיגורציה של הלקוח.** ‏`boardFieldState` מחזירה `editable` לאיש צוות
 *    (‏`board_config` שלו ריקה), ולכן השכבה הזו אינה מסננת דבר אצל המשרד —
 *    היא הצרה *נוספת* על קהל הלקוחות ולא שכבה חדשה שכולם עוברים בה.
 *
 * ארבע שאלות ולא אחת: "כמה עובדים", "מי הם", "מי ראש הצוות" ו"כמה שעות" הן
 * ארבעה מפתחות נפרדים ב-`board_fields`, ולקוח יכול להיסגר על חלקם בלבד.
 */
import { useMemo } from 'react'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'

export interface CrewVisibility {
  /** שמות האנשים שעל המשימה, בלי ראש הצוות — שדה `team`. */
  names: boolean
  /** שם ראש הצוות — שדה `team_lead`. שם של אדם בדיוק כמו השאר. */
  lead: boolean
  /** כמה עובדים המשימה דורשת — שדה `worker_count`. */
  count: boolean
  /** משך המשימה בשעות — שדה `hours_count`. */
  hours: boolean
  /**
   * שעת הסיום בשטח — שדה `onsite_end_time`.
   *
   * נוסע עם המשך ולא לצדו: "מ-08:00 עד 14:00" הוא אותה תשובה בדיוק כמו
   * "‏6:00", ולסגור אחד מהם ולהשאיר את השני היה סגירה למראית עין.
   */
  endTime: boolean
}

export function useCrewVisibility(): CrewVisibility {
  const has = useAuth((s) => s.has)
  const boardFieldState = useAuth((s) => s.boardFieldState)
  const staffing = has(PERM.BOARD_VIEW_STAFFING)
  const shown = (key: string) => boardFieldState(key) !== 'hidden'
  const names = staffing && shown('team')
  const lead = staffing && shown('team_lead')
  const count = shown('worker_count')
  const hours = shown('hours_count')
  const endTime = shown('onsite_end_time')
  /* על הערכים ולא על הפונקציות: `has` ו-`boardFieldState` הן פונקציות יציבות
     של ה-store ולעולם לא יתחלפו, ואילו האובייקט שנבנה כאן נכנס לרשימות
     התלות של `useMemo` במסכים שקוראים לו — אובייקט טרי בכל רינדור היה מבטל
     שם כל memo. */
  return useMemo(
    () => ({ names, lead, count, hours, endTime }),
    [names, lead, count, hours, endTime],
  )
}
