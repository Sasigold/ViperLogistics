/**
 * מה שנפתח מתא בלו״ז — ומה שהכרטיס המלא מרכיב מאותם חלקים.
 *
 * עד 0108 הייתה דרך אחת לערוך משימה לעומק: לפתוח את כרטיס המשימה, מסך בן
 * שבעה כרטיסים, ולגלול אל החלק שבאמת רצית. תא בלו״ז ידע לענות רק על שאלה
 * אחת — "מי משובץ" — דרך בורר קטן, ולכן כל השאר (מי יוצא מהמחסן, כמה עובדים
 * הקבלן מביא, באיזה תעריף) חייב היה לעבור באותו מסך גדול.
 *
 * ‏0108 מפריד בין השניים. הכרטיס המלא הוא של מנהל המערכת, והתאים בלו״ז
 * פותחים **פאנל ממוקד**: לחיצה על "קבלן" פותחת את כל ההאצלה — קבלנים,
 * כמות עובדים, אתר עבודה, תעריף וסגל; לחיצה על "צוות" או "ראש צוות" פותחת
 * את השיבוץ כולו, כולל מי יוצא מהמחסן ומי מגיע לשטח. הפאנלים אינם קיצור
 * דרך לכרטיס: הם אותם רכיבים בדיוק, ולכן אין שני מקומות שאפשר להם להיפרד.
 *
 * כל מה שכאן נשמר **מיד**, בלי כפתור שמירה. זו לא בחירת נוחות: `terms`,
 * `task_assignments` ו-`task_contractor_workers` אינן עמודות של המשימה, ולכן
 * גם בכרטיס המלא הן מעולם לא נשמרו איתה.
 */
import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { HardHat, ICON, STROKE, Trash2, Users } from '../../components/ui/icons'
import {
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  Drawer,
  Field,
  Input,
  MultiSelect,
  SegmentedControl,
  Select,
  Skeleton,
  Switch,
  cx,
  fmtMoney,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import {
  useContractorAssignableWorkers,
  useContractorDelegate,
  useContractorWorkerAssign,
  useContractors,
  useStaff,
  useCustomerTrucks,
  useTrucks,
} from '../../lib/queries'
import { useWarehouses } from '../attendance/attendanceQueries'
import { fmtDate } from '../../lib/dates'
import { errorMessage } from '../../lib/errors'
import type {
  Contractor,
  Profile,
  StaffRole,
  TaskContractorTerms,
  WorkSite,
} from '../../types/domain'

/**
 * שיבוץ הסגל של קבלן אחד למשימה, וסימון אי-התייצבות (0096).
 *
 * נכתב מיד דרך RPC ולא נשמר עם הטופס — `task_contractor_workers` אינה עמודה של
 * המשימה. הקבלן נגזר מהעובד בשרת (`contractor_assign_worker`), ולכן די כאן ב-
 * ‏contractorId כדי להביא את הרוסטר הנכון ולתייג את העובדים.
 */
export function ContractorCrew({
  taskId,
  contractorId,
  contractorName,
  assignedWorkerIds,
  workerRoles,
  noShow,
  canMarkNoShow,
}: {
  taskId: string
  contractorId: string
  contractorName: string | null
  assignedWorkerIds: string[]
  /** התפקיד שכל עובד קבלן משובץ בו על המשימה (0121), לפי worker_id. */
  workerRoles?: Record<string, StaffRole | null>
  noShow: Set<string>
  canMarkNoShow: boolean
}) {
  const toast = useToast()
  const qc = useQueryClient()
  const { data: assignable = [] } = useContractorAssignableWorkers(contractorId)
  const contractorAssign = useContractorWorkerAssign()
  const assignedSet = new Set(assignedWorkerIds)
  const noShowMut = useMutation({
    mutationFn: async ({ workerId, on }: { workerId: string; on: boolean }) => {
      const { error } = await supabase.rpc('contractor_mark_no_show', {
        p_task_id: taskId,
        p_worker_id: workerId,
        p_on: on,
      })
      if (error) throw error
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['tasks', 'one', taskId] })
      /* אותה משימה נקראת משני מפתחות — הכרטיס המלא והפאנל (0108) */
      void qc.invalidateQueries({ queryKey: ['tasks', 'staffing', taskId] })
      void qc.invalidateQueries({ queryKey: ['workboard'] })
    },
    onError: (e) => toast.error(errorMessage(e)),
  })
  return (
    <>
      <MultiSelect
        options={assignable.map((w) => ({
          id: w.worker_id ? `w:${w.worker_id}` : `p:${w.profile_id}`,
          /* לאיזה קבלן העובד שייך, ולא "חשבון" (0094). */
          label: contractorName ? `${w.full_name} · ${contractorName}` : w.full_name,
        }))}
        values={assignable
          .filter((w) => w.worker_id && assignedSet.has(w.worker_id))
          .map((w) => `w:${w.worker_id}`)}
        onToggle={(id) => {
          const isProfile = id.startsWith('p:')
          const key = id.slice(2)
          contractorAssign.mutate(
            {
              taskId,
              workerId: isProfile ? null : key,
              profileId: isProfile ? key : null,
              on: !(!isProfile && assignedSet.has(key)),
            },
            { onError: (e) => toast.error(errorMessage(e)) },
          )
        }}
        placeholder="בחירת עובדים מהקבלן..."
      />
      {assignable.length === 0 && (
        <p className="mt-1 type-caption text-ink-tertiary">אין עדיין עובדים בסגל של הקבלן.</p>
      )}

      {/* תפקידי עובדי הקבלן על המשימה (0121): מי מהמשובצים שמוגדר ראש צוות /
          נהג יכול להיות משובץ בתפקיד. עובד רגיל = ללא תפקיד. */}
      {(() => {
        const eligible = assignable.filter(
          (w) =>
            w.worker_id &&
            assignedSet.has(w.worker_id) &&
            (w.roles.includes('team_lead') || w.roles.includes('driver')),
        )
        if (eligible.length === 0) return null
        return (
          <div className="mt-3 space-y-1.5 border-t border-line-subtle pt-3">
            <div className="type-overline">תפקידי הצוות</div>
            {eligible.map((w) => (
              <label key={w.worker_id} className="flex items-center justify-between gap-2 type-caption">
                <span className="truncate">{w.full_name}</span>
                <Select
                  selectSize="sm"
                  className="w-32"
                  value={workerRoles?.[w.worker_id!] ?? ''}
                  onChange={(e) =>
                    contractorAssign.mutate(
                      {
                        taskId,
                        workerId: w.worker_id,
                        on: true,
                        role: (e.target.value || null) as StaffRole | null,
                      },
                      { onError: (err) => toast.error(errorMessage(err)) },
                    )
                  }
                >
                  <option value="">עובד</option>
                  {w.roles.includes('team_lead') && <option value="team_lead">ראש צוות</option>}
                  {w.roles.includes('driver') && <option value="driver">נהג</option>}
                </Select>
              </label>
            ))}
          </div>
        )
      })()}

      {/* סימון אי-התייצבות למנהל/משרד (0093). מפעיל את קנס אי-ההתייצבות. */}
      {canMarkNoShow && assignedWorkerIds.length > 0 && (
        <div className="mt-3 space-y-1.5 border-t border-line-subtle pt-3">
          <div className="type-overline">נוכחות עובדי הקבלן</div>
          {assignable
            .filter((w) => w.worker_id && assignedSet.has(w.worker_id))
            .map((w) => (
              <label key={w.worker_id} className="flex items-center justify-between gap-2 type-caption">
                <span className="truncate">{w.full_name}</span>
                <span className="inline-flex items-center gap-1.5 text-ink-secondary">
                  לא התייצב
                  <Switch
                    checked={noShow.has(w.worker_id!)}
                    onChange={(on) => noShowMut.mutate({ workerId: w.worker_id!, on })}
                  />
                </span>
              </label>
            ))}
        </div>
      )}
    </>
  )
}

/**
 * כרטיס האצלה של קבלן אחד במשימה (0096). משימה יכולה לשאת כמה כאלה. שדות
 * ה-terms (נקודת התחלה, כמות עובדים, תעריף/מחיר) נכתבים מיד ל-terms של אותו
 * קבלן; שורה ששולם עליה ננעלת לעריכה. שיבוץ עובדי הקבלן דרך `ContractorCrew`.
 */
export function ContractorDelegationCard({
  taskId,
  term,
  contractor,
  assignedWorkerIds,
  workerRoles,
  noShow,
  canDelegate,
  canEditPricing,
  canViewPricing,
  canAssignContractor,
  canMarkNoShow,
  onRemove,
  removing,
}: {
  taskId: string
  term: TaskContractorTerms
  contractor: Contractor | undefined
  assignedWorkerIds: string[]
  workerRoles?: Record<string, StaffRole | null>
  noShow: Set<string>
  canDelegate: boolean
  canEditPricing: boolean
  canViewPricing: boolean
  canAssignContractor: boolean
  canMarkNoShow: boolean
  onRemove: () => void
  removing: boolean
}) {
  const toast = useToast()
  const qc = useQueryClient()
  const [workSite, setWorkSite] = useState<WorkSite>(term.work_site ?? 'field')
  const [count, setCount] = useState(
    term.contractor_worker_count != null ? String(term.contractor_worker_count) : '',
  )
  const [pricePerWorker, setPricePerWorker] = useState(
    term.price_per_worker != null ? String(term.price_per_worker) : '',
  )
  const [price, setPrice] = useState(term.price != null ? String(term.price) : '')

  /* השרת מחשב מחדש מחיר וקנסות אחרי כל שינוי — מסנכרנים את ה-state עם השורה
     שחזרה, כדי שהשדות הלא-נערכים ישקפו את התוצאה. */
  useEffect(() => {
    setWorkSite(term.work_site ?? 'field')
    setCount(term.contractor_worker_count != null ? String(term.contractor_worker_count) : '')
    setPricePerWorker(term.price_per_worker != null ? String(term.price_per_worker) : '')
    setPrice(term.price != null ? String(term.price) : '')
  }, [term.work_site, term.contractor_worker_count, term.price_per_worker, term.price])

  const patchTerms = useMutation({
    mutationFn: async (patch: Record<string, unknown>) => {
      const { error } = await supabase
        .from('task_contractor_terms')
        .update(patch)
        .eq('task_id', taskId)
        .eq('contractor_id', term.contractor_id)
      if (error) throw error
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['tasks', 'one', taskId] })
      /* אותה משימה נקראת משני מפתחות — הכרטיס המלא והפאנל (0108) */
      void qc.invalidateQueries({ queryKey: ['tasks', 'staffing', taskId] })
      void qc.invalidateQueries({ queryKey: ['workboard'] })
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const paid = term.paid_at != null
  const parts = term.price_parts
  /* מה שהמנוע כתב ל-`price`, מחושב מהפירוט: קנס שגדול מהמחיר יורד מתחת
     לאפס (0108), ולכן אין כאן ריצפה — היא הייתה מציגה מספר אחר מהשרת. */
  const net = parts ? parts.base + parts.surcharge - parts.penalty_total : 0
  const effectiveRate =
    pricePerWorker !== '' ? Number(pricePerWorker) : contractor?.price_per_worker ?? null
  const perWorkerPricing = effectiveRate != null

  return (
    <div
      className={cx(
        'space-y-4 rounded-xl border p-3',
        paid ? 'border-success-border bg-success-subtle/30' : 'border-line-subtle',
      )}
    >
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <span className="type-body font-semibold">{contractor?.name ?? 'קבלן'}</span>
          {paid && <Badge tone="success">שולם</Badge>}
        </div>
        {canDelegate && !paid && (
          <Button
            variant="ghost"
            size="sm"
            loading={removing}
            onClick={onRemove}
            aria-label={`הסרת ${contractor?.name ?? 'קבלן'}`}
          >
            <Trash2 size={ICON.sm} strokeWidth={STROKE} />
          </Button>
        )}
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        {/* נקודת ההתחלה שהמשרד קובע לקבלן. חלה אוטומטית על עובדיו (0091),
            ומאז 0111 היא היחידה שקובעת: ה-RPC מתעלם ממה שהקבלן שולח. הבורר
            נראה כבוי למי שאינו רשאי — קודם הוא היה נראה פעיל ובלע את הלחיצה. */}
        <Field
          label="נקודת התחלה"
          hint={canDelegate && !paid ? 'עובדי הקבלן יוצאים מכאן — כולם' : undefined}
        >
          <SegmentedControl
            value={workSite}
            onChange={(v) => {
              if (!canDelegate || paid) return
              setWorkSite(v as WorkSite)
              patchTerms.mutate({ work_site: v })
            }}
            items={[
              { key: 'field' as WorkSite, label: 'שטח' },
              { key: 'warehouse' as WorkSite, label: 'מחסן' },
            ]}
            className={cx(!canDelegate || paid ? 'pointer-events-none opacity-55' : undefined)}
          />
        </Field>
        {/* כמה עובדים הקבלן צריך להביא — תקרת השיבוץ, בלתי תלויה בכמות המשימה. */}
        <Field label="עובדים להביא" hint="תקרת השיבוץ של הקבלן">
          <Input
            type="number"
            min="0"
            value={count}
            onChange={(e) => setCount(e.target.value)}
            onBlur={() => {
              if (!canDelegate || paid) return
              const next = count === '' ? null : Number(count)
              if (next !== (term.contractor_worker_count ?? null))
                patchTerms.mutate({ contractor_worker_count: next })
            }}
            disabled={!canDelegate || paid}
          />
        </Field>
      </div>

      {canViewPricing && (
        <div className="grid gap-4 sm:grid-cols-2">
          {/* התעריף-לעובד: ריק = ברירת המחדל של הקבלן. כשקיים, המחיר מחושב
              בשרת לפי מספר העובדים ששובצו בפועל (0091). */}
          <Field
            label="מחיר לעובד (₪)"
            hint={
              contractor?.price_per_worker != null
                ? `ריק = ברירת מחדל של הקבלן (${fmtMoney(contractor.price_per_worker)})`
                : 'ריק = תמחור לפי מחיר משימה קבוע'
            }
          >
            <Input
              type="number"
              min="0"
              value={pricePerWorker}
              placeholder={contractor?.price_per_worker?.toString() ?? ''}
              onChange={(e) => setPricePerWorker(e.target.value)}
              onBlur={() => {
                if (!canEditPricing || paid) return
                const next = pricePerWorker === '' ? null : Number(pricePerWorker)
                if (next !== (term.price_per_worker ?? null))
                  patchTerms.mutate({ price_per_worker: next })
              }}
              disabled={!canEditPricing || paid}
            />
          </Field>
          <Field
            label="מחיר לקבלן (₪)"
            hint={
              perWorkerPricing
                ? `מחושב: ${assignedWorkerIds.length} עובדים × ${fmtMoney(effectiveRate ?? 0)}`
                : undefined
            }
          >
            <Input
              type="number"
              min="0"
              value={perWorkerPricing ? String(term.price ?? 0) : price}
              onChange={(e) => setPrice(e.target.value)}
              onBlur={() => {
                if (!canEditPricing || paid || perWorkerPricing) return
                const next = price === '' ? null : Number(price)
                if (next !== (term.price ?? null)) patchTerms.mutate({ price: next })
              }}
              disabled={!canEditPricing || paid || perWorkerPricing}
            />
          </Field>
        </div>
      )}

      {/* פירוט תמחור וקנסות למנהל (0093/0094). */}
      {canViewPricing && parts && (
        <div className="space-y-1 rounded-xl border border-line-subtle bg-subtle/30 p-3 type-caption text-ink-secondary">
          <div className="type-body font-medium text-ink">פירוט תמחור וקנסות</div>
          <div className="flex justify-between">
            <span>בסיס{parts.transport ? ' (הובלה)' : ''}</span>
            <span dir="ltr" className="tabular">{fmtMoney(parts.base)}</span>
          </div>
          {parts.surcharge > 0 && (
            <div className="flex justify-between">
              <span>תוספת מחסן</span>
              <span dir="ltr" className="tabular">{fmtMoney(parts.surcharge)}</span>
            </div>
          )}
          {parts.late_count > 0 && (
            <div className="flex justify-between text-error-text">
              <span>קנס איחור ({parts.late_count})</span>
              <span dir="ltr" className="tabular">
                −{fmtMoney(parts.late_count * parts.late_penalty_each)}
              </span>
            </div>
          )}
          {parts.noshow_count > 0 && (
            <div className="flex justify-between text-error-text">
              <span>קנס אי-התייצבות ({parts.noshow_count})</span>
              <span dir="ltr" className="tabular">
                −{fmtMoney(parts.noshow_count * parts.noshow_penalty_each)}
              </span>
            </div>
          )}
          {/* בלי ריצפת אפס (0108): קנס שגדול מהמחיר הוא חוב של הקבלן, והמספר
              השלילי הוא מה שמעביר אותו הלאה. הריצפה כאן גם סתרה את השרת. */}
          <div className="flex justify-between border-t border-line-subtle pt-1 type-body font-semibold text-ink">
            <span>{net < 0 ? 'לחיוב הקבלן' : 'סך לתשלום'}</span>
            <span dir="ltr" className={cx('tabular', net < 0 && 'text-error-text')}>
              {fmtMoney(net)}
            </span>
          </div>
        </div>
      )}

      {canAssignContractor && (
        <div className="border-t border-line-subtle pt-3">
          <div className="type-overline mb-2">עובדי הקבלן</div>
          <ContractorCrew
            taskId={taskId}
            contractorId={term.contractor_id}
            contractorName={contractor?.name ?? null}
            assignedWorkerIds={assignedWorkerIds}
            workerRoles={workerRoles}
            noShow={noShow}
            canMarkNoShow={canMarkNoShow}
          />
        </div>
      )}
    </div>
  )
}
/* ===== מה שהפאנלים משותפים בו ============================================ */

/** הכותרת של פאנל: איזו משימה זו, בלי לפתוח את הכרטיס כדי לדעת. */
function PanelSubject({ task }: { task: TaskPanelTask | null }) {
  if (!task) return null
  const who = task.end_client_name || task.customer_name || task.title
  return (
    <div className="flex flex-wrap items-center gap-2 rounded-lg border border-line-subtle bg-subtle/50 px-3 py-2">
      <span className="type-body font-semibold text-ink">{who || task.task_type_name}</span>
      {who && <Badge>{task.task_type_name}</Badge>}
      <span className="ms-auto type-caption text-ink-secondary">{fmtDate(task.task_date)}</span>
    </div>
  )
}

interface TaskPanelTask {
  id: string
  task_date: string
  title: string | null
  worker_count: number | null
  warehouse_id: string | null
  customer_id: string | null
  customer_name: string | null
  end_client_name: string | null
  task_type_name: string
  /* הקבלן הראשי, כפי שהוא משוקף על המשימה (0105). זו הדרך היחידה לדעת שיש
     לה קבלן בלי `contractors.view_pricing`: `contractor_list` נגזר משורות
     ה-terms, ו-`tct_select` סוגרת אותן למי שאין לו את מפתח המחירים. */
  contractor_id: string | null
  contractor_name: string | null
}

interface PanelAssignment {
  id: string
  profile_id: string
  role: StaffRole
  truck_id: string | null
  work_site: WorkSite
}

interface PanelContractorWorker {
  worker_id: string
  contractor_id: string | null
  full_name: string
  work_site: WorkSite
  no_show: boolean
  role: StaffRole | null
}

/**
 * מה ששני הפאנלים קוראים: המשימה, השיבוץ, שורות ההאצלה ועובדי הקבלן.
 *
 * מפתח משלה ולא `['tasks','one',id]`: זו שאילתה קלה בהרבה (בלי תמחור לקוח
 * ובלי המפרט), והיא נדרשת גם כשהכרטיס המלא סגור לקורא לגמרי.
 */
function useTaskPanelData(taskId: string | null, enabled: boolean) {
  return useQuery({
    queryKey: ['tasks', 'staffing', taskId],
    enabled: enabled && !!taskId,
    queryFn: async () => {
      const [t, a, terms, cw] = await Promise.all([
        supabase
          .from('work_board_view')
          .select(
            'id, task_date, title, worker_count, customer_id, customer_name, end_client_name, task_type_name, contractor_id, contractor_name',
          )
          .eq('id', taskId)
          .single(),
        supabase
          .from('task_assignments')
          .select('id, profile_id, role, truck_id, work_site')
          .eq('task_id', taskId),
        supabase.from('task_contractor_terms').select('*').eq('task_id', taskId),
        supabase
          .from('task_contractor_workers')
          .select(
            'contractor_worker_id, work_site, no_show, role, contractor_workers!inner(contractor_id, full_name)',
          )
          .eq('task_id', taskId),
      ])
      if (t.error) throw t.error
      /* `warehouse_id` אינו ב-view (הוא דריסה, לא תצוגה), ולכן הוא נשלף
         מהטבלה — ומי שאין לו גישה לשורה פשוט מקבל null ולא שגיאה. */
      const wh = await supabase.from('tasks').select('warehouse_id').eq('id', taskId).maybeSingle()
      const cwRows = (cw.data ?? []) as unknown as {
        contractor_worker_id: string
        work_site: WorkSite | null
        no_show: boolean
        role: StaffRole | null
        contractor_workers: { contractor_id: string; full_name: string } | null
      }[]
      return {
        task: {
          ...(t.data as Omit<TaskPanelTask, 'warehouse_id'>),
          warehouse_id: (wh.data?.warehouse_id as string | null) ?? null,
        } as TaskPanelTask,
        assignments: ((a.data ?? []) as PanelAssignment[]).map((x) => ({
          ...x,
          work_site: x.work_site ?? 'field',
        })),
        terms: (terms.data ?? []) as TaskContractorTerms[],
        contractorWorkers: cwRows.map((r) => ({
          worker_id: r.contractor_worker_id,
          contractor_id: r.contractor_workers?.contractor_id ?? null,
          full_name: r.contractor_workers?.full_name ?? '',
          work_site: r.work_site ?? 'field',
          no_show: r.no_show,
          role: r.role ?? null,
        })) as PanelContractorWorker[],
      }
    },
  })
}

/** כל מה שהפאנלים כותבים ל-`task_assignments`, במקום אחד. */
function useStaffingWrites(taskId: string | null) {
  const qc = useQueryClient()
  const toast = useToast()
  const done = () => {
    void qc.invalidateQueries({ queryKey: ['tasks', 'staffing', taskId] })
    void qc.invalidateQueries({ queryKey: ['tasks', 'one', taskId] })
    void qc.invalidateQueries({ queryKey: ['workboard'] })
  }
  const fail = (e: unknown) => toast.error(errorMessage(e))

  const toggle = useMutation({
    mutationFn: async (v: { role: StaffRole; profileId: string; on: boolean }) => {
      if (!taskId) return
      if (!v.on) {
        const { error } = await supabase
          .from('task_assignments')
          .delete()
          .eq('task_id', taskId)
          .eq('profile_id', v.profileId)
          .eq('role', v.role)
        if (error) throw error
        return
      }
      /* מושב ראש הצוות הוא אינדקס ייחודי, ולכן הוא מתפנה לפני שהוא מתמלא */
      if (v.role === 'team_lead') {
        const { error } = await supabase
          .from('task_assignments')
          .delete()
          .eq('task_id', taskId)
          .eq('role', 'team_lead')
        if (error) throw error
      }
      const { error } = await supabase
        .from('task_assignments')
        .insert({ task_id: taskId, profile_id: v.profileId, role: v.role, work_site: 'field' })
      if (error) throw error
    },
    onSettled: done,
    onError: fail,
  })

  const patchAssignment = useMutation({
    mutationFn: async (v: { id: string; patch: { work_site?: WorkSite; truck_id?: string | null } }) => {
      const { error } = await supabase.from('task_assignments').update(v.patch).eq('id', v.id)
      if (error) throw error
    },
    onSettled: done,
    onError: fail,
  })

  const patchTask = useMutation({
    mutationFn: async (patch: Record<string, unknown>) => {
      if (!taskId) return
      const { error } = await supabase.from('tasks').update(patch).eq('id', taskId)
      if (error) throw error
    },
    onSettled: done,
    onError: fail,
  })

  return { toggle, patchAssignment, patchTask, done, fail }
}

/** אנשי הצוות שמחזיקים תפקיד מסוים — אותו מסנן שהכרטיס המלא מחיל. */
function staffFor(staff: Profile[], role: StaffRole) {
  return staff.filter((p) => (p.staff_roles ?? []).some((r) => r.role === role))
}

/* ===== הפאנל של השיבוץ =================================================== */

/**
 * מה שנפתח מתא "צוות" או "ראש צוות" בלו״ז.
 *
 * שלוש שאלות שהתא לבדו לא ידע לענות עליהן: מי משובץ, מאיפה כל אחד מתחיל
 * (שטח או מחסן — וזה מה שקובע את שעת ההתחלה שלו במשמרת ואת המיקום שמולו
 * נמדדת החתמת הכניסה), ובאיזו משאית נוסע כל נהג. עובדי הקבלן יושבים כאן
 * לצד אנשי הצוות מפני שבשטח הם צוות אחד — אבל הם נכתבים דרך ה-RPC שלהם,
 * כי הם אינם שורה ב-`task_assignments`.
 */
export function StaffingPanel({
  open,
  onClose,
  taskId,
}: {
  open: boolean
  onClose: () => void
  taskId: string | null
}) {
  const has = useAuth((s) => s.has)
  const { data, isLoading } = useTaskPanelData(taskId, open)
  const { data: staff = [] } = useStaff()
  const { data: trucks = [] } = useTrucks()
  const { data: customerTrucks = [] } = useCustomerTrucks()
  const { data: warehouses = [] } = useWarehouses()
  /* רק לשמות. מנהל קבלן אינו מחזיק `contractors.view`, ולכן היא חוזרת ריקה
     אצלו — והשם נלקח אז מהשיקוף שעל המשימה. */
  const { data: contractors = [] } = useContractors()
  const { toggle, patchAssignment, patchTask, fail } = useStaffingWrites(taskId)
  const contractorAssign = useContractorWorkerAssign()

  const canAssign = {
    worker: has(PERM.TASKS_ASSIGN_WORKER),
    driver: has(PERM.TASKS_ASSIGN_DRIVER),
    team_lead: has(PERM.TASKS_ASSIGN_TEAM_LEAD),
  }
  const canTruck = has(PERM.TASKS_ASSIGN_TRUCK)
  const canChangeLocation = has(PERM.TASKS_CHANGE_LOCATION)
  const canAssignContractor = has(PERM.PORTAL_ASSIGN_WORKERS) || has(PERM.CONTRACTORS_ASSIGN_WORKERS)
  const myContractorId = useAuth((s) => s.me?.profile.contractor_id ?? null)
  /**
   * הקבלן שמשבץ את הסגל שלו — ותו לא (0111).
   *
   * נגזר מהמפתחות ולא מסוג המשתמש, כמו ב-0108: מי שאין לו אף מפתח שיבוץ של
   * המשרד ואין לו את המפתח המשרדי מול קבלנים, אבל כן `portal.assign_workers`,
   * הוא בהגדרה קבלן שמשבץ אצל עצמו. עבורו הפאנל הזה מצטמצם לרשימת העובדים
   * שלו: כרטיס "מי משובץ" מונה את **הצוות שלנו** בשמות ובתפקידים והיה מנוטרל
   * אצלו ממילא, וכרטיס "נקודת התחלה" מציע החלטה שאינה שלו — השרת מתעלם ממנה
   * מאז 0111, והמסך לא אמור להציע מה שלא ייכתב.
   */
  const contractorOnly =
    canAssignContractor &&
    !has(PERM.CONTRACTORS_ASSIGN_WORKERS) &&
    !canAssign.worker &&
    !canAssign.driver &&
    !canAssign.team_lead

  const assignments = data?.assignments ?? []
  const contractorWorkers = data?.contractorWorkers ?? []
  const nameOf = (id: string) => staff.find((p) => p.id === id)?.full_name ?? '—'
  const byRole = (role: StaffRole) => assignments.filter((a) => a.role === role)
  const options = useMemo(
    () => ({
      worker: staffFor(staff, 'worker').map((p) => ({ id: p.id, label: p.full_name })),
      driver: staffFor(staff, 'driver').map((p) => ({ id: p.id, label: p.full_name })),
      team_lead: staffFor(staff, 'team_lead').map((p) => ({ id: p.id, label: p.full_name })),
    }),
    [staff],
  )

  const needed = data?.task.worker_count ?? 0

  /* ‏0116: המשאיות של הלקוח של המשימה. אותו כלל של הלוח והכרטיס —
     רשימה ריקה = אין הגבלה — כדי שלא יהיו שלושה מסכים עם שלוש תשובות. */
  const availableTrucks = useMemo(() => {
    const customerId = data?.task.customer_id
    if (!customerId) return trucks
    const ids = new Set(
      customerTrucks.filter((r) => r.customer_id === customerId).map((r) => r.truck_id),
    )
    return ids.size === 0 ? trucks : trucks.filter((t) => ids.has(t.id))
  }, [trucks, customerTrucks, data?.task.customer_id])
  const assignedCount = byRole('worker').length + byRole('driver').length + contractorWorkers.length

  /* איזה קבלנים יש למשימה, משלושה מקורות שאף אחד מהם אינו זמין תמיד:
     שורות ה-terms (חסומות בלי מפתח מחירים), הקבלן המשוקף על המשימה, והקבלנים
     של העובדים שכבר שובצו. */
  const crewContractorIds = useMemo(() => {
    const ids = new Set<string>()
    for (const t of data?.terms ?? []) ids.add(t.contractor_id)
    if (data?.task.contractor_id) ids.add(data.task.contractor_id)
    for (const w of data?.contractorWorkers ?? []) if (w.contractor_id) ids.add(w.contractor_id)
    /* קבלן רואה את הסגל שלו בלבד. המשימה יכולה לשאת כמה קבלנים (0096), ושמו
       של קבלן אחר אינו עניינו — גם כשהשיקוף שעל המשימה מסגיר אותו. */
    if (contractorOnly) return [...ids].filter((id) => id === myContractorId)
    return [...ids]
  }, [data, contractorOnly, myContractorId])
  const contractorNameOf = (id: string) =>
    contractors.find((c) => c.id === id)?.name ??
    (data?.task.contractor_id === id ? data.task.contractor_name : null)

  const site = (
    value: WorkSite,
    onChange: (v: WorkSite) => void,
    disabled: boolean,
  ) => (
    <SegmentedControl
      items={[
        { key: 'field' as WorkSite, label: 'שטח' },
        { key: 'warehouse' as WorkSite, label: 'מחסן' },
      ]}
      value={value}
      onChange={(v) => !disabled && onChange(v)}
      className={cx('shrink-0', disabled && 'pointer-events-none opacity-55')}
    />
  )

  return (
    <Drawer
      open={open}
      onClose={onClose}
      title="שיבוץ הצוות"
      description="מי עובד, מאיפה הוא מתחיל, ובאיזו משאית — נשמר מיד"
      footer={
        <Button className="ms-auto" onClick={onClose}>
          סגירה
        </Button>
      }
    >
      {isLoading || !data ? (
        <div className="space-y-4">
          <Skeleton className="h-12 w-full" />
          <Skeleton className="h-40 w-full" />
        </div>
      ) : (
        <div className="space-y-4">
          <PanelSubject task={data.task} />

          {!contractorOnly && (
          <Card>
            <CardHeader
              title="מי משובץ"
              subtitle={needed > 0 ? `${assignedCount} מתוך ${needed} שובצו` : `${assignedCount} משובצים`}
              icon={<Users size={ICON.md} strokeWidth={STROKE} />}
            />
            <CardBody className="space-y-4">
              <Field label="ראש צוות">
                <MultiSelect
                  options={options.team_lead}
                  values={byRole('team_lead').map((a) => a.profile_id)}
                  onToggle={(id) =>
                    toggle.mutate({
                      role: 'team_lead',
                      profileId: id,
                      on: !byRole('team_lead').some((a) => a.profile_id === id),
                    })
                  }
                  placeholder="בחירת ראש צוות..."
                  disabled={!canAssign.team_lead}
                />
              </Field>
              <Field label="עובדים">
                <MultiSelect
                  options={options.worker}
                  values={byRole('worker').map((a) => a.profile_id)}
                  onToggle={(id) =>
                    toggle.mutate({
                      role: 'worker',
                      profileId: id,
                      on: !byRole('worker').some((a) => a.profile_id === id),
                    })
                  }
                  placeholder="בחירת עובדים..."
                  disabled={!canAssign.worker}
                />
              </Field>
              <Field label="נהגים">
                <MultiSelect
                  options={options.driver}
                  values={byRole('driver').map((a) => a.profile_id)}
                  onToggle={(id) =>
                    toggle.mutate({
                      role: 'driver',
                      profileId: id,
                      on: !byRole('driver').some((a) => a.profile_id === id),
                    })
                  }
                  placeholder="בחירת נהגים..."
                  disabled={!canAssign.driver}
                />
              </Field>
            </CardBody>
          </Card>
          )}

          {!contractorOnly && (assignments.length > 0 || contractorWorkers.length > 0) && (
            <Card>
              <CardHeader
                title="נקודת התחלה"
                subtitle="מי יוצא מהמחסן ומי מגיע לשטח — קובע את שעת ההתחלה במשמרת ואת מיקום ההחתמה"
                icon={<HardHat size={ICON.md} strokeWidth={STROKE} />}
              />
              <CardBody className="space-y-3">
                <Field label="מחסן יציאה" hint="דריסה למשימה הזו בלבד. ריק = המחסן של הלקוח">
                  <Select
                    value={data.task.warehouse_id ?? ''}
                    onChange={(e) => patchTask.mutate({ warehouse_id: e.target.value || null })}
                    disabled={!canChangeLocation}
                  >
                    <option value="">המחסן של הלקוח</option>
                    {warehouses
                      .filter((w) => w.is_active || w.id === data.task.warehouse_id)
                      .map((w) => (
                        <option key={w.id} value={w.id}>
                          {w.name}
                        </option>
                      ))}
                  </Select>
                </Field>

                {assignments.map((a) => (
                  <div key={a.id} className="flex flex-wrap items-center gap-2">
                    <span className="min-w-28 flex-1 truncate type-body">{nameOf(a.profile_id)}</span>
                    {a.role === 'driver' && (
                      <Select
                        value={a.truck_id ?? ''}
                        onChange={(e) =>
                          patchAssignment.mutate({
                            id: a.id,
                            patch: { truck_id: e.target.value || null },
                          })
                        }
                        disabled={!canTruck}
                        className="w-36 shrink-0"
                      >
                        <option value="">בלי משאית</option>
                        {availableTrucks
                          .filter((t) => t.is_active || t.id === a.truck_id)
                          .map((t) => (
                            <option key={t.id} value={t.id}>
                              {t.name}
                            </option>
                          ))}
                      </Select>
                    )}
                    {site(
                      a.work_site,
                      (work_site) => patchAssignment.mutate({ id: a.id, patch: { work_site } }),
                      !canAssign[a.role],
                    )}
                  </div>
                ))}

                {/* עובדי הקבלן נכתבים ב-RPC שלהם: `task_contractor_workers`
                    אינה נפתחת ב-UPDATE למנהל הקבלן, וה-RPC כן — הוא עושה
                    upsert על אותה שורה עם אתר העבודה החדש. */}
                {contractorWorkers.map((w) => (
                  <div key={w.worker_id} className="flex flex-wrap items-center gap-2">
                    <span className="min-w-28 flex-1 truncate type-body">
                      👷 {w.full_name}
                      {w.no_show && <Badge tone="error">לא התייצב</Badge>}
                    </span>
                    {site(
                      w.work_site,
                      (workSite) =>
                        contractorAssign.mutate(
                          { taskId: taskId!, workerId: w.worker_id, on: true, workSite },
                          { onError: fail },
                        ),
                      !canAssignContractor,
                    )}
                  </div>
                ))}
              </CardBody>
            </Card>
          )}

          {/* הסגל של הקבלן, לצד הצוות שלנו.
              זה גם המשטח היחיד שמנהל קבלן עורך: אין לו `board.inline_edit`
              ואין לו `contractors.view`, ולכן תא הקבלן אינו מוצג לו כלל
              והפאנל הזה הוא הדלת. הרשימה נגזרת מכל מקור שמעיד על קבלן
              במשימה, כדי שהיא לא תיעלם ממי שאין לו מפתח מחירים. */}
          {canAssignContractor &&
            crewContractorIds.map((cid) => (
              <Card key={cid}>
                <CardHeader
                  title="עובדי הקבלן"
                  subtitle={contractorNameOf(cid) ?? 'הסגל של הקבלן, ועובדים שנרשמו תחתיו'}
                  icon={<HardHat size={ICON.md} strokeWidth={STROKE} />}
                />
                <CardBody>
                  <ContractorCrew
                    taskId={taskId!}
                    contractorId={cid}
                    contractorName={contractorNameOf(cid)}
                    assignedWorkerIds={contractorWorkers
                      .filter((w) => w.contractor_id === cid)
                      .map((w) => w.worker_id)}
                    workerRoles={Object.fromEntries(
                      contractorWorkers.filter((w) => w.contractor_id === cid).map((w) => [w.worker_id, w.role]),
                    )}
                    noShow={new Set()}
                    canMarkNoShow={false}
                  />
                </CardBody>
              </Card>
            ))}
        </div>
      )}
    </Drawer>
  )
}

/* ===== הפאנל של ההאצלה =================================================== */

/**
 * מה שנפתח מתא "קבלן" בלו״ז.
 *
 * התא עצמו יודע לענות רק על "לאיזה קבלן", וזו השאלה הקטנה: מה שנקבע בהאצלה
 * הוא גם כמה עובדים הקבלן מביא, מאיפה הם מתחילים, באיזה תעריף, ומי מהסגל
 * שלו באמת יוצא. כל אלה יושבים כאן, בדיוק באותו רכיב שהכרטיס המלא משתמש בו.
 */
export function ContractorPanel({
  open,
  onClose,
  taskId,
}: {
  open: boolean
  onClose: () => void
  taskId: string | null
}) {
  const has = useAuth((s) => s.has)
  const toast = useToast()
  const { data, isLoading } = useTaskPanelData(taskId, open)
  const { data: contractors = [] } = useContractors()
  const delegate = useContractorDelegate()
  const [addContractor, setAddContractor] = useState('')

  const canDelegate = has(PERM.TASKS_DELEGATE)
  const canViewPricing = has(PERM.CONTRACTORS_VIEW_PRICING)
  const canEditPricing = has(PERM.CONTRACTORS_EDIT_PRICING)
  const canMarkNoShow = has(PERM.CONTRACTORS_EDIT_PRICING) || has(PERM.TASKS_EDIT)
  const canAssignContractor = has(PERM.PORTAL_ASSIGN_WORKERS) || has(PERM.CONTRACTORS_ASSIGN_WORKERS)

  const terms = data?.terms ?? []
  const delegatedIds = new Set(terms.map((t) => t.contractor_id))
  const addable = contractors.filter((c) => c.is_active && !delegatedIds.has(c.id))

  return (
    <Drawer
      open={open}
      onClose={onClose}
      title="האצלה לקבלנים"
      description="לאיזה קבלן, כמה עובדים, מאיפה ובאיזה תעריף — נשמר מיד"
      footer={
        <Button className="ms-auto" onClick={onClose}>
          סגירה
        </Button>
      }
    >
      {isLoading || !data || !taskId ? (
        <div className="space-y-4">
          <Skeleton className="h-12 w-full" />
          <Skeleton className="h-40 w-full" />
        </div>
      ) : (
        <div className="space-y-4">
          <PanelSubject task={data.task} />

          {terms.length === 0 && (
            <p className="type-caption text-ink-tertiary">המשימה לא הואצלה לאף קבלן.</p>
          )}

          {terms.map((term) => {
            const mine = data.contractorWorkers.filter((w) => w.contractor_id === term.contractor_id)
            return (
              <ContractorDelegationCard
                key={term.contractor_id}
                taskId={taskId}
                term={term}
                contractor={contractors.find((c) => c.id === term.contractor_id)}
                assignedWorkerIds={mine.map((w) => w.worker_id)}
                workerRoles={Object.fromEntries(mine.map((w) => [w.worker_id, w.role]))}
                noShow={new Set(mine.filter((w) => w.no_show).map((w) => w.worker_id))}
                canDelegate={canDelegate}
                canEditPricing={canEditPricing}
                canViewPricing={canViewPricing}
                canAssignContractor={canAssignContractor}
                canMarkNoShow={canMarkNoShow}
                onRemove={() =>
                  delegate.mutate(
                    { taskId, contractorId: term.contractor_id, on: false },
                    { onError: (e) => toast.error(errorMessage(e)) },
                  )
                }
                removing={delegate.isPending}
              />
            )
          })}

          {canDelegate && addable.length > 0 && (
            <div className="flex items-end gap-2 border-t border-line-subtle pt-4">
              <Field label="הוספת קבלן" className="flex-1">
                <Select value={addContractor} onChange={(e) => setAddContractor(e.target.value)}>
                  <option value="">בחירת קבלן...</option>
                  {addable.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name}
                    </option>
                  ))}
                </Select>
              </Field>
              <Button
                loading={delegate.isPending}
                disabled={!addContractor}
                onClick={() =>
                  delegate.mutate(
                    { taskId, contractorId: addContractor, on: true },
                    {
                      onSuccess: () => setAddContractor(''),
                      onError: (e) => toast.error(errorMessage(e)),
                    },
                  )
                }
              >
                הוספה
              </Button>
            </div>
          )}
        </div>
      )}
    </Drawer>
  )
}
