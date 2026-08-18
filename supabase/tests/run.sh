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

# ── the suite runner ────────────────────────────────────────────────────────
# ON_ERROR_STOP matters here as much as it does on the migrations above, and
# for a subtler reason. The verdict at the bottom is a grep for '^FAIL', and a
# suite that dies on a real SQL error — a renamed column, a dropped function —
# prints ERROR, *carries on to the next statement*, and exits 0. The assertions
# that would have printed FAIL never run, so they print nothing, the grep finds
# nothing, and CI goes green on a suite that stopped testing. Failing loudly on
# the first unexpected error is the only way the green means anything.
#
# Expected failures do not trip this: t_expect_fail/t_expect_ok (01_seed.sql)
# trap the exception inside plpgsql, so psql never sees an error for a statement
# that was *supposed* to be refused.
SUITE_OUT=$(mktemp)
trap 'rm -f "$SUITE_OUT"' EXIT

run_suite() {
  local file="$1" raw rc filtered
  raw=$(mktemp)
  set +e
  $PSQL -v ON_ERROR_STOP=1 -d vl -f "$HERE/$file" >"$raw" 2>&1
  rc=$?
  set -e
  filtered=$(grep -v '^[0-9a-f-]\{36\}$' "$raw" | grep -v '^$' || true)
  echo "$filtered"
  printf '%s\n' "$filtered" >>"$SUITE_OUT"
  if [ "$rc" -ne 0 ]; then
    echo
    echo "ABORTED: $file stopped on a SQL error (psql exit $rc)."
    echo "Everything after that point never ran, so a pass count here would be a lie."
    tail -20 "$raw" | sed 's/^/    /'
    rm -f "$raw"
    exit 1
  fi
  rm -f "$raw"
}

echo
echo "== privilege-escalation suite =="
run_suite 02_escalation.sql

echo
echo "== pricing suite =="
# 03 seeds rows of its own and must run after 02, which asserts on row counts.
run_suite 03_pricing.sql

echo
echo "== attendance suite =="
# 04 seeds its own people and tasks, and must run last: it moves task dates
# around to exercise the clock's "too early" branch.
run_suite 04_attendance.sql

echo
echo "== dashboard suite =="
# 05 runs last and reads what the earlier suites created: the payroll
# neutrality check compares the report against the function it now sits on,
# and needs attendance rows to exist for that comparison to mean anything.
run_suite 05_dashboard.sql

echo
echo "== report builder suite =="
# 06 runs after 05 and reads everything the earlier suites created: the margin
# neutrality check compares the engine against dashboard_sections, and needs
# priced tasks and approved attendance for that comparison to mean anything.
# It also grants and revokes keys on f1, so nothing after it may assume f1's
# permissions are untouched.
run_suite 06_report_builder.sql

echo
echo "== notifications suite =="
# 07 runs last: it switches notifications.email and notifications.push on, and
# any earlier suite that counts delivery rows would see a different picture.
# It puts both back to off at the end.
run_suite 07_notifications.sql

echo
echo "== events import suite =="
# 08 מקימה לקוח ואנשי צוות משלה ומייבאת אירועים חדשים, ולכן היא רצה אחרי כל
# מי שסופר שורות. היא אינה נשענת על ההרשאות של f1, ש-06 מזיזה.
run_suite 08_import_tasks.sql

echo
echo "== reports page suite =="
# 09 משחק במענקים האישיים של f3 ומחזיר אותם בסופו; הוא רץ אחרון כדי שאף
# בדיקה אחרת לא תראה את f3 באמצע התחפושת.
run_suite 09_reports_page.sql

echo
echo "== task status lifecycle suite =="
# 10 מקימה לקוח, אירוע ואנשים משל עצמה ואינה נשענת על אף חבילה קודמת — 02
# הופכת את f2 לאדמין ו-06 מזיזה מפתחות על f1. היא רצה אחרונה כי היא סופרת
# את קטלוג הסטטוסים כולו, ומשימה שחבילה אחרת תיצור אחריה לא תשנה את הספירה.
run_suite 10_task_status.sql

echo
echo "== default permissions suite =="
# 11 מקימה לקוח, קבלן, אירוע ומשימות משל עצמה ואינה נשענת על אף חבילה קודמת.
# היא רצה אחרונה כי היא מזריעה משימות "משובצות" ואנשי צוות נוספים, ואינה
# מנקה אחריה — כל מי שסופר שורות חייב לרוץ לפניה.
run_suite 11_default_permissions.sql

echo
echo "== income & receipts suite =="
# 12 מקימה לקוח, אירוע ואנשים משלה, והאירוע שלה יושב ב-current_date+210 כדי
# שטווחי הסקשנים שלה לא יתפסו משימות של חבילות אחרות. היא משנה את חלוקת
# הלקוח שלה בלבד ואינה נוגעת ב-f1/f2/f3.
run_suite 12_income_receipts.sql

echo
echo "== task P&L suite =="
# 13 מקימה לקוח, קבלן, אירוע, משימות, עובדים ומשמרות משל עצמה, והן יושבות
# ביום שני שבשבוע current_date+240 כדי ששיעור יום המנוחה לא ייגע במספרים
# ושחבילה אחרת לא תזלוג לטווח. היא רצה אחרונה כי היא סופרת שורות וסכומים
# בטווח שלה, ומוסיפה משימות ומשמרות שאינן מנוקות.
run_suite 13_task_pnl.sql

echo
echo "== contractor shell suite =="
# 14 מקימה שני קבלנים, לקוח, אירוע ומשימות משל עצמה. היא רצה אחרונה כי היא
# מוסיפה שורות סגל ושיבוצים שאינם מנוקים, ובודקת ספירות בהיקף שלה בלבד.
run_suite 14_contractor_shell.sql

echo
echo "== customer spend / dual hat / clock error codes =="
# 15 מקימה לקוח, קבלן, אירוע ומשימה משל עצמה, ובודקת בעיקר *היעדר* מפתחות
# אצל הלקוח. היא רצה אחרונה כי היא מוסיפה שיבוץ ותמחור שאינם מנוקים.
run_suite 15_customer_spend_and_dual_hat.sql

echo
PASSED=$(grep -c '^pass' "$SUITE_OUT" || true)
FAILED=$(grep -c '^FAIL' "$SUITE_OUT" || true)
echo "pass: $PASSED   FAIL: $FAILED"
[ "$FAILED" -eq 0 ] || exit 1

# A floor under the pass count. Without one, a suite that quietly shrinks from
# 200 assertions to 3 is indistinguishable from one at full strength — every
# number the run prints would still be green. Raise it when the suite grows;
# that edit is the point, because it makes shrinkage a deliberate act.
: "${VL_MIN_PASS:=880}"
if [ "$PASSED" -lt "$VL_MIN_PASS" ]; then
  echo "FAILED: only $PASSED assertions ran, expected at least $VL_MIN_PASS."
  echo "Either a suite stopped early, or the floor needs updating on purpose."
  exit 1
fi
