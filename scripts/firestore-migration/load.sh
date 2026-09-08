#!/usr/bin/env bash
# טוען את ה-SQL שנבנה ב-build.mjs, בטרנזקציה אחת ובלי טריגרים.
#
#   DATABASE_URL='postgresql://...' ./load.sh <outDir>
#
# ‏**למה בלי טריגרים.** על `events` יושב `events_default_tasks` שיוצר משימות
# ברירת מחדל — הייבוא מביא את המשימות האמיתיות ולא צריך אותן; על `tasks`
# יושב `tasks_recalc_price` שמחשב מחיר מחדש ללקוח שתמחורו auto (ארקו),
# ‏**ודורס את המחיר ההיסטורי** שהובא מהמערכת הישנה; ועל שניהם יושבים
# ‏`notify_*` שהיו שולחים אלפי התראות על אירועים מ-2023. ‏`disable trigger
# user` אינו נוגע בטריגרים הפנימיים של המפתחות הזרים, ולכן שגיאת מיפוי
# עדיין נתפסת — וזו הסיבה שלא נעשה כאן שימוש ב-session_replication_role,
# שהיה מכבה גם אותם.
#
# הכול בטרנזקציה אחת: `alter table ... disable trigger` הוא טרנזקציוני
# בפוסטגרס, ולכן כישלון באמצע מחזיר את הטריגרים למקומם מעצמו.
set -euo pipefail
OUT="${1:-out}"
: "${DATABASE_URL:?צריך DATABASE_URL}"

TABLES=(events event_contacts tasks task_pricing task_contractor_terms event_activity event_specs event_signatures)
# הסדר מחייב: אירועים לפני משימות, משימות לפני מחירים, והארכיון אחרון —
# הוא מצביע על שניהם.
FILES=(events.sql event_contacts.sql tasks.sql task_pricing.sql task_contractor_terms.sql \
       event_activity.sql event_specs.sql event_signatures.sql legacy_firestore_docs.sql)

{
  echo "begin;"
  echo "set local statement_timeout = 0;"
  for t in "${TABLES[@]}"; do echo "alter table $t disable trigger user;"; done
  for f in "${FILES[@]}"; do
    [ -f "$OUT/$f" ] || { echo "\\echo 'דילוג: $f'" ; continue; }
    echo "\\echo '== $f'"
    cat "$OUT/$f"
  done
  for t in "${TABLES[@]}"; do echo "alter table $t enable trigger user;"; done
  echo "commit;"
} | psql "$DATABASE_URL" --single-transaction=off -v ON_ERROR_STOP=1 -q -f -

echo "נטען. בדיקת ספירות:"
psql "$DATABASE_URL" -q -c "
select 'events' t, count(*) n from events
union all select 'tasks', count(*) from tasks
union all select 'task_pricing', count(*) from task_pricing
union all select 'task_contractor_terms', count(*) from task_contractor_terms
union all select 'event_contacts', count(*) from event_contacts
union all select 'event_activity', count(*) from event_activity
union all select 'event_specs', count(*) from event_specs
union all select 'event_signatures', count(*) from event_signatures
union all select 'legacy_firestore_docs', count(*) from legacy_firestore_docs
order by 1;"
