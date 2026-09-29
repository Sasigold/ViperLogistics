import { useMemo, useState } from 'react'
import { AlertTriangle, ArrowUpLeft, CalendarCheck2, ChevronLeft, ChevronRight, MapPin, PackageCheck, Truck, Users, Clock3 } from 'lucide-react'
import { addDays, dayLabel, hm, iso, mins, parse, taskHealth, TODAY, useEvents, useTasks, weekStart, HE_DAYS, money } from './data'
import type { LabEvent } from './data'
import type { WorkBoardRow } from '../../src/types/domain'
import { AvatarStack, Chip, Ring, Rng, Seg, cx, tint } from './ui'

const STEPS = [
  { code: 'new', label: 'חדש' },
  { code: 'approved', label: 'מאושר' },
  { code: 'in_progress', label: 'בביצוע' },
  { code: 'done', label: 'הושלם' },
]

export function Stepper({ code }: { code: string }) {
  const idx = Math.max(0, STEPS.findIndex((s) => s.code === code))
  const cancelled = code === 'cancelled'
  return (
    <div className="flex items-center gap-1">
      {STEPS.map((s, i) => (
        <div key={s.code} className="flex flex-1 flex-col gap-1">
          <span className="h-1.5 rounded-full" style={{ background: !cancelled && i <= idx ? 'var(--nova-grad)' : 'var(--vl-border)' }} />
          <span className={cx('text-[11px] font-semibold', !cancelled && i === idx ? 'text-ink' : 'text-ink-tertiary')}>{s.label}</span>
        </div>
      ))}
    </div>
  )
}

function summarize(tasks: WorkBoardRow[]) {
  const hs = tasks.map(taskHealth)
  const need = hs.reduce((a, h) => a + h.need, 0), have = hs.reduce((a, h) => a + Math.min(h.have, h.need), 0)
  const starts = tasks.map((t) => mins(t.warehouse_start_time ?? t.onsite_start_time)).filter((x): x is number => x != null)
  const ends = tasks.map((t) => mins(t.onsite_end_time)).filter((x): x is number => x != null)
  const flags = hs.flatMap((h) => h.flags)
  const t = (m: number) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`
  return { need, have, from: starts.length ? t(Math.min(...starts)) : null, to: ends.length ? t(Math.max(...ends)) : null, flags, ok: flags.length === 0 && tasks.length > 0 }
}

export function CalendarLab({ onOpen, initialSel }: { onOpen: (id: string) => void; initialSel?: string | null }) {
  const [anchor, setAnchor] = useState(TODAY)
  const [scope, setScope] = useState<'week' | 'day'>('week')
  const [sel, setSel] = useState<string | null>(initialSel ?? null)
  const [statusF, setStatusF] = useState<string | null>(null)
  const from = scope === 'week' ? weekStart(anchor) : anchor
  const to = scope === 'week' ? addDays(from, 6) : anchor
  const { data: events = [] } = useEvents(from, to)
  const { data: tasks = [] } = useTasks(from, to)

  const visible = events.filter((e) => e.statuses?.code !== 'cancelled' && (!statusF || e.statuses?.code === statusF))
  const tasksBy = useMemo(() => {
    const m = new Map<string, WorkBoardRow[]>()
    tasks.forEach((t) => t.event_id && m.set(t.event_id, [...(m.get(t.event_id) ?? []), t]))
    return m
  }, [tasks])
  const days = Array.from({ length: scope === 'week' ? 7 : 1 }, (_, i) => addDays(from, i))
  const selected = visible.find((e) => e.id === sel) ?? null

  const all = visible.map((e) => summarize(tasksBy.get(e.id) ?? []))
  const attention = all.filter((s) => s.flags.length).length
  const crewNeed = all.reduce((a, s) => a + s.need, 0), crewHave = all.reduce((a, s) => a + s.have, 0)
  const trucks = new Set(tasks.filter((t) => t.truck_id && visible.some((e) => e.id === t.event_id)).map((t) => t.truck_id)).size
  const statusCounts = ['new', 'approved', 'in_progress', 'done'].map((c) => ({ c, n: events.filter((e) => e.statuses?.code === c).length }))
  const fromD = parse(from), toD = parse(to)

  return (
    <div className="mx-auto flex max-w-[1600px] flex-col gap-4 p-5">
      {/* כותרת + ניווט */}
      <div className="flex flex-wrap items-end gap-4">
        <div>
          <div className="lab-eyebrow">לוח אירועים</div>
          <h1 className="text-[28px] font-extrabold leading-tight tracking-tight">
            {scope === 'week' ? `${fromD.getDate()} ${fromD.toLocaleDateString('he-IL', { month: 'short' })} – ${toD.getDate()} ${toD.toLocaleDateString('he-IL', { month: 'short' })}` : dayLabel(anchor)}
            <span className="ms-3 text-[20px] text-ink-tertiary">{toD.getFullYear()}</span>
          </h1>
        </div>
        <div className="ms-auto flex items-center gap-2">
          <Seg value={scope} onChange={setScope} options={[{ v: 'day', label: 'יום' }, { v: 'week', label: 'שבוע' }]} />
          <div className="flex overflow-hidden rounded-xl bg-[var(--vl-subtle)] shadow-[inset_0_0_0_1px_var(--vl-border-subtle)]">
            <button className="px-2.5 py-1.5" onClick={() => setAnchor(addDays(anchor, scope === 'week' ? 7 : 1))}><ChevronRight size={16} /></button>
            <button className="border-x border-[var(--vl-border-subtle)] px-3 text-[13px] font-semibold" onClick={() => setAnchor(TODAY)}>היום</button>
            <button className="px-2.5 py-1.5" onClick={() => setAnchor(addDays(anchor, scope === 'week' ? -7 : -1))}><ChevronLeft size={16} /></button>
          </div>
          <button className="bg-primary rounded-xl px-4 py-2 text-[13px] font-bold text-white">+ אירוע חדש</button>
        </div>
      </div>

      {/* סיכום מהיר — מה קורה בטווח, במבט אחד */}
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {[
          { icon: CalendarCheck2, label: 'אירועים בטווח', value: visible.length, sub: `${tasks.length} משימות`, tone: 'var(--nova-a)' },
          { icon: AlertTriangle, label: 'דורשים טיפול', value: attention, sub: attention ? 'חסר צוות / משאית / ראש צוות' : 'הכול מוכן', tone: attention ? 'var(--vl-error)' : 'var(--vl-success)' },
          { icon: Users, label: 'איוש צוותים', value: `${crewHave}/${crewNeed}`, sub: crewNeed ? `${Math.round((crewHave / crewNeed) * 100)}% מהנדרש` : '—', tone: 'var(--vl-warning)' },
          { icon: Truck, label: 'משאיות בשימוש', value: trucks, sub: 'מתוך 3 בצי', tone: '#0c7ba6' },
        ].map((k) => (
          <div key={k.label} className="lab-card flex items-center gap-3 p-4">
            <span className="flex size-11 items-center justify-center rounded-2xl" style={{ background: tint(k.tone, 13), color: k.tone }}><k.icon size={20} /></span>
            <div className="min-w-0">
              <div className="text-[12px] font-semibold text-ink-tertiary">{k.label}</div>
              <div className="text-[26px] font-extrabold leading-none tracking-tight">{k.value}</div>
              <div className="mt-1 truncate text-[11.5px] text-ink-tertiary">{k.sub}</div>
            </div>
          </div>
        ))}
      </div>

      <div className="grid gap-4 xl:grid-cols-[minmax(0,1fr)_400px]">
        {/* אג'נדה לפי יום */}
        <div className="flex min-w-0 flex-col gap-3">
          <div className="flex flex-wrap items-center gap-2">
            <button onClick={() => setStatusF(null)} className={cx('lab-chip', !statusF ? 'bg-ink text-[var(--vl-surface)]' : 'bg-[var(--vl-subtle)] text-ink-secondary')}>הכול · {events.filter((e) => e.statuses?.code !== 'cancelled').length}</button>
            {statusCounts.map(({ c, n }) => {
              const s = events.find((e) => e.statuses?.code === c)?.statuses
              return s ? (
                <button key={c} onClick={() => setStatusF(statusF === c ? null : c)} className={cx('lab-chip', statusF === c ? 'ring-2 ring-[var(--nova-a)]' : '')} style={{ background: tint(s.color, 14), color: 'var(--vl-text)' }}>
                  <span className="lab-dot" style={{ background: s.color }} />{s.name} · {n}
                </button>
              ) : null
            })}
          </div>

          {days.map((d) => {
            const list = visible.filter((e) => e.event_date === d)
            const isToday = d === TODAY
            const dt = list.flatMap((e) => tasksBy.get(e.id) ?? [])
            return (
              <section key={d} className="flex gap-2 sm:gap-4">
                {/* עמוד התאריך */}
                <div className="sticky top-2 flex h-fit w-[46px] sm:w-[64px] shrink-0 flex-col items-center gap-0.5 pt-1">
                  <span className="text-[11px] font-bold text-ink-tertiary">{HE_DAYS[parse(d).getDay()]}</span>
                  <span className={cx('flex size-11 items-center justify-center rounded-2xl text-[20px] font-extrabold', isToday ? 'text-white shadow-[0_8px_18px_-6px_var(--nova-a)]' : 'bg-[var(--vl-subtle)]')} style={isToday ? { background: 'var(--nova-grad)' } : undefined}>{parse(d).getDate()}</span>
                  {isToday && <span className="text-[10px] font-bold text-[var(--nova-a)]">היום</span>}
                  {list.length > 0 && <span className="mt-1 text-[11px] text-ink-tertiary">{list.length} אירועים</span>}
                </div>
                <div className="flex min-w-0 flex-1 flex-col gap-2.5 border-s border-[var(--vl-border-subtle)] ps-4 pb-3">
                  {list.length === 0 && <div className="rounded-xl border border-dashed border-[var(--vl-border)] px-4 py-3 text-[13px] text-ink-tertiary">אין אירועים ביום הזה</div>}
                  {list.map((e) => <EventCard key={e.id} e={e} tasks={tasksBy.get(e.id) ?? []} selected={sel === e.id} onSelect={() => setSel(e.id)} />)}
                  {dt.length > 0 && list.length > 1 && (
                    <div className="text-[11.5px] text-ink-tertiary">סה״כ ביום: {dt.length} משימות · {dt.reduce((a, t) => a + t.worker_count, 0)} עובדים נדרשים</div>
                  )}
                </div>
              </section>
            )
          })}
        </div>

        {/* חלונית פרטים — מבינים אירוע בלי לעזוב את הלוח */}
        <div className="xl:sticky xl:top-2 xl:h-[calc(100vh-190px)]">
          {selected ? <Inspector e={selected} tasks={tasksBy.get(selected.id) ?? []} onOpen={() => onOpen(selected.id)} /> : (
            <div className="lab-card flex h-full min-h-[300px] flex-col items-center justify-center gap-2 p-8 text-center text-ink-tertiary">
              <CalendarCheck2 size={34} strokeWidth={1.4} />
              <div className="text-[15px] font-bold text-ink">בחר אירוע</div>
              <div className="text-[13px]">כל הפרטים — צוות, משאיות, לוח זמנים ומה חסר — יופיעו כאן</div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

function EventCard({ e, tasks, selected, onSelect }: { e: LabEvent; tasks: WorkBoardRow[]; selected: boolean; onSelect: () => void }) {
  const s = summarize(tasks)
  const color = e.customers?.color ?? '#64748b'
  const approved = !!e.approved_at
  return (
    <button onClick={onSelect} className={cx('lab-card lab-hoverable relative flex w-full flex-col items-stretch overflow-hidden p-0 text-start sm:flex-row sm:gap-4', selected && 'lab-sel')}>
      <span className="h-1.5 w-full shrink-0 sm:h-auto sm:w-1.5" style={{ background: e.statuses?.color }} />
      {/* עמודת זמן — המידע הכי חשוב לרכז */}
      <div className="flex shrink-0 items-baseline gap-2 px-4 pt-3 sm:w-[86px] sm:flex-col sm:justify-center sm:gap-0 sm:px-0 sm:py-3">
        <span className="text-[19px] font-extrabold leading-none tracking-tight tabular-nums">{s.from ?? '—'}</span>
        <span className="mt-1 text-[12px] text-ink-tertiary tabular-nums">עד {s.to ?? '—'}</span>
      </div>
      <div className="flex min-w-0 flex-1 flex-col justify-center gap-1.5 px-4 py-3 sm:px-0">
        <div className="flex items-center gap-2">
          <span className="lab-chip" style={{ background: tint(color, 13), color: 'var(--vl-text)' }}><span className="lab-dot" style={{ background: color }} />{e.customers?.name}</span>
          <span className="text-[12px] text-ink-tertiary">#{e.event_number}</span>
          {approved && <Chip tone="good">✓ מאושר</Chip>}
        </div>
        <div className="truncate text-[17px] font-extrabold tracking-tight">{e.end_client_name}</div>
        <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-[12.5px] text-ink-secondary">
          <span className="inline-flex items-center gap-1"><MapPin size={13} />{e.location_text}</span>
          {e.truck_count != null && <span className="inline-flex items-center gap-1"><Truck size={13} />{e.truck_count} משאיות</span>}
          {e.volume_m != null && <span className="inline-flex items-center gap-1"><PackageCheck size={13} />{e.volume_m} מ״ק</span>}
        </div>
        <div className="mt-0.5 flex flex-wrap gap-1.5">
          {tasks.map((t) => {
            const h = taskHealth(t)
            return (
              <span key={t.id} className="lab-chip" style={{ background: 'var(--vl-subtle)' }}>
                <span className="lab-dot" style={{ background: h.ready ? 'var(--vl-success)' : h.flags.some((f) => f.tone === 'bad') ? 'var(--vl-error)' : 'var(--vl-warning)' }} />
                {t.task_type_name} <b className="tabular-nums">{hm(t.onsite_start_time)}</b>
              </span>
            )
          })}
        </div>
      </div>
      {/* מוכנות: טבעת + מה חסר */}
      <div className="flex w-[100px] shrink-0 flex-col items-center justify-center gap-1.5 border-s sm:w-[150px] border-[var(--vl-border-subtle)] px-3">
        <Ring value={s.have} max={s.need} size={50} color={s.ok ? 'var(--vl-success)' : s.have < s.need ? 'var(--vl-error)' : 'var(--vl-warning)'}>{s.have}/{s.need}</Ring>
        {s.flags.length === 0 ? <span className="text-[11.5px] font-bold text-[var(--vl-success-text)]">מוכן לביצוע</span>
          : <span className="text-center text-[11.5px] font-bold leading-tight text-[var(--vl-error-text)]">{s.flags[0].label}{s.flags.length > 1 && <span className="text-ink-tertiary"> +{s.flags.length - 1}</span>}</span>}
      </div>
    </button>
  )
}

function Inspector({ e, tasks, onOpen }: { e: LabEvent; tasks: WorkBoardRow[]; onOpen: () => void }) {
  const color = e.customers?.color ?? '#64748b'
  const s = summarize(tasks)
  const total = tasks.reduce((a, t) => a + (t.customer_price ?? 0), 0)
  return (
    <div className="lab-card lab-scroll flex h-full flex-col overflow-auto">
      <div className="relative shrink-0 overflow-hidden p-5 pb-4" style={{ background: `linear-gradient(160deg, ${tint(color, 20)}, var(--vl-surface) 70%)` }}>
        <div className="flex items-center gap-2 text-[12px] font-semibold text-ink-secondary"><span className="lab-dot" style={{ background: color }} />{e.customers?.name} · #{e.event_number}</div>
        <h2 className="mt-1 text-[24px] font-extrabold leading-tight tracking-tight">{e.end_client_name}</h2>
        <div className="mt-1 flex items-center gap-1.5 text-[13px] text-ink-secondary"><MapPin size={14} />{e.location_text}</div>
        <div className="mt-4"><Stepper code={e.statuses?.code ?? 'new'} /></div>
      </div>

      <div className="flex shrink-0 flex-col gap-5 p-5 pt-3">
        {s.flags.length > 0 && (
          <div className="rounded-2xl border border-[var(--vl-error-border)] bg-[var(--vl-error-subtle)] p-3">
            <div className="mb-1.5 flex items-center gap-1.5 text-[12.5px] font-extrabold text-[var(--vl-error-text)]"><AlertTriangle size={14} />צריך לטפל לפני האירוע</div>
            <ul className="flex flex-col gap-1 text-[12.5px] text-[var(--vl-error-text)]">{[...new Set(s.flags.map((f) => f.label))].map((l) => <li key={l}>• {l}</li>)}</ul>
          </div>
        )}

        <div>
          <div className="lab-eyebrow mb-3">מהלך האירוע</div>
          <ol className="relative flex flex-col gap-4 ps-6 before:absolute before:inset-y-1 before:start-[7px] before:w-px before:bg-[var(--vl-border)]">
            {tasks.map((t) => {
              const h = taskHealth(t)
              const people = [t.team_lead_name, ...(t.workers ?? []).map((w) => w.name), ...(t.drivers ?? []).map((w) => w.name)].filter(Boolean) as string[]
              return (
                <li key={t.id} className="relative">
                  <span className="absolute -start-6 top-1 size-[15px] rounded-full border-[3px] border-[var(--vl-surface)]" style={{ background: h.ready ? 'var(--vl-success)' : 'var(--vl-warning)', boxShadow: '0 0 0 1px var(--vl-border)' }} />
                  <div className="flex items-baseline justify-between gap-2">
                    <span className="text-[14px] font-extrabold">{t.task_type_name}</span>
                    <Rng className="text-[12.5px] font-bold text-ink-secondary" a={hm(t.onsite_start_time)} b={hm(t.onsite_end_time)} />
                  </div>
                  <div className="mt-0.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-[12px] text-ink-tertiary">
                    <span className="inline-flex items-center gap-1"><Clock3 size={12} />יציאה מהמחסן {hm(t.warehouse_start_time)}</span>
                    <span className="inline-flex items-center gap-1"><Truck size={12} />{t.truck_name ?? <b className="text-[var(--vl-warning-text)]">אין משאית</b>}</span>
                  </div>
                  <div className="mt-2 flex items-center gap-2">
                    {people.length ? <AvatarStack names={people} max={5} size={26} /> : <span className="text-[12px] text-ink-tertiary">לא שובצו אנשים</span>}
                    <Chip tone={h.have >= h.need ? 'good' : 'bad'}>{h.have}/{h.need} עובדים</Chip>
                  </div>
                  {t.team_lead_name && <div className="mt-1 text-[12px] text-ink-secondary">ראש צוות: <b>{t.team_lead_name}</b></div>}
                </li>
              )
            })}
          </ol>
        </div>

        <div className="grid grid-cols-2 gap-2 text-[12.5px]">
          {[['חיוב ללקוח', money(total)], ['נפח', e.volume_m ? `${e.volume_m} מ״ק` : '—'], ['משאיות', e.truck_count ?? '—'], ['הערות מיקום', e.location_notes ?? '—']].map(([k, v]) => (
            <div key={String(k)} className="rounded-xl bg-[var(--vl-subtle)] px-3 py-2"><div className="text-[11px] text-ink-tertiary">{k}</div><div className="font-bold leading-snug">{v}</div></div>
          ))}
        </div>
        {e.notes && <div className="rounded-xl bg-[var(--vl-warning-subtle)] px-3 py-2 text-[12.5px] text-[var(--vl-warning-text)]">📝 {e.notes}</div>}

        <div className="flex gap-2">
          <button onClick={onOpen} className="bg-primary flex flex-1 items-center justify-center gap-1.5 rounded-xl py-2.5 text-[13px] font-bold text-white">פתח את דף האירוע <ArrowUpLeft size={15} /></button>
          <button className="rounded-xl bg-[var(--vl-subtle)] px-4 text-[13px] font-semibold">עריכה</button>
        </div>
      </div>
    </div>
  )
}
