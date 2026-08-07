import { useEffect, useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { ICON, Plus, STROKE, UserCheck } from '../../components/ui/icons'
import {
  Avatar,
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  Drawer,
  EmptyState,
  Field,
  Input,
  PageHeader,
  SkeletonList,
  StatusPill,
  Switch,
  Tabs,
  Textarea,
  useToast,
} from '../../components/ui'
import { invokeFunction, supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { useCustomerUsers } from '../../lib/queries'
import { RequirePermission } from '../auth/guards'
import { PERM } from '../../lib/permissions'
import { PermissionMatrix } from '../permissions/PermissionMatrix'
import { UserFormFieldsCard } from '../permissions/UserFormFieldsCard'
import type { Profile } from '../../types/domain'

const TABS = [
  { key: 'details' as const, label: 'פרטים' },
  { key: 'permissions' as const, label: 'הרשאות' },
]

/**
 * Sub-users the client opens under their own company.
 *
 * Everything here is also enforced in the database — profiles_insert scopes the
 * new row to the caller's customer, app.guard_user_permissions refuses a grant
 * the caller does not hold, and the admin-users function re-checks the target.
 * The UI narrows the same way so a client is never offered a control that would
 * only produce an error.
 */
export default function ClientUsersPage() {
  const { me, has } = useAuth()
  const [editing, setEditing] = useState<Profile | null>(null)
  const [createOpen, setCreateOpen] = useState(false)
  const { data: users = [], isLoading } = useCustomerUsers(me?.profile.customer_id)

  return (
    <RequirePermission perm={PERM.USERS_VIEW}>
      <div className="space-y-4">
        <PageHeader
          title="המשתמשים שלי"
          subtitle={isLoading ? 'טוען...' : `${users.length} משתמשים`}
          actions={
            has(PERM.USERS_CREATE) && (
              <Button size="sm" variant="primary" onClick={() => setCreateOpen(true)}>
                <Plus size={ICON.sm} strokeWidth={STROKE} />
                משתמש חדש
              </Button>
            )
          }
        />

        {isLoading ? (
          <SkeletonList rows={3} />
        ) : users.length === 0 ? (
          <Card>
            <EmptyState
              art="alert"
              title="אין עדיין משתמשים"
              description="אפשר לפתוח משתמשים נוספים בחברה שלך ולקבוע לכל אחד מהם הרשאות"
            />
          </Card>
        ) : (
          <Card>
            <CardBody padded={false}>
              <ul>
                {users.map((u) => (
                  <li key={u.id} className="border-b border-line-subtle last:border-0">
                    <button
                      onClick={() => setEditing(u)}
                      className="flex w-full items-center gap-3 px-4 py-3 text-start transition-colors hover:bg-hover"
                    >
                      <Avatar name={u.full_name} size="sm" />
                      <span className="min-w-0 flex-1">
                        <span className="block truncate type-body font-medium">{u.full_name}</span>
                        {u.email && (
                          <span className="block truncate type-caption text-ink-tertiary" dir="ltr">
                            {u.email}
                          </span>
                        )}
                      </span>
                      {u.id === me?.profile.id && <Badge tone="primary">אני</Badge>}
                      {u.user_id ? <Badge tone="success" dot>התחברות</Badge> : <Badge>אין התחברות</Badge>}
                      {u.is_active ? (
                        <StatusPill color="#16a34a">פעיל</StatusPill>
                      ) : (
                        <StatusPill color="#dc2626">מושבת</StatusPill>
                      )}
                    </button>
                  </li>
                ))}
              </ul>
            </CardBody>
          </Card>
        )}

        {(editing || createOpen) && (
          <UserDrawer
            profile={editing}
            onClose={() => {
              setEditing(null)
              setCreateOpen(false)
            }}
          />
        )}
      </div>
    </RequirePermission>
  )
}

function UserDrawer({ profile, onClose }: { profile: Profile | null; onClose: () => void }) {
  const { me, has } = useAuth()
  const qc = useQueryClient()
  const toast = useToast()
  const [tab, setTab] = useState<'details' | 'permissions'>('details')
  const [form, setForm] = useState({ full_name: '', phone: '', email: '', notes: '', is_active: true })
  const [login, setLogin] = useState({ email: '', password: '' })
  const [touched, setTouched] = useState(false)

  const isSelf = profile?.id === me?.profile.id
  // the database refuses a self-edit through this path; saying so beats a 403
  const mayEdit = has(PERM.USERS_EDIT) && !isSelf

  useEffect(() => {
    setForm({
      full_name: profile?.full_name ?? '',
      phone: profile?.phone ?? '',
      email: profile?.email ?? '',
      notes: profile?.notes ?? '',
      is_active: profile?.is_active ?? true,
    })
    setLogin({ email: profile?.email ?? '', password: '' })
    setTouched(false)
  }, [profile])

  const invalidate = () => {
    void qc.invalidateQueries({ queryKey: ['profiles', 'byCustomer'] })
  }

  const save = useMutation({
    mutationFn: async () => {
      if (!form.full_name.trim()) throw new Error('חובה להזין שם')
      const payload = {
        full_name: form.full_name.trim(),
        phone: form.phone || null,
        email: form.email || null,
        notes: form.notes || null,
        is_active: form.is_active,
      }
      if (profile) {
        const { error } = await supabase.from('profiles').update(payload).eq('id', profile.id)
        if (error) throw error
      } else {
        // user_kind and customer_id are fixed by policy, not by this form
        const { error } = await supabase
          .from('profiles')
          .insert({ ...payload, user_kind: 'customer_user', customer_id: me?.profile.customer_id })
        if (error) throw error
      }
    },
    onSuccess: () => {
      toast.success(profile ? 'המשתמש עודכן' : 'המשתמש נוצר')
      invalidate()
      if (!profile) onClose()
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
      invalidate()
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const nameError = touched && !form.full_name.trim() ? 'חובה להזין שם' : undefined

  return (
    <Drawer
      open
      onClose={onClose}
      title={profile ? profile.full_name : 'משתמש חדש'}
      footer={
        tab === 'details' && (
          <>
            <Button onClick={onClose}>ביטול</Button>
            <Button
              variant="primary"
              loading={save.isPending}
              disabled={!!profile && !mayEdit}
              onClick={() => {
                setTouched(true)
                save.mutate()
              }}
            >
              שמירה
            </Button>
          </>
        )
      }
    >
      {profile && <Tabs items={TABS} value={tab} onChange={setTab} />}

      {tab === 'details' || !profile ? (
        <div className="space-y-4">
          {isSelf && (
            <Card padded className="type-caption text-ink-secondary">
              זהו המשתמש שלך. לעריכת הפרטים או ההרשאות של עצמך יש לפנות למנהל המערכת.
            </Card>
          )}
          <Field label="שם מלא" required error={nameError}>
            <Input
              value={form.full_name}
              onChange={(e) => setForm((f) => ({ ...f, full_name: e.target.value }))}
              disabled={!!profile && !mayEdit}
            />
          </Field>
          <Field label="טלפון">
            <Input
              dir="ltr"
              value={form.phone}
              onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))}
              disabled={!!profile && !mayEdit}
            />
          </Field>
          <Field label="אימייל">
            <Input
              dir="ltr"
              type="email"
              value={form.email}
              onChange={(e) => setForm((f) => ({ ...f, email: e.target.value }))}
              disabled={!!profile && !mayEdit}
            />
          </Field>
          <Field label="הערות">
            <Textarea
              autoGrow
              value={form.notes}
              onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))}
              disabled={!!profile && !mayEdit}
            />
          </Field>
          <Switch
            checked={form.is_active}
            onChange={(v) => setForm((f) => ({ ...f, is_active: v }))}
            label="משתמש פעיל"
            disabled={!!profile && !mayEdit}
          />

          {profile && has(PERM.USERS_CREATE_LOGIN) && !profile.user_id && !isSelf && (
            <Card>
              <CardHeader title="חשבון התחברות" subtitle="יצירת גישה למערכת עבור המשתמש" />
              <CardBody className="space-y-3">
                <Field label="אימייל">
                  <Input
                    dir="ltr"
                    type="email"
                    autoComplete="off"
                    value={login.email}
                    onChange={(e) => setLogin((l) => ({ ...l, email: e.target.value }))}
                  />
                </Field>
                <Field label="סיסמה">
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
              </CardBody>
            </Card>
          )}
          {profile && !profile.user_id && !has(PERM.USERS_CREATE_LOGIN) && (
            <p className="type-caption text-ink-tertiary">אין לך הרשאה ליצור חשבונות התחברות.</p>
          )}
        </div>
      ) : (
        profile &&
        (isSelf ? (
          <EmptyState
            art="alert"
            title="ההרשאות שלך"
            description="אינך יכול לשנות את ההרשאות של עצמך. פנה למנהל המערכת."
          />
        ) : (
          <div className="space-y-4">
            {/* useGroupedRegistry filters the catalog by applies_to, so a
                customer_user subject already shows only client-relevant keys.
                canGrant mirrors app.guard_permission_grant on top of that. */}
            <PermissionMatrix
              subject={{ kind: 'user', profileId: profile.id, userKind: 'customer_user' }}
              canGrant={(key) => has(key)}
            />
            <UserFormFieldsCard profile={profile} />
          </div>
        ))
      )}
    </Drawer>
  )
}
