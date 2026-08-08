import { useMemo, useState } from 'react'
import { Button, Drawer, EmptyState, IconButton, SearchInput, Switch, cx } from '../../components/ui'
import { ChevronDown, ChevronUp, ICON, Pencil, PencilLine, Plus, STROKE, Trash2 } from '../../components/ui/icons'
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
  canBuild,
  ownIds,
  onNew,
  onEdit,
  onDelete,
}: {
  open: boolean
  onClose: () => void
  items: LayoutItem[]
  hidden: string[]
  widgets: WidgetDef[]
  onToggle: (id: string, on: boolean) => void
  onMove: (id: string, offset: number) => void
  /** `dashboard.build_widget` — absent for portal users and anyone denied it */
  canBuild?: boolean
  /* Widget ids this reader owns, from the server's `is_mine`. A shared widget
     belongs to whoever built it, so the catalogue offers it to everyone but
     hands the pencil to one person — and that answer comes from the row, not
     from anything parsed out of a display string. */
  ownIds?: ReadonlySet<string>
  onNew?: (variant: 'query' | 'note') => void
  /** only ever offered for a widget this reader owns */
  onEdit?: (widgetId: string) => void
  onDelete?: (widgetId: string) => void
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

        {/* Building is its own permission, not a slice of `dashboard.customize`:
            that one is on by default for the customer portal too, and the query
            builder is not a portal screen. */}
        {canBuild && (
          <div className="flex flex-wrap gap-2">
            <Button size="sm" onClick={() => onNew?.('query')}>
              <Plus size={ICON.sm} strokeWidth={STROKE} />
              ווידג׳ט חדש
            </Button>
            <Button size="sm" variant="ghost" onClick={() => onNew?.('note')}>
              <PencilLine size={ICON.sm} strokeWidth={STROKE} />
              פתק
            </Button>
          </div>
        )}

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

                    {/* Editing and deleting are the owner's, not the reader's:
                        a shared widget on your dashboard is someone else's
                        object, and the toggle above is the whole of your say
                        over it. */}
                    {w.group === 'custom' && ownIds?.has(w.id) && (
                      <span className="flex shrink-0 items-center">
                        <IconButton size="sm" label={`עריכת ${w.title}`} onClick={() => onEdit?.(w.id)}>
                          <Pencil size={ICON.sm} strokeWidth={STROKE} aria-hidden />
                        </IconButton>
                        <IconButton
                          size="sm"
                          variant="ghost"
                          label={`מחיקת ${w.title}`}
                          onClick={() => onDelete?.(w.id)}
                        >
                          <Trash2 size={ICON.sm} strokeWidth={STROKE} className="text-error" aria-hidden />
                        </IconButton>
                      </span>
                    )}

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
