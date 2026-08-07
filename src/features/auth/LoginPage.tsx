import { useState } from 'react'
import { Navigate } from 'react-router'
import { AlertCircle, ICON, STROKE } from '../../components/ui/icons'
import { Button, Field, Input } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'

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
    <div className="relative flex min-h-full items-center justify-center overflow-hidden bg-canvas p-4">
      {/* two soft brand washes give the page depth without a background image */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-40 start-1/4 size-[32rem] rounded-full opacity-[0.13] blur-3xl"
        style={{ background: 'radial-gradient(circle, var(--vl-primary), transparent 70%)' }}
      />
      <div
        aria-hidden
        className="pointer-events-none absolute -bottom-40 end-1/4 size-[28rem] rounded-full opacity-[0.1] blur-3xl"
        style={{ background: 'radial-gradient(circle, var(--color-accent-500), transparent 70%)' }}
      />

      <div className="relative w-full max-w-sm">
        <div className="mb-7 flex flex-col items-center gap-3 text-center">
          <img src="/icons/icon-192.png" className="size-14 shrink-0 rounded-2xl shadow-md" alt="ViperLogistics" />
          <div>
            <h1 className="type-heading">ViperLogistics</h1>
            <p className="mt-0.5 type-caption text-ink-tertiary">מערכת ניהול כוח אדם לאירועים</p>
          </div>
        </div>

        <div className="surface-raised p-6">
          <form onSubmit={submit} className="space-y-4" noValidate>
            <Field label="אימייל" required>
              <Input
                type="email"
                dir="ltr"
                inputSize="lg"
                autoComplete="username"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                invalid={!!error}
                autoFocus
                required
              />
            </Field>
            <Field label="סיסמה" required>
              <Input
                type="password"
                dir="ltr"
                inputSize="lg"
                autoComplete="current-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                invalid={!!error}
                required
              />
            </Field>

            {error && (
              <div
                role="alert"
                className="flex animate-slide-up items-center gap-2 rounded-lg border border-error-border bg-error-subtle px-3 py-2 type-body text-error-text"
              >
                <AlertCircle size={ICON.md} className="shrink-0" strokeWidth={STROKE} />
                {error}
              </div>
            )}

            <Button type="submit" variant="primary" size="lg" block loading={loading}>
              התחברות
            </Button>
          </form>
        </div>

        <p className="mt-6 text-center type-caption text-ink-tertiary">
          מערכת פנימית · הגישה מוגבלת למשתמשים מורשים
        </p>
      </div>
    </div>
  )
}
