# חשבוניות ספקים (0233)

הדף `/invoices` — למנהלי מערכת בלבד. מעלים חשבונית (PDF או תמונה), מצלמים
(התמונה נשמרת כ-PDF), או מחברים את Gmail. Claude קורא כל חשבונית: ספק, ח.פ.,
מספר, תאריך, סכום לפני מע"מ, מע"מ, סה"כ, סוג הוצאה, השורות, ועבור איזו חברה
היא יצאה. כל חודש הוא "תיקייה" עם סיכום, ומכל תיקייה יוצא ZIP לרואה החשבון:
קובץ Excel (סיכום, רשימת החשבוניות, השורות) ולצידו כל קובצי ה-PDF, ממוספרים
לפי התאריך.

## מה בנוי איפה

| חלק | איפה |
|---|---|
| טבלאות, הרשאה, RPCs, דלי `invoices`, pg_cron | `supabase/migrations/0233_invoices.sql` (בדיקות: `supabase/tests/75_invoices.sql`) |
| קריאת חשבונית שהועלתה | פונקציית קצה `invoice-read` (JWT פעיל) |
| חיבור Gmail וסריקה | פונקציית קצה `invoice-gmail` (**`--no-verify-jwt`** — Google חוזר אליה בלי JWT; כל POST בודק את הקורא בעצמו) |
| ההנחיה, הסכמה, הנרמול, עזרי Gmail ו-OAuth | `supabase/functions/_shared/invoice.ts` (טהור, נבדק ב-vitest) + `invoiceRead.ts` |
| המסך | `src/features/invoices/*` |

## הפעלה בייצור — פעם אחת

1. **מיגרציה**: `0233_invoices.sql` (דרך `apply_migration`). אין בה `drop` ואין
   `delete`, כך שהכלי לא נתקע. אם היא גדולה מדי לקריאה אחת — לפצל לפי הסעיפים
   (`-- ===== N.`).
2. **קריאה אוטומטית**: `invoice-read` משתמשת באותו `ANTHROPIC_API_KEY` של
   `payslip-read`. פריסה רגילה:
   `supabase functions deploy invoice-read`
   (אופציונלי: `INVOICE_MODEL`, ברירת מחדל `claude-opus-5-5`).
   בלי המפתח הכול עובד, רק בלי קריאה — מקלידים ביד.

## חיבור Gmail — ההגדרה ב-Google Cloud (פעם אחת)

1. https://console.cloud.google.com → פרויקט חדש (למשל "Viper Invoices").
2. **APIs & Services → Library** → לחפש **Gmail API** → Enable.
3. **APIs & Services → OAuth consent screen** (Google Auth Platform):
   - User type: **External**.
   - שם האפליקציה, מייל תמיכה, מייל מפתח.
   - **Data access / Scopes**: להוסיף `https://www.googleapis.com/auth/gmail.readonly`.
   - **Audience**: להעביר ל-**In production** (Publish app). במצב Testing
     Google מבטל את החיבור כל 7 ימים. אפליקציה שלא עברה אימות מציגה בחיבור
     מסך "Google hasn't verified this app" — לוחצים Advanced → Go to … (זה
     בסדר לשימוש פנימי של עד 100 משתמשים; אימות מלא נדרש רק לאפליקציה ציבורית).
4. **APIs & Services → Credentials → Create credentials → OAuth client ID**:
   - Application type: **Web application**.
   - **Authorized redirect URIs**:
     `https://<project-ref>.supabase.co/functions/v1/invoice-gmail/callback`
   - לשמור את ה-**Client ID** וה-**Client secret**.
5. סודות לפונקציות הקצה (Dashboard → Edge Functions → Secrets, או CLI):
   ```
   supabase secrets set GOOGLE_OAUTH_CLIENT_ID=...
   supabase secrets set GOOGLE_OAUTH_CLIENT_SECRET=...
   supabase secrets set INVOICE_GMAIL_SYNC_SECRET=<מחרוזת אקראית ארוכה>
   ```
6. פריסה: `supabase functions deploy invoice-gmail --no-verify-jwt`
7. סריקה אוטומטית כל 3 שעות (pg_cron כבר מתוזמן במיגרציה; הוא שולח רק כשיש
   לאן):
   ```sql
   alter database postgres set app.invoice_gmail_url =
     'https://<project-ref>.supabase.co/functions/v1/invoice-gmail';
   alter database postgres set app.invoice_gmail_secret = '<אותו INVOICE_GMAIL_SYNC_SECRET>';
   ```
8. במסך: ⚙ הגדרות → **החברות שלי** — להוסיף את "וייפר מיקור חוץ לעסקים" עם
   ח.פ. ושמות נוספים (למשל באנגלית). בלי חברה מוגדרת Gmail לא מושך דבר.
   ואז **חיבור Gmail** → הסכמה ב-Google → חזרה למסך → **סריקת Gmail**.

## איך הסריקה מחליטה

- מחפשת מיילים עם PDF/JPG/PNG מצורף (`has:attachment`), מאז הסריקה המלאה
  האחרונה פחות יומיים; בפעם הראשונה — 60 יום אחורה. אפשר להוסיף סינון
  בתחביר של Gmail לכל חשבון (`from:…`, `label:…`).
- כל קובץ מצורף נקרא ב-Claude. נשמר רק אם הוא חשבונית, **והנמען שבה** (ח.פ.,
  ואם אין — השם או אחד השמות הנוספים) הוא אחת החברות. אותו קובץ פעמיים
  (sha256) לא נשמר.
- כל מייל שנבדק נרשם ואינו נקרא שוב. תמונה זעירה (לוגו, חתימה) מדולגת.
- ריצה אחת מוגבלת בזמן; "סריקת Gmail" במסך ממשיכה עד הסוף, והריצה המתוזמנת
  ממשיכה מאותו מקום.
- ההרשאה היא קריאה בלבד. ה-refresh token נשמר בטבלה סגורה
  (`invoice_gmail_accounts`) שרק service_role קורא. ניתוק מוחק אותו מיד.

## כסף

הסיכומים (לפני מע"מ, מע"מ, סה"כ, לפי סוג הוצאה) מחושבים בשרת
(`invoices_board`). חשבונית זיכוי נשמרת בסכומים שליליים. מטבע זר מופיע ברשימה
ובייצוא אבל לא בסיכום בשקלים. חשבונית שאושרה ביד ("שמירה ואישור") אינה נדרסת
בקריאה חוזרת.
