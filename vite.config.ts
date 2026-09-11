import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { VitePWA } from 'vite-plugin-pwa'

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
    /**
     * האסטרטגיה היא injectManifest ולא generateSW, מסיבה אחת: ‏Workbox אינו
     * יכול לייצר handler ל-`push`, וההתראות ל-PWA מחייבות worker משלנו.
     * ‏src/sw.ts הוא הקובץ, והוא זה שמבצע גם את ה-precache.
     *
     * שלוש מלכודות שקטות במעבר הזה, ולכן כולן מפורשות כאן:
     *   • המפתח `workbox` מתעלם ב-injectManifest. ‏globPatterns חייב לעבור
     *     ל-`injectManifest`, אחרת ה-precache מצטמצם בשקט לברירות המחדל.
     *   • ‏navigateFallback שהיה מובן מאליו ב-generateSW אינו קיים כאן. בלי
     *     ה-NavigationRoute שב-sw.ts קישור עמוק היה נשבר במצב לא מקוון.
     *   • התקרה הרגילה היא 2MiB, והאפליקציה הזו אורזת fullcalendar, recharts,
     *     exceljs ו-leaflet. בלי ההגדלה חלקים היו נושרים מה-precache באזהרה.
     */
    VitePWA({
      strategies: 'injectManifest',
      srcDir: 'src',
      filename: 'sw.ts',
      registerType: 'autoUpdate',
      includeAssets: ['favicon.svg', 'favicon-16x16.png', 'favicon-32x32.png', 'apple-touch-icon.png'],
      manifest: {
        name: 'ViperLogistics — ניהול כוח אדם',
        short_name: 'ViperLogistics',
        description: 'מערכת ניהול כוח אדם ולוגיסטיקה של Viper Logistics',
        lang: 'he',
        dir: 'rtl',
        start_url: '/',
        scope: '/',
        display: 'standalone',
        background_color: '#05070c',
        theme_color: '#05070c',
        icons: [
          {
            src: '/icons/icon-192.png',
            sizes: '192x192',
            type: 'image/png',
            purpose: 'any',
          },
          {
            src: '/icons/icon-512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'any',
          },
          {
            src: '/icons/maskable-icon-512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable',
          },
        ],
      },
      injectManifest: {
        // ‏ttf נכנס בגלל שני קבצי Heebo שמסמך הצעת המחיר מטמיע (0170): הם
        // נטענים ב-fetch בזמן ההפקה, ובלי precache הפקה על רשת חלשה נתקעת
        // על 88KB שכבר ישבו על המכשיר.
        globPatterns: ['**/*.{js,css,html,svg,png,ico,woff2,ttf}'],
        /* מדריך העובד הוא עמוד סטטי שנשלח בקישור, ולא חלק מהאפליקציה: שני
           מגה של צילומי מסך שהיו נכנסים ל-precache הם התקנה כפולה בנפח לכל
           מי שמתקין, בשביל דף שנפתח פעם אחת. */
        globIgnores: ['**/employee-guide/**'],
        maximumFileSizeToCacheInBytes: 4 * 1024 * 1024,
      },
      devOptions: { enabled: false, type: 'module' },
    }),
  ],
})
