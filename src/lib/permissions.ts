/**
 * Queries over the permission catalog.
 *
 * The admin screens are built from these tables rather than from a hard-coded
 * list, which is the whole point of the registry: a module added later shows up
 * in the permission editor because it registered itself, not because someone
 * remembered to update a constant in the client.
 */
import { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { supabase } from './supabase'
import { useAuth } from '../state/auth'
import type {
  FieldDef,
  PermissionDef,
  PermissionModule,
  PermissionRole,
  PermissionScope,
  UserKind,
} from '../types/domain'

export { PERM } from './permissionKeys'
export type { PermissionKey } from './permissionKeys'

/**
 * נקרא אחרי כל שינוי במרשם ההרשאות.
 *
 * `me.capabilities` נפתר פעם אחת בשרת בעליית האפליקציה ולא נגע בו איש
 * אחרי כן, ולכן אדמין שערך הרשאות המשיך לראות את התשובה הישנה עד להתנתקות
 * — כפתורים שנעלמו ולא הופיעו, ומסכים שנפתחו ואמורים היו להיחסם.
 *
 * הרענון אינו מותנה בשאלה "האם ערכתי את עצמי": עריכה של *תפקיד* משנה את מי
 * שמחזיק בו, והעורך עשוי להיות אחד מהם. הקריאה זולה ונדירה, ולכן עדיף
 * לרענן תמיד מלנסות לנחש מתי זה נחוץ.
 */
export function refreshOwnCapabilities() {
  void useAuth.getState().refreshMe()
}

/** How a single permission is set for one subject. */
export type GrantState = 'inherit' | 'allow' | 'deny'

export function usePermissionModules() {
  return useQuery({
    queryKey: ['permission_modules'],
    staleTime: 5 * 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.from('permission_modules').select('*').order('sort_order')
      if (error) throw error
      return data as PermissionModule[]
    },
  })
}

export function usePermissionRegistry() {
  return useQuery({
    queryKey: ['permission_registry'],
    staleTime: 5 * 60_000,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('permission_registry')
        .select('*')
        .eq('is_active', true)
        .order('sort_order')
      if (error) throw error
      return data as PermissionDef[]
    },
  })
}

export function useFieldRegistry() {
  return useQuery({
    queryKey: ['field_registry'],
    staleTime: 5 * 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.from('field_registry').select('*').order('sort_order')
      if (error) throw error
      return data as FieldDef[]
    },
  })
}

export function usePermissionRoles() {
  return useQuery({
    queryKey: ['permission_roles'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('permission_roles')
        .select('*')
        .is('deleted_at', null)
        .order('sort_order')
      if (error) throw error
      return data as PermissionRole[]
    },
  })
}

export function useRolePermissions(roleId?: string | null) {
  return useQuery({
    queryKey: ['role_permissions', roleId],
    enabled: !!roleId,
    queryFn: async () => {
      const { data, error } = await supabase.from('role_permissions').select('*').eq('role_id', roleId)
      if (error) throw error
      return data as { role_id: string; permission_key: string; allowed: boolean }[]
    },
  })
}

/**
 * Grants across several roles at once — the "role layer" for a person who holds
 * more than one. Matches app.has(): any role allowing a key wins over one
 * denying it.
 */
export function useRolesPermissions(roleIds: string[]) {
  const key = [...roleIds].sort().join(',')
  return useQuery({
    queryKey: ['role_permissions', 'multi', key],
    enabled: roleIds.length > 0,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('role_permissions')
        .select('permission_key, allowed')
        .in('role_id', roleIds)
      if (error) throw error
      const merged = new Map<string, boolean>()
      for (const row of data as { permission_key: string; allowed: boolean }[]) {
        merged.set(row.permission_key, merged.get(row.permission_key) === true ? true : row.allowed)
      }
      return merged
    },
  })
}

export function useProfileRoles(profileId?: string | null) {
  return useQuery({
    queryKey: ['profile_roles', profileId],
    enabled: !!profileId,
    queryFn: async () => {
      const { data, error } = await supabase.from('profile_roles').select('role_id').eq('profile_id', profileId)
      if (error) throw error
      return (data as { role_id: string }[]).map((r) => r.role_id)
    },
  })
}

export function useUserGrants(profileId?: string | null) {
  return useQuery({
    queryKey: ['user_permission_grants', profileId],
    enabled: !!profileId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('user_permission_grants')
        .select('permission_key, allowed')
        .eq('profile_id', profileId)
      if (error) throw error
      return data as { permission_key: string; allowed: boolean }[]
    },
  })
}

export function useKindDefaults() {
  return useQuery({
    queryKey: ['kind_permission_defaults'],
    staleTime: 5 * 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.from('kind_permission_defaults').select('*')
      if (error) throw error
      return data as { user_kind: UserKind; permission_key: string; allowed: boolean }[]
    },
  })
}

export function usePermissionScopes(profileId?: string | null, roleId?: string | null) {
  return useQuery({
    queryKey: ['permission_scopes', profileId ?? null, roleId ?? null],
    enabled: !!profileId || !!roleId,
    queryFn: async () => {
      let q = supabase.from('permission_scopes').select('*')
      q = profileId ? q.eq('profile_id', profileId) : q.eq('role_id', roleId)
      const { data, error } = await q
      if (error) throw error
      return data as PermissionScope[]
    },
  })
}

export function useFieldPermissionRows(profileId?: string | null, roleId?: string | null) {
  return useQuery({
    queryKey: ['field_permissions', profileId ?? null, roleId ?? null],
    enabled: !!profileId || !!roleId,
    queryFn: async () => {
      let q = supabase.from('field_permissions').select('*')
      q = profileId ? q.eq('profile_id', profileId) : q.eq('role_id', roleId)
      const { data, error } = await q
      if (error) throw error
      return data as {
        id: string
        entity: string
        field_key: string
        can_view: boolean
        can_edit: boolean
      }[]
    },
  })
}

/**
 * Resolves what a subject *effectively* gets, mirroring app.has() including the
 * implied_by walk. The editor shows this next to each control so an admin can
 * see that denying a key had no visible effect because a role still grants it —
 * the single most confusing thing about layered permissions.
 */
export function resolveEffective(
  key: string,
  registry: PermissionDef[],
  layers: {
    userGrants: Map<string, boolean>
    roleGrants: Map<string, boolean>
    kindDefaults: Map<string, boolean>
  },
): { allowed: boolean; source: 'user' | 'role' | 'kind' | 'default' | 'inherited' | 'none' } {
  const byKey = new Map(registry.map((r) => [r.key, r]))
  let current: string | null = key
  let depth = 0
  while (current && depth < 8) {
    const u = layers.userGrants.get(current)
    if (u !== undefined) return { allowed: u, source: depth === 0 ? 'user' : 'inherited' }
    const r = layers.roleGrants.get(current)
    if (r !== undefined) return { allowed: r, source: depth === 0 ? 'role' : 'inherited' }
    const k = layers.kindDefaults.get(current)
    if (k !== undefined) return { allowed: k, source: depth === 0 ? 'kind' : 'inherited' }
    if (byKey.get(current)?.default_allowed) {
      return { allowed: true, source: depth === 0 ? 'default' : 'inherited' }
    }
    current = byKey.get(current)?.implied_by ?? null
    depth += 1
  }
  return { allowed: false, source: 'none' }
}

/** Groups the flat registry by module, in catalog order, for the matrix UI. */
export function useGroupedRegistry(kind?: UserKind) {
  const { data: modules = [], isLoading: lm } = usePermissionModules()
  const { data: registry = [], isLoading: lr } = usePermissionRegistry()
  const grouped = useMemo(() => {
    const relevant = kind ? registry.filter((r) => r.applies_to.includes(kind)) : registry
    return modules
      .map((m) => ({ module: m, items: relevant.filter((r) => r.module === m.key) }))
      .filter((g) => g.items.length > 0)
  }, [modules, registry, kind])
  return { grouped, registry, isLoading: lm || lr }
}

export const SCOPE_LABELS: Record<string, string> = {
  all: 'ללא הגבלה',
  own: 'רק מה שמשויך אליי',
  customers: 'לקוחות מסוימים',
  contractors: 'קבלנים מסוימים',
  task_types: 'סוגי משימות מסוימים',
  statuses: 'סטטוסים מסוימים',
  execution_methods: 'אופני ביצוע מסוימים',
  trucks: 'משאיות מסוימות',
  date_window: 'חלון תאריכים',
}

export const SCOPE_RESOURCES: { key: string; label: string; types: string[] }[] = [
  {
    key: 'tasks',
    label: 'משימות',
    types: ['own', 'customers', 'contractors', 'task_types', 'statuses', 'execution_methods', 'trucks', 'date_window'],
  },
  { key: 'events', label: 'אירועים', types: ['own', 'customers', 'statuses', 'date_window'] },
  { key: 'customers', label: 'לקוחות', types: ['customers'] },
  { key: 'contractors', label: 'קבלנים', types: ['contractors'] },
]

export const CATEGORY_LABELS: Record<string, string> = {
  access: 'גישה',
  crud: 'בסיסי',
  field: 'שדות',
  action: 'פעולות',
  admin: 'ניהול הרשאות',
}
