/**
 * עורך אזורי הנסיעה.
 *
 * זמן הנסיעה בנוסחת התמחור אינו מוזן ידנית לכל אירוע — הוא נגזר מהמיקום
 * שהלקוח בחר. המסך הזה הוא המקום שבו נקבע מה זה אומר: משרטטים אזור על
 * המפה, וכל אירוע שנופל בתוכו מקבל את זמן הנסיעה שלו.
 *
 * אותו רכיב משרת את שתי הרמות. customerId=null מנהל את האזורים הגלובליים
 * (בהגדרות), ו-customerId מנהל אזורים פרטיים ללקוח שגוברים עליהם. הגלובליים
 * מוצגים גם במסך הלקוח, מקווקווים ולקריאה בלבד, כדי שיהיה ברור מה כבר חל
 * לפני שמציירים עוד אזור.
 */
import { useMemo, useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Circle, ICON, Map as MapIcon, Pentagon, Plus, STROKE, Trash2 } from '../../components/ui/icons'
import {
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  Field,
  IconButton,
  Input,
  SegmentedControl,
  Skeleton,
  Switch,
  fmtMoney,
  useConfirm,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { usePricingZones } from '../../lib/queries'
import { ZoneMap } from './ZoneMap'
import type { DraftShape } from './ZoneMap'
import type { PricingZone } from '../../types/domain'
import { errorMessage } from '../../lib/errors'

const SHAPES = [
  { key: 'polygon' as const, label: 'פוליגון', icon: <Pentagon size={ICON.xs} /> },
  { key: 'circle' as const, label: 'עיגול', icon: <Circle size={ICON.xs} /> },
]

interface DraftMeta {
  name: string
  travel_hours: string
  surcharge: string
  priority: string
  color: string
}

const EMPTY_META: DraftMeta = { name: '', travel_hours: '0.5', surcharge: '0', priority: '100', color: '#3563f0' }

export function PricingZonesEditor({ customerId }: { customerId: string | null }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const { has } = useAuth()
  const canEdit = has(PERM.PRICING_MANAGE_RULES)

  const { data: zones = [], isLoading } = usePricingZones(customerId)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [draft, setDraft] = useState<DraftShape | null>(null)
  const [meta, setMeta] = useState<DraftMeta>(EMPTY_META)

  const invalidate = () => {
    void qc.invalidateQueries({ queryKey: ['pricing_zones'] })
    void qc.invalidateQueries({ queryKey: ['workboard'] })
  }

  const create = useMutation({
    mutationFn: async () => {
      if (!draft) throw new Error('אין אזור לשמור')
      if (!meta.name.trim()) throw new Error('חובה לתת שם לאזור')
      const common = {
        customer_id: customerId,
        name: meta.name.trim(),
        travel_hours: Number(meta.travel_hours) || 0,
        surcharge: Number(meta.surcharge) || 0,
        priority: Number(meta.priority) || 100,
        color: meta.color,
      }
      // גאומטריית פוליגון ועיגול הן שתי צורות זרות; ה-check ב-pricing_zones
      // דורש שרק אחת מהן תהיה מלאה, ולכן השדות של השנייה נשלחים ריקים ולא
      // נשמטים — כדי שהחלפת צורה על אזור קיים לא תשאיר שאריות.
      const row: Record<string, unknown> = { ...common, shape: draft.shape }
      if (draft.shape === 'polygon') {
        if (draft.points.length < 3) throw new Error('פוליגון דורש לפחות שלוש נקודות')
        row.points = draft.points
      } else {
        if (!draft.center) throw new Error('יש ללחוץ על המפה כדי לקבוע מרכז')
        if (!draft.radius_km) throw new Error('חובה לקבוע רדיוס')
        row.center_lat = draft.center[0]
        row.center_lng = draft.center[1]
        row.radius_km = draft.radius_km
      }
      const { error } = await supabase.from('pricing_zones').insert(row)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('האזור נשמר')
      setDraft(null)
      setMeta(EMPTY_META)
      invalidate()
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const patch = useMutation({
    mutationFn: async ({ id, values }: { id: string; values: Partial<PricingZone> }) => {
      const { error } = await supabase.from('pricing_zones').update(values).eq('id', id)
      if (error) throw error
    },
    onSuccess: invalidate,
    onError: (e) => toast.error(errorMessage(e)),
  })

  // עדכון ישיר ולא soft_delete: הפוליסה pz_write כבר דורשת
  // pricing.manage_rules, ו-soft_delete הייתה מחייבת להוסיף את הטבלה לרשימה
  // שבתוכה — פונקציה שכבר הוגדרה מחדש שלוש פעמים לאורך המיגרציות.
  const remove = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('pricing_zones').update({ deleted_at: new Date().toISOString() }).eq('id', id)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('האזור נמחק')
      setSelectedId(null)
      invalidate()
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  // אזור של הלקוח ניתן לעריכה כאן; אזור גלובלי מוצג לצורך הקשר בלבד, כדי
  // שלא יערכו מהמסך של לקוח אחד משהו שחל על כולם.
  const { own, inherited } = useMemo(
    () => ({
      own: zones.filter((z) => z.customer_id === customerId),
      inherited: customerId ? zones.filter((z) => z.customer_id === null) : [],
    }),
    [zones, customerId],
  )

  return (
    <Card>
      {dialog}
      <CardHeader
        title="אזורי נסיעה"
        subtitle={
          customerId
            ? 'אזור של הלקוח גובר על אזור גלובלי. זמן הנסיעה נכנס לנוסחת התמחור.'
            : 'ברירת המחדל לכל הלקוחות. אזור ספציפי בהגדרות לקוח גובר עליה.'
        }
        icon={<MapIcon size={ICON.md} strokeWidth={STROKE} />}
        actions={
          canEdit &&
          !draft && (
            <Button size="sm" variant="primary" onClick={() => setDraft({ shape: 'polygon', points: [] })}>
              <Plus size={ICON.sm} />
              אזור חדש
            </Button>
          )
        }
      />

      <CardBody padded={false}>
        {isLoading ? (
          <Skeleton className="h-96 w-full" />
        ) : (
          <ZoneMap
            zones={zones}
            selectedId={selectedId}
            draft={draft}
            onDraftChange={setDraft}
            onSelect={setSelectedId}
            className="h-[380px] w-full"
          />
        )}
      </CardBody>

      {draft && (
        <div className="border-t border-line-subtle bg-warning-subtle/40 p-4">
          <div className="mb-3 flex flex-wrap items-center gap-3">
            <SegmentedControl
              items={SHAPES}
              value={draft.shape}
              onChange={(s) =>
                setDraft(s === 'polygon' ? { shape: 'polygon', points: [] } : { shape: 'circle', center: null, radius_km: 10 })
              }
            />
            <span className="type-caption text-ink-tertiary">
              {draft.shape === 'polygon'
                ? `לחיצה על המפה מוסיפה נקודה · ${draft.points.length} נקודות`
                : draft.center
                  ? 'לחיצה נוספת מזיזה את המרכז'
                  : 'לחצו על המפה כדי לקבוע מרכז'}
            </span>
            {draft.shape === 'polygon' && draft.points.length > 0 && (
              <Button size="sm" variant="ghost" onClick={() => setDraft({ ...draft, points: draft.points.slice(0, -1) })}>
                בטל נקודה אחרונה
              </Button>
            )}
          </div>

          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <Field label="שם האזור" required>
              <Input value={meta.name} onChange={(e) => setMeta({ ...meta, name: e.target.value })} placeholder="גוש דן" />
            </Field>
            <Field label="זמן נסיעה (ש׳)" hint="כיוון אחד — הנוסחה מכפילה ב-2">
              <Input
                type="number"
                step="0.25"
                min="0"
                dir="ltr"
                value={meta.travel_hours}
                onChange={(e) => setMeta({ ...meta, travel_hours: e.target.value })}
              />
            </Field>
            <Field label="תוספת לאזור (₪)" hint="אופציונלי, נכנס רק אם המחשבון מפנה אליו">
              <Input
                type="number"
                step="any"
                dir="ltr"
                value={meta.surcharge}
                onChange={(e) => setMeta({ ...meta, surcharge: e.target.value })}
              />
            </Field>
            {draft.shape === 'circle' ? (
              <Field label="רדיוס (ק״מ)" required>
                <Input
                  type="number"
                  step="0.5"
                  min="0.1"
                  dir="ltr"
                  value={draft.radius_km}
                  onChange={(e) => setDraft({ ...draft, radius_km: Number(e.target.value) })}
                />
              </Field>
            ) : (
              <Field label="עדיפות" hint="נמוך יותר גובר — לאזור קטן בתוך גדול">
                <Input
                  type="number"
                  dir="ltr"
                  value={meta.priority}
                  onChange={(e) => setMeta({ ...meta, priority: e.target.value })}
                />
              </Field>
            )}
          </div>

          <div className="mt-3 flex gap-2">
            <Button variant="primary" loading={create.isPending} onClick={() => create.mutate()}>
              שמירת האזור
            </Button>
            <Button
              variant="ghost"
              onClick={() => {
                setDraft(null)
                setMeta(EMPTY_META)
              }}
            >
              ביטול
            </Button>
          </div>
        </div>
      )}

      <div className="border-t border-line-subtle">
        {own.length === 0 && inherited.length === 0 ? (
          <EmptyState
            art="search"
            compact
            title="אין אזורי נסיעה"
            description={
              customerId
                ? 'בלי אזור, זמן הנסיעה של אירועי הלקוח הזה הוא אפס — אלא אם הוזן ידנית על המשימה.'
                : 'הגדירו אזורים כדי שזמן הנסיעה ייגזר מהמיקום במקום להיות מוזן ידנית.'
            }
          />
        ) : (
          <ul>
            {own.map((z) => (
              <ZoneRow
                key={z.id}
                zone={z}
                selected={z.id === selectedId}
                canEdit={canEdit}
                onSelect={() => setSelectedId(z.id)}
                onPatch={(values) => patch.mutate({ id: z.id, values })}
                onRemove={async () => {
                  if (await confirm(`למחוק את האזור "${z.name}"?`, { title: 'מחיקת אזור', confirmLabel: 'מחיקה' }))
                    remove.mutate(z.id)
                }}
              />
            ))}
            {inherited.map((z) => (
              <ZoneRow key={z.id} zone={z} selected={z.id === selectedId} canEdit={false} inherited onSelect={() => setSelectedId(z.id)} />
            ))}
          </ul>
        )}
      </div>
    </Card>
  )
}

function ZoneRow({
  zone,
  selected,
  canEdit,
  inherited,
  onSelect,
  onPatch,
  onRemove,
}: {
  zone: PricingZone
  selected: boolean
  canEdit: boolean
  inherited?: boolean
  onSelect: () => void
  onPatch?: (values: Partial<PricingZone>) => void
  onRemove?: () => void
}) {
  return (
    <li
      className={
        'flex flex-wrap items-center gap-x-3 gap-y-1.5 border-b border-line-subtle px-4 py-2.5 last:border-0 ' +
        (selected ? 'bg-subtle' : '')
      }
    >
      <button type="button" onClick={onSelect} className="flex min-w-0 flex-1 items-center gap-2 text-start">
        <span className="size-2.5 shrink-0 rounded-full" style={{ background: zone.color }} aria-hidden />
        <span className="truncate type-body font-medium">{zone.name}</span>
        {inherited && <Badge tone="neutral">גלובלי</Badge>}
        {zone.shape === 'circle' && <span className="type-caption text-ink-tertiary">{zone.radius_km} ק״מ</span>}
      </button>

      <span className="tabular type-caption text-ink-tertiary">{zone.travel_hours} ש׳ נסיעה</span>
      {Number(zone.surcharge) !== 0 && (
        <span className="tabular type-caption text-ink-tertiary" dir="ltr">
          {fmtMoney(zone.surcharge)}
        </span>
      )}

      {canEdit && onPatch && (
        <>
          <Switch checked={zone.is_active} onChange={(v) => onPatch({ is_active: v })} label="פעיל" />
          <IconButton label="מחיקת אזור" size="sm" onClick={onRemove}>
            <Trash2 size={ICON.sm} className="text-error" />
          </IconButton>
        </>
      )}
    </li>
  )
}
