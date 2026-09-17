import { useMemo, useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Avatar,
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  Field,
  IconButton,
  Input,
  Modal,
  PageHeader,
  Skeleton,
  Switch,
  useConfirm,
  useToast,
} from '../../components/ui'
import { ICON, LogIn, Plus, STROKE, Trash2, User } from '../../components/ui/icons'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import {
  useCustomerStaffAccount,
  useCustomerStaffAccountRemove,
  useCustomerStaffPassword,
  useCustomerWorkerAccounts,
  useCustomerWorkerRoles,
  useCustomerWorkers,
} from '../../lib/queries'
import { errorMessage } from '../../lib/errors'
import type { CustomerWorker, CustomerWorkerAccount, StaffRole } from '../../types/domain'

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
      <PageHeader
        title="הסגל שלי"
        subtitle="העובדים, ראשי הצוות והנהגים ששובצו למשימות שאתם מבצעים — והכניסה שלהם למערכת"
      />
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
  /* ‏0178: חשבון ההתחברות הוא שאלה על העובד ולא על השיבוץ, ולכן הוא
     נשאל כאן ולא דרך `customer_assignable_workers`. */
  const { data: accounts = [] } = useCustomerWorkerAccounts(customerId)
  const [form, setForm] = useState({ full_name: '', phone: '', id_number: '' })
  const [accountFor, setAccountFor] = useState<CustomerWorker | null>(null)

  const accountOf = useMemo(() => {
    const m = new Map<string, CustomerWorkerAccount>()
    for (const a of accounts) m.set(a.customer_worker_id, a)
    return m
  }, [accounts])

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
    void qc.invalidateQueries({ queryKey: ['customer_worker_accounts', customerId] })
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
                    {/* ‏0178: כניסה למערכת — צ׳יפ למי שכבר יש לו, וכפתור למי שאין. */}
                    {accountOf.has(w.id) ? (
                      <button
                        type="button"
                        onClick={() => setAccountFor(w)}
                        title={accountOf.get(w.id)?.email ?? 'חשבון משתמש'}
                      >
                        <Badge tone={accountOf.get(w.id)?.user_id ? 'success' : 'warning'}>
                          {accountOf.get(w.id)?.user_id ? 'יש כניסה' : 'טרם נפתחה כניסה'}
                        </Badge>
                      </button>
                    ) : (
                      <IconButton label={`פתיחת כניסה ל${w.full_name}`} size="sm" bare onClick={() => setAccountFor(w)}>
                        <LogIn size={ICON.sm} strokeWidth={STROKE} className="text-ink-tertiary" />
                      </IconButton>
                    )}
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
      {accountFor && (
        <StaffAccountModal
          worker={accountFor}
          account={accountOf.get(accountFor.id) ?? null}
          onClose={() => setAccountFor(null)}
          onDone={invalidate}
        />
      )}
    </Card>
  )
}

/**
 * הכניסה של עובד בסגל (0178).
 *
 * המקבילה של `ClockAccountModal` של הקבלן, בהבדל אחד שהוא כל העניין:
 * שם המשרד פותח את החשבון מכרטיס הקבלן, וכאן הלקוח עושה זאת
 * בעצמו — הסגל הוא שלו, ולכן גם המפתח לדלת.
 *
 * מה שהחשבון נותן נאמר במפורש במסך, כדי שלא ייפתח בטעות למי
 * שאמור לנהל: המשימות שהעובד שובץ אליהן והמשמרות שלו, ולא הלו״ז
 * של הלקוח כולו.
 */
function StaffAccountModal({
  worker,
  account,
  onClose,
  onDone,
}: {
  worker: CustomerWorker
  account: CustomerWorkerAccount | null
  onClose: () => void
  onDone: () => void
}) {
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const [creds, setCreds] = useState({ email: account?.email ?? '', password: '' })
  const open = useCustomerStaffAccount()
  const reset = useCustomerStaffPassword()
  const drop = useCustomerStaffAccountRemove()
  const hasLogin = !!account?.user_id

  const submit = () => {
    if (hasLogin) {
      reset.mutate(
        { profileId: account!.id, password: creds.password },
        {
          onSuccess: () => {
            toast.success('הסיסמה הוחלפה')
            onDone()
            onClose()
          },
          onError: (e) => toast.error(errorMessage(e)),
        },
      )
      return
    }
    open.mutate(
      { workerId: worker.id, email: creds.email, password: creds.password },
      {
        onSuccess: () => {
          toast.success('נפתחה כניסה לעובד')
          onDone()
          onClose()
        },
        onError: (e) => toast.error(errorMessage(e)),
      },
    )
  }

  const removeAccount = async () => {
    if (!account) return
    if (!(await confirm(`לבטל את הכניסה של ${worker.full_name}?`, {
      title: 'ביטול כניסה',
      confirmLabel: 'ביטול הכניסה',
    }))) return
    drop.mutate(
      { workerId: worker.id, profileId: account.id, hasLogin },
      {
        onSuccess: () => {
          toast.success('הכניסה בוטלה — העובד נשאר בסגל')
          onDone()
          onClose()
        },
        onError: (e) => toast.error(errorMessage(e)),
      },
    )
  }

  return (
    <Modal
      open
      onClose={onClose}
      size="sm"
      title={`כניסה למערכת ל${worker.full_name}`}
      footer={
        <>
          {account && (
            <Button variant="danger" onClick={() => void removeAccount()} loading={drop.isPending}>
              ביטול הכניסה
            </Button>
          )}
          <Button onClick={onClose}>סגירה</Button>
          <Button
            variant="primary"
            loading={open.isPending || reset.isPending}
            disabled={!creds.password || (!hasLogin && !creds.email.trim())}
            onClick={submit}
          >
            {hasLogin ? 'החלפת סיסמה' : 'פתיחת כניסה'}
          </Button>
        </>
      }
    >
      {dialog}
      <div className="space-y-4">
        <p className="type-caption text-ink-tertiary">
          העובד יראה בלו״ז את המשימות ששובץ אליהן ואת המשמרות שלו — ולא את שאר
          הלו״ז, את המחירים או את שאר הסגל.
        </p>
        {account && !hasLogin && (
          <p className="type-caption text-warning-text">
            שורת העובד נוצרה, אך הכניסה עצמה לא נפתחה. אפשר לנסות שוב כאן.
          </p>
        )}
        <Field label="אימייל" required={!hasLogin}>
          <Input
            data-autofocus={!hasLogin}
            dir="ltr"
            type="email"
            autoComplete="off"
            disabled={hasLogin}
            value={creds.email}
            onChange={(e) => setCreds((c) => ({ ...c, email: e.target.value }))}
          />
        </Field>
        <Field label={hasLogin ? 'סיסמה חדשה' : 'סיסמה'} required>
          <Input
            data-autofocus={hasLogin}
            dir="ltr"
            type="text"
            autoComplete="off"
            value={creds.password}
            onChange={(e) => setCreds((c) => ({ ...c, password: e.target.value }))}
          />
        </Field>
      </div>
    </Modal>
  )
}
