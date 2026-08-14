import { useEffect, useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Percent, ICON, STROKE } from '../../components/ui/icons'
import {
  Card,
  CardBody,
  CardHeader,
  Checkbox,
  EmptyState,
  Input,
  Skeleton,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useCustomerIncomeSplits, useIncomeCategories } from '../../lib/queries'
import { errorMessage } from '../../lib/errors'

/**
 * חלוקת ההכנסות של הלקוח: אילו קטגוריות מופעלות לו, וכמה מכל שקל נשאר אצל
 * ויפר. קיום שורת split = הקטגוריה מופעלת = השדה מופיע בטופס האירוע.
 *
 * חשוב לדעת בקריאה: האחוז נשמר כ-snapshot על כל אירוע בעת ההזנה. שינוי כאן
 * משפיע על אירועים שיוזנו/ייערכו מעכשיו — לא על היסטוריה.
 */
export default function IncomeSplitTab({ customerId }: { customerId: string }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { data: categories = [], isLoading } = useIncomeCategories()
  const { data: splits = [] } = useCustomerIncomeSplits(customerId)

  const splitOf = (categoryId: string) => splits.find((s) => s.category_id === categoryId)
  const invalidate = () => void qc.invalidateQueries({ queryKey: ['customer_income_splits', customerId] })

  const toggle = useMutation({
    mutationFn: async ({ categoryId, on }: { categoryId: string; on: boolean }) => {
      if (on) {
        const { error } = await supabase
          .from('customer_income_splits')
          .insert({ customer_id: customerId, category_id: categoryId })
        if (error) throw error
      } else {
        const { error } = await supabase
          .from('customer_income_splits')
          .delete()
          .eq('customer_id', customerId)
          .eq('category_id', categoryId)
        if (error) throw error
      }
    },
    onSuccess: invalidate,
    onError: (e) => toast.error(errorMessage(e)),
  })

  const setPct = useMutation({
    mutationFn: async ({ categoryId, pct }: { categoryId: string; pct: number }) => {
      const { error } = await supabase
        .from('customer_income_splits')
        .update({ viper_share_pct: pct })
        .eq('customer_id', customerId)
        .eq('category_id', categoryId)
      if (error) throw error
    },
    onSuccess: invalidate,
    onError: (e) => toast.error(errorMessage(e)),
  })

  const active = categories.filter((c) => c.is_active)

  return (
    <Card className="max-w-2xl">
      <CardHeader
        title="חלוקת הכנסות"
        subtitle={`${splits.length} קטגוריות מופעלות · האחוז נשמר על כל אירוע בעת ההזנה`}
        icon={<Percent size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody padded={false}>
        <p className="border-b border-line-subtle bg-subtle/40 px-4 py-2.5 type-caption text-ink-secondary">
          קטגוריה מופעלת מוסיפה שדה סכום לטופס האירוע של הלקוח. שינוי אחוז משפיע רק על
          אירועים שיוזנו מעתה — ההיסטוריה שומרת את האחוז שהיה בזמן ההזנה.
        </p>
        {isLoading ? (
          <div className="p-4">
            <Skeleton className="h-32 w-full" />
          </div>
        ) : active.length === 0 ? (
          <EmptyState compact art="box" title="אין קטגוריות הכנסה" description="ניתן להגדיר אותן במסך ההגדרות, לשונית כספים" />
        ) : (
          <ul>
            {active.map((c) => {
              const split = splitOf(c.id)
              return (
                <SplitRow
                  key={c.id}
                  name={c.name}
                  color={c.color}
                  enabled={!!split}
                  pct={split ? Number(split.viper_share_pct) : 100}
                  busy={toggle.isPending || setPct.isPending}
                  onToggle={(on) => toggle.mutate({ categoryId: c.id, on })}
                  onPct={(pct) => setPct.mutate({ categoryId: c.id, pct })}
                />
              )
            })}
            <li className="flex items-center gap-3 px-4 py-2.5">
              <span className="size-2 shrink-0 rounded-full bg-ink-tertiary" aria-hidden />
              <span className="min-w-0 flex-1">
                <span className="block type-body font-medium">צוות</span>
                <span className="type-caption text-ink-tertiary">
                  מחושב מתמחור המשימות — 100% ויפר, ללא שדה על האירוע
                </span>
              </span>
            </li>
          </ul>
        )}
      </CardBody>
    </Card>
  )
}

function SplitRow(props: {
  name: string
  color: string
  enabled: boolean
  pct: number
  busy: boolean
  onToggle: (on: boolean) => void
  onPct: (pct: number) => void
}) {
  const [draft, setDraft] = useState(String(props.pct))
  useEffect(() => setDraft(String(props.pct)), [props.pct])

  const commit = () => {
    const n = Number(draft)
    if (!Number.isFinite(n) || n < 0 || n > 100) {
      setDraft(String(props.pct))
      return
    }
    if (n !== props.pct) props.onPct(n)
  }

  const clientPct = Math.round((100 - Number(draft || 0)) * 100) / 100

  return (
    <li className="flex flex-wrap items-center gap-3 border-b border-line-subtle px-4 py-2.5">
      <span className="size-2 shrink-0 rounded-full" style={{ background: props.color }} aria-hidden />
      <span className="min-w-24 flex-1">
        <Checkbox label={props.name} checked={props.enabled} onChange={props.onToggle} disabled={props.busy} />
      </span>
      {props.enabled && (
        <span className="flex items-center gap-2">
          <span className="type-caption text-ink-secondary">ויפר</span>
          <Input
            inputSize="sm"
            type="number"
            min={0}
            max={100}
            step={0.5}
            dir="ltr"
            className="w-20 text-center"
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onBlur={commit}
            onKeyDown={(e) => e.key === 'Enter' && commit()}
            aria-label={`אחוז ויפר בקטגוריה ${props.name}`}
          />
          <span className="type-caption text-ink-secondary">%</span>
          <span className="type-caption text-ink-tertiary tabular">
            ללקוח: {Number.isFinite(clientPct) ? clientPct : '—'}%
          </span>
        </span>
      )}
    </li>
  )
}
