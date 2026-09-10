/**
 * טקסט דו-כיווני ב-PDF — עברית, מספרים ולטינית באותה שורה.
 *
 * המסך אינו זקוק לזה: הדפדפן מריץ את UAX#9 בעצמו, וכל האפליקציה חיה תחת
 * `dir="rtl"` אחד ב-`index.html`. ה-PDF כן, ובדרך לא צפויה.
 *
 * **‏`pdf-lib` כבר הופך עברית — וזו בדיוק הבעיה.** ‏`embedFont` מעביר כל
 * מחרוזת דרך ה-layout של fontkit, שמזהה את הכתב, מכריז RTL, ומהפך את **כל**
 * מערך הגליפים. על "אבגד" זה נכון. על "אב 12345" זה מהפך גם את הספרות,
 * ו-12345 מצויר 54321. אימות: מחרוזת לוגית אחת בכל צורה, וקריאת מיקומי
 * הגליפים מהקובץ שנוצר.
 *
 * ולכן שורה אינה מצוירת כמחרוזת אחת אלא כ**רצפים**: ‏`bidi-js` מריץ את
 * UAX#9 המלא (רמות הטמעה, סדר ויזואלי, היפוך סוגריים), התוצאה נחתכת לרצפים
 * לפי כיוון, וכל רצף מצויר בנפרד במיקומו. רצף עברי נמסר ל-pdf-lib בסדר
 * **לוגי** — ההיפוך של fontkit הוא שמעמיד אותו במקום — ורצף שאין בו אות
 * ימנית נמסר כפי שהוא, כי fontkit לא יגע בו.
 *
 * הכיוון הבסיסי הוא תמיד `rtl`: המסמך עברי, וגם שורה שכולה אנגלית יושבת
 * בתוך פסקה עברית.
 */

/** תו שיגרום ל-fontkit להכריז RTL ולהפוך את הרצף: עברי או ערבי. */
const RTL_CHAR = /[֐-ࣿיִ-﷿ﹰ-﻿]/

export interface VisualRun {
  /** הטקסט כפי שהוא נמסר ל-pdf-lib — כבר בהיפוך שההיפוך שלו יבטל */
  text: string
  /** האם הרצף ימני-לשמאלי. המסמך אינו צריך את זה; הבדיקות כן */
  rtl: boolean
}

type BidiLevels = { levels: Uint8Array }
type Bidi = {
  getEmbeddingLevels: (text: string, direction?: 'ltr' | 'rtl') => BidiLevels
  getReorderedIndices: (text: string, levels: BidiLevels) => number[]
  getMirroredCharacter: (char: string) => string | null
}

let bidi: Bidi | null = null

/** נטען פעם אחת, יחד עם שאר מחולל ה-PDF. עד אז אין סיבה לשלם על הספרייה. */
export async function loadBidi(): Promise<void> {
  if (bidi) return
  const factory = (await import('bidi-js')).default
  bidi = factory() as unknown as Bidi
}

/**
 * השורה כרצפים, משמאל לימין, מוכנים לציור.
 *
 * דורשת `loadBidi()` לפניה. בלעדיה היא מחזירה רצף אחד עם הקלט כמות שהוא —
 * טקסט שנראה הפוך גרוע מקריסה, אבל קריסה באמצע הפקת מסמך גרועה משניהם.
 */
export function visualRuns(text: string): VisualRun[] {
  if (!text) return []
  if (!bidi) return [{ text, rtl: RTL_CHAR.test(text) }]

  const levels = bidi.getEmbeddingLevels(text, 'rtl')
  const order = bidi.getReorderedIndices(text, levels)

  const groups: { rtl: boolean; chars: string[] }[] = []
  for (const logical of order) {
    const rtl = (levels.levels[logical] & 1) === 1
    // סוגר שנפתח בהקשר ימני נקרא כסוגר שנסגר, ולהפך. בלי זה "(גרסה 2)"
    // מודפס עם הסוגריים כלפי חוץ.
    const ch = (rtl ? bidi.getMirroredCharacter(text[logical]) : null) ?? text[logical]
    const last = groups[groups.length - 1]
    if (last && last.rtl === rtl) last.chars.push(ch)
    else groups.push({ rtl, chars: [ch] })
  }

  return groups.map((g) => {
    const visual = g.chars.join('')
    // ההיפוך נעשה **רק** כשידוע ש-fontkit יהפוך בחזרה. רצף ברמה ימנית
    // שכולו רווחים וסימני פיסוק אינו נושא כתב עברי, ו-fontkit יעביר אותו
    // כמות שהוא — היפוך שלו כאן היה נשאר הפוך על הנייר.
    const willBeReversed = RTL_CHAR.test(visual)
    return {
      rtl: g.rtl,
      text: willBeReversed ? [...visual].reverse().join('') : visual,
    }
  })
}
