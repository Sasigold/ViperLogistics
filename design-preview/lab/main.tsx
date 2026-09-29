import { StrictMode, useState } from 'react'
import { createRoot } from 'react-dom/client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { CalendarDays, ClipboardList, LayoutDashboard, Truck, Users, Clock, Settings, PartyPopper } from 'lucide-react'
import '../../src/index.css'
import '../variants/nova.css'
import './lab.css'
import { CalendarLab } from './CalendarLab'
import { DispatchLab } from './DispatchLab'
import { EventLab } from './EventLab'
import { cx } from './ui'

const qc = new QueryClient({ defaultOptions: { queries: { retry: 0, refetchOnWindowFocus: false } } })
const params = new URLSearchParams(location.search)
document.documentElement.dataset.theme = params.get('theme') ?? localStorage.getItem('vl-theme') ?? 'light'

const PAGES = [
  { k: 'calendar', label: 'לוח אירועים', icon: CalendarDays },
  { k: 'dispatch', label: 'לוח שיבוץ יומי', icon: ClipboardList },
  { k: 'event', label: 'דף אירוע', icon: PartyPopper },
] as const

function App() {
  const [page, setPage] = useState<string>(params.get('page') ?? 'calendar')
  const [eventId, setEventId] = useState<string>(params.get('event') ?? '')
  const open = (id: string) => { setEventId(id); setPage('event') }
  return (
    <div className="flex h-screen gap-0 md:p-2 md:pe-0">
      {/* פס אייקונים צר — כל המסכים נגישים, אבל התוכן תופס את הרוחב */}
      <nav className="hidden w-[68px] md:flex shrink-0 flex-col items-center gap-1 py-3">
        <img src="/icons/icon-192.png" className="mb-4 size-9 rounded-[11px] shadow-[0_4px_14px_-4px_var(--nova-a)]" />
        {[LayoutDashboard, CalendarDays, ClipboardList, Truck, Users, Clock].map((I, i) => (
          <span key={i} className={cx('flex size-10 items-center justify-center rounded-xl text-ink-tertiary', i === 1 && 'bg-[var(--vl-surface)] text-[var(--nova-a)] shadow-sm')}><I size={19} /></span>
        ))}
        <span className="mt-auto flex size-10 items-center justify-center rounded-xl text-ink-tertiary"><Settings size={19} /></span>
      </nav>
      <div className="flex min-w-0 flex-1 flex-col overflow-hidden md:mx-2 md:rounded-[22px] bg-[var(--vl-surface)] shadow-[0_0_0_1px_var(--vl-border),0_30px_60px_-30px_rgb(16_20_46/0.25)]">
        <div className="flex h-14 shrink-0 items-center gap-3 border-b border-[var(--vl-border-subtle)] px-5">
          <span className="text-[15px] font-extrabold tracking-tight">ViperLogistics</span>
          <span className="lab-chip hidden bg-[var(--vl-primary-subtle)] text-[var(--vl-primary-text)] sm:inline-flex">Layout Lab</span>
          <div className="ms-auto flex gap-0.5 overflow-x-auto rounded-xl bg-[var(--vl-subtle)] p-[3px]">
            {PAGES.map((p) => (
              <button key={p.k} onClick={() => setPage(p.k)} className={cx('flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-[9px] px-2.5 py-1 text-[12.5px] font-semibold', page === p.k ? 'bg-[var(--vl-surface)] shadow-sm' : 'text-ink-tertiary')}>
                <p.icon size={14} />{p.label}
              </button>
            ))}
          </div>
        </div>
        <div className="lab-scroll min-h-0 flex-1 overflow-auto">
          {page === 'calendar' && <CalendarLab onOpen={open} initialSel={params.get('sel')} />}
          {page === 'dispatch' && <DispatchLab onOpen={open} />}
          {page === 'event' && <EventLab id={eventId} />}
        </div>
      </div>
    </div>
  )
}
createRoot(document.getElementById('root')!).render(<StrictMode><QueryClientProvider client={qc}><App /></QueryClientProvider></StrictMode>)
