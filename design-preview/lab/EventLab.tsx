// דף אירוע — אותם רכיבים כמו היום: כותרת ופעולות, פרטי האירוע, תמחור, ארבעת הסיכומים, משימות, יומן פעילות. בסדר אחר: המשימות במרכז.
import { Calendar, Check, Clock, FileText, HardHat, Briefcase, MapPin, Paperclip, Pencil, PencilLine, Trash2, Users } from 'lucide-react'
import { fmtDM, hm, money, parse, useContact, useEvent, useTasks } from './data'
import { crewLead, crewPeople, crewSize } from '../../src/features/tasks/crew'
import { Chip, Rng, cx, tint } from './ui'

const H0 = 4, H1 = 24
const mn = (t: string | null) => (t ? +t.slice(0, 2) * 60 + +t.slice(3, 5) : null)
const pct = (m: number) => Math.max(0, Math.min(100, ((m - H0 * 60) / ((H1 - H0) * 60)) * 100))

export function EventLab({ id }: { id: string }) {
  const { data: e } = useEvent(id || 'e1-0000-4000-8000-000000000001')
  const { data: contact } = useContact(e?.id ?? '')
  const d = e?.event_date ?? '2026-09-29'
  const { data: all = [] } = useTasks(d, d)
  if (!e) return <div className="p-10 text-ink-tertiary">טוען…</div>
  const tasks = all.filter((t) => t.event_id === e.id).sort((a, b) => (a.onsite_start_time ?? '').localeCompare(b.onsite_start_time ?? ''))
  const color = e.customers?.color ?? '#64748b'
  const setup = tasks.filter((t) => t.task_type_code === 'setup').length, teardown = tasks.filter((t) => t.task_type_code === 'teardown').length
  const workers = tasks.reduce((a, t) => a + crewSize(t), 0)
  const total = tasks.reduce((a, t) => a + (t.customer_price ?? 0), 0)
  const addons = [e.no_parking && 'אין חניה', e.porterage && 'סבלות', e.supplier_pickup && 'איסוף מספקים'].filter(Boolean) as string[]
  const details: [string, React.ReactNode][] = [
    ['לקוח במערכת', <span key="c" className="inline-flex items-center gap-1.5"><span className="lab-dot" style={{ background: color }} />{e.customers?.name}</span>],
    ['שם לקוח האירוע', e.end_client_name], ['מספר אירוע', e.event_number], ['מיקום', e.location_text], ['הערות למיקום', e.location_notes],
    ['נפח במטר', e.volume_m], ['כמות משאיות', e.truck_count], ['איש קשר', contact?.contact_name],
    ['טלפון איש קשר', contact?.contact_phone ? <a key="p" dir="ltr" href={`tel:${contact.contact_phone}`} className="text-[var(--vl-primary-text)]">{contact.contact_phone}</a> : null],
    ['הערות', e.notes],
  ]

  return (
    <div className="mx-auto flex max-w-[1500px] flex-col gap-5 p-5">
      {/* כותרת: שם, סטטוס, מאושר, לקוח, תאריך, מספר, מיקום — ופעולות */}
      <div className="lab-card relative overflow-hidden p-6" style={{ background: `radial-gradient(70% 160% at 100% 0%, ${tint(color, 22)}, var(--vl-surface) 65%)` }}>
        <div className="flex flex-wrap items-start gap-6">
          <div className="flex size-[76px] shrink-0 flex-col items-center justify-center rounded-3xl bg-[var(--vl-surface)] shadow-[0_0_0_1px_var(--vl-border-subtle),var(--vl-shadow-md)]">
            <span className="text-[11px] font-bold text-ink-tertiary">{parse(d).toLocaleDateString('he-IL', { weekday: 'short' })}</span>
            <span className="text-[30px] font-extrabold leading-none tracking-tight">{parse(d).getDate()}</span>
            <span className="text-[11px] font-semibold text-ink-tertiary">{parse(d).toLocaleDateString('he-IL', { month: 'short' })}</span>
          </div>
          <div className="min-w-[280px] flex-1">
            <div className="flex flex-wrap items-center gap-2.5">
              <h1 className="text-[32px] font-extrabold leading-tight tracking-tight">{e.end_client_name}</h1>
              <span className="lab-chip" style={{ background: tint(e.statuses?.color ?? '#888', 16), color: 'var(--vl-text)' }}><span className="lab-dot" style={{ background: e.statuses?.color }} />{e.statuses?.name}</span>
              {e.approved_at && <Chip tone="good"><Check size={12} strokeWidth={3} />מאושר לביצוע</Chip>}
            </div>
            <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-[13.5px] text-ink-secondary">
              <span className="inline-flex items-center gap-1.5 font-semibold"><span className="lab-dot" style={{ background: color }} />{e.customers?.name}</span>
              <span className="inline-flex items-center gap-1.5"><Calendar size={14} />{parse(d).toLocaleDateString('he-IL', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}</span>
              {e.event_number && <span className="tabular-nums">אירוע #{e.event_number}</span>}
              {e.location_text && <span className="inline-flex items-center gap-1.5"><MapPin size={14} />{e.location_text}</span>}
            </div>
            {addons.length > 0 && <div className="mt-3 flex gap-1.5">{addons.map((a) => <Chip key={a} tone="brand">{a}</Chip>)}</div>}
          </div>
          <div className="flex flex-wrap items-center gap-2">
            {[[Paperclip, 'מפרט'], [FileText, 'הצעת מחיר'], [PencilLine, 'החתמת לקוח']].map(([I, l]) => { const Ic = I as typeof Paperclip; return <button key={l as string} className="inline-flex items-center gap-1.5 rounded-xl bg-[var(--vl-surface)] px-3.5 py-2 text-[13px] font-semibold shadow-[0_0_0_1px_var(--vl-border)]"><Ic size={14} />{l as string}</button> })}
            <button className="inline-flex items-center gap-1.5 rounded-xl bg-[var(--vl-surface)] px-3.5 py-2 text-[13px] font-semibold shadow-[0_0_0_1px_var(--vl-border)]"><Check size={14} />{e.approved_at ? 'ביטול אישור לביצוע' : 'אישור לביצוע'}</button>
            <button className="bg-primary inline-flex items-center gap-1.5 rounded-xl px-4 py-2 text-[13px] font-bold text-white"><Pencil size={14} />עריכה</button>
            <button className="inline-flex items-center gap-1.5 rounded-xl bg-[var(--vl-error-subtle)] px-3.5 py-2 text-[13px] font-semibold text-[var(--vl-error-text)]"><Trash2 size={14} />מחיקה</button>
          </div>
        </div>
      </div>

      {/* ארבעת הסיכומים — כמו היום */}
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {[
          ['סך משימות', <b key="a" className="text-[26px] leading-none">{tasks.length}</b>],
          ['חלוקת משימות', <span key="b" className="flex flex-wrap gap-1.5"><Chip tone="brand">הקמה {setup}</Chip><Chip tone="warn">פירוק {teardown}</Chip></span>],
          ['צוות משובץ', <span key="c" className="flex items-center gap-1.5"><Users size={16} className="text-ink-tertiary" /><b className="text-[26px] leading-none">{workers}</b><span className="text-[12px] text-ink-tertiary">עובדים</span></span>],
          ['סך תמחור', <b key="d" dir="ltr" className="text-[26px] leading-none text-[var(--vl-success-text)]">{money(total)}</b>],
        ].map(([k, v]) => (
          <div key={k as string} className="lab-card flex min-h-[86px] flex-col justify-between p-4"><span className="text-[12px] font-semibold text-ink-tertiary">{k}</span>{v}</div>
        ))}
      </div>

      <div className="grid items-start gap-5 xl:grid-cols-[minmax(0,1fr)_380px]">
        {/* משימות האירוע — במרכז הדף */}
        <div className="flex min-w-0 flex-col gap-4">
          <div className="lab-card p-5">
            <div className="mb-1 text-[15px] font-extrabold">פרטי האירוע</div>
            <dl className="grid gap-x-8 md:grid-cols-2">
              {details.filter(([, v]) => v != null && v !== '').map(([k, v]) => (
                <div key={k} className="flex items-start justify-between gap-4 border-b border-[var(--vl-border-subtle)] py-2.5 text-[13px]"><dt className="shrink-0 text-ink-tertiary">{k}</dt><dd className="text-end font-semibold">{v}</dd></div>
              ))}
            </dl>
          </div>
          <div className="flex items-center gap-3"><h2 className="text-[19px] font-extrabold">משימות האירוע</h2><Chip>{tasks.length}</Chip></div>
          <div className="grid gap-4 md:grid-cols-2">
            {tasks.map((t) => {
              const lead = crewLead(t), people = crewPeople(t)
              const w = mn(t.warehouse_start_time), a = mn(t.onsite_start_time), b = mn(t.onsite_end_time)
              return (
                <div key={t.id} className="lab-card lab-hoverable p-5">
                  <div className="flex items-center justify-between gap-2">
                    <div className="flex items-center gap-2"><Chip tone={t.task_type_code === 'teardown' ? 'warn' : 'brand'}>{t.task_type_code === 'teardown' ? 'פירוק' : t.task_type_code === 'setup' ? 'הקמה' : 'משימה'}</Chip>
                      <span className="lab-chip" style={{ background: tint(t.status_color, 16), color: 'var(--vl-text)' }}><span className="lab-dot" style={{ background: t.status_color }} />{t.status_name}</span></div>
                    {t.customer_price != null && <b dir="ltr" className="text-[15px] text-[var(--vl-success-text)]">{money(t.customer_price)}</b>}
                  </div>
                  <h3 className="mt-3 text-[19px] font-extrabold tracking-tight">{t.title || t.task_type_name}</h3>
                  <div className="mt-2 flex flex-wrap items-center gap-2 text-[12.5px] text-ink-secondary">
                    <span className="inline-flex items-center gap-1 rounded-md bg-[var(--vl-subtle)] px-2 py-1"><Calendar size={12} />{fmtDM(t.task_date)}</span>
                    <span className="inline-flex items-center gap-1 rounded-md bg-[var(--vl-subtle)] px-2 py-1"><Clock size={12} /><Rng a={hm(t.onsite_start_time)} b={hm(t.onsite_end_time)} /></span>
                    {t.hours_count != null && <span className="text-ink-tertiary">({t.hours_count} שעות)</span>}
                  </div>
                  {a != null && b != null && (
                    <div className="relative mt-3 h-1.5 rounded-full bg-[var(--vl-subtle)]">
                      {w != null && w < a && <span className="absolute inset-y-0 rounded-full bg-[var(--vl-border-strong)]" style={{ insetInlineStart: `${pct(w)}%`, width: `${pct(a) - pct(w)}%` }} />}
                      <span className="absolute inset-y-0 rounded-full" style={{ background: color, insetInlineStart: `${pct(a)}%`, width: `${pct(b) - pct(a)}%` }} />
                    </div>
                  )}
                  {(lead || t.contractor_name || t.execution_method_name) && (
                    <div className="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1 border-t border-[var(--vl-border-subtle)] pt-3 text-[12.5px] text-ink-secondary">
                      {lead && <span className="inline-flex items-center gap-1"><HardHat size={13} className="text-[var(--vl-warning-text)]" />ר״צ: {lead.name}</span>}
                      {t.contractor_name && <span className="inline-flex items-center gap-1"><Briefcase size={13} className="text-[var(--vl-info-text)]" />{t.contractor_name}</span>}
                      {t.execution_method_name && !t.contractor_name && <span className="text-ink-tertiary">({t.execution_method_name})</span>}
                    </div>
                  )}
                  <div className="mt-3 flex flex-wrap items-center gap-1.5 border-t border-[var(--vl-border-subtle)] pt-3">
                    {people.length ? people.map((p) => <span key={p.key} className="rounded bg-[var(--vl-subtle)] px-1.5 py-px text-[12px] text-ink-secondary">{p.name}</span>) : <span className="text-[12px] text-ink-tertiary">לא שובצו עובדים</span>}
                    <span className="ms-auto text-[12px] tabular-nums text-ink-tertiary">{crewSize(t)}/{t.worker_count || '—'} עובדים</span>
                  </div>
                </div>
              )
            })}
          </div>
        </div>

        {/* עמודת צד: פרטי האירוע, תמחור, יומן פעילות */}
        <div className="flex flex-col gap-5">
          <div className="lab-card p-5">
            <div className="text-[15px] font-extrabold">תמחור</div>
            <div className="mb-2 text-[12px] text-ink-tertiary">המחיר שהלקוח משלם</div>
            <dl className="flex flex-col divide-y divide-[var(--vl-border-subtle)]">
              {tasks.map((t) => <div key={t.id} className="flex justify-between py-2.5 text-[13px]"><dt className="text-ink-secondary">{t.title || t.task_type_name}</dt><dd dir="ltr" className="font-semibold tabular-nums">{money(t.customer_price)}</dd></div>)}
              <div className="flex items-baseline justify-between pt-3"><dt className="text-[13px] font-bold">סך הכול</dt><dd dir="ltr" className="text-[22px] font-extrabold tracking-tight text-[var(--vl-success-text)]">{money(total)}</dd></div>
            </dl>
          </div>
          <div className="lab-card p-5">
            <div className="text-[15px] font-extrabold">יומן פעילות</div>
            <div className="mb-3 text-[12px] text-ink-tertiary">כל שינוי באירוע יירשם כאן אוטומטית, ואפשר גם לרשום תיעוד חופשי</div>
            <div className="rounded-xl bg-[var(--vl-subtle)] p-3 text-[13px] text-ink-tertiary">מה קרה? למשל: הלקוח ביקש משאית נוספת בטלפון</div>
            <button className="bg-primary mt-2 rounded-xl px-4 py-2 text-[13px] font-bold text-white opacity-60">הוספה ליומן</button>
            <div className="mt-5 text-center"><div className="text-[14px] font-bold">היומן ריק</div></div>
          </div>
        </div>
      </div>
    </div>
  )
}
export { cx }
