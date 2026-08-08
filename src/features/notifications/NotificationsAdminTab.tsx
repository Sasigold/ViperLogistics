import { useEffect, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Bell, ICON, Mail, STROKE, Smartphone } from '../../components/ui/icons'
import {
  Card,
  CardBody,
  CardHeader,
  Checkbox,
  Field,
  Input,
  SegmentedControl,
  Select,
  Skeleton,
  Switch,
  Tooltip,
  cx,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useSaveAppSetting } from '../attendance/attendanceQueries'
import { errorMessage } from '../../lib/errors'
import {
  AUDIENCES,
  CHANNELS,
  MODES,
  useEmailConfig,
  useNotificationOverrides,
  useNotificationPolicies,
  useNotificationTypes,
  useOverriddenProfiles,
  usePushConfig,
  usePushStats,
  useSaveOverride,
  useSavePolicy,
  useUserNotificationSettings,
} from './notificationQueries'
import type {
  NotificationAudience,
  NotificationChannel,
  NotificationMode,
  NotificationType,
} from '../../types/domain'

/**
 * מסך הניהול של ההתראות.
 *
 * שלושה כרטיסים, ובכוונה בסדר הזה: קודם *האם* ערוץ בכלל פועל, אחר כך מה
 * כל קהל מקבל, ורק בסוף היוצאים מן הכלל. מנהל שמסתכל על המטריצה בלי לדעת
 * שהערוץ כבוי היה מגדיר שם דברים ותוהה למה דבר לא קורה.
 */
export function NotificationsAdminTab() {
  const { data: types = [], isLoading } = useNotificationTypes()
  if (isLoading) return <Skeleton className="h-96 w-full" />
  return (
    <div className="space-y-4">
      <ChannelsCard types={types} />
      <PolicyMatrix types={types} />
      <UserOverrides types={types} />
    </div>
  )
}

/** מפתח הגדרות אחד, עם טיוטה מקומית ושמירה מפורשת — כמו OvertimeSettingsTab. */
function ChannelsCard({ types }: { types: NotificationType[] }) {
  const toast = useToast()
  const { data: email } = useEmailConfig()
  const { data: push } = usePushConfig()
  const { data: stats } = usePushStats()
  const saveEmail = useSaveAppSetting('notifications.email')
  const savePush = useSaveAppSetting('notifications.push')

  const [from, setFrom] = useState('')
  const [vapid, setVapid] = useState('')
  useEffect(() => setFrom(email?.from ?? ''), [email?.from])
  useEffect(() => setVapid(push?.vapid_public_key ?? ''), [push?.vapid_public_key])

  if (!email || !push) return <Skeleton className="h-64 w-full" />

  const totalDevices = Object.values(stats ?? {}).reduce((n, v) => n + v.devices, 0)
  const totalPeople = Object.values(stats ?? {}).reduce((n, v) => n + v.people, 0)

  const patchEmail = (p: Partial<typeof email>) =>
    saveEmail.mutate({ ...email, ...p }, { onError: (e) => toast.error(errorMessage(e)) })
  const patchPush = (p: Partial<typeof push>) =>
    savePush.mutate({ ...push, ...p }, { onError: (e) => toast.error(errorMessage(e)) })

  const toggleMute = (cfg: 'email' | 'push', key: string, muted: boolean) => {
    const cur = cfg === 'email' ? email.muted_types : push.muted_types
    const next = muted ? [...new Set([...cur, key])] : cur.filter((t) => t !== key)
    if (cfg === 'email') patchEmail({ muted_types: next })
    else patchPush({ muted_types: next })
  }

  return (
    <Card>
      <CardHeader
        title="ערוצים"
        subtitle="הפעמון פועל תמיד. שני האחרים נדלקים כאן"
        icon={<Bell size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody className="space-y-5">
        {/* מייל */}
        <section className="space-y-3">
          <div className="flex items-center justify-between gap-4">
            <span className="flex items-center gap-2 type-body font-medium">
              <Mail size={ICON.sm} strokeWidth={STROKE} aria-hidden />
              מייל
            </span>
            <Switch
              checked={email.enabled}
              onChange={(v) => patchEmail({ enabled: v })}
              aria-label="הפעלת ערוץ המייל"
            />
          </div>
          <Field label="כתובת השולח" hint="למשל: ViperLogistics &lt;noreply@yourdomain.com&gt;">
            <Input
              value={from}
              dir="ltr"
              onChange={(e) => setFrom(e.target.value)}
              onBlur={() => from !== email.from && patchEmail({ from })}
            />
          </Field>
        </section>

        {/* push */}
        <section className="space-y-3 border-t border-line-subtle pt-4">
          <div className="flex items-center justify-between gap-4">
            <span className="flex items-center gap-2 type-body font-medium">
              <Smartphone size={ICON.sm} strokeWidth={STROKE} aria-hidden />
              התראה למכשיר
            </span>
            <Switch
              checked={push.enabled}
              onChange={(v) => patchPush({ enabled: v })}
              aria-label="הפעלת ערוץ ההתראות למכשיר"
            />
          </div>
          <Field
            label="מפתח VAPID ציבורי"
            hint="המפתח הפרטי אינו נשמר כאן אלא במשתני הסביבה של notify-dispatch. ראו README."
          >
            <Input
              value={vapid}
              dir="ltr"
              className="font-mono"
              onChange={(e) => setVapid(e.target.value)}
              onBlur={() => vapid !== push.vapid_public_key && patchPush({ vapid_public_key: vapid })}
            />
          </Field>
          {totalDevices > 0 && (
            <p className="type-caption text-ink-tertiary">
              {totalDevices} מכשירים רשומים אצל {totalPeople} אנשים
            </p>
          )}
        </section>

        {/* השתקה גלובלית */}
        <section className="space-y-2 border-t border-line-subtle pt-4">
          <p className="type-body font-medium">סוגים שלא יישלחו בערוץ, יהיה מה שיהיה</p>
          <p className="type-caption text-ink-tertiary">
            גובר על המטריצה ועל בחירת המשתמש. שימושי להשתקה מהירה של סוג רועש.
          </p>
          <div className="grid gap-1 sm:grid-cols-2">
            {types.map((t) => (
              <div key={t.key} className="flex items-center gap-4 rounded-lg px-2 py-1.5 hover:bg-hover">
                <span className="flex-1 truncate type-caption">{t.label_he}</span>
                <Checkbox
                  checked={email.muted_types.includes(t.key)}
                  onChange={(v) => toggleMute('email', t.key, v)}
                  label="מייל"
                />
                <Checkbox
                  checked={push.muted_types.includes(t.key)}
                  onChange={(v) => toggleMute('push', t.key, v)}
                  label="מכשיר"
                />
              </div>
            ))}
          </div>
        </section>
      </CardBody>
    </Card>
  )
}

/** ברירת המחדל של תא, כשאין שורת מדיניות — משקף app.notification_default_mode. */
function defaultMode(t: NotificationType, channel: NotificationChannel): NotificationMode {
  return channel === 'inapp'
    ? t.default_mode_inapp
    : channel === 'email'
      ? t.default_mode_email
      : t.default_mode_push
}

/**
 * המטריצה.
 *
 * קהל אחד בכל פעם, ולא רשת אחת ענקית: תשעה סוגים × שלושה ערוצים × ארבעה
 * קהלים הם 108 פקדים, שאינם קריאים בטלפון ב-RTL. עם בורר קהל זה 27.
 */
function PolicyMatrix({ types }: { types: NotificationType[] }) {
  const toast = useToast()
  const [audience, setAudience] = useState<NotificationAudience>('staff')
  const { data: policies = [], isLoading } = useNotificationPolicies()
  const save = useSavePolicy()

  if (isLoading) return <Skeleton className="h-96 w-full" />

  const modeOf = (t: NotificationType, ch: NotificationChannel): NotificationMode =>
    policies.find((p) => p.audience === audience && p.type === t.key && p.channel === ch)?.mode ??
    defaultMode(t, ch)

  const isExplicit = (t: NotificationType, ch: NotificationChannel) =>
    policies.some((p) => p.audience === audience && p.type === t.key && p.channel === ch)

  const rows = types.filter((t) => t.audiences.includes(audience))

  return (
    <Card>
      <CardHeader
        title="מי מקבל מה"
        subtitle="ברירת המחדל לכל קהל, ומה נעול מפני שינוי"
        icon={<Bell size={ICON.md} strokeWidth={STROKE} />}
        actions={
          <SegmentedControl
            items={AUDIENCES.map((a) => ({ key: a.key, label: a.label }))}
            value={audience}
            onChange={setAudience}
          />
        }
      />
      <CardBody className="p-0">
        {rows.length === 0 ? (
          <p className="px-4 py-6 text-center type-body text-ink-tertiary">
            אין סוגי התראה שרלוונטיים לקהל הזה.
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[36rem]">
              <thead>
                <tr className="border-b border-line-subtle">
                  <th className="px-4 py-2 text-start type-caption font-normal text-ink-tertiary">
                    סוג ההתראה
                  </th>
                  {CHANNELS.map((c) => (
                    <th
                      key={c.key}
                      className="px-3 py-2 text-start type-caption font-normal text-ink-tertiary"
                    >
                      {c.label}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map((t) => (
                  <tr key={t.key} className="border-b border-line-subtle last:border-0">
                    <td className="px-4 py-2.5">
                      <p className="type-body">{t.label_he}</p>
                      <p className="type-caption text-ink-tertiary">{t.group_he}</p>
                    </td>
                    {CHANNELS.map((c) => {
                      const mode = modeOf(t, c.key)
                      const explicit = isExplicit(t, c.key)
                      return (
                        <td key={c.key} className="px-3 py-2.5">
                          <Select
                            selectSize="sm"
                            value={mode}
                            className={cx('w-44', !explicit && 'text-ink-secondary')}
                            onChange={(e) => {
                              const next = e.target.value as NotificationMode
                              save.mutate(
                                {
                                  audience,
                                  type: t.key,
                                  channel: c.key,
                                  mode: next,
                                  // חזרה לברירת המחדל מוחקת את השורה
                                  isDefault: next === defaultMode(t, c.key),
                                },
                                { onError: (err) => toast.error(errorMessage(err)) },
                              )
                            }}
                          >
                            {MODES.map((m) => (
                              <option key={m.key} value={m.key}>
                                {m.label}
                                {m.key === defaultMode(t, c.key) ? ' (ברירת מחדל)' : ''}
                              </option>
                            ))}
                          </Select>
                        </td>
                      )
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </CardBody>
    </Card>
  )
}

/**
 * חריגים לאדם בודד.
 *
 * רשימת מי שיש לו חריג מוצגת למעלה בכוונה: חריג שנקבע פעם אחת בטלפון ונשכח
 * הוא בדיוק הדבר שגורם ל"למה הוא לא מקבל התראות" חצי שנה אחר כך.
 */
function UserOverrides({ types }: { types: NotificationType[] }) {
  const toast = useToast()
  const [profileId, setProfileId] = useState<string>('')
  const { data: people = [] } = useQuery({
    queryKey: ['profiles', 'notification-overrides'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('profiles')
        .select('id, full_name, user_kind')
        .is('deleted_at', null)
        .eq('is_active', true)
        .order('full_name')
      if (error) throw error
      return data as { id: string; full_name: string; user_kind: string }[]
    },
  })
  const { data: withOverrides = [] } = useOverriddenProfiles()
  const { data: settings = [] } = useUserNotificationSettings(profileId || null)
  const { data: overrides = [] } = useNotificationOverrides(profileId || null)
  const save = useSaveOverride()

  const rows = types.filter((t) => settings.some((s) => s.type === t.key))

  return (
    <Card>
      <CardHeader
        title="חריגים אישיים"
        subtitle="לכבות או לכפות התראה לאדם אחד, בלי לשנות מדיניות לכל הקהל"
      />
      <CardBody className="space-y-4">
        {withOverrides.length > 0 && (
          <p className="type-caption text-ink-tertiary">
            חריגים מוגדרים כרגע ל: {withOverrides.map((p) => p.name).join(', ')}
          </p>
        )}

        <Field label="משתמש">
          <Select value={profileId} onChange={(e) => setProfileId(e.target.value)}>
            <option value="">בחרו משתמש…</option>
            {people.map((p) => (
              <option key={p.id} value={p.id}>
                {p.full_name}
              </option>
            ))}
          </Select>
        </Field>

        {profileId && (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[36rem]">
              <thead>
                <tr className="border-b border-line-subtle">
                  <th className="px-2 py-2 text-start type-caption font-normal text-ink-tertiary">
                    סוג ההתראה
                  </th>
                  {CHANNELS.map((c) => (
                    <th
                      key={c.key}
                      className="px-2 py-2 text-start type-caption font-normal text-ink-tertiary"
                    >
                      {c.label}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map((t) => {
                  const resolved = settings.find((s) => s.type === t.key)
                  return (
                    <tr key={t.key} className="border-b border-line-subtle last:border-0">
                      <td className="px-2 py-2.5 type-body">{t.label_he}</td>
                      {CHANNELS.map((c) => {
                        const ov = overrides.find((o) => o.type === t.key && o.channel === c.key)
                        const effective = resolved?.channels[c.key].mode
                        return (
                          <td key={c.key} className="px-2 py-2.5">
                            <Tooltip
                              content={ov ? 'חריג אישי' : `לפי המדיניות: ${labelOfMode(effective)}`}
                            >
                              <Select
                                selectSize="sm"
                                className={cx('w-40', !ov && 'text-ink-secondary')}
                                value={ov?.mode ?? ''}
                                onChange={(e) =>
                                  save.mutate(
                                    {
                                      profileId,
                                      type: t.key,
                                      channel: c.key,
                                      mode: (e.target.value || null) as NotificationMode | null,
                                    },
                                    { onError: (err) => toast.error(errorMessage(err)) },
                                  )
                                }
                              >
                                <option value="">לפי המדיניות</option>
                                {MODES.map((m) => (
                                  <option key={m.key} value={m.key}>
                                    {m.label}
                                  </option>
                                ))}
                              </Select>
                            </Tooltip>
                          </td>
                        )
                      })}
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </CardBody>
    </Card>
  )
}

function labelOfMode(mode: NotificationMode | undefined): string {
  return MODES.find((m) => m.key === mode)?.label ?? '—'
}
