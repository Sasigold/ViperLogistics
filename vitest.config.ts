import { defineConfig } from 'vitest/config'

/**
 * בדיקות היחידה רצות ב-node ובלי DOM במכוון: מה שנבדק כאן הוא הלוגיקה
 * הטהורה — הכרעת ההרשאות, גזירת המשמרת לתצוגה, קיבוץ הלוח ומיפוי השגיאות —
 * ולא הרנדור. זה מה שמחזיק את החבילה מהירה ובלי תלות ב-jsdom.
 */
export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
    setupFiles: ['./vitest.setup.ts'],
    /**
     * `lib/supabase.ts` builds its client at import time and throws without a
     * URL. A test that reaches any feature module pulls it in transitively —
     * the widget registry does, on its way to the components it names — so the
     * suite needs *a* value here. Nothing in these tests makes a request; the
     * placeholders exist so importing a module is not the same as configuring
     * an app.
     */
    env: {
      VITE_SUPABASE_URL: 'http://localhost:54321',
      VITE_SUPABASE_ANON_KEY: 'test-anon-key',
    },
  },
})
