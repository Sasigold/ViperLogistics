import { useEffect, useMemo, useState } from 'react'
import { useSearchParams } from 'react-router'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Clock, ICON, KeyRound, Plus, STROKE, Shield, User, UserCheck } from '../../components/ui/icons'
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
  StatusPill,
  Switch,
  Tabs,
  Textarea,
  useToast,
} from '../../components/ui'
import type { Column } from '../../components/ui'
import { supabase, invokeFunction } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { useContractors, useCustomers } from '../../lib/queries'
import { RequirePermission } from '../auth/guards'
import { UserPermissionsTab } from '../permissions/UserPermissionsTab'
import { EmployeeWorkSettingsCard } from '../attendance/EmployeeWorkSettingsCard'
import { ASSIGNMENT_ROLE_LABELS } from '../attendance/shiftFormat'
import type { Profile, StaffRole } from '../../types/domain'
import { errorMessage } from '../../lib/errors'
import { USER_TYPE_LABELS, USER_TYPE_OPTION_LABELS, kindOfType, userTypeOf } from './userType'
import type { UserType } from './userType'

/**
 * הרשימה והמסנן מדברים ב"סוג משתמש" של הטופס ולא ב-`user_kind` של המסד:
 * מנהל מערכת שנרשם כשורת צוות היה מופיע כאן בתוך "צוות", בדיוק כמו העובדים
 * שהוא אינו אחד מהם. ראו userType.ts.
 */
const kindLabels = USER_TYPE_LABELS
/** מוגדר ב-shiftFormat, כדי שמסך העובדים ופירוק המשמרת יקראו לתפקיד אותו דבר. */
const roleLabels = ASSIGNMENT_ROLE_LABELS


export default function UsersPage() {
  const creatableKinds = useAuth((s) => s.creatableKinds)
  const [kind, setKind] = useState<UserType | ''>('')
  const [q, setQ] = useState('')
  const [editing, setEditing] = useState<Profile | null>(null)
  const [createOpen, setCreateOpen] = useState(false)

  /* חיפוש גלובלי מגיע לכאן עם ?q=<שם> — אין דף פרטים לעובד, אז הסינון הוא
     הנחיתה. effect ולא initializer, מאותה סיבה שמוסברת ב-deepLink.ts:
     בחירה שנייה בפלטה בזמן שהמסך כבר פתוח צריכה לעבוד גם היא. */
  const [params] = useSearchParams()
  const qParam = params.get('q')
  useEffect(() => {
    if (qParam) setQ(qParam)
  }, [qParam])

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
    (p) => (!kind || userTypeOf(p) === kind) && (p.full_name.includes(q) || (p.phone ?? '').includes(q)),
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
        sortValue: (p) => kindLabels[userTypeOf(p)],
        render: (p) => kindLabels[userTypeOf(p)],
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

  /* `profiles_select` already scoped this list — a client sees their own
     company's people and nobody else's. So the subtitle and the kind filter
     are built from the kinds that actually came back rather than from a fixed
     three, and both disappear when there is only one kind to tell apart. */
  const kindsPresent = useMemo(
    () => (Object.keys(kindLabels) as UserType[]).filter((k) => profiles.some((p) => userTypeOf(p) === k)),
    [profiles],
  )
  const subtitle = kindsPresent
    .map((k) => `${profiles.filter((p) => userTypeOf(p) === k).length} ${kindLabels[k]}`)
    .join(' · ')

  return (
    <RequirePermission perm={PERM.USERS_VIEW}>
      <div className="space-y-4">
        <PageHeader
          title="עובדים ומשתמשים"
          subtitle={isLoading ? 'טוען...' : subtitle}
          actions={
            creatableKinds().length > 0 && (
              <Button size="sm" variant="primary" onClick={() => setCreateOpen(true)}>
                <Plus size={ICON.sm} strokeWidth={STROKE} />
                משתמש חדש
              </Button>
            )
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
            {kindsPresent.length > 1 && (
              <SegmentedControl
                className="max-sm:w-full"
                items={[
                  { key: '', label: 'הכול' },
                  ...kindsPresent.map((k) => ({ key: k, label: kindLabels[k] })),
                ]}
                value={kind}
                onChange={(k) => setKind(k as UserType | '')}
              />
            )}
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
                  <span>{kindLabels[userTypeOf(p)]}</span>
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
  { key: 'work' as const, label: 'שכר ונוכחות', icon: <Clock size={ICON.sm} /> },
  { key: 'permissions' as const, label: 'הרשאות', icon: <Shield size={ICON.sm} /> },
]

function UserDrawer({ open, profile, onClose }: { open: boolean; profile: Profile | null; onClose: () => void }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { me, can, has, creatableKinds } = useAuth()
  const isAdmin = !!me?.profile.is_admin
  const { data: customers = [] } = useCustomers()
  const { data: contractors = [] } = useContractors()
  const [tab, setTab] = useState<'details' | 'work' | 'permissions'>('details')

  /* Resolved by the server through `app.may_create_profile` — the same
     predicate `profiles_insert` uses — so the form cannot offer a kind the
     write would refuse. Someone who may open only one kind is not asked. */
  const kinds = creatableKinds()
  const pinnedKind = kinds.length === 1 ? kinds[0] : null
  /* ‏"מנהל מערכת" הוא אפשרות בבורר ולא מתג נסתר בתחתית הטופס, ולכן הוא נגזר
     מאותה רשימה: הוא שורת `staff`, ומי שרשאי לפתוח מנהל הוא מי שמחזיק את
     `users.set_admin` — בדיוק התנאי של `app.may_create_profile`. */
  const canSetAdmin = has(PERM.USERS_SET_ADMIN)
  const typeOptions: UserType[] = kinds.flatMap((k) =>
    k === 'staff' && canSetAdmin ? (['staff', 'admin'] as UserType[]) : [k],
  )
  const pinnedType = typeOptions.length === 1 ? typeOptions[0] : null

  const [form, setForm] = useState({
    full_name: '',
    phone: '',
    email: '',
    notes: '',
    user_type: 'staff' as UserType,
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
        user_type: userTypeOf(profile),
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
        user_type: pinnedType ?? 'staff',
        is_admin: false,
        is_active: true,
        // pinned to the actor's own company, exactly as profiles_insert requires
        customer_id: pinnedKind === 'customer_user' ? (me?.profile.customer_id ?? '') : '',
        contractor_id: pinnedKind === 'contractor_user' ? (me?.profile.contractor_id ?? '') : '',
        roles: pinnedKind && pinnedKind !== 'staff' ? [] : ['worker'],
      })
      setLogin({ email: '', password: '' })
    }
  }, [open, profile])

  const save = useMutation({
    mutationFn: async () => {
      if (!form.full_name.trim()) throw new Error('חובה להזין שם')
      const kind = kindOfType(form.user_type)
      /* מנהל מערכת הוא הדגל, וצוות הוא מה שהמתג אומר עליו. שאר הסוגים אינם
         מנהלים בשום מקרה, ולכן בחירה בהם *מכבה* את הדגל ולא רק נמנעת מלהדליק
         אותו — אחרת שינוי סוג היה משאיר אדמין מאחור. */
      const wantsAdmin = form.user_type === 'admin' || (form.user_type === 'staff' && form.is_admin)
      const base = {
        full_name: form.full_name,
        phone: form.phone || null,
        email: form.email || null,
        notes: form.notes || null,
        user_kind: kind,
        /* נשלח על ידי מי שרשאי לקבוע אותו — אותו מפתח שמראה את הבורר ואת
           המתג, ואותו תנאי ש-`app.guard_profile_write` אוכף בשרת. */
        is_admin: canSetAdmin ? wantsAdmin : undefined,
        is_active: form.is_active,
        customer_id: form.user_type === 'customer_user' ? form.customer_id || null : null,
        /* לא רק ל-`contractor_user`: עובד צוות שגם מביא סגל משלו נושא את
           העמודה הזאת, וזה מה שפותח לו את הצד הקבלני (0075). האילוץ
           `profiles_contractor_kind` (0001) תמיד הרשה את זה — השורה הזאת
           היא שאיפסה אותה בכל שמירה. `customer_user` עדיין מנוקה: לקוח
           שהוא גם קבלן אינו מקרה שקיים. */
        contractor_id: form.user_type === 'customer_user' ? null : form.contractor_id || null,
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
      /* ‏'admin' אינו כאן בכוונה: מנהל מערכת שנפתח כסוג משלו אינו עובד,
         ותפקיד צוות היה מכניס אותו לרוסטר לוח המשמרות ולרשימות השיבוץ. */
      await supabase.from('staff_roles').delete().eq('profile_id', profileId)
      if (form.user_type === 'staff' && form.roles.length) {
        const { error } = await supabase.from('staff_roles').insert(form.roles.map((role) => ({ profile_id: profileId, role })))
        if (error) throw error
      }

      /* שינוי סוג משתמש מפקיע את תפקידי ההרשאה שהוצמדו לסוג הקודם:
         `app.my_role_ids()` (0067) מסנן אותם, כלומר הם נשארים מוצמדים ואינם
         מעניקים דבר. בלי הניקוי הזה המשתמש יוצא מהשמירה עם פחות הרשאות ממה
         שמסך הניהול מראה — וזה בדיוק המצב שנמצא בפרודקשן. תפקיד בלי
         `user_kind` (כמו "קבלן — בנוסף לתפקיד") שורד כל שינוי סוג. */
      if (profile && profile.user_kind !== kind) {
        const { data: strays } = await supabase
          .from('profile_roles')
          .select('role_id, permission_roles!inner(user_kind)')
          .eq('profile_id', profileId)
          .not('permission_roles.user_kind', 'is', null)
          .neq('permission_roles.user_kind', kind)
        if (strays?.length) {
          await supabase
            .from('profile_roles')
            .delete()
            .eq('profile_id', profileId)
            .in('role_id', strays.map((s) => s.role_id))
        }
        return { dropped: strays?.length ?? 0 }
      }
    },
    onSuccess: (r) => {
      if (r?.dropped) {
        toast.info(`המשתמש נשמר · ${r.dropped} תפקידים שאינם מתאימים לסוג החדש הוסרו`)
        void qc.invalidateQueries({ queryKey: ['profile_roles'] })
        void qc.invalidateQueries({ queryKey: ['profiles'] })
        onClose()
        return
      }
      toast.success('המשתמש נשמר')
      void qc.invalidateQueries({ queryKey: ['profiles'] })
      onClose()
    },
    onError: (e) => toast.error(errorMessage(e)),
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
    onError: (e) => toast.error(errorMessage(e)),
  })

  const resetPassword = useMutation({
    mutationFn: async () => {
      if (!login.password) throw new Error('חובה להזין סיסמה חדשה')
      await invokeFunction('admin-users', { action: 'set_password', profile_id: profile?.id, password: login.password })
    },
    onSuccess: () => {
      toast.success('הסיסמה עודכנה')
      setLogin((l) => ({ ...l, password: '' }))
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const nameError = touched && !form.full_name.trim() ? 'חובה להזין שם' : undefined
  const linkError =
    touched && form.user_type === 'customer_user' && !form.customer_id
      ? 'יש לבחור לקוח'
      : touched && form.user_type === 'contractor_user' && !form.contractor_id
        ? 'יש לבחור קבלן'
        : undefined
  const canSave = can('users', profile ? 'edit' : 'create') || isAdmin
  // הלשונית הזו כותבת ל-worker_pay_settings מאחורי מפתחות משלה; מי שאין לו
  // אף אחד משניהם היה מקבל כרטיס ריק.
  const canWorkTab = isAdmin || has(PERM.ATTENDANCE_MANAGE_PAY) || has(PERM.ATTENDANCE_MANAGE_CLOCK)
  const drawerTabs = DRAWER_TABS.filter((x) => x.key !== 'work' || canWorkTab)

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
      description={profile ? kindLabels[userTypeOf(profile)] : 'הוספת מנהל, עובד, משתמש לקוח או משתמש קבלן'}
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
      {profile && <Tabs className="mb-4" size="sm" items={drawerTabs} value={tab} onChange={setTab} />}

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
              <Input type="tel" autoComplete="tel" dir="ltr" value={form.phone} onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))} />
            </Field>
          </div>

          {!pinnedType && (
            <Field label="סוג משתמש" hint="קובע את סט ההרשאות ואת המסכים שהמשתמש רואה">
              <Select
                value={form.user_type}
                onChange={(e) => setForm((f) => ({ ...f, user_type: e.target.value as UserType }))}
              >
                {typeOptions.map((t) => (
                  <option key={t} value={t}>
                    {USER_TYPE_OPTION_LABELS[t]}
                  </option>
                ))}
              </Select>
            </Field>
          )}

          {/* מנהל מערכת אינו עובד: אין לו תפקיד צוות, ולכן הוא אינו נכנס
              לרוסטר לוח המשמרות ולרשימות השיבוץ. מי שגם מנהל וגם עובד נפתח
              כ"צוות" ומקבל את המתג שבתחתית הטופס. */}
          {form.user_type === 'admin' && (
            <p className="rounded-lg border border-line-subtle bg-subtle/50 px-3 py-2.5 type-caption text-ink-secondary">
              גישה מלאה לכל המסכים, בלי שיבוץ ובלי שעון נוכחות. למי שגם מנהל וגם עובד — בחרו "צוות"
              והדליקו את המתג "מנהל מערכת" שבתחתית.
            </p>
          )}

          {form.user_type === 'staff' && (
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

          {form.user_type === 'customer_user' && !pinnedKind && (
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

          {form.user_type === 'contractor_user' && !pinnedKind && (
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

          {/* עובד שגם מביא סגל משלו. הוא נשאר עובד לכל דבר — שעון, משמרות
              ושכר שעתי — ומקבל בנוסף את הסגל, השיבוץ והכספים של הקבלן שהוא
              מקושר אליו. ‏0075 שינה את ההכרעה מ"מי הוא" ל"למי הוא שייך",
              ולכן העמודה הזאת על פרופיל צוות היא כל מה שנדרש; את התפקיד
              ‏"קבלן — בנוסף לתפקיד" מצמידים בלשונית ההרשאות. */}
          {form.user_type === 'staff' && !pinnedKind && (
            <Field
              label="גם קבלן"
              hint="לעובד שמביא גם סגל משלו. בחירת קבלן פותחת לו את הסגל, השיבוץ והכספים שלו — בנוסף לתפקיד שלו כעובד"
            >
              <Select value={form.contractor_id} onChange={(e) => setForm((f) => ({ ...f, contractor_id: e.target.value }))}>
                <option value="">לא — עובד בלבד</option>
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
            {canSetAdmin && form.user_type === 'staff' && (
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
                  {has(PERM.USERS_RESET_PASSWORD) && (
                    <Button loading={resetPassword.isPending} disabled={!login.password} onClick={() => resetPassword.mutate()}>
                      איפוס סיסמה
                    </Button>
                  )}
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
      ) : tab === 'work' ? (
        profile && <EmployeeWorkSettingsCard profileId={profile.id} />
      ) : (
        profile && <UserPermissionsTab profile={profile} />
      )}
    </Drawer>
  )
}
