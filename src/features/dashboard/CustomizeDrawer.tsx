import { useMemo, useState } from 'react'
import { Drawer, EmptyState, IconButton, SearchInput, Switch, cx } from '../../components/ui'
import { ChevronDown, ChevronUp, ICON, STROKE } from '../../components/ui/icons'
import { useAuth } from '../../state/auth'
import { GROUPS, GROUP_LABELS } from './dashboardTypes'
import type { LayoutItem, WidgetDef, WidgetGroup } from './dashboardTypes'
import { widgetAllowed } from './layout'

/**
 * The catalogue.
 *
 * Filtered by the same `has()` the server answers with, exactly as
 * `visibleNavSections` filters the sidebar: a widget the reader holds no key
 * for is not offered here at all. Listing one and having it render nothing
 * would teach people that the toggle is broken.
 *
 * The ↑/↓ list is not a lesser version of dragging — it is how a twenty-widget
 * reshuffle stays bearable, and how any of this works on a keyboard.
 */
export function CustomizeDrawer({
  open,
  onClose,
  items,
  hidden,
  widgets,
  onToggle,
  onMove,
}: {
  open: boolean
  onClose: () => void
  items: LayoutItem[]
  hidden: string[]
  widgets: WidgetDef[]
  onToggle: (id: string, on: boolean) => void
  onMove: (id: string, offset: number) => void
}) {
  const has = useAuth((s) => s.has)
  const kind = useAuth((s) => s.me?.profile.user_kind)
  const [q, setQ] = useState('')

  const allowed = useMemo(() => widgets.filter((w) => widgetAllowed(w, has, kind)), [widgets, has, kind])

  const shown = useMemo(() => {
    const needle = q.trim()
    if (!needle) return allowed
    return allowed.filter((w) => w.title.includes(needle) || w.description.includes(needle))
  }, [allowed, q])

  const onPage = new Set(items.map((i) => i.id))
  const orderOf = new Map(items.map((i, idx) => [i.id, idx]))

  const byGroup = GROUPS.map((g) => ({
    group: g as WidgetGroup,
    list: shown.filter((w) => w.group === g),
  })).filter((g) => g.list.length > 0)

  return (
    <Drawer open={open} onClose={onClose} title="התאמת הדשבורד" description={`${items.length} ווידג׳טים מוצגים`}>
      <div className="space-y-4">
        <SearchInput value={q} onChange={(e) => setQ(e.target.value)} placeholder="חיפוש ווידג׳ט" />

        {byGroup.length === 0 && <EmptyState compact art="search" title="לא נמצא ווידג׳ט מתאים" />}

        {byGroup.map(({ group, list }) => (
          <section key={group}>
            <h3 className="mb-1.5 type-overline">{GROUP_LABELS[group]}</h3>
            <ul className="overflow-hidden rounded-lg border border-line">
              {list.map((w) => {
                const on = onPage.has(w.id)
                const idx = orderOf.get(w.id) ?? -1
                return (
                  <li
                    key={w.id}
                    className={cx(
                      'flex items-center gap-2 border-b border-line-subtle px-3 py-2 last:border-0',
                      !on && 'bg-subtle/40',
                    )}
                  >
                    <span className="min-w-0 flex-1">
                      <span className="block truncate type-body font-medium">{w.title}</span>
                      <span className="block truncate type-caption text-ink-tertiary">{w.description}</span>
                    </span>

                    {on && (
                      <span className="flex shrink-0 items-center">
                        <IconButton
                          size="sm"
                          label={`הזז את ${w.title} אחורה`}
                          disabled={idx <= 0}
                          onClick={() => onMove(w.id, -1)}
                        >
                          <ChevronUp size={ICON.md} strokeWidth={STROKE} aria-hidden />
                        </IconButton>
                        <IconButton
                          size="sm"
                          label={`הזז את ${w.title} קדימה`}
                          disabled={idx < 0 || idx >= items.length - 1}
                          onClick={() => onMove(w.id, 1)}
                        >
                          <ChevronDown size={ICON.md} strokeWidth={STROKE} aria-hidden />
                        </IconButton>
                      </span>
                    )}

                    <Switch checked={on} onChange={(v) => onToggle(w.id, v)} aria-label={`הצגת ${w.title}`} />
                  </li>
                )
              })}
            </ul>
          </section>
        ))}

        {hidden.length > 0 && (
          <p className="type-caption text-ink-tertiary">
            {hidden.length} ווידג׳טים הוסרו. הם לא יחזרו מעצמם גם בגרסאות הבאות.
          </p>
        )}
      </div>
    </Drawer>
  )
}
