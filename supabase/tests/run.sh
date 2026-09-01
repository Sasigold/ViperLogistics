#!/usr/bin/env bash
# Applies every migration to a throwaway PostgreSQL cluster and runs the
# privilege-escalation suite against it. No Supabase project is touched.
#
#   ./supabase/tests/run.sh
#
# Needs a local postgres (`postgresql-16` or newer). The cluster lives under
# /var/tmp/vlpg and is recreated on every run.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BASE=/var/tmp/vlpg
PORT=${VL_TEST_PORT:-55432}
PGBIN=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1 || true)
[ -n "$PGBIN" ] && export PATH="$PGBIN:$PATH"

PSQL="psql -h /var/tmp -p $PORT -U postgres -q"

if ! $PSQL -d postgres -tAc 'select 1' >/dev/null 2>&1; then
  echo "== starting a scratch cluster on port $PORT =="
  rm -rf "$BASE"
  mkdir -p "$BASE/pgdata"
  # postgres refuses to run as root, so the cluster is owned by the postgres user
  chown -R postgres:postgres "$BASE"
  chmod 700 "$BASE/pgdata"
  su postgres -c "PATH=$PGBIN:\$PATH initdb -D $BASE/pgdata -U postgres --auth=trust" >/dev/null
  su postgres -c "PATH=$PGBIN:\$PATH pg_ctl -D $BASE/pgdata -o '-k /var/tmp -p $PORT -c listen_addresses=' -l $BASE/log start" >/dev/null
  sleep 2
fi

$PSQL -v ON_ERROR_STOP=1 -d postgres -c 'drop database if exists vl;' -c 'create database vl;' >/dev/null
$PSQL -v ON_ERROR_STOP=1 -d vl -f "$HERE/00_bootstrap.sql" >/dev/null
$PSQL -d vl -c 'create publication supabase_realtime;' >/dev/null 2>&1 || true

echo "== migrations =="
for f in "$ROOT"/supabase/migrations/*.sql; do
  if ! $PSQL -v ON_ERROR_STOP=1 -d vl -f "$f" >/tmp/vl-mig.log 2>&1; then
    echo "FAILED: $(basename "$f")"; tail -10 /tmp/vl-mig.log; exit 1
  fi
done
echo "all $(ls "$ROOT"/supabase/migrations/*.sql | wc -l) migrations applied"

$PSQL -v ON_ERROR_STOP=1 -d vl -f "$HERE/01_seed.sql" >/dev/null

echo
echo "== privilege-escalation suite =="
OUT=$($PSQL -d vl -f "$HERE/02_escalation.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT"

echo
echo "== pricing suite =="
# 03 seeds rows of its own and must run after 02, which asserts on row counts.
OUT2=$($PSQL -d vl -f "$HERE/03_pricing.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT2"
OUT="$OUT
$OUT2"

echo
echo "== attendance suite =="
# 04 seeds its own people and tasks, and must run last: it moves task dates
# around to exercise the clock's "too early" branch.
OUT3=$($PSQL -d vl -f "$HERE/04_attendance.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT3"
OUT="$OUT
$OUT3"

echo
echo "== dashboard suite =="
# 05 runs last and reads what the earlier suites created: the payroll
# neutrality check compares the report against the function it now sits on,
# and needs attendance rows to exist for that comparison to mean anything.
OUT4=$($PSQL -d vl -f "$HERE/05_dashboard.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT4"
OUT="$OUT
$OUT4"

echo
echo "== report builder suite =="
# 06 runs after 05 and reads everything the earlier suites created: the margin
# neutrality check compares the engine against dashboard_sections, and needs
# priced tasks and approved attendance for that comparison to mean anything.
# It also grants and revokes keys on f1, so nothing after it may assume f1's
# permissions are untouched.
OUT5=$($PSQL -d vl -f "$HERE/06_report_builder.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT5"
OUT="$OUT
$OUT5"

echo
echo "== notifications suite =="
# 07 runs last: it switches notifications.email and notifications.push on, and
# any earlier suite that counts delivery rows would see a different picture.
# It puts both back to off at the end.
OUT6=$($PSQL -d vl -f "$HERE/07_notifications.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT6"
OUT="$OUT
$OUT6"

echo
echo "== events import suite =="
# 08 מקימה לקוח ואנשי צוות משלה ומייבאת אירועים חדשים, ולכן היא רצה אחרי כל
# מי שסופר שורות. היא אינה נשענת על ההרשאות של f1, ש-06 מזיזה.
OUT7=$($PSQL -d vl -f "$HERE/08_import_tasks.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT7"
OUT="$OUT
$OUT7"

echo
echo "== reports page suite =="
# 09 משחק במענקים האישיים של f3 ומחזיר אותם בסופו; הוא רץ אחרון כדי שאף
# בדיקה אחרת לא תראה את f3 באמצע התחפושת.
OUT8=$($PSQL -d vl -f "$HERE/09_reports_page.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT8"
OUT="$OUT
$OUT8"

echo
echo "== task status lifecycle suite =="
# 10 מקימה לקוח, אירוע ואנשים משל עצמה ואינה נשענת על אף חבילה קודמת — 02
# הופכת את f2 לאדמין ו-06 מזיזה מפתחות על f1. היא רצה אחרונה כי היא סופרת
# את קטלוג הסטטוסים כולו, ומשימה שחבילה אחרת תיצור אחריה לא תשנה את הספירה.
OUT9=$($PSQL -d vl -f "$HERE/10_task_status.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT9"
OUT="$OUT
$OUT9"

echo
echo "== default permissions suite =="
# 11 מקימה לקוח, קבלן, אירוע ומשימות משל עצמה ואינה נשענת על אף חבילה קודמת.
# היא רצה אחרונה כי היא מזריעה משימות "משובצות" ואנשי צוות נוספים, ואינה
# מנקה אחריה — כל מי שסופר שורות חייב לרוץ לפניה.
OUT10=$($PSQL -d vl -f "$HERE/11_default_permissions.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT10"
OUT="$OUT
$OUT10"

echo
echo "== income & receipts suite =="
# 12 מקימה לקוח, אירוע ואנשים משלה, והאירוע שלה יושב ב-current_date+210 כדי
# שטווחי הסקשנים שלה לא יתפסו משימות של חבילות אחרות. היא משנה את חלוקת
# הלקוח שלה בלבד ואינה נוגעת ב-f1/f2/f3.
OUT11=$($PSQL -d vl -f "$HERE/12_income_receipts.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT11"
OUT="$OUT
$OUT11"

echo
echo "== task P&L suite =="
# 13 מקימה לקוח, קבלן, אירוע, משימות, עובדים ומשמרות משל עצמה, והן יושבות
# ביום שני שבשבוע current_date+240 כדי ששיעור יום המנוחה לא ייגע במספרים
# ושחבילה אחרת לא תזלוג לטווח. היא רצה אחרונה כי היא סופרת שורות וסכומים
# בטווח שלה, ומוסיפה משימות ומשמרות שאינן מנוקות.
OUT12=$($PSQL -d vl -f "$HERE/13_task_pnl.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT12"
OUT="$OUT
$OUT12"

echo
echo "== contractor shell suite =="
# 14 מקימה שני קבלנים, לקוח, אירוע ומשימות משל עצמה. היא רצה אחרונה כי היא
# מוסיפה שורות סגל ושיבוצים שאינם מנוקים, ובודקת ספירות בהיקף שלה בלבד.
OUT13=$($PSQL -d vl -f "$HERE/14_contractor_shell.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT13"
OUT="$OUT
$OUT13"

echo
echo "== customer spend / dual hat / clock error codes =="
# 15 מקימה לקוח, קבלן, אירוע ומשימה משל עצמה, ובודקת בעיקר *היעדר* מפתחות
# אצל הלקוח. היא רצה אחרונה כי היא מוסיפה שיבוץ ותמחור שאינם מנוקים.
OUT14=$($PSQL -d vl -f "$HERE/15_customer_spend_and_dual_hat.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT14"
OUT="$OUT
$OUT14"

echo
echo "== event specs suite =="
# 16 מקימה לקוח, אירוע ושלושה פרופילים משלה ואינה נשענת על אף חבילה קודמת. היא
# רצה אחרונה כי היא סופרת פוליסות על storage.objects ואת שורות היומן של האירוע
# שלה, ומשאירה אחריה גרסאות מפרט שאינן מנוקות.
OUT15=$($PSQL -d vl -f "$HERE/16_event_specs.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT15"
OUT="$OUT
$OUT15"

echo
echo "== field worker suite =="
# 17 מקימה לקוח, מחסן, אירוע, שני פרופילים ושתי משימות משלה ואינה נשענת על אף
# חבילה קודמת. היא רצה אחרונה כי היא מוסיפה משימות ושיבוצים שאינם מנוקים,
# והמשמרות שלה יושבות ב-current_date+320 כדי שלא ייתפסו בטווח של אף חבילה.
OUT16=$($PSQL -d vl -f "$HERE/17_worker_view.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT16"
OUT="$OUT
$OUT16"

echo
echo "== team scope suite =="
# 18 מקימה לקוח, אירוע, ארבעה פרופילים ושלוש משימות משלה ואינה נשענת על אף
# חבילה קודמת. היא רצה אחרונה כי היא סופרת את משימות האירוע שלה, ומשאירה
# אחריה משימות ושיבוצים שאינם מנוקים. האירוע יושב ב-current_date+330.
OUT17=$($PSQL -d vl -f "$HERE/18_team_scope.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT17"
OUT="$OUT
$OUT17"

echo
echo "== fleet suite =="
# 19 מקימה משאית, שני רכבים וחמישה פרופילים משלה ואינה נשענת על אף חבילה
# קודמת. היא רצה אחרונה כי היא סופרת פוליסות על storage.objects, כותבת
# התראות, ומשאירה אחריה רכבים ומסמכים שאינם מנוקים. תאריכי הפקיעה שלה
# נגזרים מ-current_date, כי כל הבדיקה היא על היחס ליום הנוכחי.
OUT18=$($PSQL -d vl -f "$HERE/19_vehicles.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT18"
OUT="$OUT
$OUT18"

echo
echo "== realtime sync suite =="
# 20 מקימה לקוח, קבלן, אירוע ושישה פרופילים משלה ואינה נשענת על אף חבילה
# קודמת. היא מרוקנת את realtime.messages בין תרחישים — אף חבילה אחרת אינה
# קוראת את הטבלה — והאירוע שלה יושב ב-current_date+340, מעבר לכל טווח אחר.
OUT19=$($PSQL -d vl -f "$HERE/20_realtime_sync.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT19"
OUT="$OUT
$OUT19"

echo
echo "== event signature suite =="
# 21 מקימה לקוח, אירוע ושש דמויות משלה ואינה נשענת על אף חבילה קודמת. היא רצה
# אחרונה כי היא מזריעה משימות, שיבוצים וחתימות שאינם מנוקים, וסופרת את שורות
# היומן של האירוע שלה. האירוע יושב ב-current_date+350, מעבר לכל טווח אחר.
OUT20=$($PSQL -d vl -f "$HERE/21_event_signature.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT20"
OUT="$OUT
$OUT20"

echo
echo "== contractor hats & penalties suite =="
# 22 מקימה קבלן, לקוח, אירוע, משימות ושלוש דמויות משלה ואינה נשענת על אף חבילה
# קודמת. היא רצה אחרונה כי היא מזריעה שיבוצים ותמחור שאינם מנוקים, והאירוע שלה
# יושב ב-current_date+360, מעבר לכל טווח אחר.
OUT21=$($PSQL -d vl -f "$HERE/22_contractor_hats_and_penalties.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT21"
OUT="$OUT
$OUT21"

echo
echo "== customer board & approval suite =="
# 23 מקימה שני לקוחות, אירועים, משימות וארבע דמויות משלה ואינה נשענת על אף
# חבילה קודמת. היא רצה אחרונה כי היא מזריעה תמחור וקונפיגורציית שדות שאינם
# מנוקים, והאירועים שלה יושבים ב-current_date+370.
OUT23=$($PSQL -d vl -f "$HERE/23_customer_board_and_approval.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT23"
OUT="$OUT
$OUT23"

echo
echo "== office defaults suite =="
# 24 מקימה לקוח, קבלן, אופני ביצוע ואירוע משלה. היא רצה אחרונה כי היא מזריעה
# אופני ביצוע גלובליים ומסתירה שדה טופס, ושניהם אינם מנוקים אחריה.
OUT24=$($PSQL -d vl -f "$HERE/24_office_defaults.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT24"
OUT="$OUT
$OUT24"

echo
echo "== price add-ons suite =="
# 25 מקימה לקוח, קבלן, אירוע, משימות וארבע דמויות משלה. היא רצה אחרונה כי היא
# סופרת את שורות היומן של האירוע שלה ומשאירה אחריה תוספות שאינן מנוקות.
# האירוע שלה יושב ב-current_date+410.
OUT25=$($PSQL -d vl -f "$HERE/25_price_addons.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT25"
OUT="$OUT
$OUT25"

echo
echo "== cancelled events and price add-ons suite =="
# 26 מקימה לקוח, שלושה אירועים ומשימות משלה, והאירועים שלה יושבים ב-
# current_date+420 — מעבר לכל טווח קודם, כדי שכל מספר בה יהיה של השורות שלה
# בלבד. היא רצה אחרונה כי היא מזריעה תוספות מחיר שאינן מנוקות אחריה.
OUT26=$($PSQL -d vl -f "$HERE/26_cancelled_and_addons.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT26"
OUT="$OUT
$OUT26"

echo
echo "== customer trucks and status suite =="
# 27 מקימה לקוח, אירוע, משאיות ומשימות משלה, ב-current_date+430. היא רצה
# אחרונה כי היא פותחת שדות לו״ז ללקוח שלה ומזריעה משאיות גלובליות שאינן
# מנוקות אחריה.
OUT27=$($PSQL -d vl -f "$HERE/27_customer_trucks_and_status.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT27"
OUT="$OUT
$OUT27"

echo
echo "== transport-only pricing suite =="
# 28 מקימה לקוח, אופני ביצוע, מחשבון ומשימות משלה ב-current_date+440. היא רצה
# אחרונה כי היא מזריעה אופני ביצוע גלובליים ומחשבון שאינם מנוקים אחריה.
OUT28=$($PSQL -d vl -f "$HERE/28_transport_only_pricing.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT28"
OUT="$OUT
$OUT28"

echo
echo "== performed-by (arko) suite =="
# 29 מקימה לקוח ארקו, אירוע ומשימות משלה ב-current_date+450. היא רצה אחרונה
# כי משימות ארקו מוסתרות מוייפר ב-RLS, וכל ספירה שלה היא של השורות שלה בלבד.
OUT29=$($PSQL -d vl -f "$HERE/29_performed_by_arko.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT29"
OUT="$OUT
$OUT29"

echo
echo "== event notes visibility suite =="
# 30 מקימה לקוח, אירוע וארבע דמויות משלה ב-current_date+460, ובודקת מי רואה
# מלל חופשי ומי רק רשומות מערכת.
OUT30=$($PSQL -d vl -f "$HERE/30_event_notes_visibility.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT30"
OUT="$OUT
$OUT30"

echo
echo "== recycle / status-approval suite =="
# 31 מקימה לקוח, אירוע ומשימות משלה ב-current_date+470: אירוע שנמחק יורד
# מהלו״ז, ביטול יורד במחיקה, מחיקה לצמיתות, ושינוי סטטוס אינו מפיל אישור.
OUT31=$($PSQL -d vl -f "$HERE/31_recycle_and_status_approval.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT31"
OUT="$OUT
$OUT31"

echo
echo "== contractor worker roles suite =="
# 32 מקימה קבלן, לקוח, אירוע ומשימה משלה ב-current_date+480, ובודקת הגדרת
# תפקידי עובד קבלן ושיבוץ לפיהם.
OUT32=$($PSQL -d vl -f "$HERE/32_contractor_worker_roles.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT32"
OUT="$OUT
$OUT32"

echo
echo "== customer own staff suite =="
# 33 מקימה שני לקוחות, אירוע, סגל עובדים ושלוש דמויות משלה ב-current_date+490.
# היא רצה אחרונה כי היא מזריעה סגל ושיבוצים שאינם מנוקים, ומשנה את משימת
# ההקמה של האירוע שלה ל"בוצע ע"י ארקו".
OUT33=$($PSQL -d vl -f "$HERE/33_customer_own_staff.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT33"
OUT="$OUT
$OUT33"

echo
echo "== customer monthly / locked dashboard suite =="
# 34 מקימה שני לקוחות משלה ב-current_date+500 — אחד עם עמלה ואחד בלי — ובודקת
# את הסיכום החודשי, את הסף החמור, ואת הדשבורד שנסגר ללקוח.
OUT34=$($PSQL -d vl -f "$HERE/34_customer_monthly_and_locked_dashboard.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT34"
OUT="$OUT
$OUT34"

echo
echo "== group payment / supplier pickup suite =="
# 35 מקימה לקוח, שני קבלנים, ספקים ושני אירועים משלה ב-current_date+500. היא
# רצה אחרי 34, שחולקת איתה את החלון: שורות 35 אינן קיימות בזמן שהיא נמדדת.
# תשלום לקבוצה שלמה (0146), ואיסוף מספקים על הלו״ז (0147).
OUT35=$($PSQL -d vl -f "$HERE/35_group_payment_and_supplier_pickup.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT35"
OUT="$OUT
$OUT35"

echo
echo "== contractor pool & event door suite =="
# 36 מקימה לקוח, קבלן, אירוע ושלוש דמויות משלה ב-current_date+520, מעבר לכל
# טווח אחר. היא משאירה אחריה שורת סגל מגושרת ושיבוצים שאינם מנוקים.
OUT36=$($PSQL -d vl -f "$HERE/36_contractor_pool_and_event_door.sql" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v '^$')
echo "$OUT36"
OUT="$OUT
$OUT36"

echo
FAILED=$(echo "$OUT" | grep -c '^FAIL' || true)
echo "pass: $(echo "$OUT" | grep -c '^pass')   FAIL: $FAILED"
[ "$FAILED" -eq 0 ]
