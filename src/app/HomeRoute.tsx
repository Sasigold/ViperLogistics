import { Suspense, useEffect } from 'react'
import { Navigate } from 'react-router'
import { Card, EmptyState, Skeleton } from '../components/ui'
import { useAuth } from '../state/auth'
import { PERM } from '../lib/permissions'
import { lazyPage } from '../lib/lazyPage'
import { FIELD_HOME, isFieldUser, navAudience, visibleNavSections } from './nav'
import { START_PATH, landingPending, markLanded, resolveLanding } from './homePref'
import { useHomePref } from './useHomePref'

const DashboardPage = lazyPage(() => import('../features/dashboard/DashboardPage'))
/* ‏הלקוח מקבל מסך ייעודי ומצומצם, לא את הרשת המשותפת — ראו CustomerDashboard. */
const CustomerDashboard = lazyPage(() => import('../features/dashboard/CustomerDashboard'))

/**
 * What `/` means depends on what you can open.
 *
 * Landing everyone on the dashboard shows a permission-denied card to anyone
 * without `dashboard.view` — which is the normal case, not the edge case: the
 * driver and worker roles do not have it, and neither does a client who was
 * given events only. So the route sends you to the first destination in the
 * sidebar you can actually reach, and only says "no access" when there is
 * genuinely nowhere to go.
 *
 * This is the client portal's index redirect, generalised. It was right there
 * and wrong everywhere else.
 */
export default function HomeRoute() {
  const has = useAuth((s) => s.has)
  const me = useAuth((s) => s.me)
  const pref = useHomePref()
  // הנחיתה האישית חלה רק בכניסה לאפליקציה; אחרי זה `/` הוא שוב הדשבורד
  const pending = landingPending()
  useEffect(() => {
    if (me) markLanded()
  }, [me])

  if (!me) return <Skeleton className="h-32 w-full" />
  const audience = navAudience(me)
  if (pending) {
    // לפני הדשבורד: מי שבחר דף נחיתה אחר לא מעמיס את הדשבורד בכלל
    const landing = resolveLanding(pref, visibleNavSections(has, audience))
    if (landing) return <Navigate to={landing} replace />
  }
  // ‏0215: דשבורד שהבעלים הסתיר הוא כמו דשבורד שאין עליו הרשאה — הבית שולח
  // ליעד הראשון בתפריט שנשאר גלוי.
  if (has(PERM.DASHBOARD_VIEW) && !audience.hiddenPages?.has('dashboard')) {
    // הבדיקה מקוננת בתוך `dashboard.view` בכוונה: לקוח "אירועים בלבד" שאין לו
    // את ההרשאה ממשיך ליפול לפריט הניווט הראשון שלו, בדיוק כמו קודם.
    const Page = me.profile.user_kind === 'customer_user' ? CustomerDashboard : DashboardPage
    return (
      <Suspense fallback={<Skeleton className="h-96 w-full" />}>
        <Page />
      </Suspense>
    )
  }

  // `to !== '/'` keeps the dashboard entry from redirecting this route to itself
  const visible = visibleNavSections(has, audience)
  // עובד שטח נוחת בשעון הנוכחות, לא בלוח השנה של התפקיד — ראו isFieldUser
  if (isFieldUser(visible)) return <Navigate to={FIELD_HOME[0]} replace />
  // דף הפתיחה אינו "היעד הראשון" — אלא אם המשתמש בחר בו (למעלה)
  const first = visible.flatMap((s) => s.items).find((n) => n.to !== '/' && n.to !== START_PATH)
  if (first) return <Navigate to={first.to} replace />

  return (
    <Card>
      <EmptyState
        art="alert"
        title="אין לך עדיין גישה"
        description="לא הוגדרו עבורך הרשאות צפייה. פנה למנהל המערכת כדי לקבל גישה."
      />
    </Card>
  )
}
