/**
 * Roles: reusable permission bundles.
 *
 * Editing a role edits everyone who holds it, which is the point — a policy
 * change is one edit rather than a sweep over every user. Individual exceptions
 * still live on the person and outrank the role.
 */
import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Filter, ICON, KeyRound, Plus, STROKE, Shield, Trash2, Users } from '../../components/ui/icons'
import {
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  Drawer,
  EmptyState,
  Field,
  IconButton,
  Input,
  Select,
  Skeleton,
  Tabs,
  Textarea,
  Tooltip,
  useConfirm,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { usePermissionRoles } from '../../lib/permissions'
import { PermissionMatrix } from './PermissionMatrix'
import { ScopeEditor } from './ScopeEditor'
import { FieldPermissions } from './FieldPermissions'
import type { PermissionRole } from '../../types/domain'

const KIND_LABELS: Record<string, string> = {
  staff: 'צוות',
  customer_user: 'משתמש לקוח',
  contractor_user: 'משתמש קבלן',
}

const ROLE_TABS = [
  { key: 'permissions' as const, label: 'הרשאות', icon: <Shield size={ICON.sm} /> },
  { key: 'fields' as const, label: 'שדות', icon: <KeyRound size={ICON.sm} /> },
  { key: 'scopes' as const, label: 'הגבלת נתונים', icon: <Filter size={ICON.sm} /> },
]

export function RolesTab() {
  const toast = useToast()
  const qc = useQueryClient()
  const { confirm, dialog } = useConfirm()
  const { data: roles = [], isLoading } = usePermissionRoles()
  const [editing, setEditing] = useState<PermissionRole | null>(null)
  const [creating, setCreating] = useState(false)
  const [form, setForm] = useState({ key: '', name_he: '', description_he: '', user_kind: '' })

  // how many people hold each role — the number that tells you whether an edit
  // here is a small change or a company-wide one
  const { data: counts = {} } = useQuery({
    queryKey: ['profile_roles', 'counts'],
    queryFn: async () => {
      const { data, error } = await supabase.from('profile_roles').select('role_id')
      if (error) throw error
      const map: Record<string, number> = {}
      for (const r of data as { role_id: string }[]) map[r.role_id] = (map[r.role_id] ?? 0) + 1
      return map
    },
  })

  const create = useMutation({
    mutationFn: async () => {
      if (!form.key.trim() || !form.name_he.trim()) throw new Error('חובה להזין מזהה ושם')
      const { error } = await supabase.from('permission_roles').insert({
        key: form.key.trim(),
        name_he: form.name_he.trim(),
        description_he: form.description_he || null,
        user_kind: form.user_kind || null,
        sort_order: (roles.at(-1)?.sort_order ?? 0) + 10,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('התפקיד נוצר')
      setCreating(false)
      setForm({ key: '', name_he: '', description_he: '', user_kind: '' })
      void qc.invalidateQueries({ queryKey: ['permission_roles'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const remove = useMutation({
    mutationFn: async (role: PermissionRole) => {
      const { error } = await supabase
        .from('permission_roles')
        .update({ deleted_at: new Date().toISOString(), is_active: false })
        .eq('id', role.id)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('התפקיד הוסר')
      void qc.invalidateQueries({ queryKey: ['permission_roles'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  if (isLoading) return <Skeleton className="h-72 w-full" />

  return (
    <div className="space-y-4">
      {dialog}
      <Card>
        <CardHeader
          title="תפקידים"
          subtitle="חבילת הרשאות לשימוש חוזר. שינוי בתפקיד חל מיד על כל מי שמשויך אליו."
          icon={<Shield size={ICON.md} strokeWidth={STROKE} />}
          actions={
            <Button variant="primary" size="sm" onClick={() => setCreating(true)}>
              <Plus size={ICON.sm} strokeWidth={STROKE} />
              תפקיד חדש
            </Button>
          }
        />
        <CardBody padded={false}>
          <ul>
            {roles.map((r) => (
              <li
                key={r.id}
                className="flex flex-wrap items-center gap-3 border-b border-line-subtle px-4 py-3 last:border-0"
              >
                <button
                  type="button"
                  onClick={() => setEditing(r)}
                  className="min-w-48 flex-1 text-start focus-visible:outline-none focus-visible:focus-ring"
                >
                  <p className="flex items-center gap-2 type-body font-semibold">
                    {r.name_he}
                    {r.is_system && <Badge tone="neutral">מערכת</Badge>}
                    {r.user_kind && <Badge tone="info">{KIND_LABELS[r.user_kind]}</Badge>}
                  </p>
                  {r.description_he && <p className="type-caption text-ink-tertiary">{r.description_he}</p>}
                </button>
                <span className="flex items-center gap-1.5 type-caption text-ink-tertiary">
                  <Users size={ICON.sm} strokeWidth={STROKE} />
                  {counts[r.id] ?? 0}
                </span>
                <Button size="sm" onClick={() => setEditing(r)}>
                  עריכה
                </Button>
                {!r.is_system && (
                  <Tooltip content="הסרת התפקיד">
                    <IconButton
                      label="הסרת התפקיד"
                      variant="danger"
                      onClick={async () => {
                        if (
                          await confirm(`להסיר את התפקיד "${r.name_he}"? מי שמשויך אליו יאבד את ההרשאות שהוא מעניק.`, {
                            title: 'הסרת תפקיד',
                            confirmLabel: 'הסרה',
                          })
                        )
                          remove.mutate(r)
                      }}
                    >
                      <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                    </IconButton>
                  </Tooltip>
                )}
              </li>
            ))}
          </ul>
          {roles.length === 0 && (
            <div className="p-6">
              <EmptyState art="people" title="אין תפקידים" description="צור תפקיד ראשון כדי לחסוך הגדרה ידנית לכל עובד" />
            </div>
          )}
        </CardBody>
      </Card>

      <Drawer
        open={creating}
        onClose={() => setCreating(false)}
        title="תפקיד חדש"
        description="הרשאות מוגדרות אחרי היצירה"
        footer={
          <>
            <Button onClick={() => setCreating(false)}>ביטול</Button>
            <Button variant="primary" loading={create.isPending} onClick={() => create.mutate()}>
              יצירה
            </Button>
          </>
        }
      >
        <div className="space-y-4">
          <Field label="שם התפקיד" required>
            <Input value={form.name_he} onChange={(e) => setForm((f) => ({ ...f, name_he: e.target.value }))} />
          </Field>
          <Field label="מזהה" required hint="באנגלית, ללא רווחים — משמש בקוד ובמיגרציות">
            <Input
              dir="ltr"
              value={form.key}
              onChange={(e) => setForm((f) => ({ ...f, key: e.target.value.replace(/\s/g, '_') }))}
            />
          </Field>
          <Field label="סוג משתמש" hint="ריק = ניתן לשייך לכל סוג משתמש">
            <Select value={form.user_kind} onChange={(e) => setForm((f) => ({ ...f, user_kind: e.target.value }))}>
              <option value="">הכול</option>
              {Object.entries(KIND_LABELS).map(([k, l]) => (
                <option key={k} value={k}>
                  {l}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="תיאור">
            <Textarea
              autoGrow
              value={form.description_he}
              onChange={(e) => setForm((f) => ({ ...f, description_he: e.target.value }))}
            />
          </Field>
        </div>
      </Drawer>

      {editing && <RoleDrawer role={editing} onClose={() => setEditing(null)} />}
    </div>
  )
}

function RoleDrawer({ role, onClose }: { role: PermissionRole; onClose: () => void }) {
  const [tab, setTab] = useState<'permissions' | 'fields' | 'scopes'>('permissions')
  return (
    <Drawer
      open
      onClose={onClose}
      title={role.name_he}
      description={role.description_he ?? 'עריכת ההרשאות של התפקיד'}
      footer={<Button onClick={onClose}>סגירה</Button>}
    >
      <div className="space-y-4">
        <Tabs items={ROLE_TABS} value={tab} onChange={setTab} />
        {tab === 'permissions' && (
          <PermissionMatrix subject={{ kind: 'role', roleId: role.id, userKind: role.user_kind }} />
        )}
        {tab === 'fields' && <FieldPermissions subject={{ kind: 'role', roleId: role.id }} />}
        {tab === 'scopes' && <ScopeEditor subject={{ kind: 'role', roleId: role.id }} />}
      </div>
    </Drawer>
  )
}

export default RolesTab
