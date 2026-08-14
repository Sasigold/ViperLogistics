import { useEffect, useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  Field,
  Input,
  Select,
  Skeleton,
  Switch,
  useToast,
} from '../../components/ui'
import { Banknote, ICON, Plus, STROKE, Wallet } from '../../components/ui/icons'
import { supabase } from '../../lib/supabase'
import { useIncomeCategories } from '../../lib/queries'
import { useAppSetting, useSaveAppSetting } from '../attendance/attendanceQueries'
import { errorMessage } from '../../lib/errors'
import type { IncomeCategory, IncomeFamily } from '../../types/domain'

const FAMILIES: { key: IncomeFamily; label: string }[] = [
  { key: 'furniture', label: 'ריהוט' },
  { key: 'logistics', label: 'לוגיסטיקה' },
]

const familyLabel = (f: IncomeFamily) => FAMILIES.find((x) => x.key === f)?.label ?? f

/**
 * לשונית הכספים: אחוז עלות המעביד וקטלוג קטגוריות ההכנסה (0068).
 * קטגוריה שכבר הוזנו עליה סכומים מכובה ולא נמחקת — ההיסטוריה נשארת בדשבורד.
 */
export function FinanceSettingsTab() {
  return (
    <div className="max-w-2xl space-y-5">
      <EmployerCostCard />
      <IncomeCategoriesCard />
    </div>
  )
}

/* ===== עלות מעביד ========================================================= */

function EmployerCostCard() {
  const toast = useToast()
  const { data: setting, isLoading } = useAppSetting<{ pct: number }>('finance.employer_cost')
  const save = useSaveAppSetting('finance.employer_cost')
  const [draft, setDraft] = useState('')
  useEffect(() => setDraft(setting ? String(setting.pct) : ''), [setting])

  const pct = Number(draft)
  const valid = draft.trim() !== '' && Number.isFinite(pct) && pct >= 0 && pct <= 200
  const dirty = setting ? Number(draft) !== Number(setting.pct) : draft.trim() !== ''

  return (
    <Card>
      <CardHeader
        title="עלות מעביד"
        subtitle="משכורות עם עלות מעביד בדשבורד = עלות השכר המאושרת × (1 + האחוז הזה)"
        icon={<Wallet size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody>
        {isLoading ? (
          <Skeleton className="h-10 w-48" />
        ) : (
          <form
            className="flex flex-wrap items-end gap-2"
            onSubmit={(e) => {
              e.preventDefault()
              if (!valid) return
              save.mutate(
                { pct },
                {
                  onSuccess: () => toast.success('אחוז עלות המעביד נשמר'),
                  onError: (err) => toast.error(errorMessage(err)),
                },
              )
            }}
          >
            <Field label="אחוז עלות מעביד" error={!valid && draft !== '' ? 'אחוז בין 0 ל-200' : undefined}>
              <Input
                inputSize="sm"
                type="number"
                min={0}
                max={200}
                step={0.5}
                dir="ltr"
                className="w-28 text-center"
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
              />
            </Field>
            <Button type="submit" size="sm" variant="primary" loading={save.isPending} disabled={!valid || !dirty}>
              שמירה
            </Button>
          </form>
        )}
      </CardBody>
    </Card>
  )
}

/* ===== קטגוריות הכנסה ===================================================== */

function IncomeCategoriesCard() {
  const qc = useQueryClient()
  const toast = useToast()
  const { data: categories = [], isLoading } = useIncomeCategories()
  const [name, setName] = useState('')
  const [family, setFamily] = useState<IncomeFamily>('logistics')

  const invalidate = () => void qc.invalidateQueries({ queryKey: ['income_categories'] })

  const add = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.from('income_categories').insert({
        name: name.trim(),
        family,
        sort_order: (categories.at(-1)?.sort_order ?? 90) + 10,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('הקטגוריה נוספה')
      setName('')
      invalidate()
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const update = useMutation({
    mutationFn: async (patch: Partial<IncomeCategory> & { id: string }) => {
      const { id, ...rest } = patch
      const { error } = await supabase.from('income_categories').update(rest).eq('id', id)
      if (error) throw error
    },
    onSuccess: invalidate,
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <Card>
      <CardHeader
        title="קטגוריות הכנסה"
        subtitle="השדות שמופיעים על אירועים של לקוחות שהופעלה להם חלוקת הכנסות"
        icon={<Banknote size={ICON.md} strokeWidth={STROKE} />}
      />
      <form
        className="flex flex-wrap items-end gap-2 border-b border-line-subtle bg-subtle/40 p-4"
        onSubmit={(e) => {
          e.preventDefault()
          if (name.trim()) add.mutate()
        }}
      >
        <Field label="קטגוריה חדשה" className="min-w-40 flex-1">
          <Input inputSize="sm" value={name} onChange={(e) => setName(e.target.value)} />
        </Field>
        <Field label="משפחה" hint="קובעת לאיזה כרטיס מסכם הקטגוריה נספרת">
          <Select value={family} onChange={(e) => setFamily(e.target.value as IncomeFamily)}>
            {FAMILIES.map((f) => (
              <option key={f.key} value={f.key}>
                {f.label}
              </option>
            ))}
          </Select>
        </Field>
        <Button type="submit" size="sm" variant="primary" loading={add.isPending} disabled={!name.trim()}>
          <Plus size={ICON.sm} strokeWidth={STROKE} />
          הוספה
        </Button>
      </form>
      <CardBody padded={false}>
        {isLoading ? (
          <div className="p-4">
            <Skeleton className="h-32 w-full" />
          </div>
        ) : categories.length === 0 ? (
          <EmptyState compact art="box" title="אין קטגוריות הכנסה" />
        ) : (
          <ul>
            {categories.map((c) => (
              <li key={c.id} className="flex flex-wrap items-center gap-3 border-b border-line-subtle px-4 py-2.5 last:border-0">
                <input
                  type="color"
                  aria-label={`צבע הקטגוריה ${c.name}`}
                  value={c.color}
                  onChange={(e) => update.mutate({ id: c.id, color: e.target.value })}
                  className="size-6 shrink-0 cursor-pointer rounded-md border border-line bg-transparent p-0.5"
                />
                <span className="min-w-0 flex-1">
                  <span className="block truncate type-body font-medium">{c.name}</span>
                  <span className="type-caption text-ink-tertiary">{familyLabel(c.family)}</span>
                </span>
                {!c.is_active && <Badge tone="neutral">כבויה</Badge>}
                <Switch
                  checked={c.is_active}
                  onChange={(v) => update.mutate({ id: c.id, is_active: v })}
                  aria-label={`הפעלת ${c.name}`}
                />
              </li>
            ))}
          </ul>
        )}
        <p className="px-4 py-2.5 type-caption text-ink-tertiary">
          קטגוריה כבויה אינה מוצעת יותר בטופס האירוע ובכרטיסי הלקוחות, אבל סכומים שכבר
          הוזנו עליה ממשיכים להיספר בדשבורד.
        </p>
      </CardBody>
    </Card>
  )
}
