import { makeCustomComponent } from './CustomWidget'
import { VIZ_SIZES, isNote, isQuery } from './widgetSpec'
import type { CustomWidgetRow } from './useCustomWidgets'
import type { WidgetDef } from '../dashboardTypes'

/**
 * Stored rows → the same `WidgetDef` shape the 65 hand-written widgets use.
 *
 * Once a custom widget is a `WidgetDef`, every piece of machinery already
 * built for the catalogue applies to it unchanged: `resolveLayout` keeps its
 * slot, `visibleItems` filters it by permission, `WidgetFrame` gives it a size
 * control and a drag handle, `CustomizeDrawer` lists it, the export walks it.
 * Nothing downstream knows the difference, which is the point.
 */

export const CUSTOM_PREFIX = 'custom.'

/**
 * A uuid with the dashes taken out.
 *
 * Namespaced so it cannot collide with a hand-written id, and `registry.test`
 * asserts that no static id starts with this prefix so it stays that way. The
 * dashes go because the id ends up in a `queryKey` and in the layout jsonb,
 * and one canonical spelling is worth more than readability here.
 */
export const toWidgetId = (uuid: string) => CUSTOM_PREFIX + uuid.replace(/-/g, '')

export const isCustomId = (id: string) => id.startsWith(CUSTOM_PREFIX)

/** back to the uuid the server knows */
export function toUuid(widgetId: string): string | null {
  if (!isCustomId(widgetId)) return null
  const hex = widgetId.slice(CUSTOM_PREFIX.length)
  if (!/^[0-9a-f]{32}$/i.test(hex)) return null
  return [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 20), hex.slice(20)].join('-')
}

export function customWidgetDefs(rows: readonly CustomWidgetRow[]): WidgetDef[] {
  return rows.map((row) => {
    const sizes = isQuery(row.spec) ? (VIZ_SIZES[row.spec.viz] ?? ['md']) : VIZ_SIZES.note
    return {
      id: toWidgetId(row.id),
      group: 'custom' as const,
      title: row.title,
      subtitle: row.subtitle ?? undefined,
      description: describe(row),
      /* Straight from the server. The client does not — and must not — work
         out from the spec which keys a widget needs: that answer is computed
         in `dashboard_widget_catalog` from the same catalogue rows the engine
         gates against, so there is no second copy to drift. */
      perms: row.perms,
      kinds: ['staff'],
      sizes: sizes.length > 0 ? sizes : (['md'] as const),
      resizableHeight: !isNote(row.spec),
      /* A note never asks the server anything, and a widget pinned to its own
         relative window ignores the page's picker. Only a page-ranged query
         should re-fetch when the dates move. */
      usesRange: isQuery(row.spec) && row.spec.range_mode === 'page',
      wantsDelta: false,
      // custom widgets go through dashboard_widgets_run, not dashboard_sections
      sections: undefined,
      Component: makeCustomComponent(row),
    } satisfies WidgetDef
  })
}

function describe(row: CustomWidgetRow): string {
  if (isNote(row.spec)) return 'פתק טקסט חופשי'
  if (!row.known) return 'מבקש נתון שאינו קיים עוד'
  const who = row.is_mine ? 'נבנה על ידך' : 'שותף על ידי עמית'
  return row.shared ? `${who} · משותף לארגון` : who
}
