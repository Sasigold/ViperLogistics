import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { MutationCache, QueryCache, QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { RouterProvider } from 'react-router/dom'
import { registerSW } from 'virtual:pwa-register'
import './index.css'
import { router } from './app/router'
import { ErrorBoundary, ToastProvider } from './components/ui'
import { reportError } from './lib/reportError'
import { useAuth } from './state/auth'

registerSW({ immediate: true })

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

void useAuth.getState().boot()

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
