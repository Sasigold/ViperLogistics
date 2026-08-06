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
| אירועים | `/events` | טופס דינמי פר-לקוח (מוצג/מוסתר/חובה), תוספות, ספקים, שכפול, ייבוא/ייצוא Excel, יומן פעילות |
| לקוחות | `/customers` | פרטים, צבע, קונפיגורציית שדות טופס, אופני ביצוע זמינים, ספקים |
| עובדים | `/users` | סוגי משתמשים, ריבוי תפקידים (עובד/נהג/ראש צוות), תפקידי הרשאה, מטריצת הרשאות, הרשאות שדה והגבלת נתונים |
| קבלנים | `/contractors` | סגל עובדים, האצלת משימות, תמחור וסימון תשלומים |
| פורטל קבלן | `/portal` | Dashboard כספי, משימות, החלפת עובדים בלבד (מיקום/זמן/כמות נעולים ב-RLS) |
| הגדרות | `/settings` | סוגי משימות, אופני ביצוע, סטטוסים, משאיות, תפקידים והרשאות, סל מיחזור |

### יומן פעילות של אירוע

בדף האירוע יושב יומן שמתעד שני דברים באותו ציר זמן: **שינויים** ו**מלל חופשי**.

- שינוי בשדה מעקב באירוע (כמות משאיות, תאריך, סטטוס, לקוח, מיקום, נפח, הערות, תוספות,
  איש קשר, ספקים) נרשם אוטומטית בטריגר — עם הערך הקודם, הערך החדש, מי שינה ומתי.
  הערכים נשמרים כפי שקוראים אותם: מזהה סטטוס הופך לשם הסטטוס, בוליאני ל"כן/לא", תאריך ל-DD/MM/YYYY.
- מי שמחזיק `events.activity_note` יכול להוסיף רשומת מלל חופשי — הסיבה שמאחורי השינוי,
  שיחה עם הלקוח, כל דבר ששווה לזכור.
- היומן לקריאה בלבד אחרי הכתיבה: אין פוליסת UPDATE, ומחיקה שמורה לאדמין.
  שינויים שנעשו בשמירה אחת מקובצים לרשומה אחת בתצוגה.
- `events.activity_log` נגזר מ-`events.view` ו-`events.activity_note` מ-`events.edit`,
  ולכן מי שכבר רואה או עורך אירועים מקבל את היומן בלי הגדרה נוספת.

## אבטחה והרשאות

כל הרשאה היא **שורה ברישום** (`permission_registry`) עם מפתח מנוקד — `tasks.assign.worker`,
`contractors.edit_pricing` — ולא ערך enum. הוספת יכולת חדשה היא `INSERT`, ולכן מודול שייכתב
בעתיד מקבל הרשאות מלאות ומופיע במסך הניהול בלי שינוי קוד.

ההכרעה נעשית במקום אחד, `app.has(key)`, בסדר הזה:

| # | שכבה | טבלה |
|---|---|---|
| 1 | אדמין | `profiles.is_admin` |
| 2 | חריגה אישית (מותר/חסום) | `user_permission_grants` |
| 3 | תפקידים שהמשתמש חבר בהם | `role_permissions` |
| 4 | ברירת מחדל לסוג משתמש | `kind_permission_defaults` |
| 5 | ברירת מחדל של המפתח | `permission_registry.default_allowed` |
| 6 | המפתח הרחב שממנו נגזר | `permission_registry.implied_by` |
| 7 | חסימה | — |

שלב 6 הוא מה שמאפשר לפצל הרשאה גסה לדקות בלי לשבור: `tasks.reschedule` נגזר מ-`tasks.edit`,
ולכן מי שקיבל "עריכת משימות" ממשיך להזיז משימות עד שאדמין יחליט אחרת. תפקיד צר "סוגר מודול"
(חסימה מפורשת) כדי לא לרשת יכולות בטעות.

**איפה זה נאכף**

| שכבה | מנגנון |
|---|---|
| שורות — אילו נתונים רואים | `permission_scopes` בתוך פוליסות ה-SELECT: לקוחות, קבלנים, סוגי משימה, סטטוסים, חלון תאריכים, "רק מה שמשויך אליי" |
| עמודות — עריכה | טריגר גנרי אחד, `app.enforce_field_perms()`, שקורא את `field_registry` לפי שם הטבלה. יושב על הטבלה ולא על ה-RPC ולכן מכסה את כל נתיבי הכתיבה |
| עמודות — צפייה | תצוגות `*_secure` שנוצרות מ-`field_registry`, מיסוך `work_board_view`, ו-`event_activity_feed` שמשמיט שינויים בשדות שאסור לקורא לראות |
| פעולות | `app.require(key)` בתוך ה-RPCs |

- קבלן **אינו יכול** לשנות מיקום/זמן/לקוח/כמות — משטח הכתיבה היחיד שלו הוא
  `task_contractor_workers` (החלפת עובדים מהסגל שלו בלבד, עד הכמות שהוגדרה).
- שיבוץ מפוצל למפתח פר-תפקיד (עובד / נהג / ראש צוות / משאית), ותמחור קבלנים מופרד
  לצפייה / עריכה / סימון תשלום.
- `users.set_admin` אינו נגזר משום הרשאה אחרת — "עריכת משתמשים" אינה דרך להפוך לאדמין.
- Audit Log על כל שינוי, Soft Delete עם סל מיחזור, התראות Realtime.

**הוספת הרשאה למודול חדש** — במיגרציה:

```sql
select app.register_module('billing', 'חיוב', 'חשבוניות ותשלומים', 'Wallet', 120);
select app.register_permission('billing.view', 'billing', 'צפייה בחיוב', p_category => 'access');
select app.register_permission('billing.issue_invoice', 'billing', 'הפקת חשבונית',
       p_dangerous => true, p_implied_by => 'billing.view');
select app.register_field('invoice', 'total', 'סכום', 'billing', 'invoices', 'total',
       p_sensitive => true, p_edit_permission_key => 'billing.issue_invoice');
create trigger invoices_field_perms before update on invoices
  for each row execute function app.enforce_field_perms();
select app.rebuild_secure_view('invoices');
```

## הרצה מקומית

```bash
cp .env.example .env.local   # ולמלא את מפתח ה-anon
npm install
npm run dev
```

## מבנה

```
supabase/migrations/   # 0001..0013 — סכמה, זריעה, RLS, RPCs, מערכת ההרשאות
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
