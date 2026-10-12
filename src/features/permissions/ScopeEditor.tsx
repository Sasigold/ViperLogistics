/**
 * Data scopes — the "which rows may they see" half of the model.
 *
 * A scope narrows a resource along one dimension. Dimensions AND together and
 * values within a dimension OR: customers [א, ב] plus a −7…+30 day window means
 * "tasks for either of those two customers, in that window". No rows for a
 * resource means no restriction beyond the user's kind (a customer user never
 * sees another customer; a contractor sees only what was delegated to it).
 *
 * These are enforced in the SELECT policies, not here — this screen only
 * writes the rules. Since 0214 it also shows, for a person, what their roles
 * impose and what the result is in plain words: before that, a worker whose
 * role says "only what is assigned to me" was shown here as "no restriction",
 * and one personal row silently replaced every role restriction.
 */
import { useMemo, useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { CalendarClock, Eye, Filter, ICON, Plus, STROKE, Trash2 } from '../../components/ui/icons'
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
  useRolesScopes,
  refreshOwnCapabilities,
} from '../../lib/permissions'
import { describeScope, effectiveRoleIds, effectiveScope } from '../../lib/scopes'
import { useContractors, useCustomers, useStatuses, useTaskTypes, useTrucks, useExecutionMethods } from '../../lib/queries'
import type { PermissionScope, ScopeType, UserKind } from '../../types/domain'
import { errorMessage } from '../../lib/errors'

export type ScopeSubject =
  | {
      kind: 'user'
      profileId: string
      userKind: UserKind
      customerId?: string | null
      contractorId?: string | null
    }
  | { kind: 'role'; roleId: string }

/** "ללא הגבלה" אישית קיימת רק לאדם: לתפקיד היא אינה מבטלת דבר (0214). */
const typesFor = (resource: string, subject: ScopeSubject): ScopeType[] => {
  const base = (SCOPE_RESOURCES.find((r) => r.key === resource)?.types ?? []) as ScopeType[]
  return subject.kind === 'user' ? [...base, 'all'] : base
}

export function ScopeEditor({ subject }: { subject: ScopeSubject }) {
  const toast = useToast()
  const qc = useQueryClient()
  const profileId = subject.kind === 'user' ? subject.profileId : null
  const roleId = subject.kind === 'role' ? subject.roleId : null

  const { data: scopes = [], isLoading } = usePermissionScopes(profileId, roleId)
  const [resource, setResource] = useState('tasks')
  const [scopeType, setScopeType] = useState<ScopeType>('customers')

  const { data: customers = [] } = useCustomers()
  const { data: contractors = [] } = useContractors()
  const { data: taskTypes = [] } = useTaskTypes()
  const { data: statuses = [] } = useStatuses()
  const { data: trucks = [] } = useTrucks()
  const { data: methods = [] } = useExecutionMethods()

  // מה שהאדם יורש: התפקידים שבתוקף לו, וההגבלות שהם נושאים
  const { data: roles = [] } = usePermissionRoles()
  const { data: heldRoleIds = [] } = useProfileRoles(profileId)
  const activeRoleIds = useMemo(
    () => (subject.kind === 'user' ? effectiveRoleIds(roles, heldRoleIds, subject.userKind) : []),
    [subject, roles, heldRoleIds],
  )
  const { data: roleScopes = [] } = useRolesScopes(activeRoleIds)
  const roleName = (id: string | null) => roles.find((r) => r.id === id)?.name_he ?? 'תפקיד'

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
  const nameOf = (type: ScopeType, id: string) => optionsFor(type).find((o) => o.id === id)?.label ?? 'לא ידוע'

  const invalidate = () => {
    void qc.invalidateQueries({ queryKey: ['permission_scopes'] })
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
      toast.success(scopeType === 'all' ? 'ההגבלות מהתפקיד בוטלו למשתמש הזה' : 'הוגדרה הגבלת נתונים')
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

  const allowedTypes = typesFor(resource, subject)
  const resourceLabel = (key: string) => SCOPE_RESOURCES.find((r) => r.key === key)?.label ?? key

  return (
    <div className="space-y-4">
      {subject.kind === 'user' && (
        <EffectiveCard
          subject={subject}
          personal={scopes}
          fromRoles={roleScopes}
          roleName={roleName}
          nameOf={nameOf}
          customerName={customers.find((c) => c.id === subject.customerId)?.name ?? null}
          contractorName={contractors.find((c) => c.id === subject.contractorId)?.name ?? null}
        />
      )}

      <Card>
        <CardHeader
          title={subject.kind === 'user' ? 'הגבלות אישיות' : 'הגבלת נתונים'}
          subtitle={
            subject.kind === 'user'
              ? 'הגבלה אישית מחליפה את ההגבלה מהתפקיד מאותו סוג בלבד. כדי לבטל את כל ההגבלות מהתפקיד — "ללא הגבלה".'
              : 'כל מי שמחזיק את התפקיד מוגבל כך. כל הגבלה מצמצמת מימד אחד.'
          }
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
                  const types = typesFor(next, subject)
                  if (!types.includes(scopeType)) setScopeType(types[0] ?? 'customers')
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

          {scopes.length === 0 ? (
            <EmptyState
              art="check"
              title={subject.kind === 'user' ? 'אין הגבלות אישיות' : 'ללא הגבלת נתונים'}
              description={
                subject.kind === 'user'
                  ? 'חלות רק ההגבלות מהתפקיד (למעלה) והגדר של סוג המשתמש'
                  : 'מי שמחזיק את התפקיד רואה כל מה שההרשאות שלו מתירות — במסגרת סוג המשתמש שלו'
              }
            />
          ) : (
            <ul className="space-y-2">
              {scopes.map((s) => (
                <li key={s.id} className="rounded-lg border border-line-subtle p-3">
                  <div className="mb-2 flex items-center gap-2">
                    <Badge tone="primary">{resourceLabel(s.resource)}</Badge>
                    <span className="type-body font-semibold">{SCOPE_LABELS[s.scope_type]}</span>
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
                    <p className="type-caption text-ink-tertiary">רואה רק רשומות ששובץ אליהן או שיצר בעצמו</p>
                  ) : s.scope_type === 'all' ? (
                    <p className="type-caption text-warning-text">
                      כל ההגבלות שמגיעות מהתפקיד על {resourceLabel(s.resource)} בוטלו למשתמש הזה. הגדר של סוג
                      המשתמש נשאר: משתמש לקוח רואה רק את הלקוח שלו, וקבלן רק את מה שהואצל לו.
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
                          לא נבחר אף ערך — עד שייבחר, המשתמש לא יראה אף רשומה ב{resourceLabel(s.resource)}
                        </p>
                      )}
                    </>
                  )}
                </li>
              ))}
            </ul>
          )}
        </CardBody>
      </Card>
    </div>
  )
}

/**
 * מה שהמשתמש רואה בפועל, מודול אחר מודול — הגדר של סוג המשתמש, ההגבלות
 * מהתפקיד (ואם הוחלפו), וההגבלות האישיות, בשפה ולא בטבלה.
 */
function EffectiveCard({
  subject,
  personal,
  fromRoles,
  roleName,
  nameOf,
  customerName,
  contractorName,
}: {
  subject: Extract<ScopeSubject, { kind: 'user' }>
  personal: PermissionScope[]
  fromRoles: PermissionScope[]
  roleName: (id: string | null) => string
  nameOf: (type: ScopeType, id: string) => string
  customerName: string | null
  contractorName: string | null
}) {
  return (
    <Card>
      <CardHeader
        title="מה המשתמש רואה בפועל"
        subtitle="הגדר של סוג המשתמש, ההגבלות מהתפקיד וההגבלות האישיות — כפי שהשרת אוכף אותם"
        icon={<Eye size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody padded={false}>
        <ul>
          {SCOPE_RESOURCES.map((r) => {
            const eff = effectiveScope(r.key, personal, fromRoles)
            const lines = describeScope(r.key, eff, {
              userKind: subject.userKind,
              customerName,
              contractorName,
              nameOf,
            })
            const inherited = fromRoles.filter((s) => s.resource === r.key && s.scope_type !== 'all')
            return (
              <li key={r.key} className="border-b border-line-subtle px-4 py-3 last:border-0">
                <p className="type-body font-semibold">{r.label}</p>
                <ul className="mt-1 list-disc space-y-0.5 ps-5">
                  {lines.map((line) => (
                    <li key={line} className="type-body text-ink-secondary">
                      {line}
                    </li>
                  ))}
                </ul>
                {inherited.length > 0 && (
                  <div className="mt-2 flex flex-wrap items-center gap-1.5">
                    <span className="type-caption text-ink-tertiary">מהתפקיד:</span>
                    {inherited.map((s) => {
                      const replaced = eff.overridden.includes(s)
                      return (
                        <Badge key={s.id} tone={replaced ? 'neutral' : 'info'}>
                          {roleName(s.role_id)} · {SCOPE_LABELS[s.scope_type]}
                          {replaced ? ' (בוטל אישית)' : ''}
                        </Badge>
                      )
                    })}
                  </div>
                )}
              </li>
            )
          })}
        </ul>
      </CardBody>
    </Card>
  )
}
