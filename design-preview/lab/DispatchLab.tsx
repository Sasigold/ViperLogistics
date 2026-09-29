// לו״ז עבודה — אותם שדות כמו הטבלה של היום (לקוח, מס' אירוע, מיקום, סוג משימה, זמנים, משך, עובדים, משאית, אופן ביצוע, ראש צוות, צוות, קבלן, סטטוס, הערות),
// בסידור של ציר זמן לפי משאית + כרטיסי משימה מקובצים לפי נושא.
import { useMemo, useState } from 'react'
import { ChevronLeft, ChevronRight } from 'lucide-react'
import { addDays, fmtDM, hm, HE_DAYS, mins, parse, TODAY, useTasks, weekStart } from './data'
import { crewLead, crewPeople, crewSize } from '../../src/features/tasks/crew'
import type { WorkBoardRow } from '../../src/types/domain'
import { Chip, Rng, cx, tint } from './ui'

const H0 = 4, H1 = 24
const pct = (m: number) => ((m - H0 * 60) / ((H1 - H0) * 60)) * 100

export function DispatchLab({ onOpen }: { onOpen: (id: string) => void }) {
  const [day, setDay] = useState(TODAY)
  const [sel, setSel] = useState<string | null>(null)
  const ws = weekStart(day)
  const { data: week = [] } = useTasks(ws, addDays(ws, 6))
  const tasks = useMemo(() => week.filter((t) => t.task_date === day && !t.event_is_cancelled).sort((a, b) => (mins(a.onsite_start_time) ?? 0) - (mins(b.onsite_start_time) ?? 0)), [week, day])
  const visible = week.filter((t) => !t.event_is_cancelled)

  const lanes = useMemo(() => {
    const m = new Map<string, { name: string; rows: WorkBoardRow[]; sub: Map<string, number>; depth: number }>()
    tasks.forEach((t) => {
      const k = t.truck_id ?? '—'
      if (!m.has(k)) m.set(k, { name: t.truck_name ?? 'ללא משאית', rows: [], sub: new Map(), depth: 1 })
      m.get(k)!.rows.push(t)
    })
    m.forEach((l) => {
      const ends: number[] = []
      ;[...l.rows].sort((x, y) => (mins(x.warehouse_start_time ?? x.onsite_start_time) ?? 0) - (mins(y.warehouse_start_time ?? y.onsite_start_time) ?? 0)).forEach((t) => {
        const a = mins(t.warehouse_start_time ?? t.onsite_start_time) ?? 0
        let r = ends.findIndex((e) => e <= a)
        if (r < 0) { r = ends.length; ends.push(0) }
        ends[r] = mins(t.onsite_end_time) ?? a
        l.sub.set(t.id, r)
      })
      l.depth = Math.max(1, ends.length)
    })
    return [...m.entries()].sort((a, b) => (a[0] === '—' ? 1 : b[0] === '—' ? -1 : a[1].name.localeCompare(b[1].name)))
  }, [tasks])

  const now = new Date()
  const nowM = day === TODAY ? now.getHours() * 60 + now.getMinutes() : null
  const selId = sel ?? null
  const events = new Set(visible.map((t) => t.event_id)).size
  const days = new Set(visible.map((t) => t.task_date)).size

  return (
    <div className="mx-auto flex max-w-[1600px] flex-col gap-4 p-5">
      <div className="flex flex-wrap items-end gap-4">
        <div>
          <div className="lab-eyebrow">לו״ז עבודה</div>
          <h1 className="text-[28px] font-extrabold leading-tight tracking-tight">{parse(day).toLocaleDateString('he-IL', { weekday: 'long', day: 'numeric', month: 'long' })}{day === TODAY && <Chip tone="brand" className="ms-3 align-middle">היום</Chip>}</h1>
          <div className="mt-1 flex gap-2 text-[12px]"><Chip>{visible.length} משימות</Chip><Chip>{days} ימי עבודה</Chip><Chip>{events} אירועים</Chip><span className="self-center text-ink-tertiary">בשבוע המוצג</span></div>
        </div>
        <div className="ms-auto flex items-center gap-1.5">
          <button className="rounded-lg p-2 hover:bg-[var(--vl-subtle)]" onClick={() => setDay(addDays(day, 7))}><ChevronRight size={16} /></button>
          {Array.from({ length: 7 }, (_, i) => addDays(ws, i)).map((d) => {
            const n = week.filter((t) => t.task_date === d && !t.event_is_cancelled).length
            return (
              <button key={d} onClick={() => setDay(d)} className={cx('flex w-[58px] flex-col items-center rounded-2xl py-1.5 transition', d === day ? 'text-white shadow-[0_8px_18px_-8px_var(--nova-a)]' : 'bg-[var(--vl-subtle)] hover:bg-[var(--vl-inset)]')} style={d === day ? { background: 'var(--nova-grad)' } : undefined}>
                <span className={cx('text-[10.5px] font-bold', d !== day && 'text-ink-tertiary')}>{HE_DAYS[parse(d).getDay()]}</span>
                <span className="text-[17px] font-extrabold leading-tight">{parse(d).getDate()}</span>
                <span className={cx('text-[10.5px] tabular-nums', d !== day && 'text-ink-tertiary')}>{n || '·'}</span>
              </button>
            )
          })}
          <button className="rounded-lg p-2 hover:bg-[var(--vl-subtle)]" onClick={() => setDay(addDays(day, -7))}><ChevronLeft size={16} /></button>
        </div>
      </div>

      {tasks.length === 0 && <div className="lab-card p-10 text-center text-ink-tertiary">אין משימות ביום הזה</div>}

      {tasks.length > 0 && (
        <div className="lab-card overflow-hidden">
          <div className="flex items-center justify-between border-b border-[var(--vl-border-subtle)] px-5 py-3">
            <div className="text-[15px] font-extrabold">מי נוסע ומתי <span className="ms-1 text-[12px] font-medium text-ink-tertiary">— שורה לכל משאית</span></div>
            <div className="flex items-center gap-3 text-[11.5px] text-ink-tertiary">
              <span className="inline-flex items-center gap-1.5"><span className="h-2 w-5 rounded-sm bg-[var(--vl-border-strong)]" />התחלה במחסן</span>
              <span className="inline-flex items-center gap-1.5"><span className="h-2 w-5 rounded-sm bg-[var(--nova-a)]" />בשטח</span>
            </div>
          </div>
          <div className="lab-scroll overflow-x-auto">
            <div className="flex min-w-[980px]">
              <div className="sticky start-0 z-20 w-[176px] shrink-0 border-e border-[var(--vl-border-subtle)] bg-[var(--vl-surface)]">
                <div className="h-9" />
                {lanes.map(([k, l]) => (
                  <div key={k} style={{ height: l.depth * 68 + 8 }} className="flex items-center gap-2 border-t border-[var(--vl-border-subtle)] px-4">
                    <div className="min-w-0"><div className="truncate text-[13px] font-bold leading-tight">{l.name}</div><div className="text-[11px] text-ink-tertiary">{l.rows.length} משימות</div></div>
                  </div>
                ))}
              </div>
              <div className="relative min-w-0 flex-1">
                <div className="relative h-9">
                  {Array.from({ length: H1 - H0 }, (_, i) => H0 + i).filter((h) => h % 2 === 0).map((h) => (
                    <span key={h} className="absolute top-2.5 text-[11px] font-semibold tabular-nums text-ink-tertiary" style={{ insetInlineStart: `${pct(h * 60)}%`, transform: 'translateX(50%)' }}>{String(h).padStart(2, '0')}:00</span>
                  ))}
                </div>
                {lanes.map(([k, l]) => (
                  <div key={k} className="relative border-t border-[var(--vl-border-subtle)]" style={{ height: l.depth * 68 + 8, backgroundImage: 'repeating-linear-gradient(to left, transparent 0, transparent calc(100%/10 - 1px), var(--vl-border-subtle) calc(100%/10 - 1px), var(--vl-border-subtle) calc(100%/10))' }}>
                    {l.rows.map((t) => {
                      const w = mins(t.warehouse_start_time), a = mins(t.onsite_start_time), b = mins(t.onsite_end_time)
                      if (a == null || b == null) return null
                      const c = t.customer_color ?? '#5b5bf0'
                      const top = 8 + (l.sub.get(t.id) ?? 0) * 68
                      return (
                        <div key={t.id}>
                          {w != null && w < a && <div className="absolute h-2.5 rounded-sm bg-[var(--vl-border-strong)] opacity-70" style={{ top: top + 25, insetInlineStart: `${pct(w)}%`, width: `${pct(a) - pct(w)}%` }} />}
                          <button onClick={() => setSel(t.id)} className={cx('lab-hoverable absolute flex h-[60px] flex-col justify-center overflow-hidden rounded-xl px-3 text-start', selId === t.id && 'lab-sel')}
                            style={{ top, insetInlineStart: `${pct(a)}%`, width: `${pct(b) - pct(a)}%`, background: tint(c, 22), boxShadow: `inset 0 0 0 1px ${tint(c, 45)}, inset 3px 0 0 ${c}` }}>
                            <span className="truncate text-[12.5px] font-extrabold leading-tight">{t.end_client_name}</span>
                            <span className="flex items-center gap-1.5 truncate text-[11px] text-ink-secondary"><Rng a={hm(t.onsite_start_time)} b={hm(t.onsite_end_time)} /><span>· {t.task_type_name}</span></span>
                            <span className="truncate text-[11px] text-ink-secondary">{t.customer_name}</span>
                          </button>
                        </div>
                      )
                    })}
                  </div>
                ))}
                {nowM != null && nowM >= H0 * 60 && nowM <= H1 * 60 && (
                  <div className="pointer-events-none absolute inset-y-0 z-10 w-px bg-[var(--vl-error)]" style={{ insetInlineStart: `${pct(nowM)}%` }}>
                    <span className="absolute top-0 -translate-x-1/2 rounded-md bg-[var(--vl-error)] px-1.5 py-0.5 text-[10px] font-bold text-white">{String(now.getHours()).padStart(2, '0')}:{String(now.getMinutes()).padStart(2, '0')}</span>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* כרטיסי משימה: כל שדות הלו״ז, מקובצים */}
      <div className="grid gap-4 md:grid-cols-2 2xl:grid-cols-3">
        {tasks.map((t) => <TaskCard key={t.id} t={t} selected={selId === t.id} onSelect={() => setSel(t.id)} onOpen={() => t.event_id && onOpen(t.event_id)} />)}
      </div>
    </div>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  if (children == null || children === '' || children === false) return null
  return <div className="min-w-0"><div className="text-[11px] text-ink-tertiary">{label}</div><div className="truncate text-[13px] font-semibold">{children}</div></div>
}

function TaskCard({ t, selected, onSelect, onOpen }: { t: WorkBoardRow; selected: boolean; onSelect: () => void; onOpen: () => void }) {
  const c = t.customer_color ?? '#5b5bf0'
  const w = mins(t.warehouse_start_time), a = mins(t.onsite_start_time), b = mins(t.onsite_end_time)
  const people = crewPeople(t), lead = crewLead(t)
  return (
    <div onClick={onSelect} className={cx('lab-card overflow-hidden p-0', selected && 'lab-sel')}>
      <div className="flex items-start gap-3 px-5 pb-3 pt-4" style={{ background: `linear-gradient(180deg, ${tint(c, 12)}, transparent)` }}>
        <span className="mt-1 h-10 w-1.5 shrink-0 rounded-full" style={{ background: c }} />
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2 text-[12px] font-semibold text-ink-secondary"><span>{t.customer_name}</span>{t.event_number && <span className="tabular-nums text-ink-tertiary">· אירוע #{t.event_number}</span>}</div>
          <button onClick={(e) => { e.stopPropagation(); onOpen() }} className="block max-w-full truncate text-start text-[18px] font-extrabold tracking-tight hover:underline">{t.end_client_name ?? t.title}</button>
          <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
            <Chip tone={t.task_type_code === 'teardown' ? 'warn' : 'brand'}>{t.task_type_name}</Chip>
            <span className="lab-chip" style={{ background: tint(t.status_color, 16), color: 'var(--vl-text)' }}><span className="lab-dot" style={{ background: t.status_color }} />{t.status_name}</span>
          </div>
        </div>
      </div>

      {/* זמנים: שלוש נקודות על ציר קטן */}
      <div className="px-5 pb-3">
        <div className="grid grid-cols-3 gap-2 text-center">
          <div className="rounded-xl bg-[var(--vl-subtle)] py-2"><div className="text-[11px] text-ink-tertiary">התחלה במחסן</div><div className="text-[16px] font-extrabold tabular-nums">{hm(t.warehouse_start_time)}</div></div>
          <div className="rounded-xl py-2" style={{ background: tint(c, 16) }}><div className="text-[11px] text-ink-secondary">התחלה בשטח</div><div className="text-[16px] font-extrabold tabular-nums">{hm(t.onsite_start_time)}</div></div>
          <div className="rounded-xl bg-[var(--vl-subtle)] py-2"><div className="text-[11px] text-ink-tertiary">סיום בשטח</div><div className="text-[16px] font-extrabold tabular-nums">{hm(t.onsite_end_time)}</div></div>
        </div>
        {a != null && b != null && (
          <div className="relative mt-2.5 h-1.5 rounded-full bg-[var(--vl-subtle)]">
            {w != null && w < a && <span className="absolute inset-y-0 rounded-full bg-[var(--vl-border-strong)]" style={{ insetInlineStart: `${pct(w)}%`, width: `${pct(a) - pct(w)}%` }} />}
            <span className="absolute inset-y-0 rounded-full" style={{ background: c, insetInlineStart: `${pct(a)}%`, width: `${pct(b) - pct(a)}%` }} />
          </div>
        )}
        {t.hours_count != null && <div className="mt-1.5 text-[12px] text-ink-tertiary">משך {t.hours_count} שעות</div>}
      </div>

      <div className="grid grid-cols-2 gap-x-4 gap-y-3 border-t border-[var(--vl-border-subtle)] px-5 py-3.5">
        <Field label="מיקום">{t.location_text}</Field>
        <Field label="משאית">{t.truck_name}</Field>
        <Field label="נפח">{t.volume_m}</Field>
        <Field label="משאיות באירוע">{t.event_truck_count}</Field>
        <Field label="אופן ביצוע">{t.execution_method_name}</Field>
        <Field label="קבלן">{t.contractor_name}</Field>
        <Field label="עובדים להביא">{t.contractor_worker_count}</Field>
      </div>

      <div className="border-t border-[var(--vl-border-subtle)] px-5 py-3.5">
        <div className="mb-2 flex items-center justify-between"><span className="text-[11px] font-bold tracking-wide text-ink-tertiary">צוות</span><span className="text-[12px] tabular-nums text-ink-tertiary">{crewSize(t)}/{t.worker_count} עובדים</span></div>
        {lead || people.length ? (
          <div className="flex flex-wrap gap-1.5">
            {lead && <span className="rounded-lg bg-[var(--vl-warning-subtle)] px-2 py-0.5 text-[12.5px] font-bold text-[var(--vl-warning-text)]">ר״צ · {lead.name}</span>}
            {people.map((p) => <span key={p.key} className="rounded-lg bg-[var(--vl-subtle)] px-2 py-0.5 text-[12.5px]">{p.name}{p.truck ? ` · ${p.truck}` : ''}</span>)}
          </div>
        ) : <span className="text-[13px] text-ink-tertiary">לא שובצו עובדים</span>}
      </div>

      {(t.notes || t.supplier_pickup) && (
        <div className="flex flex-col gap-1.5 border-t border-[var(--vl-border-subtle)] px-5 py-3.5 text-[12.5px]">
          {t.supplier_pickup && <div className="w-fit rounded-lg bg-[var(--vl-warning-subtle)] px-2 py-0.5 font-semibold text-[var(--vl-warning-text)]">איסוף מספקים{t.supplier_names?.length ? `: ${t.supplier_names.join(', ')}` : ''}</div>}
          {t.notes && <div className="text-ink-secondary">{t.notes}</div>}
        </div>
      )}
    </div>
  )
}
export { fmtDM }
