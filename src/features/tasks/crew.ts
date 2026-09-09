/**
 * מי עומד על המשימה, כאדם אחד לכל אדם.
 *
 * שלוש טבלאות שונות מרכיבות צוות אחד בשטח — ‏`task_assignments` של הצוות
 * הפנימי, ‏`task_contractor_workers` של הקבלן ו-`task_customer_workers` של
 * הלקוח שמבצע בעצמו — ולכל אחת מהן התפקידים שלה. מה שמסך צריך אינו שלוש
 * הרשימות אלא **האנשים**: מי עובד כאן, מה הוא, ומאיפה הוא מתחיל.
 *
 * שני כללים מחזיקים את כל מה שכאן:
 *
 * 1. **אדם אחד, שורה אחת.** ראש צוות שגם נוהג מחזיק שתי שורות שיבוץ (0155),
 *    ועובד ששובץ גם כנהג — שתיים אחרות. שתיהן הן אותו אדם, והוא נספר,
 *    מוצג ומסומן פעם אחת.
 * 2. **ראש הצוות אינו חוזר בצוות.** יש לו תא משלו בלו״ז, ומאז 0128 גם ראש
 *    הצוות של הקבלן יושב בו. אדם אחד, מקום אחד — ומה שהיה מסגיר אותו שם
 *    (שהוא נוהג, שהוא יוצא מהמחסן) נאמר עליו שם, ולא בשורה שנייה.
 *
 * הקובץ טהור בכוונה: זו החלוקה שהלו״ז, הכרטיס בנייד וכל מסך אחר צריכים
 * לראות אותה דבר, והיא נבדקת בלי DOM.
 */
import type { StaffRole, WorkBoardRow, WorkSite } from '../../types/domain'

/** מאיזה מאגר הגיע האדם — זה מה שהסימון שלצד השם אומר. */
export type CrewSource = 'staff' | 'contractor' | 'customer'

export interface CrewPerson {
  /** מפתח תצוגה. המאגר בפנים: אותו מזהה יכול לחזור בשני מרחבי זהות. */
  key: string
  name: string
  source: CrewSource
  /** נוהג במשימה הזו — לבדו כנהג, או כראש צוות שסומן (0162). */
  drives: boolean
  /** המשאית שלו, כשידועה. */
  truck: string | null
  site: WorkSite
}

export interface CrewLead extends CrewPerson {
  role: 'team_lead'
}

const site = (v: 'field' | 'warehouse' | null | undefined): WorkSite => (v === 'warehouse' ? 'warehouse' : 'field')

/**
 * ראש הצוות של המשימה — פנימי, של הקבלן או של הלקוח (0128/0134).
 *
 * ‏`team_lead_*` הן עמודות ה-view מ-0162, והן מקור האמת. הנפילה חזרה
 * לרשימות אינה קישוט: החזית עולה לאוויר בלי קשר למיגרציה, ובחלון שביניהן
 * השורה מגיעה בלי העמודות החדשות — והרשימות עצמן כבר נושאות את אותה עדות.
 */
export function crewLead(row: WorkBoardRow): CrewLead | null {
  if (!row.team_lead_name) return null
  const source: CrewSource = row.team_lead_kind ?? 'staff'
  /* השורה שלו במאגר שממנו הוא בא, כשהיא בהישג יד: לצוות הפנימי זו שורת
     הנהיגה השנייה (0155), ולשני האחרים שורת השיבוץ עצמה. */
  const driving = source === 'staff' ? (row.drivers ?? []).find((d) => d.profile_id === row.team_lead_id) : undefined
  const ofContractor =
    source === 'contractor' ? (row.contractor_worker_list ?? []).find((w) => w.role === 'team_lead') : undefined
  const ofCustomer =
    source === 'customer' ? (row.customer_worker_list ?? []).find((w) => w.role === 'team_lead') : undefined
  return {
    key: `lead:${row.team_lead_id ?? ofContractor?.id ?? ofCustomer?.id ?? row.team_lead_name}`,
    name: row.team_lead_name,
    source,
    role: 'team_lead',
    drives: row.team_lead_drives ?? (!!driving || !!ofContractor?.drives),
    truck: row.team_lead_truck_name ?? driving?.truck_name ?? ofCustomer?.truck_name ?? null,
    site: site(row.team_lead_work_site ?? driving?.work_site ?? ofContractor?.work_site ?? ofCustomer?.work_site),
  }
}

/**
 * הצוות של המשימה בלי ראש הצוות — אדם אחד לשורה, עם מה שמסגיר אותו.
 *
 * האיחוד הוא לפי מזהה בתוך המאגר: עובד קבלן ואיש צוות יכולים לשאת אותו
 * מזהה בלי שיהיו אותו אדם.
 */
export function crewPeople(row: WorkBoardRow): CrewPerson[] {
  const staff = new Map<string, CrewPerson>()
  const leadProfile = row.team_lead_kind === 'staff' ? row.team_lead_id : null
  const add = (id: string, name: string, at: WorkSite) => {
    const found = staff.get(id)
    if (found) return found
    const person: CrewPerson = { key: `s:${id}`, name, source: 'staff', drives: false, truck: null, site: at }
    staff.set(id, person)
    return person
  }
  for (const w of row.workers ?? []) {
    if (w.profile_id === leadProfile) continue
    add(w.profile_id, w.name, site(w.work_site))
  }
  for (const d of row.drivers ?? []) {
    /* ראש הצוות שנוהג מחזיק שורת נהג משלו, והיא שלו — לא של הצוות (0162). */
    if (d.profile_id === leadProfile) continue
    const person = add(d.profile_id, d.name, site(d.work_site))
    person.drives = true
    if (d.truck_name) person.truck = d.truck_name
  }

  const drives = (role: StaffRole | null | undefined) => role === 'driver'
  return [
    ...staff.values(),
    /* ראש צוות של קבלן יושב מ-0128 בשורה של ראש הצוות, ולכן אינו חוזר כאן.
       שאר הסגל — נהג הקבלן ועובדיו — נשאר. */
    ...(row.contractor_worker_list ?? [])
      .filter((w) => w.role !== 'team_lead')
      .map<CrewPerson>((w) => ({
        key: `c:${w.id}`,
        name: w.name,
        source: 'contractor',
        drives: drives(w.role),
        truck: null,
        site: site(w.work_site),
      })),
    ...(row.customer_worker_list ?? [])
      .filter((w) => w.role !== 'team_lead')
      .map<CrewPerson>((w) => ({
        key: `o:${w.id}`,
        name: w.name,
        source: 'customer',
        drives: drives(w.role),
        truck: w.truck_name ?? null,
        site: site(w.work_site),
      })),
  ]
}

/** כמה **אנשים** עומדים על המשימה — ראש הצוות בכללם, ופעם אחת. */
export function crewSize(row: WorkBoardRow): number {
  return crewPeople(row).length + (crewLead(row) ? 1 : 0)
}
