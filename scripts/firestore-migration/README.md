# העברת הנתונים מ-Firestore

העברה חד-פעמית של פרויקט Firebase‏ `nihol-mishmarot` למסד של ViperLogistics.
שלוש קולקציות אירועים, ארבע קולקציות משימות, 1,720 אירועים ו-3,783 משימות.

## הרצה

```bash
node fetch.mjs   ./dump                    # שאיבה מ-Firestore
node build.mjs   ./dump catalog.json ./out # המרה ל-SQL (לא נוגע במסד)
DATABASE_URL='postgresql://...' ./load.sh ./out
```

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
