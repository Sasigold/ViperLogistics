import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Bell, ICON, STROKE } from '../../components/ui/icons'
import {
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  ErrorState,
  PageHeader,
  Skeleton,
  Switch,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { errorMessage } from '../../lib/errors'

/**
 * העדפות ההתראות של המשתמש עצמו.
 *
 * המסך יושב תחת /my ולא בהגדרות במכוון: ההגדרות מגודרות ב-settings.view,
 * ועובד שמקבל שיבוצים אינו אמור להחזיק אותו כדי להחליט אם למלא לו את תיבת
 * הדואר. המפתח notifications.preferences הוא default_allowed, ולכן כל מי
 * שיש לו חשבון מגיע לכאן.
 */

/** הסוגים שמייצרים היום התראה, לפי app.notify_* ב-0004 ו-0024. */
const TYPES = [
  { key: 'task_assigned', label: 'שובצתי למשימה' },
  { key: 'task_changed', label: 'שינוי בזמני משימה ששובצתי אליה' },
  { key: 'contractor_task', label: 'משימה חדשה הוקצתה לקבלן שלי' },
  { key: 'event_created', label: 'לקוח פתח אירוע חדש' },
  { key: 'attendance_submitted', label: 'עובד דיווח משמרת שממתינה לאישור' },
  { key: 'attendance_reviewed', label: 'הדיווח שלי אושר או נדחה' },
] as const

interface Pref {
  profile_id: string
  channel: string
  type: string | null
  enabled: boolean
}

export default function NotificationPreferencesPage() {
  return (
    <RequirePermission perm={PERM.NOTIFICATIONS_PREFERENCES}>
      <Preferences />
    </RequirePermission>
  )
}

function Preferences() {
  const toast = useToast()
  const qc = useQueryClient()
  const profileId = useAuth((s) => s.me?.profile.id)

  const { data: prefs = [], isLoading, error, refetch } = useQuery({
    queryKey: ['notification_preferences', profileId],
    enabled: !!profileId,
    queryFn: async () => {
      const { data, error: e } = await supabase
        .from('notification_preferences')
        .select('*')
        .eq('profile_id', profileId)
      if (e) throw e
      return data as Pref[]
    },
  })

  // האם ערוץ הדואר בכלל דלוק במערכת. כשהוא כבוי אין טעם להבטיח משהו.
  const { data: channelOn } = useQuery({
    queryKey: ['app_settings', 'notifications.email'],
    queryFn: async () => {
      const { data, error: e } = await supabase
        .from('app_settings')
        .select('value')
        .eq('key', 'notifications.email')
        .maybeSingle()
      if (e) throw e
      return !!(data?.value as { enabled?: boolean } | null)?.enabled
    },
  })

  /** היעדר שורה משמעו ברירת המחדל, שהיא "כן" — בדיוק כמו app.should_email. */
  const isOn = (type: string | null): boolean => {
    const exact = prefs.find((p) => p.type === type)
    if (exact) return exact.enabled
    if (type !== null) {
      const general = prefs.find((p) => p.type === null)
      if (general) return general.enabled
    }
    return true
  }

  const save = useMutation({
    mutationFn: async ({ type, enabled }: { type: string | null; enabled: boolean }) => {
      if (!profileId) throw new Error('חסר מזהה משתמש')
      const { error: e } = await supabase.from('notification_preferences').upsert(
        { profile_id: profileId, channel: 'email', type, enabled, updated_at: new Date().toISOString() },
        { onConflict: 'profile_id,channel,type' },
      )
      if (e) throw e
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['notification_preferences', profileId] }),
    onError: (e) => toast.error(errorMessage(e)),
  })

  if (isLoading) return <Skeleton className="h-72 w-full max-w-2xl" />
  if (error) return <ErrorState error={error} onRetry={() => void refetch()} />

  const allOff = isOn(null) === false

  return (
    <div className="space-y-4">
      <PageHeader title="התראות" subtitle="באילו התראות לקבל גם מייל, ולא רק פעמון במערכת" />

      {channelOn === false && (
        <Card className="max-w-2xl">
          <EmptyState
            compact
            art="alert"
            title="שליחת מייל אינה פעילה במערכת"
            description="ההעדפות כאן יישמרו ויחולו ברגע שמנהל המערכת יפעיל את הערוץ."
          />
        </Card>
      )}

      <Card className="max-w-2xl">
        <CardHeader
          title="מייל"
          subtitle="הפעמון במערכת ממשיך לעבוד בכל מקרה"
          icon={<Bell size={ICON.md} strokeWidth={STROKE} />}
        />
        <CardBody className="space-y-1">
          {/* div ולא label: Switch מרנדר label משלו, וקינון של שניים אינו חוקי */}
          <div className="flex items-center justify-between gap-4 rounded-lg px-2 py-2.5 hover:bg-hover">
            <span className="type-body font-medium">קבלת מיילים</span>
            <Switch
              checked={!allOff}
              onChange={(v) => save.mutate({ type: null, enabled: v })}
              aria-label="קבלת מיילים"
            />
          </div>

          <div className="border-t border-line-subtle pt-1">
            {TYPES.map((t) => (
              <div
                key={t.key}
                className="flex items-center justify-between gap-4 rounded-lg px-2 py-2.5 hover:bg-hover"
              >
                <span className={allOff ? 'type-body text-ink-tertiary' : 'type-body'}>{t.label}</span>
                <Switch
                  checked={!allOff && isOn(t.key)}
                  disabled={allOff}
                  onChange={(v) => save.mutate({ type: t.key, enabled: v })}
                  aria-label={t.label}
                />
              </div>
            ))}
          </div>
        </CardBody>
      </Card>
    </div>
  )
}
