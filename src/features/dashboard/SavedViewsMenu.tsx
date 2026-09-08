import {
  Button,
  IconButton,
  MenuItem,
  MenuLabel,
  MenuSeparator,
  Popover,
  useConfirm,
  usePrompt,
} from '../../components/ui'
import { Bookmark, ChevronDown, Copy, ICON, Pencil, Pin, PinOff, STROKE, Save, Trash2 } from '../../components/ui/icons'
import { PERM } from '../../lib/permissions'
import { fmtDate } from '../../lib/dates'
import { useAuth } from '../../state/auth'
import { RANGE_PRESETS } from './dashboardRange'
import type { DateRange } from './dashboardRange'
import type { DashboardLayoutRow } from './useDashboardLayout'
import type { ViewPrefs } from './dashboardTypes'
import type { UserKind } from '../../types/domain'

const KIND_LABELS: Record<UserKind, string> = {
  staff: 'עובדי צוות',
  customer_user: 'משתמשי לקוח',
  contractor_user: 'משתמשי קבלן',
}

/**
 * Saved views, plus the administrative actions that belong beside them.
 *
 * A saved view is the active layout with a name on it — same payload, one more
 * row — which is what makes offering several of them worth the surface. Since
 * 0151 that payload also carries the *view*: packing, time bucket, top-N and,
 * if it was pinned, the range it opens on. "The screen I want" is not only
 * which cards and in what order.
 *
 * Three things a saved view could not do before and now can: be overwritten
 * (it was save-as or nothing, so refining one meant a second row with a second
 * name), be renamed, and be duplicated. And on the administrative side, a
 * published default can be taken back down — publishing one was a one-way door.
 */
export function SavedViewsMenu({
  views,
  onApply,
  onSaveAs,
  onOverwrite,
  onRename,
  onDelete,
  onReset,
  onPublishDefault,
  onRemoveDefault,
  onPinRange,
  pinnedRange,
  currentRange,
  orgDefaults,
  hasOwnLayout,
}: {
  views: DashboardLayoutRow[]
  onApply: (row: DashboardLayoutRow) => void
  onSaveAs: (name: string) => Promise<void> | void
  onOverwrite: (id: string) => Promise<unknown>
  onRename: (id: string, name: string) => Promise<unknown>
  onDelete: (id: string) => Promise<unknown>
  onReset: () => Promise<void> | void
  onPublishDefault: (kind: UserKind | null) => Promise<unknown>
  onRemoveDefault: (kind: UserKind | null) => Promise<unknown>
  onPinRange: (range: ViewPrefs['range']) => void
  pinnedRange: ViewPrefs['range']
  currentRange: DateRange
  /** the published rows, so an administrator can see what exists before adding to it */
  orgDefaults: DashboardLayoutRow[]
  hasOwnLayout: boolean
}) {
  const has = useAuth((s) => s.has)
  const { prompt, dialog: promptDialog } = usePrompt()
  const { confirm, dialog: confirmDialog } = useConfirm()
  const canManage = has(PERM.DASHBOARD_MANAGE_DEFAULT)
  const published = new Set(orgDefaults.map((r) => r.user_kind))

  /* The range is pinned by preset when the reader is sitting on one, so "this
     month" saved in March opens on April in April. Only an exact match counts —
     a range that merely looks like the preset is a range somebody typed. */
  const matchingPreset = RANGE_PRESETS.find((p) => {
    const r = p.range()
    return r.from === currentRange.from && r.to === currentRange.to
  })

  return (
    <>
      <Popover
        align="end"
        /* `onClick={toggle}` explicitly, and only the aria spread. `Popover`
           hands its trigger `{toggle, ...aria}`; spreading the whole object onto
           a button puts `toggle` on the DOM element, where React drops it — and
           the menu never opens. Every other Popover in the product does it this
           way. */
        trigger={({ toggle, ...aria }) => (
          <Button size="sm" variant="ghost" onClick={toggle} {...aria}>
            תצוגות
            <ChevronDown size={ICON.sm} strokeWidth={STROKE} aria-hidden />
          </Button>
        )}
      >
        {(close) => (
          <>
            {views.length > 0 && <MenuLabel>התצוגות שלי</MenuLabel>}
            {views.map((v) => (
              <span key={v.id} className="flex items-center gap-1 pe-1">
                <span className="min-w-0 flex-1">
                  <MenuItem
                    icon={<Bookmark size={ICON.md} strokeWidth={STROKE} aria-hidden />}
                    onClick={() => {
                      onApply(v)
                      close()
                    }}
                  >
                    {v.name}
                  </MenuItem>
                </span>
                {/* Overwrite, rename, delete — the three things you want from a
                    saved view once you have more than one of them. */}
                <IconButton
                  size="sm"
                  label={`עדכון ${v.name} למה שעל המסך`}
                  onClick={async () => {
                    close()
                    if (
                      await confirm(`"${v.name}" יוחלף בתצוגה שעל המסך עכשיו.`, {
                        title: 'עדכון תצוגה',
                        confirmLabel: 'עדכון',
                      })
                    )
                      await onOverwrite(v.id)
                  }}
                >
                  <Save size={ICON.sm} strokeWidth={STROKE} aria-hidden />
                </IconButton>
                <IconButton
                  size="sm"
                  label={`שינוי שם ${v.name}`}
                  onClick={async () => {
                    close()
                    const name = await prompt('שם התצוגה', v.name ?? '', { title: 'שינוי שם' })
                    if (name?.trim()) await onRename(v.id, name.trim())
                  }}
                >
                  <Pencil size={ICON.sm} strokeWidth={STROKE} aria-hidden />
                </IconButton>
                <IconButton
                  size="sm"
                  label={`מחיקת ${v.name}`}
                  onClick={async () => {
                    if (
                      await confirm(`למחוק את "${v.name}"?`, {
                        title: 'מחיקת תצוגה',
                        confirmLabel: 'מחיקה',
                        tone: 'danger',
                      })
                    )
                      await onDelete(v.id)
                  }}
                >
                  <Trash2 size={ICON.sm} strokeWidth={STROKE} aria-hidden />
                </IconButton>
              </span>
            ))}
            {views.length > 0 && <MenuSeparator />}

            <MenuItem
              icon={<Copy size={ICON.md} strokeWidth={STROKE} aria-hidden />}
              onClick={async () => {
                close()
                const name = await prompt('שם התצוגה', '', { title: 'שמירת תצוגה', placeholder: 'למשל: כספים' })
                if (name?.trim()) await onSaveAs(name.trim())
              }}
            >
              שמירה כתצוגה חדשה
            </MenuItem>

            {/* The range is part of "the screen I want" — a finance view that
                opens on last month is a different answer from one that opens on
                today, and until now the view could not say which. */}
            <MenuItem
              icon={
                pinnedRange ? (
                  <PinOff size={ICON.md} strokeWidth={STROKE} aria-hidden />
                ) : (
                  <Pin size={ICON.md} strokeWidth={STROKE} aria-hidden />
                )
              }
              onClick={() => {
                close()
                if (pinnedRange) onPinRange(undefined)
                else onPinRange(matchingPreset ? { preset: matchingPreset.label } : { ...currentRange })
              }}
            >
              {pinnedRange
                ? 'ביטול קיבוע הטווח'
                : matchingPreset
                  ? `פתיחה תמיד על "${matchingPreset.label}"`
                  : `פתיחה תמיד על ${fmtDate(currentRange.from)}–${fmtDate(currentRange.to)}`}
            </MenuItem>

            <MenuItem
              disabled={!hasOwnLayout}
              onClick={async () => {
                close()
                if (
                  await confirm('הפריסה האישית תימחק והדשבורד יחזור לברירת המחדל.', {
                    title: 'לאפס את הדשבורד?',
                    confirmLabel: 'איפוס',
                    tone: 'danger',
                  })
                )
                  await onReset()
              }}
            >
              איפוס לברירת המחדל
            </MenuItem>

            {canManage && (
              <>
                <MenuSeparator />
                <MenuLabel>ברירת מחדל לארגון</MenuLabel>
                {/* Saying what is already published, next to the button that
                    publishes: an administrator who cannot see the current state
                    is an administrator who publishes twice to be sure. */}
                <PublishRow
                  label="לכל המשתמשים"
                  published={published.has(null)}
                  onPublish={async () => {
                    close()
                    if (
                      await confirm(
                        'הפריסה הנוכחית — כולל צורות התצוגה והנעילות — תהיה מה שכל מי שאין לו פריסה אישית רואה.',
                        { title: 'לפרסם לכל המשתמשים?', confirmLabel: 'פרסום' },
                      )
                    )
                      await onPublishDefault(null)
                  }}
                  onRemove={async () => {
                    close()
                    if (
                      await confirm('ברירת המחדל הכללית תימחק, והמשתמשים יחזרו לפריסה המובנית.', {
                        title: 'להסיר את ברירת המחדל?',
                        confirmLabel: 'הסרה',
                        tone: 'danger',
                      })
                    )
                      await onRemoveDefault(null)
                  }}
                />
                {(Object.keys(KIND_LABELS) as UserKind[]).map((k) => (
                  <PublishRow
                    key={k}
                    label={`ל${KIND_LABELS[k]}`}
                    published={published.has(k)}
                    onPublish={async () => {
                      close()
                      if (
                        await confirm('ברירת מחדל לסוג משתמש גוברת על הכללית.', {
                          title: `לפרסם ל${KIND_LABELS[k]}?`,
                          confirmLabel: 'פרסום',
                        })
                      )
                        await onPublishDefault(k)
                    }}
                    onRemove={async () => {
                      close()
                      if (
                        await confirm(`ברירת המחדל ל${KIND_LABELS[k]} תימחק, והם יחזרו לכללית.`, {
                          title: 'להסיר?',
                          confirmLabel: 'הסרה',
                          tone: 'danger',
                        })
                      )
                        await onRemoveDefault(k)
                    }}
                  />
                ))}
                <p className="px-2.5 py-1 type-caption text-ink-tertiary">
                  ווידג׳ט שננעל בעריכה יופיע אצל כולם ולא ניתן יהיה להסירו.
                </p>
              </>
            )}
          </>
        )}
      </Popover>
      {promptDialog}
      {confirmDialog}
    </>
  )
}

function PublishRow({
  label,
  published,
  onPublish,
  onRemove,
}: {
  label: string
  published: boolean
  onPublish: () => void
  onRemove: () => void
}) {
  return (
    <span className="flex items-center gap-1 pe-1">
      <span className="min-w-0 flex-1">
        <MenuItem onClick={onPublish} shortcut={published ? 'פורסם' : undefined}>
          {label}
        </MenuItem>
      </span>
      {published && (
        <IconButton size="sm" label={`הסרת ברירת המחדל ${label}`} onClick={onRemove}>
          <Trash2 size={ICON.sm} strokeWidth={STROKE} aria-hidden />
        </IconButton>
      )}
    </span>
  )
}
