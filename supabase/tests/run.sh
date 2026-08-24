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
FAILED=$(echo "$OUT" | grep -c '^FAIL' || true)
echo "pass: $(echo "$OUT" | grep -c '^pass')   FAIL: $FAILED"
[ "$FAILED" -eq 0 ]
