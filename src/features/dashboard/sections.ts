/**
 * Every section key `dashboard_sections` knows how to compute.
 *
 * Mirrored from `supabase/migrations/0041_dashboard_sections.sql`, for the same
 * reason `permissionKeys.ts` mirrors the permission registry: the server is the
 * authority either way, but a typo here has no symptom. An unknown key is
 * deliberately *skipped* rather than raised — that is what lets an older server
 * serve a newer client — so `revenue.trends` would return null forever and the
 * widget would simply never appear, for everyone, with nothing in any log.
 *
 * `registry.test.ts` checks every widget's `sections` against this list, which
 * turns that silent failure into a failing test.
 */
export const SECTIONS = [
  // כספים — הכנסות
  'revenue.trend',
  'revenue.forecast',
  'pricing.quality',
  // כספים — קבלנים
  'cost.contractor',
  'cost.by_contractor',
  'cost.contractor_unpaid',
  // כספים — שכר
  'cost.payroll',
  'cost.payroll_by_worker',
  'cost.payroll_trend',
  // כספים — רווח גולמי
  'margin.summary',
  'margin.trend',
  'margin.by_customer',
  // כספים — הכנסות קטגוריה, תקבולים ועלות מעביד (0069)
  'income.by_category',
  'income.mix',
  'finance.receivables',
  'finance.client_share',
  'cost.payroll_employer',
  'finance.profit_summary',
  // הצד של הלקוח (0074) — הוצאה, לא הכנסה
  'spend.summary',
  // תפעול
  'tasks.by_type',
  'tasks.by_method',
  'tasks.trend',
  'tasks.understaffed',
  'tasks.no_truck',
  'fleet.utilization',
  // לקוחות
  'events.by_customer',
  'events.funnel',
  'events.volume',
  'customers.leaderboard',
  'customers.inactive',
  // כוח אדם
  'attendance.hours',
  'attendance.hours_by_worker',
  'attendance.pending',
  'attendance.flags',
  'hr.headcount',
] as const

export type SectionKey = (typeof SECTIONS)[number]
