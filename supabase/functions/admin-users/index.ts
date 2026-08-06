import { createClient } from 'npm:@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })
}

type Action = 'create_login' | 'set_password' | 'set_active' | 'delete_login'

/** Which registry key each action costs. */
const REQUIRED: Record<Action, string> = {
  create_login: 'users.create_login',
  set_password: 'users.reset_password',
  set_active: 'users.edit',
  delete_login: 'users.delete',
}

interface TargetProfile {
  id: string
  user_id: string | null
  is_admin: boolean
  full_name: string
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405)

  try {
    const url = Deno.env.get('SUPABASE_URL')!
    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)

    const authHeader = req.headers.get('Authorization') ?? ''
    if (!authHeader) return json({ error: 'לא מחובר' }, 401)

    // A second client bound to the caller's JWT, so authorization is decided by
    // asking the database the same questions RLS asks. The previous version
    // re-derived the permission chain here against user_permissions and
    // permission_defaults — tables the 0010 rewrite dropped — which is exactly
    // how a hand-rolled copy drifts from the thing it copies.
    const asUser = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: authHeader } },
    })

    const { data: me, error: meErr } = await asUser.rpc('get_my_permissions')
    if (meErr || !me) return json({ error: 'לא מחובר' }, 401)

    const caller = me.profile as { id: string; is_admin: boolean }
    const caps = (me.capabilities ?? {}) as Record<string, boolean>
    const has = (key: string) => caller.is_admin || caps[key] === true

    const body = await req.json()
    const action = body.action as Action
    if (!REQUIRED[action]) return json({ error: 'פעולה לא מוכרת' }, 400)
    if (!has(REQUIRED[action])) return json({ error: 'אין לך הרשאה לבצע פעולה זו' }, 403)

    // Never trust a raw user_id from the body: the old code linked a fresh auth
    // user to whatever profile_id it was handed, so anyone who could create a
    // login could attach one to an admin's profile. Resolve a profile row
    // first, then authorize against that row.
    const { profile_id, user_id } = body as { profile_id?: string; user_id?: string }
    if (!profile_id && !user_id) return json({ error: 'חסר מזהה משתמש' }, 400)

    const lookup = admin.from('profiles').select('id, user_id, is_admin, full_name')
    const { data: target } = profile_id
      ? await lookup.eq('id', profile_id).maybeSingle()
      : await lookup.eq('user_id', user_id!).maybeSingle()
    if (!target) return json({ error: 'המשתמש לא נמצא' }, 404)
    const t = target as TargetProfile

    // app.can_manage_profile is the predicate the RLS policies use. It excludes
    // self on purpose — every escalation path starts with editing yourself —
    // but changing your own password is not escalation.
    const isSelf = t.id === caller.id
    if (!(isSelf && action === 'set_password')) {
      const { data: allowed } = await asUser.rpc('can_manage_profile', { p_target: t.id })
      if (allowed !== true) return json({ error: 'אין לך הרשאה לנהל משתמש זה' }, 403)
    }
    if (t.is_admin && !caller.is_admin) {
      return json({ error: 'אין לך הרשאה לנהל מנהל מערכת' }, 403)
    }
    if (isSelf && (action === 'set_active' || action === 'delete_login')) {
      return json({ error: 'לא ניתן לבצע פעולה זו על עצמך' }, 403)
    }

    if (action === 'create_login') {
      const { email, password } = body
      if (!email || !password) return json({ error: 'חסר אימייל או סיסמה' }, 400)
      if (t.user_id) return json({ error: 'למשתמש כבר קיים חשבון התחברות' }, 400)

      const { data: created, error: createErr } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      })
      if (createErr) return json({ error: createErr.message }, 400)

      const { error: linkErr } = await admin
        .from('profiles')
        .update({ user_id: created.user.id, email })
        .eq('id', t.id)
        .is('user_id', null) // lost race → link nothing rather than overwrite
      if (linkErr) {
        await admin.auth.admin.deleteUser(created.user.id)
        return json({ error: linkErr.message }, 400)
      }
      return json({ user_id: created.user.id })
    }

    // the remaining actions all operate on an existing login
    if (!t.user_id) return json({ error: 'למשתמש אין חשבון התחברות' }, 400)

    if (action === 'set_password') {
      const { password } = body
      if (!password) return json({ error: 'חסרים פרטים' }, 400)
      const { error } = await admin.auth.admin.updateUserById(t.user_id, { password })
      if (error) return json({ error: error.message }, 400)
      return json({ ok: true })
    }

    if (action === 'set_active') {
      const { error } = await admin.auth.admin.updateUserById(t.user_id, {
        ban_duration: body.is_active ? 'none' : '876000h',
      })
      if (error) return json({ error: error.message }, 400)
      return json({ ok: true })
    }

    // delete_login
    const { error } = await admin.auth.admin.deleteUser(t.user_id)
    if (error) return json({ error: error.message }, 400)
    return json({ ok: true })
  } catch (e) {
    return json({ error: (e as Error).message }, 500)
  }
})
