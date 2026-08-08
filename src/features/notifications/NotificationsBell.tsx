import { useEffect } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Bell, CheckCheck, ICON, STROKE } from '../../components/ui/icons'
import { Button, EmptyState, IconButton, Popover, cx, fmtRelative, useToast } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { fmtDateTime } from '../../lib/dates'
import type { Notification } from '../../types/domain'

export function NotificationsBell() {
  const me = useAuth((s) => s.me)
  const qc = useQueryClient()
  const toast = useToast()

  const { data: notifications = [] } = useQuery({
    queryKey: ['notifications', 'recent'],
    enabled: !!me,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('notifications')
        .select('*')
        // muted = סוג שהמשתמש או המנהל השתיקו בפעמון. השורה נשמרת כיומן
        // (‏notification_deliveries תלויה בה) אבל אינה מוצגת כאן.
        .eq('muted', false)
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
          const row = payload.new as Notification
          if (row.muted) return
          // דחיפה שהגיעה למערכת ההפעלה כבר הודיעה למשתמש. טוסט נוסף באותו
          // רגע הוא אותה הודעה פעמיים.
          const pushed =
            typeof Notification !== 'undefined' && window.Notification.permission === 'granted'
          if (!pushed) toast.info(row.title)
          void qc.invalidateQueries({ queryKey: ['notifications'] })
        },
      )
      .subscribe()
    return () => {
      void supabase.removeChannel(channel)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [me?.profile.id])

  const markAllRead = async () => {
    await supabase.rpc('mark_notifications_read')
    void qc.invalidateQueries({ queryKey: ['notifications'] })
  }

  return (
    <Popover
      panelClassName="w-[min(22rem,calc(100vw-2rem))] p-0 overflow-hidden"
      trigger={({ toggle, ...aria }) => (
        <span className="relative inline-flex">
          <IconButton
            label={unread > 0 ? `התראות (${unread} שלא נקראו)` : 'התראות'}
            size="sm"
            onClick={toggle}
            {...aria}
          >
            <Bell size={ICON.md} strokeWidth={STROKE} />
          </IconButton>
          {unread > 0 && (
            <span
              aria-hidden
              className="pointer-events-none absolute -top-0.5 end-0 flex size-4 items-center justify-center rounded-full bg-error text-[9px] font-bold tabular text-white ring-2 ring-surface"
            >
              {unread > 9 ? '9+' : unread}
            </span>
          )}
        </span>
      )}
    >
      {() => (
        <>
          <div className="flex items-center gap-2 border-b border-line-subtle px-3 py-2.5">
            <h3 className="type-title">התראות</h3>
            {unread > 0 && (
              <span className="rounded-full bg-primary-subtle px-1.5 py-0.5 type-caption font-bold tabular text-primary-text">
                {unread}
              </span>
            )}
            {unread > 0 && (
              <Button size="sm" variant="ghost" className="ms-auto" onClick={() => void markAllRead()}>
                <CheckCheck size={ICON.sm} />
                סמן הכל
              </Button>
            )}
          </div>

          <div className="max-h-96 overflow-y-auto">
            {notifications.length === 0 ? (
              <EmptyState compact art="check" title="אין התראות" description="כשמשהו ידרוש את תשומת ליבך, זה יופיע כאן" />
            ) : (
              <ul>
                {notifications.map((n) => (
                  <li
                    key={n.id}
                    className={cx(
                      'relative border-b border-line-subtle px-3 py-2.5 last:border-0 transition-colors hover:bg-hover',
                      !n.read_at && 'bg-primary-subtle/40',
                    )}
                  >
                    {!n.read_at && (
                      <span className="absolute end-2.5 top-3 size-1.5 rounded-full bg-primary" aria-label="לא נקרא" />
                    )}
                    <p className={cx('pe-4 type-body', n.read_at ? 'text-ink-secondary' : 'font-medium text-ink')}>
                      {n.title}
                    </p>
                    {n.body && <p className="mt-0.5 type-caption text-ink-tertiary">{n.body}</p>}
                    <p className="mt-1 type-caption text-ink-tertiary" title={fmtDateTime(n.created_at)}>
                      {fmtRelative(n.created_at)}
                    </p>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </>
      )}
    </Popover>
  )
}
