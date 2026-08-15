/**
 * The permissions tab inside the user drawer.
 *
 * Four sections, in the order you actually configure someone: give them a role,
 * then adjust individual permissions, then fields, then how much data they see.
 * Each of the last three is the same component the role editor uses, pointed at
 * a person instead of a role.
 */
import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Filter, ICON, KeyRound, STROKE, Shield, Users } from '../../components/ui/icons'
import {
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  Checkbox,
  EmptyState,
  Skeleton,
  Tabs,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM, usePermissionRoles, useProfileRoles, refreshOwnCapabilities } from '../../lib/permissions'
import { PermissionMatrix } from './PermissionMatrix'
import { ScopeEditor } from './ScopeEditor'
import { FieldPermissions } from './FieldPermissions'
import { UserFormFieldsCard } from './UserFormFieldsCard'
import type { Profile } from '../../types/domain'
import { errorMessage } from '../../lib/errors'

const TABS = [
  { key: 'roles' as const, label: 'תפקידים', icon: <Users size={ICON.sm} /> },
  { key: 'permissions' as const, label: 'הרשאות', icon: <Shield size={ICON.sm} /> },
  { key: 'fields' as const, label: 'שדות', icon: <KeyRound size={ICON.sm} /> },
  { key: 'scopes' as const, label: 'נתונים', icon: <Filter size={ICON.sm} /> },
]

export function UserPermissionsTab({ profile }: { profile: Profile }) {
  const [tab, setTab] = useState<'roles' | 'permissions' | 'fields' | 'scopes'>('roles')
  const has = useAuth((s) => s.has)

  if (profile.is_admin) {
    return (
      <EmptyState
        art="check"
        title="מנהל מערכת"
        description="גישה מלאה לכל המודולים, השדות והנתונים — טבלת ההרשאות אינה חלה על מנהלי מערכת"
      />
    )
  }

  if (!has(PERM.USERS_MANAGE_PERMISSIONS)) {
    return (
      <EmptyState
        art="alert"
        title="אין הרשאה"
        description="נדרשת הרשאת ״עריכת הרשאות פר-משתמש״ כדי לשנות את ההגדרות האלה"
      />
    )
  }

  return (
    <div className="space-y-4">
      <Tabs items={TABS.filter((t) => t.key !== 'scopes' || has(PERM.USERS_MANAGE_SCOPES))} value={tab} onChange={setTab} />
      {tab === 'roles' && <RolesSection profile={profile} />}
      {tab === 'permissions' && (
        /* `app.guard_permission_grant` refuses a grant the actor does not hold
           themselves, so offering it here would only produce an error. `has`
           short-circuits for admins, who are unaffected. */
        <PermissionMatrix
          subject={{ kind: 'user', profileId: profile.id, userKind: profile.user_kind }}
          canGrant={(key) => has(key)}
        />
      )}
      {tab === 'fields' && (
        <div className="space-y-4">
          <FieldPermissions subject={{ kind: 'user', profileId: profile.id }} />
          {/* the event form's shape, as opposed to access to its data — only
              exists for someone whose company configured a form to narrow */}
          {profile.customer_id && <UserFormFieldsCard profile={profile} />}
        </div>
      )}
      {tab === 'scopes' && <ScopeEditor subject={{ kind: 'user', profileId: profile.id }} />}
    </div>
  )
}

function RolesSection({ profile }: { profile: Profile }) {
  const toast = useToast()
  const qc = useQueryClient()
  const has = useAuth((s) => s.has)
  const { data: roles = [], isLoading } = usePermissionRoles()
  const { data: mine = [] } = useProfileRoles(profile.id)
  const canAssign = has(PERM.USERS_ASSIGN_ROLES)

  const toggle = useMutation({
    mutationFn: async ({ roleId, on }: { roleId: string; on: boolean }) => {
      if (on) {
        const { error } = await supabase.from('profile_roles').insert({ profile_id: profile.id, role_id: roleId })
        if (error) throw error
      } else {
        const { error } = await supabase
          .from('profile_roles')
          .delete()
          .eq('profile_id', profile.id)
          .eq('role_id', roleId)
        if (error) throw error
      }
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['profile_roles'] })
      void qc.invalidateQueries({ queryKey: ['role_permissions'] })
      refreshOwnCapabilities()
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  if (isLoading) return <Skeleton className="h-64 w-full" />

  // a role scoped to another kind of user would grant nothing useful here
  const applicable = roles.filter((r) => !r.user_kind || r.user_kind === profile.user_kind)

  /* תפקיד שמוצמד למשתמש ואינו תואם לסוג שלו.
     `app.my_role_ids()` (0067) מסנן אותו, ולכן הוא אינו מעניק דבר — והסינון
     שלמעלה גם הסתיר אותו מהמסך, כך שלא היה אפשר לראות שהוא שם ולא היה אפשר
     להסיר אותו. כך נראה בפרודקשן משתמש קבלן שמחזיק שני תפקידי לקוח: מי
     שהגדיר אותו בטוח שנתן לו הרשאות, והוא נכנס בלי כלום. ‏0075 §3 מנקה את
     השורות הקיימות; זה מה שמונע מהן לחזור בשקט. */
  const stray = roles.filter((r) => r.user_kind && r.user_kind !== profile.user_kind && mine.includes(r.id))

  return (
    <Card>
      <CardHeader
        title="תפקידים"
        subtitle="נקודת ההתחלה. אפשר להוסיף חריגות אישיות בלשונית ״הרשאות״ — הן גוברות על התפקיד."
        icon={<Users size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody padded={false}>
        <ul>
          {applicable.map((r) => (
            <li key={r.id} className="border-b border-line-subtle px-4 py-3 last:border-0">
              <Checkbox
                checked={mine.includes(r.id)}
                disabled={!canAssign}
                onChange={(v) => toggle.mutate({ roleId: r.id, on: v })}
                label={
                  <span className="flex items-center gap-2">
                    {r.name_he}
                    {r.is_system && <Badge tone="neutral">מערכת</Badge>}
                  </span>
                }
                description={r.description_he ?? undefined}
              />
            </li>
          ))}
        </ul>
        {applicable.length === 0 && stray.length === 0 && (
          <div className="p-6">
            <EmptyState
              art="people"
              title="אין תפקידים מתאימים"
              description={`לא הוגדרו תפקידים עבור סוג המשתמש הזה`}
            />
          </div>
        )}
        {stray.length > 0 && (
          <div className="border-t border-line-subtle bg-warning-subtle/30 p-4">
            <p className="type-caption text-ink-secondary">
              התפקידים הבאים מוצמדים למשתמש אבל אינם מתאימים לסוג שלו, ולכן אינם מעניקים לו דבר. סביר שסוג
              המשתמש שונה אחרי שהם הוצמדו.
            </p>
            <ul className="mt-2">
              {stray.map((r) => (
                <li key={r.id} className="flex items-center gap-2 py-1.5">
                  <Badge tone="warning">אינו בתוקף</Badge>
                  <span className="type-body">{r.name_he}</span>
                  {canAssign && (
                    <Button size="sm" variant="ghost" onClick={() => toggle.mutate({ roleId: r.id, on: false })}>
                      הסרה
                    </Button>
                  )}
                </li>
              ))}
            </ul>
          </div>
        )}
      </CardBody>
    </Card>
  )
}
