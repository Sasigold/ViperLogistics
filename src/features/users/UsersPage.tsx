import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ICON, KeyRound, Plus, STROKE, Shield, User, UserCheck } from '../../components/ui/icons'
import {
  Avatar,
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  Checkbox,
  DataTable,
  Drawer,
  EmptyState,
  Field,
  FilterBar,
  Input,
  PageHeader,
  SearchInput,
  SegmentedControl,
  Select,
  Skeleton,
  StatusPill,
  Switch,
  Tabs,
  Textarea,
  useToast,
} from '../../components/ui'
import type { Column } from '../../components/ui'
import { supabase, invokeFunction } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
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

  const { data: profiles = [], isLoading, error, refetch } = useQuery({
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

  const columns = useMemo<Column<Profile>[]>(
    () => [
      {
        key: 'full_name',
        header: 'שם',
        width: 220,
        sticky: true,
        fixed: true,
        sortValue: (p) => p.full_name,
        render: (p) => (
          <span className="flex items-center gap-2">
            <Avatar name={p.full_name} size="sm" />
            <span className="min-w-0 truncate font-medium">{p.full_name}</span>
            {p.is_admin && (
              <Badge tone="primary" className="shrink-0">
                אדמין
              </Badge>
            )}
          </span>
        ),
      },
      {
        key: 'phone',
        header: 'טלפון',
        width: 130,
        sortValue: (p) => p.phone,
        render: (p) =>
          p.phone ? (
            <span className="tabular" dir="ltr">
              {p.phone}
            </span>
          ) : (
            <span className="text-ink-tertiary">—</span>
          ),
      },
      {
        key: 'email',
        header: 'אימייל',
        width: 200,
        sortValue: (p) => p.email,
        render: (p) =>
          p.email ? (
            <span className="block truncate" dir="ltr">
              {p.email}
            </span>
          ) : (
            <span className="text-ink-tertiary">—</span>
          ),
      },
      {
        key: 'kind',
        header: 'סוג',
        width: 110,
        sortValue: (p) => kindLabels[p.user_kind],
        render: (p) => kindLabels[p.user_kind],
      },
      {
        key: 'roles',
        header: 'תפקידים',
        width: 190,
        render: (p) => {
          const roles = p.staff_roles ?? []
          return roles.length ? (
            <span className="flex flex-wrap gap-1">
              {roles.map((r) => (
                <Badge key={r.role}>{roleLabels[r.role]}</Badge>
              ))}
            </span>
          ) : (
            <span className="text-ink-tertiary">—</span>
          )
        },
      },
      {
        key: 'login',
        header: 'התחברות',
        width: 110,
        sortValue: (p) => (p.user_id ? 1 : 0),
        render: (p) =>
          p.user_id ? (
            <Badge tone="success" dot>
              פעילה
            </Badge>
          ) : (
            <Badge>אין</Badge>
          ),
      },
      {
        key: 'status',
        header: 'סטטוס',
        width: 110,
        sortValue: (p) => (p.is_active ? 1 : 0),
        render: (p) => (p.is_active ? <StatusPill color="#16a34a">פעיל</StatusPill> : <StatusPill color="#dc2626">מושבת</StatusPill>),
      },
    ],
    [],
  )

  const counts = {
    staff: profiles.filter((p) => p.user_kind === 'staff').length,
    customer_user: profiles.filter((p) => p.user_kind === 'customer_user').length,
    contractor_user: profiles.filter((p) => p.user_kind === 'contractor_user').length,
  }

  return (
    <RequirePermission resource="users">
      <div className="space-y-4">
        <PageHeader
          title="עובדים ומשתמשים"
          subtitle={
            isLoading
              ? 'טוען...'
              : `${counts.staff} צוות · ${counts.customer_user} משתמשי לקוח · ${counts.contractor_user} משתמשי קבלן`
          }
          actions={
            <Button size="sm" variant="primary" onClick={() => setCreateOpen(true)}>
              <Plus size={ICON.sm} strokeWidth={STROKE} />
              משתמש חדש
            </Button>
          }
        >
          <FilterBar
            onReset={
              q || kind
                ? () => {
                    setQ('')
                    setKind('')
                  }
                : undefined
            }
          >
            <SearchInput
              className="w-64 max-sm:w-full"
              inputSize="sm"
              placeholder="חיפוש לפי שם או טלפון..."
              value={q}
              onChange={(e) => setQ(e.target.value)}
              onClear={() => setQ('')}
              aria-label="חיפוש משתמש"
            />
            <SegmentedControl
              className="max-sm:w-full"
              items={[
                { key: '', label: 'הכול' },
                { key: 'staff', label: 'צוות' },
                { key: 'customer_user', label: 'לקוחות' },
                { key: 'contractor_user', label: 'קבלנים' },
              ]}
              value={kind}
              onChange={(k) => setKind(k as UserKind | '')}
            />
          </FilterBar>
        </PageHeader>

        <DataTable
          rows={filtered}
          columns={columns}
          getRowId={(p) => p.id}
          loading={isLoading}
          error={error}
          onRetry={() => void refetch()}
          onRowClick={(p) => setEditing(p)}
          storageKey="users"
          pageSize={25}
          mobileCard={(p) => (
            <div className="flex items-center gap-2.5">
              <Avatar name={p.full_name} size="md" />
              <div className="min-w-0 flex-1">
                <p className="flex items-center gap-1.5">
                  <span className="truncate type-body font-semibold">{p.full_name}</span>
                  {p.is_admin && <Badge tone="primary">אדמין</Badge>}
                </p>
                <p className="flex flex-wrap items-center gap-x-1.5 type-caption text-ink-tertiary">
                  <span>{kindLabels[p.user_kind]}</span>
                  {p.phone && (
                    <span className="tabular" dir="ltr">
                      · {p.phone}
                    </span>
                  )}
                  {(p.staff_roles ?? []).length > 0 && (
                    <span className="truncate">· {(p.staff_roles ?? []).map((r) => roleLabels[r.role]).join(', ')}</span>
                  )}
                </p>
              </div>
              <StatusPill color={p.is_active ? '#16a34a' : '#dc2626'} className="shrink-0">
                {p.is_active ? 'פעיל' : 'מושבת'}
              </StatusPill>
            </div>
          )}
          empty={
            <EmptyState
              art="people"
              title={q || kind ? 'אין משתמשים תואמים' : 'אין משתמשים'}
              description={q || kind ? 'נסה לשנות את הסינון' : 'הוסף עובדים, נהגים וראשי צוות כדי לשבץ אותם למשימות'}
              action={
                <Button size="sm" variant="primary" onClick={() => setCreateOpen(true)}>
                  <Plus size={ICON.sm} />
                  משתמש חדש
                </Button>
              }
            />
          }
        />

        <UserDrawer
          open={createOpen || !!editing}
          profile={editing}
          onClose={() => {
            setCreateOpen(false)
            setEditing(null)
          }}
        />
      </div>
    </RequirePermission>
  )
}

/* ===== user drawer ======================================================== */

const DRAWER_TABS = [
  { key: 'details' as const, label: 'פרטים', icon: <User size={ICON.sm} /> },
  { key: 'permissions' as const, label: 'הרשאות', icon: <Shield size={ICON.sm} /> },
]

function UserDrawer({ open, profile, onClose }: { open: boolean; profile: Profile | null; onClose: () => void }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { me, can } = useAuth()
  const isAdmin = !!me?.profile.is_admin
  const { data: customers = [] } = useCustomers()
  const { data: contractors = [] } = useContractors()
  const [tab, setTab] = useState<'details' | 'permissions'>('details')

  const [form, setForm] = useState({
    full_name: '',
    phone: '',
    email: '',
    notes: '',
    user_kind: 'staff' as UserKind,
    is_admin: false,
    is_active: true,
    customer_id: '',
    contractor_id: '',
    roles: [] as StaffRole[],
  })
  const [login, setLogin] = useState({ email: '', password: '' })
  const [touched, setTouched] = useState(false)

  useEffect(() => {
    if (!open) return
    setTab('details')
    setTouched(false)
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
      setForm({
        full_name: '',
        phone: '',
        email: '',
        notes: '',
        user_kind: 'staff',
        is_admin: false,
        is_active: true,
        customer_id: '',
        contractor_id: '',
        roles: ['worker'],
      })
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
      await invokeFunction('admin-users', {
        action: 'create_login',
        email: login.email,
        password: login.password,
        profile_id: profile?.id,
      })
    },
    onSuccess: () => {
      toast.success('חשבון ההתחברות נוצר')
      setLogin((l) => ({ ...l, password: '' }))
      void qc.invalidateQueries({ queryKey: ['profiles'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const resetPassword = useMutation({
    mutationFn: async () => {
      if (!login.password) throw new Error('חובה להזין סיסמה חדשה')
      await invokeFunction('admin-users', { action: 'set_password', user_id: profile?.user_id, password: login.password })
    },
    onSuccess: () => {
      toast.success('הסיסמה עודכנה')
      setLogin((l) => ({ ...l, password: '' }))
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const nameError = touched && !form.full_name.trim() ? 'חובה להזין שם' : undefined
  const linkError =
    touched && form.user_kind === 'customer_user' && !form.customer_id
      ? 'יש לבחור לקוח'
      : touched && form.user_kind === 'contractor_user' && !form.contractor_id
        ? 'יש לבחור קבלן'
        : undefined
  const canSave = can('users', profile ? 'edit' : 'create') || isAdmin

  return (
    <Drawer
      open={open}
      onClose={onClose}
      title={
        profile ? (
          <span className="flex items-center gap-2">
            <Avatar name={profile.full_name} size="md" />
            {profile.full_name}
          </span>
        ) : (
          'משתמש חדש'
        )
      }
      description={profile ? kindLabels[profile.user_kind] : 'הוספת עובד, משתמש לקוח או משתמש קבלן'}
      footer={
        tab === 'details' && (
          <>
            <Button onClick={onClose}>ביטול</Button>
            {canSave && (
              <Button
                variant="primary"
                loading={save.isPending}
                onClick={() => {
                  setTouched(true)
                  save.mutate()
                }}
              >
                שמירה
              </Button>
            )}
          </>
        )
      }
    >
      {profile && <Tabs className="mb-4" size="sm" items={DRAWER_TABS} value={tab} onChange={setTab} />}

      {tab === 'details' ? (
        <div className="space-y-4">
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="שם מלא" required error={nameError}>
              <Input
                data-autofocus
                value={form.full_name}
                onBlur={() => setTouched(true)}
                onChange={(e) => setForm((f) => ({ ...f, full_name: e.target.value }))}
              />
            </Field>
            <Field label="טלפון">
              <Input dir="ltr" value={form.phone} onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))} />
            </Field>
          </div>

          <Field label="סוג משתמש" hint="קובע את סט ההרשאות ואת המסכים שהמשתמש רואה">
            <Select value={form.user_kind} onChange={(e) => setForm((f) => ({ ...f, user_kind: e.target.value as UserKind }))}>
              <option value="staff">צוות (עובד / נהג / ראש צוות)</option>
              <option value="customer_user">משתמש לקוח</option>
              <option value="contractor_user">משתמש קבלן</option>
            </Select>
          </Field>

          {form.user_kind === 'staff' && (
            <Field label="תפקידים" hint="ניתן לשלב מספר תפקידים לאותו עובד">
              <div className="grid gap-2 sm:grid-cols-3">
                {(Object.keys(roleLabels) as StaffRole[]).map((r) => (
                  <label
                    key={r}
                    className="flex cursor-pointer items-center rounded-lg border border-line-subtle p-2.5 transition-colors hover:bg-hover"
                  >
                    <Checkbox
                      label={roleLabels[r]}
                      checked={form.roles.includes(r)}
                      onChange={(v) => setForm((f) => ({ ...f, roles: v ? [...f.roles, r] : f.roles.filter((x) => x !== r) }))}
                    />
                  </label>
                ))}
              </div>
            </Field>
          )}

          {form.user_kind === 'customer_user' && (
            <Field label="לקוח משויך" required error={linkError}>
              <Select value={form.customer_id} onChange={(e) => setForm((f) => ({ ...f, customer_id: e.target.value }))}>
                <option value="">בחירה...</option>
                {customers.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </Select>
            </Field>
          )}

          {form.user_kind === 'contractor_user' && (
            <Field label="קבלן משויך" required error={linkError}>
              <Select value={form.contractor_id} onChange={(e) => setForm((f) => ({ ...f, contractor_id: e.target.value }))}>
                <option value="">בחירה...</option>
                {contractors.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </Select>
            </Field>
          )}

          <Field label="הערות">
            <Textarea autoGrow rows={2} value={form.notes} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
          </Field>

          <div className="space-y-3 rounded-lg border border-line-subtle bg-subtle/50 p-3">
            {isAdmin && form.user_kind === 'staff' && (
              <Switch
                checked={form.is_admin}
                onChange={(v) => setForm((f) => ({ ...f, is_admin: v }))}
                label="מנהל מערכת"
                description="גישה מלאה לכל המשאבים, עוקף את טבלת ההרשאות"
              />
            )}
            <Switch
              checked={form.is_active}
              onChange={(v) => setForm((f) => ({ ...f, is_active: v }))}
              label="משתמש פעיל"
              description="משתמש מושבת לא יוכל להתחבר ולא יופיע ברשימות שיבוץ"
            />
          </div>

          {/* login management */}
          <Card>
            <CardHeader
              title="חשבון התחברות"
              subtitle={profile?.user_id ? 'קיים חשבון פעיל' : profile ? 'טרם נוצר חשבון' : 'זמין לאחר השמירה'}
              icon={<KeyRound size={ICON.md} strokeWidth={STROKE} />}
            />
            <CardBody>
              {profile?.user_id ? (
                <div className="flex flex-wrap items-end gap-2">
                  <Field label="סיסמה חדשה" className="min-w-40 flex-1">
                    <Input
                      dir="ltr"
                      type="password"
                      autoComplete="new-password"
                      value={login.password}
                      onChange={(e) => setLogin((l) => ({ ...l, password: e.target.value }))}
                    />
                  </Field>
                  <Button loading={resetPassword.isPending} disabled={!login.password} onClick={() => resetPassword.mutate()}>
                    איפוס סיסמה
                  </Button>
                </div>
              ) : profile ? (
                <div className="flex flex-wrap items-end gap-2">
                  <Field label="אימייל" className="min-w-40 flex-1">
                    <Input
                      dir="ltr"
                      type="email"
                      autoComplete="off"
                      value={login.email}
                      onChange={(e) => setLogin((l) => ({ ...l, email: e.target.value }))}
                    />
                  </Field>
                  <Field label="סיסמה" className="min-w-36 flex-1">
                    <Input
                      dir="ltr"
                      type="password"
                      autoComplete="new-password"
                      value={login.password}
                      onChange={(e) => setLogin((l) => ({ ...l, password: e.target.value }))}
                    />
                  </Field>
                  <Button
                    variant="primary"
                    loading={createLogin.isPending}
                    disabled={!login.email || !login.password}
                    onClick={() => createLogin.mutate()}
                  >
                    <UserCheck size={ICON.sm} strokeWidth={STROKE} />
                    יצירת חשבון
                  </Button>
                </div>
              ) : (
                <p className="type-caption text-ink-tertiary">שמור את המשתמש תחילה, ואז ניתן ליצור לו חשבון התחברות.</p>
              )}
            </CardBody>
          </Card>
        </div>
      ) : (
        profile && <PermissionsTab profile={profile} />
      )}
    </Drawer>
  )
}

/* ===== permission matrix ==================================================
   A 7x4 grid of three-state selects reads as noise. Rendering it as a matrix
   of compact segmented controls, with the inherited default spelled out,
   makes "what does this user actually get" answerable at a glance.        */

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
        const { error } = await supabase
          .from('user_permissions')
          .delete()
          .eq('profile_id', profile.id)
          .eq('resource', resource)
          .eq('action', action)
        if (error) throw error
      } else {
        const { error } = await supabase
          .from('user_permissions')
          .upsert({ profile_id: profile.id, resource, action, allowed: state === 'allow' })
        if (error) throw error
      }
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['user_permissions', profile.id] }),
    onError: (e) => toast.error((e as Error).message),
  })

  const phoneFp = fieldPerms.find((f) => f.entity === 'event' && f.field_key === 'contact_phone')
  const togglePhone = useMutation({
    mutationFn: async (canView: boolean) => {
      const { error } = await supabase.from('field_permissions').upsert({
        id: phoneFp?.id,
        profile_id: profile.id,
        entity: 'event',
        field_key: 'contact_phone',
        can_view: canView,
        can_edit: canView,
      })
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['field_permissions', profile.id] }),
    onError: (e) => toast.error((e as Error).message),
  })

  if (isLoading) return <Skeleton className="h-72 w-full" />

  if (profile.is_admin)
    return (
      <EmptyState
        art="check"
        title="מנהל מערכת"
        description="לכל המשאבים והפעולות — טבלת ההרשאות אינה חלה על מנהלי מערכת"
      />
    )

  const overrideCount = overrides.length

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader
          title="הרשאות פר-משאב"
          subtitle={
            overrideCount > 0
              ? `${overrideCount} חריגות מברירת המחדל של "${kindLabels[profile.user_kind]}"`
              : `הכול לפי ברירת המחדל של "${kindLabels[profile.user_kind]}"`
          }
          icon={<Shield size={ICON.md} strokeWidth={STROKE} />}
        />
        <CardBody padded={false}>
          <ul>
            {resources.map((r) => (
              <li key={r.key} className="border-b border-line-subtle px-4 py-3 last:border-0">
                <p className="mb-2 type-body font-semibold">{r.label}</p>
                <div className="grid gap-2 sm:grid-cols-2">
                  {actions.map((a) => {
                    const state = stateOf(r.key, a.key)
                    const inherited = defaultOf(r.key, a.key)
                    return (
                      <div key={a.key} className="flex items-center gap-2">
                        <span className="w-12 shrink-0 type-caption text-ink-tertiary">{a.label}</span>
                        <SegmentedControl
                          items={[
                            { key: 'default', label: inherited ? 'ברירת מחדל · מותר' : 'ברירת מחדל · חסום' },
                            { key: 'allow', label: 'מותר' },
                            { key: 'deny', label: 'חסום' },
                          ]}
                          value={state}
                          onChange={(next) => update.mutate({ resource: r.key, action: a.key, state: next })}
                        />
                      </div>
                    )
                  })}
                </div>
              </li>
            ))}
          </ul>
        </CardBody>
      </Card>

      <Card>
        <CardHeader title="הרשאות ברמת שדה" icon={<KeyRound size={ICON.md} strokeWidth={STROKE} />} />
        <CardBody>
          <Switch
            checked={phoneFp ? phoneFp.can_view : true}
            onChange={(v) => togglePhone.mutate(v)}
            label="רואה טלפון ואיש קשר של אירועים"
            description="נאכף גם בצד השרת (RLS) — לא רק בתצוגה"
          />
        </CardBody>
      </Card>
    </div>
  )
}
