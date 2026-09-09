import { describe, expect, it } from 'vitest'
import { crewLead, crewPeople, crewSize } from './crew'
import type { WorkBoardRow } from '../../types/domain'

/* מה שנבדק כאן הוא הכלל שכל מסך שמציג שיבוץ נשען עליו: אדם אחד מופיע פעם
   אחת, וראש הצוות מופיע בתא שלו ולא גם ברשימת הצוות. המקרה שבגללו הוא נכתב
   הוא ראש הצוות שנוהג — שתי שורות שיבוץ לאותו אדם (0155), ושני שמות זהים
   בשתי שורות של הלו״ז. */

const row = (r: Partial<WorkBoardRow>): WorkBoardRow =>
  ({
    team_lead_id: null,
    team_lead_name: null,
    team_lead_kind: null,
    team_lead_work_site: null,
    team_lead_drives: null,
    team_lead_truck_name: null,
    workers: null,
    drivers: null,
    contractor_worker_list: null,
    customer_worker_list: null,
    ...r,
  }) as WorkBoardRow

const lead = {
  team_lead_id: 'p1',
  team_lead_name: 'דנה',
  team_lead_kind: 'staff' as const,
}

describe('crewPeople', () => {
  it('עובד שהוא גם נהג הוא אדם אחד, עם המשאית שלו', () => {
    const people = crewPeople(
      row({
        workers: [{ profile_id: 'p2', name: 'רון', work_site: 'field' }],
        drivers: [{ profile_id: 'p2', name: 'רון', work_site: 'field', truck_name: 'משאית 1' }],
      }),
    )
    expect(people).toHaveLength(1)
    expect(people[0]).toMatchObject({ name: 'רון', drives: true, truck: 'משאית 1' })
  })

  it('ראש הצוות שנוהג אינו חוזר ברשימת הצוות', () => {
    const people = crewPeople(
      row({
        ...lead,
        drivers: [{ profile_id: 'p1', name: 'דנה', work_site: 'warehouse', truck_name: 'משאית 1' }],
        workers: [{ profile_id: 'p2', name: 'רון', work_site: 'field' }],
      }),
    )
    expect(people.map((p) => p.name)).toEqual(['רון'])
  })

  it('וגם ראש צוות ששובץ במקביל כעובד אינו חוזר', () => {
    const people = crewPeople(
      row({ ...lead, workers: [{ profile_id: 'p1', name: 'דנה', work_site: 'field' }] }),
    )
    expect(people).toHaveLength(0)
  })

  it('ראש הצוות של הקבלן יושב בתא שלו, ושאר הסגל נשאר', () => {
    const people = crewPeople(
      row({
        team_lead_name: 'אבי',
        team_lead_kind: 'contractor',
        contractor_worker_list: [
          { id: 'c1', name: 'אבי', contractor_id: 'k', role: 'team_lead', work_site: 'warehouse' },
          { id: 'c2', name: 'יוסי', contractor_id: 'k', role: 'driver', work_site: 'field' },
          { id: 'c3', name: 'משה', contractor_id: 'k', role: null, work_site: 'field' },
        ],
      }),
    )
    expect(people.map((p) => p.name)).toEqual(['יוסי', 'משה'])
    expect(people[0]).toMatchObject({ source: 'contractor', drives: true })
  })

  it('סגל הלקוח נקרא באותם כללים', () => {
    const people = crewPeople(
      row({
        team_lead_name: 'שירה',
        team_lead_kind: 'customer',
        customer_worker_list: [
          { id: 'o1', name: 'שירה', role: 'team_lead', work_site: 'field' },
          { id: 'o2', name: 'תום', role: 'driver', work_site: 'warehouse', truck_name: 'משאית 2' },
        ],
      }),
    )
    expect(people).toHaveLength(1)
    expect(people[0]).toMatchObject({ name: 'תום', source: 'customer', drives: true, truck: 'משאית 2', site: 'warehouse' })
  })
})

describe('crewLead', () => {
  it('בלי ראש צוות אין מה לומר', () => {
    expect(crewLead(row({}))).toBeNull()
  })

  it('העמודות של השורה הן מקור האמת', () => {
    expect(
      crewLead(
        row({
          ...lead,
          team_lead_work_site: 'warehouse',
          team_lead_drives: true,
          team_lead_truck_name: 'משאית 1',
        }),
      ),
    ).toMatchObject({ name: 'דנה', source: 'staff', drives: true, truck: 'משאית 1', site: 'warehouse' })
  })

  it('ובלעדיהן — שורת הנהיגה שלו עונה את אותה תשובה', () => {
    expect(
      crewLead(
        row({
          ...lead,
          drivers: [{ profile_id: 'p1', name: 'דנה', work_site: 'warehouse', truck_name: 'משאית 1' }],
        }),
      ),
    ).toMatchObject({ drives: true, truck: 'משאית 1', site: 'warehouse' })
  })

  it('ראש צוות של קבלן שסומן "גם נהג"', () => {
    expect(
      crewLead(
        row({
          team_lead_name: 'אבי',
          team_lead_kind: 'contractor',
          contractor_worker_list: [
            { id: 'c1', name: 'אבי', contractor_id: 'k', role: 'team_lead', work_site: 'warehouse', drives: true },
          ],
        }),
      ),
    ).toMatchObject({ source: 'contractor', drives: true, site: 'warehouse' })
  })

  it('ראש צוות שאינו נוהג מתחיל בשטח כברירת מחדל', () => {
    expect(crewLead(row(lead))).toMatchObject({ drives: false, truck: null, site: 'field' })
  })
})

describe('crewSize', () => {
  it('סופר אנשים ולא שורות שיבוץ', () => {
    expect(
      crewSize(
        row({
          ...lead,
          drivers: [
            { profile_id: 'p1', name: 'דנה', work_site: 'field' },
            { profile_id: 'p2', name: 'רון', work_site: 'field' },
          ],
          workers: [{ profile_id: 'p2', name: 'רון', work_site: 'field' }],
          contractor_worker_list: [
            { id: 'c1', name: 'אבי', contractor_id: 'k', role: null, work_site: 'field' },
          ],
        }),
      ),
    ).toBe(3)
  })
})
