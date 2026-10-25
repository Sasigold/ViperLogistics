// הכלים של עוזר הוואטסאפ (0236): כל כלי רץ בשם המשתמש (`asUser`), דרך אותם
// מסלולים שהמסכים משתמשים בהם — ולכן RLS, ההרשאות והטריגרים קובעים.
//
// כלי שאלה עונה מיד. כלי שינוי אינו משנה: הוא קורא את המצב הנוכחי, בונה את
// שורות התצוגה, ומריץ ניסיון של כל השינויים שהוכנו עד כה ושל החדש בטרנזקציה
// שמתבטלת — כך שהרשאה חסרה או אילוץ מופר נאמרים לפני "כן", ולא אחריו.
// אחרי "כן" רץ `execOp` על אותה רשימה בדיוק, בטרנזקציה אחת (index.ts).

import type { Tx } from './db.ts'
import { asServiceWithin, asUser, dbError, service } from './db.ts'
import { download } from './greenapi.ts'
import {
  ArgError,
  args,
  crewSize,
  eventLabel,
  israelLocalToIso,
  lineAssign,
  lineCreateTask,
  lineInvoice,
  lineMission,
  lineMoney,
  lineMoveEvent,
  lineNote,
  lineStatus,
  lineTaskTimes,
  lineUnassign,
  monthHe,
  roleHe,
  toolByName,
} from '../_shared/assistant.ts'
import type { CrewRow, TaskTimes, ToolDef } from '../_shared/assistant.ts'
import { addDays, daysBetween, fmtDay, fmtMoney, fmtTime, periodRange } from '../_shared/whatsapp.ts'
import type { Period } from '../_shared/whatsapp.ts'
import { imageToPdf, invoiceClient, invoiceModel, readInvoicePdf } from '../_shared/invoiceRead.ts'
import { sha256Hex } from '../_shared/invoice.ts'

export interface PendingOp {
  op: string
  args: Record<string, unknown>
  preview: string[]
  links: string[]
}

export interface ToolCtx {
  /** auth.users.id — הזהות שהמסד מכיר */
  uid: string
  profileId: string
  isAdmin: boolean
  /** שמות הכלים שהוצעו למשתמש הזה */
  offered: Set<string>
  chat: { id: string; isGroup: boolean; participants: unknown[]; botWid: string }
  today: string
  now: Date
  appUrl: string
  file: { url: string; mime: string; name: string } | null
  anthropicKey: string
}

export interface ToolOutcome {
  content: string
  isError?: boolean
  pending?: PendingOp[]
}

const PERIODS = ['today', 'tomorrow', 'this_week', 'next_week', 'this_month', 'last_month', 'next_month'] as const
const MAX_RESULT = 12_000
const MAX_FILE = 14 * 1024 * 1024

const json = (v: unknown) => {
  const s = JSON.stringify(v)
  return s.length <= MAX_RESULT ? s : `${s.slice(0, MAX_RESULT)} …(truncated)`
}

const link = (ctx: ToolCtx, path: string) => `${ctx.appUrl}${path}`
const eventLink = (ctx: ToolCtx, id: string) => link(ctx, `/events/${id}`)

type Input = Record<string, unknown>

/** טווח תאריכים: period, או date_from/date_to, או ברירת מחדל */
function range(ctx: ToolCtx, i: Input, fallback: Period, maxDays: number): { from: string; to: string } {
  let from = args.date(i, 'date_from')
  let to = args.date(i, 'date_to')
  if (i.period !== undefined && i.period !== null && i.period !== '') {
    ;({ from, to } = periodRange(args.oneOf(i, 'period', PERIODS), ctx.now))
  }
  if (!from && !to) ({ from, to } = periodRange(fallback, ctx.now))
  from ??= to!
  to ??= from
  if (from > to) [from, to] = [to, from]
  if (daysBetween(from, to) > maxDays) throw new ArgError(`the range may span at most ${maxDays} days`)
  return { from, to }
}

const rangeText = (r: { from: string; to: string }, today: string) =>
  r.from === r.to ? fmtDay(r.from, today) : `${fmtDay(r.from, today)} – ${fmtDay(r.to, today)}`

const likePattern = (q: string) => `%${q.replace(/[\\%_]/g, (m) => `\\${m}`)}%`

const times = (r: { task_date: string; onsite_start_time: string | null; warehouse_start_time: string | null; hours_count: number | string | null }): TaskTimes => ({
  date: r.task_date,
  onsite: r.onsite_start_time,
  warehouse: r.warehouse_start_time,
  hours: r.hours_count == null ? null : Number(r.hours_count),
})

interface BoardRow extends CrewRow {
  id: string
  event_id: string | null
  task_type_name: string
  task_type_code: string | null
  title: string | null
  task_date: string
  warehouse_start_time: string | null
  onsite_start_time: string | null
  hours_count: number | null
  worker_count: number | null
  status_name: string
  status_code: string | null
  requires_team_lead: boolean | null
  end_client_name: string | null
  customer_name: string | null
  event_number: string | null
  event_date?: string | null
  location_text?: string | null
  notes?: string | null
  updated_at?: string
}

// תאריכים ושעות כטקסט: postgres.js הופך date ל-Date של JS, וזה שובר השוואות.
// ‏updated_at כטקסט: Date מעגל למילישניות, והעמודה שומרת מיקרו-שניות.
const BOARD_COLUMNS = `w.id, w.event_id, w.task_type_name, w.task_type_code, w.title, w.task_date::text as task_date,
  w.warehouse_start_time::text as warehouse_start_time, w.onsite_start_time::text as onsite_start_time,
  w.hours_count::float8 as hours_count, w.worker_count, w.status_name, w.status_code,
  w.team_lead_name, w.team_lead_id, w.team_lead_kind, w.workers, w.drivers, w.contractor_worker_list,
  w.customer_worker_list, w.requires_team_lead, w.end_client_name, w.customer_name, w.event_number,
  w.location_text, w.notes, w.updated_at::text as updated_at,
  (select e.event_date::text from events e where e.id = w.event_id) as event_date`

/** משימה בשורה אחת, כפי שהמודל צריך אותה */
function compactTask(ctx: ToolCtx, w: BoardRow) {
  const crew = crewSize(w)
  const need = w.worker_count ?? 0
  const names = (l: { name: string }[] | null | undefined) => (l ?? []).map((x) => x.name)
  return {
    task_id: w.id,
    event_id: w.event_id,
    event: eventLabel({ ...w, event_date: w.event_date ?? null }, ctx.today),
    type: w.title || w.task_type_name,
    type_code: w.task_type_code,
    date: w.task_date,
    day: fmtDay(w.task_date, ctx.today),
    warehouse_start: fmtTime(w.warehouse_start_time) || null,
    onsite_start: fmtTime(w.onsite_start_time) || null,
    hours: w.hours_count,
    workers_needed: need,
    crew_size: crew,
    missing_workers: Math.max(0, need - crew),
    team_lead: w.team_lead_name ?? null,
    missing_team_lead: !!w.requires_team_lead && !w.team_lead_name,
    workers: names(w.workers),
    drivers: names(w.drivers),
    contractor_workers: names(w.contractor_worker_list),
    customer_workers: names(w.customer_worker_list),
    status: w.status_name,
    published: w.status_code === 'assigned',
    link: link(ctx, `/board?task=${w.id}&date=${w.task_date}`),
  }
}

async function boardRow(tx: Tx, taskId: string): Promise<BoardRow> {
  const [r] = await tx.unsafe(`select ${BOARD_COLUMNS} from work_board_view w where w.id = $1::uuid`, [taskId])
  if (!r) throw new ArgError('task not found (or not visible to this user)')
  return r as unknown as BoardRow
}

/** האירוע, ויום המשימה כשהוא אחר מיום האירוע (הקמה ביום שלפני) */
const taskWhen = (ctx: ToolCtx, w: BoardRow) =>
  `${eventLabel({ ...w, event_date: w.event_date ?? null }, ctx.today)}${
    w.event_date && w.event_date !== w.task_date ? ` (המשימה ב${fmtDay(w.task_date, ctx.today)})` : ''
  }`

const taskTitle = (ctx: ToolCtx, w: BoardRow) => `${w.title || w.task_type_name} · ${taskWhen(ctx, w)}`

interface EventRow {
  id: string
  customer_id: string
  event_date: string
  event_number: string | null
  end_client_name: string | null
  customer_name: string | null
  location_text: string | null
  status: string | null
  status_code: string | null
  notes: string | null
  updated_at: string
}

async function eventRow(tx: Tx, id: string): Promise<EventRow> {
  const [r] = await tx`
    select e.id, e.customer_id, e.event_date::text as event_date, e.event_number, e.end_client_name,
           c.name as customer_name, e.location_text, s.name as status, s.code as status_code, e.notes,
           e.updated_at::text as updated_at
      from events e
      left join customers c on c.id = e.customer_id
      left join statuses s on s.id = e.status_id
     where e.id = ${id}::uuid and e.deleted_at is null`
  if (!r) throw new ArgError('event not found (or not visible to this user)')
  return r as unknown as EventRow
}

// ===== שאלות ===============================================================

const READ: Record<string, (ctx: ToolCtx, i: Input) => Promise<unknown>> = {
  async find_events(ctx, i) {
    const q = args.text(i, 'query', { max: 80 })
    const dated = !!(i.period || i.date_from || i.date_to)
    const r = dated
      ? range(ctx, i, 'today', 1100)
      : q
        ? { from: addDays(ctx.today, -365), to: addDays(ctx.today, 730) }
        : { from: ctx.today, to: addDays(ctx.today, 30) }
    const withCancelled = args.bool(i, 'include_cancelled', false)
    const pat = q ? likePattern(q) : null
    const rows = await asUser(ctx.uid, 'read', async (tx) => {
      const [x] = await tx`
        select coalesce(jsonb_agg(x order by x.event_date, x.event_number), '[]'::jsonb) as rows from (
          select e.id, e.event_date, e.event_number, e.end_client_name, c.name as customer_name,
                 e.location_text, s.name as status, coalesce(s.code = 'cancelled', false) as cancelled,
                 (select coalesce(jsonb_agg(jsonb_build_object(
                           'type', tt.name, 'date', t.task_date, 'onsite', to_char(t.onsite_start_time, 'HH24:MI'))
                         order by t.task_date, t.onsite_start_time), '[]'::jsonb)
                    from tasks t join task_types tt on tt.id = t.task_type_id
                   where t.event_id = e.id and t.deleted_at is null and tt.code in ('setup', 'teardown')) as setup_teardown
            from events e
            left join customers c on c.id = e.customer_id
            left join statuses s on s.id = e.status_id
           where e.deleted_at is null
             and e.event_date between ${r.from}::date and ${r.to}::date
             and (${withCancelled}::boolean or coalesce(s.code, '') <> 'cancelled')
             and (${pat}::text is null
                  or e.end_client_name ilike ${pat}::text or e.event_number ilike ${pat}::text
                  or e.location_text ilike ${pat}::text or c.name ilike ${pat}::text)
           order by e.event_date, e.event_number
           limit 15) x`
      return x.rows as Record<string, unknown>[]
    })
    return {
      searched: { query: q, range: rangeText(r, ctx.today) },
      events: rows.map((e) => ({
        event_id: e.id,
        label: eventLabel(e as never, ctx.today),
        date: e.event_date,
        status: e.status,
        cancelled: e.cancelled,
        location: e.location_text,
        setup_teardown: ((e.setup_teardown ?? []) as { type: string; date: string; onsite: string | null }[])
          .map((t) => `${t.type} ${fmtDay(t.date, ctx.today)}${t.onsite ? ` ${t.onsite}` : ''}`)
          .join('; '),
        link: eventLink(ctx, String(e.id)),
      })),
    }
  },

  async event_details(ctx, i) {
    const id = args.uuid(i, 'event_id')!
    return await asUser(ctx.uid, 'read', async (tx) => {
      const e = await eventRow(tx, id)
      const tasks = (await tx.unsafe(
        `select ${BOARD_COLUMNS} from work_board_view w where w.event_id = $1::uuid
          order by w.task_date, w.onsite_start_time nulls last`,
        [id],
      )) as unknown as BoardRow[]
      return {
        event_id: e.id,
        label: eventLabel(e, ctx.today),
        date: e.event_date,
        customer: e.customer_name,
        end_client: e.end_client_name,
        number: e.event_number,
        location: e.location_text,
        status: e.status,
        notes: e.notes ? e.notes.slice(0, 300) : null,
        tasks: tasks.map((w) => ({ ...compactTask(ctx, w), notes: w.notes ? w.notes.slice(0, 200) : null })),
        link: eventLink(ctx, e.id),
      }
    })
  },

  async schedule(ctx, i) {
    const r = range(ctx, i, 'tomorrow', 14)
    const onlyMissing = args.bool(i, 'only_missing_crew', false)
    const rows = await asUser(ctx.uid, 'read', async (tx) =>
      (await tx.unsafe(
        `select ${BOARD_COLUMNS} from work_board_view w
          where w.task_date between $1::date and $2::date
            and w.event_is_cancelled = false and w.hidden_on_board = false
          order by w.task_date, w.onsite_start_time nulls last
          limit 200`,
        [r.from, r.to],
      )) as unknown as BoardRow[],
    )
    const tasks = rows.map((w) => compactTask(ctx, w))
    const shown = onlyMissing ? tasks.filter((t) => t.missing_workers > 0 || t.missing_team_lead) : tasks
    return {
      range: rangeText(r, ctx.today),
      total_tasks: tasks.length,
      tasks: shown,
      truncated: rows.length === 200,
      link: link(ctx, `/board?date=${r.from}`),
    }
  },

  async finance_summary(ctx, i) {
    const r = range(ctx, i, 'this_month', 400)
    const out = await asUser(ctx.uid, 'read', async (tx) => {
      const [a] = await tx`select dashboard_stats(${r.from}::date, ${r.to}::date) -> 'revenue' as revenue`
      const [b] = await tx`
        select dashboard_sections(array['finance.profit_summary'], ${r.from}::date, ${r.to}::date, '{}'::jsonb)
               -> 'finance.profit_summary' as profit`
      return { revenue: a.revenue as Record<string, unknown> | null, profit: b.profit as Record<string, unknown> | null }
    })
    const rev = out.revenue
    const pr = out.profit
    return {
      range: rangeText(r, ctx.today),
      revenue: rev
        ? {
            label: 'הכנסות בטווח',
            total: rev.total,
            priced_tasks: rev.priced_tasks,
            top_customers: ((rev.by_customer ?? []) as { name: string; total: number }[]).slice(0, 8).map((c) => ({ name: c.name, total: c.total })),
          }
        : 'not available to this user',
      profit: pr
        ? {
            label: 'רווח',
            profit: pr.profit,
            margin_pct: pr.pct,
            revenue_basis: pr.revenue,
            payroll_with_employer_cost: pr.payroll_with_employer,
            contractors: pr.contractor,
            excludes_overhead: pr.excludes_overhead,
            unrated_shifts: pr.unrated_shifts,
          }
        : 'not available to this user',
      link: link(ctx, '/'),
    }
  },

  async receivables(ctx, i) {
    const r = range(ctx, i, 'this_month', 400)
    const customer = args.uuid(i, 'customer_id', false)
    return await asUser(ctx.uid, 'read', async (tx) => {
      const [d] = customer
        ? await tx`select event_payments_dashboard(${r.from}::date, ${r.to}::date, ${customer}::uuid) as d`
        : await tx`select event_payments_dashboard(${r.from}::date, ${r.to}::date) as d`
      if (!d.d) return { error: 'not available to this user' }
      const [l] = await tx`
        select coalesce(jsonb_agg(to_jsonb(x) order by x.balance desc), '[]'::jsonb) as rows from (
          select event_id, event_date, end_client_name, event_number, customer_name, due, paid, balance
            from event_payments_list(${r.from}::date, ${r.to}::date)
           where balance > 0 and not cancelled
             and (${customer}::uuid is null or customer_id = ${customer}::uuid)
           order by balance desc
           limit 15) x`
      const dash = d.d as Record<string, unknown>
      return {
        range: rangeText(r, ctx.today),
        by: 'event date',
        due: dash.due,
        paid: dash.paid,
        unpaid: dash.unpaid,
        events: dash.events,
        open_events: dash.open_events,
        open: (l.rows as Record<string, unknown>[]).map((e) => ({
          event_id: e.event_id,
          label: eventLabel(e as never, ctx.today),
          due: e.due,
          paid: e.paid,
          balance: e.balance,
          link: eventLink(ctx, String(e.event_id)),
        })),
        link: link(ctx, '/payments'),
      }
    })
  },

  async event_payment(ctx, i) {
    const id = args.uuid(i, 'event_id')!
    return await asUser(ctx.uid, 'read', async (tx) => {
      const e = await eventRow(tx, id)
      const [s] = await tx`select event_payment_summary(${id}::uuid) as s`
      const sum = s.s as Record<string, unknown> | null
      if (!sum) return { error: 'not available to this user' }
      if (sum.enabled === false) return { label: eventLabel(e, ctx.today), payments_enabled: false }
      return {
        label: eventLabel(e, ctx.today),
        due: sum.due,
        paid: sum.paid,
        balance: sum.balance,
        lines: sum.lines,
        payments: ((sum.payments ?? []) as Record<string, unknown>[]).slice(0, 15),
        link: eventLink(ctx, id),
      }
    })
  },

  async cash_wallet(ctx, i) {
    const r = range(ctx, i, 'this_month', 400)
    return await asUser(ctx.uid, 'read', async (tx) => {
      const [w] = await tx`select cash_wallet(${r.from}::date, ${r.to}::date) as w`
      const x = w.w as Record<string, unknown> | null
      if (!x) return { error: 'not available to this user' }
      const entries = (x.entries ?? []) as Record<string, unknown>[]
      return {
        range: rangeText(r, ctx.today),
        balance_now: x.balance,
        opening: x.opening,
        cash_in: x.cash_in,
        income: x.income,
        expenses: x.expenses,
        closing: x.closing,
        latest_entries: entries.slice(-15).map((e) => ({
          date: e.date, amount: e.amount, label: e.label, note: e.note, event: e.event_name ?? e.event_number ?? null,
        })),
        link: link(ctx, '/wallet'),
      }
    })
  },

  async missions(ctx, i) {
    const owner = args.oneOf(i, 'owner', ['me', 'all'] as const, 'me')
    const board = await asUser(ctx.uid, 'read', async (tx) => {
      const [b] = await tx`select missions_board(${owner === 'me' ? ctx.profileId : null}::uuid) as b`
      return b.b as { missions?: Record<string, unknown>[] }
    })
    const local = (iso: string) =>
      new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Jerusalem', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(iso))
    const hhmm = (iso: string) =>
      new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Jerusalem', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(new Date(iso))
    const open = (board.missions ?? []).filter((m) => m.status === 'open')
    const shape = (m: Record<string, unknown>) => ({
      mission_id: m.id,
      title: m.title,
      due: `${fmtDay(local(String(m.due_at)), ctx.today)} ${hhmm(String(m.due_at))}`,
      priority: m.priority,
      owner: m.owner_name,
      postponed: m.postpone_count,
    })
    const now = ctx.now.getTime()
    return {
      overdue: open.filter((m) => new Date(String(m.due_at)).getTime() < now).map(shape),
      today: open.filter((m) => new Date(String(m.due_at)).getTime() >= now && local(String(m.due_at)) === ctx.today).map(shape),
      upcoming: open.filter((m) => local(String(m.due_at)) > ctx.today).slice(0, 15).map(shape),
      link: link(ctx, '/command'),
    }
  },

  async staff_lookup(ctx, i) {
    const name = args.text(i, 'name', { max: 60 })
    const role = i.role ? args.oneOf(i, 'role', ['worker', 'driver', 'team_lead'] as const) : null
    const pat = name ? likePattern(name) : null
    const rows = await asUser(ctx.uid, 'read', async (tx) => {
      const [x] = await tx`
        select coalesce(jsonb_agg(x order by x.full_name), '[]'::jsonb) as rows from (
          select p.id, p.full_name, coalesce(array_agg(sr.role::text) filter (where sr.role is not null), '{}') as roles
            from profiles p
            left join staff_roles sr on sr.profile_id = p.id
           where p.user_kind = 'staff' and p.is_active and p.deleted_at is null
             and (${pat}::text is null or p.full_name ilike ${pat}::text)
           group by p.id, p.full_name
          having ${role}::text is null or ${role}::text = any (array_agg(sr.role::text))
           order by p.full_name
           limit 30) x`
      return x.rows as { id: string; full_name: string; roles: string[] }[]
    })
    return { people: rows.map((p) => ({ profile_id: p.id, name: p.full_name, roles: p.roles.map(roleHe) })) }
  },

  async reference(ctx) {
    return await asUser(ctx.uid, 'read', async (tx) => {
      const [x] = await tx`
        select
          (select coalesce(jsonb_agg(jsonb_build_object('task_type_id', id, 'name', name, 'code', code) order by sort_order, name), '[]')
             from task_types where is_active and deleted_at is null) as task_types,
          (select coalesce(jsonb_agg(jsonb_build_object('status_id', id, 'name', name, 'code', code) order by sort_order, name), '[]')
             from statuses where entity = 'task' and is_active and deleted_at is null) as task_statuses,
          (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name) order by sort_order, name), '[]')
             from execution_methods where is_active and deleted_at is null) as execution_methods`
      return { ...x, note: 'publish = the status with code "assigned"' }
    })
  },
}

// ===== שינויים: הכנה ========================================================

type Prepare = (ctx: ToolCtx, i: Input) => Promise<PendingOp>

const PREPARE: Record<string, Prepare> = {
  async reschedule_task(ctx, i) {
    const taskId = args.uuid(i, 'task_id')!
    const date = args.date(i, 'date')
    const onsite = args.time(i, 'onsite_start_time')
    const warehouse = args.time(i, 'warehouse_start_time')
    const hours = args.num(i, 'hours', { min: 0.25, max: 24 })
    if (date === null && onsite === undefined && warehouse === undefined && hours === null) {
      throw new ArgError('nothing to change: give date, onsite_start_time, warehouse_start_time or hours')
    }
    const w = await asUser(ctx.uid, 'read', (tx) => boardRow(tx, taskId))
    const before = times(w)
    const after: TaskTimes = {
      date: date ?? before.date,
      onsite: onsite === undefined ? before.onsite : onsite,
      warehouse: warehouse === undefined ? before.warehouse : warehouse,
      hours: hours ?? before.hours,
    }
    const set: Record<string, unknown> = {}
    if (date && date !== before.date) set.task_date = date
    if (onsite !== undefined && fmtTime(onsite) !== fmtTime(before.onsite)) set.onsite_start_time = onsite
    if (warehouse !== undefined && fmtTime(warehouse) !== fmtTime(before.warehouse)) set.warehouse_start_time = warehouse
    if (hours !== null && hours !== before.hours) set.hours_count = hours
    if (!Object.keys(set).length) throw new ArgError('the task already has these values — nothing to change')
    const notified = w.status_code === 'assigned' && ('task_date' in set || 'onsite_start_time' in set || 'warehouse_start_time' in set)
      ? crewSize(w)
      : 0
    return {
      op: 'reschedule_task',
      args: { task_id: taskId, set, expect: w.updated_at },
      preview: [lineTaskTimes(w.title || w.task_type_name, taskWhen(ctx, w), before, after, ctx.today, notified)],
      links: [link(ctx, `/board?task=${taskId}&date=${after.date}`)],
    }
  },

  async move_event(ctx, i) {
    const eventId = args.uuid(i, 'event_id')!
    const newDate = args.date(i, 'new_date', true)!
    const moveTasks = args.bool(i, 'move_setup_teardown', true)
    const { e, tasks } = await asUser(ctx.uid, 'read', async (tx) => {
      const e = await eventRow(tx, eventId)
      const tasks = (await tx.unsafe(
        `select ${BOARD_COLUMNS} from work_board_view w
          where w.event_id = $1::uuid and w.task_type_code in ('setup', 'teardown')
          order by w.task_date, w.onsite_start_time nulls last`,
        [eventId],
      )) as unknown as BoardRow[]
      return { e, tasks }
    })
    if (newDate === e.event_date) throw new ArgError('the event is already on that date')
    const delta = daysBetween(e.event_date, newDate)
    const moved = moveTasks
      ? tasks.map((t) => ({ task_id: t.id, task_date: addDays(t.task_date, delta), expect: t.updated_at, row: t }))
      : []
    const label = eventLabel(e, ctx.today)
    return {
      op: 'move_event',
      args: {
        event_id: eventId,
        event_date: newDate,
        expect: e.updated_at,
        tasks: moved.map(({ task_id, task_date, expect }) => ({ task_id, task_date, expect })),
      },
      preview: [
        lineMoveEvent(label, e.event_date, newDate, ctx.today),
        ...moved.map(({ row, task_date }) =>
          lineTaskTimes(row.title || row.task_type_name, '', times(row), { ...times(row), date: task_date }, ctx.today,
            row.status_code === 'assigned' ? crewSize(row) : 0)),
      ],
      links: [eventLink(ctx, eventId)],
    }
  },

  async create_task(ctx, i) {
    const eventId = args.uuid(i, 'event_id')!
    const typeId = args.uuid(i, 'task_type_id')!
    const date = args.date(i, 'date', true)!
    const onsite = args.time(i, 'onsite_start_time') ?? null
    const warehouse = args.time(i, 'warehouse_start_time') ?? null
    const hours = args.num(i, 'hours', { min: 0.25, max: 24 })
    const workers = args.num(i, 'worker_count', { min: 0, max: 200, int: true })
    const notes = args.text(i, 'notes', { max: 1000 })
    const { e, typeName } = await asUser(ctx.uid, 'read', async (tx) => {
      const e = await eventRow(tx, eventId)
      const [tt] = await tx`select name from task_types where id = ${typeId}::uuid and is_active and deleted_at is null`
      if (!tt) throw new ArgError('unknown task_type_id — take it from the reference tool')
      return { e, typeName: String(tt.name) }
    })
    return {
      op: 'create_task',
      args: {
        event_id: eventId, customer_id: e.customer_id, task_type_id: typeId, task_date: date,
        onsite_start_time: onsite, warehouse_start_time: warehouse, hours_count: hours, worker_count: workers, notes,
      },
      preview: [lineCreateTask(typeName, eventLabel(e, ctx.today), { date, onsite, warehouse, hours, workers }, ctx.today)],
      links: [eventLink(ctx, eventId)],
    }
  },

  async assign_crew(ctx, i) {
    const taskId = args.uuid(i, 'task_id')!
    const profileId = args.uuid(i, 'profile_id')!
    const role = args.oneOf(i, 'role', ['worker', 'driver', 'team_lead'] as const)
    const site = args.oneOf(i, 'work_site', ['field', 'warehouse'] as const, 'field')
    const { w, person, conflicts } = await asUser(ctx.uid, 'read', async (tx) => {
      const w = await boardRow(tx, taskId)
      const [p] = await tx`
        select p.full_name,
               exists (select 1 from staff_roles sr where sr.profile_id = p.id and sr.role = ${role}::staff_role) as has_role
          from profiles p
         where p.id = ${profileId}::uuid and p.user_kind = 'staff' and p.is_active and p.deleted_at is null`
      if (!p) throw new ArgError('person not found — take profile_id from staff_lookup')
      if (!p.has_role) throw new ArgError(`${p.full_name} is not set up as ${role} (staff roles); choose someone with that role`)
      const [c] = await tx`select assignment_conflicts(${taskId}::uuid, array[${profileId}]::uuid[]) as c`
      const conflicts = ((c.c ?? []) as Record<string, unknown>[]).filter((x) => x.kind === 'worker' && x.subject_id === profileId)
      return { w, person: String(p.full_name), conflicts }
    })
    if (role === 'team_lead' && w.team_lead_name && w.team_lead_kind && w.team_lead_kind !== 'staff') {
      throw new ArgError('the task has a contractor/customer team lead; replacing it is done in the system')
    }
    const already = role === 'team_lead'
      ? w.team_lead_id === profileId
      : ((role === 'worker' ? w.workers : w.drivers) ?? []).some((x) => x.profile_id === profileId)
    if (already) throw new ArgError(`${person} is already ${role} on this task`)
    const replaces = role === 'team_lead' && w.team_lead_name ? w.team_lead_name : null
    const preview = [lineAssign(person, role, taskTitle(ctx, w), replaces)]
    for (const c of conflicts.slice(0, 3)) {
      preview.push(`  ⚠️ ${person} כבר משובץ באותו זמן: ${c.task_label ?? 'משימה'}${c.customer_name ? ` · ${c.customer_name}` : ''}`)
    }
    return {
      op: 'assign_crew',
      args: { task_id: taskId, profile_id: profileId, role, work_site: site },
      preview,
      links: [link(ctx, `/board?task=${taskId}&date=${w.task_date}`)],
    }
  },

  async unassign_crew(ctx, i) {
    const taskId = args.uuid(i, 'task_id')!
    const profileId = args.uuid(i, 'profile_id')!
    const role = args.oneOf(i, 'role', ['worker', 'driver', 'team_lead'] as const)
    const { w, name } = await asUser(ctx.uid, 'read', async (tx) => {
      const w = await boardRow(tx, taskId)
      const [a] = await tx`
        select p.full_name from task_assignments a join profiles p on p.id = a.profile_id
         where a.task_id = ${taskId}::uuid and a.profile_id = ${profileId}::uuid and a.role = ${role}::assignment_role`
      if (!a) throw new ArgError(`this person is not assigned as ${role} on this task`)
      return { w, name: String(a.full_name) }
    })
    return {
      op: 'unassign_crew',
      args: { task_id: taskId, profile_id: profileId, role },
      preview: [lineUnassign(name, role, taskTitle(ctx, w))],
      links: [link(ctx, `/board?task=${taskId}&date=${w.task_date}`)],
    }
  },

  async set_task_status(ctx, i) {
    const ids = args.uuids(i, 'task_ids', 30)
    const statusId = args.uuid(i, 'status_id')!
    const { rows, status } = await asUser(ctx.uid, 'read', async (tx) => {
      const [s] = await tx`select name, code from statuses where id = ${statusId}::uuid and entity = 'task' and is_active and deleted_at is null`
      if (!s) throw new ArgError('unknown status_id — take it from the reference tool')
      const rows: BoardRow[] = []
      for (const id of ids) rows.push(await boardRow(tx, id))
      return { rows, status: s as { name: string; code: string | null } }
    })
    const changing = rows.filter((w) => w.status_code !== status.code || w.status_name !== status.name)
    if (!changing.length) throw new ArgError('these tasks already have that status')
    const preview: string[] = []
    for (const w of changing) {
      preview.push(lineStatus(taskTitle(ctx, w), w.status_name, status.name))
      if (status.code === 'assigned') {
        const missing = Math.max(0, (w.worker_count ?? 0) - crewSize(w))
        if (missing) preview.push(`  ⚠️ חסרים ${missing} עובדים`)
        if (w.requires_team_lead && !w.team_lead_name) preview.push('  ⚠️ אין ראש צוות')
      }
    }
    return {
      op: 'set_task_status',
      args: { status_id: statusId, tasks: changing.map((w) => ({ task_id: w.id, expect: w.updated_at })) },
      preview,
      links: [link(ctx, `/board?date=${changing[0].task_date}`)],
    }
  },

  async create_mission(ctx, i) {
    const title = args.text(i, 'title', { max: 200, required: true })!
    const due = israelLocalToIso(String(i.due_at ?? ''))
    const priority = args.num(i, 'priority', { min: 1, max: 4, int: true }) ?? 2
    const description = args.text(i, 'description', { max: 2000 })
    const owner = args.uuid(i, 'owner_id', false)
    const recurrence = args.oneOf(i, 'recurrence', ['none', 'daily', 'weekly', 'monthly'] as const, 'none')
    let ownerName: string | null = null
    if (owner && owner !== ctx.profileId) {
      ownerName = await asUser(ctx.uid, 'read', async (tx) => {
        const [p] = await tx`select full_name from profiles where id = ${owner}::uuid and is_admin and is_active and deleted_at is null`
        if (!p) throw new ArgError('owner_id must be an active admin')
        return String(p.full_name)
      })
    }
    return {
      op: 'create_mission',
      args: { p: { title, description, owner_id: owner ?? ctx.profileId, due_at: due, priority, recurrence } },
      preview: [lineMission(title, due, priority, ownerName) + (recurrence !== 'none' ? ` · חוזרת (${{ daily: 'כל יום', weekly: 'כל שבוע', monthly: 'כל חודש' }[recurrence]})` : '')],
      links: [link(ctx, '/command')],
    }
  },

  async complete_mission(ctx, i) {
    const id = args.uuid(i, 'mission_id')!
    const m = await missionById(ctx, id)
    return { op: 'complete_mission', args: { mission_id: id }, preview: [`• *סימון כבוצעה:* "${m.title}"`], links: [link(ctx, '/command')] }
  },

  async snooze_mission(ctx, i) {
    const id = args.uuid(i, 'mission_id')!
    const minutes = args.num(i, 'minutes', { min: 1, max: 129600, int: true, required: true })!
    const m = await missionById(ctx, id)
    const until = new Date(Math.max(new Date(m.due_at).getTime(), ctx.now.getTime()) + minutes * 60_000)
    const local = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Jerusalem', year: 'numeric', month: '2-digit', day: '2-digit' }).format(until)
    const hhmm = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Jerusalem', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(until)
    return {
      op: 'snooze_mission',
      args: { mission_id: id, minutes },
      preview: [`• *דחייה:* "${m.title}" עד ~${fmtDay(local, ctx.today)} ${hhmm}`],
      links: [link(ctx, '/command')],
    }
  },

  async add_event_payment(ctx, i) {
    const eventId = args.uuid(i, 'event_id')!
    const amount = args.num(i, 'amount', { min: 0.01, max: 10_000_000, required: true })!
    const method = args.oneOf(i, 'method', ['cash', 'other'] as const)
    const note = args.text(i, 'note', { max: 300 })
    const date = args.date(i, 'received_at') ?? ctx.today
    const e = await asUser(ctx.uid, 'read', (tx) => eventRow(tx, eventId))
    return {
      op: 'add_event_payment',
      args: { event_id: eventId, amount, method, note, received_at: date },
      preview: [lineMoney('payment', amount, `${eventLabel(e, ctx.today)} · ${method === 'cash' ? 'מזומן' : 'אחר'}${note ? ` · ${note}` : ''} · ${fmtDay(date, ctx.today)}`, null)],
      links: [eventLink(ctx, eventId)],
    }
  },

  async add_event_charge(ctx, i) {
    const eventId = args.uuid(i, 'event_id')!
    const label = args.text(i, 'label', { max: 200, required: true })!
    const amount = args.num(i, 'amount', { min: 0.01, max: 10_000_000, required: true })!
    const note = args.text(i, 'note', { max: 300 })
    const e = await asUser(ctx.uid, 'read', (tx) => eventRow(tx, eventId))
    return {
      op: 'add_event_charge',
      args: { event_id: eventId, label, amount, note },
      preview: [lineMoney('charge', amount, `"${label}" · ${eventLabel(e, ctx.today)}`, null)],
      links: [eventLink(ctx, eventId)],
    }
  },

  async add_cash_entry(ctx, i) {
    const kind = args.oneOf(i, 'kind', ['expense', 'income'] as const)
    const amount = args.num(i, 'amount', { min: 0.01, max: 10_000_000, required: true })!
    const label = args.text(i, 'label', { max: 200, required: true })!
    const note = args.text(i, 'note', { max: 300 })
    const date = args.date(i, 'entry_date') ?? ctx.today
    return {
      op: 'add_cash_entry',
      args: { kind, amount, label, note, entry_date: date },
      preview: [lineMoney(kind === 'income' ? 'cash_in' : 'cash_out', amount, `"${label}" · ${fmtDay(date, ctx.today)}`, null)],
      links: [link(ctx, '/wallet')],
    }
  },

  async add_event_note(ctx, i) {
    const eventId = args.uuid(i, 'event_id')!
    const text = args.text(i, 'text', { max: 2000, required: true })!
    const e = await asUser(ctx.uid, 'read', (tx) => eventRow(tx, eventId))
    return {
      op: 'add_event_note',
      args: { event_id: eventId, text },
      preview: [lineNote(eventLabel(e, ctx.today), text)],
      links: [eventLink(ctx, eventId)],
    }
  },

  async save_supplier_invoice(ctx) {
    if (!ctx.file) throw new ArgError('there is no file in this message')
    if (!ctx.anthropicKey) throw new ArgError('invoice reading is not configured')
    const { pdf, sha, sourceSha, name } = await invoicePdf(ctx.file)
    const dup = await asUser(ctx.uid, 'read', async (tx) => {
      const [d] = await tx`select vendor_name, issue_date::text as issue_date from invoices where file_sha256 = ${sha} and deleted_at is null`
      return d ?? null
    })
    if (dup) {
      throw new ArgError(`this exact file is already saved in the invoices page${dup.vendor_name ? ` (${dup.vendor_name})` : ''}`)
    }
    const { reading, model } = await readInvoicePdf(invoiceClient(ctx.anthropicKey), invoiceModel(), pdf, `File name: ${name}.`)
    if (reading.kind !== 'invoice') {
      throw new ArgError('this file does not look like a supplier invoice or receipt — ask the user what it is')
    }
    const folder = `${ctx.today.slice(0, 7)}-01`
    return {
      op: 'save_supplier_invoice',
      args: { url: ctx.file.url, mime: ctx.file.mime, name, sha, source_sha: sourceSha, reading, model },
      preview: [lineInvoice({
        vendor: reading.vendor_name,
        docType: DOC_TYPE_HE[reading.doc_type ?? ''] ?? null,
        number: reading.invoice_number,
        issueDate: reading.issue_date,
        total: reading.total_amount,
        currency: reading.currency,
        folder: monthHe(folder),
      })],
      links: [link(ctx, '/invoices')],
    }
  },
}

const DOC_TYPE_HE: Record<string, string> = {
  tax_invoice: 'חשבונית מס',
  tax_invoice_receipt: 'חשבונית מס/קבלה',
  receipt: 'קבלה',
  credit: 'חשבונית זיכוי',
  other: 'מסמך',
}

async function missionById(ctx: ToolCtx, id: string): Promise<{ title: string; due_at: string }> {
  return await asUser(ctx.uid, 'read', async (tx) => {
    const [b] = await tx`select missions_board(null) as b`
    const m = ((b.b?.missions ?? []) as Record<string, unknown>[]).find((x) => x.id === id && x.status === 'open')
    if (!m) throw new ArgError('open mission not found — take mission_id from the missions tool')
    return { title: String(m.title), due_at: String(m.due_at) }
  })
}

/**
 * הקובץ שצורף, כ-PDF אחד: PDF כמו שהוא, תמונה (JPEG/PNG) כעמוד. ההמרה
 * דטרמיניסטית (`imageToPdf` בלי חותמת זמן), כך שאותה תמונה היא אותה חשבונית.
 */
async function invoicePdf(file: { url: string; mime: string; name: string }): Promise<{ pdf: Uint8Array; sha: string; sourceSha: string; name: string }> {
  const bytes = await download(file.url, MAX_FILE)
  const mime = file.mime.toLowerCase()
  const base = (file.name || 'whatsapp').replace(/\.[^.]+$/, '')
  let pdf: Uint8Array
  if (mime === 'application/pdf' || /\.pdf$/i.test(file.name)) pdf = bytes
  else if (mime === 'image/jpeg' || mime === 'image/jpg') pdf = await imageToPdf(bytes, 'image/jpeg')
  else if (mime === 'image/png') pdf = await imageToPdf(bytes, 'image/png')
  else throw new ArgError('only PDF, JPG or PNG files can be saved as invoices')
  return { pdf, sha: await sha256Hex(pdf), sourceSha: await sha256Hex(bytes), name: `${base}.pdf` }
}

// ===== שינויים: ביצוע ========================================================

export interface ExecResult {
  /** שורה לתשובה אחרי הביצוע */
  done: string
  /** שורה נוספת לתצוגה (מצב אחרי, מהרצת הניסיון) */
  after?: string
}

/**
 * מריץ פעולה אחת בתוך טרנזקציה שכבר בזהות המשתמש. `dry` — הרצת ניסיון:
 * אותו דבר בדיוק, בלי הצד החיצוני (העלאת קובץ) — הטרנזקציה ממילא מתבטלת.
 */
export async function execOp(tx: Tx, ctx: Pick<ToolCtx, 'profileId' | 'today'>, op: PendingOp, dry: boolean): Promise<ExecResult> {
  const a = op.args as Record<string, unknown>
  const one = <T>(rows: T[], msg: string): T => {
    if (!rows.length) throw new Error(msg)
    return rows[0]
  }
  switch (op.op) {
    case 'reschedule_task': {
      const set = a.set as Record<string, unknown>
      const cols: Record<string, string> = {
        task_date: 'date', onsite_start_time: 'time', warehouse_start_time: 'time', hours_count: 'numeric',
      }
      const params: unknown[] = []
      const parts = Object.entries(set).map(([k, v]) => {
        if (!cols[k]) throw new Error(`unknown column ${k}`)
        params.push(v)
        return `${k} = $${params.length}::${cols[k]}`
      })
      params.push(a.task_id, a.expect)
      one(
        await tx.unsafe(
          `update tasks set ${parts.join(', ')} where id = $${params.length - 1}::uuid and updated_at = $${params.length}::text::timestamptz returning id`,
          params as never[],
        ),
        'המשימה השתנתה מאז שהשינוי הוכן, או שאין לך הרשאה לשנות אותה',
      )
      return { done: op.preview[0] }
    }

    case 'move_event': {
      const tasks = (a.tasks ?? []) as { task_id: string; task_date: string; expect: string }[]
      const [ev] = await tx`select updated_at::text as v from events where id = ${a.event_id as string}::uuid and deleted_at is null`
      if (!ev || ev.v !== a.expect) throw new Error('האירוע השתנה מאז שהשינוי הוכן')
      for (const t of tasks) {
        const [r] = await tx`select updated_at::text as v from tasks where id = ${t.task_id}::uuid and deleted_at is null`
        if (!r || r.v !== t.expect) throw new Error('אחת המשימות של האירוע השתנתה מאז שהשינוי הוכן')
      }
      await tx`select update_event(${a.event_id as string}::uuid, jsonb_build_object('event_date', ${a.event_date as string}::date))`
      for (const t of tasks) {
        one(await tx`update tasks set task_date = ${t.task_date}::date where id = ${t.task_id}::uuid returning id`,
          'אין לך הרשאה להזיז את המשימות של האירוע')
      }
      return { done: op.preview[0] }
    }

    case 'create_task': {
      await tx`
        insert into tasks (event_id, customer_id, task_type_id, task_date, onsite_start_time, warehouse_start_time,
                           hours_count, worker_count, notes, status_id)
        values (${a.event_id as string}::uuid, ${a.customer_id as string}::uuid, ${a.task_type_id as string}::uuid,
                ${a.task_date as string}::date, ${(a.onsite_start_time as string | null) ?? null}::time,
                ${(a.warehouse_start_time as string | null) ?? null}::time, ${(a.hours_count as number | null) ?? null}::numeric,
                coalesce(${(a.worker_count as number | null) ?? null}::int, 0), ${(a.notes as string | null) ?? null},
                (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null limit 1))
        returning id`
      return { done: op.preview[0] }
    }

    case 'assign_crew': {
      if (a.role === 'team_lead') {
        await tx`delete from task_assignments
                  where task_id = ${a.task_id as string}::uuid and role = 'team_lead' and profile_id <> ${a.profile_id as string}::uuid`
      }
      one(
        await tx`
          insert into task_assignments (task_id, profile_id, role, work_site)
          values (${a.task_id as string}::uuid, ${a.profile_id as string}::uuid, ${a.role as string}::assignment_role, ${a.work_site as string})
          on conflict do nothing
          returning id`,
        'כבר משובץ בתפקיד הזה',
      )
      return { done: op.preview[0] }
    }

    case 'unassign_crew': {
      one(
        await tx`delete from task_assignments
                  where task_id = ${a.task_id as string}::uuid and profile_id = ${a.profile_id as string}::uuid
                    and role = ${a.role as string}::assignment_role
                  returning id`,
        'השיבוץ כבר לא קיים, או שאין לך הרשאה להסיר אותו',
      )
      return { done: op.preview[0] }
    }

    case 'set_task_status': {
      for (const t of (a.tasks ?? []) as { task_id: string; expect: string }[]) {
        one(
          await tx`update tasks set status_id = ${a.status_id as string}::uuid
                    where id = ${t.task_id}::uuid and updated_at = ${t.expect}::text::timestamptz
                    returning id`,
          'אחת המשימות השתנתה מאז שהשינוי הוכן, או שאין לך הרשאה לשנות אותה',
        )
      }
      return { done: op.preview.filter((l) => l.startsWith('•')).join('\n') }
    }

    case 'create_mission': {
      await tx`select mission_save(null, ${tx.json(a.p as never)})`
      return { done: op.preview[0] }
    }

    case 'complete_mission': {
      await tx`select mission_complete(${a.mission_id as string}::uuid)`
      return { done: op.preview[0] }
    }

    case 'snooze_mission': {
      await tx`select mission_snooze(${a.mission_id as string}::uuid, ${a.minutes as number}::int)`
      return { done: op.preview[0] }
    }

    case 'add_event_payment': {
      await tx`select event_payment_add(${a.event_id as string}::uuid, ${a.amount as number}::numeric, ${a.method as string},
                                        ${(a.note as string | null) ?? null}, ${a.received_at as string}::date)`
      return { done: op.preview[0], after: dry ? await balanceAfter(tx, a.event_id as string) : undefined }
    }

    case 'add_event_charge': {
      await tx`select event_charge_add(${a.event_id as string}::uuid, ${a.label as string}, ${a.amount as number}::numeric,
                                       ${(a.note as string | null) ?? null})`
      return { done: op.preview[0], after: dry ? await balanceAfter(tx, a.event_id as string) : undefined }
    }

    case 'add_cash_entry': {
      await tx`select cash_wallet_entry_add(${a.kind as string}, ${a.amount as number}::numeric, ${a.label as string},
                                            ${(a.note as string | null) ?? null}, ${a.entry_date as string}::date)`
      if (!dry) return { done: op.preview[0] }
      const [w] = await tx`select cash_wallet(${ctx.today}::date, ${ctx.today}::date) ->> 'balance' as b`
      return { done: op.preview[0], after: w?.b != null ? `  יתרת הארנק אחרי: ${fmtMoney(Number(w.b))}` : undefined }
    }

    case 'add_event_note': {
      await tx`insert into event_activity (event_id, kind, note, actor_profile_id)
               values (${a.event_id as string}::uuid, 'note', ${a.text as string}, ${ctx.profileId}::uuid)`
      return { done: op.preview[0] }
    }

    case 'save_supplier_invoice': {
      if (dry) return { done: op.preview[0] }
      const { pdf, sha, sourceSha } = await invoicePdf({ url: a.url as string, mime: a.mime as string, name: a.name as string })
      if (sourceSha !== a.source_sha) throw new Error('הקובץ שהורד עכשיו שונה מזה שנקרא — שלח אותו שוב')
      const [c] = await tx`select invoice_create(${a.name as string}, 'upload', ${sha}) as r`
      const r = c.r as { id?: string; duplicate_of?: string }
      if (r.duplicate_of || !r.id) throw new Error('החשבונית הזו כבר שמורה בעמוד החשבוניות')
      await uploadInvoice(r.id, pdf)
      await asServiceWithin(tx, async () => {
        await tx`select invoice_store_reading(${r.id!}::uuid, ${tx.json(a.reading as never)}, ${a.model as string})`
      })
      return { done: op.preview[0] }
    }
  }
  throw new Error(`unknown operation ${op.op}`)
}

async function balanceAfter(tx: Tx, eventId: string): Promise<string | undefined> {
  const [s] = await tx`select event_payment_summary(${eventId}::uuid) as s`
  const sum = s?.s as { enabled?: boolean; balance?: number } | null
  if (!sum || sum.enabled === false || sum.balance == null) return undefined
  return `  יתרה לתשלום אחרי: ${fmtMoney(Number(sum.balance))}`
}

async function uploadInvoice(id: string, pdf: Uint8Array): Promise<void> {
  const url = `${Deno.env.get('SUPABASE_URL')}/storage/v1/object/invoices/${id}.pdf`
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const res = await fetch(url, {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, apikey: key, 'content-type': 'application/pdf', 'x-upsert': 'true' },
    body: pdf as BodyInit,
    signal: AbortSignal.timeout(30_000),
  })
  if (!res.ok) throw new Error(`העלאת הקובץ נכשלה (${res.status})`)
}

// ===== הכניסה ===============================================================

/** כלי אחד: בדיקת היתר, הקבוצה, הקלט — ואז שאלה, או הכנת שינוי והרצת ניסיון. */
export async function runTool(ctx: ToolCtx, name: string, input: unknown, pendingSoFar: readonly PendingOp[]): Promise<ToolOutcome> {
  const def: ToolDef | null = toolByName(name)
  if (!def || !ctx.offered.has(name)) return { content: `tool ${name} is not available to this user`, isError: true }

  if (def.sensitive && ctx.chat.isGroup) {
    const ok = await service(async (tx) => {
      const [r] = await tx`
        select app.wa_participants_hold(${tx.json(ctx.chat.participants as never)}, ${ctx.chat.botWid},
                                        array(select jsonb_array_elements_text(${tx.json(def.groupKeys)}))) as ok`
      return r.ok === true
    })
    if (!ok) {
      return {
        content: 'blocked_in_group: not every member of this group may see this kind of data. Tell the user to ask in a private chat with the bot.',
        isError: true,
      }
    }
  }

  try {
    const i = args.obj(input ?? {})
    if (!def.write) return { content: json(await READ[name](ctx, i)) }

    const op = await PREPARE[name](ctx, i)
    // הרצת ניסיון של כל מה שהוכן בסבב הזה ושל החדש, בזהות המשתמש — ואז ביטול
    const result = await asUser(ctx.uid, 'dryrun', async (tx) => {
      for (const p of pendingSoFar) await execOp(tx, ctx, p, true)
      return await execOp(tx, ctx, op, true)
    })
    if (result?.after) op.preview.push(result.after)
    return {
      content: json({ prepared: true, shown_to_user_for_confirmation: op.preview }),
      pending: [op],
    }
  } catch (e) {
    if (e instanceof ArgError) return { content: e.message, isError: true }
    console.error(`whatsapp tool ${name}:`, e)
    return { content: `the system refused: ${dbError(e)}`, isError: true }
  }
}
