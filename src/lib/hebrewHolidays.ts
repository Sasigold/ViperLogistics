/**
 * חגים ומועדים ישראליים — חישוב מקומי, בלי רשת ובלי תלות חיצונית.
 *
 * לוח שנה עברי הוא אריתמטיקה סגורה: מולד תשרי מחושב מתוך מספר החודשים
 * שחלפו מאז הבריאה, ארבע דחיות קובעות על איזה יום בשבוע ראש השנה יכול
 * לנחות, ומכאן אורך השנה ואורכי חשוון וכסלו. זה כל האלגוריתם, והוא נכון
 * לאלפי שנים לפנים ולאחור — ולכן אין כאן טבלה שצריך למלא כל ספטמבר מחדש.
 *
 * ‏`Intl` עם `ca-hebrew` היה חוסך את המרת התאריכים, אבל שמות החודשים שהוא
 * מחזיר משתנים בין מנועים ובין גרסאות ICU (‏Adar/Adar I/Adar II), וכלל
 * כמו "תענית אסתר נדחית ליום חמישי" נשען בדיוק על ההבחנה הזאת.
 *
 * הלוח כאן הוא הלוח שנוהג בישראל: יום טוב אחד ולא שני, יום העצמאות עם
 * הדחיות שנקבעו ב-2004, וחול המועד כימי עבודה לכל דבר.
 *
 * המרה: `absolute` הוא מניין הימים הרציף (RD) שבו 1 בינואר שנת 1 הוא יום 1
 * — אותו ציר שהמרות הלוח העברי הקלאסיות עובדות בו, ושממנו קצרה הדרך
 * לתאריך ISO דרך אפוק היוניקס.
 */

export type HolidayKind =
  /** שבתון — חג שאין בו עבודה */
  | 'yomtov'
  /** חול המועד — יום עבודה, לרוב מקוצר */
  | 'chol'
  /** ערב חג */
  | 'erev'
  /** מועד שאינו שבתון — חנוכה, פורים, ל״ג בעומר */
  | 'minor'
  /** צום */
  | 'fast'
  /** יום זיכרון ממלכתי */
  | 'memorial'

export interface Holiday {
  /** yyyy-MM-dd */
  date: string
  name: string
  kind: HolidayKind
}

/* ── לוח שנה עברי ─────────────────────────────────────────────────────── */

/** ‏RD של א׳ בתשרי שנת א׳ — הקבוע שמחבר את שני הלוחות */
const HEBREW_EPOCH = -1373428
/** ‏RD של 1970-01-01, הגשר אל `Date` */
const RD_UNIX_EPOCH = 719163

/** מודולו מתמטי — ‏`%` של JS מחזיר סימן של המחולק */
const mod = (a: number, b: number) => ((a % b) + b) % b

/* מספור החודשים הוא המקראי (ניסן ראשון), כי עליו בנויות נוסחאות ההמרה */
const NISAN = 1
const IYAR = 2
const SIVAN = 3
const TAMMUZ = 4
const AV = 5
const ELUL = 6
const TISHREI = 7
const KISLEV = 9
const TEVET = 10
const SHEVAT = 11
/** אדר א׳ בשנה מעוברת, ואדר היחיד בשנה פשוטה */
const ADAR = 12
/** אדר ב׳ — קיים רק בשנה מעוברת */
const ADAR_II = 13

export function isHebrewLeapYear(year: number): boolean {
  return mod(7 * year + 1, 19) < 7
}

const lastMonthOfYear = (year: number) => (isHebrewLeapYear(year) ? ADAR_II : ADAR)

/** ימים שחלפו עד מולד תשרי של השנה, כולל דחיית "לא אד״ו ראש" */
function elapsedDays(year: number): number {
  const monthsElapsed = Math.floor((235 * year - 234) / 19)
  const partsElapsed = 12084 + 13753 * monthsElapsed
  let day = monthsElapsed * 29 + Math.floor(partsElapsed / 25920)
  if (mod(3 * (day + 1), 7) < 3) day += 1
  return day
}

/** שתי הדחיות שנגזרות מאורך השנה — גטר״ד ובט״ו תקפ״ט */
function newYearDelay(year: number): number {
  const last = elapsedDays(year - 1)
  const present = elapsedDays(year)
  const next = elapsedDays(year + 1)
  if (next - present === 356) return 2
  if (present - last === 382) return 1
  return 0
}

/** אורך השנה בימים: 353/354/355, ומעוברת 383/384/385 */
function yearLength(year: number): number {
  return hebrewToAbsolute(year + 1, TISHREI, 1) - hebrewToAbsolute(year, TISHREI, 1)
}

function monthLength(year: number, month: number): number {
  if (month === NISAN || month === SIVAN || month === AV || month === TISHREI || month === SHEVAT) return 30
  if (month === IYAR || month === TAMMUZ || month === ELUL || month === TEVET || month === ADAR_II) return 29
  if (month === ADAR) return isHebrewLeapYear(year) ? 30 : 29
  // חשוון וכסלו הם המרווח שסופג את הדחיות: שנה שלמה, כסדרה או חסרה
  if (month === 8) return yearLength(year) % 10 === 5 ? 30 : 29
  if (month === KISLEV) return yearLength(year) % 10 === 3 ? 29 : 30
  throw new Error(`חודש עברי לא חוקי: ${month}`)
}

/** תאריך עברי → מניין הימים הרציף */
export function hebrewToAbsolute(year: number, month: number, day: number): number {
  let total = day
  if (month < TISHREI) {
    // ניסן ואילך שייכים לשנה שכבר נפתחה בתשרי — הדרך אליהם עוברת בכל החודשים שביניהם
    for (let m = TISHREI; m <= lastMonthOfYear(year); m++) total += monthLength(year, m)
    for (let m = NISAN; m < month; m++) total += monthLength(year, m)
  } else {
    for (let m = TISHREI; m < month; m++) total += monthLength(year, m)
  }
  return total + elapsedDays(year) + newYearDelay(year) + HEBREW_EPOCH
}

/** 0 = ראשון … 6 = שבת */
const weekday = (abs: number) => mod(abs, 7)

const toISO = (abs: number) => new Date((abs - RD_UNIX_EPOCH) * 86_400_000).toISOString().slice(0, 10)

const fromISO = (iso: string) => Math.round(Date.parse(`${iso}T00:00:00Z`) / 86_400_000) + RD_UNIX_EPOCH

/* ── המועדים עצמם ─────────────────────────────────────────────────────── */

const SATURDAY = 6
const SUNDAY = 0
const MONDAY = 1
const FRIDAY = 5

/** כל המועדים של שנה עברית אחת, ממוינים לפי תאריך */
function holidaysOfHebrewYear(year: number): Holiday[] {
  const out: Holiday[] = []
  const add = (abs: number, name: string, kind: HolidayKind) => out.push({ date: toISO(abs), name, kind })
  const at = (month: number, day: number) => hebrewToAbsolute(year, month, day)

  /* תשרי */
  add(at(TISHREI, 1), 'ראש השנה', 'yomtov')
  add(at(TISHREI, 2), 'ראש השנה ב׳', 'yomtov')
  // צום גדליה נדחה משבת ליום ראשון
  const gedaliah = at(TISHREI, 3)
  add(weekday(gedaliah) === SATURDAY ? gedaliah + 1 : gedaliah, 'צום גדליה', 'fast')
  add(at(TISHREI, 9), 'ערב יום כיפור', 'erev')
  add(at(TISHREI, 10), 'יום כיפור', 'yomtov')
  add(at(TISHREI, 14), 'ערב סוכות', 'erev')
  add(at(TISHREI, 15), 'סוכות', 'yomtov')
  for (let d = 16; d <= 20; d++) add(at(TISHREI, d), 'חול המועד סוכות', 'chol')
  add(at(TISHREI, 21), 'הושענא רבה', 'chol')
  add(at(TISHREI, 22), 'שמחת תורה', 'yomtov')

  /* כסלו–טבת */
  const chanukah = at(KISLEV, 25)
  for (let i = 0; i < 8; i++) add(chanukah + i, 'חנוכה', 'minor')
  add(at(TEVET, 10), 'צום עשרה בטבת', 'fast')

  /* שבט */
  add(at(SHEVAT, 15), 'ט״ו בשבט', 'minor')

  /* אדר — בשנה מעוברת פורים באדר ב׳ */
  const purimMonth = lastMonthOfYear(year)
  const taanit = hebrewToAbsolute(year, purimMonth, 13)
  // תענית אסתר שחלה בשבת מוקדמת ליום חמישי שלפניה
  add(weekday(taanit) === SATURDAY ? taanit - 2 : taanit, 'תענית אסתר', 'fast')
  add(hebrewToAbsolute(year, purimMonth, 14), 'פורים', 'minor')
  add(hebrewToAbsolute(year, purimMonth, 15), 'שושן פורים', 'minor')

  /* ניסן */
  add(at(NISAN, 14), 'ערב פסח', 'erev')
  add(at(NISAN, 15), 'פסח', 'yomtov')
  for (let d = 16; d <= 20; d++) add(at(NISAN, d), 'חול המועד פסח', 'chol')
  add(at(NISAN, 21), 'שביעי של פסח', 'yomtov')

  // יום השואה לא ייערך בסמוך לשבת: חל בשישי — מוקדם, חל בראשון — נדחה
  const shoah = at(NISAN, 27)
  const shoahDay = weekday(shoah)
  add(shoahDay === FRIDAY ? shoah - 1 : shoahDay === SUNDAY ? shoah + 1 : shoah, 'יום השואה', 'memorial')

  /* אייר */
  // יום העצמאות: חל בשישי או בשבת — מוקדם ליום חמישי, חל בשני — נדחה לשלישי
  const atzmaut = at(IYAR, 5)
  const atzmautDay = weekday(atzmaut)
  const independence =
    atzmautDay === FRIDAY ? atzmaut - 1 : atzmautDay === SATURDAY ? atzmaut - 2 : atzmautDay === MONDAY ? atzmaut + 1 : atzmaut
  add(independence - 1, 'יום הזיכרון', 'memorial')
  add(independence, 'יום העצמאות', 'yomtov')
  add(at(IYAR, 18), 'ל״ג בעומר', 'minor')
  add(at(IYAR, 28), 'יום ירושלים', 'minor')

  /* סיוון */
  add(at(SIVAN, 5), 'ערב שבועות', 'erev')
  add(at(SIVAN, 6), 'שבועות', 'yomtov')

  /* תמוז–אב — שני הצומות נדחים משבת ליום ראשון */
  const tammuz17 = at(TAMMUZ, 17)
  add(weekday(tammuz17) === SATURDAY ? tammuz17 + 1 : tammuz17, 'צום י״ז בתמוז', 'fast')
  const av9 = at(AV, 9)
  add(weekday(av9) === SATURDAY ? av9 + 1 : av9, 'תשעה באב', 'fast')
  add(at(AV, 15), 'ט״ו באב', 'minor')

  /* אלול — ערב ראש השנה של השנה הבאה */
  add(at(ELUL, 29), 'ערב ראש השנה', 'erev')

  return out.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0))
}

/** שנה עברית מחושבת פעם אחת ונשמרת — לוח חודשי מבקש את אותה שנה בכל render */
const cache = new Map<number, Holiday[]>()

function cachedYear(year: number): Holiday[] {
  let hit = cache.get(year)
  if (!hit) {
    hit = holidaysOfHebrewYear(year)
    cache.set(year, hit)
  }
  return hit
}

/**
 * כל המועדים בטווח תאריכים לועזי, לפי יום.
 *
 * ‏`from` ו-`to` הם yyyy-MM-dd וכלולים שניהם. ביום אחד יש מועד אחד לכל
 * היותר, ואם שניים נפגשו — הראשון שנקבע הוא הקובע.
 */
export function holidaysInRange(from: string, to: string): Map<string, Holiday> {
  const out = new Map<string, Holiday>()
  if (!from || !to || from > to) return out
  // השנה העברית שנפתחת בשנה לועזית מסוימת היא היא + 3761; הטווח נלקח ברוחב
  // שנה לכל צד, כי כל שנה עברית פרושה על שתי שנים לועזיות
  const firstYear = Number(from.slice(0, 4)) + 3760
  const lastYear = Number(to.slice(0, 4)) + 3761
  for (let y = firstYear; y <= lastYear; y++) {
    for (const h of cachedYear(y)) {
      if (h.date < from || h.date > to) continue
      if (!out.has(h.date)) out.set(h.date, h)
    }
  }
  return out
}

/** המועד שחל בתאריך לועזי יחיד, אם יש */
export function holidayOn(iso: string): Holiday | undefined {
  return holidaysInRange(iso, iso).get(iso)
}

/** מה שיום כזה עושה ליום עבודה — לכותרות ולתיאורי נגישות */
export const KIND_LABEL: Record<HolidayKind, string> = {
  yomtov: 'חג — שבתון',
  chol: 'חול המועד',
  erev: 'ערב חג',
  minor: 'מועד',
  fast: 'צום',
  memorial: 'יום זיכרון',
}

/** האם היום כולו מושבת — לוח שנה ולו״ז עבודה מסמנים אותו חזק יותר */
export const isDayOff = (h: Holiday | undefined) => h?.kind === 'yomtov'

/** תאריך עברי → ISO, לשימוש חיצוני (וגם מה שהבדיקות אוחזות בו) */
export function hebrewToISO(year: number, month: number, day: number): string {
  return toISO(hebrewToAbsolute(year, month, day))
}

/** ISO → מספר הימים הרציף, לחישובי מרחק בין תאריכים */
export function isoToAbsolute(iso: string): number {
  return fromISO(iso)
}
