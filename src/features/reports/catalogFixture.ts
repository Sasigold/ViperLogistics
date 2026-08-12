import type { Catalog, CatalogField, CatalogMeasure } from '../dashboard/builder/widgetSpec'

/**
 * A test-only mirror of the catalogue migration 0043 seeds — the keys, the
 * allowed aggregates, the allowed dimensions, the fan-out flags.
 *
 * This file exists for exactly one reason: `reportTemplates.test.ts` holds
 * every canned report against it, so a migration that renames or retires a
 * catalogue key breaks CI here instead of rendering a broken panel. When 0043
 * (or a successor) changes the catalogue, change this file in the same
 * commit — the test failing is the reminder.
 *
 * Production code must never import this: the real catalogue is served by
 * `useReportCatalog`, and a runtime mirror is a thing that drifts.
 */

const measure = (over: Partial<CatalogMeasure> & { key: string; source_key: string }): CatalogMeasure => ({
  label_he: over.key,
  hint_he: null,
  allowed_aggs: ['sum'],
  default_agg: over.allowed_aggs?.[0] ?? 'sum',
  unit: 'count',
  is_estimate: false,
  fanout_safe: false,
  allowed_dims: null,
  sort_order: 10,
  ...over,
})

const field = (over: Partial<CatalogField> & { key: string; source_key: string }): CatalogField => ({
  label_he: over.key,
  kind: 'cat',
  col_type: 'uuid',
  fans_out: false,
  nullable: true,
  is_estimate: false,
  can_group: true,
  can_filter: true,
  allowed_ops: ['eq', 'ne', 'in', 'not_in'],
  sort_order: 10,
  ...over,
})

export const CATALOG_0043: Catalog = {
  sources: [
    { key: 'tasks', label_he: 'משימות', row_noun_he: 'משימות', scope_note_he: null, sort_order: 10 },
    { key: 'events', label_he: 'אירועים', row_noun_he: 'אירועים', scope_note_he: null, sort_order: 20 },
    { key: 'attendance', label_he: 'נוכחות', row_noun_he: 'משמרות', scope_note_he: 'משמרות מאושרות בלבד', sort_order: 30 },
    { key: 'payroll', label_he: 'שכר ורווחיות', row_noun_he: 'משמרות', scope_note_he: null, sort_order: 40 },
  ],
  measures: [
    measure({ key: 'tasks.count', source_key: 'tasks', allowed_aggs: ['count_distinct'], fanout_safe: true }),
    measure({ key: 'tasks.hours', source_key: 'tasks', allowed_aggs: ['sum', 'avg', 'max'], unit: 'hours' }),
    measure({ key: 'tasks.workers_needed', source_key: 'tasks', allowed_aggs: ['sum', 'avg', 'max'] }),
    measure({ key: 'revenue', source_key: 'tasks', allowed_aggs: ['sum', 'avg', 'max'], unit: 'money' }),
    measure({ key: 'contractor_cost', source_key: 'tasks', allowed_aggs: ['sum', 'avg'], unit: 'money' }),
    measure({ key: 'contractor_paid', source_key: 'tasks', allowed_aggs: ['sum'], unit: 'money' }),
    measure({ key: 'events.count', source_key: 'events', allowed_aggs: ['count_distinct'], fanout_safe: true }),
    measure({ key: 'events.volume', source_key: 'events', allowed_aggs: ['sum', 'avg', 'max'], unit: 'volume', fanout_safe: true }),
    measure({ key: 'events.trucks', source_key: 'events', allowed_aggs: ['sum', 'avg', 'max'], fanout_safe: true }),
    measure({ key: 'attendance.hours', source_key: 'attendance', allowed_aggs: ['sum', 'avg', 'max'], unit: 'hours', fanout_safe: true }),
    measure({ key: 'attendance.shifts', source_key: 'attendance', allowed_aggs: ['count_distinct'], fanout_safe: true }),
    measure({ key: 'attendance.workers', source_key: 'attendance', allowed_aggs: ['count_distinct'], fanout_safe: true }),
    measure({
      key: 'payroll.total', source_key: 'payroll', unit: 'money', fanout_safe: true,
      allowed_dims: ['__none__', 'payroll.date', 'payroll.worker', 'payroll.customer'],
    }),
    measure({
      key: 'payroll.paid_hours', source_key: 'payroll', unit: 'hours', fanout_safe: true,
      allowed_dims: ['__none__', 'payroll.date', 'payroll.worker'],
    }),
    measure({ key: 'payroll.overtime_hours', source_key: 'payroll', unit: 'hours', fanout_safe: true, allowed_dims: ['__none__'] }),
    measure({ key: 'payroll.bonus', source_key: 'payroll', unit: 'money', fanout_safe: true, allowed_dims: ['__none__'] }),
    measure({ key: 'payroll.shifts', source_key: 'payroll', fanout_safe: true, allowed_dims: ['__none__'] }),
    measure({
      key: 'margin.gross', source_key: 'payroll', unit: 'money', fanout_safe: true,
      allowed_dims: ['__none__', 'payroll.date', 'payroll.customer'],
    }),
    measure({
      key: 'margin.pct', source_key: 'payroll', unit: 'percent', fanout_safe: true,
      allowed_dims: ['__none__', 'payroll.date'],
    }),
  ],
  fields: [
    field({ key: 'tasks.date', source_key: 'tasks', kind: 'time', col_type: 'date', nullable: false, allowed_ops: ['gte', 'lte', 'between'] }),
    field({ key: 'tasks.customer', source_key: 'tasks', allowed_ops: ['eq', 'ne', 'in', 'not_in', 'is_null', 'is_not_null'] }),
    field({ key: 'tasks.status', source_key: 'tasks' }),
    field({ key: 'tasks.type', source_key: 'tasks' }),
    field({ key: 'tasks.method', source_key: 'tasks' }),
    field({ key: 'tasks.truck', source_key: 'tasks', fans_out: true, can_filter: false, allowed_ops: [] }),
    field({ key: 'tasks.contractor', source_key: 'tasks', allowed_ops: ['eq', 'ne', 'in', 'not_in', 'is_null', 'is_not_null'] }),
    field({ key: 'tasks.hours_count', source_key: 'tasks', kind: 'num', col_type: 'numeric', can_group: false, allowed_ops: ['gt', 'gte', 'lt', 'lte', 'between', 'is_null', 'is_not_null'] }),
    field({ key: 'tasks.worker_count', source_key: 'tasks', kind: 'num', col_type: 'int', nullable: false, can_group: false, allowed_ops: ['eq', 'gt', 'gte', 'lt', 'lte', 'between'] }),
    field({ key: 'tasks.requires_team_lead', source_key: 'tasks', kind: 'bool', col_type: 'bool', nullable: false, can_group: false, allowed_ops: ['is_true', 'is_false'] }),
    field({ key: 'events.date', source_key: 'events', kind: 'time', col_type: 'date', nullable: false, allowed_ops: ['gte', 'lte', 'between'] }),
    field({ key: 'events.customer', source_key: 'events', allowed_ops: ['eq', 'ne', 'in', 'not_in', 'is_null', 'is_not_null'] }),
    field({ key: 'events.status', source_key: 'events' }),
    field({ key: 'events.end_client', source_key: 'events', col_type: 'text', allowed_ops: ['eq', 'ne', 'in', 'not_in', 'is_null', 'is_not_null'] }),
    field({ key: 'events.volume_m', source_key: 'events', kind: 'num', col_type: 'numeric', can_group: false, allowed_ops: ['gt', 'gte', 'lt', 'lte', 'between', 'is_null', 'is_not_null'] }),
    field({ key: 'events.truck_count', source_key: 'events', kind: 'num', col_type: 'int', can_group: false, allowed_ops: ['eq', 'gt', 'gte', 'lt', 'lte', 'between'] }),
    field({ key: 'events.no_parking', source_key: 'events', kind: 'bool', col_type: 'bool', nullable: false, can_group: false, allowed_ops: ['is_true', 'is_false'] }),
    field({ key: 'events.porterage', source_key: 'events', kind: 'bool', col_type: 'bool', nullable: false, can_group: false, allowed_ops: ['is_true', 'is_false'] }),
    field({ key: 'attendance.date', source_key: 'attendance', kind: 'time', col_type: 'date', nullable: false, allowed_ops: ['gte', 'lte', 'between'] }),
    field({ key: 'attendance.worker', source_key: 'attendance', nullable: false }),
    field({ key: 'attendance.work_site', source_key: 'attendance', col_type: 'text', allowed_ops: ['eq', 'ne', 'in', 'not_in', 'is_null', 'is_not_null'] }),
    field({ key: 'attendance.source', source_key: 'attendance', col_type: 'text' }),
    field({ key: 'payroll.date', source_key: 'payroll', kind: 'time', col_type: 'date', nullable: false, can_filter: false, allowed_ops: [] }),
    field({ key: 'payroll.worker', source_key: 'payroll', nullable: false, can_filter: false, allowed_ops: [] }),
    field({ key: 'payroll.customer', source_key: 'payroll', nullable: false, is_estimate: true, can_filter: false, allowed_ops: [] }),
  ],
}
