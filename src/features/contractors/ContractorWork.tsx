/**
 * הלו״ז ולוח השנה של קבלן — המשימות שהוקצו לו, ושיבוץ העובדים שלו אליהן.
 *
 * עד כאן היה לקבלן מסך אחד: רשימה שטוחה של כל המשימות בסדר יורד, בלי ניווט
 * בזמן ובלי שום תצוגה של "מה יש לי השבוע". מנהל קבלן שנכנס לפורטל כדי לשבץ
 * צוות לשבוע הבא היה צריך לגלול אחורה דרך כל ההיסטוריה כדי להגיע אליו.
 *
 * שתי התצוגות כאן חולקות שאילתה אחת ורכיב שיבוץ אחד, ונבדלות רק בצורה: הלו״ז
 * מקבץ לפי יום ורץ אנכית, לוח השנה פורש חודש. שתיהן מקבלות `contractorId`
 * מבחוץ ולכן משרתות גם את הפורטל של הקבלן וגם את כרטיס הקבלן אצל המנהל —
 * ההבדל היחיד ביניהם הוא איזה מפתח מתיר לשבץ, וזה נכנס כ-`canAssign`.
 *
 * הקריאה היא ל-work_board_view, אותו נתיב שהלוח של המשרד קורא. RLS היא
 * שתוחמת לקבלן, ולכן אין כאן שום סינון שמתחזה להרשאה.
 */
import { useMemo, useRef, useState } from 'react'
import FullCalendar from '@fullcalendar/react'
import dayGridPlugin from '@fullcalendar/daygrid'
import heLocale from '@fullcalendar/core/locales/he'
import type { DatesSetArg, EventContentArg } from '@fullcalendar/core'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { addMonths, endOfMonth, startOfMonth } from 'date-fns'
import { ChevronLeft, ChevronRight, Clock, ICON, MapPin, STROKE, Users } from '../../components/ui/icons'
import {
  Button,
  Card,
  CardBody,
  CardHeader,
  Drawer,
  EmptyState,
  ErrorState,
  IconButton,
  MultiSelect,
  Skeleton,
  SkeletonList,
  StatusPill,
  Tooltip,
  cx,
  relativeDayLabel,
  useToast,
} from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { errorMessage } from '../../lib/errors'
import { useContractorWorkers } from '../../lib/queries'
import { fmtDate, fmtMoney, fmtTime, toISODate } from '../../lib/dates'
import { shortAddress } from '../../lib/address'
import { HIGHLIGHT_CLASS, useDeepLinkHighlight } from '../../lib/deepLink'
import type { WorkBoardRow } from '../../types/domain'

interface ContractorTerm {
  task_id: string
  price: number
  paid_at: string | null
  paid_amount: number | null
}

/* ===== data ============================================================== */

/**
 * המשימות של הקבלן בטווח. `contractorId` נשלח כמסנן ולא כהגנה: ה-RLS כבר
 * תוחם משתמש קבלן לשלו, והמסנן הוא מה שמשרת את המנהל, שרואה את כולם.
 */
function useContractorTasks(contractorId: string | null, from: string, to: string) {
  return useQuery({
    queryKey: ['contractor_work', 'tasks', contractorId, from, to],
    enabled: !!contractorId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('work_board_view')
        .select('*')
        .eq('contractor_id', contractorId)
        .gte('task_date', from)
        .lte('task_date', to)
        /* אירוע שבוטל הוא עבודה שלא תתבצע, ולו״ז הוא רשימה של עבודה שכן —
           אותה החלטה בדיוק שלוח העבודה של המשרד מקבל (0037). */
        .eq('event_is_cancelled', false)
        .order('task_date')
        .order('onsite_start_time', { nullsFirst: false })
        .limit(500)
      if (error) throw error
      return data as WorkBoardRow[]
    },
  })
}

/**
 * התאריך הקרוב ביותר שיש בו עבודה, קדימה ואחורה.
 *
 * לו״ז שנפתח על החודש הנוכחי ומראה "אין משימות" אינו מבחין בין "אין לי
 * עבודה" לבין "העבודה שלי בחודש הבא", ושתי התשובות האלה שונות מאוד למי
 * שנכנס לשבץ צוות. שתי שאילתות של שדה אחד, ורק כשהחודש חוזר ריק.
 */
function useNearestWork(contractorId: string | null, enabled: boolean) {
  return useQuery({
    queryKey: ['contractor_work', 'nearest', contractorId],
    enabled: !!contractorId && enabled,
    queryFn: async () => {
      const today = toISODate(new Date())
      const [next, prev] = await Promise.all([
        supabase
          .from('work_board_view')
          .select('task_date')
          .eq('contractor_id', contractorId)
          .eq('event_is_cancelled', false)
          .gte('task_date', today)
          .order('task_date')
          .limit(1)
          .maybeSingle(),
        supabase
          .from('work_board_view')
          .select('task_date')
          .eq('contractor_id', contractorId)
          .eq('event_is_cancelled', false)
          .lt('task_date', today)
          .order('task_date', { ascending: false })
          .limit(1)
          .maybeSingle(),
      ])
      if (next.error) throw next.error
      if (prev.error) throw prev.error
      return {
        next: (next.data?.task_date as string | undefined) ?? null,
        prev: (prev.data?.task_date as string | undefined) ?? null,
      }
    },
  })
}

/** התנאים הכספיים. מי שאין לו את המפתח מקבל טבלה ריקה מ-RLS, לא שגיאה. */
function useContractorTerms(contractorId: string | null) {
  return useQuery({
    queryKey: ['contractor_work', 'terms', contractorId],
    enabled: !!contractorId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('task_contractor_terms')
        .select('task_id, price, paid_at, paid_amount')
        .eq('contractor_id', contractorId)
      if (error) throw error
      return data as ContractorTerm[]
    },
  })
}

/**
 * שיבוץ עובד למשימה, והסרתו.
 *
 * `onSettled` ולא `onSuccess`: כשלון RLS מחזיר שגיאה אחרי שהמצב האופטימי כבר
 * צויר, ורענון בשני המקרים הוא מה שמחזיר את המסך למה שבשרת באמת יש.
 */
function useWorkerToggle() {
  const qc = useQueryClient()
  const toast = useToast()
  return useMutation({
    mutationFn: async ({ taskId, workerId, on }: { taskId: string; workerId: string; on: boolean }) => {
      if (on) {
        const { error } = await supabase
          .from('task_contractor_workers')
          .insert({ task_id: taskId, contractor_worker_id: workerId })
        if (error) throw error
      } else {
        const { error } = await supabase
          .from('task_contractor_workers')
          .delete()
          .eq('task_id', taskId)
          .eq('contractor_worker_id', workerId)
        if (error) throw error
      }
    },
    onError: (e) => toast.error(errorMessage(e)),
    onSettled: () => {
      void qc.invalidateQueries({ queryKey: ['contractor_work'] })
      void qc.invalidateQueries({ queryKey: ['portal'] })
    },
  })
}

/* ===== month navigation ================================================== */

function useMonth(initial?: string) {
  const [anchor, setAnchor] = useState(() => (initial ? new Date(initial) : new Date()))
  const range = useMemo(
    () => ({ from: toISODate(startOfMonth(anchor)), to: toISODate(endOfMonth(anchor)) }),
    [anchor],
  )
  return {
    anchor,
    range,
    label: anchor.toLocaleDateString('he-IL', { month: 'long', year: 'numeric' }),
    step: (n: number) => setAnchor((d) => addMonths(d, n)),
    today: () => setAnchor(new Date()),
    goTo: (iso: string) => setAnchor(new Date(iso)),
  }
}

/** סרגל חודש אחד לשתי התצוגות, כדי שהניווט ייראה ויתנהג אותו דבר בשתיהן. */
function MonthBar({
  label,
  onPrev,
  onNext,
  onToday,
  count,
  busy,
}: {
  label: string
  onPrev: () => void
  onNext: () => void
  onToday: () => void
  count: number
  busy?: boolean
}) {
  return (
    <Card padded className="flex flex-wrap items-center gap-2">
      {/* RTL: "הקודם" יושב בצד ההתחלה ומצביע לכיוון ההתחלה */}
      <IconButton label="חודש קודם" size="sm" onClick={onPrev}>
        <ChevronRight size={ICON.md} strokeWidth={STROKE} />
      </IconButton>
      <IconButton label="חודש הבא" size="sm" onClick={onNext}>
        <ChevronLeft size={ICON.md} strokeWidth={STROKE} />
      </IconButton>
      <span className="type-title">{label}</span>
      {busy && <Skeleton className="h-4 w-10" />}
      <span className="type-caption text-ink-tertiary">
        {count} {count === 1 ? 'משימה' : 'משימות'}
      </span>
      <Button variant="ghost" size="sm" className="ms-auto" onClick={onToday}>
        היום
      </Button>
    </Card>
  )
}

/* ===== assignment ======================================================== */

/**
 * הבחירה עצמה. `worker_count` הוא מה שהמשרד ביקש, ולכן הוא מוצג כיעד ולא
 * נאכף כאן: קבלן ששולח אדם נוסף אינו טעות שהמסך אמור לחסום, והמניין הצבעוני
 * הוא מה שאומר אם הוא במקום.
 */
function WorkerPicker({
  task,
  contractorId,
  canAssign,
}: {
  task: WorkBoardRow
  contractorId: string
  canAssign: boolean
}) {
  const { data: roster = [], isLoading } = useContractorWorkers(contractorId)
  const toggle = useWorkerToggle()
  const chosen = (task.contractor_worker_list ?? []).map((w) => w.id)
  const target = task.worker_count || 0
  const full = target > 0 && chosen.length >= target

  return (
    <div>
      <div className="mb-1.5 flex items-center gap-2">
        <p className="flex items-center gap-1 type-caption font-semibold text-ink-secondary">
          <Users size={ICON.sm} strokeWidth={STROKE} aria-hidden />
          העובדים שלי למשימה
        </p>
        <span
          className={cx(
            'rounded-full px-1.5 py-0.5 type-caption font-bold tabular',
            full ? 'bg-success-subtle text-success-text' : 'bg-warning-subtle text-warning-text',
          )}
        >
          {chosen.length}/{target || '∞'}
        </span>
      </div>
      {isLoading ? (
        <Skeleton className="h-9 w-full" />
      ) : roster.length === 0 ? (
        /* בלי סגל אין את מי לשבץ, ורשימה נפתחת ריקה אינה אומרת את זה. */
        <p className="rounded-lg border border-dashed border-line px-3 py-2 type-caption text-ink-tertiary">
          עדיין אין עובדים ברשימת הסגל שלך. הוסיפו אותם בלשונית "העובדים שלי", ואז אפשר לשבץ אותם כאן.
        </p>
      ) : (
        <MultiSelect
          options={roster.map((w) => ({ id: w.id, label: w.full_name }))}
          values={chosen}
          onToggle={(id) =>
            toggle.mutate({ taskId: task.id, workerId: id, on: !chosen.includes(id) })
          }
          placeholder="בחירת עובדים מהסגל שלך..."
          disabled={!canAssign}
        />
      )}
      {!canAssign && (
        <p className="mt-1 type-caption text-ink-tertiary">אין לך הרשאה לשנות שיבוץ במשימה זו.</p>
      )}
    </div>
  )
}

function Fact({
  icon,
  label,
  value,
  full,
  ltr,
}: {
  icon: React.ReactNode
  label: string
  value: string
  full?: string
  ltr?: boolean
}) {
  const bubble = full ?? value
  return (
    <div className="min-w-0">
      <dt className="flex items-center gap-1 type-caption text-ink-tertiary">
        <span className="shrink-0" aria-hidden>
          {icon}
        </span>
        {label}
      </dt>
      <Tooltip content={bubble !== value || bubble.length > 24 ? bubble : ''} openOnClick>
        <dd className={cx('mt-0.5 truncate type-body font-medium', ltr && 'tabular')} dir={ltr ? 'ltr' : undefined}>
          {value}
        </dd>
      </Tooltip>
    </div>
  )
}

/** כרטיס משימה מלא — אותו כרטיס בלו״ז ובמגירה של לוח השנה. */
export function ContractorTaskCard({
  task,
  term,
  contractorId,
  canAssign,
  highlighted,
  bare,
}: {
  task: WorkBoardRow
  term?: ContractorTerm
  contractorId: string
  canAssign: boolean
  highlighted?: boolean
  /** בתוך מגירה אין צורך בעוד מסגרת סביב המסגרת */
  bare?: boolean
}) {
  const ref = useDeepLinkHighlight(highlighted ? task.id : null)
  const dayLabel = relativeDayLabel(task.task_date)

  const body = (
    <>
      <dl className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        <Fact
          icon={<MapPin size={ICON.sm} strokeWidth={STROKE} />}
          label="מיקום"
          value={shortAddress(task.location_text) || '—'}
          full={task.location_text || undefined}
        />
        <Fact
          icon={<Clock size={ICON.sm} strokeWidth={STROKE} />}
          label="שעה בשטח"
          value={fmtTime(task.onsite_start_time) || '—'}
          ltr
        />
        <Fact
          icon={<Users size={ICON.sm} strokeWidth={STROKE} />}
          label="כמות עובדים"
          value={String(task.worker_count || '—')}
        />
      </dl>
      <WorkerPicker task={task} contractorId={contractorId} canAssign={canAssign} />
    </>
  )

  const title = (
    <span className="flex flex-wrap items-center gap-2">
      {task.title || task.task_type_name}
      <StatusPill color={task.status_color}>{task.status_name}</StatusPill>
      {term && (
        <StatusPill color={term.paid_at ? '#16a34a' : '#f59e0b'}>
          {term.paid_at ? `שולם ${fmtMoney(term.paid_amount ?? term.price)}` : `צפוי ${fmtMoney(term.price)}`}
        </StatusPill>
      )}
    </span>
  )

  if (bare)
    return (
      <div className="space-y-3">
        <div>
          <p className="type-title">{title}</p>
          <p className="type-caption text-ink-tertiary">
            <span className="tabular">{fmtDate(task.task_date)}</span>
            {task.customer_name && <> · {task.customer_name}</>}
          </p>
        </div>
        {body}
      </div>
    )

  return (
    /* ה-ref על עטיפה ולא על Card — Card אינו מצהיר על ref בטיפוסים */
    <div ref={ref as React.Ref<HTMLDivElement>} className={highlighted ? HIGHLIGHT_CLASS : undefined}>
      <Card>
        <CardHeader
          title={title}
          subtitle={
            <span className="flex flex-wrap items-center gap-x-2">
              <span className="tabular">{fmtDate(task.task_date)}</span>
              {dayLabel && <span className="font-semibold text-primary-text">· {dayLabel}</span>}
              {task.customer_name && <span>· {task.customer_name}</span>}
            </span>
          }
        />
        <CardBody className="space-y-3">{body}</CardBody>
      </Card>
    </div>
  )
}

/* ===== the schedule ====================================================== */

export function ContractorSchedule({
  contractorId,
  canAssign,
  highlightId,
  initialMonth,
}: {
  contractorId: string
  canAssign: boolean
  highlightId?: string | null
  /** התאריך שאליו הגיעו מקישור התראה — פותח את הלו״ז בחודש הנכון */
  initialMonth?: string | null
}) {
  const month = useMonth(initialMonth ?? undefined)
  const { data: tasks = [], isLoading, isFetching, error, refetch } =
    useContractorTasks(contractorId, month.range.from, month.range.to)
  const { data: terms = [] } = useContractorTerms(contractorId)

  /* הקיבוץ לימים נשען על כך שהשאילתה כבר החזירה מסודר לפי תאריך ואז שעה,
     ולכן הוא שומר על הסדר במקום להטיל אותו מחדש. */
  const days = useMemo(() => {
    const out: { date: string; rows: WorkBoardRow[] }[] = []
    for (const t of tasks) {
      const last = out[out.length - 1]
      if (last && last.date === t.task_date) last.rows.push(t)
      else out.push({ date: t.task_date, rows: [t] })
    }
    return out
  }, [tasks])

  return (
    <div className="space-y-3">
      <MonthBar
        label={month.label}
        onPrev={() => month.step(-1)}
        onNext={() => month.step(1)}
        onToday={month.today}
        count={tasks.length}
        busy={isFetching && !isLoading}
      />

      {error != null ? (
        <ErrorState error={error} onRetry={() => void refetch()} />
      ) : isLoading ? (
        <SkeletonList rows={4} />
      ) : days.length === 0 ? (
        <EmptyMonth onJump={month.goTo} contractorId={contractorId} />
      ) : (
        days.map((d) => (
          <section key={d.date} className="space-y-2">
            <h3 className="sticky top-14 z-10 -mx-1 bg-canvas/90 px-1 py-1 backdrop-blur-sm">
              <span className="type-title tabular">{fmtDate(d.date)}</span>
              <span className="ms-2 type-caption text-ink-tertiary">
                {new Date(d.date).toLocaleDateString('he-IL', { weekday: 'long' })}
                {relativeDayLabel(d.date) ? ` · ${relativeDayLabel(d.date)}` : ''}
              </span>
            </h3>
            {d.rows.map((t) => (
              <ContractorTaskCard
                key={t.id}
                task={t}
                term={terms.find((x) => x.task_id === t.id)}
                contractorId={contractorId}
                canAssign={canAssign}
                highlighted={t.id === highlightId}
              />
            ))}
          </section>
        ))
      )}
    </div>
  )
}

/**
 * חודש ריק, ובו התשובה לשאלה הבאה: "אז מתי כן". בלי זה, קבלן שכל העבודה שלו
 * בחודש הבא היה רואה מסך ריק בדיוק כמו קבלן שאין לו עבודה בכלל.
 */
function EmptyMonth({ contractorId, onJump }: { contractorId: string; onJump: (iso: string) => void }) {
  const { data } = useNearestWork(contractorId, true)
  const jump = data?.next ?? data?.prev ?? null

  return (
    <Card>
      <EmptyState
        art="calendar"
        title="אין משימות בחודש הזה"
        description={
          jump
            ? `${data?.next ? 'המשימה הקרובה שלך' : 'המשימה האחרונה שלך'} בתאריך ${fmtDate(jump)}`
            : 'משימות שיואצלו אליך יופיעו כאן, ותוכל לשבץ אליהן את העובדים שלך'
        }
        action={
          jump ? (
            <Button variant="secondary" size="sm" onClick={() => onJump(jump)}>
              מעבר לחודש הזה
            </Button>
          ) : undefined
        }
      />
    </Card>
  )
}

/* ===== the calendar ====================================================== */

export function ContractorCalendar({
  contractorId,
  canAssign,
}: {
  contractorId: string
  canAssign: boolean
}) {
  const calRef = useRef<FullCalendar>(null)
  const [open, setOpen] = useState<WorkBoardRow | null>(null)
  /* הטווח נגזר ממה שהלוח באמת מצייר ולא מהחודש הקלנדרי: תצוגת חודש מציגה
     גם ימים מהחודש שלפני ואחרי, ומשימה שיושבת עליהם הייתה נעדרת מהתא. */
  const [range, setRange] = useState(() => ({
    from: toISODate(startOfMonth(new Date())),
    to: toISODate(endOfMonth(new Date())),
  }))
  const [title, setTitle] = useState('')

  const { data: tasks = [], isLoading, error, refetch } = useContractorTasks(contractorId, range.from, range.to)
  const { data: terms = [] } = useContractorTerms(contractorId)

  const events = useMemo(
    () =>
      tasks.map((t) => ({
        id: t.id,
        title: t.title || t.task_type_name,
        start: t.task_date,
        allDay: true,
        extendedProps: { task: t },
      })),
    [tasks],
  )

  /* המשימה במגירה נשלפת מחדש מהרשימה בכל ציור, ולא נשמרת כעותק: אחרי שיבוץ
     העותק היה מציג את רשימת העובדים שלפניו. */
  const current = open ? (tasks.find((t) => t.id === open.id) ?? open) : null

  return (
    <div className="space-y-3">
      <MonthBar
        label={title}
        onPrev={() => calRef.current?.getApi().prev()}
        onNext={() => calRef.current?.getApi().next()}
        onToday={() => calRef.current?.getApi().today()}
        count={tasks.length}
        busy={isLoading}
      />

      {error != null && tasks.length === 0 && <ErrorState error={error} onRetry={() => void refetch()} />}

      {/* ה-chrome של FullCalendar כבר מנוטרל גלובלית ב-index.css, ולכן התא
          מצויר כאן ב-eventContent לבדו ואין צורך בסגנון משלו למסך הזה. */}
      <Card padded>
        <FullCalendar
          ref={calRef}
          plugins={[dayGridPlugin]}
          initialView="dayGridMonth"
          headerToolbar={false}
          direction="rtl"
          locale={heLocale}
          height="auto"
          firstDay={0}
          dayMaxEventRows={4}
          events={events}
          eventContent={renderTask}
          eventClick={(info) => setOpen(info.event.extendedProps.task as WorkBoardRow)}
          datesSet={(arg: DatesSetArg) => {
            setTitle(arg.view.title)
            const from = toISODate(arg.start)
            const to = toISODate(new Date(arg.end.getTime() - 86_400_000))
            setRange((r) => (r.from === from && r.to === to ? r : { from, to }))
          }}
        />
      </Card>

      <Drawer
        open={!!current}
        onClose={() => setOpen(null)}
        title={current ? current.title || current.task_type_name : ''}
        description={current ? fmtDate(current.task_date) : undefined}
      >
        {current && (
          <ContractorTaskCard
            bare
            task={current}
            term={terms.find((x) => x.task_id === current.id)}
            contractorId={contractorId}
            canAssign={canAssign}
          />
        )}
      </Drawer>
    </div>
  )
}

/**
 * תא בלוח: שעה, שם, ומניין השיבוץ. המניין הוא הסיבה שהקבלן פתח את המסך —
 * "לאילו ימים עוד לא שלחתי אנשים" — ולכן הוא בתא עצמו ולא רק במגירה.
 */
function renderTask(arg: EventContentArg) {
  const t = arg.event.extendedProps.task as WorkBoardRow
  const chosen = (t.contractor_worker_list ?? []).length
  const target = t.worker_count || 0
  const full = target > 0 && chosen >= target
  return (
    <div
      className="flex w-full min-w-0 items-center gap-1 rounded px-1 py-0.5 type-caption"
      style={{ background: `${t.customer_color ?? t.status_color}22` }}
    >
      {t.onsite_start_time && (
        <span className="shrink-0 tabular opacity-70" dir="ltr">
          {fmtTime(t.onsite_start_time)}
        </span>
      )}
      <span className="truncate">{t.title || t.task_type_name}</span>
      <span
        className={cx(
          'ms-auto shrink-0 rounded-full px-1 font-bold tabular',
          full ? 'bg-success-subtle text-success-text' : 'bg-warning-subtle text-warning-text',
        )}
      >
        {chosen}/{target || '∞'}
      </span>
    </div>
  )
}
