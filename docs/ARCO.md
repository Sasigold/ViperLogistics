# החיבור לארקו (דרך Make)

מדריך ההפעלה: מה עובר בצינור, מה להגדיר בשני הצדדים, ומה לעשות כשמשהו נתקע.
הנימוקים יושבים בכותרות של המיגרציות `0182`–`0184`; כאן רק מה שצריך כדי
שזה יעבוד.

## מה זה עושה

‏**ארקו** מנהלת את ההזמנות שלה ב-Origami, ושני תרחישים ב-Make הם הגשר.
שניהם קיימים כבר היום וכותבים ל-Firestore של המערכת הקודמת. **לא נגענו
בהם** — נוספה להם תחנה: מודול HTTP אחרי מודול ה-Firestore, שכותב גם אלינו.
שתי המערכות מתעדכנות זו לצד זו, וכיבוי הישנה יהיה יום אחד מחיקה של מודול
אחד.

| התרחיש ב-Make | מה הוא עושה אצלנו |
|---|---|
| **craet_doc** — הזמנה נפתחה | נפתח **אירוע** על הלקוח של החיבור, עם **הקמה ופירוק**, והתשובה מחזירה את **מחיר כל משימה** |
| **update_doc** — המפרט הוחלף | נרשמת **גרסת מפרט** חדשה על האירוע (רשימת המפרטים, כפתור "מפרט") |

ובכיוון השני: **כל שינוי באירוע של ארקו** — אצלנו או משם — נשלח כ-webhook
לכתובת שהיא נתנה.

### מה מתורגם לאיזה שדה

| ההזמנה בארקו | האירוע אצלנו |
|---|---|
| `order_number` (ספרות בלבד) | מספר אירוע — והוא גם המפתח שמחבר בין השניים |
| `customer_name` | הלקוח הסופי |
| `order_date` | תאריך האירוע (‏UTC → שעון ישראל) |
| `location` | המיקום, **וגם הפין**: הכתובת עוברת גיאוקודינג, כי אזור הנסיעה הוא חלק מהמחיר. אולם שכבר היינו בו יורש את הפין שסומן בפעם הקודמת (0185) |
| `event_status` | סטטוס האירוע, לפי השם |
| `truck_quantity`, `volume` | כמות משאיות, נפח |
| `parking`, `porterage`, `supplier_collection` | אין חניה, סבלות, איסוף מספק — שלוש תוספות התמחור |
| `operational_contact_*`, `operational_notes` | איש קשר, והערות (בלידה בלבד) |
| `setup_*` / `dismantling_*` | משימת ההקמה ומשימת הפירוק: תאריך, שעה, שעות, עובדים, אופן ביצוע |
| `*_execution_contractor` = שם הלקוח | המשימה מסומנת "מבוצע ע״י ארקו" — ומחירה 0 (0120) |

מה ש**אינו** מסונכרן ונשאר שלנו לחלוטין: השיבוץ, הקבלן, המשאית, סטטוס
המשימה, שעת היציאה מהמחסן, הערות הרכז אחרי הלידה, ומחיר שאדם נעל ביד.

**חצות אינה שעה.** ‏Origami מייצא תאריך-בלבד כחותמת של חצות מקומית. חותמת
כזו נקראת כתאריך, והשעה נשארת ריקה — אחרת הייתה נפתחת משימה ב-00:00.

**המחיר אינו מחושב כאן.** הוא מה שמנוע התמחור של הלקוח (0017) כבר חישב
ברגע שהמשימה נכתבה. משימה שמחירה ננעל ידנית חוזרת עם `price_is_manual: true`.

## מה צריך להגדיר — לפי הסדר

### 1. סודות של פונקציות הקצה

הסודות **אינם** יושבים במסד: ‏`app_settings` קריאה לכל משתמש מאומת, וכתובת
‏webhook של Make היא מפתח לכל דבר — מי שמחזיק אותה יכול לכתוב לתרחיש.

```bash
supabase secrets set \
  ARCO_INTAKE_SECRET="$(openssl rand -hex 24)" \
  ARCO_DISPATCH_SECRET="$(openssl rand -hex 24)" \
  ARCO_EVENT_WEBHOOK_URL='https://hook.eu2.make.com/…'
```

| סוד | למה | חובה |
|---|---|---|
| `ARCO_INTAKE_SECRET` | מה ששני התרחישים שולחים בכותרת `x-arco-secret` | כן |
| `ARCO_DISPATCH_SECRET` | מה שהטריגר שולח ל-`arco-dispatch`; זהה ל-GUC שבסעיף 4 | לדיווח |
| `ARCO_EVENT_WEBHOOK_URL` | כתובת ה-webhook שאליה נשלח כל שינוי | לדיווח |
| `ARCO_WEBHOOK_TOKEN` | רשות — נשלח ככותרת `x-viper-token`, כדי שהצד השני יזהה אותנו | לא |

### 2. פריסת שתי פונקציות הקצה

```bash
# חובה --no-verify-jwt: המודול ב-Make נושא את הסוד המשותף שלנו ולא JWT של
# Supabase, ושער ה-JWT היה עונה 401 לפני שהקוד שלנו רץ.
supabase functions deploy arco-intake   --no-verify-jwt
supabase functions deploy arco-dispatch --no-verify-jwt
```

### 3. החיבור אצלנו

במסך **אינטגרציות** (`/integrations`, מפתח `integrations.manage`), או ב-SQL:

```sql
select arco_set_connection(
  p_customer_id    => '<מזהה הלקוח ארקו>',
  p_name           => 'ארקו',
  p_is_active      => true,    -- קולט הזמנות
  p_notify_updates => true);   -- ומדווח על כל שינוי
```

**הלקוח נבחר ואינו מוקשח בקוד.** בשום מקום באינטגרציה אין השוואה לשם
'ארקו'; מה שקושר הוא `arco_connections.customer_id`. המיגרציה פותחת שורה
ללקוח הראשון ששמו מכיל "ארקו", ואפשר להחליף בכל רגע.

שני המתגים נפרדים בכוונה: אפשר להפסיק לדווח בלי להפסיק לקלוט, ולהפך.

### 4. הצלצול של הדיווח

הטריגר מצלצל ל-`arco-dispatch` דרך `pg_net`, ושתי ההגדרות האלה הן כתובת
הפונקציה והסוד שלה. בלעדיהן התור **מתמלא ואינו נשלח** — עד שמישהו יקרא
לפונקציה (סעיף 6).

```sql
alter database postgres
  set app.arco_dispatch_url = 'https://<project-ref>.supabase.co/functions/v1/arco-dispatch';
alter database postgres
  set app.arco_dispatch_secret = '<אותו ערך של ARCO_DISPATCH_SECRET>';
```

### 5. שני המודולים ב-Make

בכל אחד מהתרחישים, **אחרי** מודול ה-Firestore הקיים, מודול `HTTP › Make a
request`:

| | תרחיש ההזמנה | תרחיש המפרט |
|---|---|---|
| URL | `https://<ref>.supabase.co/functions/v1/arco-intake/event` | `…/arco-intake/spec` |
| Method | POST | POST |
| Headers | `Content-Type: application/json`, `x-arco-secret: <ARCO_INTAKE_SECRET>` | אותו דבר |
| Body | ‏JSON עם שדות ה-webhook (מודול 1) | `{ "order_number": …, "file": … }` |
| Parse response | כן | כן |

בתרחיש ההזמנה נוסף אחריו מודול HTTP שני, ששולח את התשובה — האירוע,
משימותיו והמחיר של כל אחת — ל-webhook של המחירים.

### 6. תזמון (מומלץ, לא חובה)

רשת הביטחון: קריאה אחת מנקזת את כל מה שממתין בתור הדיווח, כולל מה שנכשל.

```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/arco-dispatch" \
  -H "x-arco-secret: $ARCO_DISPATCH_SECRET" \
  -H 'Content-Type: application/json' -d '{}'
```

פעם בשעה מספיקה. בנוסף, פעם ביום:
‏`select arco_prune_deliveries(90);` — מנקה משלוחים ישנים, חוץ ממשלוחים
שנכשלו, שאינם נמחקים בשום גיל: הם עבודה פתוחה.

## מה חוזר לארקו

### בתשובה לפתיחת הזמנה

```jsonc
{
  "status": "created",           // created | updated | ignored | failed
  "event_id": "…",
  "location_resolved": true,     // false ⇒ הכתובת לא זוהתה, והמחיר חסר נסיעה
  "event": {
    "order_number": "26000233",
    "event_date": "2026-10-02",
    "status": "טרם אושר",
    "tasks": [
      { "task_type": "הקמה", "task_type_code": "setup",
        "task_date": "2026-10-01", "onsite_start_time": "08:00",
        "worker_count": 3, "hours_count": 4.0,
        "performed_by": "viper", "price": 3214.0, "price_is_manual": false }
    ],
    "total_price": 3214.0,
    "currency": "ILS"
  }
}
```

### בכל שינוי באירוע

```jsonc
{
  "type": "event.updated",
  "origin": "viper",             // "arco" = הד של מה שהיא עצמה שלחה
  "kinds": ["changed"],
  "changes": [
    { "kind": "changed", "field": "event_date", "label": "תאריך אירוע",
      "old": "02/10/2026", "new": "03/10/2026", "actor": "מתן" }
  ],
  "occurred_at": "…",
  "event": { /* אותה תמונה בדיוק, עם המשימות והמחירים */ }
}
```

**שמירה אחת = הודעה אחת.** עריכה שנגעה בשמונה שדות היא הודעה אחת עם שמונה
שינויים. מה שנחשב שינוי הוא מה שיומן הפעילות שומע: שורת האירוע, אנשי הקשר,
הספקים, שדות המשימה (תאריך, שעה, שעות, עובדים, אופן ביצוע), הוספת משימה
והסרתה, המפרטים והצעת המחיר.

‏`origin: "arco"` מסמן הד: ‏ארקו שלחה עדכון, אנחנו החלנו אותו, והשינוי חוזר
אליה. התרחיש בצד השני מחליט אם הוא מסנן אותו.

### בכל עדכון שנעשה אצלנו — הצורה השטוחה (0195)

מאז 0195 **המסד שולח בעצמו**, דרך `pg_net`, ברגע ה-commit של השמירה — בלי
‏`arco-dispatch` ובלי סודות של פונקציות קצה. הכתובת יושבת בטבלה הפרטית
‏`app.arco_webhook_targets` (אינה בריפו, ואינה קריאה ל-authenticated):

```sql
insert into app.arco_webhook_targets (connection_id, url)
values ('<arco_connections.id>', 'https://…')
on conflict (connection_id) do update set url = excluded.url, updated_at = now();
```

הגוף הוא אובייקט שטוח אחד, כל ערך מחרוזת (מספר חסר יוצא `null`, טקסט חסר `""`):

```jsonc
{
  "customer_name": "שלומי אילני", "order_number": "200062",
  "location": "חוות רונית", "location_notes": "מקום גדול",
  "date": "23/02/2026", "event_status": "טרם אושר",
  "trucks_count": "1", "volume": "3.5",
  "supplier_pickup": "false", "parking": "true", "porters": "false",
  "contact_name": "רעות", "phone": "054-6600280", "operational_notes": "…",
  "setup_datetime": "23/02/2026 10:00", "setup_method": "סידור",
  "setup_workers": "2", "setup_hours": "3.0",
  "setup_contractor": "וייפר", "setup_price": "1600.0",
  "teardown_datetime": "23/02/2026 20:00", "teardown_method": "איסוף",
  "teardown_workers": "2", "teardown_hours": "3.0",
  "teardown_contractor": "וייפר", "teardown_price": "1800.0"
}
```

‏`*_contractor` הוא "וייפר", או שם הלקוח כשהמשימה מבוצעת ע״י ארקו (ואז המחיר
‏0). `parking` הוא `no_parking` שלנו — אותו מסלול של הקליטה. **הד של ארקו
(`origin = 'arco'`) אינו נשלח** ונרשם בתור כ-`skipped`. מצב כל שליחה:
‏`queued` → `sending` → `sent`/`failed`; ‏`select arco_outbound_retry();`
שולח מחדש את כל מה שב-`queued`/`failed`.

## כשמשהו נתקע

| תסמין | איפה מסתכלים |
|---|---|
| ‏Make מקבל 401 | `ARCO_INTAKE_SECRET` והכותרת `x-arco-secret` אינם זהים |
| ‏Make מקבל 200 אבל אין אירוע | `select * from arco_deliveries order by received_at desc` — העמודה `reason` אומרת למה |
| ההזמנה נקלטה, המחיר נמוך מדי | `location_resolved: false` ⇒ אין פין ⇒ אין שעות נסיעה. מסמנים מיקום במסך האירוע, והמחיר מחושב מחדש מעצמו — **ומאותו רגע כל אירוע עתידי באותו אולם יורש את הפין הזה** (0185) |
| אין דיווחים יוצאים | `select * from arco_outbound where status <> 'sent'` — ואז סעיף 4 (‏GUC-ים) וסעיף 1 (`ARCO_EVENT_WEBHOOK_URL`) |
| דיווח שנכשל חמש פעמים | `select arco_outbound_retry();` מחזיר לתור את כל מה שנשרף |
| משלוח נכנס שצריך להריץ שוב | `select arco_replay('<delivery id>');` |

**כישלון עסקי אינו מחזיר שגיאת HTTP.** תרחיש ב-Make שמקבל 4xx נעצר ומסמן
את עצמו כשבור, ומשלוח אחד שלא ידענו לעכל היה מפיל את הצינור כולו. לכן כל
מה שהגיע עונה 200, והכישלון הוא שורה אדומה ב-`arco_deliveries` עם סיבה
וכפתור "הרץ מחדש". רק תקלה אצלנו (סוד חסר, המסד לא ענה) עונה 5xx.


## מה כבר מותקן

| רכיב | מצב |
|---|---|
| מיגרציות 0182–0185 | הוחלו על פרויקט `ViperLogistics` |
| `arco-intake`, `arco-dispatch` | נפרסו עם `verify_jwt=false` |
| החיבור | נפתח אוטומטית על הלקוח "ארקו" — פעיל, ומדווח |
| שני המודולים ב-Make | נוספו לשני התרחישים, אחרי המודולים הקיימים |
| `geocode-proxy` | **טרם נפרסה מחדש** — ראו למטה |

שלושה דברים נשארו, וכולם בידיים שלך:

1. **הסודות** (סעיף 1). עד שהם מוגדרים, `arco-intake` עונה
   ‏`503 intake secret not configured`, והמודול ב-Make פשוט ממשיך הלאה בלי
   לשבור דבר.
2. **`supabase functions deploy geocode-proxy`** — הגרסה שבריפו מקבלת גם
   קריאה בזהות המערכת, וזה מה שמאפשר ל-`arco-intake` להפוך כתובת לפין.
   בלעדיה כל אירוע חדש נפתח בלי פין (`location_resolved: false`) עד
   שמסמנים אותו ביד.
3. **כתובות ה-webhook** — `ARCO_EVENT_WEBHOOK_URL` לעדכונים, ומודול HTTP
   נוסף בסוף תרחיש ההזמנה לכתובת המחירים.
