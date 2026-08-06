/**
 * Per-field view/edit rights, rendered from `field_registry`.
 *
 * A field whose `edit_permission_key` is set is governed by that capability
 * rather than by a switch here, so this screen shows it as read-only and points
 * at the permission instead — otherwise two controls would claim to decide the
 * same thing and the one that loses would look broken.
 *
 * Hiding a field also blocks writing it: app.can_edit_field() returns false
 * whenever the viewer can't read the field, so the two switches can't be left
 * in a contradictory state.
 */
import { useMemo, useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Eye, EyeOff, ICON, KeyRound, Pencil, STROKE } from '../../components/ui/icons'
import {
  Badge,
  CollapsibleCard,
  SearchInput,
  Skeleton,
  Switch,
  Tooltip,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useFieldPermissionRows, useFieldRegistry, usePermissionModules } from '../../lib/permissions'
import type { FieldDef } from '../../types/domain'

export type FieldSubject = { kind: 'user'; profileId: string } | { kind: 'role'; roleId: string }

export function FieldPermissions({ subject }: { subject: FieldSubject }) {
  const toast = useToast()
  const qc = useQueryClient()
  const [q, setQ] = useState('')

  const profileId = subject.kind === 'user' ? subject.profileId : null
  const roleId = subject.kind === 'role' ? subject.roleId : null

  const { data: registry = [], isLoading } = useFieldRegistry()
  const { data: modules = [] } = usePermissionModules()
  const { data: rows = [] } = useFieldPermissionRows(profileId, roleId)

  const byField = useMemo(() => {
    const m = new Map<string, { id: string; can_view: boolean; can_edit: boolean }>()
    for (const r of rows) m.set(`${r.entity}.${r.field_key}`, r)
    return m
  }, [rows])

  const invalidate = () =>
    void qc.invalidateQueries({ queryKey: ['field_permissions', profileId ?? null, roleId ?? null] })

  const save = useMutation({
    mutationFn: async ({ field, canView, canEdit }: { field: FieldDef; canView: boolean; canEdit: boolean }) => {
      const existing = byField.get(`${field.entity}.${field.field_key}`)
      const isDefault = canView === field.default_can_view && canEdit === field.default_can_edit
      if (isDefault && existing) {
        const { error } = await supabase.from('field_permissions').delete().eq('id', existing.id)
        if (error) throw error
        return
      }
      if (isDefault) return
      const base = subject.kind === 'user' ? { profile_id: profileId } : { role_id: roleId }
      const { error } = await supabase.from('field_permissions').upsert({
        ...(existing ? { id: existing.id } : {}),
        ...base,
        entity: field.entity,
        field_key: field.field_key,
        can_view: canView,
        // a field that can't be read can't be written
        can_edit: canView && canEdit,
      })
      if (error) throw error
    },
    onSuccess: invalidate,
    onError: (e) => toast.error((e as Error).message),
  })

  const term = q.trim().toLowerCase()
  const grouped = useMemo(() => {
    const relevant = registry.filter(
      (f) =>
        !term ||
        f.label_he.toLowerCase().includes(term) ||
        f.field_key.toLowerCase().includes(term) ||
        f.entity.toLowerCase().includes(term),
    )
    return modules
      .map((m) => ({ module: m, items: relevant.filter((f) => f.module === m.key) }))
      .filter((g) => g.items.length > 0)
  }, [registry, modules, term])

  if (isLoading) return <Skeleton className="h-80 w-full" />

  return (
    <div className="space-y-3">
      <SearchInput value={q} onChange={(e) => setQ(e.target.value)} placeholder="חיפוש שדה..." />

      {grouped.map(({ module, items }) => (
        <CollapsibleCard
          key={module.key}
          title={module.label_he}
          subtitle={`${items.length} שדות`}
          icon={<KeyRound size={ICON.md} strokeWidth={STROKE} />}
          defaultOpen={!!term}
        >
          <ul className="space-y-1">
            {items.map((f) => {
              const row = byField.get(`${f.entity}.${f.field_key}`)
              const canView = row ? row.can_view : f.default_can_view
              const canEdit = row ? row.can_edit : f.default_can_edit
              return (
                <li
                  key={`${f.entity}.${f.field_key}`}
                  className="flex flex-wrap items-center gap-x-4 gap-y-2 rounded-lg px-2 py-2 hover:bg-subtle/50"
                >
                  <div className="min-w-44 flex-1">
                    <p className="flex items-center gap-1.5 type-body font-medium">
                      {f.label_he}
                      {f.is_sensitive && <Badge tone="warning">רגיש</Badge>}
                    </p>
                    <p className="type-caption text-ink-tertiary" dir="ltr">
                      {f.entity}.{f.field_key}
                    </p>
                  </div>

                  <div className="flex items-center gap-4">
                    <Switch
                      checked={canView}
                      onChange={(v) => save.mutate({ field: f, canView: v, canEdit })}
                      label={
                        <span className="flex items-center gap-1">
                          {canView ? <Eye size={ICON.sm} strokeWidth={STROKE} /> : <EyeOff size={ICON.sm} strokeWidth={STROKE} />}
                          צפייה
                        </span>
                      }
                    />
                    {f.edit_permission_key ? (
                      <Tooltip content={`העריכה נשלטת על ידי ההרשאה ${f.edit_permission_key}`}>
                        <span className="type-caption text-ink-tertiary">
                          <Pencil size={ICON.sm} strokeWidth={STROKE} className="me-1 inline" />
                          נקבע בהרשאות
                        </span>
                      </Tooltip>
                    ) : (
                      <Switch
                        checked={canEdit && canView}
                        disabled={!canView}
                        onChange={(v) => save.mutate({ field: f, canView, canEdit: v })}
                        label={
                          <span className="flex items-center gap-1">
                            <Pencil size={ICON.sm} strokeWidth={STROKE} />
                            עריכה
                          </span>
                        }
                      />
                    )}
                  </div>
                </li>
              )
            })}
          </ul>
        </CollapsibleCard>
      ))}
    </div>
  )
}
