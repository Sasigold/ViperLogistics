/**
 * "דפים" — אילו דפים מוצגים (0215), לקבוצת מנהלי המערכת, לתפקיד או למשתמש.
 *
 * אותו מבנה של מטריצת ההרשאות: לכל דף שלושה מצבים — ירושה / מוצג / מוסתר —
 * והתשובה בפועל כתובה לידו. עם תפקידים, קבוצת המנהלים והגדרה אישית ביחד,
 * "הסתרתי והוא עדיין רואה" אי אפשר להבין מהמסך בלי לומר ממה זה נובע.
 *
 * דף נפתח רק כשגם ההרשאות פותחות אותו, ולכן ליד דף שההרשאות סוגרות כתוב
 * שהוא סגור — "מוצג" כאן אינו מעניק דבר.
 */
import { useMemo } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, ICON, LayoutDashboard, STROKE } from '../../components/ui/icons'
import { Badge, CollapsibleCard, SegmentedControl, Skeleton, Tooltip, useToast } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import {
  refreshOwnCapabilities,
  resolveEffective,
  useKindDefaults,
  usePermissionRegistry,
  usePermissionRoles,
  useProfileRoles,
  useRolePermissions,
  useRolesPermissions,
  useUserGrants,
} from '../../lib/permissions'
import { effectiveRoleIds } from '../../lib/scopes'
import { ADMIN_LOCKED_PAGES, PAGES, resolvePage, settingOf } from '../../app/pages'
import type { PageGroup, PageResolution, PageSetting, PageVisibilityRow } from '../../app/pages'
import { pagePermitted, pagePerms } from '../../app/nav'
import type { Profile, UserKind } from '../../types/domain'
import { errorMessage } from '../../lib/errors'

export type PageSubject =
  | { kind: 'admins' }
  | { kind: 'role'; roleId: string; roleName: string; userKind: UserKind | null }
  | { kind: 'user'; profile: Profile }

const SETTINGS: { key: PageSetting; label: string }[] = [
  { key: 'inherit', label: 'ירושה' },
  { key: 'show', label: 'מוצג' },
  { key: 'hide', label: 'מוסתר' },
]

const ADMINS_LABEL = 'מנהלי מערכת'

/** כל השורות שהקורא רשאי לראות — הטבלה קטנה (דפים × תפקידים ומשתמשים). */
function usePageVisibilityRows() {
  return useQuery({
    queryKey: ['page_visibility'],
    queryFn: async () => {
      const { data, error } = await supabase.from('page_visibility').select('page_key, role_id, profile_id, visible')
      if (error) throw error
      return data as PageVisibilityRow[]
    },
  })
}

const INTRO: Record<PageSubject['kind'], string> = {
  admins:
    'אילו דפים יוצגו לכל מנהלי המערכת. מנהל מערכת ממשיך להחזיק את כל ההרשאות — כאן רק בוחרים מה מופיע בתפריט שלו.',
  role: '"מוצג" בתפקיד אחד גובר על "מוסתר" בתפקיד אחר, והגדרה אישית של משתמש גוברת על שניהם.',
  user: 'הגדרה אישית גוברת על התפקידים של המשתמש ועל קבוצת מנהלי המערכת.',
}

export function PageVisibilityEditor({ subject }: { subject: PageSubject }) {
  const toast = useToast()
  const qc = useQueryClient()

  const profile = subject.kind === 'user' ? subject.profile : null
  const roleId = subject.kind === 'role' ? subject.roleId : null
  const isAdmin = subject.kind === 'admins' || !!profile?.is_admin
  const kind: UserKind | null =
    subject.kind === 'admins' ? 'staff' : subject.kind === 'role' ? subject.userKind : subject.profile.user_kind

  const { data: rows = [], isLoading } = usePageVisibilityRows()
  const { data: registry = [] } = usePermissionRegistry()
  const { data: roles = [] } = usePermissionRoles()
  const { data: heldRoleIds = [] } = useProfileRoles(profile?.id)
  const { data: userGrants = [] } = useUserGrants(profile && !profile.is_admin ? profile.id : null)
  const { data: ownRoleGrants = [] } = useRolePermissions(roleId)
  const { data: kindDefaults = [] } = useKindDefaults()

  // התפקידים שבתוקף למשתמש — אותה הכרעה של `app.my_role_ids`
  const inEffect = useMemo(
    () => (profile ? roles.filter((r) => effectiveRoleIds(roles, heldRoleIds, profile.user_kind).includes(r.id)) : []),
    [profile, roles, heldRoleIds],
  )
  const { data: heldRoleGrants } = useRolesPermissions(
    subject.kind === 'user' && !isAdmin ? inEffect.map((r) => r.id) : [],
  )

  /** האם ההרשאות של הנושא פותחות את המפתח — הבבואה של `app.has` */
  const allowed = useMemo(() => {
    const kinds = new Map(
      kindDefaults.filter((d) => kind && d.user_kind === kind).map((d) => [d.permission_key, d.allowed] as const),
    )
    const layers =
      subject.kind === 'user'
        ? {
            userGrants: new Map(userGrants.map((g) => [g.permission_key, g.allowed] as const)),
            roleGrants: heldRoleGrants ?? new Map<string, boolean>(),
            kindDefaults: kinds,
          }
        : {
            userGrants: new Map<string, boolean>(),
            roleGrants: new Map(ownRoleGrants.map((g) => [g.permission_key, g.allowed] as const)),
            kindDefaults: kinds,
          }
    return (key: string) => isAdmin || resolveEffective(key, registry, layers, kind).allowed
  }, [subject.kind, isAdmin, kind, registry, userGrants, heldRoleGrants, ownRoleGrants, kindDefaults])

  /** דף שאף מפתח שלו אינו חל על סוג המשתמש — לא יוצג לעולם, ולכן אינו ברשימה */
  const relevant = (page: string) =>
    !kind ||
    registry.length === 0 ||
    pagePerms(page).some((key) => registry.find((r) => r.key === key)?.applies_to.includes(kind))

  const own = (page: string): boolean | undefined =>
    rows.find(
      (r) =>
        r.page_key === page &&
        (subject.kind === 'admins'
          ? r.role_id === null && r.profile_id === null
          : subject.kind === 'role'
            ? r.role_id === roleId
            : r.profile_id === profile!.id),
    )?.visible

  const resolve = (page: string): PageResolution => {
    if (subject.kind !== 'user') {
      const label = subject.kind === 'admins' ? ADMINS_LABEL : subject.roleName
      return resolvePage(page, { isAdmin, groups: [{ label, visible: own(page) }] })
    }
    const groups: PageGroup[] = inEffect.map((r) => ({
      label: `התפקיד ${r.name_he}`,
      visible: rows.find((x) => x.page_key === page && x.role_id === r.id)?.visible,
    }))
    if (isAdmin) {
      groups.unshift({
        label: ADMINS_LABEL,
        visible: rows.find((x) => x.page_key === page && x.role_id === null && x.profile_id === null)?.visible,
      })
    }
    return resolvePage(page, { isAdmin, personal: own(page), groups })
  }

  const sourceText = (res: PageResolution) => {
    if (res.source === 'locked') return 'אינו מוסתר ממנהל מערכת'
    if (res.source === 'personal') return 'הגדרה אישית'
    if (res.source === 'default') return 'ברירת מחדל'
    return subject.kind === 'user' ? `לפי ${res.via.join(', ')}` : 'נקבע כאן'
  }

  const update = useMutation({
    mutationFn: async ({ page, setting }: { page: string; setting: PageSetting }) => {
      const { error } = await supabase.rpc('page_visibility_set', {
        p_page_key: page,
        p_visible: setting === 'inherit' ? null : setting === 'show',
        p_role_id: roleId,
        p_profile_id: profile?.id ?? null,
        p_admins: subject.kind === 'admins',
      })
      if (error) throw error
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['page_visibility'] })
      // מי שערך עשוי להיות בקבוצה שערך — התפריט שלו מתעדכן מיד
      refreshOwnCapabilities()
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  if (isLoading) return <Skeleton className="h-96 w-full" />

  const sections = [...new Set(PAGES.map((p) => p.section))]
    .map((section) => ({ section, pages: PAGES.filter((p) => p.section === section && relevant(p.key)) }))
    .filter((s) => s.pages.length > 0)

  return (
    <div className="space-y-3">
      <p className="type-caption text-ink-secondary">
        {INTRO[subject.kind]} הסתרת דף מורידה אותו מהתפריט וחוסמת את הכתובת שלו; הנתונים עצמם נשלטים בהרשאות.
      </p>

      {sections.map(({ section, pages }) => {
        const hidden = pages.filter((p) => !resolve(p.key).visible).length
        const set = pages.filter((p) => own(p.key) !== undefined).length
        return (
          <CollapsibleCard
            key={section}
            title={section}
            subtitle={
              hidden > 0
                ? `${hidden} מתוך ${pages.length} מוסתרים`
                : set > 0
                  ? `${set} הוגדרו במפורש — הכול מוצג`
                  : 'הכול מוצג'
            }
            icon={<LayoutDashboard size={ICON.md} strokeWidth={STROKE} />}
          >
            <ul className="space-y-1">
              {pages.map((page) => {
                const res = resolve(page.key)
                const permitted = pagePermitted(page.key, allowed)
                const locked = isAdmin && ADMIN_LOCKED_PAGES.has(page.key)
                return (
                  <li
                    key={page.key}
                    className="flex flex-wrap items-center gap-x-3 gap-y-2 rounded-lg px-2 py-2 hover:bg-subtle/50"
                  >
                    <div className="min-w-48 flex-1">
                      <p className="type-body font-medium">{page.label}</p>
                      {'hint' in page && page.hint && (
                        <p className="type-caption text-ink-tertiary">{page.hint}</p>
                      )}
                      {!permitted && (
                        <p className="mt-1 flex items-center gap-1.5 type-caption text-warning-text">
                          <AlertTriangle size={ICON.xs} strokeWidth={STROKE} />
                          {subject.kind === 'role'
                            ? 'התפקיד אינו מעניק הרשאה לדף הזה — "מוצג" לבדו לא יפתח אותו'
                            : 'אין למשתמש הרשאה לדף הזה — "מוצג" לבדו לא יפתח אותו'}
                        </p>
                      )}
                    </div>

                    <div className="flex items-center gap-2">
                      <Badge tone={permitted && res.visible ? 'success' : 'neutral'}>
                        {!permitted ? 'בפועל: סגור' : res.visible ? 'בפועל: מוצג' : 'בפועל: מוסתר'}
                      </Badge>
                      <span className="hidden type-caption text-ink-tertiary sm:inline">{sourceText(res)}</span>
                      <Tooltip content={locked ? 'מההגדרות מחזירים דפים שהוסתרו, ולכן הן אינן מוסתרות ממנהל מערכת' : ''}>
                        <SegmentedControl
                          items={SETTINGS}
                          value={settingOf(own(page.key))}
                          onChange={(next) => !locked && update.mutate({ page: page.key, setting: next })}
                          className={locked ? 'pointer-events-none opacity-55' : undefined}
                        />
                      </Tooltip>
                    </div>
                  </li>
                )
              })}
            </ul>
          </CollapsibleCard>
        )
      })}
    </div>
  )
}
