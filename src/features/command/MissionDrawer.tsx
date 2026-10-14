import { useState } from 'react'
import { ICON, Plus, STROKE, X } from '../../components/ui/icons'
import { Button, Drawer, Field, IconButton, Input, SegmentedControl, Select, Textarea, useToast } from '../../components/ui'
import { actionError } from '../../lib/errors'
import type { Mission, MissionRecurrence } from '../../types/domain'
import { useSaveMission } from './missionQueries'
import { PRIORITIES, RECURRENCE_LABELS, toLocalInput } from './warRoom'

interface StepDraft {
  id?: string
  title: string
  done: boolean
}

/**
 * יצירה ועריכה של משימה. `mission` null — חדשה, עם ברירות המחדל מ-`seed`.
 */
export function MissionDrawer({
  open,
  mission,
  seed,
  admins,
  meId,
  onClose,
}: {
  open: boolean
  mission: Mission | null
  seed?: { title?: string; due?: Date; ownerId?: string | null }
  admins: { id: string; full_name: string }[]
  meId: string
  onClose: () => void
}) {
  const toast = useToast()
  const save = useSaveMission()
  const [title, setTitle] = useState(mission?.title ?? seed?.title ?? '')
  const [description, setDescription] = useState(mission?.description ?? '')
  const [owner, setOwner] = useState(mission?.owner_id ?? seed?.ownerId ?? meId)
  const [due, setDue] = useState(() => {
    if (mission) return toLocalInput(new Date(mission.due_at))
    const d = seed?.due ?? new Date(Date.now() + 86_400_000)
    if (!seed?.due) d.setHours(18, 0, 0, 0)
    return toLocalInput(d)
  })
  const [priority, setPriority] = useState<1 | 2 | 3 | 4>(mission?.priority ?? 2)
  const [recurrence, setRecurrence] = useState<MissionRecurrence>(mission?.recurrence ?? 'none')
  const [steps, setSteps] = useState<StepDraft[]>(mission?.steps.map((s) => ({ ...s })) ?? [])
  const [newStep, setNewStep] = useState('')

  /* ‏0228: משימה שבוצעה קפואה בניקוד שלה — השרת שומר את הבעלים, היעד והעדיפות */
  const frozen = mission?.status === 'done'
  const postpones = mission && mission.status === 'open' && due && new Date(due) > new Date(mission.due_at)

  const addStep = () => {
    const t = newStep.trim()
    if (!t) return
    setSteps((s) => [...s, { title: t, done: false }])
    setNewStep('')
  }

  const submit = async () => {
    if (!title.trim()) return toast.error('למשימה צריך שם')
    if (!due) return toast.error('למשימה צריך תאריך יעד')
    try {
      await save.mutateAsync({
        id: mission?.id ?? null,
        input: {
          title: title.trim(),
          description: description.trim() || null,
          owner_id: owner,
          due_at: new Date(due).toISOString(),
          priority,
          recurrence,
          steps: [...steps, ...(newStep.trim() ? [{ title: newStep.trim(), done: false }] : [])],
        },
      })
      toast.success(mission ? 'המשימה עודכנה' : 'המשימה נוספה. השעון התחיל לתקתק.')
      onClose()
    } catch (e) {
      toast.error(actionError('השמירה', e))
    }
  }

  return (
    <Drawer
      open={open}
      onClose={onClose}
      title={mission ? 'עריכת משימה' : 'משימה חדשה'}
      footer={
        <div className="flex w-full items-center justify-between gap-2">
          <span className="type-caption text-warning-text">{postpones ? 'הזזת היעד קדימה נספרת כדחייה (−10 XP)' : ''}</span>
          <div className="flex gap-2">
            <Button variant="ghost" onClick={onClose}>
              ביטול
            </Button>
            <Button variant="primary" loading={save.isPending} onClick={submit}>
              שמירה
            </Button>
          </div>
        </div>
      }
    >
      <div className="space-y-4">
        <Field label="מה צריך לעשות" required>
          <Input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={200} autoFocus placeholder="התקנת מצלמות במחסן" />
        </Field>

        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="תאריך ושעת יעד" required>
            <Input type="datetime-local" value={due} disabled={frozen} onChange={(e) => setDue(e.target.value)} />
          </Field>
          <Field label="אחראי">
            <Select value={owner} disabled={frozen} onChange={(e) => setOwner(e.target.value)}>
              {admins.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.full_name}
                  {a.id === meId ? ' (אני)' : ''}
                </option>
              ))}
            </Select>
          </Field>
        </div>

        {frozen && (
          <p className="rounded-lg bg-subtle px-3 py-2 type-caption text-ink-secondary">
            המשימה בוצעה, והנקודות נקבעו. כדי לשנות יעד, אחראי או עדיפות — קודם "החזרה לפתוחות".
          </p>
        )}

        <Field label="עדיפות">
          <SegmentedControl
            block
            value={String(priority) as '1'}
            onChange={(k) => !frozen && setPriority(Number(k) as 1 | 2 | 3 | 4)}
            items={PRIORITIES.map((p) => ({ key: String(p.value) as '1', label: p.label }))}
          />
        </Field>

        <Field label="חזרה" hint="משימה חוזרת: כשמסיימים אותה, המופע הבא נוצר מעצמו">
          <Select value={recurrence} onChange={(e) => setRecurrence(e.target.value as MissionRecurrence)}>
            {(Object.keys(RECURRENCE_LABELS) as MissionRecurrence[]).map((k) => (
              <option key={k} value={k}>
                {RECURRENCE_LABELS[k]}
              </option>
            ))}
          </Select>
        </Field>

        <Field label="צעדים" hint="רשימת תתי-משימות. פס ההתקדמות על הכרטיס נגזר ממנה">
          <ul className="space-y-1.5">
            {steps.map((s, i) => (
              <li key={s.id ?? `new-${i}`} className="flex items-center gap-2">
                <input
                  type="checkbox"
                  checked={s.done}
                  onChange={() => setSteps((all) => all.map((x, j) => (j === i ? { ...x, done: !x.done } : x)))}
                  className="size-4 accent-[var(--vl-success)]"
                  aria-label="בוצע"
                />
                <Input
                  inputSize="sm"
                  value={s.title}
                  onChange={(e) => setSteps((all) => all.map((x, j) => (j === i ? { ...x, title: e.target.value } : x)))}
                />
                <IconButton label="הסרת הצעד" size="sm" onClick={() => setSteps((all) => all.filter((_, j) => j !== i))}>
                  <X size={ICON.sm} strokeWidth={STROKE} />
                </IconButton>
              </li>
            ))}
            <li className="flex items-center gap-2">
              <Input
                inputSize="sm"
                value={newStep}
                placeholder="צעד חדש…"
                onChange={(e) => setNewStep(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    e.preventDefault()
                    addStep()
                  }
                }}
              />
              <IconButton label="הוספת צעד" size="sm" onClick={addStep}>
                <Plus size={ICON.sm} strokeWidth={STROKE} />
              </IconButton>
            </li>
          </ul>
        </Field>

        <Field label="הערות">
          <Textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={3} autoGrow />
        </Field>
      </div>
    </Drawer>
  )
}
