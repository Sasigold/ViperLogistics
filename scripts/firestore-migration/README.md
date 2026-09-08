# העברת הנתונים מ-Firestore

העברה חד-פעמית של פרויקט Firebase‏ `nihol-mishmarot` למסד של ViperLogistics.
שלוש קולקציות אירועים, ארבע קולקציות משימות, 1,720 אירועים ו-3,783 משימות.

## הרצה

```bash
node fetch.mjs            ./dump                    # שאיבה מ-Firestore
node fetch-signatures.mjs                           # תמונות החתימה → dump/signatures.json
node build.mjs            ./dump catalog.json ./out # המרה ל-SQL (לא נוגע במסד)

# טעינה — אחת משתיים:
DATABASE_URL='postgresql://...' ./load.sh ./out     # psql
node run-import.mjs viper-firestore-import.sql.gz "postgresql://..."   # בלי psql
```

בסביבה שאין בה חיבור בפרוטוקול Postgres כלל (רק HTTPS), `push-import.mjs`
דוחף את המנות דרך `public.mig_exec` — פונקציה זמנית שנוצרת לפני הטעינה
ונמחקת אחריה. כך בוצעה ההעברה בפועל.

`catalog.json` הוא מפת ה-UUID של הקטלוגים במסד היעד. הוא נבנה פעם אחת
בשאילתה שבראש `catalog.sql`, אחרי הרצת `00_catalogs.sql` ו-`01_form_fields.sql`.

`LIMIT=2 node build.mjs ...` בונה שני אירועים מכל קולקציה — טעינת ניסיון
שעוברת בדיוק באותו קוד כמו המלאה.

## המקור

| קולקציה | מסמכים | מה זה |
| --- | --- | --- |
| `achaotMechir` | 1,137 | אירועי ארקו |
| `caesar` | 258 | אירועי קיסר |
| `eventsCdesign` | 325 | אירועי שיא עיצובים |
| `achaotMechir/{id}/mesimotArco` | 675 | משימות של אירוע ארקו |
| `caesar/{id}/mesimotCaesar` | 522 | משימות של אירוע קיסר |
| `eventsCdesign/{id}/mesimotC` | 654 | משימות של אירוע שיא עיצובים |
| `achaotMechir/{id}/mesimot` | 14 | תת-קולקציה ישנה; האירועים שמעליה נמחקו |
| `mesimot` | 1,337 | משימות של אירועי ארקו שאין להם תת-קולקציה, ומשימות עצמאיות |

‏`users`, `siomaroa` ו-`movilim` אינם מועברים.

## מבנה

מסמך אירוע מחזיק שני "חלקים" — הקמה (`akama*`) ופירוק (`pirok*`) — וזה בדיוק
המודל כאן: אירוע ושתי משימות. משימה נבנית מאחד משלושה מקורות, לפי הסדר:

1. מסמך בתת-הקולקציה של האירוע;
2. מסמך ב-`mesimot` הראשית, לפי `sayachAkama` / `shyachPirok`;
3. השדות הפנימיים של האירוע עצמו — 595 משימות שאין להן מסמך משלהן.

## מיפוי — אירוע

| Firestore | עמודה |
| --- | --- |
| `name` | `end_client_name` |
| `makat` | `event_number` |
| `date` | `event_date` (תאריך בשעון ישראל) |
| `mikom` | `location_text` |
| `earotLmikom` | `location_notes` |
| `nefach` | `volume_m` |
| `masaiot` | `truck_count` |
| `earot` | `notes` |
| `statos` | `status_id` |
| `chania` | `no_parking` — **הפוך**: `chania=false` פירושו שאין חניה |
| `sabalot` | `porterage` |
| `aisufMesapak` | `supplier_pickup` |
| `nameAishKesher` / `aishKesher` | `event_contacts` |
| `maseggges[]` | `event_activity` |
| `mifrat[]`, `informationImage[]` | `event_specs` (source=`link`) |
| `sign` | `event_signatures` |

הקבצים נשארים ב-Firebase Storage ונשמרים כקישור, לפי החלטת הלקוח.

## מיפוי — משימה

| Firestore | עמודה |
| --- | --- |
| `akameOperok` | `task_type_id` (הקמה/פירוק/עבודה במחסן/סידור/איסוף/אחר) |
| `date` / `dateStart` | `task_date`, `onsite_start_time` |
| `timeMachsan` | `warehouse_start_time` |
| `end`−`start` | `hours_count` |
| `camotAnashim` | `worker_count` |
| `ofenBichoa` | `execution_method_id` |
| `rechev[]` | `truck_ids`, והשאר ל-`truck_free_text` יחד עם `ayzeMasait` |
| `earot` | `notes` |
| `cablanName` / `cablan[0].name` | `contractor_id` |
| `cablanRashiName` | `performed_by` — ארקו→`arko`, אחרת `viper` |
| `mechirAkama` / `mechirPirok` / `mecir` | `task_pricing.price` |
| `cablan[]`, `cablan_akama[]`, `cablan_pirok[]` | `task_contractor_terms` |

‏`onsite_end_time` היא עמודה מחושבת ואי אפשר לכתוב אליה, ולכן `hours_count`
נגזר מהפרש חותמות הזמן — כך שהשעה המוצגת זהה למה שהיה במקור. השניים
מסכימים ב-1,483 מתוך 1,493 המשימות שיש בהן גם `zmanMesima`.

## שדות מותאמים

| לקוח | Firestore | תווית |
| --- | --- | --- |
| ארקו | `scomObala` | סכום הובלה |
| ארקו | `mechirLogistica` / `mechirLogisticaPirot` | מחיר / פירוט לוגיסטיקה |
| ארקו | `mechirHovala` / `mechirHovalaPirot` | מחיר / פירוט הובלה |
| ארקו | `mitgalgelLaovala` | מתגלגל להובלה |
| ארקו | `tnaayTashlum` | תנאי תשלום |
| קיסר | `mechirRihot` / `myGove` / `typePrice` | מחיר ריהוט / מי גובה / תנאי תשלום |
| שיא עיצובים | `mechirRihot` / `priceChadash` / `linkToEroit` | מחיר ריהוט / מחיר חדש / קישור ל-Eruit |

## החלטות

**סטטוסי אירוע.** כפילויות אוחדו ("מאושר סופית" = "אושר סופית" = "הארוע אושר
סופית"), וחמישה ערכים שאין להם מקבילה נוספו לקטלוג: הזמנה חדשה, תומחר,
בהמתנה לתמחור מחדש, הקמה בוצעה, אירוע בוצע. בלעדיהם 700+ אירועים היו
מאבדים את מצבם.

**סטטוס משימה.** כל המשימות נטענות כ"מתוכנן". לישות משימה יש כאן שלושה
סטטוסים בלבד — "הושלם", "בוטל" ו"בביצוע" נמחקו רכות ב-2026-08 — ו"משובץ"
הוא פרסום לעובדים, שלא רוצים לעשות לאלפי משימות היסטוריות. משימה של אירוע
מבוטל ממילא אינה נראית: `app.live_tasks` מסננת לפי סטטוס האירוע.

**אופני ביצוע.** "רק הרכבה"→"הרכבה בלבד", "רק פירוק"→"פירוק בלבד",
"הובלה"→"הובלה בלבד", "עובד מחסן" ו"סידור מחסן"→"מחסן". ערכים שהופיעו
פחות מחמש פעמים נוספו כ-`is_active=false`.

**אידמפוטנטיות.** כל מזהה הוא `uuid5` על נתיב המסמך ב-Firestore, וכל
ה-`insert` הם `on conflict do update`. אפשר לתקן מיפוי ולהריץ שוב.

**טריגרים.** הטעינה מכבה את טריגרי המשתמש על טבלאות היעד. הסיבה המהותית
היא `tasks_recalc_price`, שמחשב מחיר מחדש ללקוח שתמחורו auto (ארקו) ודורס
את המחיר ההיסטורי; לצידו `events_default_tasks` שהיה יוצר משימות כפולות,
ו-`notify_*` שהיו שולחים אלפי התראות. מפתחות זרים ממשיכים להיאכף.

**ארכיון.** `legacy_firestore_docs` (מיגרציה 0152) מחזיקה את 4,922 המסמכים
כפי שהיו. שום קוד מוצר אינו קורא ממנה; היא קיימת כדי ששאלה עתידית תיענה
בלי לחזור ל-Firebase, שייסגר.


## מה נטען בפועל

ההעברה בוצעה ב-2026-09-08. אלה השורות שנכתבו:

| טבלה | שורות |
| --- | --- |
| `events` | 1,709 |
| `tasks` | 3,783 |
| `task_pricing` | 2,921 |
| `task_contractor_terms` | 756 |
| `event_contacts` | 1,264 |
| `event_activity` | 10,567 |
| `event_specs` | 3,478 |
| `event_signatures` | 62 |
| `legacy_firestore_docs` | 4,922 |

ספירת האירועים לפי לקוח ולפי שנה הושוותה למקור ותאמה בכל שבע המשבצות.
מעבר לספירה, `build.mjs` פולט `out/_verify.json` עם md5 של כל שורות
האירועים והמשימות בצורה קנונית; אותו חישוב הורץ מול המסד אחרי הטעינה
והחזיר את אותן שתי חתימות — כלומר כל שדה בכל שורה זהה, ולא רק המספר.

## מה המקור אילץ לשנות

**‏11 מסמכים לא נטענו כאירוע.** ב-`achaotMechir` יש 11 מסמכים עם שדה אחד
בלבד — `name` ובו "בדיקה", "בדיקה300", "סיילספלואו". אין להם תאריך,
ו-`events.event_date` הוא not null. הם נשמרו בארכיון בלבד.

**‏41 מק״טים קיבלו סיומת.** ‏`events_customer_number_uq` הוא unique על
‏(customer_id, event_number), ובמקור 38 מק״טים חוזרים על עצמם אצל אותו
לקוח. אלה אינם שכפולים טכניים אלא הזמנה שבוטלה לצד זו שהתקיימה, או אותו
לקוח סופי בשני תאריכים. המספר נשמר על האירוע החי והשאר קיבלו `/2`, `/3`.

**החתימות ירדו כתמונה ולא כקישור.** ‏`event_signatures.signature_data`
מחייבת `data:image/...;base64`. ‏62 החתימות הורדו מ-Firebase Storage
והוטמעו, ולכן הן ישרדו את סגירת הפרויקט הישן. שאר הקבצים (מפרטים,
תמונות) נשארו כקישור לפי החלטת הלקוח.

**יומן ההודעות התפצל לשניים.** ‏`event_activity` דורשת `field_key`
ו-`field_label` לרשומת `changed`, וטקסט לא ריק ל-`note`. הודעה שאדם כתב
נכנסה כ-`note`, והודעת מערכת כ-`changed` עם שדה `legacy_message` שהטקסט
יושב בערכו החדש — כך "הערות בלבד" במסך ממשיך להראות רק מה שאדם כתב.

## מה נשאר לשיקול המשרד

‏34 אירועים מחזיקים יותר משתי משימות. חלקם עבודה אמיתית (עד חמש משימות
מחסן על אירוע אחד), וחלקם הקמה או פירוק שמופיעים פעמיים — אירוע שהמערכת
הישנה החזיקה עבורו גם תת-קולקציה וגם רשומה ב-`mesimot`. שתיהן נטענו, כי
שתיהן קיימות במקור; המחיקה היא החלטה של מי שמכיר את האירועים.
