import { useEffect, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { KeyRound, Plus } from 'lucide-react'
import { supabase, invokeFunction } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import {
  Badge, Button, Checkbox, Drawer, Field, Input, Select, Spinner, EmptyState, useToast, cx,
} from '../../components/ui'
import { useContractors, useCustomers } from '../../lib/queries'
import { RequirePermission } from '../auth/guards'
import type { PermissionAction, Profile, StaffRole, UserKind } from '../../types/domain'

const kindLabels: Record<UserKind, string> = { staff: 'צוות', customer_user: 'לקוח', contractor_user: 'קבלן' }
const roleLabels: Record<StaffRole, string> = { worker: 'עובד', driver: 'נהג', team_lead: 'ראש צוות' }
const resources = [
  { key: 'events', label: 'אירועים' },
  { key: 'tasks', label: 'משימות' },
  { key: 'customers', label: 'לקוחות' },
  { key: 'users', label: 'משתמשים' },
  { key: 'contractors', label: 'קבלנים' },
  { key: 'settings', label: 'הגדרות' },
  { key: 'dashboard', label: 'דשבורד' },
]
const actions: { key: PermissionAction; label: string }[] = [
  { key: 'view', label: 'צפייה' },
  { key: 'create', label: 'יצירה' },
  { key: 'edit', label: 'עריכה' },
  { key: 'delete', label: 'מחיקה' },
]

export default function UsersPage() {
  const [kind, setKind] = useState<UserKind | ''>('')
  const [q, setQ] = useState('')
  const [editing, setEditing] = useState<Profile | null>(null)
  const [createOpen, setCreateOpen] = useState(false)

  const { data: profiles = [], isLoading } = useQuery({
    queryKey: ['profiles', 'all'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('profiles')
        .select('*, staff_roles(role)')
        .is('deleted_at', null)
        .order('full_name')
      if (error) throw error
      return data as Profile[]
    },
  })

  const filtered = profiles.filter(
    (p) => (!kind || p.user_kind === kind) && (p.full_name.includes(q) || (p.phone ?? '').includes(q)),
  )

  return (
    <RequirePermission resource="users">
      <div className="space-y-3">
        <div className="flex items-center gap-2">
          <h1 className="text-xl font-bold">עובדים ומשתמשים</h1>
          <div className="ms-auto">
            <Button variant="primary" onClick={() => setCreateOpen(true)}>
              <Plus size={14} /> משתמש חדש
            </Button>
          </div>
        </div>
        <div className="surface flex flex-wrap gap-2 p-2.5">
          <Input className="w-56" placeholder="חיפוש לפי שם או טלפון..." value={q} onChange={(e) => setQ(e.target.value)} />
          <Select className="w-36" value={kind} onChange={(e) => setKind(e.target.value as UserKind | '')}>
            <option value="">כל הסוגים</option>
            <option value="staff">צוות</option>
            <option value="customer_user">משתמשי לקוח</option>
            <option value="contractor_user">משתמשי קבלן</option>
          </Select>
        </div>
        <div className="surface overflow-x-auto">
          {isLoading ? (
            <Spinner full />
          ) : filtered.length === 0 ? (
            <EmptyState text="אין משתמשים" />
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[var(--border)] text-xs text-[var(--muted)]">
                  <th className="px-3 py-2 text-start">שם</th>
                  <th className="px-3 py-2 text-start">טלפון</th>
                  <th className="px-3 py-2 text-start">אימייל</th>
                  <th className="px-3 py-2 text-start">סוג</th>
                  <th className="px-3 py-2 text-start">תפקידים</th>
                  <th className="px-3 py-2 text-start">התחברות</th>
                  <th className="px-3 py-2 text-start">סטטוס</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((p) => (
                  <tr key={p.id} onClick={() => setEditing(p)} className="cursor-pointer border-b border-[var(--border)] last:border-0 hover:bg-[var(--bg)]">
                    <td className="px-3 py-2 font-medium">
                      {p.full_name} {p.is_admin && <Badge color="#8b5cf6">אדמין</Badge>}
                    </td>
                    <td className="px-3 py-2" dir="ltr">{p.phone}</td>
                    <td className="px-3 py-2" dir="ltr">{p.email}</td>
                    <td className="px-3 py-2">{kindLabels[p.user_kind]}</td>
                    <td className="px-3 py-2">
                      <span className="flex flex-wrap gap-1">
                        {(p.staff_roles ?? []).map((r) => <Badge key={r.role}>{roleLabels[r.role]}</Badge>)}
                      </span>
                    </td>
                    <td className="px-3 py-2">{p.user_id ? <Badge color="#22c55e">יש</Badge> : <Badge>אין</Badge>}</td>
                    <td className="px-3 py-2">{p.is_active ? <Badge color="#22c55e">פעיל</Badge> : <Badge color="#ef4444">מושבת</Badge>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
        <UserDrawer open={createOpen || !!editing} profile={editing} onClose={() => { setCreateOpen(false); setEditing(null) }} />
      </div>
    </RequirePermission>
  )
}

function UserDrawer({ open, profile, onClose }: { open: boolean; profile: Profile | null; onClose: () => void }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { me, can } = useAuth()
  const isAdmin = !!me?.profile.is_admin
  const { data: customers = [] } = useCustomers()
  const { data: contractors = [] } = useContractors()
  const [tab, setTab] = useState<'details' | 'permissions'>('details')

  const [form, setForm] = useState({
    full_name: '', phone: '', email: '', notes: '',
    user_kind: 'staff' as UserKind, is_admin: false, is_active: true,
    customer_id: '', contractor_id: '', roles: [] as StaffRole[],
  })
  const [login, setLogin] = useState({ email: '', password: '' })

  useEffect(() => {
    if (!open) return
    setTab('details')
    if (profile) {
      setForm({
        full_name: profile.full_name,
        phone: profile.phone ?? '',
        email: profile.email ?? '',
        notes: profile.notes ?? '',
        user_kind: profile.user_kind,
        is_admin: profile.is_admin,
        is_active: profile.is_active,
        customer_id: profile.customer_id ?? '',
        contractor_id: profile.contractor_id ?? '',
        roles: (profile.staff_roles ?? []).map((r) => r.role),
      })
      setLogin({ email: profile.email ?? '', password: '' })
    } else {
      setForm({ full_name: '', phone: '', email: '', notes: '', user_kind: 'staff', is_admin: false, is_active: true, customer_id: '', contractor_id: '', roles: ['worker'] })
      setLogin({ email: '', password: '' })
    }
  }, [open, profile])

  const save = useMutation({
    mutationFn: async () => {
      if (!form.full_name.trim()) throw new Error('חובה להזין שם')
      const base = {
        full_name: form.full_name,
        phone: form.phone || null,
        email: form.email || null,
        notes: form.notes || null,
        user_kind: form.user_kind,
        is_admin: isAdmin ? form.is_admin : undefined,
        is_active: form.is_active,
        customer_id: form.user_kind === 'customer_user' ? form.customer_id || null : null,
        contractor_id: form.user_kind === 'contractor_user' ? form.contractor_id || null : null,
      }
      let profileId = profile?.id
      if (profile) {
        const { error } = await supabase.from('profiles').update(base).eq('id', profile.id)
        if (error) throw error
      } else {
        const { data, error } = await supabase.from('profiles').insert(base).select('id').single()
        if (error) throw error
        profileId = data.id
      }
      // staff roles
      await supabase.from('staff_roles').delete().eq('profile_id', profileId)
      if (form.user_kind === 'staff' && form.roles.length) {
        const { error } = await supabase.from('staff_roles').insert(form.roles.map((role) => ({ profile_id: profileId, role })))
        if (error) throw error
      }
    },
    onSuccess: () => {
      toast.success('המשתמש נשמר')
      void qc.invalidateQueries({ queryKey: ['profiles'] })
      onClose()
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const createLogin = useMutation({
    mutationFn: async () => {
      if (!login.email || !login.password) throw new Error('חובה להזין אימייל וסיסמה')
      await invokeFunction('admin-users', { action: 'create_login', email: login.email, password: login.password, profile_id: profile?.id })
    },
    onSuccess: () => {
      toast.success('חשבון ההתחברות נוצר')
      void qc.invalidateQueries({ queryKey: ['profiles'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const resetPassword = useMutation({
    mutationFn: async () => {
      if (!login.password) throw new Error('חובה להזין סיסמה חדשה')
      await invokeFunction('admin-users', { action: 'set_password', user_id: profile?.user_id, password: login.password })
    },
    onSuccess: () => toast.success('הסיסמה עודכנה'),
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <Drawer open={open} onClose={onClose} title={profile ? `עריכת משתמש — ${profile.full_name}` : 'משתמש חדש'}>
      {profile && (
        <div className="mb-4 flex gap-1 border-b border-[var(--border)]">
          {(['details', 'permissions'] as const).map((t) => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={cx(
                'border-b-2 px-3 py-1.5 text-sm font-medium',
                tab === t ? 'border-brand-600 text-brand-600 dark:text-brand-300' : 'border-transparent text-[var(--muted)]',
              )}
            >
              {t === 'details' ? 'פרטים' : 'הרשאות'}
            </button>
          ))}
        </div>
      )}

      {tab === 'details' ? (
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Field label="שם מלא" required>
              <Input value={form.full_name} onChange={(e) => setForm((f) => ({ ...f, full_name: e.target.value }))} />
            </Field>
            <Field label="טלפון">
              <Input dir="ltr" value={form.phone} onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))} />
            </Field>
          </div>
          <Field label="סוג משתמש">
            <Select value={form.user_kind} onChange={(e) => setForm((f) => ({ ...f, user_kind: e.target.value as UserKind }))}>
              <option value="staff">צוות (עובד / נהג / ראש צוות)</option>
              <option value="customer_user">משתמש לקוח</option>
              <option value="contractor_user">משתמש קבלן</option>
            </Select>
          </Field>
          {form.user_kind === 'staff' && (
            <Field label="תפקידים (ניתן לשלב)">
              <div className="flex gap-4">
                {(Object.keys(roleLabels) as StaffRole[]).map((r) => (
                  <Checkbox
                    key={r}
                    label={roleLabels[r]}
                    checked={form.roles.includes(r)}
                    onChange={(v) => setForm((f) => ({ ...f, roles: v ? [...f.roles, r] : f.roles.filter((x) => x !== r) }))}
                  />
                ))}
              </div>
            </Field>
          )}
          {form.user_kind === 'customer_user' && (
            <Field label="לקוח" required>
              <Select value={form.customer_id} onChange={(e) => setForm((f) => ({ ...f, customer_id: e.target.value }))}>
                <option value="">בחירה...</option>
                {customers.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
              </Select>
            </Field>
          )}
          {form.user_kind === 'contractor_user' && (
            <Field label="קבלן" required>
              <Select value={form.contractor_id} onChange={(e) => setForm((f) => ({ ...f, contractor_id: e.target.value }))}>
                <option value="">בחירה...</option>
                {contractors.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
              </Select>
            </Field>
          )}
          <div className="flex gap-4">
            {isAdmin && form.user_kind === 'staff' && (
              <Checkbox label="מנהל מערכת" checked={form.is_admin} onChange={(v) => setForm((f) => ({ ...f, is_admin: v }))} />
            )}
            <Checkbox label="פעיל" checked={form.is_active} onChange={(v) => setForm((f) => ({ ...f, is_active: v }))} />
          </div>

          {/* login management */}
          <div className="space-y-2 rounded-lg border border-[var(--border)] p-3">
            <h3 className="flex items-center gap-1.5 text-xs font-bold text-[var(--muted)]"><KeyRound size={12} /> חשבון התחברות</h3>
            {profile?.user_id ? (
              <div className="flex items-end gap-2">
                <Field label="סיסמה חדשה">
                  <Input dir="ltr" type="password" value={login.password} onChange={(e) => setLogin((l) => ({ ...l, password: e.target.value }))} />
                </Field>
                <Button loading={resetPassword.isPending} onClick={() => resetPassword.mutate()}>איפוס סיסמה</Button>
              </div>
            ) : profile ? (
              <div className="flex flex-wrap items-end gap-2">
                <Field label="אימייל">
                  <Input dir="ltr" type="email" value={login.email} onChange={(e) => setLogin((l) => ({ ...l, email: e.target.value }))} />
                </Field>
                <Field label="סיסמה">
                  <Input dir="ltr" type="password" value={login.password} onChange={(e) => setLogin((l) => ({ ...l, password: e.target.value }))} />
                </Field>
                <Button loading={createLogin.isPending} onClick={() => createLogin.mutate()}>יצירת חשבון</Button>
              </div>
            ) : (
              <p className="text-xs text-[var(--muted)]">שמור את המשתמש תחילה, ואז ניתן ליצור לו חשבון התחברות.</p>
            )}
          </div>

          <div className="flex justify-end gap-2 pt-2">
            <Button onClick={onClose}>ביטול</Button>
            {(can('users', profile ? 'edit' : 'create') || isAdmin) && (
              <Button variant="primary" loading={save.isPending} onClick={() => save.mutate()}>שמירה</Button>
            )}
          </div>
        </div>
      ) : (
        profile && <PermissionsTab profile={profile} />
      )}
    </Drawer>
  )
}

function PermissionsTab({ profile }: { profile: Profile }) {
  const toast = useToast()
  const qc = useQueryClient()

  const { data: overrides = [], isLoading } = useQuery({
    queryKey: ['user_permissions', profile.id],
    queryFn: async () => {
      const { data, error } = await supabase.from('user_permissions').select('*').eq('profile_id', profile.id)
      if (error) throw error
      return data as { resource: string; action: PermissionAction; allowed: boolean }[]
    },
  })

  const { data: defaults = [] } = useQuery({
    queryKey: ['permission_defaults'],
    queryFn: async () => {
      const { data, error } = await supabase.from('permission_defaults').select('*')
      if (error) throw error
      return data as { user_kind: UserKind; resource: string; action: PermissionAction; allowed: boolean }[]
    },
  })

  const { data: fieldPerms = [] } = useQuery({
    queryKey: ['field_permissions', profile.id],
    queryFn: async () => {
      const { data, error } = await supabase.from('field_permissions').select('*').eq('profile_id', profile.id)
      if (error) throw error
      return data as { id: string; entity: string; field_key: string; can_view: boolean }[]
    },
  })

  const stateOf = (resource: string, action: PermissionAction): 'default' | 'allow' | 'deny' => {
    const o = overrides.find((x) => x.resource === resource && x.action === action)
    if (!o) return 'default'
    return o.allowed ? 'allow' : 'deny'
  }
  const defaultOf = (resource: string, action: PermissionAction) =>
    defaults.find((d) => d.user_kind === profile.user_kind && d.resource === resource && d.action === action)?.allowed ?? false

  const update = useMutation({
    mutationFn: async ({ resource, action, state }: { resource: string; action: PermissionAction; state: string }) => {
      if (state === 'default') {
        const { error } = await supabase.from('user_permissions').delete().eq('profile_id', profile.id).eq('resource', resource).eq('action', action)
        if (error) throw error
      } else {
        const { error } = await supabase.from('user_permissions').upsert({ profile_id: profile.id, resource, action, allowed: state === 'allow' })
        if (error) throw error
      }
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['user_permissions', profile.id] }),
    onError: (e) => toast.error((e as Error).message),
  })

  const phoneFp = fieldPerms.find((f) => f.entity === 'event' && f.field_key === 'contact_phone')
  const togglePhone = useMutation({
    mutationFn: async (canView: boolean) => {
      const { error } = await supabase
        .from('field_permissions')
        .upsert(
          { id: phoneFp?.id, profile_id: profile.id, entity: 'event', field_key: 'contact_phone', can_view: canView, can_edit: canView },
        )
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['field_permissions', profile.id] }),
    onError: (e) => toast.error((e as Error).message),
  })

  if (isLoading) return <Spinner full />
  if (profile.is_admin) return <p className="text-sm text-[var(--muted)]">מנהל מערכת — כל ההרשאות פתוחות.</p>

  return (
    <div className="space-y-4">
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-xs text-[var(--muted)]">
              <th className="px-2 py-1.5 text-start">משאב</th>
              {actions.map((a) => <th key={a.key} className="px-2 py-1.5 text-start">{a.label}</th>)}
            </tr>
          </thead>
          <tbody>
            {resources.map((r) => (
              <tr key={r.key} className="border-t border-[var(--border)]">
                <td className="px-2 py-2 font-medium">{r.label}</td>
                {actions.map((a) => (
                  <td key={a.key} className="px-2 py-1.5">
                    <select
                      value={stateOf(r.key, a.key)}
                      onChange={(e) => update.mutate({ resource: r.key, action: a.key, state: e.target.value })}
                      className={cx(
                        'rounded border border-[var(--border)] bg-[var(--panel)] px-1.5 py-1 text-xs',
                        stateOf(r.key, a.key) === 'allow' && 'text-emerald-600',
                        stateOf(r.key, a.key) === 'deny' && 'text-red-500',
                      )}
                    >
                      <option value="default">ברירת מחדל ({defaultOf(r.key, a.key) ? 'מותר' : 'חסום'})</option>
                      <option value="allow">מותר</option>
                      <option value="deny">חסום</option>
                    </select>
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="rounded-lg border border-[var(--border)] p-3">
        <h3 className="mb-2 text-xs font-bold text-[var(--muted)]">הרשאות ברמת שדה</h3>
        <Checkbox
          label="רואה טלפון ואיש קשר של אירועים"
          checked={phoneFp ? phoneFp.can_view : true}
          onChange={(v) => togglePhone.mutate(v)}
        />
        <p className="mt-1 text-xs text-[var(--muted)]">נאכף גם בצד השרת (RLS) — לא רק בתצוגה.</p>
      </div>
    </div>
  )
}
