import { useMemo, useState } from 'react'
import { AlertTriangle, ChevronLeft, ChevronRight, MapPin, Truck, Users } from 'lucide-react'
import { addDays, dayLabel, hm, HE_DAYS, mins, parse, taskHealth, TODAY, useTasks, weekStart } from './data'
import type { WorkBoardRow } from '../../src/types/domain'
import { AvatarStack, Chip, Ring, Rng, cx, tint } from './ui'

const H0 = 4, H1 = 24 // טווח השעות שמוצג

export function DispatchLab({ onOpen }: { onOpen: (id: string) => void }) {
  const [day, setDay] = useState(TODAY)
  const [sel, setSel] = useState<string | null>(null)
  const ws = weekStart(day)
  const { data: week = [] } = useTasks(ws, addDays(ws, 6))
  const tasks = useMemo(() => week.filter((t) => t.task_date === day && !t.event_is_cancelled), [week, day])

  const lanes = useMemo(() => {
    const m = new Map<string, { name: string; rows: WorkBoardRow[]; sub?: Map<string, number>; depth?: number }>()
    tasks.forEach((t) => {
      const k = t.truck_id ?? '—'
      if (!m.has(k)) m.set(k, { name: t.truck_name ?? 'ללא משאית', rows: [] })
      m.get(k)!.rows.push(t)
    })
    // אריזה לשורות-משנה: משימות חופפות באותה משאית לא נערמות זו על זו
    m.forEach((l) => {
      const ends: number[] = []
      l.sub = new Map()
      ;[...l.rows].sort((x, y) => (mins(x.onsite_start_time) ?? 0) - (mins(y.onsite_start_time) ?? 0)).forEach((t) => {
        const a = mins(t.warehouse_start_time ?? t.onsite_start_time) ?? 0
        let r = ends.findIndex((e) => e <= a)
        if (r < 0) { r = ends.length; ends.push(0) }
        ends[r] = mins(t.onsite_end_time) ?? a
        l.sub!.set(t.id, r)
      })
      l.depth = Math.max(1, ends.length)
    })
    return [...m.entries()].sort((a, b) => (a[0] === '—' ? 1 : b[0] === '—' ? -1 : a[1].name.localeCompare(b[1].name)))
  }, [tasks])

  const health = tasks.map(taskHealth)
  const problems = tasks.map((t, i) => ({ t, h: health[i] })).filter((x) => x.h.flags.length)
  const crewNeed = health.reduce((a, h) => a + h.need, 0), crewHave = health.reduce((a, h) => a + Math.min(h.have, h.need), 0)
  const now = new Date()
  const nowM = day === TODAY ? now.getHours() * 60 + now.getMinutes() : null
  const pct = (m: number) => ((m - H0 * 60) / ((H1 - H0) * 60)) * 100
  const selected = tasks.find((t) => t.id === sel) ?? problems[0]?.t ?? tasks[0] ?? null

  return (
    <div className="mx-auto flex max-w-[1600px] flex-col gap-4 p-5">
      <div className="flex flex-wrap items-end gap-4">
        <div>
          <div className="lab-eyebrow">לוח שיבוץ יומי</div>
          <h1 className="text-[28px] font-extrabold leading-tight tracking-tight">{dayLabel(day)}{day === TODAY && <Chip tone="brand" className="ms-3 align-middle">היום</Chip>}</h1>
        </div>
        {/* פס שבוע: כמה עומס בכל יום, ואיפה יש בעיות */}
        <div className="ms-auto flex items-center gap-1.5">
          <button className="rounded-lg p-2 hover:bg-[var(--vl-subtle)]" onClick={() => setDay(addDays(day, 7))}><ChevronRight size={16} /></button>
          {Array.from({ length: 7 }, (_, i) => addDays(ws, i)).map((d) => {
            const n = week.filter((t) => t.task_date === d)
            const bad = n.some((t) => taskHealth(t).flags.some((f) => f.tone === 'bad'))
            return (
              <button key={d} onClick={() => setDay(d)} className={cx('relative flex w-[58px] flex-col items-center rounded-2xl py-1.5 transition', d === day ? 'text-white shadow-[0_8px_18px_-8px_var(--nova-a)]' : 'bg-[var(--vl-subtle)] hover:bg-[var(--vl-inset)]')} style={d === day ? { background: 'var(--nova-grad)' } : undefined}>
                <span className={cx('text-[10.5px] font-bold', d !== day && 'text-ink-tertiary')}>{HE_DAYS[parse(d).getDay()]}</span>
                <span className="text-[17px] font-extrabold leading-tight">{parse(d).getDate()}</span>
                <span className={cx('text-[10.5px] tabular-nums', d !== day && 'text-ink-tertiary')}>{n.length || '·'}</span>
                {bad && <span className="absolute end-1.5 top-1.5 size-2 rounded-full bg-[var(--vl-error)] ring-2 ring-[var(--vl-surface)]" />}
              </button>
            )
          })}
          <button className="rounded-lg p-2 hover:bg-[var(--vl-subtle)]" onClick={() => setDay(addDays(day, -7))}><ChevronLeft size={16} /></button>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-[repeat(3,minmax(0,1fr))_minmax(0,1.6fr)]">
        {[
          { icon: Truck, label: 'משימות היום', v: tasks.length, sub: `${lanes.filter(([k]) => k !== '—').length} משאיות בפעילות`, c: 'var(--nova-a)' },
          { icon: Users, label: 'איוש', v: `${crewHave}/${crewNeed}`, sub: 'עובדים ששובצו מהנדרש', c: 'var(--vl-warning)' },
          { icon: AlertTriangle, label: 'לטיפול', v: problems.length, sub: problems.length ? 'משימות עם חוסרים' : 'אין חוסרים', c: problems.length ? 'var(--vl-error)' : 'var(--vl-success)' },
        ].map((k) => (
          <div key={k.label} className="lab-card flex items-center gap-3 p-4">
            <span className="flex size-10 items-center justify-center rounded-2xl" style={{ background: tint(k.c, 13), color: k.c }}><k.icon size={18} /></span>
            <div><div className="text-[12px] font-semibold text-ink-tertiary">{k.label}</div><div className="text-[24px] font-extrabold leading-none">{k.v}</div><div className="mt-1 text-[11.5px] text-ink-tertiary">{k.sub}</div></div>
          </div>
        ))}
        <div className="lab-card lab-scroll col-span-2 flex max-h-[104px] lg:col-span-1 flex-col gap-1 overflow-auto p-3">
          <div className="lab-eyebrow">דורש תשומת לב</div>
          {problems.length === 0 && <div className="text-[13px] text-[var(--vl-success-text)]">✓ הכול מאויש ומשובץ</div>}
          {problems.map(({ t, h }) => (
            <button key={t.id} onClick={() => setSel(t.id)} className="flex items-center gap-2 rounded-lg px-1.5 py-0.5 text-start text-[12.5px] hover:bg-[var(--vl-subtle)]">
              <span className="lab-dot" style={{ background: h.flags.some((f) => f.tone === 'bad') ? 'var(--vl-error)' : 'var(--vl-warning)' }} />
              <b className="truncate">{t.end_client_name}</b><span className="text-ink-tertiary">{t.task_type_name}</span>
              <span className="ms-auto shrink-0 text-[var(--vl-error-text)]">{h.flags[0].label}</span>
            </button>
          ))}
        </div>
      </div>

      {/* ציר זמן: נתיב לכל משאית, שעות לרוחב */}
      <div className="lab-card overflow-hidden">
        <div className="flex items-center justify-between border-b border-[var(--vl-border-subtle)] px-5 py-3">
          <div className="text-[15px] font-extrabold">ציר הזמן של היום <span className="ms-1 text-[12px] font-medium text-ink-tertiary">— נתיב לכל משאית</span></div>
          <div className="flex items-center gap-3 text-[11.5px] text-ink-tertiary">
            <span className="inline-flex items-center gap-1.5"><span className="h-2 w-5 rounded-sm bg-[var(--vl-border-strong)]" />העמסה במחסן</span>
            <span className="inline-flex items-center gap-1.5"><span className="h-2 w-5 rounded-sm bg-[var(--nova-a)]" />עבודה בשטח</span>
          </div>
        </div>
        <div className="lab-scroll overflow-x-auto"><div className="flex min-w-[980px]">
          <div className="w-[176px] shrink-0 border-e border-[var(--vl-border-subtle)]">
            <div className="h-9" />
            {lanes.map(([k, l]) => (
              <div key={k} style={{ height: (l.depth ?? 1) * 68 + 8 }} className="flex items-center gap-2.5 border-t border-[var(--vl-border-subtle)] px-4">
                <span className={cx('flex size-9 items-center justify-center rounded-xl', k === '—' ? 'bg-[var(--vl-warning-subtle)] text-[var(--vl-warning-text)]' : 'bg-[var(--vl-primary-subtle)] text-[var(--vl-primary-text)]')}><Truck size={17} /></span>
                <div className="min-w-0"><div className="truncate text-[13px] font-bold leading-tight">{l.name}</div><div className="text-[11px] text-ink-tertiary">{l.rows.length} משימות</div></div>
              </div>
            ))}
            {lanes.length === 0 && <div className="p-6 text-[13px] text-ink-tertiary">אין משימות</div>}
          </div>
          <div className="relative min-w-0 flex-1">
            <div className="relative h-9">
              {Array.from({ length: H1 - H0 + 1 }, (_, i) => H0 + i).filter((h) => h % 2 === 0 && h < 24).map((h) => (
                <span key={h} className="absolute top-2.5 text-[11px] font-semibold tabular-nums text-ink-tertiary" style={{ insetInlineStart: `${pct(h * 60)}%`, transform: 'translateX(50%)' }}>{String(h).padStart(2, '0')}:00</span>
              ))}
            </div>
            {lanes.map(([k, l]) => (
              <div key={k} className="relative border-t border-[var(--vl-border-subtle)]" style={{ height: (l.depth ?? 1) * 68 + 8, backgroundImage: 'repeating-linear-gradient(to left, transparent 0, transparent calc(100%/10 - 1px), var(--vl-border-subtle) calc(100%/10 - 1px), var(--vl-border-subtle) calc(100%/10))' }}>
                {l.rows.map((t) => {
                  const w = mins(t.warehouse_start_time), a = mins(t.onsite_start_time), b = mins(t.onsite_end_time)
                  if (a == null || b == null) return null
                  const h = taskHealth(t)
                  const c = t.customer_color ?? '#5b5bf0'
                  const bad = h.flags.some((f) => f.tone === 'bad')
                  return (
                    <div key={t.id}>
                      {w != null && w < a && <div className="absolute h-2.5 rounded-sm bg-[var(--vl-border-strong)] opacity-70" style={{ top: 8 + (l.sub?.get(t.id) ?? 0) * 68 + 25, insetInlineStart: `${pct(w)}%`, width: `${pct(a) - pct(w)}%` }} />}
                      <button onClick={() => setSel(t.id)} className={cx('lab-hoverable absolute flex h-[60px] flex-col justify-center overflow-hidden rounded-xl px-3 text-start', sel === t.id && 'lab-sel')}
                        style={{ top: 8 + (l.sub?.get(t.id) ?? 0) * 68, insetInlineStart: `${pct(a)}%`, width: `${pct(b) - pct(a)}%`, background: tint(c, 22), boxShadow: `inset 0 0 0 1px ${tint(c, 45)}, inset 3px 0 0 ${c}` }}>
                        <span className="truncate text-[12.5px] font-extrabold leading-tight">{t.end_client_name}</span>
                        <span className="flex items-center gap-1.5 truncate text-[11px] text-ink-secondary"><Rng a={hm(t.onsite_start_time)} b={hm(t.onsite_end_time)} /><span>· {t.task_type_name}</span></span>
                        <span className={cx('truncate text-[11px] font-bold', bad ? 'text-[var(--vl-error-text)]' : 'text-[var(--vl-success-text)]')}>{h.have}/{h.need} עובדים{h.flags[0] ? ` · ${h.flags[0].label}` : ''}</span>
                      </button>
                    </div>
                  )
                })}
              </div>
            ))}
            {nowM != null && nowM >= H0 * 60 && nowM <= H1 * 60 && (
              <div className="pointer-events-none absolute inset-y-0 z-10 w-px bg-[var(--vl-error)]" style={{ insetInlineStart: `${pct(nowM)}%` }}>
                <span className="lab-now absolute -top-0 -translate-x-1/2 rounded-md bg-[var(--vl-error)] px-1.5 py-0.5 text-[10px] font-bold text-white">{String(now.getHours()).padStart(2, '0')}:{String(now.getMinutes()).padStart(2, '0')}</span>
              </div>
            )}
          </div>
        </div></div>
      </div>

      {/* כרטיסי משימה: רשימה קריאה לפי שעה */}
      <div className="grid gap-4 xl:grid-cols-[minmax(0,1fr)_380px]">
        <div className="lab-card overflow-hidden">
          <div className="border-b border-[var(--vl-border-subtle)] px-5 py-3 text-[15px] font-extrabold">המשימות לפי שעה</div>
          {tasks.map((t) => {
            const h = taskHealth(t)
            const people = [t.team_lead_name, ...(t.workers ?? []).map((w) => w.name), ...(t.drivers ?? []).map((w) => w.name)].filter(Boolean) as string[]
            return (
              <button key={t.id} onClick={() => setSel(t.id)} className={cx('flex w-full items-center gap-4 border-t border-[var(--vl-border-subtle)] px-5 py-3 text-start first:border-0 hover:bg-[var(--vl-subtle)]', sel === t.id && 'bg-[var(--vl-primary-subtle)]')}>
                <div className="w-[62px] shrink-0"><div className="text-[18px] font-extrabold leading-none tabular-nums">{hm(t.onsite_start_time)}</div><div className="mt-1 text-[11px] text-ink-tertiary tabular-nums">עד {hm(t.onsite_end_time)}</div></div>
                <span className="h-9 w-1 shrink-0 rounded-full" style={{ background: t.customer_color ?? 'var(--nova-a)' }} />
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2"><span className="truncate text-[14.5px] font-extrabold">{t.end_client_name}</span><Chip tone="neutral">{t.task_type_name}</Chip></div>
                  <div className="mt-0.5 flex items-center gap-3 text-[12px] text-ink-tertiary"><span className="inline-flex items-center gap-1"><MapPin size={12} />{t.location_text}</span><span className="inline-flex items-center gap-1"><Truck size={12} />{t.truck_name ?? 'ללא'}</span></div>
                </div>
                {people.length ? <AvatarStack names={people} max={4} size={28} /> : <span className="text-[12px] text-ink-tertiary">לא שובץ</span>}
                <Ring value={h.have} max={h.need} size={40} stroke={4} color={h.ready ? 'var(--vl-success)' : 'var(--vl-error)'}>{h.have}/{h.need}</Ring>
              </button>
            )
          })}
        </div>

        <div className="lab-card lab-scroll h-fit overflow-auto p-5 xl:sticky xl:top-2">
          {!selected ? <div className="py-10 text-center text-[13px] text-ink-tertiary">בחר משימה מהציר או מהרשימה כדי לראות את כל הפרטים</div> : (() => {
            const h = taskHealth(selected)
            return (
              <div className="flex flex-col gap-4">
                <div><div className="lab-eyebrow">{selected.task_type_name} · {selected.customer_name}</div><div className="text-[22px] font-extrabold tracking-tight">{selected.end_client_name}</div></div>
                <div className="grid grid-cols-3 gap-2 text-center">
                  {[['מחסן', hm(selected.warehouse_start_time)], ['בשטח', hm(selected.onsite_start_time)], ['סיום', hm(selected.onsite_end_time)]].map(([k, v]) => (
                    <div key={k} className="rounded-xl bg-[var(--vl-subtle)] py-2"><div className="text-[11px] text-ink-tertiary">{k}</div><div className="text-[17px] font-extrabold tabular-nums">{v}</div></div>
                  ))}
                </div>
                {h.flags.map((f) => <Chip key={f.key} tone={f.tone === 'bad' ? 'bad' : 'warn'} className="w-fit">⚠ {f.label}</Chip>)}
                <div className="flex flex-col gap-2 text-[13px]">
                  <div className="flex justify-between"><span className="text-ink-tertiary">ראש צוות</span><b>{selected.team_lead_name ?? '—'}</b></div>
                  <div className="flex justify-between"><span className="text-ink-tertiary">משאית</span><b>{selected.truck_name ?? '—'}</b></div>
                  <div className="flex justify-between"><span className="text-ink-tertiary">קבלן</span><b>{selected.contractor_name ?? '—'}</b></div>
                  <div className="flex justify-between"><span className="text-ink-tertiary">מיקום</span><b>{selected.location_text}</b></div>
                </div>
                <button onClick={() => selected.event_id && onOpen(selected.event_id)} className="bg-primary rounded-xl py-2.5 text-[13px] font-bold text-white">פתח את האירוע</button>
              </div>
            )
          })()}
        </div>
      </div>
    </div>
  )
}
