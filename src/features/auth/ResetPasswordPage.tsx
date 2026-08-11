import { useState } from 'react'
import { Link, useNavigate } from 'react-router'
import { AlertCircle, ICON, STROKE } from '../../components/ui/icons'
import { Button, Field, Input, useToast } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { errorMessage } from '../../lib/errors'
import { useAuth } from '../../state/auth'

/**
 * היעד של קישור האיפוס מהמייל. הקישור פותח את הדף עם סשן recovery —
 * supabase-js קולט אותו מה-URL (detectSessionInUrl, ברירת המחדל) —
 * ולכן משתמש "מחובר" הוא בדיוק המצב שהדף משרת, ואין להפנות ממנו החוצה.
 *
 * דרישות תפעול (פעם אחת, בדשבורד של Supabase): SMTP מוגדר ב-Auth,
 * ו-<origin>/reset-password ברשימת ה-Redirect URLs.
 */
export default function ResetPasswordPage() {
  const { session, booted } = useAuth()
  const toast = useToast()
  const navigate = useNavigate()
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [error, setError] = useState('')
  const [saving, setSaving] = useState(false)

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')
    if (password.length < 6) {
      setError('הסיסמה צריכה להיות באורך 6 תווים לפחות')
      return
    }
    if (password !== confirm) {
      setError('הסיסמאות אינן זהות')
      return
    }
    setSaving(true)
    const { error } = await supabase.auth.updateUser({ password })
    setSaving(false)
    if (error) {
      setError(errorMessage(error))
      return
    }
    toast.success('הסיסמה עודכנה')
    navigate('/', { replace: true })
  }

  return (
    <div className="relative flex min-h-full items-center justify-center overflow-hidden bg-canvas p-4">
      {/* אותם שני משטחי צבע רכים של מסך ההתחברות */}
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
            <h1 className="type-heading">בחירת סיסמה חדשה</h1>
            <p className="mt-0.5 type-caption text-ink-tertiary">ViperLogistics</p>
          </div>
        </div>

        <div className="surface-raised p-6">
          {booted && !session ? (
            <div className="space-y-4 text-center">
              <p className="type-body text-ink-secondary">הקישור אינו תקף או שפג תוקפו.</p>
              <Link to="/login" className="type-caption text-primary-text hover:underline">
                חזרה למסך ההתחברות לבקשת קישור חדש
              </Link>
            </div>
          ) : (
            <form onSubmit={submit} className="space-y-4" noValidate>
              <Field label="סיסמה חדשה" required>
                <Input
                  type="password"
                  dir="ltr"
                  inputSize="lg"
                  autoComplete="new-password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  invalid={!!error}
                  autoFocus
                  required
                />
              </Field>
              <Field label="אימות סיסמה" required>
                <Input
                  type="password"
                  dir="ltr"
                  inputSize="lg"
                  autoComplete="new-password"
                  value={confirm}
                  onChange={(e) => setConfirm(e.target.value)}
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

              <Button type="submit" variant="primary" size="lg" block loading={saving}>
                עדכון סיסמה
              </Button>
            </form>
          )}
        </div>
      </div>
    </div>
  )
}
