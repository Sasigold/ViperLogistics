import { Bell, Check, ICON, Mail, STROKE, Smartphone, Trash2 } from '../../components/ui/icons'
import {
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  ErrorState,
  IconButton,
  PageHeader,
  Skeleton,
  Tooltip,
  fmtRelative,
  useToast,
} from '../../components/ui'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { errorMessage } from '../../lib/errors'
import { describeDevice, pushBlockedReason, pushSupported } from '../../lib/push'
import { CHANNELS, useMyDevices, useMyNotificationSettings, usePushConfig } from './notificationQueries'
import { useDisablePush, useEnablePush, useForgetDevice } from './pushQueries'
import type { NotificationChannel, NotificationSetting } from '../../types/domain'

/**
 * אילו התראות מגיעות אליי — ולמה. מסך קריאה בלבד.
 *
 * ההחלטה מה נשלח שייכת למנהל המערכת, ולו בלבד: הוא קובע אותה פר-קהל
 * (מטריצת המדיניות) ופר-אדם (חריג אישי), בלשונית ההתראות שבהגדרות. עד 0086
 * הייתה כאן שכבה נוספת — ההעדפה האישית — וכל עובד יכול היה לכבות לעצמו
 * שיבוץ למשמרת. זה בדיוק מה שנתבקש להיסגר: התראה שמישהו כיבה לעצמו לפני
 * חצי שנה היא הסיבה הנפוצה ל"למה הוא לא ידע שהוא משובץ".
 *
 * המסך נשאר, ואינו מתרוקן, משתי סיבות: לדעת מה יגיע אליך זה מידע שימושי
 * (וגם מונע פניות), ורישום המכשיר ל-push חייב להיעשות מהדפדפן של המשתמש —
 * זו הרשאת דפדפן ולא העדפה.
 *
 * רשימת הסוגים מגיעה מ-my_notification_settings ולא מקבוע בקובץ הזה: סוג
 * חדש מופיע כאן מפני שהוא נרשם בקטלוג, ולא מפני שמישהו זכר לעדכן TSX.
 */
export default function NotificationPreferencesPage() {
  return (
    <RequirePermission perm={PERM.NOTIFICATIONS_PREFERENCES}>
      <Preferences />
    </RequirePermission>
  )
}

const CHANNEL_ICON: Record<NotificationChannel, typeof Bell> = {
  inapp: Bell,
  email: Mail,
  push: Smartphone,
}

function Preferences() {
  const { data: settings = [], isLoading, error, refetch } = useMyNotificationSettings()

  if (isLoading) return <Skeleton className="h-96 w-full max-w-3xl" />
  if (error) return <ErrorState error={error} onRetry={() => void refetch()} />

  // הקיבוץ נשען על סדר ה-RPC (sort_order), ולכן קבוצה נשארת רציפה
  const groups: { name: string; rows: NotificationSetting[] }[] = []
  for (const s of settings) {
    const last = groups[groups.length - 1]
    if (last && last.name === s.group_he) last.rows.push(s)
    else groups.push({ name: s.group_he, rows: [s] })
  }

  const offChannels = CHANNELS.filter(
    (c) => c.key !== 'inapp' && settings.some((s) => !s.channels[c.key].channel_enabled),
  )

  return (
    <div className="space-y-4">
      <PageHeader title="התראות" subtitle="אילו התראות מגיעות אליי, ובאילו ערוצים" />

      <Card className="max-w-3xl">
        <EmptyState
          compact
          art="alert"
          title="ההתראות נקבעות על ידי מנהל המערכת"
          description="הרשימה כאן היא מה שיגיע אליך בפועל. לשינוי — פנו למנהל המערכת."
        />
      </Card>

      {offChannels.length > 0 && (
        <Card className="max-w-3xl">
          <EmptyState
            compact
            art="alert"
            title={`${offChannels.map((c) => c.label).join(' ו')} אינם פעילים במערכת`}
            description="ההתראות בערוצים האלה לא יישלחו עד שמנהל המערכת יפעיל אותם."
          />
        </Card>
      )}

      <PushDevicesCard />

      {groups.map((g) => (
        <Card key={g.name} className="max-w-3xl">
          <CardHeader title={g.name} icon={<Bell size={ICON.md} strokeWidth={STROKE} />} />
          <CardBody className="p-0">
            {/* כותרת העמודות. מוסתרת בנייד, שם כל ערוץ נושא אייקון משלו. */}
            <div className="hidden items-center gap-4 border-b border-line-subtle px-4 py-2 sm:flex">
              <span className="flex-1" />
              {CHANNELS.map((c) => (
                <span key={c.key} className="w-24 text-center type-caption text-ink-tertiary">
                  {c.label}
                </span>
              ))}
            </div>

            {g.rows.map((row) => (
              <div
                key={row.type}
                className="flex flex-col gap-2 border-b border-line-subtle px-4 py-3 last:border-0 sm:flex-row sm:items-center sm:gap-4"
              >
                <div className="flex-1">
                  <p className="type-body font-medium">{row.label_he}</p>
                  {row.description_he && (
                    <p className="mt-0.5 type-caption text-ink-tertiary">{row.description_he}</p>
                  )}
                </div>

                <div className="flex items-center gap-4">
                  {CHANNELS.map((c) => {
                    const cell = row.channels[c.key]
                    const Icon = CHANNEL_ICON[c.key]
                    return (
                      <div
                        key={c.key}
                        className="flex w-24 items-center justify-center gap-1.5 sm:justify-center"
                      >
                        <Icon
                          size={ICON.sm}
                          strokeWidth={STROKE}
                          aria-hidden
                          className="text-ink-tertiary sm:hidden"
                        />
                        <ChannelCell
                          label={`${row.label_he} — ${c.label}`}
                          mode={cell.mode}
                          enabled={cell.enabled}
                          channelOff={!cell.channel_enabled}
                        />
                      </div>
                    )
                  })}
                </div>
              </div>
            ))}
          </CardBody>
        </Card>
      ))}
    </div>
  )
}

/**
 * תא בודד — סימן ולא מתג.
 *
 * מתג מרמז שאפשר להזיז אותו, וכאן אי אפשר: ההחלטה כולה של מנהל המערכת. לכן
 * שני מצבים בלבד, "מגיע" ו"לא מגיע", וההסבר *למה* יושב ב-tooltip כדי שמי
 * שמצפה להתראה שאינה מגיעה יידע אם זה הערוץ, המדיניות, או שניהם.
 */
function ChannelCell({
  label,
  mode,
  enabled,
  channelOff,
}: {
  label: string
  mode: string
  enabled: boolean
  channelOff: boolean
}) {
  const why = channelOff
    ? 'הערוץ אינו פעיל במערכת'
    : mode === 'off'
      ? 'ההתראה הזו כבויה במערכת'
      : enabled
        ? 'מנהל המערכת קבע שההתראה הזו נשלחת אליך'
        : 'מנהל המערכת קבע שההתראה הזו אינה נשלחת אליך'

  return (
    <Tooltip content={why}>
      <span
        className={enabled && !channelOff ? 'text-success-text' : 'text-ink-tertiary'}
        aria-label={`${label}: ${enabled && !channelOff ? 'מגיע אליי' : 'לא מגיע'} — ${why}`}
      >
        {enabled && !channelOff ? <Check size={ICON.md} strokeWidth={STROKE} aria-hidden /> : '—'}
      </span>
    </Tooltip>
  )
}

/**
 * המכשירים של המשתמש.
 *
 * מכונת מצבים קטנה, וכל ענף בה קיים בגלל מקרה אמיתי — בראשם iOS, שמאפשר
 * ‏Web Push רק לאפליקציה מותקנת. בלי ההסבר הזה המשתמש היה לוחץ על כפתור
 * שנראה תקין ולא קורה בו דבר.
 */
function PushDevicesCard() {
  const toast = useToast()
  const { data: cfg } = usePushConfig()
  const { data: devices = [] } = useMyDevices()
  const enable = useEnablePush()
  const disable = useDisablePush()
  const forget = useForgetDevice()

  const blocked = pushBlockedReason()
  const supported = pushSupported()
  const granted = supported && typeof Notification !== 'undefined' && Notification.permission === 'granted'

  return (
    <Card className="max-w-3xl">
      <CardHeader
        title="המכשירים שלי"
        subtitle="התראות שמגיעות גם כשהאפליקציה סגורה"
        icon={<Smartphone size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody className="space-y-3">
        {cfg?.enabled === false && (
          <p className="type-caption text-ink-tertiary">
            ערוץ ההתראות למכשיר אינו פעיל במערכת. אפשר לרשום מכשיר כבר עכשיו, וההתראות יתחילו
            להגיע ברגע שמנהל המערכת יפעיל אותו.
          </p>
        )}

        {blocked ? (
          <p className="rounded-lg bg-subtle/60 px-3 py-2.5 type-body text-ink-secondary">{blocked}</p>
        ) : (
          <div className="flex flex-wrap items-center gap-2">
            <Button
              variant="primary"
              size="sm"
              disabled={enable.isPending}
              onClick={() =>
                enable.mutate(undefined, {
                  onSuccess: () => toast.success('המכשיר הזה יקבל התראות'),
                  onError: (e) => toast.error(errorMessage(e)),
                })
              }
            >
              {granted && devices.length > 0 ? 'רישום מחדש של המכשיר הזה' : 'הפעלת התראות במכשיר הזה'}
            </Button>
            {granted && (
              <Button
                variant="ghost"
                size="sm"
                disabled={disable.isPending}
                onClick={() =>
                  disable.mutate(undefined, {
                    onSuccess: () => toast.success('המכשיר הזה כבר לא יקבל התראות'),
                    onError: (e) => toast.error(errorMessage(e)),
                  })
                }
              >
                כיבוי במכשיר הזה
              </Button>
            )}
          </div>
        )}

        {devices.length === 0 ? (
          <p className="type-caption text-ink-tertiary">אין עדיין מכשירים רשומים.</p>
        ) : (
          <ul className="divide-y divide-line-subtle rounded-lg border border-line-subtle">
            {devices.map((d) => (
              <li key={d.id} className="flex items-center gap-2 px-3 py-2.5">
                <Smartphone
                  size={ICON.sm}
                  strokeWidth={STROKE}
                  aria-hidden
                  className="shrink-0 text-ink-tertiary"
                />
                <div className="min-w-0 flex-1">
                  <p className="truncate type-body">{describeDevice(d.user_agent)}</p>
                  <p className="type-caption text-ink-tertiary">
                    פעיל לאחרונה {fmtRelative(d.last_seen_at)}
                  </p>
                </div>
                {d.failure_count > 0 && (
                  <Badge tone="warning">{d.failure_count} כשלים</Badge>
                )}
                <IconButton
                  label="ניתוק המכשיר"
                  size="sm"
                  onClick={() =>
                    forget.mutate(d.id, { onError: (e) => toast.error(errorMessage(e)) })
                  }
                >
                  <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                </IconButton>
              </li>
            ))}
          </ul>
        )}
      </CardBody>
    </Card>
  )
}
