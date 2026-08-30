import { useMemo, useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Avatar,
  Button,
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  Field,
  IconButton,
  Input,
  PageHeader,
  Skeleton,
  Switch,
  useConfirm,
  useToast,
} from '../../components/ui'
import { ICON, Plus, STROKE, Trash2, User } from '../../components/ui/icons'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { useCustomerWorkerRoles, useCustomerWorkers } from '../../lib/queries'
import { errorMessage } from '../../lib/errors'
import type { CustomerWorker, StaffRole } from '../../types/domain'

/**
 * הסגל של לקוח שמבצע בעצמו (0133) — המקבילה של "העובדים שלי" של הקבלן.
 *
 * אותה רשומה בדיוק במבנה, ובכוונה: מי שמבצע מביא אנשים, וחלקם ראשי צוות
 * וחלקם נהגים. מה שאין כאן, ולא במקרה, הוא כל מה שכספי — אין תעריף, אין
 * מעקב איחורים ואין הגדרות שכר: אלה עובדים של הלקוח, וויפר אינה משלמת להם.
 */
export default function MyCrewPage() {
  return (
    <RequirePermission perm={PERM.CUSTOMERS_MANAGE_OWN_STAFF}>
      <MyCrew />
    </RequirePermission>
  )
}

function MyCrew() {
  const { me, has } = useAuth()
  const customerId = me?.profile.customer_id ?? null
  const enabled = !!me?.customer?.performed_by_enabled
  const canManage = has(PERM.CUSTOMERS_MANAGE_OWN_STAFF)

  return (
    <div className="space-y-4">
      <PageHeader title="הסגל שלי" subtitle="העובדים, ראשי הצוות והנהגים ששובצו למשימות שאתם מבצעים" />
      {customerId && enabled ? (
        <CrewCard customerId={customerId} canManage={canManage} />
      ) : (
        /* מנהל מערכת שמציץ, או לקוח שאינו מבצע בעצמו: המפתח בידו והדגל כבוי,
           וזה בדיוק הצירוף שהמסך הזה אינו נועד לו. */
        <Card>
          <EmptyState
            art="alert"
            title="המסך הזה שייך ללקוח שמבצע בעצמו"
            description="החשבון שלך אינו משויך ללקוח שסומן כמבצע את המשימות שלו."
          />
        </Card>
      )}
    </div>
  )
}

function CrewCard({ customerId, canManage }: { customerId: string; canManage: boolean }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const { data: workers = [], isLoading } = useCustomerWorkers(customerId)
  const { data: roleRows = [] } = useCustomerWorkerRoles(customerId)
  const [form, setForm] = useState({ full_name: '', phone: '', id_number: '' })

  const rolesOf = useMemo(() => {
    const m = new Map<string, Set<StaffRole>>()
    for (const r of roleRows) {
      const set = m.get(r.customer_worker_id) ?? new Set<StaffRole>()
      set.add(r.role)
      m.set(r.customer_worker_id, set)
    }
    return m
  }, [roleRows])

  const invalidate = () => {
    void qc.invalidateQueries({ queryKey: ['customer_workers', customerId] })
    void qc.invalidateQueries({ queryKey: ['customer_worker_roles', customerId] })
    void qc.invalidateQueries({ queryKey: ['customer_assignable'] })
  }

  const add = useMutation({
    mutationFn: async () => {
      if (!form.full_name.trim()) throw new Error('חובה להזין שם עובד')
      const { error } = await supabase
        .from('customer_workers')
        .insert({ customer_id: customerId, ...form })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('העובד נוסף לסגל')
      setForm({ full_name: '', phone: '', id_number: '' })
      invalidate()
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  /* תפקיד הוא הגדרה, והשיבוץ בתפקיד נעשה על המשימה עצמה (0133) — בדיוק
     כמו אצל הקבלן ב-0121. עובד בלי אף מתג הוא עובד. */
  const toggleRole = useMutation({
    mutationFn: async ({ id, role, on }: { id: string; role: StaffRole; on: boolean }) => {
      if (on) {
        const { error } = await supabase
          .from('customer_worker_roles')
          .insert({ customer_worker_id: id, role })
        if (error) throw error
      } else {
        const { error } = await supabase
          .from('customer_worker_roles')
          .delete()
          .eq('customer_worker_id', id)
          .eq('role', role)
        if (error) throw error
      }
    },
    onSuccess: invalidate,
    onError: (e) => toast.error(errorMessage(e)),
  })

  const remove = async (w: CustomerWorker) => {
    if (!(await confirm(`להסיר את ${w.full_name} מהסגל?`, { title: 'הסרת עובד', confirmLabel: 'הסרה' }))) return
    const { error } = await supabase
      .from('customer_workers')
      .update({ deleted_at: new Date().toISOString() })
      .eq('id', w.id)
    if (error) toast.error(errorMessage(error))
    else {
      toast.success('העובד הוסר')
      invalidate()
    }
  }

  return (
    <Card className="max-w-2xl">
      {dialog}
      <CardHeader
        title="סגל העובדים"
        subtitle={`${workers.length} עובדים`}
        icon={<User size={ICON.md} strokeWidth={STROKE} />}
      />
      {canManage && (
        <div className="border-b border-line-subtle bg-subtle/40 p-4">
          <form
            className="flex flex-wrap items-end gap-2"
            onSubmit={(e) => {
              e.preventDefault()
              add.mutate()
            }}
          >
            <Field label="שם מלא" className="min-w-40 flex-1">
              <Input
                inputSize="sm"
                value={form.full_name}
                onChange={(e) => setForm((f) => ({ ...f, full_name: e.target.value }))}
              />
            </Field>
            <Field label="טלפון" className="w-36">
              <Input
                type="tel"
                autoComplete="tel"
                inputSize="sm"
                dir="ltr"
                value={form.phone}
                onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))}
              />
            </Field>
            <Field label="ת.ז." className="w-36">
              <Input
                inputSize="sm"
                dir="ltr"
                value={form.id_number}
                onChange={(e) => setForm((f) => ({ ...f, id_number: e.target.value }))}
              />
            </Field>
            <Button type="submit" size="sm" variant="primary" loading={add.isPending} disabled={!form.full_name.trim()}>
              <Plus size={ICON.sm} strokeWidth={STROKE} />
              הוספה
            </Button>
          </form>
        </div>
      )}
      <CardBody padded={false}>
        {isLoading ? (
          <div className="p-4">
            <Skeleton className="h-24 w-full" />
          </div>
        ) : workers.length === 0 ? (
          <EmptyState
            compact
            art="people"
            title="אין עובדים בסגל"
            description={canManage ? 'הוסיפו עובדים כדי לשבץ אותם למשימות שאתם מבצעים' : undefined}
          />
        ) : (
          <ul>
            {workers.map((w) => (
              <li
                key={w.id}
                className="flex items-center gap-3 border-b border-line-subtle px-4 py-2.5 last:border-0 hover:bg-hover"
              >
                <Avatar name={w.full_name} size="md" />
                <div className="min-w-0 flex-1">
                  <p className="truncate type-body font-medium">{w.full_name}</p>
                  <p className="truncate type-caption tabular text-ink-tertiary" dir="ltr">
                    {[w.phone, w.id_number].filter(Boolean).join(' · ') || '—'}
                  </p>
                </div>
                {canManage && (
                  <div className="flex items-center gap-3">
                    <Switch
                      checked={rolesOf.get(w.id)?.has('team_lead') ?? false}
                      onChange={(on) => toggleRole.mutate({ id: w.id, role: 'team_lead', on })}
                      label="ראש צוות"
                    />
                    <Switch
                      checked={rolesOf.get(w.id)?.has('driver') ?? false}
                      onChange={(on) => toggleRole.mutate({ id: w.id, role: 'driver', on })}
                      label="נהג"
                    />
                    <IconButton label={`הסרת ${w.full_name}`} size="sm" bare onClick={() => void remove(w)}>
                      <Trash2 size={ICON.sm} strokeWidth={STROKE} className="text-ink-tertiary" />
                    </IconButton>
                  </div>
                )}
              </li>
            ))}
          </ul>
        )}
      </CardBody>
    </Card>
  )
}
