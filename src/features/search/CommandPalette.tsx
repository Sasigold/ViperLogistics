import { useEffect, useMemo, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { useNavigate } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import {
  Building2,
  ClipboardList,
  ICON,
  Loader2,
  PartyPopper,
  STROKE,
  Search,
  User,
} from '../../components/ui/icons'
import { EmptyState, Kbd, cx } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import type { SearchResult } from '../../types/domain'

const KINDS = {
  event: { icon: PartyPopper, label: 'אירועים', tone: '#8b5cf6' },
  customer: { icon: Building2, label: 'לקוחות', tone: '#3563f0' },
  profile: { icon: User, label: 'עובדים', tone: '#1fa189' },
  task: { icon: ClipboardList, label: 'משימות', tone: '#f59e0b' },
} as const

/**
 * Global search overlay. Ctrl/Cmd+K is owned by AppLayout — this component
 * only handles what happens once it is open.
 */
export function CommandPalette({ open, onClose }: { open: boolean; onClose: () => void }) {
  const [q, setQ] = useState('')
  const [active, setActive] = useState(0)
  const navigate = useNavigate()
  const listRef = useRef<HTMLDivElement>(null)

  const { data: results = [], isFetching } = useQuery({
    queryKey: ['global_search', q],
    enabled: open && q.trim().length >= 2,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('global_search', { p_q: q.trim(), p_limit: 8 })
      if (error) throw error
      return data as SearchResult[]
    },
  })

  // group results by kind so 20 rows read as four short lists
  const groups = useMemo(() => {
    const order: (keyof typeof KINDS)[] = ['task', 'event', 'customer', 'profile']
    const flat: SearchResult[] = []
    const out: { kind: keyof typeof KINDS; items: SearchResult[]; offset: number }[] = []
    for (const kind of order) {
      const items = results.filter((r) => r.kind === kind)
      if (items.length === 0) continue
      out.push({ kind, items, offset: flat.length })
      flat.push(...items)
    }
    return { groups: out, flat }
  }, [results])

  useEffect(() => setActive(0), [q, results])
  useEffect(() => {
    if (!open) setQ('')
  }, [open])

  // keep the highlighted row in view while arrowing through
  useEffect(() => {
    listRef.current?.querySelector<HTMLElement>('[data-active="true"]')?.scrollIntoView({ block: 'nearest' })
  }, [active])

  if (!open) return null

  const go = (r: SearchResult) => {
    onClose()
    setQ('')
    if (r.kind === 'event') navigate(`/events/${r.id}`)
    else if (r.kind === 'customer') navigate(`/customers/${r.id}`)
    else if (r.kind === 'profile') navigate('/users')
    else if (r.kind === 'task') navigate(`/board?task=${r.id}&date=${r.extra ?? ''}`)
  }

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Escape') {
      e.preventDefault()
      onClose()
    } else if (e.key === 'ArrowDown') {
      e.preventDefault()
      setActive((i) => Math.min(i + 1, groups.flat.length - 1))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setActive((i) => Math.max(i - 1, 0))
    } else if (e.key === 'Enter' && groups.flat[active]) {
      e.preventDefault()
      go(groups.flat[active])
    }
  }

  const short = q.trim().length < 2

  return createPortal(
    <div
      className="fixed inset-0 z-[55] scrim p-4 pt-[12vh]"
      onMouseDown={(e) => e.target === e.currentTarget && onClose()}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label="חיפוש גלובלי"
        className="mx-auto w-full max-w-xl animate-scale-in overflow-hidden rounded-2xl border border-line bg-raised shadow-overlay"
      >
        <div className="flex items-center gap-2.5 border-b border-line-subtle px-4 py-3.5">
          {isFetching ? (
            <Loader2 size={ICON.lg} className="shrink-0 animate-spin text-primary" aria-hidden />
          ) : (
            <Search size={ICON.lg} className="shrink-0 text-ink-tertiary" strokeWidth={STROKE} aria-hidden />
          )}
          <input
            autoFocus
            value={q}
            onChange={(e) => setQ(e.target.value)}
            onKeyDown={onKeyDown}
            role="combobox"
            aria-expanded
            aria-autocomplete="list"
            placeholder="חיפוש אירועים, לקוחות, עובדים, טלפונים..."
            className="w-full bg-transparent type-subtitle outline-none placeholder:text-ink-tertiary"
          />
          <Kbd className="shrink-0">Esc</Kbd>
        </div>

        <div ref={listRef} className="max-h-[min(26rem,60vh)] overflow-y-auto p-2" role="listbox">
          {short && (
            <EmptyState
              compact
              title="הקלד לפחות 2 תווים"
              description="החיפוש סורק אירועים, לקוחות, עובדים ומשימות בבת אחת"
            />
          )}
          {!short && !isFetching && results.length === 0 && (
            <EmptyState compact art="search" title="אין תוצאות" description={`לא נמצאה התאמה עבור "${q.trim()}"`} />
          )}

          {groups.groups.map(({ kind, items, offset }) => {
            const meta = KINDS[kind]
            const Icon = meta.icon
            return (
              <div key={kind} className="mb-1 last:mb-0">
                <p className="px-2 pb-1 pt-2 type-overline">{meta.label}</p>
                {items.map((r, i) => {
                  const idx = offset + i
                  const isActive = idx === active
                  return (
                    <button
                      key={`${r.kind}:${r.id}`}
                      role="option"
                      aria-selected={isActive}
                      data-active={isActive}
                      onMouseEnter={() => setActive(idx)}
                      onClick={() => go(r)}
                      className={cx(
                        'flex w-full items-center gap-3 rounded-lg px-2.5 py-2 text-start transition-colors',
                        isActive && 'bg-hover',
                      )}
                    >
                      <span
                        className="flex size-7 shrink-0 items-center justify-center rounded-lg"
                        style={{ background: `color-mix(in srgb, ${meta.tone} 13%, transparent)`, color: meta.tone }}
                        aria-hidden
                      >
                        <Icon size={ICON.sm} strokeWidth={STROKE} />
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate type-body font-medium">{r.title}</span>
                        <span className="block truncate type-caption text-ink-tertiary">{r.subtitle}</span>
                      </span>
                      {isActive && <Kbd className="shrink-0">↵</Kbd>}
                    </button>
                  )
                })}
              </div>
            )
          })}
        </div>

        <div className="flex items-center gap-3 border-t border-line-subtle bg-subtle/50 px-4 py-2 type-caption text-ink-tertiary">
          <span className="flex items-center gap-1">
            <Kbd>↑</Kbd>
            <Kbd>↓</Kbd> ניווט
          </span>
          <span className="flex items-center gap-1">
            <Kbd>↵</Kbd> פתיחה
          </span>
          <span className="ms-auto flex items-center gap-1">
            <Kbd>Ctrl</Kbd>
            <Kbd>K</Kbd>
          </span>
        </div>
      </div>
    </div>,
    document.body,
  )
}
