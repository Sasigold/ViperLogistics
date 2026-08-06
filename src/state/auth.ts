import { create } from 'zustand'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import type { FieldState, MyPermissions, PermissionAction } from '../types/domain'

interface AuthState {
  session: Session | null
  me: MyPermissions | null
  booted: boolean
  theme: 'light' | 'dark'
  boot: () => Promise<void>
  refreshMe: () => Promise<void>
  signOut: () => Promise<void>
  toggleTheme: () => void
  /** the granular check — one registry key, resolved server-side at login */
  has: (key: string) => boolean
  hasAny: (...keys: string[]) => boolean
  /** legacy shape, equivalent to has(`${resource}.${action}`) */
  can: (resource: string, action: PermissionAction) => boolean
  canViewField: (entity: string, field: string) => boolean
  canEditField: (entity: string, field: string) => boolean
  /** merged company + per-user event-form config; 'visible' when unconfigured */
  formFieldState: (key: string) => FieldState
  /** form composition AND data access — what a client actually gets to see */
  showsEventField: (key: string) => boolean
}

/**
 * One form field can sit on several columns, and the two registries name them
 * differently: `form_fields` is form-shaped ('location', 'addons'), while
 * `field_registry` is column-shaped. Only the columns listed here carry a data
 * rule; the setup/teardown keys have no registry entry and so are governed by
 * the form config alone.
 */
const FIELD_COLUMNS: Record<string, string[]> = {
  location: ['location_text'],
  addons: ['no_parking', 'porterage', 'supplier_pickup'],
}
const columnsOf = (key: string) => FIELD_COLUMNS[key] ?? [key]

function applyTheme(theme: 'light' | 'dark') {
  document.documentElement.dataset.theme = theme
  localStorage.setItem('vl-theme', theme)
}

export const useAuth = create<AuthState>((set, get) => ({
  session: null,
  me: null,
  booted: false,
  theme: (localStorage.getItem('vl-theme') as 'light' | 'dark') ?? 'light',

  boot: async () => {
    applyTheme(get().theme)
    const { data } = await supabase.auth.getSession()
    set({ session: data.session })
    if (data.session) await get().refreshMe()
    set({ booted: true })
    supabase.auth.onAuthStateChange((_evt, session) => {
      set({ session })
      if (session) void get().refreshMe()
      else set({ me: null })
    })
  },

  refreshMe: async () => {
    const { data, error } = await supabase.rpc('get_my_permissions')
    if (!error) set({ me: (data as MyPermissions | null) ?? null })
  },

  signOut: async () => {
    await supabase.auth.signOut()
    set({ session: null, me: null })
  },

  toggleTheme: () => {
    const next = get().theme === 'light' ? 'dark' : 'light'
    applyTheme(next)
    set({ theme: next })
  },

  /**
   * `capabilities` was resolved by the server through the same functions RLS
   * uses, so this can only ever agree with what a request would be allowed to
   * do. It hides controls; it does not protect anything — the write would be
   * refused by the column trigger or a policy regardless.
   */
  has: (key) => {
    const me = get().me
    if (!me) return false
    if (me.profile.is_admin) return true
    return me.capabilities?.[key] ?? false
  },

  hasAny: (...keys) => {
    const has = get().has
    return keys.some((k) => has(k))
  },

  can: (resource, action) => {
    const me = get().me
    if (!me) return false
    if (me.profile.is_admin) return true
    return me.permissions[resource]?.[action] ?? false
  },

  canViewField: (entity, field) => {
    const me = get().me
    if (!me) return false
    if (me.profile.is_admin) return true
    const fp = me.field_permissions.find((f) => f.entity === entity && f.field_key === field)
    return fp ? fp.can_view : true
  },

  canEditField: (entity, field) => {
    const me = get().me
    if (!me) return false
    if (me.profile.is_admin) return true
    const fp = me.field_permissions.find((f) => f.entity === entity && f.field_key === field)
    return fp ? fp.can_edit : true
  },

  formFieldState: (key) => get().me?.form_config?.find((f) => f.field_key === key)?.state ?? 'visible',

  // A field disappears for two unrelated reasons: it was configured off the
  // form, or the data behind it is out of reach. Lists and detail screens have
  // to honour both, or a column reappears for a field the form never offered.
  showsEventField: (key) => {
    if (get().formFieldState(key) === 'hidden') return false
    const canViewField = get().canViewField
    return columnsOf(key).every((c) => canViewField('event', c))
  },
}))
