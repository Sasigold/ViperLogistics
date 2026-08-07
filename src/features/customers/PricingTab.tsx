/**
 * מסך התמחור של הלקוח: מצב (ידני/אוטומטי) ובונה מחשבון לכל סוג משימה.
 *
 * הבונה עורך JSONB ותו לא. הוא אינו מחשב כלום בעצמו — התצוגה המקדימה
 * קוראת ל-RPC preview_task_price, שמריץ את אותו app.price_calc שמתמחר
 * בפועל. זה מה שמונע את המצב שבו המסך מבטיח מספר אחד והמערכת גובה אחר.
 */
import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  ArrowDown,
  ArrowUp,
  Banknote,
  Calculator,
  Clock,
  ICON,
  Info,
  Plus,
  RefreshCw,
  STROKE,
  Trash2,
  Users,
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
  Select,
  SegmentedControl,
  Skeleton,
  fmtHoursShort,
  fmtMoney,
  useConfirm,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { useCustomerPricingRules, useTaskTypes } from '../../lib/queries'
import { StickySaveBar } from '../contractors/ContractorDetailPage'
import { PricingZonesEditor } from '../pricing/PricingZonesEditor'
import {
  AFTER_KINDS,
  BOOLEAN_VARS,
  COMPONENT_KINDS,
  HOUR_KINDS,
  MODEL_HINT,
  MODEL_LABEL,
  NUMBER_VARS,
  PREVIEW_DEFAULTS,
  PRICING_VARS,
  ROUNDING_LABEL,
  WORKERS_BASIS_LABEL,
  moveItem,
  newId,
  normalizeConfig,
} from './pricingSchema'
import type { FieldName } from './pricingSchema'
import type {
  Customer,
  PriceBreakdown,
  PriceCond,
  PricingAfterWorkers,
  PricingComponent,
  PricingConfig,
  PricingHourComponent,
  PricingMode,
  PricingModel,
  PricingMultiplier,
  PricingTier,
  PricingWorkerAdjustment,
  TaskType,
} from '../../types/domain'

/* ===== the tab ============================================================ */

const MODES = [
  { key: 'manual' as const, label: 'ידני' },
  { key: 'auto' as const, label: 'אוטומטי' },
]

export default function PricingTab({ customer }: { customer: Customer }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const { has } = useAuth()
  const canEdit = has(PERM.PRICING_MANAGE_RULES)

  const { data: taskTypes = [] } = useTaskTypes()
  const { data: rules = [], isLoading } = useCustomerPricingRules(customer.id)

  const setMode = useMutation({
    mutationFn: async (mode: PricingMode) => {
      const { error } = await supabase.from('customers').update({ pricing_mode: mode }).eq('id', customer.id)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('אופן התמחור עודכן')
      void qc.invalidateQueries({ queryKey: ['customers'] })
      void qc.invalidateQueries({ queryKey: ['workboard'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  // חישוב גורף כולל אירועי עבר. שינוי מחשבון לבדו נוגע רק בעתיד, כי אירוע
  // שכבר היה עשוי להיות מחויב — כאן מבקשים במפורש לשכתב גם אותו.
  const recalcAll = useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.rpc('recalculate_customer_prices', {
        p_customer_id: customer.id,
        p_from: null,
      })
      if (error) throw error
      return data as number
    },
    onSuccess: (n) => {
      toast.success(`${n} מחירים חושבו מחדש`)
      void qc.invalidateQueries({ queryKey: ['workboard'] })
      void qc.invalidateQueries({ queryKey: ['task_pricing'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  // הקמה ופירוק תחילה — הם המשימות שבפועל מתומחרות — ואז כל השאר.
  const ordered = useMemo(() => {
    const rank = (t: TaskType) => (t.code === 'setup' ? 0 : t.code === 'teardown' ? 1 : 2)
    return taskTypes.filter((t) => t.is_active).slice().sort((a, b) => rank(a) - rank(b) || a.sort_order - b.sort_order)
  }, [taskTypes])

  return (
    <div className="max-w-4xl space-y-4">
      {dialog}

      <Card>
        <CardHeader
          title="אופן תמחור"
          subtitle={
            customer.pricing_mode === 'auto'
              ? 'המחיר מחושב מהמחשבון ומתעדכן בכל שינוי באירוע'
              : 'המחיר מוזן ידנית על כל משימה'
          }
          icon={<Calculator size={ICON.md} strokeWidth={STROKE} />}
        />
        <CardBody className="flex flex-wrap items-center gap-3">
          <SegmentedControl
            items={MODES}
            value={customer.pricing_mode}
            onChange={(m) => canEdit && setMode.mutate(m)}
            className={canEdit ? undefined : 'pointer-events-none opacity-55'}
          />
          {customer.pricing_mode === 'auto' && canEdit && (
            <Button
              size="sm"
              variant="ghost"
              loading={recalcAll.isPending}
              onClick={async () => {
                if (
                  await confirm('לחשב מחדש את כל המחירים של הלקוח, כולל אירועי עבר ומחירים שנערכו ידנית?', {
                    title: 'חישוב מחדש',
                    confirmLabel: 'חשב מחדש',
                  })
                )
                  recalcAll.mutate()
              }}
            >
              <RefreshCw size={ICON.sm} />
              חשב מחדש לכל האירועים
            </Button>
          )}
        </CardBody>
      </Card>

      {customer.pricing_mode === 'manual' ? (
        <Card>
          <CardBody>
            <EmptyState
              art="table"
              title="תמחור ידני"
              description="המחיר של כל משימה מוזן במגירת המשימה או בטופס האירוע. כדי לבנות מחשבון שיחשב אותו לבד, החליפו ל״אוטומטי״."
            />
          </CardBody>
        </Card>
      ) : isLoading ? (
        <Skeleton className="h-96 w-full" />
      ) : (
        <>
          {ordered.map((type) => (
            <RuleCard
              key={type.id}
              customerId={customer.id}
              taskType={type}
              rule={rules.find((r) => r.task_type_id === type.id) ?? null}
              canEdit={canEdit}
            />
          ))}
          {/* זמן הנסיעה בנוסחה מגיע מכאן, ולכן המפה יושבת לצד המחשבון ולא
              במסך נפרד שצריך לזכור שהוא קיים. */}
          <PricingZonesEditor customerId={customer.id} />
        </>
      )}
    </div>
  )
}

/* ===== one calculator ===================================================== */

function RuleCard({
  customerId,
  taskType,
  rule,
  canEdit,
}: {
  customerId: string
  taskType: TaskType
  rule: { id: string; config: PricingConfig; is_active: boolean } | null
  canEdit: boolean
}) {
  const qc = useQueryClient()
  const toast = useToast()
  const [draft, setDraft] = useState<PricingConfig | null>(null)
  const [open, setOpen] = useState(taskType.code === 'setup')

  const saved = useMemo(() => (rule ? normalizeConfig(rule.config) : null), [rule])
  useEffect(() => setDraft(null), [rule])

  const config = draft ?? saved
  const dirty = draft !== null && JSON.stringify(draft) !== JSON.stringify(saved)

  const save = useMutation({
    mutationFn: async (next: PricingConfig) => {
      const { error } = await supabase
        .from('customer_pricing_rules')
        .upsert(
          { customer_id: customerId, task_type_id: taskType.id, config: next, is_active: true },
          { onConflict: 'customer_id,task_type_id' },
        )
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('המחשבון נשמר')
      setDraft(null)
      void qc.invalidateQueries({ queryKey: ['customer_pricing_rules', customerId] })
      void qc.invalidateQueries({ queryKey: ['workboard'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  // התבנית מגיעה מהשרת ולא מהקליינט, כדי שנוסחת ההתחלה תישאר במקום אחד.
  const createFromTemplate = useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.rpc('pricing_config_template', { p_task_type_id: taskType.id })
      if (error) throw error
      return normalizeConfig(data as PricingConfig)
    },
    onSuccess: (cfg) => {
      setOpen(true)
      save.mutate(cfg)
    },
    onError: (e) => toast.error((e as Error).message),
  })

  if (!config) {
    return (
      <Card>
        <CardHeader title={taskType.name} icon={<Calculator size={ICON.md} strokeWidth={STROKE} />} />
        <CardBody>
          <EmptyState
            art="table"
            title="אין עדיין מחשבון"
            description={`משימות מסוג ${taskType.name} אצל הלקוח הזה לא יקבלו מחיר אוטומטי עד שייבנה מחשבון.`}
            action={
              canEdit ? (
                <Button variant="primary" loading={createFromTemplate.isPending} onClick={() => createFromTemplate.mutate()}>
                  <Plus size={ICON.sm} />
                  צור מחשבון
                </Button>
              ) : undefined
            }
          />
        </CardBody>
      </Card>
    )
  }

  const patch = (p: Partial<PricingConfig>) => setDraft({ ...config, ...p })

  return (
    <Card>
      <CardHeader
        title={taskType.name}
        subtitle={MODEL_LABEL[config.model]}
        icon={<Calculator size={ICON.md} strokeWidth={STROKE} />}
        actions={
          <Button size="sm" variant="ghost" onClick={() => setOpen((v) => !v)}>
            {open ? 'סגירה' : 'עריכה'}
          </Button>
        }
      />
      {open && (
        <>
          <CardBody className="space-y-5">
            <Field label="מודל חישוב" hint={MODEL_HINT[config.model]}>
              <Select
                value={config.model}
                disabled={!canEdit}
                onChange={(e) => {
                  const model = e.target.value as PricingModel
                  setDraft(normalizeConfig({ ...config, model }))
                }}
              >
                {(Object.keys(MODEL_LABEL) as PricingModel[]).map((m) => (
                  <option key={m} value={m}>
                    {MODEL_LABEL[m]}
                  </option>
                ))}
              </Select>
            </Field>

            {config.model === 'worker_hours' ? (
              <WorkerHoursEditor config={config} onChange={patch} canEdit={canEdit} />
            ) : (
              <LineItemsEditor config={config} onChange={patch} canEdit={canEdit} />
            )}

            <MultipliersEditor config={config} onChange={patch} canEdit={canEdit} />
            <TailEditor config={config} onChange={patch} canEdit={canEdit} />
          </CardBody>

          <PreviewPanel config={config} />

          {canEdit && (
            <StickySaveBar
              dirty={dirty}
              saving={save.isPending}
              onSave={() => draft && save.mutate(draft)}
              onReset={() => setDraft(null)}
            />
          )}
        </>
      )}
    </Card>
  )
}

/* ===== shared bits ======================================================== */

/** מספר או ריק. שומר על '' ולא הופך אותו ל-0, כדי שמחיקת התוכן לא תקפיץ אפס. */
function NumField({
  label,
  value,
  onChange,
  disabled,
  suffix,
  step = 'any',
  className,
}: {
  label: string
  value: number | null | undefined
  onChange: (v: number | null) => void
  disabled?: boolean
  suffix?: string
  step?: string
  className?: string
}) {
  return (
    <Field label={label} className={className}>
      <Input
        type="number"
        step={step}
        inputMode="decimal"
        dir="ltr"
        disabled={disabled}
        value={value ?? ''}
        trailing={suffix ? <span className="type-caption text-ink-tertiary">{suffix}</span> : undefined}
        onChange={(e) => onChange(e.target.value === '' ? null : Number(e.target.value))}
      />
    </Field>
  )
}

function VarSelect({
  label,
  value,
  onChange,
  disabled,
  numeric = true,
}: {
  label: string
  value: string | undefined
  onChange: (v: string) => void
  disabled?: boolean
  numeric?: boolean
}) {
  const options = numeric ? NUMBER_VARS : PRICING_VARS
  const def = PRICING_VARS.find((v) => v.key === value)
  return (
    <Field label={label} hint={def?.source}>
      <Select value={value ?? ''} disabled={disabled} onChange={(e) => onChange(e.target.value)}>
        <option value="">— בחרו נתון —</option>
        {options.map((v) => (
          <option key={v.key} value={v.key}>
            {v.label}
            {v.unit ? ` (${v.unit})` : ''}
          </option>
        ))}
      </Select>
    </Field>
  )
}

/**
 * עורך התנאי. מכוון בכוונה לצורה אחת בלבד — "כל התנאים מתקיימים" על שדות
 * בוליאניים — כי זו הצורה היחידה שעלתה בשטח, ותיבת סימון היא ממשק שאפשר
 * להשתמש בו. המנוע תומך ב-any, בהשוואות מספריות ובקינון; קונפיג שמגיע עם
 * תנאי מורכב יותר נשמר כפי שהוא ומוצג כאן כטקסט בלבד, ולא נדרס.
 */
function CondEditor({
  when,
  onChange,
  disabled,
}: {
  when: PriceCond | undefined
  onChange: (c: PriceCond) => void
  disabled?: boolean
}) {
  const tests = when && typeof when === 'object' && 'all' in when ? when.all : []
  const simple = !when || (typeof when === 'object' && 'all' in when)
  const active = new Set(tests.filter((t) => t.op === 'is_true').map((t) => t.field))

  if (!simple) {
    return (
      <p className="type-caption text-ink-tertiary">
        תנאי מותאם אישית — נשמר כפי שהוא. לעריכה שלו יש לפנות למי שהגדיר אותו.
      </p>
    )
  }

  return (
    <div className="flex flex-wrap gap-x-4 gap-y-1.5">
      {BOOLEAN_VARS.map((v) => (
        <Checkbox
          key={v.key}
          label={v.label}
          disabled={disabled}
          checked={active.has(v.key)}
          onChange={(on) => {
            const next = on
              ? [...tests, { field: v.key, op: 'is_true' as const }]
              : tests.filter((t) => t.field !== v.key)
            onChange(next.length ? { all: next } : null)
          }}
        />
      ))}
    </div>
  )
}

function RowShell({
  title,
  index,
  count,
  onMove,
  onRemove,
  disabled,
  children,
}: {
  title: React.ReactNode
  index: number
  count: number
  onMove: (to: number) => void
  onRemove: () => void
  disabled?: boolean
  children: React.ReactNode
}) {
  return (
    <li className="rounded-xl border border-line-subtle bg-subtle/30 p-3">
      <div className="mb-2 flex items-center gap-2">
        <span className="min-w-0 flex-1">{title}</span>
        {!disabled && (
          <>
            <IconButton label="העברה למעלה" size="sm" disabled={index === 0} onClick={() => onMove(index - 1)}>
              <ArrowUp size={ICON.sm} />
            </IconButton>
            <IconButton label="העברה למטה" size="sm" disabled={index === count - 1} onClick={() => onMove(index + 1)}>
              <ArrowDown size={ICON.sm} />
            </IconButton>
            <IconButton label="מחיקה" size="sm" variant="ghost" onClick={onRemove}>
              <Trash2 size={ICON.sm} className="text-error" />
            </IconButton>
          </>
        )}
      </div>
      {children}
    </li>
  )
}

/** אילו שדות לצייר לפי הסוג שנבחר — מונע כפילות בין שלושת העורכים. */
function KindFields({
  fields,
  item,
  onPatch,
  disabled,
}: {
  fields: FieldName[]
  item: Record<string, unknown>
  onPatch: (p: Record<string, unknown>) => void
  disabled?: boolean
}) {
  const num = (k: string) => (item[k] as number | undefined) ?? null
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {fields.includes('input') && (
        <VarSelect
          label="נתון"
          value={item.input as string | undefined}
          disabled={disabled}
          onChange={(v) => onPatch({ input: v })}
        />
      )}
      {fields.includes('hours') && (
        <NumField label="שעות" suffix="ש׳" value={num('hours')} disabled={disabled} onChange={(v) => onPatch({ hours: v ?? 0 })} />
      )}
      {fields.includes('multiplier') && (
        <NumField
          label="מכפיל"
          value={num('multiplier')}
          disabled={disabled}
          onChange={(v) => onPatch({ multiplier: v ?? 1 })}
        />
      )}
      {fields.includes('first') && (
        <NumField label="הראשון" suffix="ש׳" value={num('first')} disabled={disabled} onChange={(v) => onPatch({ first: v ?? 0 })} />
      )}
      {fields.includes('each_additional') && (
        <NumField
          label="כל נוסף"
          suffix="ש׳"
          value={num('each_additional')}
          disabled={disabled}
          onChange={(v) => onPatch({ each_additional: v ?? 0 })}
        />
      )}
      {fields.includes('amount') && (
        <NumField
          label="סכום"
          suffix={item.amount_kind === 'percent' || item.kind === 'percent' ? '%' : '₪'}
          value={num('amount')}
          disabled={disabled}
          onChange={(v) => onPatch({ amount: v ?? 0 })}
        />
      )}
      {fields.includes('amount_kind') && (
        <Field label="סוג הסכום">
          <Select
            value={(item.amount_kind as string) ?? 'fixed'}
            disabled={disabled}
            onChange={(e) => onPatch({ amount_kind: e.target.value })}
          >
            <option value="fixed">סכום בשקלים</option>
            <option value="percent">אחוז ממה שנצבר</option>
          </Select>
        </Field>
      )}
      {fields.includes('rate') && (
        <NumField label="תעריף ליחידה" suffix="₪" value={num('rate')} disabled={disabled} onChange={(v) => onPatch({ rate: v ?? 0 })} />
      )}
      {fields.includes('included_units') && (
        <NumField
          label="יחידות כלולות"
          value={num('included_units')}
          disabled={disabled}
          onChange={(v) => onPatch({ included_units: v ?? 0 })}
        />
      )}
      {fields.includes('workers_basis') && (
        <Field label="לפי אילו עובדים" hint="למשל סבלות שנספרת לפי מי שהוזמן ולא לפי תוספת החניה">
          <Select
            value={(item.workers_basis as string) ?? 'effective'}
            disabled={disabled}
            onChange={(e) => onPatch({ workers_basis: e.target.value })}
          >
            {Object.entries(WORKERS_BASIS_LABEL).map(([k, label]) => (
              <option key={k} value={k}>
                {label}
              </option>
            ))}
          </Select>
        </Field>
      )}
      {fields.includes('tiers') && (
        <div className="sm:col-span-2">
          <TiersEditor
            tiers={(item.tiers as PricingTier[]) ?? []}
            mode={(item.mode as 'flat' | 'progressive') ?? 'flat'}
            disabled={disabled}
            onChange={(tiers, mode) => onPatch({ tiers, mode })}
          />
        </div>
      )}
    </div>
  )
}

function TiersEditor({
  tiers,
  mode,
  onChange,
  disabled,
}: {
  tiers: PricingTier[]
  mode: 'flat' | 'progressive'
  onChange: (tiers: PricingTier[], mode: 'flat' | 'progressive') => void
  disabled?: boolean
}) {
  const flat = mode === 'flat'
  return (
    <div className="space-y-2">
      <Field label="סוג המדרגות" hint={flat ? 'המדרגה שהכמות נופלת בתוכה קובעת מחיר אחד' : 'כל מדרגה מתומחרת על החלק שלה'}>
        <SegmentedControl
          items={[
            { key: 'flat' as const, label: 'מחיר למדרגה' },
            { key: 'progressive' as const, label: 'מדורג לפי פרוסות' },
          ]}
          value={mode}
          onChange={(m) => !disabled && onChange(tiers, m)}
          className={disabled ? 'pointer-events-none opacity-55' : undefined}
        />
      </Field>
      <ul className="space-y-2">
        {tiers.map((t, i) => (
          <li key={i} className="flex items-end gap-2">
            <NumField
              label={i === 0 ? 'עד' : ''}
              value={t.up_to}
              disabled={disabled}
              className="flex-1"
              onChange={(v) => onChange(tiers.map((x, j) => (j === i ? { ...x, up_to: v } : x)), mode)}
            />
            <NumField
              label={i === 0 ? (flat ? 'מחיר' : 'תעריף ליחידה') : ''}
              suffix="₪"
              value={flat ? (t.amount ?? null) : (t.rate ?? null)}
              disabled={disabled}
              className="flex-1"
              onChange={(v) =>
                onChange(tiers.map((x, j) => (j === i ? { ...x, [flat ? 'amount' : 'rate']: v ?? 0 } : x)), mode)
              }
            />
            {!disabled && (
              <IconButton label="מחיקת מדרגה" size="sm" className="mb-1" onClick={() => onChange(tiers.filter((_, j) => j !== i), mode)}>
                <Trash2 size={ICON.sm} className="text-error" />
              </IconButton>
            )}
          </li>
        ))}
      </ul>
      {!disabled && (
        <Button size="sm" variant="ghost" onClick={() => onChange([...tiers, { up_to: null, amount: 0, rate: 0 }], mode)}>
          <Plus size={ICON.sm} />
          מדרגה
        </Button>
      )}
      <p className="type-caption text-ink-tertiary">מדרגה בלי ״עד״ היא הפתוחה — כל מה שמעל הקודמת.</p>
    </div>
  )
}

/* ===== worker_hours ======================================================= */

function WorkerHoursEditor({
  config,
  onChange,
  canEdit,
}: {
  config: PricingConfig
  onChange: (p: Partial<PricingConfig>) => void
  canEdit: boolean
}) {
  const hours = config.hours ?? []
  const after = config.after_workers ?? []
  const adjustments = config.workers?.adjustments ?? []
  const constants = (config.constants ?? {}) as Record<string, unknown>

  return (
    <div className="space-y-5">
      {/* ── רכיבי הזמן ── */}
      <section className="space-y-2">
        <SectionTitle icon={<Clock size={ICON.sm} />} title="רכיבי זמן" hint="הכול נסכם לשעות, ואז מוכפל בתעריף" />
        <ul className="space-y-2">
          {hours.map((h, i) => {
            const def = HOUR_KINDS.find((k) => k.kind === h.kind) ?? HOUR_KINDS[0]
            const patch = (p: Partial<PricingHourComponent>) =>
              onChange({ hours: hours.map((x, j) => (j === i ? { ...x, ...p } : x)) })
            return (
              <RowShell
                key={h.id}
                index={i}
                count={hours.length}
                disabled={!canEdit}
                onMove={(to) => onChange({ hours: moveItem(hours, i, to) })}
                onRemove={() => onChange({ hours: hours.filter((_, j) => j !== i) })}
                title={
                  <Input
                    value={h.label}
                    disabled={!canEdit}
                    placeholder="שם הרכיב"
                    onChange={(e) => patch({ label: e.target.value })}
                  />
                }
              >
                <div className="grid gap-3 sm:grid-cols-2">
                  <Field label="סוג" hint={def.hint}>
                    <Select
                      value={h.kind}
                      disabled={!canEdit}
                      onChange={(e) => patch({ kind: e.target.value as PricingHourComponent['kind'] })}
                    >
                      {HOUR_KINDS.map((k) => (
                        <option key={k.kind} value={k.kind}>
                          {k.label}
                        </option>
                      ))}
                    </Select>
                  </Field>
                </div>
                <div className="mt-3">
                  <KindFields
                    fields={def.fields}
                    item={h as unknown as Record<string, unknown>}
                    disabled={!canEdit}
                    onPatch={(p) => patch(p as Partial<PricingHourComponent>)}
                  />
                </div>
              </RowShell>
            )
          })}
        </ul>
        {canEdit && (
          <Button
            size="sm"
            variant="ghost"
            onClick={() =>
              onChange({ hours: [...hours, { id: newId('h'), label: 'רכיב זמן', kind: 'const', hours: 0 }] })
            }
          >
            <Plus size={ICON.sm} />
            רכיב זמן
          </Button>
        )}
      </section>

      {/* ── תעריף ── */}
      <section className="grid gap-3 sm:grid-cols-2">
        <NumField
          label="תעריף לשעה"
          suffix="₪"
          value={config.hour_rate ?? null}
          disabled={!canEdit}
          onChange={(v) => onChange({ hour_rate: v ?? 0 })}
        />
        <NumField
          label="תוספת קבועה לעובד"
          suffix="₪"
          value={config.per_worker_fee ?? null}
          disabled={!canEdit}
          onChange={(v) => onChange({ per_worker_fee: v ?? 0 })}
        />
      </section>

      {/* ── עובדים ── */}
      <section className="space-y-2">
        <SectionTitle icon={<Users size={ICON.sm} />} title="כמות עובדים" hint="המחיר לעובד מוכפל בכמות הזו" />
        <VarSelect
          label="נתון הבסיס"
          value={config.workers?.input ?? 'worker_count'}
          disabled={!canEdit}
          onChange={(v) => onChange({ workers: { input: v, adjustments } })}
        />
        <ul className="space-y-2">
          {adjustments.map((a, i) => {
            const patch = (p: Partial<PricingWorkerAdjustment>) =>
              onChange({
                workers: {
                  input: config.workers?.input ?? 'worker_count',
                  adjustments: adjustments.map((x, j) => (j === i ? { ...x, ...p } : x)),
                },
              })
            return (
              <RowShell
                key={a.id}
                index={i}
                count={adjustments.length}
                disabled={!canEdit}
                onMove={(to) =>
                  onChange({
                    workers: { input: config.workers?.input ?? 'worker_count', adjustments: moveItem(adjustments, i, to) },
                  })
                }
                onRemove={() =>
                  onChange({
                    workers: {
                      input: config.workers?.input ?? 'worker_count',
                      adjustments: adjustments.filter((_, j) => j !== i),
                    },
                  })
                }
                title={
                  <Input value={a.label} disabled={!canEdit} placeholder="שם התוספת" onChange={(e) => patch({ label: e.target.value })} />
                }
              >
                <NumField label="עובדים להוספה" value={a.add} disabled={!canEdit} onChange={(v) => patch({ add: v ?? 0 })} />
                <div className="mt-3">
                  <Field label="רק כאשר">
                    <CondEditor when={a.when} disabled={!canEdit} onChange={(c) => patch({ when: c })} />
                  </Field>
                </div>
              </RowShell>
            )
          })}
        </ul>
        {canEdit && (
          <Button
            size="sm"
            variant="ghost"
            onClick={() =>
              onChange({
                workers: {
                  input: config.workers?.input ?? 'worker_count',
                  adjustments: [...adjustments, { id: newId('w'), label: 'תוספת עובד', add: 1, when: null }],
                },
              })
            }
          >
            <Plus size={ICON.sm} />
            תוספת עובדים
          </Button>
        )}
      </section>

      {/* ── תוספות ── */}
      <section className="space-y-2">
        <SectionTitle
          icon={<Banknote size={ICON.sm} />}
          title="תוספות"
          hint="מתווספות אחרי ההכפלה בכמות העובדים"
        />
        <ul className="space-y-2">
          {after.map((a, i) => {
            const def = AFTER_KINDS.find((k) => k.kind === a.kind) ?? AFTER_KINDS[0]
            const patch = (p: Partial<PricingAfterWorkers>) =>
              onChange({ after_workers: after.map((x, j) => (j === i ? { ...x, ...p } : x)) })
            return (
              <RowShell
                key={a.id}
                index={i}
                count={after.length}
                disabled={!canEdit}
                onMove={(to) => onChange({ after_workers: moveItem(after, i, to) })}
                onRemove={() => onChange({ after_workers: after.filter((_, j) => j !== i) })}
                title={
                  <Input value={a.label} disabled={!canEdit} placeholder="שם התוספת" onChange={(e) => patch({ label: e.target.value })} />
                }
              >
                <div className="grid gap-3 sm:grid-cols-2">
                  <Field label="סוג" hint={def.hint}>
                    <Select
                      value={a.kind}
                      disabled={!canEdit}
                      onChange={(e) => patch({ kind: e.target.value as PricingAfterWorkers['kind'] })}
                    >
                      {AFTER_KINDS.map((k) => (
                        <option key={k.kind} value={k.kind}>
                          {k.label}
                        </option>
                      ))}
                    </Select>
                  </Field>
                </div>
                <div className="mt-3">
                  <KindFields
                    fields={def.fields}
                    item={a as unknown as Record<string, unknown>}
                    disabled={!canEdit}
                    onPatch={(p) => patch(p as Partial<PricingAfterWorkers>)}
                  />
                </div>
                <div className="mt-3">
                  <Field label="רק כאשר">
                    <CondEditor when={a.when} disabled={!canEdit} onChange={(c) => patch({ when: c })} />
                  </Field>
                </div>
              </RowShell>
            )
          })}
        </ul>
        {canEdit && (
          <Button
            size="sm"
            variant="ghost"
            onClick={() => onChange({ after_workers: [...after, { id: newId('a'), label: 'תוספת', kind: 'fixed', amount: 0, when: null }] })}
          >
            <Plus size={ICON.sm} />
            תוספת
          </Button>
        )}
      </section>

      {/* ── קבועים ── */}
      <section className="space-y-2">
        <SectionTitle
          icon={<Info size={ICON.sm} />}
          title="קבועים"
          hint="ערך ברירת מחדל למשתנה שאין לו שדה. דריסה על משימה בודדת גוברת עליו."
        />
        <div className="flex flex-wrap gap-x-4 gap-y-1.5">
          {BOOLEAN_VARS.filter((v) => v.source === 'קבוע במחשבון').map((v) => (
            <Checkbox
              key={v.key}
              label={v.label}
              disabled={!canEdit}
              checked={constants[v.key] === true}
              onChange={(on) => onChange({ constants: { ...constants, [v.key]: on } })}
            />
          ))}
        </div>
      </section>
    </div>
  )
}

/* ===== line_items ========================================================= */

function LineItemsEditor({
  config,
  onChange,
  canEdit,
}: {
  config: PricingConfig
  onChange: (p: Partial<PricingConfig>) => void
  canEdit: boolean
}) {
  const items = config.components ?? []
  return (
    <section className="space-y-2">
      <SectionTitle icon={<Banknote size={ICON.sm} />} title="שורות המחיר" hint="נסכמות לפי הסדר" />
      <ul className="space-y-2">
        {items.map((c, i) => {
          const def = COMPONENT_KINDS.find((k) => k.kind === c.kind) ?? COMPONENT_KINDS[0]
          const patch = (p: Partial<PricingComponent>) =>
            onChange({ components: items.map((x, j) => (j === i ? { ...x, ...p } : x)) })
          return (
            <RowShell
              key={c.id}
              index={i}
              count={items.length}
              disabled={!canEdit}
              onMove={(to) => onChange({ components: moveItem(items, i, to) })}
              onRemove={() => onChange({ components: items.filter((_, j) => j !== i) })}
              title={
                <Input value={c.label} disabled={!canEdit} placeholder="שם השורה" onChange={(e) => patch({ label: e.target.value })} />
              }
            >
              <div className="grid gap-3 sm:grid-cols-2">
                <Field label="סוג" hint={def.hint}>
                  <Select
                    value={c.kind}
                    disabled={!canEdit}
                    onChange={(e) => patch({ kind: e.target.value as PricingComponent['kind'] })}
                  >
                    {COMPONENT_KINDS.map((k) => (
                      <option key={k.kind} value={k.kind}>
                        {k.label}
                      </option>
                    ))}
                  </Select>
                </Field>
              </div>
              <div className="mt-3">
                <KindFields
                  fields={def.fields}
                  item={c as unknown as Record<string, unknown>}
                  disabled={!canEdit}
                  onPatch={(p) => patch(p as Partial<PricingComponent>)}
                />
              </div>
              <div className="mt-3">
                <Field label="רק כאשר">
                  <CondEditor when={c.when} disabled={!canEdit} onChange={(w) => patch({ when: w })} />
                </Field>
              </div>
            </RowShell>
          )
        })}
      </ul>
      {canEdit && (
        <Button
          size="sm"
          variant="ghost"
          onClick={() => onChange({ components: [...items, { id: newId('c'), label: 'שורה', kind: 'fixed', amount: 0, when: null }] })}
        >
          <Plus size={ICON.sm} />
          שורה
        </Button>
      )}
    </section>
  )
}

/* ===== tail =============================================================== */

function MultipliersEditor({
  config,
  onChange,
  canEdit,
}: {
  config: PricingConfig
  onChange: (p: Partial<PricingConfig>) => void
  canEdit: boolean
}) {
  const list = config.multipliers ?? []
  return (
    <section className="space-y-2">
      <SectionTitle
        icon={<RefreshCw size={ICON.sm} />}
        title="מקדמים"
        hint="מוכפלים בזה אחר זה — ×1.3 ואז ×1.2 אינו ×1.5"
      />
      <ul className="space-y-2">
        {list.map((m, i) => {
          const patch = (p: Partial<PricingMultiplier>) =>
            onChange({ multipliers: list.map((x, j) => (j === i ? { ...x, ...p } : x)) })
          return (
            <RowShell
              key={m.id}
              index={i}
              count={list.length}
              disabled={!canEdit}
              onMove={(to) => onChange({ multipliers: moveItem(list, i, to) })}
              onRemove={() => onChange({ multipliers: list.filter((_, j) => j !== i) })}
              title={<Input value={m.label} disabled={!canEdit} placeholder="שם המקדם" onChange={(e) => patch({ label: e.target.value })} />}
            >
              <NumField label="מקדם" value={m.factor} disabled={!canEdit} onChange={(v) => patch({ factor: v ?? 1 })} />
            </RowShell>
          )
        })}
      </ul>
      {canEdit && (
        <Button
          size="sm"
          variant="ghost"
          onClick={() => onChange({ multipliers: [...list, { id: newId('m'), label: 'מקדם', factor: 1 }] })}
        >
          <Plus size={ICON.sm} />
          מקדם
        </Button>
      )}
    </section>
  )
}

function TailEditor({
  config,
  onChange,
  canEdit,
}: {
  config: PricingConfig
  onChange: (p: Partial<PricingConfig>) => void
  canEdit: boolean
}) {
  return (
    <section className="grid gap-3 sm:grid-cols-2">
      <NumField
        label="מחיר מינימום"
        suffix="₪"
        value={config.min_price ?? null}
        disabled={!canEdit}
        onChange={(v) => onChange({ min_price: v })}
      />
      <NumField
        label="מחיר מקסימום"
        suffix="₪"
        value={config.max_price ?? null}
        disabled={!canEdit}
        onChange={(v) => onChange({ max_price: v })}
      />
      <Field label="עיגול">
        <Select
          value={config.rounding?.mode ?? 'nearest'}
          disabled={!canEdit}
          onChange={(e) =>
            onChange({ rounding: { mode: e.target.value as 'nearest' | 'up' | 'down', to: config.rounding?.to ?? 1 } })
          }
        >
          {Object.entries(ROUNDING_LABEL).map(([k, label]) => (
            <option key={k} value={k}>
              {label}
            </option>
          ))}
        </Select>
      </Field>
      <NumField
        label="עיגול לכפולות של"
        suffix="₪"
        value={config.rounding?.to ?? 1}
        disabled={!canEdit}
        onChange={(v) => onChange({ rounding: { mode: config.rounding?.mode ?? 'nearest', to: v ?? 0 } })}
      />
    </section>
  )
}

function SectionTitle({ icon, title, hint }: { icon: React.ReactNode; title: string; hint?: string }) {
  return (
    <div>
      <h4 className="flex items-center gap-1.5 type-body font-semibold">
        <span className="text-ink-tertiary" aria-hidden>
          {icon}
        </span>
        {title}
      </h4>
      {hint && <p className="type-caption text-ink-tertiary">{hint}</p>}
    </div>
  )
}

/* ===== live preview ======================================================= */

/**
 * מריץ את הקונפיג שעל המסך — כולל שינויים שעוד לא נשמרו — מול המנוע האמיתי.
 * ה-debounce קצר בכוונה: הערך של הכלי הזה הוא שהמספר זז בזמן שמקלידים.
 */
function PreviewPanel({ config }: { config: PricingConfig }) {
  const [vars, setVars] = useState<Record<string, number | boolean>>(PREVIEW_DEFAULTS)
  const [debounced, setDebounced] = useState({ config, vars })

  useEffect(() => {
    const t = setTimeout(() => setDebounced({ config, vars }), 350)
    return () => clearTimeout(t)
  }, [config, vars])

  const { data, isFetching, error } = useQuery({
    queryKey: ['preview_task_price', debounced],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('preview_task_price', {
        p_config: debounced.config,
        p_vars: debounced.vars,
      })
      if (error) throw error
      return data as PriceBreakdown
    },
  })

  return (
    <div className="border-t border-line-subtle bg-subtle/30 p-4">
      <SectionTitle icon={<Calculator size={ICON.sm} />} title="בדיקה" hint="נתוני דוגמה, מחושבים במנוע האמיתי" />

      <div className="mt-3 grid gap-3 sm:grid-cols-3">
        {NUMBER_VARS.filter((v) => v.key !== 'worker_hours').map((v) => (
          <NumField
            key={v.key}
            label={v.label}
            suffix={v.unit}
            value={(vars[v.key] as number) ?? 0}
            onChange={(n) => setVars((s) => ({ ...s, [v.key]: n ?? 0 }))}
          />
        ))}
      </div>
      <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1.5">
        {BOOLEAN_VARS.map((v) => (
          <Checkbox
            key={v.key}
            label={v.label}
            checked={vars[v.key] === true}
            onChange={(on) => setVars((s) => ({ ...s, [v.key]: on }))}
          />
        ))}
      </div>

      <div className="mt-4">
        {error ? (
          <p className="type-caption text-error">{(error as Error).message}</p>
        ) : !data ? (
          <Skeleton className="h-24 w-full" />
        ) : (
          <Breakdown breakdown={data} muted={isFetching} />
        )}
      </div>
    </div>
  )
}

/**
 * הפירוט. שורות הכסף נסכמות תמיד לסך הכול לפני העיגול — גם המקדמים נרשמים
 * כתוספת ולא כמכפלה — כדי שמי שקורא יוכל לעקוב אחרי החשבון ולא רק לקבל אותו.
 */
export function Breakdown({ breakdown, muted }: { breakdown: PriceBreakdown; muted?: boolean }) {
  const money = breakdown.lines.filter((l) => l.amount !== null)
  return (
    <div className={muted ? 'opacity-60 transition-opacity' : 'transition-opacity'}>
      {breakdown.model === 'worker_hours' && breakdown.hour_lines.length > 0 && (
        <div className="mb-3 rounded-lg bg-canvas p-2.5">
          <div className="mb-1 flex items-center justify-between type-caption text-ink-tertiary">
            <span>רכיבי זמן</span>
            <span>{fmtHoursShort(breakdown.hours)}</span>
          </div>
          <ul className="space-y-0.5">
            {breakdown.hour_lines.map((l, i) => (
              <li key={l.id ?? i} className="flex items-center justify-between type-caption">
                <span className="text-ink-secondary">{l.label}</span>
                <span dir="ltr" className="tabular-nums">
                  {fmtHoursShort(l.hours)}
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}

      <ul className="space-y-1">
        {money.map((l, i) => (
          <li key={l.id ?? i} className="flex items-baseline justify-between gap-3 type-body">
            <span className="min-w-0">
              <span className="text-ink-secondary">{l.label}</span>
              {l.detail && <span className="ms-1.5 type-caption text-ink-tertiary">{l.detail}</span>}
            </span>
            <span dir="ltr" className="shrink-0 tabular-nums">
              {fmtMoney(l.amount)}
            </span>
          </li>
        ))}
      </ul>

      <div className="mt-2 flex items-baseline justify-between border-t border-line-subtle pt-2">
        <span className="type-body font-semibold">סך הכול</span>
        <span dir="ltr" className="type-title tabular-nums font-semibold">
          {fmtMoney(breakdown.total)}
        </span>
      </div>

      {breakdown.model === 'worker_hours' && (
        <p className="mt-1 type-caption text-ink-tertiary">
          {fmtHoursShort(breakdown.hours)} · {fmtMoney(breakdown.per_worker)} לעובד · {breakdown.workers} עובדים
          {breakdown.workers !== breakdown.base_workers && ` (מתוכם ${breakdown.base_workers} שהוזמנו)`}
        </p>
      )}
    </div>
  )
}

export function PriceBadge({ isManual }: { isManual: boolean }) {
  return isManual ? <Badge tone="warning">ידני</Badge> : <Badge tone="neutral">חושב אוטומטית</Badge>
}
