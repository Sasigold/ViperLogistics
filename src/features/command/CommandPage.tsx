import { useEffect, useMemo, useState } from 'react'
import { useSearchParams } from 'react-router'
import { ICON, ListChecks, Plus, STROKE } from '../../components/ui/icons'
import {
  Badge,
  Button,
  EmptyState,
  ErrorState,
  Input,
  PageHeader,
  SegmentedControl,
  SkeletonList,
  Tabs,
  cx,
  useConfirm,
  useToast,
} from '../../components/ui'
import { useAuth } from '../../state/auth'
import { actionError } from '../../lib/errors'
import type { Mission } from '../../types/domain'
import { FocusMode } from './FocusMode'
import { MissionCard } from './MissionCard'
import type { MissionActions } from './MissionCard'
import { MissionDrawer } from './MissionDrawer'
import {
  useCompleteMission,
  useMissionsBoard,
  useMissionsStats,
  useRemoveMission,
  useReopenMission,
  useSaveMission,
  useSnoozeMission,
  useToggleStep,
} from './missionQueries'
import { parseQuickAdd } from './quickAdd'
import { StatsPanel } from './StatsPanel'
import { TasksSummary } from './TasksSummary'
import { LANES, groupByLane } from './warRoom'
import type { Lane } from './warRoom'

type Tab = 'board' | 'stats'

const LANE_TONE: Record<Lane, string> = {
  overdue: 'text-error-text',
  today: 'text-ink',
  week: 'text-ink-secondary',
  later: 'text-ink-secondary',
  done: 'text-ink-secondary',
}

/**
 * משימות ניהול (0227, 0232) — המשימות של מנהלי המערכת: לוח לפי יעד
 * (באיחור · היום · השבוע · בהמשך), שורת מדדים, הוספה מהירה וסטטיסטיקה.
 */
export default function CommandPage() {
  const me = useAuth((s) => s.me)
  const meId = me?.profile.id ?? ''
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const [params, setParams] = useSearchParams()

  const who = params.get('who') ?? 'me'
  const owner = who === 'all' ? null : who === 'me' ? meId : who
  const focusId = params.get('m')

  const [tab, setTab] = useState<Tab>('board')
  const board = useMissionsBoard(owner, !!meId)
  const stats = useMissionsStats(owner, 84, !!meId)

  const complete = useCompleteMission()
  const reopen = useReopenMission()
  const snooze = useSnoozeMission()
  const remove = useRemoveMission()
  const toggleStep = useToggleStep()
  const save = useSaveMission()

  const [editing, setEditing] = useState<{ mission: Mission | null; seed?: Parameters<typeof MissionDrawer>[0]['seed'] } | null>(null)
  const [focus, setFocus] = useState<Mission | null>(null)
  const [quick, setQuick] = useState('')
  const [showDone, setShowDone] = useState(false)

  /* ===== השעון: מתעדכן כל חצי דקה, מיושר לשעון השרת ================== */
  const [tick, setTick] = useState(() => Date.now())
  useEffect(() => {
    const t = setInterval(() => setTick(Date.now()), 30_000)
    return () => clearInterval(t)
  }, [])
  const data = board.data
  const skew = data ? Date.parse(data.now) - data.fetchedAt : 0
  const nowMs = tick + skew

  /* ===== ?m=<id> — משימה מהתראה ======================================= */
  useEffect(() => {
    if (!focusId || !data) return
    const m = data.missions.find((x) => x.id === focusId)
    if (m && m.status === 'done') setShowDone(true)
    requestAnimationFrame(() =>
      document.getElementById(`mission-${focusId}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' }),
    )
  }, [focusId, data])

  const lanes = useMemo(() => groupByLane(data?.missions ?? [], nowMs), [data?.missions, nowMs])
  const openCount = (data?.missions ?? []).filter((m) => m.status === 'open').length
  const admins = data?.admins ?? []
  const parsed = quick.trim() ? parseQuickAdd(quick, new Date(nowMs), admins) : null

  const setWho = (v: string) => {
    const next = new URLSearchParams(params)
    if (v === 'me') next.delete('who')
    else next.set('who', v)
    next.delete('m')
    setParams(next, { replace: true })
  }

  /* ===== פעולות ======================================================= */

  const actions: MissionActions = useMemo(
    () => ({
      onComplete: (m) => {
        complete.mutate(m.id, {
          onSuccess: (r) => {
            if (focus?.id === m.id) setFocus(null)
            toast.success(r.on_time ? 'המשימה הושלמה' : 'המשימה הושלמה (באיחור)')
            if (r.next_id) toast.info('המופע הבא של המשימה החוזרת נוצר')
          },
          onError: (e) => toast.error(actionError('הסימון', e)),
        })
      },
      onReopen: (m) =>
        reopen.mutate(m.id, {
          onSuccess: () => toast.info(`"${m.title}" הוחזרה לפתוחות`),
          onError: (e) => toast.error(actionError('ההחזרה', e)),
        }),
      onSnooze: (m, minutes) =>
        snooze.mutate(
          { id: m.id, minutes },
          {
            onSuccess: () => toast.success('היעד עודכן'),
            onError: (e) => toast.error(actionError('הדחייה', e)),
          },
        ),
      onEdit: (m) => setEditing({ mission: m }),
      onRemove: async (m) => {
        const ok = await confirm(`להסיר את "${m.title}"?`, {
          title: 'הסרת משימה',
          confirmLabel: 'הסרה',
        })
        if (!ok) return
        remove.mutate(m.id, {
          onSuccess: () => toast.success('המשימה הוסרה'),
          onError: (e) => toast.error(actionError('ההסרה', e)),
        })
      },
      onFocus: (m) => setFocus(m),
      onToggleStep: (id) => toggleStep.mutate(id, { onError: (e) => toast.error(actionError('הסימון', e)) }),
    }),
    [complete, reopen, snooze, remove, toggleStep, confirm, toast, focus?.id],
  )

  const quickSubmit = async () => {
    if (!parsed || !parsed.title) return
    try {
      await save.mutateAsync({
        id: null,
        input: {
          title: parsed.title,
          description: null,
          owner_id: parsed.ownerId ?? owner ?? meId,
          due_at: parsed.due.toISOString(),
          priority: parsed.priority,
          recurrence: parsed.recurrence,
          steps: [],
        },
      })
      setQuick('')
      toast.success('המשימה נוספה')
    } catch (e) {
      toast.error(actionError('ההוספה', e))
    }
  }

  /* ===== ציור ========================================================= */

  const whoItems = [
    { key: 'me', label: 'שלי' },
    { key: 'all', label: 'כולם' },
    ...admins.filter((a) => a.id !== meId).map((a) => ({ key: a.id, label: a.full_name.split(' ')[0] })),
  ]
  const focusLive = focus ? (data?.missions.find((m) => m.id === focus.id) ?? focus) : null

  return (
    <div className="space-y-4">

      <PageHeader
        title={
          <span className="inline-flex items-center gap-2">
            <ListChecks size={ICON.xl} strokeWidth={STROKE} className="text-ink-tertiary" />
            משימות ניהול
          </span>
        }
        subtitle="המשימות של מנהלי המערכת: יעדים, אחראים ותזכורות"
        actions={
          <>
            <SegmentedControl items={whoItems} value={whoItems.some((w) => w.key === who) ? who : 'me'} onChange={setWho} />
            <Button variant="primary" onClick={() => setEditing({ mission: null, seed: { ownerId: owner ?? meId } })}>
              <Plus size={ICON.sm} strokeWidth={STROKE} />
              משימה
            </Button>
          </>
        }
      />

      {board.error ? (
        <ErrorState error={board.error} onRetry={() => void board.refetch()} />
      ) : !data ? (
        <SkeletonList rows={6} />
      ) : (
        <>
          <TasksSummary missions={data.missions} stats={stats.data} nowMs={nowMs} />

          {/* הוספה מהירה */}
          <div className="rounded-xl border border-line bg-surface p-2">
            <form
              className="flex gap-2"
              onSubmit={(e) => {
                e.preventDefault()
                void quickSubmit()
              }}
            >
              <Input
                value={quick}
                onChange={(e) => setQuick(e.target.value)}
                placeholder='הוספה מהירה: "התקנת מצלמות במחסן מחר 10:00 @שם !1"'
                aria-label="הוספה מהירה"
              />
              <Button type="submit" variant="primary" loading={save.isPending} disabled={!parsed?.title}>
                הוספה
              </Button>
            </form>
            {parsed && (
              <div className="mt-2 flex flex-wrap items-center gap-1.5 px-1 type-caption text-ink-tertiary">
                <span className="font-semibold text-ink">{parsed.title || '(בלי שם)'}</span>
                <span>·</span>
                <span>
                  {parsed.due.toLocaleString('he-IL', { weekday: 'short', day: 'numeric', month: 'numeric', hour: '2-digit', minute: '2-digit' })}
                </span>
                {parsed.chips.map((c) => (
                  <Badge key={c} tone="primary">
                    {c}
                  </Badge>
                ))}
                <button
                  type="button"
                  className="ms-auto font-semibold text-primary-text hover:underline"
                  onClick={() =>
                    setEditing({ mission: null, seed: { title: parsed.title, due: parsed.due, ownerId: parsed.ownerId ?? owner ?? meId } })
                  }
                >
                  עוד פרטים…
                </button>
              </div>
            )}
          </div>

          <Tabs
            items={[
              { key: 'board', label: `לוח (${openCount})` },
              { key: 'stats', label: 'סטטיסטיקה' },
            ]}
            value={tab}
            onChange={setTab}
          />

          {tab === 'stats' ? (
            <StatsPanel stats={stats.data} loading={stats.isLoading} />
          ) : openCount === 0 && !lanes.done.length ? (
            <EmptyState
              title="אין משימות"
              description="משימה חדשה תופיע כאן לפי תאריך היעד שלה."
              action={
                <Button variant="primary" onClick={() => setEditing({ mission: null, seed: { ownerId: owner ?? meId } })}>
                  <Plus size={ICON.sm} /> משימה ראשונה
                </Button>
              }
            />
          ) : (
            <>
              {openCount === 0 && (
                <p className="rounded-xl border border-line bg-surface px-4 py-3 type-body text-ink-secondary">
                  אין משימות פתוחות.
                </p>
              )}
              <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
                {LANES.filter((l) => l.key !== 'done').map((lane) => {
                  const items = lanes[lane.key]
                  if (lane.key === 'overdue' && !items.length) return null
                  return (
                    <section
                      key={lane.key}
                      className={cx(
                        'flex min-h-24 flex-col gap-2 rounded-xl border border-line-subtle bg-subtle p-2.5',
                      )}
                    >
                      <header className="flex items-center justify-between px-1">
                        <h2 className={cx('type-subtitle font-bold', LANE_TONE[lane.key])}>
                          {lane.label}
                        </h2>
                        <span className={cx('tabular type-caption font-bold', LANE_TONE[lane.key])}>{items.length}</span>
                      </header>
                      {items.length === 0 ? (
                        <p className="px-1 py-3 text-center type-caption text-ink-tertiary">אין</p>
                      ) : (
                        items.map((m) => (
                          <MissionCard
                            key={m.id}
                            mission={m}
                            nowMs={nowMs}
                            showOwner={owner !== meId}
                            highlight={m.id === focusId}
                            actions={actions}
                          />
                        ))
                      )}
                    </section>
                  )
                })}
              </div>

              {lanes.done.length > 0 && (
                <section className="rounded-xl border border-line-subtle bg-subtle p-2.5">
                  <button
                    type="button"
                    className="flex w-full items-center justify-between px-1 type-subtitle font-bold text-ink-secondary"
                    onClick={() => setShowDone((v) => !v)}
                    aria-expanded={showDone}
                  >
                    <span>הושלמו ב-7 הימים האחרונים</span>
                    <span className="tabular">
                      {lanes.done.length} {showDone ? '▴' : '▾'}
                    </span>
                  </button>
                  {showDone && (
                    <div className="mt-2 grid gap-2 md:grid-cols-2 xl:grid-cols-4">
                      {lanes.done.map((m) => (
                        <MissionCard
                          key={m.id}
                          mission={m}
                          nowMs={nowMs}
                          showOwner={owner !== meId}
                          highlight={m.id === focusId}
                          actions={actions}
                        />
                      ))}
                    </div>
                  )}
                </section>
              )}
            </>
          )}
        </>
      )}

      {editing && (
        <MissionDrawer
          open
          mission={editing.mission}
          seed={editing.seed}
          admins={admins}
          meId={meId}
          onClose={() => setEditing(null)}
        />
      )}

      {focusLive && focusLive.status === 'open' && (
        <FocusMode
          mission={focusLive}
          nowMs={nowMs}
          onClose={() => setFocus(null)}
          onComplete={(el) => actions.onComplete(focusLive, el)}
          onToggleStep={actions.onToggleStep}
        />
      )}

      {dialog}
    </div>
  )
}
