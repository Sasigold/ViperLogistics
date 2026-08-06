import { useEffect, useState } from 'react'
import { createPortal } from 'react-dom'
import { useNavigate } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import { Search, PartyPopper, Building2, User, ClipboardList } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import type { SearchResult } from '../../types/domain'

const icons = { event: PartyPopper, customer: Building2, profile: User, task: ClipboardList }
const kindLabels = { event: 'אירוע', customer: 'לקוח', profile: 'משתמש', task: 'משימה' }

export function CommandPalette({ open, onClose }: { open: boolean; onClose: () => void }) {
  const [q, setQ] = useState('')
  const navigate = useNavigate()

  useEffect(() => {
    const h = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault()
        if (!open) window.dispatchEvent(new CustomEvent('vl-open-search'))
      }
      if (e.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', h)
    return () => window.removeEventListener('keydown', h)
  }, [open, onClose])

  const { data: results = [], isFetching } = useQuery({
    queryKey: ['global_search', q],
    enabled: open && q.trim().length >= 2,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('global_search', { p_q: q.trim(), p_limit: 8 })
      if (error) throw error
      return data as SearchResult[]
    },
  })

  if (!open) return null

  const go = (r: SearchResult) => {
    onClose()
    setQ('')
    if (r.kind === 'event') navigate(`/events/${r.id}`)
    else if (r.kind === 'customer') navigate(`/customers/${r.id}`)
    else if (r.kind === 'profile') navigate('/users')
    else if (r.kind === 'task') navigate(`/board?task=${r.id}&date=${r.extra ?? ''}`)
  }

  return createPortal(
    <div className="fixed inset-0 z-[55] bg-black/40 p-4 pt-24" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="mx-auto w-full max-w-xl overflow-hidden rounded-xl border border-[var(--border)] bg-[var(--panel)] shadow-2xl">
        <div className="flex items-center gap-2 border-b border-[var(--border)] px-4 py-3">
          <Search size={16} className="text-[var(--muted)]" />
          <input
            autoFocus
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="חיפוש אירועים, לקוחות, עובדים, טלפונים..."
            className="w-full bg-transparent text-sm outline-none placeholder:text-[var(--muted)]"
          />
        </div>
        <div className="max-h-96 overflow-y-auto p-1.5">
          {q.trim().length < 2 && <p className="p-4 text-center text-sm text-[var(--muted)]">הקלד לפחות 2 תווים</p>}
          {q.trim().length >= 2 && !isFetching && results.length === 0 && (
            <p className="p-4 text-center text-sm text-[var(--muted)]">אין תוצאות</p>
          )}
          {results.map((r) => {
            const Icon = icons[r.kind]
            return (
              <button
                key={`${r.kind}:${r.id}`}
                onClick={() => go(r)}
                className="flex w-full items-center gap-3 rounded-lg px-3 py-2 text-start hover:bg-[var(--bg)]"
              >
                <Icon size={16} className="shrink-0 text-[var(--muted)]" />
                <span className="min-w-0">
                  <span className="block truncate text-sm font-medium">{r.title}</span>
                  <span className="block truncate text-xs text-[var(--muted)]">{r.subtitle}</span>
                </span>
                <span className="ms-auto rounded bg-[var(--bg)] px-1.5 py-0.5 text-[10px] text-[var(--muted)]">
                  {kindLabels[r.kind]}
                </span>
              </button>
            )
          })}
        </div>
      </div>
    </div>,
    document.body,
  )
}
