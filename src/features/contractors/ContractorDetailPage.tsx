import { useEffect, useMemo, useState } from 'react'
import { useParams } from 'react-router'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Banknote, Briefcase, Clock, ICON, Plus, STROKE, Trash2, User, Wallet } from '../../components/ui/icons'
import {
  Avatar,
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  DataTable,
  EmptyState,
  Field,
  IconButton,
  Input,
  Modal,
  PageHeader,
  Skeleton,
  ErrorState,
  StatCard,
  StatusPill,
  Switch,
  Tabs,
  cx,
  useConfirm,
  useToast,
  StickySaveBar,
} from '../../components/ui'
import type { Column } from '../../components/ui'
import { supabase, invokeFunction } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { useContractorAssignableWorkers, useContractorWorkers } from '../../lib/queries'
import { fmtDate, fmtMoney } from '../../lib/dates'
import { usePageTitle } from '../../app/breadcrumbs'
import { RequirePermission } from '../auth/guards'
import { PERM } from '../../lib/permissions'
import type { Contractor, ContractorWorker } from '../../types/domain'
import { errorMessage } from '../../lib/errors'

interface ContractorTaskRow {
  task_id: string
  price: number
  paid_at: string | null
  paid_amount: number | null
  tasks: {
    id: string
    task_date: string
    title: string | null
    task_types: { name: string } | null
    customers: { name: string } | null
    statuses: { name: string; color: string; is_terminal: boolean } | null
  }
}

const TABS = [
  { key: 'details', label: 'פרטים' },
  { key: 'workers', label: 'עובדי הקבלן' },
  { key: 'tasks', label: 'משימות ותשלומים' },
] as const

export default function ContractorDetailPage() {
  const { id } = useParams<{ id: string }>()
  const [tab, setTab] = useState<(typeof TABS)[number]['key']>('details')

  const { data: contractor, isLoading, error, refetch } = useQuery({
    queryKey: ['contractors', 'one', id],
    queryFn: async () => {
      const { data, error } = await supabase.from('contractors').select('*').eq('id', id).single()
      if (error) throw error
      return data as Contractor
    },
  })

  usePageTitle(contractor?.name ?? null)

  if (isLoading || !contractor) {
    // ראה CustomerDetailPage: בלי זה כישלון טעינה נראה כטעינה שלא נגמרת.
    if (error) return <ErrorState error={error} onRetry={() => void refetch()} />
    return (
      <div className="space-y-4">
        <Skeleton className="h-8 w-56" />
        <Skeleton className="h-10 w-full max-w-md" />
        <Skeleton className="h-64 w-full max-w-2xl" />
      </div>
    )
  }

  return (
    <RequirePermission perm={PERM.CONTRACTORS_VIEW}>
      <div className="space-y-4">
        <PageHeader
          title={
            <span className="flex flex-wrap items-center gap-2.5">
              <Avatar name={contractor.name} size="lg" />
              {contractor.name}
              {!contractor.is_active && <StatusPill color="#8a93a5">לא פעיל</StatusPill>}
            </span>
          }
          subtitle={[contractor.contact_name, contractor.phone].filter(Boolean).join(' · ') || 'ללא פרטי קשר'}
        >
          <Tabs items={TABS} value={tab} onChange={setTab} />
        </PageHeader>

        {tab === 'details' && <DetailsTab contractor={contractor} />}
        {tab === 'workers' && <WorkersTab contractorId={contractor.id} />}
        {tab === 'tasks' && <TasksTab contractorId={contractor.id} />}
      </div>
    </RequirePermission>
  )
}

/* ===== details ============================================================ */

function DetailsTab({ contractor }: { contractor: Contractor }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { has } = useAuth()
  const canEdit = has(PERM.CONTRACTORS_EDIT)
  const [form, setForm] = useState(contractor)
  useEffect(() => setForm(contractor), [contractor])

  const dirty = useMemo(
    () =>
      (['name', 'contact_name', 'phone', 'email', 'notes', 'default_task_price', 'is_active'] as const).some(
        (k) => form[k] !== contractor[k],
      ),
    [form, contractor],
  )

  const save = useMutation({
    mutationFn: async () => {
      if (!form.name.trim()) throw new Error('חובה להזין שם קבלן')
      const { error } = await supabase
        .from('contractors')
        .update({
          name: form.name,
          contact_name: form.contact_name,
          phone: form.phone,
          email: form.email,
          notes: form.notes,
          default_task_price: form.default_task_price,
          is_active: form.is_active,
        })
        .eq('id', contractor.id)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('הקבלן עודכן')
      void qc.invalidateQueries({ queryKey: ['contractors'] })
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <Card className="max-w-2xl">
      <CardHeader title="פרטי הקבלן" icon={<Briefcase size={ICON.md} strokeWidth={STROKE} />} />
      <CardBody className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="שם" required error={!form.name.trim() ? 'שדה חובה' : undefined}>
            <Input value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} disabled={!canEdit} />
          </Field>
          <Field label="איש קשר">
            <Input
              value={form.contact_name ?? ''}
              onChange={(e) => setForm((f) => ({ ...f, contact_name: e.target.value }))}
              disabled={!canEdit}
            />
          </Field>
          <Field label="טלפון">
            <Input type="tel" autoComplete="tel" dir="ltr" value={form.phone ?? ''} onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))} disabled={!canEdit} />
          </Field>
          <Field label="אימייל">
            <Input
              dir="ltr"
              type="email"
              value={form.email ?? ''}
              onChange={(e) => setForm((f) => ({ ...f, email: e.target.value }))}
              disabled={!canEdit}
            />
          </Field>
          <Field label="מחיר ברירת מחדל למשימה" hint="בשקלים, משמש כמחיר התחלתי בהאצלת משימה">
            <Input
              type="number"
              min="0"
              value={form.default_task_price ?? ''}
              onChange={(e) => setForm((f) => ({ ...f, default_task_price: e.target.value === '' ? null : Number(e.target.value) }))}
              disabled={!canEdit}
            />
          </Field>
        </div>
        <Field label="הערות">
          <Input value={form.notes ?? ''} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} disabled={!canEdit} />
        </Field>
        <Switch
          checked={form.is_active}
          onChange={(v) => setForm((f) => ({ ...f, is_active: v }))}
          disabled={!canEdit}
          label="קבלן פעיל"
          description="קבלן לא פעיל לא יופיע ברשימות ההאצלה"
        />
      </CardBody>
      {canEdit && (
        <StickySaveBar dirty={dirty} saving={save.isPending} onSave={() => save.mutate()} onReset={() => setForm(contractor)} />
      )}
    </Card>
  )
}

/* ===== workers ============================================================ */

/**
 * `canManage` used to default to true, and neither caller passed it — the write
 * UI was always on. It now defaults to the permission, and the two callers pass
 * the key that matches where they are: staff managing a contractor's roster
 * versus a contractor managing their own.
 */
export function WorkersTab({
  contractorId,
  canManage,
}: {
  contractorId: string
  canManage?: boolean
}) {
  const qc = useQueryClient()
  const toast = useToast()
  const has = useAuth((s) => s.has)
  const mayManage = canManage ?? has(PERM.CONTRACTORS_MANAGE_WORKERS)
  // יצירת חשבון היא פעולה של המשרד, לא של הקבלן — ולכן מפתח users ולא portal.
  const canCreateLogin = has(PERM.USERS_CREATE_LOGIN) && has(PERM.USERS_CREATE)
  const { confirm, dialog } = useConfirm()
  const { data: workers = [], isLoading } = useContractorWorkers(contractorId)
  const [form, setForm] = useState({ full_name: '', phone: '', id_number: '' })
  const [clockFor, setClockFor] = useState<ContractorWorker | null>(null)
  /* מי מהסגל כבר קיבל התחברות.
     `profiles.contractor_worker_id` הוא הקישור היחיד בין שורת הסגל לחשבון,
     אבל שאילתה ישירה על `profiles` עונה נכון רק במשרד: ל-`contractor_user`
     ‏`profiles_select` מחזיר את השורה שלו בלבד — ובלי שגיאה — ולכן התווית
     הייתה כבויה תמיד אצל מי שהמסך הזה נבנה בשבילו. `contractor_assignable_workers`
     ‏(0072) הוא `security definer` וכבר מחזיר `has_login` לכל שורת רוסטר,
     לשני הקהלים, מאותה סיבה שהוליד אותו מלכתחילה.

     ‏`enabled: mayManage` מיישר את הקריאה עם מה שה-RPC דורש: בהיקף זר הוא
     מבקש `contractors.manage_workers`, וזה בדיוק מה ש-`mayManage` שווה לו
     במשרד. מי שרק צופה אינו רואה תוויות התחברות, וגם אינו מקבל סירוב. */
  const { data: assignable = [] } = useContractorAssignableWorkers(mayManage ? contractorId : null)
  const hasLogin = useMemo(
    () => new Set(assignable.filter((a) => a.has_login && a.worker_id).map((a) => a.worker_id as string)),
    [assignable],
  )

  const add = useMutation({
    mutationFn: async () => {
      if (!form.full_name.trim()) throw new Error('חובה להזין שם עובד')
      const { error } = await supabase.from('contractor_workers').insert({ contractor_id: contractorId, ...form })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('העובד נוסף לסגל')
      setForm({ full_name: '', phone: '', id_number: '' })
      void qc.invalidateQueries({ queryKey: ['contractor_workers'] })
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const remove = async (w: ContractorWorker) => {
    if (!(await confirm(`להסיר את ${w.full_name} מהסגל?`, { title: 'הסרת עובד', confirmLabel: 'הסרה' }))) return
    const { error } = await supabase.from('contractor_workers').update({ deleted_at: new Date().toISOString() }).eq('id', w.id)
    if (error) toast.error(errorMessage(error))
    else {
      toast.success('העובד הוסר')
      void qc.invalidateQueries({ queryKey: ['contractor_workers'] })
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
      {mayManage && (
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
              <Input type="tel" autoComplete="tel" inputSize="sm" dir="ltr" value={form.phone} onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))} />
            </Field>
            <Field label="ת.ז." className="w-36">
              <Input inputSize="sm" dir="ltr" value={form.id_number} onChange={(e) => setForm((f) => ({ ...f, id_number: e.target.value }))} />
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
            description={mayManage ? 'הוסף עובדים כדי לשבץ אותם למשימות שהואצלו לקבלן' : undefined}
          />
        ) : (
          <ul>
            {workers.map((w) => (
              <li key={w.id} className="flex items-center gap-3 border-b border-line-subtle px-4 py-2.5 last:border-0 hover:bg-hover">
                <Avatar name={w.full_name} size="md" />
                <div className="min-w-0 flex-1">
                  <p className="truncate type-body font-medium">{w.full_name}</p>
                  <p className="truncate type-caption tabular text-ink-tertiary" dir="ltr">
                    {[w.phone, w.id_number].filter(Boolean).join(' · ') || '—'}
                  </p>
                </div>
                {hasLogin.has(w.id) ? (
                  <Badge tone="success">שעון נוכחות</Badge>
                ) : (
                  canCreateLogin && (
                    <Button size="sm" onClick={() => setClockFor(w)}>
                      <Clock size={ICON.sm} strokeWidth={STROKE} />
                      חשבון נוכחות
                    </Button>
                  )
                )}
                {mayManage && (
                  <IconButton label={`הסרת ${w.full_name}`} size="sm" onClick={() => void remove(w)} className="hover:text-error">
                    <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                  </IconButton>
                )}
              </li>
            ))}
          </ul>
        )}
      </CardBody>
      {clockFor && (
        <ClockAccountModal
          worker={clockFor}
          contractorId={contractorId}
          onClose={() => setClockFor(null)}
          onDone={() => void qc.invalidateQueries({ queryKey: ['profiles'] })}
        />
      )}
    </Card>
  )
}

/**
 * נותן לעובד קבלן חשבון שכל תפקידו להחתים שעון.
 *
 * שלושת השלבים חייבים לקרות יחד: שורת profiles (בלעדיה app.has מחזיר false
 * לכל מפתח והמערכת כולה סגורה בפניו), חשבון התחברות, והתפקיד הצר —
 * שבלעדיו הוא יורש מברירות המחדל של contractor_user את פורטל הקבלן על כל
 * הנתונים הכספיים שבו.
 */
function ClockAccountModal({
  worker,
  contractorId,
  onClose,
  onDone,
}: {
  worker: ContractorWorker
  contractorId: string
  onClose: () => void
  onDone: () => void
}) {
  const toast = useToast()
  const [creds, setCreds] = useState({ email: '', password: '' })

  const create = useMutation({
    mutationFn: async () => {
      if (!creds.email || !creds.password) throw new Error('חובה להזין אימייל וסיסמה')
      const { data: profile, error } = await supabase
        .from('profiles')
        .insert({
          full_name: worker.full_name,
          phone: worker.phone,
          user_kind: 'contractor_user',
          contractor_id: contractorId,
          contractor_worker_id: worker.id,
        })
        .select('id')
        .single()
      if (error) throw error

      const { data: role } = await supabase
        .from('permission_roles')
        .select('id')
        .eq('key', 'contractor_worker')
        .maybeSingle()
      if (role) {
        const { error: roleErr } = await supabase
          .from('profile_roles')
          .insert({ profile_id: profile.id, role_id: (role as { id: string }).id })
        if (roleErr) throw roleErr
      }

      await invokeFunction('admin-users', {
        action: 'create_login',
        email: creds.email,
        password: creds.password,
        profile_id: profile.id,
      })
    },
    onSuccess: () => {
      toast.success('נוצר חשבון נוכחות לעובד')
      onDone()
      onClose()
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <Modal
      open
      onClose={onClose}
      size="sm"
      title={`חשבון נוכחות ל${worker.full_name}`}
      footer={
        <>
          <Button onClick={onClose}>ביטול</Button>
          <Button variant="primary" loading={create.isPending} onClick={() => create.mutate()}>
            יצירה
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <p className="type-caption text-ink-tertiary">
          החשבון מאפשר לעובד להחתים שעון ולראות את המשמרות שלו בלבד — לא את פורטל הקבלן.
        </p>
        <Field label="אימייל" required>
          <Input
            data-autofocus
            dir="ltr"
            type="email"
            value={creds.email}
            onChange={(e) => setCreds((c) => ({ ...c, email: e.target.value }))}
          />
        </Field>
        <Field label="סיסמה" required>
          <Input
            dir="ltr"
            type="text"
            value={creds.password}
            onChange={(e) => setCreds((c) => ({ ...c, password: e.target.value }))}
          />
        </Field>
      </div>
    </Modal>
  )
}

/* ===== tasks & payments =================================================== */

function TasksTab({ contractorId }: { contractorId: string }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { has } = useAuth()
  const canEditPricing = has(PERM.CONTRACTORS_EDIT_PRICING)
  const canMarkPaid = has(PERM.CONTRACTORS_MARK_PAID)
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')

  const { data: rows = [], isLoading, error, refetch } = useQuery({
    queryKey: ['contractor_terms', contractorId, from, to],
    queryFn: async () => {
      let q = supabase
        .from('task_contractor_terms')
        .select(
          'task_id, price, paid_at, paid_amount, tasks!inner(id, task_date, title, deleted_at, task_types(name), customers(name), statuses(name, color, is_terminal))',
        )
        .eq('contractor_id', contractorId)
        .is('tasks.deleted_at', null)
      if (from) q = q.gte('tasks.task_date', from)
      if (to) q = q.lte('tasks.task_date', to)
      const { data, error } = await q
      if (error) throw error
      return (data as unknown as ContractorTaskRow[]).sort((a, b) => b.tasks.task_date.localeCompare(a.tasks.task_date))
    },
  })

  const setPaid = useMutation({
    mutationFn: async ({ taskId, paid }: { taskId: string; paid: boolean }) => {
      const row = rows.find((r) => r.task_id === taskId)
      const { error } = await supabase
        .from('task_contractor_terms')
        .update(paid ? { paid_at: new Date().toISOString(), paid_amount: row?.price ?? 0 } : { paid_at: null, paid_amount: null })
        .eq('task_id', taskId)
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['contractor_terms'] }),
    onError: (e) => toast.error(errorMessage(e)),
  })

  const updatePrice = useMutation({
    mutationFn: async ({ taskId, price }: { taskId: string; price: number }) => {
      const { error } = await supabase.from('task_contractor_terms').update({ price }).eq('task_id', taskId)
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['contractor_terms'] }),
    onError: (e) => toast.error(errorMessage(e)),
  })

  const expected = rows.reduce((s, r) => s + Number(r.price), 0)
  const paid = rows.filter((r) => r.paid_at).reduce((s, r) => s + Number(r.paid_amount ?? r.price), 0)
  const unpaidCount = rows.filter((r) => !r.paid_at).length

  const columns = useMemo<Column<ContractorTaskRow>[]>(
    () => [
      {
        key: 'date',
        header: 'תאריך',
        width: 110,
        fixed: true,
        sortValue: (r) => r.tasks.task_date,
        render: (r) => <span className="tabular">{fmtDate(r.tasks.task_date)}</span>,
      },
      {
        key: 'task',
        header: 'משימה',
        width: 180,
        sortValue: (r) => r.tasks.title ?? r.tasks.task_types?.name,
        render: (r) => <span className="font-medium">{r.tasks.title || r.tasks.task_types?.name}</span>,
      },
      {
        key: 'customer',
        header: 'לקוח',
        width: 150,
        sortValue: (r) => r.tasks.customers?.name,
        render: (r) => r.tasks.customers?.name ?? <span className="text-ink-tertiary">—</span>,
      },
      {
        key: 'status',
        header: 'סטטוס',
        width: 130,
        sortValue: (r) => r.tasks.statuses?.name,
        render: (r) =>
          r.tasks.statuses ? <StatusPill color={r.tasks.statuses.color}>{r.tasks.statuses.name}</StatusPill> : null,
      },
      {
        key: 'price',
        header: 'מחיר (₪)',
        width: 120,
        align: 'end',
        sortValue: (r) => Number(r.price),
        render: (r) => (
          <Input
            type="number"
            min="0"
            inputSize="sm"
            className="w-24"
            aria-label="מחיר למשימה"
            defaultValue={r.price}
            disabled={!canEditPricing}
            onClick={(e) => e.stopPropagation()}
            onBlur={(e) => {
              const v = Number(e.target.value) || 0
              if (v !== Number(r.price)) updatePrice.mutate({ taskId: r.task_id, price: v })
            }}
          />
        ),
      },
      {
        key: 'paid',
        header: 'תשלום',
        width: 160,
        sortValue: (r) => (r.paid_at ? 1 : 0),
        render: (r) => (
          <button
            disabled={!canMarkPaid}
            onClick={(e) => {
              e.stopPropagation()
              setPaid.mutate({ taskId: r.task_id, paid: !r.paid_at })
            }}
            className={cx(
              'rounded-full px-2.5 py-1 type-caption font-semibold transition-colors disabled:pointer-events-none',
              r.paid_at
                ? 'bg-success-subtle text-success-text hover:brightness-95'
                : 'bg-warning-subtle text-warning-text hover:brightness-95',
            )}
          >
            {r.paid_at ? `שולם · ${fmtDate(r.paid_at)}` : 'ממתין לתשלום'}
          </button>
        ),
      },
    ],
    [canEditPricing, canMarkPaid, setPaid, updatePrice],
  )

  return (
    <div className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-3">
        <StatCard icon={<Wallet size={ICON.xl} strokeWidth={STROKE} />} label="סה״כ צפוי" value={fmtMoney(expected)} />
        <StatCard icon={<Banknote size={ICON.xl} strokeWidth={STROKE} />} label="שולם" value={fmtMoney(paid)} tone="#16a34a" />
        <StatCard
          icon={<Banknote size={ICON.xl} strokeWidth={STROKE} />}
          label="יתרה לתשלום"
          value={fmtMoney(expected - paid)}
          tone="#f59e0b"
          hint={unpaidCount > 0 ? `${unpaidCount} משימות פתוחות` : 'הכול שולם'}
        />
      </div>

      <DataTable
        rows={rows}
        columns={columns}
        getRowId={(r) => r.task_id}
        loading={isLoading}
        error={error}
        onRetry={() => void refetch()}
        storageKey="contractor-terms"
        pageSize={20}
        defaultSort={{ key: 'date', dir: 'desc' }}
        mobileCard={(r) => (
          <div className="space-y-1.5">
            <div className="flex items-center gap-2">
              <span className="type-caption font-semibold tabular">{fmtDate(r.tasks.task_date)}</span>
              {r.tasks.statuses && (
                <StatusPill color={r.tasks.statuses.color} className="ms-auto shrink-0">
                  {r.tasks.statuses.name}
                </StatusPill>
              )}
            </div>
            <p className="truncate type-body font-semibold">{r.tasks.title || r.tasks.task_types?.name}</p>
            {r.tasks.customers?.name && (
              <p className="truncate type-caption text-ink-tertiary">{r.tasks.customers.name}</p>
            )}
            <div className="flex items-center gap-2">
              <Input
                type="number"
                min="0"
                inputSize="sm"
                className="w-28"
                aria-label="מחיר למשימה"
                defaultValue={r.price}
                disabled={!canEditPricing}
                onClick={(e) => e.stopPropagation()}
                onBlur={(e) => {
                  const v = Number(e.target.value) || 0
                  if (v !== Number(r.price)) updatePrice.mutate({ taskId: r.task_id, price: v })
                }}
              />
              <button
                disabled={!canMarkPaid}
                onClick={(e) => {
                  e.stopPropagation()
                  setPaid.mutate({ taskId: r.task_id, paid: !r.paid_at })
                }}
                className={cx(
                  'rounded-full px-2.5 py-1 type-caption font-semibold transition-colors disabled:pointer-events-none',
                  r.paid_at
                    ? 'bg-success-subtle text-success-text'
                    : 'bg-warning-subtle text-warning-text',
                )}
              >
                {r.paid_at ? `שולם · ${fmtDate(r.paid_at)}` : 'ממתין לתשלום'}
              </button>
            </div>
          </div>
        )}
        toolbar={
          <div className="flex flex-wrap items-end gap-2">
            {/* a fixed 9rem is narrower than a date control's own minimum on a
                phone, so the two fields share the row and grow into it instead */}
            <Field label="מתאריך" className="grow basis-36 sm:w-36 sm:grow-0 sm:basis-auto">
              <Input type="date" inputSize="sm" value={from} onChange={(e) => setFrom(e.target.value)} />
            </Field>
            <Field label="עד תאריך" className="grow basis-36 sm:w-36 sm:grow-0 sm:basis-auto">
              <Input type="date" inputSize="sm" value={to} onChange={(e) => setTo(e.target.value)} />
            </Field>
          </div>
        }
        empty={
          <EmptyState
            art="table"
            title="אין משימות שהואצלו לקבלן"
            description="משימות שיואצלו לקבלן יופיעו כאן יחד עם התמחור ומצב התשלום"
          />
        }
      />
    </div>
  )
}
