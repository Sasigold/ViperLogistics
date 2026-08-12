import { autoBucket } from './reportState'
import { defaultRange } from '../dashboard/dashboardRange'
import type { DimChoice, ReportState } from './reportState'
import type { Agg } from '../dashboard/builder/widgetSpec'

/**
 * The canned reports — a curated entry point, not a second engine.
 *
 * Every template is nothing but a `ReportState` preset over catalogue keys
 * that migration 0043 seeds; after picking one, every control on the screen
 * stays live. The test file holds each template against the catalogue
 * vocabulary, so a migration that renames a key fails CI here instead of
 * rendering a broken panel.
 *
 * Deliberately NOT filtered by permission on the client: the catalogue
 * carries no permission columns and the client never derives one (the
 * `useReportCatalog` rule). A denied run renders a quiet notice and
 * contributes nothing to the export — the server's answer, per reader.
 */

export type ReportDomain = 'ops' | 'events' | 'finance' | 'margin' | 'attendance' | 'payroll'

export const DOMAIN_LABELS: Record<ReportDomain, string> = {
  ops: 'תפעול',
  events: 'אירועים',
  finance: 'כספים',
  margin: 'רווחיות',
  attendance: 'נוכחות',
  payroll: 'שכר',
}

export const DOMAIN_ORDER: ReportDomain[] = ['ops', 'events', 'finance', 'margin', 'attendance', 'payroll']

export interface ReportTemplate {
  key: string
  domain: ReportDomain
  title: string
  hint?: string
  source: string
  measure: string
  agg: Agg
  /** empty = a single un-broken-down number (measures that allow `__none__`) */
  dims: DimChoice[]
}

export const REPORT_TEMPLATES: ReportTemplate[] = [
  /* ── תפעול ─────────────────────────────────────────────────────────── */
  {
    key: 'ops.by_customer',
    domain: 'ops',
    title: 'משימות לפי לקוח',
    source: 'tasks',
    measure: 'tasks.count',
    agg: 'count_distinct',
    dims: [{ field: 'tasks.customer' }, { field: 'tasks.date' }],
  },
  {
    key: 'ops.by_type',
    domain: 'ops',
    title: 'משימות לפי סוג',
    source: 'tasks',
    measure: 'tasks.count',
    agg: 'count_distinct',
    dims: [{ field: 'tasks.type', viz: 'donut' }],
  },
  {
    key: 'ops.by_status',
    domain: 'ops',
    title: 'משימות לפי סטטוס',
    source: 'tasks',
    measure: 'tasks.count',
    agg: 'count_distinct',
    dims: [{ field: 'tasks.status', viz: 'donut' }],
  },
  {
    key: 'ops.by_method',
    domain: 'ops',
    title: 'משימות לפי אופן ביצוע',
    source: 'tasks',
    measure: 'tasks.count',
    agg: 'count_distinct',
    dims: [{ field: 'tasks.method' }],
  },
  {
    key: 'ops.by_truck',
    domain: 'ops',
    title: 'משימות לפי משאית',
    hint: 'משימה רב-משאיתית נספרת לכל משאית — סכום השורות גדול ממספר המשימות',
    source: 'tasks',
    measure: 'tasks.count',
    agg: 'count_distinct',
    dims: [{ field: 'tasks.truck' }],
  },
  {
    key: 'ops.hours_by_customer',
    domain: 'ops',
    title: 'שעות משימה לפי לקוח',
    source: 'tasks',
    measure: 'tasks.hours',
    agg: 'sum',
    dims: [{ field: 'tasks.customer' }, { field: 'tasks.date' }],
  },
  {
    key: 'ops.workers_over_time',
    domain: 'ops',
    title: 'עובדים נדרשים לאורך זמן',
    source: 'tasks',
    measure: 'tasks.workers_needed',
    agg: 'sum',
    dims: [{ field: 'tasks.date' }],
  },

  /* ── אירועים ───────────────────────────────────────────────────────── */
  {
    key: 'events.by_customer',
    domain: 'events',
    title: 'אירועים לפי לקוח',
    source: 'events',
    measure: 'events.count',
    agg: 'count_distinct',
    dims: [{ field: 'events.customer' }, { field: 'events.date' }],
  },
  {
    key: 'events.by_status',
    domain: 'events',
    title: 'אירועים לפי סטטוס',
    source: 'events',
    measure: 'events.count',
    agg: 'count_distinct',
    dims: [{ field: 'events.status', viz: 'donut' }],
  },
  {
    key: 'events.volume',
    domain: 'events',
    title: 'נפח מטען',
    source: 'events',
    measure: 'events.volume',
    agg: 'sum',
    dims: [{ field: 'events.date' }, { field: 'events.customer' }],
  },
  {
    key: 'events.trucks',
    domain: 'events',
    title: 'משאיות נדרשות לפי לקוח',
    source: 'events',
    measure: 'events.trucks',
    agg: 'sum',
    dims: [{ field: 'events.customer' }],
  },

  /* ── כספים ─────────────────────────────────────────────────────────── */
  {
    key: 'finance.revenue_breakdown',
    domain: 'finance',
    title: 'הכנסות — פילוח מלא',
    hint: 'לפי לקוח, לאורך זמן ולפי סוג משימה, זה לצד זה',
    source: 'tasks',
    measure: 'revenue',
    agg: 'sum',
    dims: [{ field: 'tasks.customer' }, { field: 'tasks.date' }, { field: 'tasks.type' }],
  },
  {
    key: 'finance.revenue_trend',
    domain: 'finance',
    title: 'הכנסות לאורך זמן',
    source: 'tasks',
    measure: 'revenue',
    agg: 'sum',
    dims: [{ field: 'tasks.date' }],
  },
  {
    key: 'finance.contractor_cost',
    domain: 'finance',
    title: 'עלות קבלנים לפי קבלן',
    hint: 'הסכום המחויב מול קבלנים בטווח',
    source: 'tasks',
    measure: 'contractor_cost',
    agg: 'sum',
    dims: [{ field: 'tasks.contractor' }, { field: 'tasks.date' }],
  },
  {
    key: 'finance.contractor_paid',
    domain: 'finance',
    title: 'ששולם לקבלנים',
    hint: 'רק שורות שסומנו כשולמו',
    source: 'tasks',
    measure: 'contractor_paid',
    agg: 'sum',
    dims: [{ field: 'tasks.contractor' }],
  },

  /* ── רווחיות ───────────────────────────────────────────────────────── */
  {
    key: 'margin.trend',
    domain: 'margin',
    title: 'רווח גולמי לאורך זמן',
    hint: 'הכנסות פחות עלות קבלנים ועלות שכר. אינו כולל תקורה',
    source: 'payroll',
    measure: 'margin.gross',
    agg: 'sum',
    dims: [{ field: 'payroll.date' }],
  },
  {
    key: 'margin.pct',
    domain: 'margin',
    title: 'שיעור רווח גולמי',
    source: 'payroll',
    measure: 'margin.pct',
    agg: 'sum',
    dims: [{ field: 'payroll.date' }],
  },
  {
    key: 'margin.by_customer',
    domain: 'margin',
    title: 'רווח לפי לקוח (משוער)',
    hint: 'עלות השכר מחולקת בין המשימות לפי שעות — הקצאה משוערת',
    source: 'payroll',
    measure: 'margin.gross',
    agg: 'sum',
    dims: [{ field: 'payroll.customer' }],
  },

  /* ── נוכחות ────────────────────────────────────────────────────────── */
  {
    key: 'hr.hours',
    domain: 'attendance',
    title: 'שעות עבודה לפי עובד',
    hint: 'משמרות מאושרות בלבד',
    source: 'attendance',
    measure: 'attendance.hours',
    agg: 'sum',
    dims: [{ field: 'attendance.worker' }, { field: 'attendance.date' }],
  },
  {
    key: 'hr.by_site',
    domain: 'attendance',
    title: 'משמרות לפי אתר עבודה',
    source: 'attendance',
    measure: 'attendance.shifts',
    agg: 'count_distinct',
    dims: [{ field: 'attendance.work_site' }],
  },
  {
    key: 'hr.by_source',
    domain: 'attendance',
    title: 'מקור הדיווח',
    hint: 'שעון מול דיווח ידני',
    source: 'attendance',
    measure: 'attendance.shifts',
    agg: 'count_distinct',
    dims: [{ field: 'attendance.source', viz: 'donut' }],
  },
  {
    key: 'hr.active_workers',
    domain: 'attendance',
    title: 'עובדים פעילים לאורך זמן',
    source: 'attendance',
    measure: 'attendance.workers',
    agg: 'count_distinct',
    dims: [{ field: 'attendance.date' }],
  },

  /* ── שכר ───────────────────────────────────────────────────────────── */
  {
    key: 'payroll.trend',
    domain: 'payroll',
    title: 'עלות שכר לאורך זמן',
    hint: 'מהנוכחות המאושרת בלבד',
    source: 'payroll',
    measure: 'payroll.total',
    agg: 'sum',
    dims: [{ field: 'payroll.date' }],
  },
  {
    key: 'payroll.by_worker',
    domain: 'payroll',
    title: 'עלות שכר לפי עובד',
    source: 'payroll',
    measure: 'payroll.total',
    agg: 'sum',
    dims: [{ field: 'payroll.worker' }],
  },
  {
    key: 'payroll.hours_by_worker',
    domain: 'payroll',
    title: 'שעות בתשלום לפי עובד',
    source: 'payroll',
    measure: 'payroll.paid_hours',
    agg: 'sum',
    dims: [{ field: 'payroll.worker' }],
  },
  /* המנוע מגיש שעות נוספות ובונוסים כמספר אחד בלבד (allowed_dims =
     '{__none__}' ב-0043) — ולכן אלה תבניות של מספר יחיד, לא של פילוח. */
  {
    key: 'payroll.overtime',
    domain: 'payroll',
    title: 'שעות נוספות',
    source: 'payroll',
    measure: 'payroll.overtime_hours',
    agg: 'sum',
    dims: [],
  },
  {
    key: 'payroll.bonus',
    domain: 'payroll',
    title: 'בונוסים',
    source: 'payroll',
    measure: 'payroll.bonus',
    agg: 'sum',
    dims: [],
  },
]

export function templatesByDomain(domain: ReportDomain): ReportTemplate[] {
  return REPORT_TEMPLATES.filter((t) => t.domain === domain)
}

/** the preset, opened on the screen's current range (or a fresh default) */
export function stateFromTemplate(t: ReportTemplate, range = defaultRange()): ReportState {
  return {
    v: 1,
    source: t.source,
    measure: t.measure,
    agg: t.agg,
    filters: [],
    dims: t.dims.map((d) => ({ ...d })),
    bucket: autoBucket(range),
    compare: false,
    range,
  }
}
