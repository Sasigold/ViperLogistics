/**
 * Data scopes — the "which rows may they see" half of the model.
 *
 * A scope narrows a resource along one dimension. Dimensions AND together and
 * values within a dimension OR: customers [א, ב] plus a −7…+30 day window means
 * "tasks for either of those two customers, in that window". No rows for a
 * resource means no restriction.
 *
 * These are enforced in the SELECT policies, not here — this screen only
 * writes the rules.
 *
 * On a user, any row of their own for a module replaces the role rows for that
 * module (app.scope_rows), so the user view also lists what still comes from
 * their roles, and offers "ללא הגבלה" — a row whose only job is that override.
 */
import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { CalendarClock, Filter, ICON, Plus, STROKE, Trash2 } from '../../components/ui/icons'
import {
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  Field,
  IconButton,
  Input,
  MultiSelect,
  Select,
  Skeleton,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import {
  SCOPE_LABELS,
  SCOPE_RESOURCES,
  usePermissionRoles,
  usePermissionScopes,
  useProfileRoles,
  useRoleScopes,
  refreshOwnCapabilities,
} from '../../lib/permissions'
import { applicableRoleIds, inheritedScopes } from '../../lib/effectiveScopes'
import { useContractors, useCustomers, useStatuses, useTaskTypes, useTrucks, useExecutionMethods } from '../../lib/queries'
import type { PermissionScope, ScopeType, UserKind } from '../../types/domain'
import { errorMessage } from '../../lib/errors'

export type ScopeSubject = { kind: 'user'; profileId: string; userKind: UserKind } | { kind: 'role'; roleId: string }

export function ScopeEditor({ subject }: { subject: ScopeSubject }) {
  const toast = useToast()
  const qc = useQueryClient()
  const profileId = subject.kind === 'user' ? subject.profileId : null
  const roleId = subject.kind === 'role' ? subject.roleId : null

  const { data: scopes = [], isLoading } = usePermissionScopes(profileId, roleId)
  const { data: allRoles = [] } = usePermissionRoles()
  const { data: assignedRoles = [] } = useProfileRoles(profileId)
  const myRoleIds =
    subject.kind === 'user' ? applicableRoleIds(allRoles, assignedRoles, subject.userKind) : []
  const { data: roleScopes = [] } = useRoleScopes(myRoleIds)
  const inherited = inheritedScopes(roleScopes, myRoleIds, scopes)
  const roleName = new Map(allRoles.map((r) => [r.id, r.name_he]))
  const roleRestricted = new Set(roleScopes.map((s) => s.resource))
  const [resource, setResource] = useState('tasks')
  const [scopeType, setScopeType] = useState<ScopeType>('customers')

  const { data: customers = [] } = useCustomers()
  const { data: contractors = [] } = useContractors()
  const { data: taskTypes = [] } = useTaskTypes()
  const { data: statuses = [] } = useStatuses()
  const { data: trucks = [] } = useTrucks()
  const { data: methods = [] } = useExecutionMethods()

  const optionsFor = (type: ScopeType): { id: string; label: string }[] => {
    switch (type) {
      case 'customers':
        return customers.map((c) => ({ id: c.id, label: c.name }))
      case 'contractors':
        return contractors.map((c) => ({ id: c.id, label: c.name }))
      case 'task_types':
        return taskTypes.map((t) => ({ id: t.id, label: t.name }))
      case 'statuses':
        return statuses.map((s) => ({ id: s.id, label: `${s.name} (${s.entity === 'task' ? 'משימה' : 'אירוע'})` }))
      case 'trucks':
        return trucks.map((t) => ({ id: t.id, label: t.name }))
      case 'execution_methods':
        return methods.map((m) => ({ id: m.id, label: m.name }))
      default:
        return []
    }
  }

  const invalidate = () => {
    void qc.invalidateQueries({ queryKey: ['permission_scopes', profileId ?? null, roleId ?? null] })
    refreshOwnCapabilities()
  }

  const add = useMutation({
    mutationFn: async () => {
      const base = subject.kind === 'user' ? { profile_id: profileId } : { role_id: roleId }
      const row: Record<string, unknown> = { ...base, resource, scope_type: scopeType, scope_values: [] }
      if (scopeType === 'date_window') {
        row.days_back = 7
        row.days_forward = 30
      }
      const { error } = await supabase.from('permission_scopes').insert(row)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('הוגדרה הגבלת נתונים')
      invalidate()
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const patch = useMutation({
    mutationFn: async ({ id, values }: { id: string; values: Record<string, unknown> }) => {
      const { error } = await supabase.from('permission_scopes').update(values).eq('id', id)
      if (error) throw error
    },
    onSuccess: invalidate,
    onError: (e) => toast.error(errorMessage(e)),
  })

  const remove = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('permission_scopes').delete().eq('id', id)
      if (error) throw error
    },
    onSuccess: invalidate,
    onError: (e) => toast.error(errorMessage(e)),
  })

  const toggleValue = (row: PermissionScope, id: string) => {
    const next = row.scope_values.includes(id)
      ? row.scope_values.filter((v) => v !== id)
      : [...row.scope_values, id]
    patch.mutate({ id: row.id, values: { scope_values: next } })
  }

  if (isLoading) return <Skeleton className="h-64 w-full" />

  const typesFor = (key: string): string[] => {
    const types = SCOPE_RESOURCES.find((r) => r.key === key)?.types ?? []
    // on a role "all" restricts nothing and overrides nothing — it only means something on a user
    return subject.kind === 'user' ? [...types, 'all'] : types
  }
  const allowedTypes = typesFor(resource)

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader
          title="הגבלת נתונים"
          subtitle="בלי הגבלות — רואים את כל מה שההרשאות מתירות. כל הגבלה מצמצמת מימד אחד."
          icon={<Filter size={ICON.md} strokeWidth={STROKE} />}
        />
        <CardBody className="space-y-3">
          <div className="flex flex-wrap items-end gap-2">
            <Field label="מודול" className="min-w-40 flex-1">
              <Select
                value={resource}
                onChange={(e) => {
                  const next = e.target.value
                  setResource(next)
                  const types = typesFor(next)
                  if (!types.includes(scopeType)) setScopeType((types[0] as ScopeType) ?? 'customers')
                }}
              >
                {SCOPE_RESOURCES.map((r) => (
                  <option key={r.key} value={r.key}>
                    {r.label}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="סוג ההגבלה" className="min-w-48 flex-1">
              <Select value={scopeType} onChange={(e) => setScopeType(e.target.value as ScopeType)}>
                {allowedTypes.map((t) => (
                  <option key={t} value={t}>
                    {SCOPE_LABELS[t]}
                  </option>
                ))}
              </Select>
            </Field>
            <Button variant="primary" loading={add.isPending} onClick={() => add.mutate()}>
              <Plus size={ICON.sm} strokeWidth={STROKE} />
              הוספה
            </Button>
          </div>

          {scopes.length === 0 && inherited.length === 0 ? (
            <EmptyState
              art="check"
              title="ללא הגבלת נתונים"
              description="המשתמש רואה כל מה שההרשאות שלו מתירות, בכל הלקוחות ובכל התאריכים"
            />
          ) : (
            <ul className="space-y-2">
              {scopes.map((s) => (
                <li key={s.id} className="rounded-lg border border-line-subtle p-3">
                  <div className="mb-2 flex items-center gap-2">
                    <Badge tone="primary">
                      {SCOPE_RESOURCES.find((r) => r.key === s.resource)?.label ?? s.resource}
                    </Badge>
                    <span className="type-body font-semibold">{SCOPE_LABELS[s.scope_type]}</span>
                    {subject.kind === 'user' && roleRestricted.has(s.resource) && (
                      <span className="type-caption text-ink-tertiary">במקום ההגבלה שמגיעה מהתפקיד</span>
                    )}
                    <IconButton
                      className="ms-auto"
                      label="הסרת ההגבלה"
                      onClick={() => remove.mutate(s.id)}
                      variant="danger"
                    >
                      <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                    </IconButton>
                  </div>

                  {s.scope_type === 'date_window' ? (
                    <div className="grid gap-3 sm:grid-cols-2">
                      <Field label="ימים אחורה" hint="כמה זמן לאחור המשתמש רואה">
                        <Input
                          type="number"
                          min="0"
                          leading={<CalendarClock size={ICON.sm} strokeWidth={STROKE} />}
                          defaultValue={s.days_back ?? ''}
                          onBlur={(e) =>
                            patch.mutate({
                              id: s.id,
                              values: { days_back: e.target.value === '' ? null : Number(e.target.value) },
                            })
                          }
                        />
                      </Field>
                      <Field label="ימים קדימה">
                        <Input
                          type="number"
                          min="0"
                          leading={<CalendarClock size={ICON.sm} strokeWidth={STROKE} />}
                          defaultValue={s.days_forward ?? ''}
                          onBlur={(e) =>
                            patch.mutate({
                              id: s.id,
                              values: { days_forward: e.target.value === '' ? null : Number(e.target.value) },
                            })
                          }
                        />
                      </Field>
                    </div>
                  ) : s.scope_type === 'own' ? (
                    <p className="type-caption text-ink-tertiary">
                      רואה רק רשומות ששובץ אליהן או שיצר בעצמו
                    </p>
                  ) : s.scope_type === 'all' ? (
                    <p className="type-caption text-ink-tertiary">
                      ללא הגבלה — מבטל הגבלות שמגיעות מתפקיד
                    </p>
                  ) : (
                    <>
                      <MultiSelect
                        options={optionsFor(s.scope_type)}
                        values={s.scope_values}
                        onToggle={(id) => toggleValue(s, id)}
                        placeholder="בחירה..."
                      />
                      {s.scope_values.length === 0 && (
                        <p className="mt-1 type-caption text-warning-text">
                          רשימה ריקה אינה מגבילה דבר — יש לבחור לפחות פריט אחד
                        </p>
                      )}
                    </>
                  )}
                </li>
              ))}
              {inherited.map((s) => (
                <li key={s.id} className="rounded-lg border border-dashed border-line-subtle p-3">
                  <div className="mb-1 flex flex-wrap items-center gap-2">
                    <Badge tone="primary">
                      {SCOPE_RESOURCES.find((r) => r.key === s.resource)?.label ?? s.resource}
                    </Badge>
                    <span className="type-body font-semibold">{SCOPE_LABELS[s.scope_type]}</span>
                    <Badge>מהתפקיד {roleName.get(s.role_id ?? '') ?? ''}</Badge>
                  </div>
                  <p className="type-caption text-ink-tertiary">
                    כדי לבטל אותה למשתמש הזה בלבד — הוסיפו לאותו מודול הגבלה מסוג ״{SCOPE_LABELS.all}״
                  </p>
                </li>
              ))}
            </ul>
          )}
        </CardBody>
      </Card>
    </div>
  )
}
