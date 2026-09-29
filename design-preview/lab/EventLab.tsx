import { BadgeCheck, CalendarDays, Check, CircleDashed, FileText, MapPin, MessageSquare, Navigation, PackageCheck, Phone, Truck, UserRound, Users, Wallet } from 'lucide-react'
import { hm, money, parse, taskHealth, useEvent, useTasks, HE_DAYS } from './data'
import { Stepper } from './CalendarLab'
import { Avatar, AvatarStack, Chip, Ring, Rng, cx, tint } from './ui'
import type { WorkBoardRow } from '../../src/types/domain'

export function EventLab({ id }: { id: string }) {
  const { data: e } = useEvent(id || 'e1-0000-4000-8000-000000000001')
  const d = e?.event_date ?? '2026-09-29'
  const { data: all = [] } = useTasks(d, d)
  if (!e) return <div className="p-10 text-ink-tertiary">טוען…</div>
  const tasks: WorkBoardRow[] = all.filter((t) => t.event_id === e.id).sort((a, b) => (a.warehouse_start_time ?? a.onsite_start_time ?? '').localeCompare(b.warehouse_start_time ?? b.onsite_start_time ?? ''))
  const color = e.customers?.color ?? '#64748b'
  const hs = tasks.map(taskHealth)
  const price = tasks.reduce((a, t) => a + (t.customer_price ?? 0), 0)
  const cost = tasks.reduce((a, t) => a + (t.contractor_price ?? 0), 0) + tasks.reduce((a, t) => a + t.worker_count * 3 * 46, 0)
  const checks = [
    { ok: !!e.approved_at, label: 'האירוע אושר לביצוע', hint: e.approved_at ? 'אושר על ידי מנהל' : 'ממתין לאישור' },
    { ok: tasks.length > 0 && tasks.every((t) => t.truck_id), label: 'משאיות שובצו', hint: `${tasks.filter((t) => t.truck_id).length}/${tasks.length} משימות` },
    { ok: tasks.every((t) => !t.requires_team_lead || t.team_lead_id), label: 'ראש צוות לכל משימה', hint: tasks.filter((t) => t.team_lead_id).length + '/' + tasks.length },
    { ok: hs.every((h) => h.have >= h.need), label: 'הצוות מלא', hint: `${hs.reduce((a, h) => a + Math.min(h.have, h.need), 0)}/${hs.reduce((a, h) => a + h.need, 0)} עובדים` },
    { ok: price > 0, label: 'מחיר נקבע', hint: money(price) },
  ]
  const score = checks.filter((c) => c.ok).length
  const dt = parse(d)
  // ציר זמן מאוחד של היום: כל צעד של כל משימה בסדר כרונולוגי
  const steps = tasks.flatMap((t) => [
    t.warehouse_start_time && { time: t.warehouse_start_time, title: `יציאה מהמחסן · ${t.task_type_name}`, sub: t.truck_name ?? 'ללא משאית', icon: Truck, t },
    t.onsite_start_time && { time: t.onsite_start_time, title: `תחילת ${t.task_type_name} בשטח`, sub: `${t.worker_count} עובדים`, icon: Users, t },
    t.onsite_end_time && { time: t.onsite_end_time, title: `סיום ${t.task_type_name}`, sub: t.hours_count ? `${t.hours_count} שעות עבודה` : '', icon: BadgeCheck, t },
  ]).filter(Boolean).sort((a, b) => a!.time.localeCompare(b!.time)) as { time: string; title: string; sub: string; icon: typeof Truck; t: WorkBoardRow }[]

  return (
    <div className="mx-auto flex max-w-[1500px] flex-col gap-5 p-5">
      {/* Hero */}
      <div className="lab-card relative overflow-hidden p-0">
        <div className="absolute inset-0 opacity-90" style={{ background: `radial-gradient(70% 140% at 100% 0%, ${tint(color, 26)}, transparent 60%), radial-gradient(60% 120% at 0% 100%, color-mix(in srgb, var(--nova-b) 12%, transparent), transparent 60%)` }} />
        <div className="relative flex flex-wrap items-start gap-6 p-6">
          <div className="flex size-[76px] shrink-0 flex-col items-center justify-center rounded-3xl bg-[var(--vl-surface)] shadow-[0_0_0_1px_var(--vl-border-subtle),var(--vl-shadow-md)]">
            <span className="text-[11px] font-bold text-ink-tertiary">{HE_DAYS[dt.getDay()]}</span>
            <span className="text-[30px] font-extrabold leading-none tracking-tight">{dt.getDate()}</span>
            <span className="text-[11px] font-semibold text-ink-tertiary">{dt.toLocaleDateString('he-IL', { month: 'short' })}</span>
          </div>
          <div className="min-w-[280px] flex-1">
            <div className="flex flex-wrap items-center gap-2">
              <span className="lab-chip" style={{ background: tint(color, 16), color: 'var(--vl-text)' }}><span className="lab-dot" style={{ background: color }} />{e.customers?.name}</span>
              <span className="text-[12.5px] text-ink-tertiary">אירוע #{e.event_number}</span>
              {e.approved_at && <Chip tone="good"><Check size={12} />מאושר לביצוע</Chip>}
            </div>
            <h1 className="mt-1.5 text-[34px] font-extrabold leading-[1.1] tracking-tight">{e.end_client_name}</h1>
            <div className="mt-2 flex flex-wrap items-center gap-x-5 gap-y-1 text-[13.5px] text-ink-secondary">
              <span className="inline-flex items-center gap-1.5"><MapPin size={15} />{e.location_text}</span>
              <span className="inline-flex items-center gap-1.5"><CalendarDays size={15} />{dt.toLocaleDateString('he-IL', { day: 'numeric', month: 'long', year: 'numeric' })}</span>
              {e.volume_m != null && <span className="inline-flex items-center gap-1.5"><PackageCheck size={15} />{e.volume_m} מ״ק</span>}
              {e.truck_count != null && <span className="inline-flex items-center gap-1.5"><Truck size={15} />{e.truck_count} משאיות</span>}
            </div>
            <div className="mt-5 max-w-[560px]"><Stepper code={e.statuses?.code ?? 'new'} /></div>
          </div>
          <div className="flex items-center gap-2">
            <button className="rounded-xl bg-[var(--vl-surface)] px-4 py-2.5 text-[13px] font-semibold shadow-[0_0_0_1px_var(--vl-border)]"><FileText size={14} className="me-1.5 inline" />הצעת מחיר</button>
            <button className="bg-primary rounded-xl px-5 py-2.5 text-[13px] font-bold text-white">עריכת אירוע</button>
          </div>
        </div>
      </div>

      <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_360px]">
        <div className="flex min-w-0 flex-col gap-5">
          {/* Readiness */}
          <div className="lab-card p-5">
            <div className="mb-4 flex items-center gap-4">
              <Ring value={score} max={checks.length} size={64} stroke={7} color={score === checks.length ? 'var(--vl-success)' : 'var(--nova-a)'}>{score}/{checks.length}</Ring>
              <div><div className="text-[17px] font-extrabold">מוכנות לביצוע</div><div className="text-[13px] text-ink-tertiary">{score === checks.length ? 'הכול מוכן — אפשר לצאת לדרך' : `${checks.length - score} דברים עדיין פתוחים`}</div></div>
            </div>
            <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-5">
              {checks.map((c) => (
                <div key={c.label} className={cx('rounded-2xl p-3', c.ok ? 'bg-[var(--vl-success-subtle)]' : 'bg-[var(--vl-warning-subtle)]')}>
                  <span className={cx('mb-2 flex size-6 items-center justify-center rounded-full', c.ok ? 'bg-[var(--vl-success)] text-white' : 'border-2 border-dashed border-[var(--vl-warning)] text-[var(--vl-warning-text)]')}>{c.ok ? <Check size={14} strokeWidth={3} /> : <CircleDashed size={13} />}</span>
                  <div className="text-[13px] font-bold leading-tight">{c.label}</div>
                  <div className="mt-0.5 text-[11.5px] text-ink-secondary">{c.hint}</div>
                </div>
              ))}
            </div>
          </div>

          {/* Run of show */}
          <div className="lab-card p-5">
            <div className="mb-4 flex items-center justify-between"><div className="text-[17px] font-extrabold">מהלך היום</div><span className="text-[12px] text-ink-tertiary">כל הצעדים בסדר כרונולוגי</span></div>
            <ol className="relative ps-1">
              {steps.map((s, i) => (
                <li key={i} className="relative flex gap-4 pb-5 last:pb-0">
                  {i < steps.length - 1 && <span className="absolute start-[54px] top-9 bottom-0 w-px bg-[var(--vl-border)]" />}
                  <span className="w-[48px] shrink-0 pt-1.5 text-end text-[14px] font-extrabold tabular-nums">{hm(s.time)}</span>
                  <span className="z-10 flex size-9 shrink-0 items-center justify-center rounded-xl" style={{ background: tint(s.t.customer_color ?? '#5b5bf0', 16), color: 'var(--vl-primary-text)' }}><s.icon size={16} /></span>
                  <div className="min-w-0 flex-1 pt-0.5"><div className="text-[14px] font-bold">{s.title}</div><div className="text-[12.5px] text-ink-tertiary">{s.sub}</div></div>
                </li>
              ))}
              {steps.length === 0 && <div className="text-[13px] text-ink-tertiary">אין עדיין משימות לאירוע</div>}
            </ol>
          </div>

          {/* Tasks as cards */}
          <div className="grid gap-4 md:grid-cols-2">
            {tasks.map((t, i) => {
              const h = hs[i]
              const people = [t.team_lead_name, ...(t.workers ?? []).map((w) => w.name), ...(t.drivers ?? []).map((w) => w.name)].filter(Boolean) as string[]
              return (
                <div key={t.id} className="lab-card p-5">
                  <div className="flex items-start justify-between gap-2">
                    <div><div className="text-[17px] font-extrabold">{t.task_type_name}</div><div className="text-[12.5px] text-ink-tertiary"><Rng a={hm(t.onsite_start_time)} b={hm(t.onsite_end_time)} /> · {t.hours_count} שעות</div></div>
                    <span className="lab-chip" style={{ background: tint(t.status_color, 16), color: 'var(--vl-text)' }}><span className="lab-dot" style={{ background: t.status_color }} />{t.status_name}</span>
                  </div>
                  <div className="mt-4 flex items-center gap-3">
                    <Ring value={h.have} max={h.need} size={56} stroke={6} color={h.ready ? 'var(--vl-success)' : 'var(--vl-error)'}>{h.have}/{h.need}</Ring>
                    <div className="min-w-0 flex-1">{people.length ? <AvatarStack names={people} max={5} size={30} /> : <span className="text-[13px] text-ink-tertiary">עדיין לא שובצו אנשים</span>}
                      {t.team_lead_name && <div className="mt-1.5 flex items-center gap-1.5 text-[12.5px]"><UserRound size={13} className="text-ink-tertiary" />ראש צוות: <b>{t.team_lead_name}</b></div>}</div>
                  </div>
                  <div className="mt-4 flex flex-wrap gap-1.5">
                    <Chip tone={t.truck_name ? 'neutral' : 'warn'}><Truck size={12} />{t.truck_name ?? 'ללא משאית'}</Chip>
                    {t.execution_method_name && <Chip>{t.execution_method_name}</Chip>}
                    {t.contractor_name && <Chip tone="brand">קבלן: {t.contractor_name}</Chip>}
                    {h.flags.map((f) => <Chip key={f.key} tone={f.tone === 'bad' ? 'bad' : 'warn'}>{f.label}</Chip>)}
                  </div>
                </div>
              )
            })}
          </div>
        </div>

        {/* עמודת צד: מקום, כסף, אנשי קשר, יומן */}
        <div className="flex flex-col gap-5">
          <div className="lab-card overflow-hidden">
            <div className="relative h-[150px]" style={{ background: 'linear-gradient(135deg, color-mix(in srgb, var(--nova-a) 14%, var(--vl-subtle)), var(--vl-subtle))' }}>
              <svg className="absolute inset-0 size-full opacity-60" viewBox="0 0 300 150" preserveAspectRatio="none"><g stroke="var(--vl-border-strong)" strokeWidth="1" fill="none"><path d="M0 100 C60 80 90 120 150 90 S250 60 300 80" /><path d="M40 0 C60 50 30 90 70 150" /><path d="M170 0 C150 60 200 90 190 150" /><path d="M0 40 L300 55" /></g></svg>
              <span className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-[70%]"><MapPin size={38} className="text-[var(--nova-a)] drop-shadow-lg" fill="var(--vl-surface)" /></span>
            </div>
            <div className="p-4"><div className="text-[14.5px] font-extrabold">{e.location_text}</div>{e.location_notes && <div className="mt-1 text-[12.5px] text-ink-secondary">{e.location_notes}</div>}
              <button className="mt-3 inline-flex items-center gap-1.5 rounded-xl bg-[var(--vl-subtle)] px-3 py-1.5 text-[12.5px] font-semibold"><Navigation size={13} />נווט ב-Waze</button></div>
          </div>

          <div className="lab-card p-5">
            <div className="mb-3 flex items-center gap-2 text-[15px] font-extrabold"><Wallet size={17} />כסף</div>
            <div className="flex items-end justify-between"><span className="text-[12.5px] text-ink-tertiary">חיוב ללקוח</span><span className="text-[26px] font-extrabold leading-none tracking-tight">{money(price)}</span></div>
            <div className="my-3 h-2 overflow-hidden rounded-full bg-[var(--vl-subtle)]"><div className="h-full rounded-full" style={{ width: `${Math.min(100, (cost / (price || 1)) * 100)}%`, background: 'var(--nova-grad)' }} /></div>
            <div className="flex justify-between text-[12.5px]"><span className="text-ink-tertiary">עלות משוערת</span><b>{money(cost)}</b></div>
            <div className="mt-1 flex justify-between text-[12.5px]"><span className="text-ink-tertiary">רווח משוער</span><b className="text-[var(--vl-success-text)]">{money(price - cost)}</b></div>
          </div>

          <div className="lab-card p-5">
            <div className="mb-3 text-[15px] font-extrabold">איש קשר</div>
            <div className="flex items-center gap-3"><Avatar name="אבי כהן" size={40} /><div className="flex-1"><div className="text-[14px] font-bold">אבי כהן</div><div className="text-[12.5px] text-ink-tertiary" dir="ltr">050-1234567</div></div>
              <span className="flex size-9 items-center justify-center rounded-xl bg-[var(--vl-success-subtle)] text-[var(--vl-success-text)]"><Phone size={16} /></span></div>
            {e.notes && <div className="mt-4 rounded-xl bg-[var(--vl-warning-subtle)] px-3 py-2.5 text-[12.5px] text-[var(--vl-warning-text)]"><MessageSquare size={12} className="me-1 inline" />{e.notes}</div>}
          </div>

          <div className="lab-card p-5">
            <div className="mb-3 text-[15px] font-extrabold">יומן פעילות</div>
            <ul className="flex flex-col gap-3 text-[12.5px]">
              {[['מנהל מערכת', 'אישר את האירוע לביצוע', 'לפני 3 ימים'], ['דניאל כהן', 'שובץ כראש צוות בהקמה', 'לפני יומיים'], ['מערכת', 'נוצרו משימות הקמה ופירוק', 'לפני שבוע']].map(([w, a, when]) => (
                <li key={a} className="flex gap-2.5"><Avatar name={w} size={24} /><div><b>{w}</b> {a}<div className="text-[11px] text-ink-tertiary">{when}</div></div></li>
              ))}
            </ul>
          </div>
        </div>
      </div>
    </div>
  )
}
