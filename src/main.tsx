import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { QueryClientProvider } from '@tanstack/react-query'
import { RouterProvider } from 'react-router/dom'
import { registerSW } from 'virtual:pwa-register'
import './index.css'
import { router } from './app/router'
import { ErrorBoundary, ToastProvider } from './components/ui'
import { reportError } from './lib/reportError'
import { queryClient } from './lib/queryClient'
import { useAuth } from './state/auth'
import { installZoomGuard } from './lib/zoomGuard'

registerSW({ immediate: true })
installZoomGuard()

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
