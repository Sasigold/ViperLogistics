import { create } from 'zustand'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import type { MyPermissions, PermissionAction } from '../types/domain'

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
}

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
}))
