import { beforeEach, describe, expect, it } from 'vitest'
import { useAuth } from './auth'
import type { MyPermissions, TaskPerformance } from '../types/domain'

/**
 * ‏0179: הגבול שבין "הלוח של המשרד" ל"הלוח של מי שמבצע".
 *
 * השאלה נענית בשרת (`app.task_performed_by_caller`) ובמסך, וזו הבדיקה של
 * הצד השני — כדי שתא לא ייראה פתוח כשהשרת ידחה אותו, ולא יינעל כשהוא לא.
 */
const ARKO = '10000000-0000-0000-0000-0000000000aa'
const OTHER = '10000000-0000-0000-0000-0000000000bb'

function login(over: {
  kind?: 'staff' | 'customer_user'
  customerId?: string | null
  selfPerforming?: boolean
  board?: { field_key: string; state: 'hidden' | 'visible' | 'editable' }[]
}) {
  const me = {
    profile: {
      id: 'p1',
      full_name: 'בדיקה',
      user_kind: over.kind ?? 'customer_user',
      is_admin: false,
      customer_id: over.customerId === undefined ? ARKO : over.customerId,
      contractor_id: null,
      customer_worker_id: null,
      phone: null,
      email: null,
    },
    roles: [],
    app_roles: [],
    customer:
      over.customerId === null
        ? null
        : {
            id: ARKO,
            name: 'ארקו',
            color: '#000',
            can_create_events: true,
            performed_by_enabled: over.selfPerforming ?? true,
          },
    permissions: {},
    capabilities: {},
    creatable_user_kinds: [],
    field_permissions: [],
    scopes: [],
    form_config: [],
    board_config: over.board ?? [
      { field_key: 'hours_count', state: 'visible' },
      { field_key: 'truck', state: 'editable' },
      { field_key: 'notes', state: 'hidden' },
    ],
  } as unknown as MyPermissions
  useAuth.setState({ me })
}

const arkoTask: TaskPerformance = { customer_id: ARKO, performed_by: 'arko' }
const viperTask: TaskPerformance = { customer_id: ARKO, performed_by: 'viper' }

beforeEach(() => useAuth.setState({ me: null }))

describe('performsTask', () => {
  it('לקוח שמבצע בעצמו — המשימה שסומנה שהוא מבצע היא שלו', () => {
    login({})
    expect(useAuth.getState().performsTask(arkoTask)).toBe(true)
  })

  it('ואותה משימה כשהיא של וייפר — אינה שלו', () => {
    login({})
    expect(useAuth.getState().performsTask(viperTask)).toBe(false)
  })

  it('לקוח שהדגל שלו כבוי אינו מבצע דבר, גם כשהמשימה מסומנת', () => {
    login({ selfPerforming: false })
    expect(useAuth.getState().performsTask(arkoTask)).toBe(false)
  })

  it('ומשימה של לקוח אחר אינה שלו', () => {
    login({})
    expect(useAuth.getState().performsTask({ customer_id: OTHER, performed_by: 'arko' })).toBe(false)
  })

  it('איש משרד אינו "מבצע" — הלוח שלו נשלט במפתחות ולא בקונפיגורציה', () => {
    login({ kind: 'staff', customerId: null })
    expect(useAuth.getState().performsTask(arkoTask)).toBe(false)
  })

  it('ובלי משימה — התשובה היא לא, ולא קריסה', () => {
    login({})
    expect(useAuth.getState().performsTask(null)).toBe(false)
    expect(useAuth.getState().performsTask()).toBe(false)
  })
})

describe('boardFieldState', () => {
  it('בלי משימה — מה שהמשרד קבע ללקוח, כמו תמיד', () => {
    login({})
    expect(useAuth.getState().boardFieldState('hours_count')).toBe('visible')
    expect(useAuth.getState().boardFieldState('truck')).toBe('editable')
  })

  it('במשימה שהלקוח מבצע — כל שדה נפתח', () => {
    login({})
    expect(useAuth.getState().boardFieldState('hours_count', arkoTask)).toBe('editable')
  })

  it('ובמשימה של וייפר — בדיוק כמו היום', () => {
    login({})
    expect(useAuth.getState().boardFieldState('hours_count', viperTask)).toBe('visible')
    expect(useAuth.getState().boardFieldState('truck', viperTask)).toBe('editable')
  })

  it('"מוסתר" נשאר מוסתר — העמודה היא של הלוח כולו ולא של השורה', () => {
    login({})
    expect(useAuth.getState().boardFieldState('notes', arkoTask)).toBe('hidden')
  })

  it('לאיש צוות הקונפיגורציה ריקה, והתשובה היא editable', () => {
    login({ kind: 'staff', customerId: null, board: [] })
    expect(useAuth.getState().boardFieldState('hours_count')).toBe('editable')
    expect(useAuth.getState().boardFieldState('hours_count', arkoTask)).toBe('editable')
  })
})
