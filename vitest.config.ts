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
  },
})
