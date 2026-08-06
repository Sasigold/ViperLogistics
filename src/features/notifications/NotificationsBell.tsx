import { useEffect, useRef, useState } from 'react'
import { Bell } from 'lucide-react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { Button, useToast } from '../../components/ui'
import { fmtDateTime } from '../../lib/dates'
import type { Notification } from '../../types/domain'

export function NotificationsBell() {
  const me = useAuth((s) => s.me)
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  const qc = useQueryClient()
  const toast = useToast()

  const { data: notifications = [] } = useQuery({
    queryKey: ['notifications', 'recent'],
    enabled: !!me,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('notifications')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(30)
      if (error) throw error
      return data as Notification[]
    },
  })
  const unread = notifications.filter((n) => !n.read_at).length

  // realtime: new notifications for me
  useEffect(() => {
    if (!me) return
    const channel = supabase
      .channel(`notif:${me.profile.id}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'notifications', filter: `recipient_id=eq.${me.profile.id}` },
        (payload) => {
          toast.success((payload.new as Notification).title)
          void qc.invalidateQueries({ queryKey: ['notifications'] })
        },
      )
      .subscribe()
    return () => {
      void supabase.removeChannel(channel)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [me?.profile.id])

  useEffect(() => {
    const h = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', h)
    return () => document.removeEventListener('mousedown', h)
  }, [])

  const markAllRead = async () => {
    await supabase.rpc('mark_notifications_read')
    void qc.invalidateQueries({ queryKey: ['notifications'] })
  }

  return (
    <div ref={ref} className="relative">
      <button onClick={() => setOpen((v) => !v)} className="relative rounded-lg p-2 text-[var(--muted)] hover:bg-[var(--bg)]">
        <Bell size={16} />
        {unread > 0 && (
          <span className="absolute -top-0.5 -start-0.5 flex size-4 items-center justify-center rounded-full bg-red-500 text-[10px] font-bold text-white">
            {unread > 9 ? '9+' : unread}
          </span>
        )}
      </button>
      {open && (
        <div className="absolute end-0 z-40 mt-1 w-80 rounded-xl border border-[var(--border)] bg-[var(--panel)] shadow-xl">
          <div className="flex items-center justify-between border-b border-[var(--border)] px-3 py-2">
            <span className="text-sm font-bold">התראות</span>
            {unread > 0 && (
              <Button variant="ghost" className="text-xs" onClick={() => void markAllRead()}>
                סמן הכל כנקרא
              </Button>
            )}
          </div>
          <div className="max-h-80 overflow-y-auto">
            {notifications.length === 0 && <p className="p-4 text-center text-sm text-[var(--muted)]">אין התראות</p>}
            {notifications.map((n) => (
              <div key={n.id} className={`border-b border-[var(--border)] px-3 py-2 last:border-0 ${n.read_at ? 'opacity-60' : ''}`}>
                <p className="text-sm font-medium">{n.title}</p>
                {n.body && <p className="text-xs text-[var(--muted)]">{n.body}</p>}
                <p className="mt-0.5 text-[10px] text-[var(--muted)]">{fmtDateTime(n.created_at)}</p>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
