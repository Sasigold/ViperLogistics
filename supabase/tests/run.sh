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
FAILED=$(echo "$OUT" | grep -c '^FAIL' || true)
echo "pass: $(echo "$OUT" | grep -c '^pass')   FAIL: $FAILED"
[ "$FAILED" -eq 0 ]
