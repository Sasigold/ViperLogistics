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
import { ChevronDown, ICON, STROKE, Trash2 } from '../../components/ui/icons'
import { PERM } from '../../lib/permissions'
import { useAuth } from '../../state/auth'
import type { DashboardLayoutRow } from './useDashboardLayout'
import type { UserKind } from '../../types/domain'

const KIND_LABELS: Record<UserKind, string> = {
  staff: 'עובדי צוות',
  customer_user: 'משתמשי לקוח',
  contractor_user: 'משתמשי קבלן',
}

/**
 * Saved views, plus the two administrative actions that belong beside them.
 *
 * A saved view is the active layout with a name on it — same payload, one more
 * row — which is what makes offering several of them worth the surface.
 */
export function SavedViewsMenu({
  views,
  onApply,
  onSaveAs,
  onDelete,
  onReset,
  onPublishDefault,
  hasOwnLayout,
}: {
  views: DashboardLayoutRow[]
  onApply: (row: DashboardLayoutRow) => void
  onSaveAs: (name: string) => Promise<void> | void
  onDelete: (id: string) => Promise<unknown>
  onReset: () => Promise<void> | void
  onPublishDefault: (kind: UserKind | null) => Promise<unknown>
  hasOwnLayout: boolean
}) {
  const has = useAuth((s) => s.has)
  const { prompt, dialog: promptDialog } = usePrompt()
  const { confirm, dialog: confirmDialog } = useConfirm()

  return (
    <>
      <Popover
        align="end"
        trigger={(p) => (
          <Button size="sm" variant="ghost" {...p}>
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
                    onClick={() => {
                      onApply(v)
                      close()
                    }}
                  >
                    {v.name}
                  </MenuItem>
                </span>
                <IconButton
                  size="sm"
                  label={`מחיקת ${v.name}`}
                  onClick={async () => {
                    if (await confirm(`למחוק את "${v.name}"?`, { title: 'מחיקת תצוגה', confirmLabel: 'מחיקה', tone: 'danger' }))
                      await onDelete(v.id)
                  }}
                >
                  <Trash2 size={ICON.sm} strokeWidth={STROKE} aria-hidden />
                </IconButton>
              </span>
            ))}
            {views.length > 0 && <MenuSeparator />}

            <MenuItem
              onClick={async () => {
                close()
                const name = await prompt('שם התצוגה', '', { title: 'שמירת תצוגה', placeholder: 'למשל: כספים' })
                if (name?.trim()) await onSaveAs(name.trim())
              }}
            >
              שמירה כתצוגה חדשה
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

            {has(PERM.DASHBOARD_MANAGE_DEFAULT) && (
              <>
                <MenuSeparator />
                <MenuLabel>פרסום כברירת מחדל</MenuLabel>
                <MenuItem
                  onClick={async () => {
                    close()
                    if (
                      await confirm('הפריסה הנוכחית תהיה מה שכל מי שאין לו פריסה אישית רואה.', {
                        title: 'לפרסם לכל המשתמשים?',
                        confirmLabel: 'פרסום',
                      })
                    )
                      await onPublishDefault(null)
                  }}
                >
                  לכל המשתמשים
                </MenuItem>
                {(Object.keys(KIND_LABELS) as UserKind[]).map((k) => (
                  <MenuItem
                    key={k}
                    onClick={async () => {
                      close()
                      if (
                        await confirm('ברירת מחדל לסוג משתמש גוברת על הכללית.', {
                          title: `לפרסם ל${KIND_LABELS[k]}?`,
                          confirmLabel: 'פרסום',
                        })
                      )
                        await onPublishDefault(k)
                    }}
                  >
                    ל{KIND_LABELS[k]}
                  </MenuItem>
                ))}
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
