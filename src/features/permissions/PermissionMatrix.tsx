/**
 * The permission editor.
 *
 * Every control on this screen comes from `permission_registry`, so a module
 * that registers permissions in a later migration appears here on its own — no
 * change to this file. That is the difference between this and the hard-coded
 * 7×4 grid it replaces.
 *
 * The same component edits a person and a role; only the table the writes land
 * in differs. Each key is three-state — ירושה / מותר / חסום — and the resolved
 * answer is spelled out next to it, because with roles, kind defaults and
 * implied_by all in play, "I set it to חסום and nothing happened" is otherwise
 * impossible to debug from the UI.
 */
import { useMemo, useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, ICON, STROKE, Search, Shield } from '../../components/ui/icons'
import {
  Badge,
  Button,
  CollapsibleCard,
  SearchInput,
  SegmentedControl,
  Skeleton,
  Tooltip,
  cx,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import {
  CATEGORY_LABELS,
  resolveEffective,
  useGroupedRegistry,
  useKindDefaults,
  useProfileRoles,
  useRolePermissions,
  useRolesPermissions,
  useUserGrants,
} from '../../lib/permissions'
import type { GrantState } from '../../lib/permissions'
import type { UserKind } from '../../types/domain'

export type MatrixSubject =
  | { kind: 'user'; profileId: string; userKind: UserKind }
  | { kind: 'role'; roleId: string; userKind: UserKind | null }

const STATES: { key: GrantState; label: string }[] = [
  { key: 'inherit', label: 'ירושה' },
  { key: 'allow', label: 'מותר' },
  { key: 'deny', label: 'חסום' },
]

const SOURCE_LABELS: Record<string, string> = {
  user: 'הרשאה אישית',
  role: 'תפקיד',
  kind: 'ברירת מחדל לסוג המשתמש',
  default: 'ברירת מחדל של המערכת',
  inherited: 'נגזר מהרשאה רחבה יותר',
  none: 'ברירת מחדל — חסום',
}

export function PermissionMatrix({ subject }: { subject: MatrixSubject }) {
  const toast = useToast()
  const qc = useQueryClient()
  const [q, setQ] = useState('')
  const [onlySet, setOnlySet] = useState(false)

  const kindFilter = subject.kind === 'user' ? subject.userKind : (subject.userKind ?? undefined)
  const { grouped, registry, isLoading } = useGroupedRegistry(kindFilter)

  const profileId = subject.kind === 'user' ? subject.profileId : null
  const roleId = subject.kind === 'role' ? subject.roleId : null

  const { data: userGrants = [] } = useUserGrants(profileId)
  const { data: ownRoleGrants = [] } = useRolePermissions(roleId)
  const { data: myRoleIds = [] } = useProfileRoles(profileId)
  const { data: kindDefaults = [] } = useKindDefaults()

  // For a person, the "role" layer is the union of every role they hold; for a
  // role being edited, its own grants are the thing under the cursor and the
  // role layer beneath is empty.
  const { data: inheritedRoleGrants } = useRolesPermissions(subject.kind === 'user' ? myRoleIds : [])

  const layers = useMemo(() => {
    const own = new Map<string, boolean>()
    const kinds = new Map<string, boolean>()
    const rolesMap = subject.kind === 'user' ? (inheritedRoleGrants ?? new Map()) : new Map()

    if (subject.kind === 'user') {
      for (const g of userGrants) own.set(g.permission_key, g.allowed)
    } else {
      for (const g of ownRoleGrants) own.set(g.permission_key, g.allowed)
    }
    const kind = subject.userKind
    if (kind) {
      for (const d of kindDefaults) {
        if (d.user_kind === kind) kinds.set(d.permission_key, d.allowed)
      }
    }
    return { own, rolesMap, kinds }
  }, [subject, userGrants, ownRoleGrants, inheritedRoleGrants, kindDefaults])

  const stateOf = (key: string): GrantState => {
    const v = layers.own.get(key)
    return v === undefined ? 'inherit' : v ? 'allow' : 'deny'
  }

  const effectiveOf = (key: string) =>
    resolveEffective(key, registry, {
      userGrants: subject.kind === 'user' ? layers.own : new Map(),
      roleGrants: subject.kind === 'user' ? layers.rolesMap : layers.own,
      kindDefaults: layers.kinds,
    })

  const invalidate = () => {
    void qc.invalidateQueries({
      queryKey: subject.kind === 'user' ? ['user_permission_grants', profileId] : ['role_permissions', roleId],
    })
  }

  const update = useMutation({
    mutationFn: async ({ key, state }: { key: string; state: GrantState }) => {
      const table = subject.kind === 'user' ? 'user_permission_grants' : 'role_permissions'
      const match =
        subject.kind === 'user'
          ? { profile_id: profileId!, permission_key: key }
          : { role_id: roleId!, permission_key: key }
      if (state === 'inherit') {
        const { error } = await supabase.from(table).delete().match(match)
        if (error) throw error
      } else {
        const { error } = await supabase.from(table).upsert({ ...match, allowed: state === 'allow' })
        if (error) throw error
      }
    },
    onSuccess: invalidate,
    onError: (e) => toast.error((e as Error).message),
  })

  /**
   * Closing a module writes an explicit חסום on every key in it the subject
   * doesn't already have set to מותר. Without it, granting a broad key like
   * "עריכת משימות" quietly carries all the narrow keys derived from it.
   */
  const closeModule = useMutation({
    mutationFn: async (moduleKey: string) => {
      const keys = grouped.find((g) => g.module.key === moduleKey)?.items ?? []
      const rows = keys
        .filter((k) => layers.own.get(k.key) !== true)
        .map((k) =>
          subject.kind === 'user'
            ? { profile_id: profileId!, permission_key: k.key, allowed: false }
            : { role_id: roleId!, permission_key: k.key, allowed: false },
        )
      if (!rows.length) return
      const table = subject.kind === 'user' ? 'user_permission_grants' : 'role_permissions'
      const { error } = await supabase.from(table).upsert(rows)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('כל ההרשאות שלא אושרו במודול נחסמו')
      invalidate()
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const resetModule = useMutation({
    mutationFn: async (moduleKey: string) => {
      const keys = (grouped.find((g) => g.module.key === moduleKey)?.items ?? []).map((k) => k.key)
      const table = subject.kind === 'user' ? 'user_permission_grants' : 'role_permissions'
      const col = subject.kind === 'user' ? 'profile_id' : 'role_id'
      const id = subject.kind === 'user' ? profileId! : roleId!
      const { error } = await supabase.from(table).delete().eq(col, id).in('permission_key', keys)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('המודול הוחזר לירושה')
      invalidate()
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const term = q.trim().toLowerCase()
  const visible = useMemo(
    () =>
      grouped
        .map((g) => ({
          ...g,
          items: g.items.filter((i) => {
            if (onlySet && layers.own.get(i.key) === undefined) return false
            if (!term) return true
            return (
              i.label_he.toLowerCase().includes(term) ||
              i.key.toLowerCase().includes(term) ||
              (i.description_he ?? '').toLowerCase().includes(term) ||
              g.module.label_he.toLowerCase().includes(term)
            )
          }),
        }))
        .filter((g) => g.items.length > 0),
    [grouped, term, onlySet, layers.own],
  )

  if (isLoading) return <Skeleton className="h-96 w-full" />

  const overrides = layers.own.size

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <SearchInput
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="חיפוש הרשאה..."
          className="min-w-56 flex-1"
        />
        <SegmentedControl
          items={[
            { key: 'all', label: 'הכול' },
            { key: 'set', label: `הוגדרו (${overrides})` },
          ]}
          value={onlySet ? 'set' : 'all'}
          onChange={(k) => setOnlySet(k === 'set')}
        />
      </div>

      {visible.length === 0 && (
        <p className="rounded-lg border border-line-subtle bg-subtle/40 px-4 py-6 text-center type-body text-ink-tertiary">
          לא נמצאו הרשאות תואמות
        </p>
      )}

      {visible.map(({ module, items }) => {
        const setCount = items.filter((i) => layers.own.get(i.key) !== undefined).length
        return (
          <CollapsibleCard
            key={module.key}
            title={module.label_he}
            subtitle={
              setCount > 0 ? `${setCount} מתוך ${items.length} הוגדרו במפורש` : `${items.length} הרשאות — הכול בירושה`
            }
            icon={<Shield size={ICON.md} strokeWidth={STROKE} />}
            defaultOpen={!!term || setCount > 0}
            actions={
              <>
                <Button size="sm" onClick={() => resetModule.mutate(module.key)}>
                  ירושה
                </Button>
                <Tooltip content="חוסם במפורש כל הרשאה שלא אושרה — כך שהרשאה רחבה לא תגרור אותן">
                  <Button size="sm" onClick={() => closeModule.mutate(module.key)}>
                    סגירת המודול
                  </Button>
                </Tooltip>
              </>
            }
          >
            <ul className="space-y-1">
              {items.map((item) => {
                const state = stateOf(item.key)
                const eff = effectiveOf(item.key)
                return (
                  <li
                    key={item.key}
                    className="flex flex-wrap items-center gap-x-3 gap-y-2 rounded-lg px-2 py-2 hover:bg-subtle/50"
                  >
                    <div className="min-w-48 flex-1">
                      <p className="flex items-center gap-1.5 type-body font-medium">
                        {item.label_he}
                        {item.is_dangerous && (
                          <Tooltip content="הרשאה רגישה — כסף, פרטי קשר או ניהול הרשאות">
                            <span className="text-warning-text">
                              <AlertTriangle size={ICON.sm} strokeWidth={STROKE} />
                            </span>
                          </Tooltip>
                        )}
                        <Badge tone="neutral">{CATEGORY_LABELS[item.category] ?? item.category}</Badge>
                      </p>
                      {item.description_he && (
                        <p className="type-caption text-ink-tertiary">{item.description_he}</p>
                      )}
                      <p className="type-caption text-ink-tertiary" dir="ltr">
                        {item.key}
                      </p>
                    </div>

                    <div className="flex items-center gap-2">
                      <Badge tone={eff.allowed ? 'success' : 'neutral'}>
                        {eff.allowed ? 'בפועל: מותר' : 'בפועל: חסום'}
                      </Badge>
                      <span className="hidden type-caption text-ink-tertiary sm:inline">
                        {SOURCE_LABELS[eff.source]}
                      </span>
                      <SegmentedControl
                        items={STATES}
                        value={state}
                        onChange={(next) => update.mutate({ key: item.key, state: next })}
                      />
                    </div>
                  </li>
                )
              })}
            </ul>
          </CollapsibleCard>
        )
      })}
    </div>
  )
}

/** Small helper reused by the role and user editors for their header line. */
export function GrantSummary({ count, total }: { count: number; total: number }) {
  return (
    <span className={cx('type-caption', count > 0 ? 'text-ink-secondary' : 'text-ink-tertiary')}>
      <Search size={ICON.xs} strokeWidth={STROKE} className="me-1 inline" />
      {count} מתוך {total} הרשאות הוגדרו במפורש
    </span>
  )
}
