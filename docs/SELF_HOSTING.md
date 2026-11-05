# הרצה על שרת פרטי (VPS)

מאז נובמבר 2026 המערכת רצה על Supabase מותקן בשרת פרטי (docker compose), ולא
על Supabase בענן. הפרויקט בענן (`qdrbhwxnijjmprtzxfai`) כבר לא בשימוש — לא
מתקינים בו מיגרציות ולא פורסים אליו פונקציות.

בכל המסמך: `<URL>` = הכתובת הציבורית של ה-Supabase בשרת (מה שמוגדר ב-
`SUPABASE_PUBLIC_URL` / `API_EXTERNAL_URL` ב-`.env` של docker), למשל
`https://api.example.co.il`.

---

## 1. האפליקציה (Vercel)

ב-Vercel → Project → Settings → Environment Variables:

| משתנה | ערך |
|---|---|
| `VITE_SUPABASE_URL` | `<URL>` |
| `VITE_SUPABASE_ANON_KEY` | ה-`ANON_KEY` מה-`.env` של השרת |

אחרי שינוי — Redeploy. (ה-Service Worker שומר קריאות לפי המקור של
`VITE_SUPABASE_URL`, כך שאין צורך לנקות דבר אצל המשתמשים.)

## 2. מיגרציות

אין חיבור אוטומטי. כל מיגרציה חדשה ב-`supabase/migrations` מותקנת ידנית:

- Studio בשרת → **SQL Editor** → מדביקים את כל הקובץ → **Run**, או
- מהשרת: `psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/02xx_….sql`

לבדוק שמשהו נכנס: `select md5(prosrc) from pg_proc where proname = '<function>';`
והשוואה ל-md5 שכתוב ב-PR.

מיגרציות שחייבות להיות בשרת (נוספו אחרי המעבר): **0237** (טעינת ההרשאות),
**0238** (ההתראות), **0239** (מהירות בדיקת ההרשאות — לו״ז עבודה ושאר המסכים).

## 3. ההתראות (push ומייל)

ההתראה בפעמון היא שורה במסד הנתונים ועובדת תמיד. push ומייל יוצאים כך:
שורה ב-`notification_deliveries` → טריגר `app.notify_dispatch_ping` קורא
ב-`pg_net` לפונקציה `notify-dispatch` → היא שולחת.

### 3.1 הגדרות במסד הנתונים

ב-SQL Editor של השרת (מחליפים את הערכים):

```sql
-- הכתובת: עדיף הכתובת הפנימית של docker (בלי DNS ו-TLS)
select vault.create_secret('http://kong:8000/functions/v1/notify-dispatch', 'notify_dispatch_url');
-- סוד חדש וארוך, כל מחרוזת אקראית
select vault.create_secret('<סוד אקראי ארוך>', 'notify_dispatch_secret');
```

אם השם כבר קיים (הגיע בגיבוי מהענן) — הוא מוצפן במפתח של הענן ולא נפתח
כאן. מעדכנים אותו:

```sql
select vault.update_secret(id, '<ערך חדש>') from vault.secrets where name = 'notify_dispatch_secret';
select vault.update_secret(id, 'http://kong:8000/functions/v1/notify-dispatch') from vault.secrets where name = 'notify_dispatch_url';
```

(בלי Vault אפשר גם: `alter database postgres set app.notify_dispatch_url = '…';` ו-
`app.notify_dispatch_secret`. ‏Vault קודם.)

וגם: `create extension if not exists pg_net;`

### 3.2 הפונקציה `notify-dispatch`

1. מעתיקים את `supabase/functions/notify-dispatch/index.ts` לשרת:
   `docker/volumes/functions/notify-dispatch/index.ts`.
2. משתני סביבה לשירות `functions` ב-`docker-compose.yml` (או ב-`.env`):
   - `VAPID_KEYS` — **אותם מפתחות שהיו בענן**, אחרת כל מכשיר שנרשם לקבלת
     התראות יקבל שגיאה ויצטרך להירשם מחדש. בענן הם שמורים ב-Vault:
     ב-SQL Editor **של הפרויקט בענן**:
     `select decrypted_secret from vault.decrypted_secrets where name = 'VAPID_KEYS';`
     (ערך JSON עם `publicKey` ו-`privateKey`).
   - `VAPID_SUBJECT` — `mailto:` של מישהו בחברה.
   - `RESEND_API_KEY` — רק אם שולחים מיילים.
   - `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` — ה-compose מעביר אותם לבד.
3. `docker compose restart functions`.

### 3.3 בדיקת JWT — המלכודת של השרת הפרטי

בענן, בדיקת ה-JWT מוגדרת לכל פונקציה בנפרד. בשרת הפרטי יש מתג אחד לכולן:
`VERIFY_JWT` ב-`.env`, והוא נאכף ב-`docker/volumes/functions/main/index.ts`.
הטריגר של ההתראות, ה-webhooks של ViperFlow/Arco/WhatsApp ו-Google שולחים
**בלי** JWT, ולכן כש-`VERIFY_JWT=true` הם נחסמים (401) לפני שהקוד שלנו רץ.

הפונקציות שחייבות לעבור בלי JWT (כל אחת מאמתת סוד משלה בקוד):
`notify-dispatch`, `viperflow-webhook`, `arco-intake`, `arco-dispatch`,
`invoice-gmail`, `whatsapp-webhook`, `fleet-expiry-sweep`.

ב-`main/index.ts`, במקום שבו נבדק `VERIFY_JWT`, מוסיפים פטור לרשימה הזו
(שם הפונקציה הוא החלק הראשון בנתיב, `service_name`):

```ts
const NO_JWT = new Set(['notify-dispatch', 'viperflow-webhook', 'arco-intake', 'arco-dispatch',
  'invoice-gmail', 'whatsapp-webhook', 'fleet-expiry-sweep'])
// ...
if (req.method !== 'OPTIONS' && VERIFY_JWT && !NO_JWT.has(service_name)) { /* הבדיקה הקיימת */ }
```

(המיקום המדויק תלוי בגרסת התבנית; צריך שהשם יחושב לפני הבדיקה.)

### 3.4 לבדוק

ב-SQL Editor, כמנהל מערכת דרך האפליקציה או ישירות:

```sql
select notify_dispatch_status();
```

מחזיר: הכתובת, האם הסוד מוגדר, האם `pg_net` מותקן, האם push מופעל
(`app_settings` → `notifications.push.enabled`), כמה ממתינים בתור, מתי נשלח
האחרון, ו-5 השגיאות האחרונות. אחרי שהכול מוגדר — ההתראה הבאה תגרום לשליחה
של כל מה שחיכה בתור (עד 5 ניסיונות לשורה).

## 4. שאר הפונקציות

מעתיקים את כל `supabase/functions/*` (כולל `_shared`) ל-`docker/volumes/functions/`,
ומגדירים את הסודות של כל אחת (הרשימה ב-`CLAUDE.md` §6 "Secrets"). שני דברים
שהיו רק בענן ואינם במאגר: `generate-vapid` (חד-פעמי, לא צריך) ו-`wall-feed`
(בענף `claude/wall-feed-crew`).

## 5. כתובות חיצוניות שצריך לעדכן

כל מי ששולח אלינו בקשות צריך לקבל את הכתובת החדשה `<URL>/functions/v1/...`:

| מערכת | איפה | כתובת חדשה |
|---|---|---|
| ViperFlow | הגדרות ה-webhook | `<URL>/functions/v1/viperflow-webhook/<connection id>` |
| Arco (Make) | התרחישים ב-Make | `<URL>/functions/v1/arco-intake/event`, `…/spec` |
| WhatsApp (Green API) | Webhook URL | `<URL>/functions/v1/whatsapp-webhook` |
| Google OAuth (חשבוניות) | Authorized redirect URI | `<URL>/functions/v1/invoice-gmail/callback` |

ובמסד הנתונים (אם בשימוש):
`alter database postgres set app.invoice_gmail_url = 'http://kong:8000/functions/v1/invoice-gmail';`
וכן `app.arco_dispatch_url` באותה צורה.

## 6. התחברות ומשימות מתוזמנות

- **Auth**: ב-`.env` של השרת: `SITE_URL` = כתובת האפליקציה, `ADDITIONAL_REDIRECT_URLS`,
  ו-SMTP (בלי SMTP לא יוצא מייל איפוס סיסמה).
- **pg_cron**: לוודא שהמשימות קיימות: `select jobname, schedule, active from cron.job;`
  צריכות להיות `war-room-10am` (`0 7,8 * * *`) ו-`invoice-gmail-sync` (`23 */3 * * *`).
- **statement_timeout**: `select rolname, rolconfig from pg_roles where rolname = 'authenticated';`
  בענן זה היה 8 שניות.
