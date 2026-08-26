/**
 * תוספות מחיר על משימה (0113).
 *
 * הבעיה שהן פותרות אינה חישובית אלא שיחתית. אירוע חורג — קומה בלי מעלית,
 * שעתיים המתנה בשער, משאית שנייה שהוזמנה באמצע היום — נגמר בהפרש בחשבונית
 * שאיש לא יודע להסביר, ובשיחת טלפון שבה מנסים לשחזר מהזיכרון מה קרה שם.
 * כאן ההפרש נרשם עם המשפט שמסביר אותו, ברגע שהוא נוצר, ובידי מי שהיה שם —
 * והמשפט הזה הוא בדיוק מה שהלקוח קורא בכרטיס התמחור של האירוע.
 *
 * הסכום אינו נכנס ל-`task_pricing.price`: המחיר שם הוא תוצר המחשבון, ו-
 * ‏`recalculate_task_price` כותב אותו מחדש. תוספת שהתמזגה לתוכו הייתה
 * נמחקת בחישוב הראשון, או נועלת את המשימה על `is_manual` ומנתקת אותה
 * מהמחשבון בגלל 80 ₪ של המתנה.
 */
import { useState } from 'react'
import { ICON, Plus, STROKE, Trash2 } from '../../components/ui/icons'
import {
  Button,
  Field,
  IconButton,
  Input,
  Skeleton,
  cx,
  fmtMoney,
  useConfirm,
  useToast,
} from '../../components/ui'
import { errorMessage } from '../../lib/errors'
import { fmtDate } from '../../lib/dates'
import type { TaskPriceAddon } from '../../types/domain'
import { sumAddons, useAddPriceAddon, useRemovePriceAddon, useTaskPriceAddons } from './addonQueries'

/**
 * הרשימה, בכרטיס המשימה. נשמרת מיד ולא עם כפתור השמירה של המגירה —
 * ‏`task_price_addons` אינה עמודה של המשימה, בדיוק כמו התנאים מול הקבלן.
 */
export function PriceAddonsEditor({ taskId, canEdit }: { taskId: string; canEdit: boolean }) {
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const { data: addons = [], isLoading } = useTaskPriceAddons(taskId)
  const add = useAddPriceAddon(taskId)
  const remove = useRemovePriceAddon(taskId)

  const [amount, setAmount] = useState('')
  const [note, setNote] = useState('')

  const parsed = amount.trim() === '' ? null : Number(amount)
  /* אפס אינו תוספת אלא הערה, ולזה יש יומן — וזה גם מה שה-CHECK במסד אוכף. */
  const ready = parsed !== null && Number.isFinite(parsed) && parsed !== 0 && note.trim() !== ''

  async function submit() {
    if (!ready) return
    try {
      await add.mutateAsync({ amount: parsed, note })
      setAmount('')
      setNote('')
      toast.success('התוספת נוספה')
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  async function onRemove(row: TaskPriceAddon) {
    const ok = await confirm(`להסיר את התוספת "${row.note}"?`, {
      title: 'הסרת תוספת מחיר',
      confirmLabel: 'הסרה',
    })
    if (!ok) return
    try {
      await remove.mutateAsync(row.id)
      toast.success('התוספת הוסרה')
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  if (isLoading) return <Skeleton className="h-16 w-full" />

  return (
    <div className="space-y-3 border-t border-line-subtle pt-3">
      <div className="flex items-center justify-between gap-2">
        <span className="type-overline">תוספות מחיר</span>
        {addons.length > 0 && (
          <span dir="ltr" className="tabular type-body font-semibold">
            {fmtMoney(sumAddons(addons))}
          </span>
        )}
      </div>

      {addons.length === 0 && (
        <p className="type-caption text-ink-tertiary">
          אין תוספות. תוספת נרשמת עם הערה, וההערה מוצגת ללקוח בכרטיס התמחור של האירוע.
        </p>
      )}

      {addons.map((row) => (
        <div key={row.id} className="flex items-start gap-2 rounded-lg border border-line-subtle bg-subtle/40 p-2">
          <span
            dir="ltr"
            className={cx('shrink-0 tabular type-body font-semibold', Number(row.amount) < 0 && 'text-success-text')}
          >
            {fmtMoney(Number(row.amount))}
          </span>
          <span className="min-w-0 flex-1">
            <span className="block type-body">{row.note}</span>
            <span className="block type-caption text-ink-tertiary">
              {[row.creator_name, fmtDate(row.created_at)].filter(Boolean).join(' · ')}
            </span>
          </span>
          {canEdit && (
            <IconButton label="הסרת התוספת" size="sm" onClick={() => void onRemove(row)} disabled={remove.isPending}>
              <Trash2 size={ICON.sm} strokeWidth={STROKE} />
            </IconButton>
          )}
        </div>
      ))}

      {canEdit && (
        <div className="flex flex-wrap items-end gap-2">
          <Field label="סכום (₪)" className="w-28 shrink-0" hint="שלילי = הנחה">
            <Input
              type="number"
              step="any"
              dir="ltr"
              inputSize="sm"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
            />
          </Field>
          <Field label="הערה ללקוח" className="min-w-40 grow">
            <Input
              inputSize="sm"
              value={note}
              placeholder="למשל: המתנה בשער, שעתיים"
              onChange={(e) => setNote(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault()
                  void submit()
                }
              }}
            />
          </Field>
          <Button
            size="sm"
            variant="primary"
            className="mb-1.5"
            disabled={!ready}
            loading={add.isPending}
            onClick={() => void submit()}
          >
            <Plus size={ICON.sm} strokeWidth={STROKE} />
            הוספה
          </Button>
        </div>
      )}
      {dialog}
    </div>
  )
}
