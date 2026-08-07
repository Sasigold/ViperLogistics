import { useEffect, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Clock, ICON, MapPin, Plus, STROKE, Trash2 } from '../../components/ui/icons'
import {
  Button,
  Card,
  CardBody,
  CardHeader,
  Checkbox,
  Field,
  IconButton,
  Input,
  Select,
  Skeleton,
  Switch,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { fmtMoney } from '../../lib/dates'
import { useClockConfig, useOvertimeConfig, useSaveAppSetting } from './attendanceQueries'
import { fmtPayLineRate } from './shiftFormat'
import { WarehousesCard } from './WarehousesCard'
import type { ClockConfig, OvertimeConfig, OvertimeTier, PayBreakdown } from '../../types/domain'
import { errorMessage } from '../../lib/errors'

const DOW = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת']

export function OvertimeSettingsTab() {
  const toast = useToast()
  const { data: overtime, isLoading: lo } = useOvertimeConfig()
  const { data: clock, isLoading: lc } = useClockConfig()
  const saveOvertime = useSaveAppSetting('attendance.overtime')
  const saveClock = useSaveAppSetting('attendance.clock')

  const [ot, setOt] = useState<OvertimeConfig | null>(null)
  const [ck, setCk] = useState<ClockConfig | null>(null)

  useEffect(() => setOt(overtime ?? null), [overtime])
  useEffect(() => setCk(clock ?? null), [clock])

  /**
   * התצוגה המקדימה רצה על אותו preview_attendance_pay שמחשב את הדוח, ולא על
   * חישוב מקביל ב-TypeScript — מה שרואים כאן הוא בהכרח מה שישולם.
   */
  const { data: preview } = useQuery({
    queryKey: ['attendance', 'preview', ot],
    enabled: !!ot,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('preview_attendance_pay', {
        p_config: ot,
        p_vars: { hours: 11, hourly_rate: 50, dow: 1, overtime_enabled: true },
      })
      if (error) throw error
      return data as PayBreakdown
    },
  })

  if (lo || lc || !ot || !ck) return <Skeleton className="h-96 w-full" />

  const patchOt = (p: Partial<OvertimeConfig>) => setOt((c) => (c ? { ...c, ...p } : c))
  const patchCk = (p: Partial<ClockConfig>) => setCk((c) => (c ? { ...c, ...p } : c))

  // המפתח נוסף ב-0024, ולכן קונפיגורציה שנשמרה לפניו לא מכילה אותו. ברירות
  // המחדל כאן הן אותן ברירות מחדל של ה-RPC, כדי שהמסך לא יציג "כבוי" למשהו
  // שבשרת פועל.
  const selfEntry = ck.self_entry ?? { enabled: true, max_backdate_days: 14, max_hours: 16 }
  const patchSelf = (p: Partial<ClockConfig['self_entry']>) =>
    patchCk({ self_entry: { ...selfEntry, ...p } })

  const save = async () => {
    try {
      await saveOvertime.mutateAsync(ot)
      await saveClock.mutateAsync(ck)
      toast.success('ההגדרות נשמרו')
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader
          title="שעות נוספות"
          subtitle="ברירת המחדל היא חוק שעות עבודה ומנוחה; אפשר לשנות כל מדרגה"
          icon={<Clock size={ICON.md} strokeWidth={STROKE} />}
        />
        <CardBody className="space-y-5">
          <TierEditor
            title="יום רגיל"
            baseHours={ot.daily.base_hours}
            baseRate={1}
            showBaseRate={false}
            tiers={ot.daily.tiers}
            onBaseHours={(h) => patchOt({ daily: { ...ot.daily, base_hours: h } })}
            onTiers={(tiers) => patchOt({ daily: { ...ot.daily, tiers } })}
          />

          <div className="border-t border-line-subtle pt-4">
            <Field label="ימי מנוחה" hint="בימים האלה חלה טבלת המדרגות של יום המנוחה במקום הרגילה">
              <div className="flex flex-wrap gap-3">
                {DOW.map((name, i) => (
                  <Checkbox
                    key={i}
                    label={name}
                    checked={ot.rest_day.dow.includes(i)}
                    onChange={(v) =>
                      patchOt({
                        rest_day: {
                          ...ot.rest_day,
                          dow: v ? [...ot.rest_day.dow, i].sort() : ot.rest_day.dow.filter((d) => d !== i),
                        },
                      })
                    }
                  />
                ))}
              </div>
            </Field>
          </div>

          <TierEditor
            title="יום מנוחה"
            baseHours={ot.rest_day.base_hours}
            baseRate={ot.rest_day.base_rate}
            showBaseRate
            tiers={ot.rest_day.tiers}
            onBaseHours={(h) => patchOt({ rest_day: { ...ot.rest_day, base_hours: h } })}
            onBaseRate={(r) => patchOt({ rest_day: { ...ot.rest_day, base_rate: r } })}
            onTiers={(tiers) => patchOt({ rest_day: { ...ot.rest_day, tiers } })}
          />

          <div className="grid gap-4 border-t border-line-subtle pt-4 sm:grid-cols-3">
            <Field label="תקרה שבועית">
              <Switch
                checked={ot.weekly.enabled}
                onChange={(v) => patchOt({ weekly: { ...ot.weekly, enabled: v } })}
                label="פעילה"
              />
            </Field>
            <Field label="שעות בשבוע" hint="מעל זה מתווספת תוספת">
              <Input
                type="number"
                dir="ltr"
                min={0}
                step={0.5}
                disabled={!ot.weekly.enabled}
                value={ot.weekly.base_hours}
                onChange={(e) => patchOt({ weekly: { ...ot.weekly, base_hours: Number(e.target.value) } })}
              />
            </Field>
            <Field label="מכפיל שבועי">
              <Input
                type="number"
                dir="ltr"
                min={1}
                step={0.05}
                disabled={!ot.weekly.enabled}
                value={ot.weekly.rate}
                onChange={(e) => patchOt({ weekly: { ...ot.weekly, rate: Number(e.target.value) } })}
              />
            </Field>
          </div>

          <div className="grid gap-4 border-t border-line-subtle pt-4 sm:grid-cols-3">
            <Field label="עיגול שעות" hint="0 = בלי עיגול">
              <Input
                type="number"
                dir="ltr"
                min={0}
                step={1}
                value={ot.rounding.minutes}
                onChange={(e) => patchOt({ rounding: { ...ot.rounding, minutes: Number(e.target.value) } })}
              />
            </Field>
            <Field label="כיוון העיגול">
              <Select
                value={ot.rounding.mode}
                onChange={(e) =>
                  patchOt({ rounding: { ...ot.rounding, mode: e.target.value as OvertimeConfig['rounding']['mode'] } })
                }
              >
                <option value="nearest">לקרוב ביותר</option>
                <option value="up">כלפי מעלה</option>
                <option value="down">כלפי מטה</option>
              </Select>
            </Field>
            <Field
              label="השלמה לשעות"
              hint="האם שעות ההשלמה נספרות גם לצורך שעות נוספות"
            >
              <Switch
                checked={ot.top_up.counts_toward_overtime}
                onChange={(v) => patchOt({ top_up: { counts_toward_overtime: v } })}
                label="נספרת לשעות נוספות"
              />
            </Field>
          </div>

          {preview && (
            <div className="rounded-lg border border-line-subtle bg-subtle/50 p-3">
              <p className="type-overline mb-2">דוגמה: 11 שעות ביום רגיל, תעריף 50 ₪</p>
              <ul className="space-y-1">
                {(preview.lines ?? []).map((l) => (
                  <li key={l.key} className="flex items-center gap-2 type-caption">
                    <span className="flex-1">{l.label}</span>
                    <span className="tabular-nums text-ink-tertiary">
                      {fmtPayLineRate(l.hours, l.rate)}
                    </span>
                    <span className="w-20 text-end tabular-nums">{fmtMoney(l.amount)}</span>
                  </li>
                ))}
                <li className="flex items-center gap-2 border-t border-line-subtle pt-1 type-body font-semibold">
                  <span className="flex-1">סך הכול</span>
                  <span className="tabular-nums">{fmtMoney(preview.total)}</span>
                </li>
              </ul>
            </div>
          )}
        </CardBody>
      </Card>

      <Card>
        <CardHeader
          title="שעון הנוכחות"
          subtitle="ברירות מחדל לכל העובדים; אפשר לדרוס אותן פר-עובד בכרטיס העובד"
          icon={<MapPin size={ICON.md} strokeWidth={STROKE} />}
        />
        <CardBody className="space-y-4">
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <Field
              label="איחוד משמרות"
              hint="שתי משימות עם פער קטן מזה יוצגו כמשמרת אחת"
            >
              <Input
                type="number"
                dir="ltr"
                min={0}
                step={15}
                value={ck.merge_gap_minutes}
                onChange={(e) => patchCk({ merge_gap_minutes: Number(e.target.value) })}
              />
            </Field>
            <Field label="נדרש מיקום">
              <Switch
                checked={ck.requires_location}
                onChange={(v) => patchCk({ requires_location: v })}
                label="חובה להחתים מהאתר"
              />
            </Field>
            <Field label="רדיוס מותר (מטרים)">
              <Input
                type="number"
                dir="ltr"
                min={1}
                step={50}
                value={ck.location_radius_m}
                onChange={(e) => patchCk({ location_radius_m: Number(e.target.value) })}
              />
            </Field>
            <Field label="התחלה לפני המשימה">
              <Switch
                checked={ck.allow_early_clock_in}
                onChange={(v) => patchCk({ allow_early_clock_in: v })}
                label="מותר להקדים"
              />
            </Field>
            <Field label="חלון חסד (דקות)" hint="כמה מוקדם מותר גם בלי ההרשאה">
              <Input
                type="number"
                dir="ltr"
                min={0}
                step={5}
                value={ck.early_grace_minutes}
                onChange={(e) => patchCk({ early_grace_minutes: Number(e.target.value) })}
              />
            </Field>
            <Field label="החתמה בלי משמרת">
              <Switch
                checked={ck.allow_clock_without_shift}
                onChange={(v) => patchCk({ allow_clock_without_shift: v })}
                label="מותר גם בלי שיבוץ"
              />
            </Field>
            <Field label="סגירה אוטומטית (שעות)" hint="משמרת שנשכחה פתוחה תיסגר אחרי הזמן הזה">
              <Input
                type="number"
                dir="ltr"
                min={1}
                value={ck.auto_close_after_hours}
                onChange={(e) => patchCk({ auto_close_after_hours: Number(e.target.value) })}
              />
            </Field>
            <Field label="דיוק מיקום מרבי (מטרים)" hint="קריאה גסה מזה מסומנת ולא נחסמת">
              <Input
                type="number"
                dir="ltr"
                min={1}
                step={50}
                value={ck.max_accuracy_m}
                onChange={(e) => patchCk({ max_accuracy_m: Number(e.target.value) })}
              />
            </Field>
          </div>

          {/* דיווח ידני של עובד הוא פתח המילוט לשעון שלא עבד. הוא נכתב
              כ"ממתין לאישור" ואינו נספר בשעות עד שמנהל מכריע, ולכן ההגדרות
              כאן הן על היקף הדיווח ולא על מי סופר אותו. */}
          <div className="grid gap-4 border-t border-line-subtle pt-4 sm:grid-cols-2 lg:grid-cols-3">
            <Field label="דיווח משמרת ידני" hint="עובד מדווח משמרת שלא הוחתמה, לאישור מנהל">
              <Switch
                checked={selfEntry.enabled}
                onChange={(v) => patchSelf({ enabled: v })}
                label="מותר לעובדים"
              />
            </Field>
            <Field label="חלון דיווח (ימים אחורה)" hint="מעבר לזה רק מנהל מזין">
              <Input
                type="number"
                dir="ltr"
                min={1}
                step={1}
                disabled={!selfEntry.enabled}
                value={selfEntry.max_backdate_days}
                onChange={(e) => patchSelf({ max_backdate_days: Number(e.target.value) })}
              />
            </Field>
            <Field label="אורך משמרת מרבי (שעות)">
              <Input
                type="number"
                dir="ltr"
                min={1}
                step={1}
                disabled={!selfEntry.enabled}
                value={selfEntry.max_hours}
                onChange={(e) => patchSelf({ max_hours: Number(e.target.value) })}
              />
            </Field>
          </div>
        </CardBody>
      </Card>

      {/* המחסנים הם ישות משלהם: משמרת שמתחילה במחסן נמדדת מול המחסן שהמשימה
          נוקבת בו, ואם לא נקבה — מול הקרוב ביותר לעובד. */}
      <WarehousesCard />

      <div className="flex justify-end">
        <Button
          variant="primary"
          loading={saveOvertime.isPending || saveClock.isPending}
          onClick={() => void save()}
        >
          שמירת ההגדרות
        </Button>
      </div>
    </div>
  )
}

/**
 * מדרגה עם hours=null פירושה "וכל מה שמעל", ולכן היא תמיד האחרונה ואי אפשר
 * להזין לה מספר שעות — אותה מוסכמה של מדרגות התמחור.
 */
function TierEditor({
  title,
  baseHours,
  baseRate,
  showBaseRate,
  tiers,
  onBaseHours,
  onBaseRate,
  onTiers,
}: {
  title: string
  baseHours: number
  baseRate: number
  showBaseRate: boolean
  tiers: OvertimeTier[]
  onBaseHours: (h: number) => void
  onBaseRate?: (r: number) => void
  onTiers: (t: OvertimeTier[]) => void
}) {
  return (
    <div className="space-y-3">
      <p className="type-overline">{title}</p>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="שעות בסיס">
          <Input
            type="number"
            dir="ltr"
            min={0}
            step={0.5}
            value={baseHours}
            onChange={(e) => onBaseHours(Number(e.target.value))}
          />
        </Field>
        {showBaseRate && (
          <Field label="מכפיל הבסיס">
            <Input
              type="number"
              dir="ltr"
              min={1}
              step={0.05}
              value={baseRate}
              onChange={(e) => onBaseRate?.(Number(e.target.value))}
            />
          </Field>
        )}
      </div>
      <div className="space-y-2">
        {tiers.map((t, i) => (
          <div key={i} className="flex items-end gap-2">
            <Field label={i === 0 ? 'שעות במדרגה' : ''} className="flex-1">
              <Input
                type="number"
                dir="ltr"
                min={0}
                step={0.5}
                placeholder="כל השאר"
                value={t.hours ?? ''}
                onChange={(e) =>
                  onTiers(
                    tiers.map((x, j) =>
                      j === i ? { ...x, hours: e.target.value ? Number(e.target.value) : null } : x,
                    ),
                  )
                }
              />
            </Field>
            <Field label={i === 0 ? 'מכפיל' : ''} className="w-32">
              <Input
                type="number"
                dir="ltr"
                min={1}
                step={0.05}
                value={t.rate}
                onChange={(e) =>
                  onTiers(tiers.map((x, j) => (j === i ? { ...x, rate: Number(e.target.value) } : x)))
                }
              />
            </Field>
            <IconButton
              label="מחיקת מדרגה"
              onClick={() => onTiers(tiers.filter((_, j) => j !== i))}
            >
              <Trash2 size={ICON.md} strokeWidth={STROKE} />
            </IconButton>
          </div>
        ))}
        <Button size="sm" onClick={() => onTiers([...tiers, { hours: 2, rate: 1.25 }])}>
          <Plus size={ICON.sm} strokeWidth={STROKE} />
          מדרגה
        </Button>
      </div>
    </div>
  )
}
