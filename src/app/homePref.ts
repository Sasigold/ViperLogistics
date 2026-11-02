import type { NavItem, NavSection } from './nav'

/**
 * דף הנחיתה ודף הפתיחה — העדפה אישית של המשתמש.
 *
 * למה: הדשבורד הוא המסך הכבד באפליקציה (עשרות סקשנים, כל אחד שאילתה), והוא
 * היה נטען בכל כניסה גם כשהמשתמש רצה רק את לוח השנה. כניסה משני מכשירים
 * בבת אחת הכפילה את העומס. עכשיו כל משתמש בוחר לאן הוא נוחת: הדשבורד (כמו
 * קודם), "דף הפתיחה" — כפתורים בלבד, בלי שום שאילתה — או מסך מסוים.
 *
 * ההעדפה נשמרת ב-`user_metadata` של המשתמש ב-Supabase Auth (לא בטבלה, ולכן
 * בלי מיגרציה), כך שהיא עוברת בין מכשירים. זו העדפת תצוגה בלבד: היא אינה
 * פותחת שום דבר — יעד שאינו גלוי למשתמש (הרשאה, הסתרת דף) פשוט נופל לברירת
 * המחדל.
 */
export const START_PATH = '/start'

/** המפתח ב-`user_metadata` */
export const HOME_PREF_KEY = 'home_v1'

export interface HomePref {
  /** 'auto' = כמו קודם (דשבורד / היעד הראשון בתפריט); START_PATH; או נתיב של רשומה בתפריט */
  landing: string
  /** הנתיבים שמוצגים כאריחים בדף הפתיחה; חסר = כל מה שגלוי */
  tiles?: string[]
}

export const DEFAULT_HOME_PREF: HomePref = { landing: 'auto' }

/** קורא את ההעדפה מתוך `user_metadata` — כל צורה לא צפויה היא ברירת המחדל. */
export function parseHomePref(meta: unknown): HomePref {
  const raw = (meta as Record<string, unknown> | null | undefined)?.[HOME_PREF_KEY]
  if (!raw || typeof raw !== 'object') return DEFAULT_HOME_PREF
  const r = raw as Record<string, unknown>
  const landing = typeof r.landing === 'string' && r.landing.startsWith('/') ? r.landing : 'auto'
  const tiles = Array.isArray(r.tiles) ? r.tiles.filter((t): t is string => typeof t === 'string') : undefined
  return tiles ? { landing, tiles } : { landing }
}

/** הרשומות שאפשר לנחות בהן או לשים כאריח: כל הגלויות, פעם אחת לכל נתיב, בלי דף הפתיחה עצמו. */
export function destinations(sections: NavSection[]): { section: NavSection; item: NavItem }[] {
  const seen = new Set<string>()
  const out: { section: NavSection; item: NavItem }[] = []
  for (const section of sections)
    for (const item of section.items) {
      if (item.to === START_PATH || seen.has(item.to)) continue
      seen.add(item.to)
      out.push({ section, item })
    }
  return out
}

/**
 * לאן לנחות. null = אין העדפה שאפשר לכבד, ו-HomeRoute ממשיך כמו קודם.
 * '/' אינו יעד: הוא הבית עצמו, וזה מה ש-null אומר.
 */
export function resolveLanding(pref: HomePref, sections: NavSection[]): string | null {
  if (pref.landing === 'auto' || pref.landing === '/') return null
  const flat = sections.flatMap((s) => s.items)
  return flat.some((i) => i.to === pref.landing) ? pref.landing : null
}

/** האריחים של דף הפתיחה, מקובצים לפי קבוצת התפריט ובסדר שלה. */
export function launcherTiles(pref: HomePref, sections: NavSection[]): { section: NavSection; items: NavItem[] }[] {
  const chosen = pref.tiles ? new Set(pref.tiles) : null
  const groups = new Map<string, { section: NavSection; items: NavItem[] }>()
  for (const { section, item } of destinations(sections)) {
    if (chosen && !chosen.has(item.to)) continue
    const g = groups.get(section.id) ?? { section, items: [] }
    g.items.push(item)
    groups.set(section.id, g)
  }
  return [...groups.values()]
}

/*
 * הנחיתה קורית פעם אחת — בכניסה לאפליקציה. אחרי זה `/` הוא שוב הדשבורד,
 * כדי שהרשומה "דשבורד" בתפריט תמשיך להוביל אליו. AppLayout מסמן "נכנסנו"
 * כשהוא עולה (כניסה ישירה ל-/calendar אינה מפנה אחר כך את `/`), ומאפס כשהוא
 * יורד (התנתקות — הכניסה הבאה נוחתת שוב).
 */
let landed = false
export const landingPending = () => !landed
export const markLanded = () => {
  landed = true
}
export const resetLanding = () => {
  landed = false
}
