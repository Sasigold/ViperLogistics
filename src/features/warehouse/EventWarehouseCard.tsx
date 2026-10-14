import { useQuery } from "@tanstack/react-query";
import { Badge, Card, CardBody, CardHeader } from "../../components/ui";
import { ICON, STROKE, Warehouse } from "../../components/ui/icons";
import { supabase } from "../../lib/supabase";
import { fmtDate, fmtHours, fmtTime } from "../../lib/dates";
import type { WarehouseScheduleRow } from "../../types/domain";
import { KIND_COLOR, KIND_LABEL } from "./warehouseSchedule";

/**
 * משימות לו״ז המחסן של האירוע, לקריאה בדף האירוע (0226). השרת מחזיר רשימה
 * ריקה כשהמודול סגור ללקוח של האירוע או לקורא — ואז הכרטיס אינו מוצג.
 * המפתח מתחיל ב-`events`, כדי שהסנכרון החי ירענן אותו כשההקמה או הפירוק זזים.
 */
export function EventWarehouseCard({ eventId }: { eventId: string }) {
  const { data, isLoading, error } = useQuery({
    queryKey: ["events", "warehouse", eventId],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("warehouse_event_tasks", {
        p_event_id: eventId,
      });
      if (error) throw error;
      return (data ?? []) as WarehouseScheduleRow[];
    },
  });

  // ‏`events_select` כבר הראה את האירוע; כאן תוספת, ולכן טעינה או שגיאה אינן
  // מציגות כרטיס ריק — רק שורות שחזרו.
  if (isLoading || error || !data?.length) return null;

  return (
    <Card>
      <CardHeader
        title="לו״ז מחסן"
        subtitle="הכנת הציוד והחזרתו למחסן"
        icon={<Warehouse size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody>
        <ul className="divide-y divide-line-subtle">
          {data.map((r) => (
            <li
              key={r.kind}
              className="flex flex-wrap items-center gap-x-3 gap-y-1 py-2 first:pt-0 last:pb-0"
            >
              <span
                className="rounded px-2 py-0.5 type-caption font-semibold text-white"
                style={{ backgroundColor: KIND_COLOR[r.kind] }}
              >
                {KIND_LABEL[r.kind]}
              </span>
              <span className="type-body font-medium tabular-nums">
                {fmtDate(r.task_date)}
              </span>
              {r.start_time && (
                <span
                  dir="ltr"
                  className="type-body tabular-nums text-ink-secondary"
                >
                  {fmtTime(r.start_time)}
                </span>
              )}
              {r.duration_hours > 0 && (
                <span className="type-caption text-ink-tertiary">
                  משך{" "}
                  <span dir="ltr" className="tabular-nums">
                    {fmtHours(r.duration_hours)}
                  </span>
                </span>
              )}
              <span className="ms-auto flex flex-wrap gap-1">
                {r.final_approved && <Badge tone="success">אישור סופי</Badge>}
                {r.event_ready && <Badge tone="success">אירוע מוכן</Badge>}
                {r.checked && <Badge tone="info">נבדק</Badge>}
              </span>
              {r.notes && (
                <p className="w-full type-caption text-ink-secondary">
                  {r.notes}
                </p>
              )}
            </li>
          ))}
        </ul>
      </CardBody>
    </Card>
  );
}
