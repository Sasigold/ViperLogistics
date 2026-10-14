import { useEffect, useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'react-router'
import { ICON, Plus, STROKE, Siren, Trophy, Volume2, VolumeX } from '../../components/ui/icons'
import {
  Badge,
  Button,
  EmptyState,
  ErrorState,
  IconButton,
  Input,
  Modal,
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
import { confetti } from './confetti'
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
import { isMuted, playDing, playFanfare, playSiren, playSnooze, setMuted } from './sfx'
import { StatsPanel } from './StatsPanel'
import { WarHeader } from './WarHeader'
import { LANES, groupByLane, levelOf, liveDebt } from './warRoom'
import type { Lane } from './warRoom'
import './command.css'

type Tab = 'board' | 'stats'

const LANE_TONE: Record<Lane, string> = {
  overdue: 'text-error-text',
  today: 'text-warning-text',
  week: 'text-primary-text',
  later: 'text-ink-secondary',
  done: 'text-success-text',
}

/** "+140 XP" שעולה מהכרטיס */
function floatXp(el: HTMLElement | null, points: number, gold: boolean) {
  if (typeof document === 'undefined') return
  const r = el?.getBoundingClientRect()
  const span = document.createElement('span')
  span.className = 'wr-xp'
  if (gold) span.dataset.gold = ''
  span.textContent = `+${points} XP`
  span.style.left = `${r ? r.left + r.width / 2 : window.innerWidth / 2}px`
  span.style.top = `${r ? r.top : window.innerHeight / 2}px`
  document.body.appendChild(span)
  setTimeout(() => span.remove(), 1700)
}

/**
 * משימות ניהול (0227) — המשימות של מנהלי המערכת.
 *
 * כל הדף משנה מצב לפי רמת האיום שהשרת מחשב: ירוק ורגוע כשאין איחורים,
 * וינייטה אדומה, פס התראה רץ וסירנה כשהם מצטברים. סיום משימה = קונפטי,
 * צליל, נקודות, ולפעמים דרגה חדשה.
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
  const [levelUp, setLevelUp] = useState<string | null>(null)
  const [muted, setMutedState] = useState(isMuted)
  const [quick, setQuick] = useState('')
  const [showDone, setShowDone] = useState(false)

  /* ===== השעון: מתקתק כל שנייה, מיושר לשעון השרת ====================== */
  const [tick, setTick] = useState(() => Date.now())
  useEffect(() => {
    const t = setInterval(() => setTick(Date.now()), 1000)
    return () => clearInterval(t)
  }, [])
  const data = board.data
  const skew = data ? Date.parse(data.now) - data.fetchedAt : 0
  const nowMs = tick + skew
  const debt = data ? liveDebt(data, tick - data.fetchedAt) : 0

  /* ===== קריסה: סירנה ורעידה, פעם אחת בביקור ========================== */
  const [shake, setShake] = useState(false)
  const alarmed = useRef(false)
  useEffect(() => {
    if (!data || data.defcon > 1 || alarmed.current) return
    alarmed.current = true
    setShake(true)
    playSiren()
    const t = setTimeout(() => setShake(false), 1400)
    return () => clearTimeout(t)
  }, [data])

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
      onComplete: (m, el) => {
        complete.mutate(m.id, {
          onSuccess: (r) => {
            const rect = el.getBoundingClientRect()
            confetti({ x: rect.left + rect.width / 2, y: rect.top, gold: r.early, count: r.early ? 220 : 150 })
            floatXp(el, r.points, r.early)
            playDing(r.early)
            if (focus?.id === m.id) setFocus(null)
            toast.success(
              r.early
                ? `ציפור מוקדמת! +${r.points} XP`
                : r.on_time
                  ? `בוצע בזמן. +${r.points} XP`
                  : r.points > 0
                    ? `בוצע — באיחור. +${r.points} XP בלבד`
                    : 'בוצע — באיחור. 0 XP. בפעם הבאה בזמן.',
            )
            const before = levelOf(r.xp_before)
            const after = levelOf(r.xp_after)
            if (after.index > before.index && m.owner_id === meId) {
              setTimeout(() => {
                setLevelUp(after.title)
                playFanfare()
                confetti({ count: 260, gold: true })
              }, 700)
            }
            if (r.next_id) toast.info('המופע הבא של המשימה החוזרת נוצר')
          },
          onError: (e) => toast.error(actionError('הסימון', e)),
        })
      },
      onReopen: (m) =>
        reopen.mutate(m.id, {
          onSuccess: () => toast.info(`"${m.title}" חזרה לפתוחות. הנקודות בוטלו.`),
          onError: (e) => toast.error(actionError('ההחזרה', e)),
        }),
      onSnooze: (m, minutes) =>
        snooze.mutate(
          { id: m.id, minutes },
          {
            onSuccess: () => {
              playSnooze()
              toast.warning(`נדחתה. זו הדחייה ה-${m.postpone_count + 1} שלה — היא תהיה שווה 10 XP פחות.`)
            },
            onError: (e) => toast.error(actionError('הדחייה', e)),
          },
        ),
      onEdit: (m) => setEditing({ mission: m }),
      onRemove: async (m) => {
        const ok = await confirm(`להסיר את "${m.title}"? היא לא תיספר — לא לטוב ולא לרע.`, {
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
    [complete, reopen, snooze, remove, toggleStep, confirm, toast, focus?.id, meId],
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
      toast.success('נוספה. השעון התחיל לתקתק.')
    } catch (e) {
      toast.error(actionError('ההוספה', e))
    }
  }

  const toggleMute = () => {
    setMuted(!muted)
    setMutedState(!muted)
  }

  /* ===== ציור ========================================================= */

  const whoItems = [
    { key: 'me', label: 'שלי' },
    { key: 'all', label: 'כולם' },
    ...admins.filter((a) => a.id !== meId).map((a) => ({ key: a.id, label: a.full_name.split(' ')[0] })),
  ]
  const scopeLabel =
    who === 'all' ? 'כל מנהלי המערכת' : who === 'me' ? 'המשימות שלי' : `המשימות של ${admins.find((a) => a.id === who)?.full_name ?? ''}`
  const focusLive = focus ? (data?.missions.find((m) => m.id === focus.id) ?? focus) : null

  return (
    <div className={cx('space-y-4', shake && 'wr-shake')}>
      {data && data.defcon <= 2 && <div className="wr-vignette" data-level={data.defcon} aria-hidden />}
      {data && data.defcon === 1 && <div className="wr-scanlines" aria-hidden />}

      <PageHeader
        title={
          <span className="inline-flex items-center gap-2">
            <Siren size={ICON.xl} strokeWidth={STROKE} className={cx(data && data.defcon <= 2 ? 'text-error' : 'text-ink-tertiary')} />
            משימות ניהול
          </span>
        }
        subtitle="המשימות של מנהלי המערכת. יעד שעובר — מאדים. משימה שנסגרת בזמן — שווה נקודות."
        actions={
          <>
            <SegmentedControl items={whoItems} value={whoItems.some((w) => w.key === who) ? who : 'me'} onChange={setWho} />
            <IconButton label={muted ? 'הפעלת צלילים' : 'השתקה'} onClick={toggleMute}>
              {muted ? <VolumeX size={ICON.md} strokeWidth={STROKE} /> : <Volume2 size={ICON.md} strokeWidth={STROKE} />}
            </IconButton>
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
          <WarHeader board={data} stats={stats.data} debt={debt} scope={scopeLabel} />

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
              title="השולחן נקי. לך לשתות קפה. ☕"
              description="אין אף משימה פתוחה. כשתהיה — היא תופיע כאן עם שעון."
              action={
                <Button variant="primary" onClick={() => setEditing({ mission: null, seed: { ownerId: owner ?? meId } })}>
                  <Plus size={ICON.sm} /> משימה ראשונה
                </Button>
              }
            />
          ) : (
            <>
              {openCount === 0 && (
                <div className="wr-aurora flex items-center gap-3 rounded-xl border border-success-border p-4">
                  <Trophy size={ICON.hero} className="text-success" />
                  <div>
                    <p className="type-title text-success-text">Inbox Zero. אין אף משימה פתוחה.</p>
                    <p className="type-caption text-ink-tertiary">זה המצב. תשמור עליו.</p>
                  </div>
                </div>
              )}
              <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
                {LANES.filter((l) => l.key !== 'done').map((lane) => {
                  const items = lanes[lane.key]
                  if (lane.key === 'overdue' && !items.length) return null
                  return (
                    <section
                      key={lane.key}
                      className={cx(
                        'flex min-h-24 flex-col gap-2 rounded-2xl border p-2.5',
                        lane.key === 'overdue'
                          ? 'border-error-border bg-[color-mix(in_srgb,var(--vl-error)_6%,var(--vl-canvas))]'
                          : 'border-line-subtle bg-subtle',
                      )}
                    >
                      <header className="flex items-center justify-between px-1">
                        <h2 className={cx('type-subtitle font-bold', LANE_TONE[lane.key])}>
                          {lane.key === 'overdue' && '⛔ '}
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
                <section className="rounded-2xl border border-success-border bg-success-subtle/40 p-2.5">
                  <button
                    type="button"
                    className="flex w-full items-center justify-between px-1 type-subtitle font-bold text-success-text"
                    onClick={() => setShowDone((v) => !v)}
                    aria-expanded={showDone}
                  >
                    <span>✓ בוצעו ב-7 הימים האחרונים</span>
                    <span className="tabular">
                      {lanes.done.length} · +{lanes.done.reduce((s, m) => s + m.points, 0)} XP {showDone ? '▴' : '▾'}
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

      <Modal open={!!levelUp} onClose={() => setLevelUp(null)} title="דרגה חדשה">
        <div className="wr-levelup flex flex-col items-center gap-2 py-6 text-center">
          <span className="text-6xl" aria-hidden>
            🏆
          </span>
          <p className="type-overline">עלית דרגה</p>
          <p className="text-4xl font-black text-ink">{levelUp}</p>
          <p className="type-body text-ink-secondary">ככה עושים את זה. המשך באותו קצב.</p>
          <Button variant="primary" className="mt-3" onClick={() => setLevelUp(null)}>
            יאללה, הבאה
          </Button>
        </div>
      </Modal>

      {dialog}
    </div>
  )
}
