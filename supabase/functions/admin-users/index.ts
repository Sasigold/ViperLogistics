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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405)

  try {
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const jwt = (req.headers.get('Authorization') ?? '').replace('Bearer ', '')
    const { data: userData, error: userErr } = await admin.auth.getUser(jwt)
    if (userErr || !userData.user) return json({ error: 'לא מחובר' }, 401)

    const { data: caller } = await admin
      .from('profiles')
      .select('id, is_admin, user_kind, is_active')
      .eq('user_id', userData.user.id)
      .is('deleted_at', null)
      .maybeSingle()
    if (!caller || !caller.is_active) return json({ error: 'לא מחובר' }, 401)

    let allowed = caller.is_admin
    if (!allowed) {
      const { data: perm } = await admin
        .from('user_permissions')
        .select('allowed')
        .eq('profile_id', caller.id)
        .eq('resource', 'users')
        .eq('action', 'create')
        .maybeSingle()
      if (perm) {
        allowed = perm.allowed
      } else {
        const { data: def } = await admin
          .from('permission_defaults')
          .select('allowed')
          .eq('user_kind', caller.user_kind)
          .eq('resource', 'users')
          .eq('action', 'create')
          .maybeSingle()
        allowed = def?.allowed ?? false
      }
    }
    if (!allowed) return json({ error: 'אין לך הרשאה לנהל משתמשים' }, 403)

    const body = await req.json()
    const action = body.action as string

    if (action === 'create_login') {
      // create an auth user and link it to a (new or existing) profile
      const { email, password, profile_id } = body
      if (!email || !password) return json({ error: 'חסר אימייל או סיסמה' }, 400)
      const { data: created, error: createErr } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      })
      if (createErr) return json({ error: createErr.message }, 400)
      if (profile_id) {
        const { error: linkErr } = await admin
          .from('profiles')
          .update({ user_id: created.user.id, email })
          .eq('id', profile_id)
        if (linkErr) {
          await admin.auth.admin.deleteUser(created.user.id)
          return json({ error: linkErr.message }, 400)
        }
      }
      return json({ user_id: created.user.id })
    }

    if (action === 'set_password') {
      const { user_id, password } = body
      if (!user_id || !password) return json({ error: 'חסרים פרטים' }, 400)
      const { error } = await admin.auth.admin.updateUserById(user_id, { password })
      if (error) return json({ error: error.message }, 400)
      return json({ ok: true })
    }

    if (action === 'set_active') {
      const { user_id, is_active } = body
      if (!user_id) return json({ error: 'חסרים פרטים' }, 400)
      const { error } = await admin.auth.admin.updateUserById(user_id, {
        ban_duration: is_active ? 'none' : '876000h',
      })
      if (error) return json({ error: error.message }, 400)
      return json({ ok: true })
    }

    if (action === 'delete_login') {
      const { user_id } = body
      if (!user_id) return json({ error: 'חסרים פרטים' }, 400)
      const { error } = await admin.auth.admin.deleteUser(user_id)
      if (error) return json({ error: error.message }, 400)
      return json({ ok: true })
    }

    return json({ error: 'פעולה לא מוכרת' }, 400)
  } catch (e) {
    return json({ error: (e as Error).message }, 500)
  }
})
