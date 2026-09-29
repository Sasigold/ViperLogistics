// לוח שנה — אותם נתונים כמו היום (שם, לקוח, סטטוס, מאושר, מיקום, משאיות, נפח, מספר, הערות), בסידור של אג'נדה + חלונית פרטים.
import { useMemo, useRef, useState } from 'react'
import { Check, ChevronLeft, ChevronRight, MapPin, PackageCheck, StickyNote, Truck } from 'lucide-react'
import { addMonths, fmtDM, hm, HE_DAYS, monthEnd, monthStart, parse, TODAY, useEvents, useTasks } from './data'
import type { LabEvent } from './data'
import { holidaysInRange } from '../../src/lib/hebrewHolidays'
import { crewPeople, crewSize } from '../../src/features/tasks/crew'
import type { WorkBoardRow } from '../../src/types/domain'
import { Chip, Rng, cx, tint } from './ui'

export function CalendarLab({ onOpen, initialSel }: { onOpen: (id: string) => void; initialSel?: string | null }) {
  const [anchor, setAnchor] = useState(TODAY)
  const [sel, setSel] = useState<string | null>(initialSel ?? null)
  const [statusF, setStatusF] = useState<string | null>(null)
  const [custF, setCustF] = useState<string | null>(null)
  const from = monthStart(anchor), to = monthEnd(anchor)
  const { data: events = [] } = useEvents(from, to)
  const { data: tasks = [] } = useTasks(from, to)
  const holidays = useMemo(() => holidaysInRange(from, to), [from, to])
  const refs = useRef<Record<string, HTMLElement | null>>({})

  const live = events.filter((e) => e.statuses?.code !== 'cancelled')
  const shown = live.filter((e) => (!statusF || e.statuses?.code === statusF) && (!custF || e.customer_id === custF))
  const statuses = [...new Map(live.filter((e) => e.statuses).map((e) => [e.statuses!.code, e.statuses!])).values()]
  const customers = [...new Map(live.filter((e) => e.customers).map((e) => [e.customer_id, e.customers!])).entries()]
  const days = [...new Set(shown.map((e) => e.event_date))].sort()
  const selected = shown.find((e) => e.id === sel) ?? null
  const first = parse(from)
  const monthName = first.toLocaleDateString('he-IL', { month: 'long', year: 'numeric' })

  // רשת חודש קטנה — ניווט מהיר בין ימים
  const lead = first.getDay()
  const dim = parse(to).getDate()
  const cells = Array.from({ length: Math.ceil((lead + dim) / 7) * 7 }, (_, i) => (i < lead || i >= lead + dim ? null : i - lead + 1))
  const dayIso = (n: number) => `${from.slice(0, 8)}${String(n).padStart(2, '0')}`

  return (
    <div className="mx-auto flex max-w-[1600px] flex-col gap-4 p-5">
      <div className="flex flex-wrap items-end gap-4">
        <div>
          <div className="lab-eyebrow">לוח שנה</div>
          <h1 className="text-[28px] font-extrabold leading-tight tracking-tight">{monthName}</h1>
          <div className="text-[13px] text-ink-tertiary">{shown.length} אירועים בתקופה המוצגת</div>
        </div>
        <div className="ms-auto flex items-center gap-2">
          <div className="flex overflow-hidden rounded-xl bg-[var(--vl-subtle)] shadow-[inset_0_0_0_1px_var(--vl-border-subtle)]">
            <button className="px-2.5 py-1.5" onClick={() => setAnchor(addMonths(anchor, 1))}><ChevronRight size={16} /></button>
            <button className="border-x border-[var(--vl-border-subtle)] px-3 text-[13px] font-semibold" onClick={() => setAnchor(TODAY)}>היום</button>
            <button className="px-2.5 py-1.5" onClick={() => setAnchor(addMonths(anchor, -1))}><ChevronLeft size={16} /></button>
          </div>
          <button className="bg-primary rounded-xl px-4 py-2 text-[13px] font-bold text-white">אירוע חדש +</button>
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-[260px_minmax(0,1fr)] xl:grid-cols-[260px_minmax(0,1fr)_400px]">
        {/* עמודת ניווט: חודש קטן + מקראים (סטטוס / לקוחות) שגם מסננים */}
        <div className="flex flex-col gap-4 lg:sticky lg:top-2 lg:h-fit">
          <div className="lab-card p-4">
            <div className="mb-2 grid grid-cols-7 text-center text-[10.5px] font-bold text-ink-tertiary">{['א׳', 'ב׳', 'ג׳', 'ד׳', 'ה׳', 'ו׳', 'ש׳'].map((d) => <span key={d}>{d}</span>)}</div>
            <div className="grid grid-cols-7 gap-y-1 text-center">
              {cells.map((n, i) => {
                if (!n) return <span key={i} />
                const d = dayIso(n)
                const dayEv = shown.filter((e) => e.event_date === d)
                const hol = holidays.get(d)
                return (
                  <button key={i} disabled={!dayEv.length} onClick={() => refs.current[d]?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
                    className={cx('relative mx-auto flex size-8 flex-col items-center justify-center rounded-xl text-[12.5px] font-semibold', d === TODAY ? 'text-white' : dayEv.length ? 'hover:bg-[var(--vl-subtle)]' : 'text-ink-tertiary', hol && d !== TODAY && 'text-[var(--vl-warning-text)]')}
                    style={d === TODAY ? { background: 'var(--nova-grad)' } : undefined}>
                    {n}
                    {dayEv.length > 0 && <span className="absolute -bottom-0.5 flex gap-px">{dayEv.slice(0, 3).map((e) => <i key={e.id} className="size-1 rounded-full" style={{ background: e.statuses?.color }} />)}</span>}
                  </button>
                )
              })}
            </div>
          </div>

          <div className="lab-card hidden p-4 lg:block">
            <div className="lab-eyebrow mb-2">סטטוס</div>
            <div className="flex flex-col gap-0.5">
              {statuses.map((s) => (
                <button key={s.code} onClick={() => setStatusF(statusF === s.code ? null : s.code)} className={cx('flex items-center gap-2 rounded-lg px-2 py-1.5 text-[13px]', statusF === s.code ? 'bg-[var(--vl-primary-subtle)] font-bold' : 'hover:bg-[var(--vl-subtle)]')}>
                  <span className="lab-dot" style={{ background: s.color }} />{s.name}<span className="ms-auto tabular-nums text-ink-tertiary">{live.filter((e) => e.statuses?.code === s.code).length}</span>
                </button>
              ))}
            </div>
            <div className="lab-eyebrow mb-2 mt-4">לקוחות בתצוגה</div>
            <div className="flex flex-col gap-0.5">
              {customers.map(([id, c]) => (
                <button key={id} onClick={() => setCustF(custF === id ? null : id)} className={cx('flex items-center gap-2 rounded-lg px-2 py-1.5 text-[13px]', custF === id ? 'bg-[var(--vl-primary-subtle)] font-bold' : 'hover:bg-[var(--vl-subtle)]')}>
                  <span className="lab-dot" style={{ background: c.color }} />{c.name}<span className="ms-auto tabular-nums text-ink-tertiary">{live.filter((e) => e.customer_id === id).length}</span>
                </button>
              ))}
            </div>
          </div>
        </div>

        {/* אג'נדה: כל יום עם אירועים, בסדר כרונולוגי */}
        <div className="flex min-w-0 flex-col gap-5">
          <div className="lab-scroll flex gap-1.5 overflow-x-auto pb-1 lg:hidden">
            {statuses.map((s) => (
              <button key={s.code} onClick={() => setStatusF(statusF === s.code ? null : s.code)} className={cx('lab-chip shrink-0', statusF === s.code && 'ring-2 ring-[var(--nova-a)]')} style={{ background: tint(s.color, 15), color: 'var(--vl-text)' }}><span className="lab-dot" style={{ background: s.color }} />{s.name} · {live.filter((e) => e.statuses?.code === s.code).length}</button>
            ))}
          </div>
          {days.length === 0 && <div className="lab-card p-10 text-center text-ink-tertiary">אין אירועים בחודש הזה</div>}
          {days.map((d) => {
            const hol = holidays.get(d)
            const list = shown.filter((e) => e.event_date === d)
            return (
              <section key={d} ref={(el) => { refs.current[d] = el }} className="flex scroll-mt-3 gap-3 sm:gap-4">
                <div className="flex w-[50px] shrink-0 flex-col items-center gap-0.5 pt-1 sm:w-[64px]">
                  <span className="text-[11px] font-bold text-ink-tertiary">{HE_DAYS[parse(d).getDay()]}</span>
                  <span className={cx('flex size-11 items-center justify-center rounded-2xl text-[20px] font-extrabold', d === TODAY ? 'text-white shadow-[0_8px_18px_-6px_var(--nova-a)]' : 'bg-[var(--vl-subtle)]')} style={d === TODAY ? { background: 'var(--nova-grad)' } : undefined}>{parse(d).getDate()}</span>
                  {d === TODAY && <span className="text-[10px] font-bold text-[var(--nova-a)]">היום</span>}
                </div>
                <div className="flex min-w-0 flex-1 flex-col gap-2.5 border-s border-[var(--vl-border-subtle)] ps-3 sm:ps-4">
                  {hol && <div className="w-fit rounded-lg bg-[var(--vl-warning-subtle)] px-2.5 py-1 text-[12px] font-semibold text-[var(--vl-warning-text)]">{hol.name}</div>}
                  {list.map((e) => <EventRow key={e.id} e={e} selected={sel === e.id} onSelect={() => setSel(e.id)} />)}
                </div>
              </section>
            )
          })}
        </div>

        <div className="hidden xl:sticky xl:top-2 xl:block xl:h-[calc(100vh-150px)]">
          {selected ? <Inspector e={selected} tasks={tasks.filter((t) => t.event_id === selected.id)} onOpen={() => onOpen(selected.id)} /> : (
            <div className="lab-card flex h-full items-center justify-center p-8 text-center text-[13.5px] text-ink-tertiary">בחר אירוע מהרשימה כדי לראות את פרטיו ואת המשימות שלו כאן</div>
          )}
        </div>
      </div>
    </div>
  )
}

function EventRow({ e, selected, onSelect }: { e: LabEvent; selected: boolean; onSelect: () => void }) {
  const c = e.customers
  const addons = [e.no_parking && 'אין חניה', e.porterage && 'סבלות', e.supplier_pickup && 'איסוף מספקים'].filter(Boolean) as string[]
  return (
    <button onClick={onSelect} className={cx('lab-card lab-hoverable flex w-full items-stretch overflow-hidden p-0 text-start', selected && 'lab-sel')}>
      <span className="w-1.5 shrink-0" style={{ background: e.statuses?.color }} />
      <div className="flex min-w-0 flex-1 flex-col gap-1.5 px-4 py-3">
        <div className="flex flex-wrap items-center gap-2">
          <span className="truncate text-[16.5px] font-extrabold tracking-tight">{e.end_client_name}</span>
          {e.approved_at && <Chip tone="good"><Check size={12} strokeWidth={3} />מאושר לביצוע</Chip>}
          <span className="ms-auto flex items-center gap-2">
            {e.event_number && <span className="text-[12px] tabular-nums text-ink-tertiary">#{e.event_number}</span>}
            <span className="lab-chip" style={{ background: tint(e.statuses?.color ?? '#888', 15), color: 'var(--vl-text)' }}><span className="lab-dot" style={{ background: e.statuses?.color }} />{e.statuses?.name}</span>
          </span>
        </div>
        <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-[12.5px] text-ink-secondary">
          {c && <span className="inline-flex items-center gap-1.5 font-semibold"><span className="lab-dot" style={{ background: c.color }} />{c.name}</span>}
          {e.location_text && <span className="inline-flex items-center gap-1"><MapPin size={13} />{e.location_text}</span>}
          {e.truck_count != null && <span className="inline-flex items-center gap-1"><Truck size={13} />{e.truck_count} משאיות</span>}
          {e.volume_m != null && <span className="inline-flex items-center gap-1"><PackageCheck size={13} />נפח {e.volume_m}</span>}
        </div>
        {(addons.length > 0 || e.notes) && (
          <div className="flex flex-wrap items-center gap-1.5">
            {addons.map((a) => <Chip key={a} tone="brand">{a}</Chip>)}
            {e.notes && <span className="inline-flex min-w-0 items-center gap-1 truncate text-[12px] text-ink-tertiary"><StickyNote size={12} />{e.notes}</span>}
          </div>
        )}
      </div>
    </button>
  )
}

function Inspector({ e, tasks, onOpen }: { e: LabEvent; tasks: WorkBoardRow[]; onOpen: () => void }) {
  const color = e.customers?.color ?? '#64748b'
  const rows: [string, React.ReactNode][] = [
    ['לקוח במערכת', e.customers?.name], ['מספר אירוע', e.event_number], ['מיקום', e.location_text], ['הערות למיקום', e.location_notes],
    ['נפח במטר', e.volume_m], ['כמות משאיות', e.truck_count], ['הערות', e.notes],
  ]
  return (
    <div className="lab-card lab-scroll flex h-full flex-col overflow-auto">
      <div className="shrink-0 p-5 pb-4" style={{ background: `linear-gradient(160deg, ${tint(color, 20)}, var(--vl-surface) 75%)` }}>
        <div className="flex items-center gap-1.5 text-[12px] font-semibold text-ink-secondary"><span className="lab-dot" style={{ background: color }} />{e.customers?.name}</div>
        <h2 className="mt-1 text-[22px] font-extrabold leading-tight tracking-tight">{e.end_client_name}</h2>
        <div className="mt-1 text-[12.5px] text-ink-secondary">{parse(e.event_date).toLocaleDateString('he-IL', { weekday: 'long', day: 'numeric', month: 'long' })}</div>
        <div className="mt-3 flex flex-wrap gap-1.5">
          <span className="lab-chip" style={{ background: tint(e.statuses?.color ?? '#888', 16), color: 'var(--vl-text)' }}><span className="lab-dot" style={{ background: e.statuses?.color }} />{e.statuses?.name}</span>
          {e.approved_at && <Chip tone="good"><Check size={12} strokeWidth={3} />מאושר לביצוע</Chip>}
        </div>
      </div>
      <div className="flex shrink-0 flex-col gap-5 p-5 pt-3">
        <dl className="flex flex-col divide-y divide-[var(--vl-border-subtle)]">
          {rows.filter(([, v]) => v != null && v !== '').map(([k, v]) => (
            <div key={k} className="flex items-start justify-between gap-4 py-2 text-[13px]"><dt className="text-ink-tertiary">{k}</dt><dd className="text-end font-semibold">{v}</dd></div>
          ))}
        </dl>
        <div>
          <div className="lab-eyebrow mb-2">משימות האירוע · {tasks.length}</div>
          <div className="flex flex-col gap-2">
            {tasks.map((t) => (
              <div key={t.id} className="rounded-xl bg-[var(--vl-subtle)] p-3">
                <div className="flex items-center justify-between gap-2"><b className="text-[13.5px]">{t.task_type_name}</b><span className="lab-chip" style={{ background: tint(t.status_color, 16), color: 'var(--vl-text)' }}><span className="lab-dot" style={{ background: t.status_color }} />{t.status_name}</span></div>
                <div className="mt-1 text-[12.5px] text-ink-secondary"><Rng a={hm(t.onsite_start_time)} b={hm(t.onsite_end_time)} />{t.hours_count != null && <span className="text-ink-tertiary"> · {t.hours_count} שעות</span>}</div>
                <div className="mt-1.5 flex flex-wrap gap-1 text-[12px]">
                  {t.team_lead_name && <span className="rounded bg-[var(--vl-surface)] px-1.5 py-px">ר״צ: {t.team_lead_name}</span>}
                  {crewPeople(t).map((p) => <span key={p.key} className="rounded bg-[var(--vl-surface)] px-1.5 py-px text-ink-secondary">{p.name}</span>)}
                  <span className="text-ink-tertiary">{crewSize(t)}/{t.worker_count} עובדים</span>
                </div>
              </div>
            ))}
          </div>
        </div>
        <button onClick={onOpen} className="bg-primary rounded-xl py-2.5 text-[13px] font-bold text-white">פתח את דף האירוע</button>
      </div>
    </div>
  )
}
export { fmtDM }
