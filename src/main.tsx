import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { MutationCache, QueryCache, QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { RouterProvider } from 'react-router/dom'
import { registerSW } from 'virtual:pwa-register'
import './index.css'
import { router } from './app/router'
import { dismissSplash } from './app/splash'
import { ErrorBoundary, ToastProvider } from './components/ui'
import { reportError } from './lib/reportError'
import { clearCachedReads } from './lib/cachedReads'
import { useAuth } from './state/auth'
import { installZoomGuard } from './lib/zoomGuard'

registerSW({ immediate: true })
installZoomGuard()

/**
 * כל שגיאה עוברת דרך נקודה אחת בדרך החוצה.
 *
 * קודם לכן כישלון בפרודקשן היה נראה רק למשתמש שנתקל בו, בטוסט, ולא השאיר
 * שום עקבה. ה-cache-ים כאן הם המקום היחיד שרואה *כל* שאילתה וכל מוטציה,
 * ולכן הם המקום הנכון לחבר אליו דיווח חיצוני — ולא כל onError בנפרד.
 */
const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 30_000, retry: 1, refetchOnWindowFocus: false },
  },
  queryCache: new QueryCache({
    onError: (error, query) => reportError(error, { kind: 'query', key: query.queryHash }),
  }),
  mutationCache: new MutationCache({
    onError: (error, _vars, _ctx, mutation) =>
      reportError(error, { kind: 'mutation', key: mutation.options.mutationKey?.join('/') }),
  }),
})

/**
 * הנתונים שייכים למשתמש שקרא אותם. כשהוא יוצא או מתחלף באותה לשונית (מנהל
 * שנכנס בשם עובד כדי לבדוק מה הוא רואה), ה-cache של React Query נשאר בזיכרון
 * ומוצג מיד למי שנכנס — לוח השנה המלא של הקודם, עד שהשאילתה חוזרת. אז מנקים
 * אותו, ואת המטמון של ה-service worker איתו (0217). הכניסה הראשונה (אין משתמש
 * קודם) אינה מנקה: העותקים במטמון כבר שמורים לפי משתמש.
 */
let lastUserId: string | null = null
useAuth.subscribe((state) => {
  const userId = state.session?.user.id ?? null
  if (lastUserId !== null && userId !== lastUserId) {
    queryClient.clear()
    void clearCachedReads()
  }
  lastUserId = userId
})

void useAuth.getState().boot().finally(dismissSplash)

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorBoundary onError={(error, info) => reportError(error, { kind: 'render', componentStack: info.componentStack })}>
      <QueryClientProvider client={queryClient}>
        <ToastProvider>
          <RouterProvider router={router} />
        </ToastProvider>
      </QueryClientProvider>
    </ErrorBoundary>
  </StrictMode>,
)
