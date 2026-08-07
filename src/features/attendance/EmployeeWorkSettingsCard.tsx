import { useEffect, useState } from 'react'
import { Banknote, Clock, ICON, STROKE } from '../../components/ui/icons'
import { Button, Card, CardBody, CardHeader, Field, Input, Select, Skeleton, Switch, useToast } from '../../components/ui'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { useSaveWorkerPaySettings, useWorkerPaySettings } from './attendanceQueries'
import type { WorkerPaySettings } from '../../types/domain'
import { errorMessage } from '../../lib/errors'

/** '' במסך = NULL במסד = "לך לפי ההגדרה הגלובלית". */
const TRI = [
  { value: '', label: 'לפי ההגדרה הכללית' },
  { value: 'true', label: 'כן' },
  { value: 'false', label: 'לא' },
]
const triValue = (v: boolean | null | undefined) => (v == null ? '' : String(v))
const triParse = (v: string): boolean | null => (v === '' ? null : v === 'true')

/**
 * שני סקשנים בכרטיס אחד, כל אחד עם המפתח שלו: שכר תחת attendance.manage_pay
 * ושעון תחת attendance.manage_clock. הכרטיס נשמר בנפרד מטופס הפרופיל בכוונה —
 * הוא כותב לטבלה אחרת מאחורי הרשאה אחרת, ואיחוד השמירות היה מפיל את שמירת
 * הפרופיל כולה בגלל עמודה אחת שנדחתה.
 */
export function EmployeeWorkSettingsCard({ profileId }: { profileId: string }) {
  const toast = useToast()
  const has = useAuth((s) => s.has)
  const canPay = has(PERM.ATTENDANCE_MANAGE_PAY)
  const canClock = has(PERM.ATTENDANCE_MANAGE_CLOCK)
  const { data, isLoading } = useWorkerPaySettings(profileId)
  const save = useSaveWorkerPaySettings(profileId)

  const [form, setForm] = useState<Partial<WorkerPaySettings>>({})

  useEffect(() => {
    setForm(
      data ?? {
        hourly_rate: null,
        overtime_enabled: true,
        min_hours_per_shift: null,
        travel_paid: true,
        clock_enabled: null,
        requires_location: null,
        location_radius_m: null,
        allow_early_clock_in: null,
        early_grace_minutes: null,
        allow_clock_without_shift: null,
      },
    )
  }, [data])

  if (!canPay && !canClock) return null
  if (isLoading) return <Skeleton className="h-64 w-full" />

  const set = (patch: Partial<WorkerPaySettings>) => setForm((f) => ({ ...f, ...patch }))
  const num = (v: string) => (v === '' ? null : Number(v))

  return (
    <Card>
      <CardHeader
        title="שכר ונוכחות"
        subtitle="תעריף שעתי, שעות נוספות והגדרות שעון הנוכחות של העובד"
        icon={<Banknote size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody className="space-y-5">
        {canPay && (
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="סכום לשעה" hint="ריק = לא מחושב שכר לעובד הזה">
              <Input
                type="number"
                dir="ltr"
                min={0}
                step={0.5}
                value={form.hourly_rate ?? ''}
                onChange={(e) => set({ hourly_rate: num(e.target.value) })}
              />
            </Field>
            <Field label="השלמה לשעות" hint="משמרת קצרה מזה משולמת כאילו נמשכה כך">
              <Input
                type="number"
                dir="ltr"
                min={0}
                max={24}
                step={0.5}
                placeholder="ללא"
                value={form.min_hours_per_shift ?? ''}
                onChange={(e) => set({ min_hours_per_shift: num(e.target.value) })}
              />
            </Field>
            <Field label="זכאי לשעות נוספות">
              <Switch
                checked={form.overtime_enabled ?? true}
                onChange={(v) => set({ overtime_enabled: v })}
                label={form.overtime_enabled ?? true ? 'מדרגות שעות נוספות חלות' : 'הכול בתעריף רגיל'}
              />
            </Field>
            <Field label="זמן נסיעה בתשלום">
              <Switch
                checked={form.travel_paid ?? true}
                onChange={(v) => set({ travel_paid: v })}
                label="נכלל במשמרת"
              />
            </Field>
          </div>
        )}

        {canClock && (
          <div className="space-y-4 border-t border-line-subtle pt-4">
            <p className="flex items-center gap-1.5 type-overline">
              <Clock size={ICON.sm} strokeWidth={STROKE} />
              שעון נוכחות
            </p>
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="נדרש מיקום" hint="החתמה מחוץ לטווח תידחה">
                <Select
                  value={triValue(form.requires_location)}
                  onChange={(e) => set({ requires_location: triParse(e.target.value) })}
                >
                  {TRI.map((o) => (
                    <option key={o.value} value={o.value}>
                      {o.label}
                    </option>
                  ))}
                </Select>
              </Field>
              <Field label="רדיוס מותר (מטרים)" hint="ריק = לפי ההגדרה הכללית">
                <Input
                  type="number"
                  dir="ltr"
                  min={1}
                  step={50}
                  value={form.location_radius_m ?? ''}
                  onChange={(e) => set({ location_radius_m: num(e.target.value) })}
                />
              </Field>
              <Field label="התחלת משמרת לפני המשימה">
                <Select
                  value={triValue(form.allow_early_clock_in)}
                  onChange={(e) => set({ allow_early_clock_in: triParse(e.target.value) })}
                >
                  {TRI.map((o) => (
                    <option key={o.value} value={o.value}>
                      {o.label}
                    </option>
                  ))}
                </Select>
              </Field>
              <Field label="חלון חסד (דקות)" hint="כמה מוקדם מותר גם בלי ההרשאה">
                <Input
                  type="number"
                  dir="ltr"
                  min={0}
                  step={5}
                  value={form.early_grace_minutes ?? ''}
                  onChange={(e) => set({ early_grace_minutes: num(e.target.value) })}
                />
              </Field>
              <Field label="החתמה בלי משמרת משובצת">
                <Select
                  value={triValue(form.allow_clock_without_shift)}
                  onChange={(e) => set({ allow_clock_without_shift: triParse(e.target.value) })}
                >
                  {TRI.map((o) => (
                    <option key={o.value} value={o.value}>
                      {o.label}
                    </option>
                  ))}
                </Select>
              </Field>
              <Field label="שעון פעיל">
                <Select
                  value={triValue(form.clock_enabled)}
                  onChange={(e) => set({ clock_enabled: triParse(e.target.value) })}
                >
                  {TRI.map((o) => (
                    <option key={o.value} value={o.value}>
                      {o.label}
                    </option>
                  ))}
                </Select>
              </Field>
            </div>
          </div>
        )}

        <div className="flex justify-end">
          <Button
            variant="primary"
            size="sm"
            loading={save.isPending}
            onClick={() =>
              save.mutate(form, {
                onSuccess: () => toast.success('ההגדרות נשמרו'),
                onError: (e) => toast.error(errorMessage(e)),
              })
            }
          >
            שמירה
          </Button>
        </div>
      </CardBody>
    </Card>
  )
}
