# ViperLogistics — מערכת ניהול כוח אדם להשכרת ציוד לאירועים

מערכת Web מודרנית (Multi-Tenant) לניהול עובדים, נהגים, ראשי צוות, קבלנים ושיבוצים
עבור חברת השכרת ציוד לאירועים. עברית מלאה (RTL) + Dark Mode.

## סטאק

- **Frontend:** Vite + React 19 + TypeScript, Tailwind CSS v4, TanStack Query + Virtual,
  FullCalendar v6 (חינמי), Recharts, ExcelJS, Zustand
- **Backend:** Supabase — Postgres 17 עם RLS מלא, Auth, Edge Functions, Realtime
- **כתובות:** Nominatim (OSM) דרך Edge Function פרוקסי, עם שכבת Adapter הניתנת להחלפה ל-Google Places

## מודולים

| מסך | נתיב | תיאור |
|---|---|---|
| דשבורד | `/` | מונים, משימות היום/שבוע/באיחור, התפלגויות וגרפים |
| לוח שנה | `/calendar` | חודש/שבוע/יום/סדר-יום, צבע פר-לקוח, גרירת תאריך ושעה, פילטרים + פילטרים שמורים |
| לוח עבודה | `/board` | כל המשימות בטבלה וירטואלית, עריכה inline, שיבוץ עובדים/נהגים/משאיות, Bulk Edit |
| אירועים | `/events` | טופס דינמי פר-לקוח (מוצג/מוסתר/חובה), תוספות, ספקים, שכפול, ייבוא/ייצוא Excel |
| לקוחות | `/customers` | פרטים, צבע, קונפיגורציית שדות טופס, אופני ביצוע זמינים, ספקים |
| עובדים | `/users` | סוגי משתמשים, ריבוי תפקידים (עובד/נהג/ראש צוות), עורך הרשאות מלא + הרשאות שדה |
| קבלנים | `/contractors` | סגל עובדים, האצלת משימות, תמחור וסימון תשלומים |
| פורטל קבלן | `/portal` | Dashboard כספי, משימות, החלפת עובדים בלבד (מיקום/זמן/כמות נעולים ב-RLS) |
| הגדרות | `/settings` | סוגי משימות, אופני ביצוע, סטטוסים, משאיות, סל מיחזור, יומן פעילות |

## אבטחה והרשאות

- **RLS מלא** על כל הטבלאות; אדמין ⟶ הכול, לקוח ⟶ רק הנתונים שלו, קבלן ⟶ רק משימותיו.
- קבלן **אינו יכול** לשנות מיקום/זמן/לקוח/כמות — משטח הכתיבה היחיד שלו הוא טבלת
  `task_contractor_workers` (החלפת עובדים מהסגל שלו בלבד, עד כמות העובדים שהוגדרה).
- שדות רגישים (טלפון איש קשר, מחירי קבלן) בטבלאות נפרדות עם RLS משלהן — אכיפת שרת אמיתית.
- הרשאות פר-משתמש (צפייה/יצירה/עריכה/מחיקה פר-משאב) + הרשאות ברמת שדה.
- Audit Log על כל שינוי, Soft Delete עם סל מיחזור, התראות Realtime.

## הרצה מקומית

```bash
cp .env.example .env.local   # ולמלא את מפתח ה-anon
npm install
npm run dev
```

## מבנה

```
supabase/migrations/   # 0001..0008 — סכמה, זריעה, RLS, RPCs, הקשחה
supabase/functions/    # admin-users (ניהול חשבונות), geocode-proxy (Nominatim)
src/features/          # מודול לכל פיצ'ר: calendar, workboard, events, customers,
                       # users, contractors, portal, settings, notifications, search...
src/components/ui.tsx  # ערכת UI (RTL + Dark Mode)
src/lib/               # supabase, queries, dates, address adapter
```

## הערות תפעול

- ליצירת משתמשים עם סיסמה משתמשים ב-Edge Function ‏`admin-users` (service role בצד השרת בלבד).
- Nominatim מוגבל לבקשה בשנייה — הפרוקסי מוסיף cache; לשימוש כבד מומלץ לעבור ל-Google Places
  דרך ה-Adapter (`src/lib/address.ts`).
- מומלץ להפעיל Leaked Password Protection בהגדרות ה-Auth בדשבורד של Supabase.
