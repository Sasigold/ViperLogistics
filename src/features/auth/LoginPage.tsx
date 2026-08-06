import { useState } from 'react'
import { Navigate } from 'react-router'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { Button, Field, Input } from '../../components/ui'
import { Truck } from 'lucide-react'

export default function LoginPage() {
  const { session, booted } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  if (booted && session) return <Navigate to="/" replace />

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError('')
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    setLoading(false)
    if (error) setError('פרטי התחברות שגויים')
  }

  return (
    <div className="flex min-h-full items-center justify-center p-4">
      <div className="surface w-full max-w-sm p-6 shadow-lg">
        <div className="mb-6 flex flex-col items-center gap-2">
          <div className="flex size-12 items-center justify-center rounded-xl bg-brand-600 text-white">
            <Truck size={24} />
          </div>
          <h1 className="text-lg font-bold">ViperLogistics</h1>
          <p className="text-sm text-[var(--muted)]">מערכת ניהול כוח אדם לאירועים</p>
        </div>
        <form onSubmit={submit} className="space-y-4">
          <Field label="אימייל" required>
            <Input type="email" dir="ltr" value={email} onChange={(e) => setEmail(e.target.value)} autoFocus required />
          </Field>
          <Field label="סיסמה" required>
            <Input type="password" dir="ltr" value={password} onChange={(e) => setPassword(e.target.value)} required />
          </Field>
          {error && <p className="text-sm text-red-500">{error}</p>}
          <Button type="submit" variant="primary" className="w-full" loading={loading}>
            התחברות
          </Button>
        </form>
      </div>
    </div>
  )
}
