import { useEffect, useRef } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import type { QueryClient } from '@tanstack/react-query'
import type { RealtimeChannel } from '@supabase/supabase-js'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import type { MyPermissions } from '../../types/domain'

/**
 * סנכרון און-ליין (0101): שינוי שמשתמש אחר עשה במשימה או באירוע מגיע לכאן
 * כאות — ישות, סוג ומזהים, בלי נתונים — והתגובה היא רענון השאילתות הפעילות.
 *
 * שני דברים שהמנגנון הזה במפגיע אינו עושה:
 *   * אינו ממזג את האות לתוך המטמון — שורת הלו״ז נבנית מ-work_board_view
 *     (שמות, צבעים, משובצים, שדות מגודרי-הרשאה), והאות אינו נושא דבר מזה.
 *     הרענון עובר דרך ה-RLS המלא, ולכן גם אות שהגיע למי שרואה חלק — בטוח.
 *   * אינו מרענן את מה שלא נטען: invalidateQueries מריץ מחדש רק שאילתות
 *     פעילות; השאר רק מסומן ישן ויישלף כשיוצג. מי שלא פתח מסך — לא מושך.
 *
 * הקהל נקבע בשרת (הטריגר שולח רק לערוצים הרלוונטיים, והפוליסה על
 * realtime.messages מסרבת להצטרפות זרה); הרשימה כאן רק בוחרת למה *לנסות*
 * להצטרף, בבואה של אותו היגיון.
 */

interface SyncSignal {
  v: number
  entity: 'task' | 'event'
  kind: 'insert' | 'update' | 'delete' | 'assignment'
  ids: string[]
  event_ids?: string[]
  actor: string | null
}

/** הערוצים שמשתמש נתון רשאי להם — הבבואה של פוליסת sync_topics_read. */
export function syncTopics(me: MyPermissions): string[] {
  const topics = new Set<string>([`sync:profile:${me.profile.id}`])
  const { user_kind, is_admin, customer_id, contractor_id } = me.profile

  if (user_kind === 'customer_user' && customer_id) topics.add(`sync:customer:${customer_id}`)
  if (user_kind === 'contractor_user' && contractor_id) topics.add(`sync:contractor:${contractor_id}`)

  if (is_admin) {
    topics.add('sync:staff')
  } else if (user_kind === 'staff') {
    const taskScopes = me.scopes.filter((s) => s.resource === 'tasks')
    const own = taskScopes.some((s) => s.scope_type === 'own')
    const customers = taskScopes.filter((s) => s.scope_type === 'customers').flatMap((s) => s.values)
    const contractors = taskScopes.filter((s) => s.scope_type === 'contractors').flatMap((s) => s.values)
    // מי שרואה רק את שיבוציו נשאר בערוץ האישי; היקף נקוב מאזין ללקוחות/קבלנים
    // שלו; ומי שאינו מוגבל כלל — הסדרן — שומע הכול בערוץ אחד.
    if (!own) {
      if (!customers.length && !contractors.length) topics.add('sync:staff')
      customers.forEach((id) => topics.add(`sync:customer:${id}`))
      contractors.forEach((id) => topics.add(`sync:contractor:${id}`))
    }
  }
  return [...topics]
}

/** אות משימה נוגע גם בנגזרות: לו״ז, דשבורד, משמרות, ופורטל הקבלן. */
const TASK_KEYS = [['workboard'], ['dashboard'], ['attendance'], ['portal']]
const EVENT_KEYS = [['events'], ['calendar'], ['workboard'], ['dashboard']]
/** אחרי נתק אין לדעת מה הוחמץ — הכול נחשב ישן. */
const RESYNC_KEYS = [['workboard'], ['events'], ['calendar'], ['tasks'], ['dashboard'], ['attendance'], ['portal']]

interface Pending {
  taskIds: Set<string>
  taskEventIds: Set<string>
  eventIds: Set<string>
  tasks: boolean
  events: boolean
  resync: boolean
}

const emptyPending = (): Pending => ({
  taskIds: new Set(),
  taskEventIds: new Set(),
  eventIds: new Set(),
  tasks: false,
  events: false,
  resync: false,
})

function flush(qc: QueryClient, p: Pending) {
  const keys = new Map<string, readonly unknown[]>()
  const add = (k: readonly unknown[]) => keys.set(JSON.stringify(k), k)

  if (p.resync) RESYNC_KEYS.forEach(add)
  if (p.tasks) {
    TASK_KEYS.forEach(add)
    p.taskIds.forEach((id) => add(['tasks', 'one', id]))
    p.taskEventIds.forEach((ev) => add(['tasks', 'autoByEvent', ev]))
    // הלו״ז של אירוע פתוח ניזון מ-['workboard','byEvent'] — מכוסה ב-['workboard']
  }
  if (p.events) {
    EVENT_KEYS.forEach(add)
    p.eventIds.forEach((id) => add(['events', 'one', id]))
  }
  keys.forEach((queryKey) => void qc.invalidateQueries({ queryKey }))
}

export function useRealtimeSync() {
  const me = useAuth((s) => s.me)
  const qc = useQueryClient()

  const pendingRef = useRef<Pending>(emptyPending())
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const firstQueuedAtRef = useRef<number | null>(null)

  useEffect(() => {
    if (!me) return
    const myProfileId = me.profile.id
    const channels: RealtimeChannel[] = []
    // ההצטרפות הראשונה אינה "התאוששות": רק חיבור שנשבר ונרפא גורר רענון מלא.
    const wasBroken = new Map<string, boolean>()
    let disposed = false

    const schedule = () => {
      // ‏trailing שנייה, עם תקרה של 3 שניות: יצירת אירוע מולידה אות אירוע ועוד
      // אותות משימה בזה אחר זה, וכולם מתקפלים לרענון אחד — אבל זרם רציף של
      // שינויים אינו דוחה את הרענון לנצח.
      const now = Date.now()
      firstQueuedAtRef.current ??= now
      if (timerRef.current) {
        if (now - firstQueuedAtRef.current > 3000) return
        clearTimeout(timerRef.current)
      }
      timerRef.current = setTimeout(() => {
        timerRef.current = null
        firstQueuedAtRef.current = null
        const p = pendingRef.current
        pendingRef.current = emptyPending()
        flush(qc, p)
      }, 1000)
    }

    const onSignal = (signal: SyncSignal) => {
      // שינוי שאני יצרתי כבר ריענן את עצמו בנתיב המוטציה; רענון שני רק היה
      // מטלטל את הלוח באמצע עריכה.
      if (signal.actor && signal.actor === myProfileId) return
      const p = pendingRef.current
      if (signal.entity === 'task') {
        p.tasks = true
        signal.ids?.forEach((id) => p.taskIds.add(id))
        signal.event_ids?.forEach((ev) => p.taskEventIds.add(ev))
      } else if (signal.entity === 'event') {
        p.events = true
        signal.ids?.forEach((id) => p.eventIds.add(id))
      }
      schedule()
    }

    const subscribe = async () => {
      // ערוץ פרטי דורש שה-socket יכיר את ה-JWT לפני ההצטרפות.
      await supabase.realtime.setAuth()
      if (disposed) return
      for (const topic of syncTopics(me)) {
        const channel = supabase
          .channel(topic, { config: { private: true } })
          .on('broadcast', { event: 'sync' }, (msg) => onSignal(msg.payload as SyncSignal))
          .subscribe((status) => {
            if (status === 'SUBSCRIBED' && wasBroken.get(topic)) {
              wasBroken.set(topic, false)
              pendingRef.current.resync = true
              schedule()
            } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
              if (!disposed) wasBroken.set(topic, true)
            }
          })
        channels.push(channel)
      }
    }
    void subscribe()

    return () => {
      disposed = true
      if (timerRef.current) clearTimeout(timerRef.current)
      timerRef.current = null
      firstQueuedAtRef.current = null
      pendingRef.current = emptyPending()
      channels.forEach((c) => void supabase.removeChannel(c))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [me?.profile.id])
}
