import { useEffect, useMemo, useState } from 'react'
import { Eye, EyeOff, Fuel, ICON, STROKE } from '../../components/ui/icons'
import {
  Card,
  CardBody,
  CardHeader,
  Field,
  IconButton,
  Input,
  Skeleton,
  StickySaveBar,
  Textarea,
  useToast,
} from '../../components/ui'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { errorMessage } from '../../lib/errors'
import type { Vehicle, VehicleFuelCard } from '../../types/domain'
import { useSaveFuelCard, useVehicleFuelCard } from './vehicleQueries'

const BLANK = { provider: '', card_number: '', pin_code: '', valid_until: '', note: '' }

function toForm(card: VehicleFuelCard | null | undefined): typeof BLANK {
  if (!card) return BLANK
  return {
    provider: card.provider ?? '',
    card_number: card.card_number ?? '',
    pin_code: card.pin_code ?? '',
    valid_until: card.valid_until ?? '',
    note: card.note ?? '',
  }
}

/**
 * כרטיס הדלקן.
 *
 * הטאב כולו חי מאחורי `fleet.view_fuel_card`, ולא רק בהסתרה בלקוח: הכרטיס
 * יושב בטבלה משלו עם RLS משלה (0088 §6), ומי שאין לו את המפתח מקבל אפס
 * שורות מהשרת. ההסתרה של ה-PIN כאן היא נגד מבט מעבר לכתף, לא נגד מי שמנסה.
 */
export function VehicleFuelCardTab({ vehicle }: { vehicle: Vehicle }) {
  const { has } = useAuth()
  const toast = useToast()
  const canManage = has(PERM.FLEET_MANAGE_FUEL_CARD)

  const { data: card, isLoading } = useVehicleFuelCard(vehicle.id)
  const save = useSaveFuelCard(vehicle.id)

  const [form, setForm] = useState(BLANK)
  const [showPin, setShowPin] = useState(false)

  useEffect(() => {
    setForm(toForm(card))
    setShowPin(false)
  }, [card])

  const dirty = useMemo(() => {
    const base = toForm(card)
    return (Object.keys(BLANK) as (keyof typeof BLANK)[]).some((k) => form[k] !== base[k])
  }, [form, card])

  const submit = () => {
    const values: Partial<VehicleFuelCard> = {
      provider: form.provider.trim() || null,
      card_number: form.card_number.trim() || null,
      pin_code: form.pin_code.trim() || null,
      valid_until: form.valid_until || null,
      note: form.note.trim() || null,
    }
    save.mutate(
      { card: card ?? null, values },
      {
        onSuccess: () => toast.success('כרטיס הדלק נשמר'),
        onError: (e) => toast.error(errorMessage(e)),
      },
    )
  }

  if (isLoading) return <Skeleton className="h-56 w-full max-w-2xl" />

  return (
    <Card className="max-w-2xl">
      <CardHeader
        title="כרטיס דלק / דלקן"
        subtitle="מי שאין לו את ההרשאה אינו מקבל את השורה הזו מהשרת כלל"
        icon={<Fuel size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody className="grid gap-4 sm:grid-cols-2">
        <Field label="ספק" hint="פז, דלק, סונול, דור אלון...">
          <Input disabled={!canManage} value={form.provider} onChange={(e) => setForm((f) => ({ ...f, provider: e.target.value }))} />
        </Field>
        <Field label="מספר כרטיס">
          <Input
            dir="ltr"
            disabled={!canManage}
            value={form.card_number}
            onChange={(e) => setForm((f) => ({ ...f, card_number: e.target.value }))}
          />
        </Field>
        <Field label="קוד תדלוק (PIN)">
          <div className="flex items-center gap-1">
            <Input
              className="flex-1"
              dir="ltr"
              type={showPin ? 'text' : 'password'}
              autoComplete="off"
              disabled={!canManage}
              value={form.pin_code}
              onChange={(e) => setForm((f) => ({ ...f, pin_code: e.target.value }))}
            />
            <IconButton label={showPin ? 'הסתרת הקוד' : 'הצגת הקוד'} onClick={() => setShowPin((v) => !v)}>
              {showPin ? <EyeOff size={ICON.md} strokeWidth={STROKE} /> : <Eye size={ICON.md} strokeWidth={STROKE} />}
            </IconButton>
          </div>
        </Field>
        <Field label="תוקף הכרטיס">
          <Input
            type="date"
            disabled={!canManage}
            value={form.valid_until}
            onChange={(e) => setForm((f) => ({ ...f, valid_until: e.target.value }))}
          />
        </Field>
        <Field label="הערה" className="sm:col-span-2">
          <Textarea
            autoGrow
            rows={2}
            disabled={!canManage}
            value={form.note}
            onChange={(e) => setForm((f) => ({ ...f, note: e.target.value }))}
          />
        </Field>
      </CardBody>
      {canManage ? (
        <StickySaveBar dirty={dirty} saving={save.isPending} onSave={submit} onReset={() => setForm(toForm(card))} />
      ) : (
        <CardBody>
          <p className="type-caption text-ink-tertiary">לצפייה בלבד — אין לך הרשאה לערוך את כרטיס הדלק.</p>
        </CardBody>
      )}
    </Card>
  )
}
