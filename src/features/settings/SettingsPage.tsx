import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Boxes,
  ClipboardList,
  ICON,
  Plus,
  RotateCcw,
  STROKE,
  Shield,
  Trash2,
  Truck,
  Zap,
} from '../../components/ui/icons'
import {
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  Checkbox,
  EmptyState,
  Field,
  IconButton,
  Input,
  PageHeader,
  Select,
  Skeleton,
  StatusPill,
  Tabs,
  Tooltip,
  cx,
  fmtRelative,
  useConfirm,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { useExecutionMethods, useStatuses, useTaskTypes, useTrucks } from '../../lib/queries'
import { fmtDateTime } from '../../lib/dates'
import { RequirePermission } from '../auth/guards'
import { PERM } from '../../lib/permissions'
import { RolesTab } from '../permissions/RolesTab'

/**
 * Each tab names the permission that governs it, so a coordinator who may edit
 * statuses but not the recycle bin lands on a screen with one tab rather than
 * on a wall of "אין הרשאה".
 */
const TABS = [
  { key: 'task_types', label: 'סוגי משימות', icon: <ClipboardList size={ICON.sm} />, perm: PERM.SETTINGS_TASK_TYPES },
  { key: 'execution_methods', label: 'אופני ביצוע', icon: <Boxes size={ICON.sm} />, perm: PERM.SETTINGS_EXECUTION_METHODS },
  { key: 'statuses', label: 'סטטוסים', icon: <Zap size={ICON.sm} />, perm: PERM.SETTINGS_STATUSES },
  { key: 'trucks', label: 'משאיות', icon: <Truck size={ICON.sm} />, perm: PERM.SETTINGS_TRUCKS },
  { key: 'roles', label: 'הרשאות ותפקידים', icon: <Shield size={ICON.sm} />, perm: PERM.SETTINGS_PERMISSIONS },
  { key: 'recycle', label: 'סל מיחזור', icon: <RotateCcw size={ICON.sm} />, perm: PERM.SETTINGS_RECYCLE_BIN },
] as const

export default function SettingsPage() {
  const has = useAuth((s) => s.has)
  const visible = TABS.filter((t) => has(t.perm))
  const [tab, setTab] = useState<(typeof TABS)[number]['key']>(visible[0]?.key ?? 'task_types')
  const active = visible.some((t) => t.key === tab) ? tab : visible[0]?.key

  return (
    <RequirePermission perm={PERM.SETTINGS_VIEW}>
      <div className="space-y-4">
        <PageHeader title="הגדרות" subtitle="נתוני הבסיס שמזינים את כל שאר המסכים">
          {visible.length > 1 && <Tabs items={visible} value={tab} onChange={setTab} />}
        </PageHeader>

        {active === 'task_types' && <TaskTypesTab />}
        {active === 'execution_methods' && <MethodsTab />}
        {active === 'statuses' && <StatusesTab />}
        {active === 'trucks' && <TrucksTab />}
        {active === 'roles' && <RolesTab />}
        {active === 'recycle' && <RecycleBinTab />}
      </div>
    </RequirePermission>
  )
}

function useSoftDelete(invalidate: string) {
  const qc = useQueryClient()
  const toast = useToast()
  return useMutation({
    mutationFn: async ({ table, id, restore }: { table: string; id: string; restore?: boolean }) => {
      const { error } = await supabase.rpc('soft_delete', { p_table: table, p_id: id, p_restore: restore ?? false })
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: [invalidate] }),
    onError: (e) => toast.error((e as Error).message),
  })
}

/** The "label + add button" header shared by every settings list. */
function AddRow({
  children,
  onSubmit,
  pending,
  disabled,
}: {
  children: React.ReactNode
  onSubmit: () => void
  pending?: boolean
  disabled?: boolean
}) {
  return (
    <form
      className="flex flex-wrap items-end gap-2 border-b border-line-subtle bg-subtle/40 p-4"
      onSubmit={(e) => {
        e.preventDefault()
        onSubmit()
      }}
    >
      {children}
      <Button type="submit" size="sm" variant="primary" loading={pending} disabled={disabled}>
        <Plus size={ICON.sm} strokeWidth={STROKE} />
        הוספה
      </Button>
    </form>
  )
}

/* ===== task types ========================================================= */

function TaskTypesTab() {
  const qc = useQueryClient()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const { data: types = [], isLoading } = useTaskTypes()
  const [name, setName] = useState('')
  const del = useSoftDelete('task_types')

  const add = useMutation({
    mutationFn: async () => {
      if (!name.trim()) throw new Error('חובה להזין שם')
      const { error } = await supabase.from('task_types').insert({ name, sort_order: types.length + 1 })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('סוג המשימה נוסף')
      setName('')
      void qc.invalidateQueries({ queryKey: ['task_types'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <Card className="max-w-2xl">
      {dialog}
      <CardHeader
        title="סוגי משימות"
        subtitle={`${types.length} סוגים · סוגי מערכת אינם ניתנים למחיקה`}
        icon={<ClipboardList size={ICON.md} strokeWidth={STROKE} />}
      />
      <AddRow onSubmit={() => add.mutate()} pending={add.isPending} disabled={!name.trim()}>
        <Field label="סוג משימה חדש" className="min-w-48 flex-1">
          <Input inputSize="sm" value={name} onChange={(e) => setName(e.target.value)} />
        </Field>
      </AddRow>
      <CardBody padded={false}>
        {isLoading ? (
          <div className="p-4">
            <Skeleton className="h-32 w-full" />
          </div>
        ) : types.length === 0 ? (
          <EmptyState compact art="box" title="לא הוגדרו סוגי משימות" />
        ) : (
          <ul>
            {types.map((t) => (
              <li key={t.id} className="flex items-center gap-2 border-b border-line-subtle px-4 py-2.5 last:border-0 hover:bg-hover">
                <span className="type-body font-medium">{t.name}</span>
                {t.is_system && <Badge tone="primary">מערכת</Badge>}
                {t.auto_create_on_event && (
                  <Tooltip content="משימה מסוג זה נוצרת אוטומטית עם כל אירוע חדש">
                    <Badge tone="success">נוצר אוטומטית</Badge>
                  </Tooltip>
                )}
                {!t.is_system && (
                  <IconButton
                    label={`מחיקת ${t.name}`}
                    size="sm"
                    className="ms-auto hover:text-error"
                    onClick={async () => {
                      if (await confirm(`למחוק את "${t.name}"?`, { title: 'מחיקת סוג משימה', confirmLabel: 'מחיקה' }))
                        del.mutate({ table: 'task_types', id: t.id })
                    }}
                  >
                    <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                  </IconButton>
                )}
              </li>
            ))}
          </ul>
        )}
      </CardBody>
    </Card>
  )
}

/* ===== execution methods ==================================================
   The method x task-type matrix is the densest control in settings; a real
   grid with a sticky first column beats a bare table of checkboxes.       */

function MethodsTab() {
  const qc = useQueryClient()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const { data: methods = [], isLoading } = useExecutionMethods()
  const { data: types = [] } = useTaskTypes()
  const [name, setName] = useState('')
  const del = useSoftDelete('execution_methods')

  const { data: mapping = [] } = useQuery({
    queryKey: ['task_type_execution_methods', 'all'],
    queryFn: async () => {
      const { data, error } = await supabase.from('task_type_execution_methods').select('*')
      if (error) throw error
      return data as { task_type_id: string; execution_method_id: string }[]
    },
  })

  const add = useMutation({
    mutationFn: async () => {
      if (!name.trim()) throw new Error('חובה להזין שם')
      const { data, error } = await supabase
        .from('execution_methods')
        .insert({ name, sort_order: methods.length + 1 })
        .select('id')
        .single()
      if (error) throw error
      // new methods are available for all task types by default
      await supabase
        .from('task_type_execution_methods')
        .insert(types.map((t) => ({ task_type_id: t.id, execution_method_id: data.id })))
    },
    onSuccess: () => {
      toast.success('אופן הביצוע נוסף')
      setName('')
      void qc.invalidateQueries({ queryKey: ['execution_methods'] })
      void qc.invalidateQueries({ queryKey: ['task_type_execution_methods'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const toggleMap = useMutation({
    mutationFn: async ({ typeId, methodId, on }: { typeId: string; methodId: string; on: boolean }) => {
      if (on) {
        const { error } = await supabase
          .from('task_type_execution_methods')
          .insert({ task_type_id: typeId, execution_method_id: methodId })
        if (error) throw error
      } else {
        const { error } = await supabase
          .from('task_type_execution_methods')
          .delete()
          .eq('task_type_id', typeId)
          .eq('execution_method_id', methodId)
        if (error) throw error
      }
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['task_type_execution_methods'] }),
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <Card>
      {dialog}
      <CardHeader
        title="אופני ביצוע"
        subtitle="סימון אילו אופני ביצוע זמינים לכל סוג משימה"
        icon={<Boxes size={ICON.md} strokeWidth={STROKE} />}
      />
      <AddRow onSubmit={() => add.mutate()} pending={add.isPending} disabled={!name.trim()}>
        <Field label="אופן ביצוע חדש" className="w-64">
          <Input inputSize="sm" value={name} onChange={(e) => setName(e.target.value)} />
        </Field>
      </AddRow>
      <CardBody padded={false}>
        {isLoading ? (
          <div className="p-4">
            <Skeleton className="h-40 w-full" />
          </div>
        ) : methods.length === 0 ? (
          <EmptyState compact art="box" title="לא הוגדרו אופני ביצוע" />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="bg-subtle">
                  <th className="sticky bg-inherit px-4 py-2 text-start type-table-head" style={{ insetInlineStart: 0 }}>
                    אופן ביצוע
                  </th>
                  {types.map((t) => (
                    <th key={t.id} className="px-2 py-2 text-center type-table-head">
                      <span className="block max-w-24 truncate">{t.name}</span>
                    </th>
                  ))}
                  <th className="w-12" />
                </tr>
              </thead>
              <tbody>
                {methods.map((m, i) => (
                  <tr
                    key={m.id}
                    className={cx('border-t border-line-subtle hover:bg-hover', i % 2 === 1 ? 'bg-subtle/40' : 'bg-surface')}
                  >
                    <td className="sticky bg-inherit px-4 py-2 type-body font-medium" style={{ insetInlineStart: 0 }}>
                      {m.name}
                    </td>
                    {types.map((t) => {
                      const on = mapping.some((x) => x.task_type_id === t.id && x.execution_method_id === m.id)
                      return (
                        <td key={t.id} className="px-2 py-2 text-center">
                          <span className="inline-flex">
                            <Checkbox
                              checked={on}
                              onChange={(v) => toggleMap.mutate({ typeId: t.id, methodId: m.id, on: v })}
                            />
                          </span>
                        </td>
                      )
                    })}
                    <td className="px-2 py-2">
                      <IconButton
                        label={`מחיקת ${m.name}`}
                        size="sm"
                        className="hover:text-error"
                        onClick={async () => {
                          if (await confirm(`למחוק את "${m.name}"?`, { title: 'מחיקת אופן ביצוע', confirmLabel: 'מחיקה' }))
                            del.mutate({ table: 'execution_methods', id: m.id })
                        }}
                      >
                        <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                      </IconButton>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </CardBody>
    </Card>
  )
}

/* ===== statuses =========================================================== */

const STATUS_COLORS = ['#3563f0', '#8b5cf6', '#0ea5e9', '#1fa189', '#16a34a', '#f59e0b', '#ef4444', '#8a93a5']

function StatusesTab() {
  const qc = useQueryClient()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const { data: statuses = [], isLoading } = useStatuses()
  const [form, setForm] = useState({ name: '', entity: 'task', color: '#3563f0', is_terminal: false })
  const del = useSoftDelete('statuses')

  const add = useMutation({
    mutationFn: async () => {
      if (!form.name.trim()) throw new Error('חובה להזין שם')
      const { error } = await supabase.from('statuses').insert({ ...form, sort_order: (statuses?.length ?? 0) + 1 })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('הסטטוס נוסף')
      setForm((f) => ({ ...f, name: '' }))
      void qc.invalidateQueries({ queryKey: ['statuses'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <Card className="max-w-3xl">
      {dialog}
      <CardHeader
        title="סטטוסים"
        subtitle="סטטוס סוגר מסמן שהמשימה הושלמה או בוטלה — משפיע על חישוב האיחורים"
        icon={<Zap size={ICON.md} strokeWidth={STROKE} />}
      />
      <AddRow onSubmit={() => add.mutate()} pending={add.isPending} disabled={!form.name.trim()}>
        <Field label="סטטוס חדש" className="min-w-40 flex-1">
          <Input inputSize="sm" value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} />
        </Field>
        <Field label="עבור" className="w-32">
          <Select selectSize="sm" value={form.entity} onChange={(e) => setForm((f) => ({ ...f, entity: e.target.value }))}>
            <option value="task">משימות</option>
            <option value="event">אירועים</option>
          </Select>
        </Field>
        <Field label="צבע">
          <div className="flex items-center gap-1">
            {STATUS_COLORS.map((c) => (
              <button
                key={c}
                type="button"
                aria-label={`צבע ${c}`}
                aria-pressed={form.color === c}
                onClick={() => setForm((f) => ({ ...f, color: c }))}
                className="size-6 rounded-md transition-transform hover:scale-110 focus-visible:outline-none focus-visible:focus-ring"
                style={{ background: c, boxShadow: form.color === c ? `0 0 0 2px var(--vl-surface), 0 0 0 4px ${c}` : undefined }}
              />
            ))}
          </div>
        </Field>
        <div className="pb-1.5">
          <Checkbox
            label="סטטוס סוגר"
            checked={form.is_terminal}
            onChange={(v) => setForm((f) => ({ ...f, is_terminal: v }))}
          />
        </div>
      </AddRow>
      <CardBody className="space-y-5">
        {isLoading ? (
          <Skeleton className="h-32 w-full" />
        ) : (
          (['task', 'event'] as const).map((entity) => {
            const list = (statuses ?? []).filter((s) => s.entity === entity)
            return (
              <div key={entity}>
                <h3 className="mb-2 type-overline">{entity === 'task' ? 'סטטוסי משימות' : 'סטטוסי אירועים'}</h3>
                {list.length === 0 ? (
                  <p className="type-caption text-ink-tertiary">אין סטטוסים</p>
                ) : (
                  <div className="flex flex-wrap gap-2">
                    {list.map((s) => (
                      <span
                        key={s.id}
                        className="inline-flex items-center gap-1.5 rounded-full border border-line py-1 pe-1.5 ps-2.5 type-body"
                      >
                        <span className="size-2.5 shrink-0 rounded-full" style={{ background: s.color }} />
                        {s.name}
                        {s.is_default && <Badge tone="primary">ברירת מחדל</Badge>}
                        {s.is_terminal && <Badge tone="success">סוגר</Badge>}
                        {!s.is_default && (
                          <IconButton
                            label={`מחיקת ${s.name}`}
                            size="sm"
                            bare
                            className="size-5 hover:text-error"
                            onClick={async () => {
                              if (await confirm(`למחוק את "${s.name}"?`, { title: 'מחיקת סטטוס', confirmLabel: 'מחיקה' }))
                                del.mutate({ table: 'statuses', id: s.id })
                            }}
                          >
                            <Trash2 size={12} />
                          </IconButton>
                        )}
                      </span>
                    ))}
                  </div>
                )}
              </div>
            )
          })
        )}
      </CardBody>
    </Card>
  )
}

/* ===== trucks ============================================================= */

function TrucksTab() {
  const qc = useQueryClient()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const { data: trucks = [], isLoading } = useTrucks()
  const [form, setForm] = useState({ name: '', plate_number: '' })
  const del = useSoftDelete('trucks')

  const add = useMutation({
    mutationFn: async () => {
      if (!form.name.trim()) throw new Error('חובה להזין שם משאית')
      const { error } = await supabase.from('trucks').insert(form)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('המשאית נוספה')
      setForm({ name: '', plate_number: '' })
      void qc.invalidateQueries({ queryKey: ['trucks'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <Card className="max-w-2xl">
      {dialog}
      <CardHeader
        title="צי משאיות"
        subtitle={`${trucks.length} משאיות · ${trucks.filter((t) => t.is_active).length} פעילות`}
        icon={<Truck size={ICON.md} strokeWidth={STROKE} />}
      />
      <AddRow onSubmit={() => add.mutate()} pending={add.isPending} disabled={!form.name.trim()}>
        <Field label="שם משאית" className="min-w-40 flex-1">
          <Input inputSize="sm" value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} />
        </Field>
        <Field label="מספר רישוי" className="w-36">
          <Input
            inputSize="sm"
            dir="ltr"
            value={form.plate_number}
            onChange={(e) => setForm((f) => ({ ...f, plate_number: e.target.value }))}
          />
        </Field>
      </AddRow>
      <CardBody padded={false}>
        {isLoading ? (
          <div className="p-4">
            <Skeleton className="h-24 w-full" />
          </div>
        ) : trucks.length === 0 ? (
          <EmptyState compact art="box" title="אין משאיות" description="הוסף משאיות כדי לשייך אותן לנהגים ולמשימות" />
        ) : (
          <ul>
            {trucks.map((t) => (
              <li key={t.id} className="flex items-center gap-3 border-b border-line-subtle px-4 py-2.5 last:border-0 hover:bg-hover">
                <span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-subtle text-ink-tertiary" aria-hidden>
                  <Truck size={ICON.sm} strokeWidth={STROKE} />
                </span>
                <div className="min-w-0 flex-1">
                  <p className="truncate type-body font-medium">{t.name}</p>
                  <p className="truncate type-caption tabular text-ink-tertiary" dir="ltr">
                    {t.plate_number || '—'}
                  </p>
                </div>
                {!t.is_active && <StatusPill color="#8a93a5">לא פעילה</StatusPill>}
                <IconButton
                  label={`מחיקת ${t.name}`}
                  size="sm"
                  className="hover:text-error"
                  onClick={async () => {
                    if (await confirm(`למחוק את "${t.name}"?`, { title: 'מחיקת משאית', confirmLabel: 'מחיקה' }))
                      del.mutate({ table: 'trucks', id: t.id })
                  }}
                >
                  <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                </IconButton>
              </li>
            ))}
          </ul>
        )}
      </CardBody>
    </Card>
  )
}

/* ===== recycle bin ======================================================== */

const RECYCLE_TABLES = [
  { value: 'events', label: 'אירועים' },
  { value: 'tasks', label: 'משימות' },
  { value: 'customers', label: 'לקוחות' },
  { value: 'contractors', label: 'קבלנים' },
  { value: 'profiles', label: 'משתמשים' },
  { value: 'suppliers', label: 'ספקים' },
  { value: 'trucks', label: 'משאיות' },
  { value: 'task_types', label: 'סוגי משימות' },
  { value: 'execution_methods', label: 'אופני ביצוע' },
  { value: 'statuses', label: 'סטטוסים' },
]

function RecycleBinTab() {
  const { me } = useAuth()
  const qc = useQueryClient()
  const toast = useToast()
  const [table, setTable] = useState('events')

  const { data: rows = [], isLoading } = useQuery({
    queryKey: ['recycle', table],
    enabled: !!me?.profile.is_admin,
    queryFn: async () => {
      const { data, error } = await supabase
        .from(table)
        .select('*')
        .not('deleted_at', 'is', null)
        .order('deleted_at', { ascending: false })
        .limit(100)
      if (error) throw error
      return data as Record<string, unknown>[]
    },
  })

  const restore = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('soft_delete', { p_table: table, p_id: id, p_restore: true })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('שוחזר בהצלחה')
      void qc.invalidateQueries({ queryKey: ['recycle'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  if (!me?.profile.is_admin) return <AdminOnly what="סל המיחזור" />

  const labelOf = (r: Record<string, unknown>) =>
    (r.name as string) || (r.end_client_name as string) || (r.full_name as string) || (r.title as string) || (r.id as string)

  return (
    <Card className="max-w-2xl">
      <CardHeader
        title="סל מיחזור"
        subtitle="פריטים שנמחקו מחיקה רכה — ניתן לשחזר אותם למצבם הקודם"
        icon={<RotateCcw size={ICON.md} strokeWidth={STROKE} />}
        actions={
          <Select className="w-44" selectSize="sm" value={table} onChange={(e) => setTable(e.target.value)} aria-label="סוג הפריטים">
            {RECYCLE_TABLES.map((t) => (
              <option key={t.value} value={t.value}>
                {t.label}
              </option>
            ))}
          </Select>
        }
      />
      <CardBody padded={false}>
        {isLoading ? (
          <div className="p-4">
            <Skeleton className="h-24 w-full" />
          </div>
        ) : rows.length === 0 ? (
          <EmptyState compact art="check" title="סל המיחזור ריק" description="לא נמחקו פריטים מסוג זה" />
        ) : (
          <ul>
            {rows.map((r) => (
              <li key={r.id as string} className="flex items-center gap-3 border-b border-line-subtle px-4 py-2.5 last:border-0 hover:bg-hover">
                <div className="min-w-0 flex-1">
                  <p className="truncate type-body font-medium">{labelOf(r)}</p>
                  <p className="type-caption text-ink-tertiary" title={fmtDateTime(r.deleted_at as string)}>
                    נמחק {fmtRelative(r.deleted_at as string)}
                  </p>
                </div>
                <Button size="sm" loading={restore.isPending} onClick={() => restore.mutate(r.id as string)}>
                  <RotateCcw size={ICON.sm} strokeWidth={STROKE} />
                  שחזור
                </Button>
              </li>
            ))}
          </ul>
        )}
      </CardBody>
    </Card>
  )
}

function AdminOnly({ what }: { what: string }) {
  return (
    <Card className="max-w-md">
      <EmptyState
        art="alert"
        title="גישה למנהלי מערכת בלבד"
        description={`${what} זמין למנהלי מערכת. פנה למנהל אם דרושה לך גישה.`}
      />
    </Card>
  )
}
